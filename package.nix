{
  niceHaskell,
  sayland,
  ...
}:
niceHaskell.mkPackageNoIFD {
  src = ./.;
  cabal2nix = ./cabal.nix;
  developPackageArgs.overrides = _: _: {inherit sayland;};
}
