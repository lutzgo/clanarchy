{ inputs, ... }:
{
  clan = {
    # Instantiate pkgs once per system with overlays applied.
    # nixpkgs.overlays in NixOS modules is ignored when pkgsForSystem is set
    # (clan-core force-sets nixpkgs.pkgs before NixOS modules run).
    pkgsForSystem = system: import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [
        # niri 25.08 test suite hits EMFILE (too many open files) in the Nix sandbox
        (_: prev: {
          niri = prev.niri.overrideAttrs (_: { checkPhase = ":"; });
        })
        # ungoogled-chromium: bake privacy flags into the binary.
        # Must be here (pkgsForSystem) — nixpkgs.overlays in NixOS modules is
        # ignored when pkgsForSystem is set (clan-core pre-sets nixpkgs.pkgs).
        (_: prev: {
          ungoogled-chromium = prev.ungoogled-chromium.override {
            commandLineArgs = [
              "--no-pings"
              "--disable-search-engine-collection"
              "--extension-mime-request-handling=always-prompt-for-install"
            ];
          };
        })
      ];
    };

    meta.name = "clanarchy";
    meta.domain = "goclan.org";

    inventory.machines = {
      miralda = { };
      # homeserver = { };  # uncomment when hardware is ready
    };

    inventory.instances = {
      # SSH baseline (recommended in official guide flow)
      sshd = {
        roles.server.tags.all = { };
        roles.server.settings.authorizedKeys = {
          "admin-machine-1" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPo4uZn6hVFTnJ0K7eagj1XL0jVn9t6sSU8RAejhWBy+ clanarchy_admin";
        };
      };

      # Zerotier scaffold (inactive until you choose a controller and deploy it)
      zerotier = {
        roles.controller.machines."miralda" = { };
        roles.peer.tags.all = { };
      };

      # Syncthing — keeps ~/Public in sync across all clan machines.
      # openDefaultPorts restricts firewall to zt+ (zerotier) interfaces only.
      # Run `clan vars generate miralda` once to generate the syncthing key/cert/ID.
      syncthing = {
        module = { name = "syncthing"; input = "clan-core"; };
        roles.peer.machines.miralda = {
          settings = {
            openDefaultPorts = true;
            folders.public = {
              path = "/home/lgo/Public";
            };
          };
        };
      };
    };

    machines = { };
  };
}
