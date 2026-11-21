{
  niceHaskell,
  saylandSrc,
}:
niceHaskell.mkPackageNoIFD {
  src = ./.;
  cabal2nix = ./cabal.nix;
  developPackageArgs.overrides = _: _: {
    sayland = niceHaskell.mkPackageNoIFD {
      src = saylandSrc;
      cabal2nix = "${saylandSrc}/cabal.nix";
    };
  };
}
