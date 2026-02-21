{
  description = "Clanarchy Standard v1";

  inputs = {
    # Clan core (25.11)
    clan-core.url = "https://git.clan.lol/clan/clan-core/archive/main.tar.gz";
    nixpkgs.follows = "clan-core/nixpkgs";

    # flake-parts
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "clan-core/nixpkgs";
    };

    # Extras
    impermanence.url = "github:nix-community/impermanence";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, clan-core, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {

      systems = [ "x86_64-linux" ];

      # flake-parts modules
      imports = [
        clan-core.flakeModules.default
        ./clan.nix
      ];

      perSystem = { pkgs, system, ... }: {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            # Clan docs recommend exposing the CLI via devShell
            clan-core.packages.${system}.clan-cli
            git
            openssh
          ];
        };
      };

      # Machine composition (explicit, standard)
      clan.machines.miralda = {
        imports = [
          inputs.impermanence.nixosModules.impermanence
          inputs.stylix.nixosModules.stylix
          inputs.home-manager.nixosModules.home-manager

          ./machines/miralda/configuration.nix
          ./machines/miralda/disko.nix
          ./machines/miralda/impermanence.nix
          ./machines/miralda/stylix.nix
          ./machines/miralda/users/admin.nix
          ./machines/miralda/secrets/admin.nix
        ];
      };
    };
}
