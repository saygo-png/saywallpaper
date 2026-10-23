{
  niceHaskell,
  saylandSrc,
  ...
}: let
  sayland = niceHaskell.mkPackage {
    flags = niceHaskell.mkFlags {
      doCheck = false;
      doHaddock = false;
    };
    packageRoot = saylandSrc;
    cabalName = "sayland";
  };
in
  niceHaskell.mkPackage {
    flags = niceHaskell.mkFlags {doCheck = false;};
    packageRoot = ./.;
    cabalName = "saywallpaper";
    developPackageArgs.overrides = _: _: {
      inherit sayland;
    };
  }
