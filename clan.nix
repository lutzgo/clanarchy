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

    # ── Custom clan service modules ──────────────────────────────────────────
    # Registered here so they can be referenced by module.name in inventory.
    # Other clans can consume these by adding clanarchy as a flake input and
    # referencing module.input = "clanarchy".
    modules."@clanarchy/machine-type" = import ./service-modules/machine-type.nix;
    modules."@clanarchy/desktop"      = import ./service-modules/desktop.nix;
    modules."@clanarchy/users"        = import ./service-modules/users.nix;
    modules."@clanarchy/software"     = import ./service-modules/software.nix;
    modules."@clanarchy/local-ai"     = import ./service-modules/local-ai.nix;
    modules."@clanarchy/yubikey"      = import ./service-modules/yubikey.nix;
    modules."@clanarchy/printing"     = import ./service-modules/printing.nix;

    inventory.machines = {
      miralda = { };
      biene   = { };
      ernst   = { };
      birte   = { };
    };

    inventory.instances = {

      # ── Machine archetypes ─────────────────────────────────────────────────
      # Each machine is assigned to a hardware/role archetype.  Most machines
      # take exactly one; ernst takes two — it stays a headless server (SSH
      # hardening, GC, store optimisation) and additionally gains the couch
      # HTPC stack.  The roles are composed, not exclusive.
      machine-type = {
        module.input = "self";
        module.name  = "@clanarchy/machine-type";
        roles.laptop.machines.miralda.settings.framework.enable = true;
        roles.laptop.machines.biene = { };   # no Framework hardware
        roles.laptop.machines.birte = { };   # Steam Deck OLED — battery-backed handheld
        roles.server.machines.ernst = { };
        # ernst doubles as the living-room machine: boots into Steam Big
        # Picture on the TV, switches to Plasma and back.  Stable channel +
        # ZFS throughout — this is the stock nixpkgs gamescope session, not
        # Jovian (see modules/roles/htpc.nix for why that distinction holds).
        roles.htpc.machines.ernst.settings = {
          user = "go";
          defaultSession = "gamescope";
          # Autologin deliberately left off: ernst also fronts the NAS array,
          # so physical access should still meet a login prompt.  Flip it if
          # the appliance feel matters more than that.
          autologin.enable = false;
        };
      };

      # ── Desktop environments ───────────────────────────────────────────────
      # Each machine is assigned to exactly one desktop role.
      # The service imports only the relevant desktop module for that machine.
      desktop = {
        module.input = "self";
        module.name  = "@clanarchy/desktop";
        # miralda: Niri with Framework 13 display — default settings match hardware
        roles.niri.machines.miralda = { };
        # biene: labwc with Noctalia shell (replaces GNOME/GDM).
        # 1366x768 panel — native resolution (1.0) avoids 1.25 default that
        # shrinks usable logical space to 1093x614 on this low-res screen.
        roles.labwc.machines.biene.settings.display.scale = 1.0;
        # birte: KDE Plasma 6 as the "Switch to Desktop" session (SDDM).
        # Gaming Mode / Steam Big Picture is provided by Jovian (see
        # machines/birte/jovian.nix); Plasma is only reached when the user
        # exits gamescope-session.
        roles.kde.machines.birte = { };
      };

      # ── Users ───────────────────────────────────────────────────────────────
      # admin is imported directly in flake.nix (sets system-wide HM options).
      users = {
        module.input = "self";
        module.name  = "@clanarchy/users";
        roles.lgo.machines.miralda  = { };
        roles.sabine.machines.biene = { };
      };

      # ── SSH baseline ────────────────────────────────────────────────────────
      sshd = {
        roles.server.tags.all = { };
        roles.server.settings.authorizedKeys = {
          "admin-machine-1" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPo4uZn6hVFTnJ0K7eagj1XL0jVn9t6sSU8RAejhWBy+ clanarchy_admin";
          "lgo-yubikey"     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDjwV5tzb5mAhtUqgrfzU1FR35btJrvIjPM+PfxBAz4W openpgp:0x5E293E5A";
        };
      };

      # ── Zerotier VPN ────────────────────────────────────────────────────────
      # miralda is the controller; all machines are peers.
      zerotier = {
        roles.controller.machines."miralda" = { };
        roles.peer.tags.all = { };
      };

      # ── YubiKey ────────────────────────────────────────────────────────────
      yubikey = {
        module.input = "self";
        module.name  = "@clanarchy/yubikey";
        roles.default.machines.miralda = { };
      };

      # ── Printing ───────────────────────────────────────────────────────────
      printing = {
        module.input = "self";
        module.name  = "@clanarchy/printing";
        roles.default.machines.miralda = { };
      };

      # ── Syncthing ───────────────────────────────────────────────────────────
      # Syncs ~/Public across clan laptops.
      # openDefaultPorts restricts the firewall to zt+ (zerotier) interfaces.
      # User overrides (run as lgo / sabine) are in machines/*/configuration.nix.
      # Run `clan vars generate <machine>` once to generate syncthing key/cert/ID.
      syncthing = {
        module = { name = "syncthing"; input = "clan-core"; };
        roles.peer.machines.miralda = {
          settings = {
            openDefaultPorts = true;
            folders.public.path = "/home/lgo/Public";
          };
        };
        roles.peer.machines.biene = {
          settings = {
            openDefaultPorts = true;
            folders.public.path = "/home/sabine/Public";
          };
        };
      };

      # ── Wi-Fi ───────────────────────────────────────────────────────────────
      # Official clan wifi service — replaces the bespoke modules/wifi.nix and
      # the wifi-home vars generator.  The SSID and PSK are prompted at
      # `clan vars generate <machine>` time (shared across machines via share = true).
      wifi = {
        roles.default.machines.miralda = { };
        roles.default.machines.biene   = { };
        roles.default.machines.birte   = { };   # Steam Deck — wifi only
        # ernst is wired-only — intentionally excluded.
        roles.default.settings.networks = {
          home = { };   # prompts: SSID "skynet", PSK; keyMgmt defaults to wpa-psk
        };
      };

      # ── Local AI: Ollama + OpenCode ───────────────────────────────────────
      local-ai = {
        module.input = "self";
        module.name  = "@clanarchy/local-ai";
        # miralda: Phoenix iGPU (gfx1103) is missing from stock ROCm kernel
        # libraries, hence the override.
        roles.ollama.machines.miralda.settings = {
          models = [ "qwen3-coder:8b" ];
          hsaOverrideGfxVersion = "11.0.3";
        };
        # ernst: RX 7900 XTX (gfx1100) is natively supported by ROCm, so no
        # override — forcing one would select the wrong kernels.  The card is
        # shared with the HTPC gaming session rather than passed through to a
        # VM: VFIO would bind it to vfio-pci and take it away from the host,
        # making Ollama and gaming mutually exclusive.  Sharing means they
        # merely compete for VRAM, which is a far better failure mode.
        roles.ollama.machines.ernst.settings = {
          models = [ "qwen3-coder:8b" ];
        };
        roles.opencode.machines.miralda.settings.user  = "lgo";
      };

      # ── Software: browsers and email clients ─────────────────────────────
      # miralda/lgo:  all five browsers, no email.
      #   librewolf/chrome home.file configs are managed here (removed from
      #   machines/miralda/home-modules/browsers.nix to avoid duplication).
      # biene/sabine: librewolf + edge; both email clients.
      #   Firefox is already configured in modules/users/sabine.nix.
      software = {
        module.input = "self";
        module.name  = "@clanarchy/software";
        # browsers — lgo
        roles.librewolf.machines.miralda.settings.user  = "lgo";
        roles.firefox.machines.miralda.settings.user    = "lgo";
        roles.chromium.machines.miralda.settings.user   = "lgo";
        roles.chrome.machines.miralda.settings.user     = "lgo";
        roles.edge.machines.miralda                     = { };
        # browsers — sabine
        roles.librewolf.machines.biene.settings.user    = "sabine";
        roles.edge.machines.biene                       = { };
        # email — sabine
        roles.thunderbird.machines.biene.settings.user  = "sabine";
      };

    };

    machines = { };
  };
}
