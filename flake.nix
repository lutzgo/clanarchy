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

    # Unstable — required for Noctalia/Quickshell + Jovian-NixOS (intentionally NOT following clan-core/nixpkgs).
    #
    # Pinned to 2026-05-30 (rev 1bc189f) because unstable HEAD removed
    # `stdenv.hostPlatform.linux-kernel` in June 2026, breaking birte's build:
    # birte uses `nixpkgs.pkgs = unstablePkgs` (see lib/mk-machine.nix) but
    # NixOS modules from clan-core's 26.05 nixpkgs pin still read
    # `pkgs.stdenv.hostPlatform.linux-kernel.target` in top-level.nix.
    # This is the last pre-removal rev on nixos-unstable that still has
    # `linux-kernel`, keeps Jovian/Noctalia/Quickshell working, and lags
    # only ~5 weeks behind current unstable.
    #
    # Bump this pin once clan-core moves off 26.05 or ships a compat shim.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/1bc189f2e14dd7abb750903697b9683d54c0fcee";

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

    # Jovian-NixOS — Steam Deck (birte) support.
    # Jovian officially supports only nixos-unstable, so it follows
    # nixpkgs-unstable (which this flake already pulls in for Noctalia).
    # birte is built entirely against nixpkgs-unstable (see clan.machines.birte
    # below) — miralda / biene / ernst remain on clan-core's 26.05 pin.
    jovian-nixos = {
      url = "github:Jovian-Experiments/Jovian-NixOS";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

  };

  outputs = inputs@{ flake-parts, clan-core, ... }:
    let
      # Machine-composition helpers — mkModuleArgs, forceUnstablePkgs,
      # commonBase, commonHeadful. See lib/mk-machine.nix for details.
      machineLib = import ./lib/mk-machine.nix { inherit inputs; };
      inherit (machineLib) mkModuleArgs forceUnstablePkgs commonBase commonHeadful;
    in
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
            jujutsu             # jj (git-colocated) — available inside `nix develop`
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

            deploy-birte() {
              local action=''${1:-switch}
              local host=''${BIRTE_HOST:-birte.local}
              nixos-rebuild "$action" \
                --flake .#birte \
                --target-host "root@$host" \
                --no-reexec \
                -j auto \
                "''${@:2}"
            }
            export -f deploy-birte

            # Check out a PR branch and boot it in QEMU. Rebuild the VM (which
            # applies the machine's virtualisation.vmVariant overrides in
            # modules/vm-variant.nix) and launch it. The reviewer's working
            # branch is left on the PR HEAD until they gh pr checkout out.
            #
            # Usage: test-pr <PR#> [machine]      machine defaults to biene
            test-pr() {
              local pr=''${1?usage: test-pr <PR#> [machine]}
              local machine=''${2:-biene}
              gh pr checkout "$pr" || return 1
              nixos-rebuild build-vm --flake ".#$machine" --no-reexec -j auto || return 1
              exec ./result/bin/run-"$machine"-vm
            }
            export -f test-pr

            # Same as test-pr, but for an already-checked-out branch (or main).
            # Usage: test-vm [machine]            machine defaults to biene
            test-vm() {
              local machine=''${1:-biene}
              nixos-rebuild build-vm --flake ".#$machine" --no-reexec -j auto || return 1
              exec ./result/bin/run-"$machine"-vm
            }
            export -f test-vm

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

      # Machine composition.
      #
      # Each block reads as a per-machine feature list: module args + shared
      # imports (via commonBase / commonHeadful from lib/mk-machine.nix) +
      # machine-specific files.  See lib/mk-machine.nix for what the shared
      # lists contain and why.

      clan.machines.miralda = {
        imports = [ (mkModuleArgs { }) ] ++ commonHeadful ++ [
          ./modules/users/sgo.nix
          ./machines/miralda/configuration.nix
          ./machines/miralda/disko.nix
          ./machines/miralda/stylix.nix
          ./machines/miralda/wallpapers.nix
        ];
      };

      clan.machines.biene = {
        imports = [ (mkModuleArgs { }) ] ++ commonHeadful ++ [
          ./modules/wifi.nix
          ./machines/biene/configuration.nix
          ./machines/biene/disko.nix
          ./machines/biene/stylix.nix
          ./machines/biene/wallpapers.nix
        ];
      };

      # birte — Steam Deck OLED (Galileo). Boots into Steam Gaming Mode via
      # Jovian-NixOS; "Switch to Desktop" drops into KDE Plasma 6 (SDDM).
      # Built entirely against nixpkgs-unstable (Jovian only supports unstable);
      # forceUnstablePkgs overrides the clan-wide 26.05 pin from clan.nix.
      clan.machines.birte = {
        imports = [ (mkModuleArgs { }) forceUnstablePkgs ] ++ commonHeadful ++ [
          inputs.jovian-nixos.nixosModules.default
          ./modules/wifi.nix
          ./modules/gaming-common.nix
          ./machines/birte/configuration.nix
          ./machines/birte/disko.nix
          ./machines/birte/jovian.nix
          ./machines/birte/stylix.nix
          ./machines/birte/deck.nix
        ];
      };

      # ernst — AM5/X870E homelab server (NAS + VM host + GPU compute).
      # Headless: uses commonBase (no stylix / display / apps).
      clan.machines.ernst = {
        imports = [ (mkModuleArgs { }) ] ++ commonBase ++ [
          ./machines/ernst/configuration.nix
          ./machines/ernst/disko.nix
          ./machines/ernst/hardware-configuration.nix
          ./machines/ernst/networking.nix
        ];
      };
    };
}
