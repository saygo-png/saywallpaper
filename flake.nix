{
  inputs = {
    treefmt-nix.url = "github:numtide/treefmt-nix";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    niceHaskell = {
      url = "github:saygo-png/nice-nixpkgs-haskell";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        treefmt-nix.follows = "treefmt-nix";
      };
    };
    sayland = {
      url = "github:saygo-png/sayland/768dee7f0947dc9c5b54b49a1bdb94b68cc61f2f";
      flake = false;
      inputs = {
        treefmt-nix.follows = "treefmt-nix";
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        niceHaskell.follows = "niceHaskell";
        git-hooks.follows = "";
      };
    };
    systems = {
      url = "path:./systems.nix";
      flake = false;
    };
  };

  outputs = {
    nixpkgs,
    systems,
    sayland,
    niceHaskell,
    treefmt-nix,
    self,
    ...
  }: let
    pkgsFor = nixpkgs.lib.genAttrs (import systems) (system: import nixpkgs {inherit system;});
    eachSystem = f: nixpkgs.lib.genAttrs (import systems) (system: f system pkgsFor.${system});
  in {
    packages = eachSystem (system: pkgs: let
      program = pkgs.callPackage ./package.nix {
        niceHaskell = niceHaskell.outputs.niceHaskell.${system};
        saylandSrc = sayland;
      };
    in {
      "saywallpaper" = program;
      default = program;
    });

    formatter = eachSystem (_system: pkgs: (treefmt-nix.lib.evalModule pkgs ./treefmt.nix).config.build.wrapper);

    devShells = eachSystem (system: pkgs: {
      default = pkgs.mkShell {
        packages = let
          hPkgs = pkgs.haskellPackages;
        in [
          self.formatter.${system}
          pkgs.cabal-install
          hPkgs.ghc
          hPkgs.haskell-language-server
        ];
      };
    });
  };
}
