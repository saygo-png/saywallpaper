{
  niceHaskell,
  sayland,
  ...
}:
niceHaskell.mkPackage {
  flags = niceHaskell.mkFlags {doCheck = false;};
  packageRoot = ./.;
  cabalName = "saywallpaper";
  compiler = "ghc912";
  developPackageArgs.overrides = _: _: {
    sayland = sayland;
  };
}
