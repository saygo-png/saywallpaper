module Config (colorChannels, bufferWidth, bufferHeight, poolName, colorFormat) where

import Relude
import Sayland

bufferWidth :: Int32
bufferWidth = 1920

bufferHeight :: Int32
bufferHeight = 1080

poolName :: String
poolName = "saywallpaper-shared-pool"

colorFormat :: Enum_wl_shm_format
colorFormat = Enum_wl_shm_format_argb8888

colorChannels :: Int32
colorChannels = 4
