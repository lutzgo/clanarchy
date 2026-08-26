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
    modules."@clanarchy/monitoring"   = import ./service-modules/monitoring.nix;
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
          # Autologin on: this is a TV appliance and should behave like one —
          # power on, land in the session, no keyboard required.
          #
          # This was previously off, on the reasoning that ernst fronts the NAS
          # array and physical access should meet a login prompt.  That trade
          # is being made deliberately, and it is narrower than it looks: `go`
          # is not in `wheel`, and roles/server.nix sets
          # `security.sudo.execWheelOnly`, so the couch session cannot sudo at
          # all.  The array is reachable from it only as far as the filesystem
          # permissions allow, which is the same exposure a logged-in `go`
          # already had — autologin changes who can *start* that session, not
          # what it can do.
          #
          # What it does mean: anyone with physical access to the living room
          # gets that session.  If ernst ever grows a couch-reachable path to
          # something privileged, revisit this first.
          autologin.enable = true;

          # The TV hangs off the dGPU (Navi 31 / RX 7900 XTX at 0000:03:00.0,
          # card1-HDMI-A-1).  The iGPU at 0000:7b:00.0 stays reserved for the
          # GL.iNet Comet KVM on card0-HDMI-A-2, which is why the GPU is pinned
          # by PCI address rather than left to the compositor's own choice:
          # card numbering is *inverted* here (the dGPU is card1) and can flip
          # on a kernel bump, which would put the session on the KVM's head and
          # take the compute card away from ROCm.
          #
          # The same dGPU is Ollama's ROCm card (see roles.ollama below).  A
          # session and ROCm workloads share a GPU without trouble — compute
          # goes through the render node, KMS through the card node — so this
          # is a note for future readers rather than a conflict.
          #
          # Naming it here also makes the session wait for the TV to be awake
          # before starting a compositor on that card; a TV that is off reads
          # as `disconnected`, and gamescope answers a card with no connected
          # output by segfaulting.  See modules/roles/htpc.nix.
          display.gpuPciAddress = "0000:03:00.0";

          # Plasma Bigscreen: OFF, and staying off.
          #
          # It cannot work in a container — Plasma 6.7 drives its session
          # through systemd user units and so needs logind, KWin needs logind
          # absent or an active *graphical* seat, and a container has no seat
          # to give.  The full account, including the seven things ruled out
          # along the way, is in modules/desktop/bigscreen.nix and
          # docs/guides/htpc-bigscreen.md; #64 reverted the last attempt and
          # parked it.
          #
          # It had been left enabled here after that revert, so ernst kept
          # building a second complete Plasma generation from nixpkgs-unstable
          # for a mode that shows a black screen — and Steam's own "Switch to
          # Desktop" button was still being mapped onto it.  The TV runs the
          # gamescope Steam session with Jellyfin Media Player, which works.
          bigscreen.enable = false;
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
          # qwen3-coder publishes only 30b/480b — there is no 8b, which is why
          # ollama-model-loader had been failing since this was configured.
          # 30b would run here, but only out of shared system RAM on the 780M
          # iGPU; the smaller dedicated coder model keeps it interactive.
          models = [ "qwen2.5-coder:7b" ];
          hsaOverrideGfxVersion = "11.0.3";
          # 4096 is what this tag derives on its own; pinning it says so out
          # loud so a future model bump cannot move it silently.  It must NOT
          # inherit ernst's 32768 — this model runs out of shared system RAM on
          # the 780M, not out of 24 GiB of VRAM.  Left at f16: a quantised KV
          # cache buys nothing worth having at a 4096 window and costs
          # tool-call reliability (see kvCacheType).
          contextLength = 4096;
        };
        # ernst: RX 7900 XTX (gfx1100) is natively supported by ROCm, so no
        # override — forcing one would select the wrong kernels.  The card is
        # shared with the HTPC gaming session rather than passed through to a
        # VM: VFIO would bind it to vfio-pci and take it away from the host,
        # making Ollama and gaming mutually exclusive.  Sharing means they
        # merely compete for VRAM, which is a far better failure mode.
        roles.ollama.machines.ernst.settings = {
          # 24 GiB of VRAM on the 7900 XTX fits the 30B MoE comfortably.
          models = [ "qwen3-coder:30b" ];
          # Both measured, not chosen: M11 Phase 0 walked the context/KV matrix
          # on this exact card.  32768 is what this tag derives anyway — pinned
          # so that editing `models` cannot move it without a diff.  q8_0 keeps
          # a 64k window fully resident (22482 MiB) where f16 spills to system
          # RAM, and makes the 32k window here cost 20757 MiB instead of 22361.
          #
          # q8_0 is safe ONLY because the client reinforces the <tool_call>
          # wrapper in its system prompt.  Without that it halves tool-call
          # reliability — the interaction is measured in the kvCacheType option
          # description and explained in service-modules/local-ai.md.  A client
          # added here that does not send that reinforcement wants f16.
          contextLength = 32768;
          kvCacheType   = "q8_0";
        };
        roles.opencode.machines.miralda.settings.user  = "lgo";
      };

      # ── Monitoring: Prometheus / Alertmanager / Grafana + node_exporter ──
      #
      # The client role is on EVERY machine, and that is the whole design:
      # scrape targets are derived from this list, so a machine added here is
      # a machine that gets monitored — there is no target list anywhere else
      # to forget.
      #
      # `alwaysOn` is the one setting that decides whether a machine gets the
      # InstanceDown alert.  ernst is the only true.  The other three are a
      # laptop, a laptop and a handheld: `up == 0` is their normal state
      # several times a day, and alerting on it would train everyone to ignore
      # the ntfy topic that also carries "the array is degraded".
      monitoring = {
        module.input = "self";
        module.name  = "@clanarchy/monitoring";

        # ernst runs the stack.  MAC and the .12 proxy address are allocated
        # in the tables in machines/ernst/networking.nix; the DHCP reservation
        # for 02:00:00:90:00:06 → 10.0.90.14 lives on the UDM-Pro.
        roles.server.machines.ernst.settings = {
          mac          = "02:00:00:90:00:06";
          proxyAddress = "10.0.90.12";

          # M7.  The identity provider, at the address allocated in the table
          # in machines/ernst/networking.nix.  Two independent things:
          #   address    — scrape it, because after M7 an Authelia that is down
          #                is every admin UI in the house being down.
          #   oidc       — Grafana logs in against it.  The LOCAL admin account
          #                stays; see the break-glass note in
          #                service-modules/monitoring.nix.
          authelia = {
            address        = "10.0.90.15";
            oidc.enable    = true;
            oidc.issuerUrl = "https://auth.goclan.org";
          };

          # M13.  Four media-stack targets, all on VLAN 90 addresses from the
          # table in machines/ernst/networking.nix, except Ollama which is on
          # ernst itself.
          #
          # Each of these needs a matching source-restriction on the FAR end —
          # the monitoring container's address has to be permitted there, or
          # the job simply times out.  Those rules are in containers/arr.nix,
          # containers/jellyfin.nix and microvms/wg-qbittorrent.nix.
          # THREE, NOT THE FOUR M13 ASKED FOR.  There is deliberately no Ollama
          # target: ollama 0.32.3 answers 404 on /metrics (measured on ernst,
          # 2026-08-26), so the job could only ever be down.  The reasoning and
          # what M15 should do instead are in service-modules/monitoring.nix.
          mediaStack = {
            arrAddress         = "10.0.90.13";
            jellyfinAddress    = "10.0.90.10";
            qbittorrentAddress = "10.0.90.11";
          };
        };

        # ernst is also a client, and the only one carrying the three optional
        # exporters: it is the machine with redundancy to lose (a zroot mirror
        # and a zdata raidz1), eight SAS/NVMe devices worth replacing before
        # they die, and the unit set — containers, secret staging, the
        # impermanence tripwire — that fails quietly if nobody looks.
        roles.client.machines.ernst.settings = {
          alwaysOn           = true;
          exporters.zfs      = true;
          exporters.smartctl = true;
          exporters.systemd  = true;
          # M13.  ARC statistics, which the pool exporter above does NOT cover
          # — see the option's description for why the two are not
          # interchangeable.  ernst only: on a laptop this series is noise.
          exporters.arc      = true;
        };

        # The laptops take node_exporter and nothing else.  miralda and biene
        # are ZFS machines, but a single-vdev laptop pool going degraded IS the
        # laptop dying, and ZED already reports that; smartctl re-queries every
        # device on a timer, which is a battery cost for data nobody acts on
        # before the machine is replaced anyway.
        roles.client.machines.miralda = { };
        roles.client.machines.biene   = { };
        roles.client.machines.birte   = { };
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
