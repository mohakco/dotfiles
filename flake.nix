{
  description = "mohak's machines";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Determinate Nix is installed on the Mac; this module makes nix-darwin defer to it.
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-darwin,
      ...
    }@inputs:
    let
      user = "mohak";
      forAllSystems = nixpkgs.lib.genAttrs [
        "aarch64-darwin"
        "x86_64-linux"
      ];
      darwinPkgs = nixpkgs.legacyPackages.aarch64-darwin;
    in
    {
      darwinConfigurations.odysseus = nix-darwin.lib.darwinSystem {
        specialArgs = { inherit inputs user; };
        modules = [ ./hosts/odysseus ];
      };

      # `nix run .#odysseus` switches the Mac; append `-- --rollback` to go back one generation.
      apps.aarch64-darwin.odysseus = {
        type = "app";
        program = toString (
          darwinPkgs.writeShellScript "odysseus" ''
            exec sudo ${nix-darwin.packages.aarch64-darwin.darwin-rebuild}/bin/darwin-rebuild \
              switch --flake ${self}#odysseus "$@"
          ''
        );
      };

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
