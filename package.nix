{
  niceHaskell,
  sayland,
  shell ? false,
  ...
}:
niceHaskell.mkPackage {
  flags = niceHaskell.mkFlags {
    doCheck = false;
    returnShellEnv = shell;
  };
  packageRoot = ./.;
  cabalName = "saywallpaper";
  developPackageArgs.overrides = _: _: {
    inherit sayland;
  };
}
