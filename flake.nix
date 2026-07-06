{
  description = "Clanarchy Standard v1";

  inputs = {
    # Clan core (26.05)
    clan-core.url = "https://git.clan.lol/clan/clan-core/archive/26.05.tar.gz";
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
      # Pin to pre-v5 revision (2026-05-26). Noctalia v5 (July 2026) rewrote the
      # HM module from typed options to freeform TOML; migrating our ~1150-line
      # noctalia-hm.nix is a multi-day project — track it separately from 26.05.
      url = "github:noctalia-dev/noctalia-shell/272cd91408b5ff6e329e6397eed042fe422069e7";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    quickshell = {
      url = "git+https://git.outfoxxed.me/quickshell/quickshell";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    zjstatus = {
      url = "github:dj95/zjstatus";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nur = {
      url = "github:nix-community/nur";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    govim = {
      url = "github:lutzgo/govim";
      # nvf expects nixpkgs-unstable; do not follow clan-core/nixpkgs
    };

    # nvf — pin to the same revision govim uses so the DAG lib is consistent
    nvf.follows = "govim/nvf";

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
            age-plugin-yubikey  # needed for sops re-encryption with YubiKey recipients
            sops                # needed for manual key rotation / recipient management

            # Docs
            python3               # needed for gendocs (gen-options.py)
            python3Packages.mkdocs-material
          ];

          # Fast deploy: builds locally, pushes result, switches remotely.
          # Avoids clan's full inventory evaluation — use for quick iteration.
          # Usage: deploy [boot|switch]   (default: switch)
          #
          # Use "clan machines update miralda" when you need secrets/vars to be
          # re-evaluated (e.g. after changing sops or clan vars config).
          shellHook = ''
            # age/SOPS identity — points to the keys.txt that contains both the
            # regular age key and the AGE-PLUGIN-YUBIKEY-1... identity stub.
            # Required for `clan machines update` and any direct `sops` invocation
            # that needs to decrypt secrets encrypted to the YubiKey recipient.
            # The file persists across reboots via impermanence (.config is listed
            # in the persisted paths).  First-time setup on a new machine:
            #   age-plugin-yubikey --identity >> ~/.config/sops/age/keys.txt
            export SOPS_AGE_KEY_FILE="''${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt"

            # Update gpg-agent's pinentry TTY to this shell's TTY.
            # gpg-agent caches the TTY from the session where it first started;
            # entering a new shell (nix develop, new terminal) changes the TTY
            # but the agent doesn't know — pinentry then tries the old TTY, fails
            # silently, and the agent refuses card-backed SSH signing operations.
            echo UPDATESTARTUPTTY | gpg-connect-agent > /dev/null 2>&1 || true

            deploy() {
              local action=''${1:-switch}
              nixos-rebuild "$action" \
                --flake .#miralda \
                --target-host root@miralda.goclan.org \
                --no-reexec \
                -j auto \
                "''${@:2}"
            }
            export -f deploy

            deploy-biene() {
              local action=''${1:-switch}
              local host=''${BIENE_HOST:-biene.local}
              nixos-rebuild "$action" \
                --flake .#biene \
                --target-host "root@$host" \
                --no-reexec \
                -j auto \
                "''${@:2}"
            }
            export -f deploy-biene

            deploy-ernst() {
              local action=''${1:-switch}
              local host=''${ERNST_HOST:-ernst.skynet.lan}
              nixos-rebuild "$action" \
                --flake .#ernst \
                --target-host "root@$host" \
                --no-reexec \
                -j auto \
                "''${@:2}"
            }
            export -f deploy-ernst

            # Push via gh token — works even when ~/.config/git is read-only
            # (impermanence on local machine). Usage: push [remote] [branch]
            push() {
              local remote=''${1:-origin}
              local branch=''${2:-main}
              local url
              url=$(git remote get-url "$remote" | sed 's|https://github.com/|https://'"$(gh auth token)"'@github.com/|')
              git push "$url" "$branch"
            }
            export -f push

            # Generate option reference docs from live NixOS config, then serve locally.
            # Usage: gendocs       — write docs/reference/*.md
            #        properdocs serve  — live-reload preview at http://localhost:8000
            gendocs() {
              python3 scripts/gen-options.py
            }
            export -f gendocs
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
            # nixpkgs 26.05 restructured services.kmscon; stylix's kmscon target
            # still writes services.kmscon.config which no longer exists.
            disabledModules = [ "${inputs.stylix}/modules/kmscon/nixos.nix" ];
          }

          inputs.impermanence.nixosModules.impermanence
          inputs.stylix.nixosModules.stylix
          inputs.home-manager.nixosModules.home-manager

          # Shared base modules (universal NixOS defaults + ZFS impermanence)
          ./modules/base.nix
          ./modules/zfs-impermanence.nix

          # Reusable modules (hardware + admin; users/roles/desktop via clan services)
          ./modules/locale.nix
          ./modules/networking.nix
          ./modules/hardware/cpu.nix
          ./modules/hardware/gpu.nix
          ./modules/hardware/display.nix
          ./modules/virtualisation.nix
          ./modules/users/admin.nix
          ./modules/users/sgo.nix

          # App category modules (options default false; enabled in configuration.nix)
          ./modules/apps

          # Machine-specific
          ./machines/miralda/configuration.nix
          ./machines/miralda/disko.nix
          ./machines/miralda/stylix.nix
          ./machines/miralda/wallpapers.nix
        ];
      };

      clan.machines.biene = {
        imports = [
          { _module.args = {
              pkgs-unstable = import inputs.nixpkgs-unstable {
                system = "x86_64-linux";
                config.allowUnfree = true;
              };
              inherit inputs;
            };
            # See miralda block — stylix kmscon target incompatible with nixpkgs 26.05.
            disabledModules = [ "${inputs.stylix}/modules/kmscon/nixos.nix" ];
          }

          inputs.impermanence.nixosModules.impermanence
          inputs.stylix.nixosModules.stylix
          inputs.home-manager.nixosModules.home-manager

          # Shared base modules (universal NixOS defaults + ZFS impermanence)
          ./modules/base.nix
          ./modules/zfs-impermanence.nix

          # App category modules (options default false; enabled in configuration.nix)
          ./modules/apps

          # Reusable modules (hardware + admin; users/roles/desktop via clan services)
          ./modules/locale.nix
          ./modules/networking.nix
          ./modules/hardware/cpu.nix
          ./modules/hardware/gpu.nix
          ./modules/hardware/display.nix
          ./modules/virtualisation.nix
          ./modules/users/admin.nix
          ./modules/wifi.nix

          # Machine-specific
          ./machines/biene/configuration.nix
          ./machines/biene/disko.nix
          ./machines/biene/stylix.nix
          ./machines/biene/wallpapers.nix
        ];
      };

      # ernst — AM5/X870E homelab server (NAS + VM host + GPU compute).
      clan.machines.ernst = {
        imports = [
          { _module.args = {
              pkgs-unstable = import inputs.nixpkgs-unstable {
                system = "x86_64-linux";
                config.allowUnfree = true;
              };
              inherit inputs;
            };
          }

          inputs.impermanence.nixosModules.impermanence
          inputs.home-manager.nixosModules.home-manager

          # Shared base modules (universal NixOS defaults + ZFS impermanence)
          ./modules/base.nix
          ./modules/zfs-impermanence.nix

          # Reusable modules
          ./modules/locale.nix
          ./modules/networking.nix
          ./modules/hardware/cpu.nix
          ./modules/hardware/gpu.nix
          ./modules/virtualisation.nix
          ./modules/users/admin.nix

          # Machine-specific
          ./machines/ernst/configuration.nix
          ./machines/ernst/disko.nix
          ./machines/ernst/hardware-configuration.nix
        ];
      };
    };
}
