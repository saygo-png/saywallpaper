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
    niceHaskell,
    saylandSrc,
    treefmt-nix,
    self,
    ...
  }: let
    pkgsFor = nixpkgs.lib.genAttrs (import systems) (system: import nixpkgs {inherit system;});
    eachSystem = f: nixpkgs.lib.genAttrs (import systems) (system: f system pkgsFor.${system});
  in {
    packages = eachSystem (system: pkgs: let
      saywallpaper = pkgs.callPackage ./package.nix {
        niceHaskell = niceHaskell.outputs.niceHaskell.${system};
        inherit saylandSrc;
      };
    in {
      inherit saywallpaper;
      default = saywallpaper;
    });

    formatter = eachSystem (_system: pkgs: (treefmt-nix.lib.evalModule pkgs ./treefmt.nix).config.build.wrapper);

    devShells = eachSystem (system: pkgs: let
      generate-cabal2nix = pkgs.writeShellApplication {
        name = "generate-cabal2nix";
        runtimeInputs = [pkgs.cabal2nix];
        text = "cabal2nix . > cabal.nix";
      };
    in {
      default = pkgs.mkShell {
        inputsFrom = [self.packages.${system}.saywallpaper.env];
        packages = [
          self.formatter.${system}
          pkgs.cabal-install
          pkgs.haskell-language-server
          generate-cabal2nix
        ];
        shellHook = ''
          echo "generate-cabal2nix regenerate cabal.nix after changing saywallpaper.cabal"
        '';
      };
    });
  };
}
