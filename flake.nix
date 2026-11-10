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
    saylandSrc = {
      url = "github:saygo-png/sayland";
      flake = false;
    };
    systems = {
      url = "path:./systems.nix";
      flake = false;
    };
  };

  outputs = {
    nixpkgs,
    systems,
    saylandSrc,
    treefmt-nix,
    self,
    ...
  } @ inputs: let
    pkgsFor = nixpkgs.lib.genAttrs (import systems) (system: import nixpkgs {inherit system;});
    eachSystem = f: nixpkgs.lib.genAttrs (import systems) (system: f system pkgsFor.${system});
  in {
    packages = eachSystem (system: pkgs: let
      niceHaskell = inputs.niceHaskell.outputs.niceHaskell.${system};
    in rec {
      sayland = niceHaskell.mkPackage {
        src = saylandSrc;
      };

      saywallpaper = pkgs.callPackage ./package.nix {
        inherit niceHaskell;
        inherit sayland;
      };

      default = saywallpaper;
    });

    formatter = eachSystem (_system: pkgs: (treefmt-nix.lib.evalModule pkgs ./treefmt.nix).config.build.wrapper);

    devShells = eachSystem (system: pkgs: rec {
      default = haskellShell;
      haskellShell = pkgs.mkShell {
        inputsFrom = [self.packages.${system}.saywallpaper.env];
        packages = [
          self.formatter.${system}
          pkgs.haskellPackages.cabal-install
          pkgs.haskellPackages.haskell-language-server
        ];
        buildInputs = [pkgs.zlib];
      };
    });
  };
}
