{-# LANGUAGE QuasiQuotes #-}

{- HLINT ignore "Use camelCase" -}

module Main (main) where

import Config
import Control.Concurrent
import Control.Concurrent.STM (retry, stateTVar)
import Control.Exception
import Data.ByteString qualified as BS
import Data.Map qualified as Map
import Data.Set qualified as Set
import Relude
import Sayland
import System.Posix

c :: forall a b. (Coercible a b) => a -> b
c = coerce

table :: ProtocolTable
table = waylandTable <> wlr_layer_shell_unstable_v1Table

data LayerPhase
  = Idle
  | AwaitingConfigure Zwlr_layer_surface_v1
  | LayerConfigured Zwlr_layer_surface_v1

phaseSurface :: LayerPhase -> Maybe Zwlr_layer_surface_v1
phaseSurface Idle = Nothing
phaseSurface (AwaitingConfigure s) = Just s
phaseSurface (LayerConfigured s) = Just s

-- | Shared state between threads
data SurfaceStates = SurfaceStates
  { outputNames :: Set GlobalName
  , layerPhase :: LayerPhase
  , pendingBuffer :: Maybe Wl_buffer
  , bufferAttached :: Bool
  }

hasAnyOutput :: SurfaceStates -> Bool
hasAnyOutput = not . Set.null . (.outputNames)

main :: IO ()
main = do
  wallpaperPath <-
    getArgs >>= \case
      "-i" : p : _ -> pure p
      _ -> putStrLn "Provide a path to the image as an argument using \"-i <path>\"" >> exitFailure
  withWaylandClient table (program wallpaperPath)

program :: FilePath -> Wayland Client ()
program wallpaperPath = do
  ClientEnv env <- ask
  stateVar <- newTVarIO $ SurfaceStates{outputNames = Set.empty, layerPhase = Idle, pendingBuffer = Nothing, bufferAttached = False}

  -- Runs an STM transition against the shared state, then performs
  -- whatever side effect that transition decided on.
  let transact :: State SurfaceStates (Wayland Client ()) -> Wayland Client ()
      transact action = join . atomically $ stateTVar stateVar (runState action)

  wlDisplay <- getWlDisplay
  registry <- newObject wlDisplay Request_wl_display_get_registry

  putStrLn "Binding to required interfaces..."

  roundtrip

  wl_shm <- bindToInterface registry
  wl_compositor <- bindToInterface registry
  zwlr_layer_shell_V1 <- bindToInterface registry

  surface <- newObject wl_compositor $ \i -> Request_wl_compositor_create_surface i

  -- wl_output is not bound as its not implemented in saywayland.

  let onEventDo :: (Message e) => (e -> Wayland Client ()) -> Wayland Client ()
      onEventDo x = modifyIORef env.eventHandlers $ (:) $ EventHandler (const x)

  onEventDo $ \case
    Event_wl_registry_global name iface _ | iface == getInterfaceName (Proxy @Wl_output) ->
      transact $ do
        modify $ \s -> s{outputNames = Set.insert (c name) s.outputNames}
        pure pass
    Event_wl_registry_global_remove name -> transact $ do
      modify $ \s -> s{outputNames = Set.delete (c name) s.outputNames}
      pure pass
    _ -> pass

  onEventDo $ \case
    Event_zwlr_layer_surface_v1_configure serial _ _ -> transact $ do
      gets (.layerPhase) >>= \case
        AwaitingConfigure surf -> do
          modify' $ \s -> s{layerPhase = LayerConfigured surf}
          pure $ sendMsg surf (Request_zwlr_layer_surface_v1_ack_configure serial)
        _ ->
          pure pass
    Event_zwlr_layer_surface_v1_closed -> transact $ do
      oldPhase <- gets (.layerPhase)
      modify' $ \s -> s{layerPhase = Idle, bufferAttached = False}
      pure . forM_ (phaseSurface oldPhase) $ \surf ->
        sendMsg surf Request_zwlr_layer_surface_v1_destroy

  initialGlobals <- readIORef env.globals

  let onlyOutputs = Map.filter $ fst >>> (== getInterfaceName (Proxy @Wl_output))
      outputsToSet x = Set.fromList . map fst $ Map.toList x
      toOutputsSet x = onlyOutputs x & outputsToSet

  putStrLn $ "[startup] globals entries seen: " <> show (length initialGlobals)
  putStrLn $ "[startup] globals contents: " <> show initialGlobals
  putStrLn $ "[startup] output globals: " <> show (onlyOutputs initialGlobals)
  atomically $ modifyTVar' stateVar $ \s -> s{outputNames = s.outputNames <> toOutputsSet initialGlobals}

  let reconcileStep :: Wayland Client ()
      reconcileStep = do
        action <- atomically $ do
          s <- readTVar stateVar
          case (hasAnyOutput s, s.layerPhase, s.pendingBuffer, s.bufferAttached) of
            (True, Idle, _, _) -> pure createLayerSurface
            (_, LayerConfigured _, Just buf, False) -> do
              writeTVar stateVar s{bufferAttached = True}
              pure (attachBuffer buf)
            _ -> retry
        putStrLn "[reconciler] woke up with an action, running it"
        action
        where
          createLayerSurface :: Wayland Client ()
          createLayerSurface = do
            zwlrLayerSurface <- newObject zwlr_layer_shell_V1 $ \i -> Request_zwlr_layer_shell_v1_get_layer_surface i surface.wlid Nothing Enum_zwlr_layer_shell_v1_layer_background [wl|wallpaper|]

            sendMsg zwlrLayerSurface $ Request_zwlr_layer_surface_v1_set_size (fromIntegral bufferWidth) (fromIntegral bufferHeight)
            sendMsg zwlrLayerSurface $ Request_zwlr_layer_surface_v1_set_exclusive_zone $ -1
            sendMsg surface Request_wl_surface_commit
            atomically $ modifyTVar' stateVar $ \s -> s{layerPhase = AwaitingConfigure zwlrLayerSurface}

          attachBuffer :: Wl_buffer -> Wayland Client ()
          attachBuffer buf = do
            sendMsg surface $ Request_wl_surface_attach (Just buf.wlid) 0 0
            sendMsg surface Request_wl_surface_commit

  putStrLn "[startup] forking reconciler"
  liftIO . void . forkIO . runReaderT (putStrLn "[reconciler] thread started" >> forever reconcileStep) $ ClientEnv env

  let makeSharedMemoryObject = shmOpen poolName (ShmOpenFlags True True False True) (foldl' unionFileModes ownerWriteMode [ownerReadMode])
      removeSharedMemoryObject _ = shmUnlink poolName
      useSharedMemoryObject fileDescriptor =
        usingReaderT (ClientEnv env) $ do
          let frameSize = bufferWidth * bufferHeight * colorChannels
          let poolSize = frameSize
          liftIO . setFdSize fileDescriptor $ fromIntegral poolSize

          wl_shm_pool <- newObject wl_shm $ \i -> Request_wl_shm_create_pool i (c fileDescriptor) (c frameSize)
          wl_buffer <- newObject wl_shm_pool $ \i -> Request_wl_shm_pool_create_buffer i 0 (c bufferWidth) (c bufferHeight) (c $ bufferWidth * colorChannels) colorFormat

          fileHandle <- liftIO $ fdToHandle fileDescriptor
          liftIO $ BS.hPut fileHandle =<< BS.readFile wallpaperPath

          atomically $ modifyTVar' stateVar $ \s -> s{pendingBuffer = Just wl_buffer}

          untilDisconnected

  liftIO . void $ bracket makeSharedMemoryObject removeSharedMemoryObject useSharedMemoryObject
