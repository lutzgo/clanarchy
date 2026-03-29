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

    # niri-flake — provides the Home Manager module for programs.niri.settings
    niri-flake = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Unstable — required for Noctalia/Quickshell (intentionally NOT following clan-core/nixpkgs)
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    quickshell = {
      url = "git+https://git.outfoxxed.me/quickshell/quickshell";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
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
            nixos-rebuild
          ];

          # Fast deploy: builds locally, pushes result, switches remotely.
          # Avoids clan's full inventory evaluation — use for quick iteration.
          # Usage: deploy [boot|switch]   (default: switch)
          #
          # Use "clan machines update miralda" when you need secrets/vars to be
          # re-evaluated (e.g. after changing sops or clan vars config).
          shellHook = ''
            deploy() {
              local action=''${1:-switch}
              nixos-rebuild "$action" \
                --flake .#miralda \
                --target-host root@miralda.goclan.org \
                --build-host localhost \
                --fast \
                -j auto \
                "''${@:2}"
            }
            export -f deploy
          '';
        };
      };

      # Machine composition (explicit, standard)
      clan.machines.miralda = {
        imports = [
          # Inject pkgs-unstable and inputs as module args (Option B — clan-core has no per-machine specialArgs)
          { _module.args = {
              pkgs-unstable = import inputs.nixpkgs-unstable {
                system = "x86_64-linux";
                config.allowUnfree = true;
              };
              inherit inputs;
            };
          }

          inputs.impermanence.nixosModules.impermanence
          inputs.stylix.nixosModules.stylix
          inputs.home-manager.nixosModules.home-manager

          ./machines/miralda/configuration.nix
          ./machines/miralda/disko.nix
          ./machines/miralda/impermanence.nix
          ./machines/miralda/stylix.nix
          ./machines/miralda/desktop.nix
          ./machines/miralda/noctalia.nix
          ./machines/miralda/yubikey.nix
          ./machines/miralda/users/admin.nix
          ./machines/miralda/users/lgo.nix
          ./machines/miralda/secrets/admin.nix
          ./machines/miralda/secrets/lgo.nix
        ];
      };
    };
}
