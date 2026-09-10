{ inputs, ... }:
{
  clan = {
    # Instantiate pkgs once per system with overlays applied.
    # nixpkgs.overlays in NixOS modules is ignored when pkgsForSystem is set
    # (clan-core force-sets nixpkgs.pkgs before NixOS modules run).
    # The overlay list itself lives in lib/overlays.nix, because
    # lib/mk-machine.nix has to apply the same one to the unstable pkgs
    # instance — see the header there.
    pkgsForSystem = system: import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [ (import ./lib/overlays.nix) ];
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
      jens    = { };
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
        roles.laptop.machines.jens.settings.framework.enable = true;  # Framework 12
        roles.laptop.machines.biene = { };   # no Framework hardware
        roles.laptop.machines.birte = { };   # Steam Deck OLED — battery-backed handheld
        roles.server.machines.ernst = { };
        # ernst doubles as the living-room machine: boots into Kodi on the TV
        # and switches to Steam Big Picture or Plasma at runtime.  Stable
        # channel + ZFS throughout — the gaming arm is the stock nixpkgs
        # gamescope session, not Jovian (see modules/roles/htpc.nix for why
        # that distinction holds).
        roles.htpc.machines.ernst.settings = {
          user = "go";
          # The living room watches more than it plays, so the machine should
          # come up in the media client rather than in Steam. Gaming is one
          # `clanarchy-session-select gamescope` away, and Kodi's own Exit
          # lands there too (see the kodi arm in modules/roles/htpc.nix).
          defaultSession = "kodi";
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

          # The living-room set is an HDR LG, and the couch use case is
          # watching films rather than only playing games: without this the
          # gamescope session is SDR, so Jellyfin's HDR material has to be
          # tone-mapped to SDR on the server — a 4K Dolby Vision transcode
          # that ernst's iGPU manages at barely realtime (0.87x measured
          # 2026-09-04). HDR output is what lets the client direct-play it
          # instead, which costs the server nothing at all.
          display.hdr.enable = true;

          # Phone remote (Kore) for the couch, since the TV remote cannot
          # reach Kodi: no CEC adapter is fitted, and CEC over the GPU's HDMI
          # does not exist on consumer cards.
          #
          # This opens a full control surface — browse, play, shut the machine
          # down — on the box that fronts the array, so it is only half the
          # job: Kodi's own web server must be given a username and password
          # in Services -> Control, which is runtime state this cannot set.
          # Reachability from the phone's VLAN is the UDM-Pro's business, the
          # same as it was for Jellyfin.
          mediaClient.remoteControl.enable = true;

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
        # jens: same Niri desktop, Framework 12 panel — 1920×1200 at 12.2"
        # (~186 PPI).  The role's resolution defaults are miralda's 2256×1504,
        # so they have to be named here; scale 1.25 is right for both.
        roles.niri.machines.jens.settings.display = {
          width  = 1920;
          height = 1200;
        };
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
        roles.lgo.machines.jens     = { };
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
        # The key travels with lgo, so every machine lgo logs into needs the
        # pcscd + pinentry-qt wiring — not just the one it was first set up on.
        roles.default.machines.jens    = { };
      };

      # ── Printing ───────────────────────────────────────────────────────────
      printing = {
        module.input = "self";
        module.name  = "@clanarchy/printing";
        roles.default.machines.miralda = { };
        roles.default.machines.jens    = { };
      };

      # ── Syncthing: TWO SEPARATE CLUSTERS, NOT ONE ──────────────────────────
      #
      # `openDefaultPorts` restricts the firewall to zt+ (zerotier) interfaces.
      # User overrides (run as lgo / sabine) are in machines/*/configuration.nix.
      # Run `clan vars generate <machine>` once to generate key/cert/ID.
      #
      # ── WHY TWO INSTANCES ───────────────────────────────────────────────
      #
      # clan-core's syncthing service puts every peer of an instance into
      # every other peer's DEVICE list, while folder sharing is scoped
      # per-folder.  A single five-machine instance therefore creates pairs
      # that know each other but share nothing at all — ernst and jens, ernst
      # and miralda, birte and biene.  Syncthing does not leave such a pair
      # alone: the two connect, exchange hellos, find no folder in common and
      # drop, then reconnect.  Measured on ernst, roughly one connect/drop
      # cycle every ten seconds, per peer, forever:
      #
      #   INF Established secure connection (device=ZY2KORK ...)
      #   INF Lost device connection (... error="reading length: EOF")
      #
      # It is not merely noise.  It buries anything real in those journals,
      # which is exactly where a genuine sync fault would have to be read.
      #
      # Splitting into two instances makes the device lists disjoint, so no
      # machine ever knows a peer it shares nothing with, and the churn has
      # nowhere to come from.
      #
      # ── AND IT MAKES THE SCOPING STRUCTURAL ─────────────────────────────
      #
      # `devices = [ ]` means "share with every peer in THIS instance"
      # (clanServices/syncthing/default.nix: `if folderConfig.devices == [ ]
      # then lib.attrNames validDevices`).  In one big instance that default
      # was a trap — adding ernst and birte for the ROM library would have
      # silently shared lgo's and Sabine's Public folders onto a homelab
      # server and a games console — and it had to be defused by naming the
      # devices of every folder by hand.
      #
      # With the clusters split, instance membership IS the scope, so the
      # default is correct by construction and the hand-maintained lists are
      # gone.  That is deliberate rather than lazy: keeping both would be two
      # sources of truth for one property, which containers/traefik.nix
      # already argues against in its own words — "how you get a rule nobody
      # dares delete because nobody can prove what it does".  To share
      # something with a machine now, put the machine in the instance.

      # The laptops: lgo's and Sabine's ~/Public.
      syncthing-home = {
        module = { name = "syncthing"; input = "clan-core"; };
        roles.peer.machines.miralda.settings = {
          openDefaultPorts = true;
          folders.public.path = "/home/lgo/Public";
        };
        roles.peer.machines.jens.settings = {
          openDefaultPorts = true;
          folders.public.path = "/home/lgo/Public";
        };
        roles.peer.machines.biene.settings = {
          openDefaultPorts = true;
          folders.public.path = "/home/sabine/Public";
        };
      };

      # ── The ROM library: ernst masters it, birte plays it offline ──────────
      #
      # ernst's copy is the authoritative one — it is the tree RomM scans and
      # the one that gets snapshotted (zdata/roms sets
      # com.sun:auto-snapshot=true precisely because Syncthing is NOT a
      # backup: it replicates deletions faithfully and within seconds).
      #
      # birte's copy is what makes the Deck work away from the house.  That was
      # the whole reason a network mount was rejected in favour of a full
      # second copy; see the header of machines/ernst/containers/romm.nix.
      #
      # The two paths differ because each machine already had a right answer
      # for where large game data lives: ernst's own dataset, and birte's
      # @games subvolume, which is outside the rollback and outside the
      # impermanence bind-mounts.  Syncthing does not care that they differ.
      #
      # ── TWO FOLDERS, NOT ONE ROOT ───────────────────────────────────────
      #
      # The obvious shape — one folder pairing ernst's /srv/roms with birte's
      # /games/retrodeck — is wrong, because those two directories are not the
      # same set of things.  RetroDECK's data folder also holds `saves/`,
      # `states/` and `.downloaded_media/`, so a root-level pair would push the
      # Deck's save games and its whole scraped-art cache onto the server as a
      # side effect of syncing ROMs.
      #
      # `roms` and `bios` are exactly the subtrees that correspond on both
      # machines, so those are the folders.  Saves stay local to the Deck; if
      # they should be replicated too, that is a separate decision with its own
      # conflict semantics (two machines playing the same game), not something
      # to acquire by accident.
      # ── ignorePerms: THE TWO ENDS ARE OWNED BY DIFFERENT PRINCIPALS ─────
      #
      # Syncthing replicates permission bits by default, and it cannot do that
      # here.  `chmod` requires OWNERSHIP, not group membership, and syncthing
      # owns neither end: on ernst the tree is RomM's (uid 3029, 2770
      # root:romm) and on birte it is RetroDECK's (deck:roms).  Syncthing is
      # only ever a member of the shared group, so it failed on every
      # directory it tried to sync:
      #
      #   syncing: handling dir (setting permissions):
      #   chmod /srv/roms/roms/playdate: operation not permitted
      #
      # AND IT WOULD BE WRONG EVEN IF IT WORKED.  The permission bits on both
      # ends are decided declaratively — by romm-dirs.service on ernst and by
      # the tmpfiles rules in machines/birte/deck.nix on birte — precisely so
      # that two different local writers can share each tree.  Letting
      # Syncthing carry one machine's bits onto the other would overwrite a
      # deliberate local decision with a remote one, and the setgid bit that
      # makes the whole arrangement work is exactly what would be lost.
      #
      # So the permissions are owned by each machine and the CONTENT is what
      # replicates.  That is the correct division here, not a concession.
      syncthing-roms = {
        module = { name = "syncthing"; input = "clan-core"; };
        roles.peer.machines.ernst.settings = {
          openDefaultPorts = true;
          folders.roms = { path = "/srv/roms/roms"; ignorePerms = true; };
          folders.bios = { path = "/srv/roms/bios"; ignorePerms = true; };
        };
        roles.peer.machines.birte.settings = {
          openDefaultPorts = true;
          folders.roms = { path = "/games/retrodeck/roms"; ignorePerms = true; };
          folders.bios = { path = "/games/retrodeck/bios"; ignorePerms = true; };
        };
      };

      # ── Wi-Fi ───────────────────────────────────────────────────────────────
      # Official clan wifi service — replaces the bespoke modules/wifi.nix and
      # the wifi-home vars generator.  The SSID and PSK are prompted at
      # `clan vars generate <machine>` time (shared across machines via share = true).
      wifi = {
        roles.default.machines.miralda = { };
        roles.default.machines.jens    = { };
        roles.default.machines.biene   = { };
        roles.default.machines.birte   = { };   # Steam Deck — wifi only
        # ernst is wired-only — intentionally excluded.
        roles.default.settings.networks = {
          home = { };   # prompts: SSID "skynet", PSK; keyMgmt defaults to wpa-psk
        };
      };

      # ── Local AI: llama.cpp inference, voice, vision, image (M19) ─────────
      #
      # OLLAMA IS GONE FROM ernst.  It was replaced by llama-swap in front of
      # llama-server in router mode, and the replacement was measured before it
      # was taken — see docs/roadmap.md §M19 and
      # ~/.local/share/m19-llamacpp/PHASE0-NOTES.md.  The decisive result is
      # that context overflow stops being silent: ollama answers an over-long
      # prompt with HTTP 200, a truncated head and a fabricated answer, where
      # llama-server answers HTTP 400 naming both numbers.  That is standing
      # note SN1's core hazard removed at the mechanism.
      #
      # MIRALDA STILL RUNS ITS OWN OLLAMA and is deliberately out of scope: its
      # gfx1103 iGPU is a different problem with a different answer, and
      # migrating it is not this milestone's business.  It keeps
      # `roles.ollama`, which is why that role still exists in the module.
      local-ai = {
        module.input = "self";
        module.name  = "@clanarchy/local-ai";

        # ── ernst: the inference server ──────────────────────────────────
        #
        # RX 7900 XTX (gfx1100) is natively supported by ROCm, so there is NO
        # HSA override — forcing one selects the wrong kernels for a card that
        # already has correct ones.  The card is shared with the HTPC gaming
        # session rather than passed through to a VM: VFIO would bind it to
        # vfio-pci and take it away from the host (invariant #5), making
        # inference and gaming mutually exclusive.  Sharing means they merely
        # compete for VRAM, which is a far better failure mode — and since M19
        # that competition is arbitrated rather than hoped about.
        roles.inference.machines.ernst.settings = {
          # Accept the SSH forward jens uses (see roles.opencode.machines.jens).
          # llama-swap stays bound to loopback — this authorises one key
          # restricted to forwarding 127.0.0.1:11434 and nothing else.  The
          # port is unchanged from the ollama era ON PURPOSE, so jens's
          # `permitopen` restriction needs no edit at all.
          remoteClients.enable = true;

          # ── The two containers that need llama-swap ────────────────────
          #
          # llama-swap binds 127.0.0.1 and stays there, so each consumer gets
          # its own point-to-point ULA veth, a proxy on the host end, and one
          # firewall accept for the container end.  Nothing on any VLAN.
          #
          # BOTH ENTRIES ARE REQUIRED AND THE SECOND WAS MISSED ONCE.
          # `monitoring` had a bespoke option and worked; `webui` was pointed at
          # fdca:fe91::1 with nothing listening, so Open WebUI showed "No models
          # available" and voice input span forever — three layers from the
          # cause.  One list now, so a consumer cannot be half-added.
          #
          # These are also where M19 widens ernst's attack surface, and the
          # interim-rule ledger says so: two extra listeners, each on a /128
          # whose only peer is one container.
          exposeOn = [
            # M6's mon0. Prometheus scrapes llama-swap's /metrics here — the
            # target M13 declined to add because ollama served none.
            { name = "monitoring"; address = "fdca:fe90::1"; allowedSource = "fdca:fe90::2"; }
            # ai0, one /64 along so the two links cannot be confused in a
            # routing table. Carries Open WebUI's chat AND its STT.
            { name = "webui";      address = "fdca:fe91::1"; allowedSource = "fdca:fe91::2"; }
          ];
        };

        # ── ernst: the model set ────────────────────────────────────────
        #
        # ONE ATTRSET, TWO CONSUMERS — the fetcher and llama-server's preset
        # INI are both rendered from this, so a model cannot be downloaded but
        # undeclared, or declared but never fetched.  That is the structural
        # answer to the ollama era's two failures: a registry tag that never
        # existed, and a context window that moved when the tag was edited.
        #
        # EVERY url AND hash BELOW WAS FETCHED AND VERIFIED before it was
        # written down, on 2026-09-09.  Do not add an entry any other way.
        roles.models.machines.ernst.settings.models = {
          # The coder model.  Same family and quantisation class as the ollama
          # blob it replaces, so M11's and M19's numbers still describe it.
          qwen3-coder-30b = {
            url  = "https://huggingface.co/unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF/resolve/main/Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL.gguf";
            hash = "sha256-KEGqMU2RZDSGDPuJkDR1KNzf5cNQ28udFGHb7oj/JTM=";
            filename    = "Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL.gguf";
            description = "Qwen3 Coder 30B (A3B, UD-Q4_K_XL)";

            # SN1 LIVES HERE NOW, and that is the point of the placement: the
            # window sits on the model, is required, and moves only when
            # somebody edits this line.  Under ollama it was derived from the
            # tag and set by one global env var, so editing which model was
            # served silently changed the context for every client.
            #
            # 32768 measured: 21799 MiB resident of 24560, f16, 107.5 tok/s.
            contextLength = 32768;

            # f16, REVERSING ernst's ollama-era q8_0 — and the reversal is a
            # measurement, not a preference.  q8_0 existed only because f16 at
            # 65536 spilled on ollama.  On llama.cpp f16 at 32768 fits with
            # 2761 MiB to spare and q8_0 would cost 14.7% of decode (94.6 vs
            # 107.5 tok/s, interleaved, n=5) to buy nothing at this window.
            kvCacheType = "f16";
          };

          # Vision.  A SECOND model rather than a bigger one: the coder model
          # has no vision tower, and llama-swap's exclusive group means the two
          # are never resident together, so this costs disk rather than VRAM.
          # QUOTED, and it has to be: `qwen2.5-vl-7b = …` is a DOTTED PATH in
          # Nix and would silently declare `qwen2."5-vl-7b"` — a model named
          # "5-vl-7b" nested under one named "qwen2", which type-checks and is
          # wrong.
          "qwen2.5-vl-7b" = {
            url  = "https://huggingface.co/ggml-org/Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf";
            hash = "sha256-kli/BbEmhtCX/ztrGNloqzk2SXgKorPNZ/7EPVBVQ5I=";
            filename    = "Qwen2.5-VL-7B-Instruct-Q4_K_M.gguf";
            description = "Qwen2.5-VL 7B (vision)";
            contextLength = 16384;
            kvCacheType   = "f16";
            # llama.cpp needs the projector and the weights as TWO files.
            mmproj = "mmproj-Qwen2.5-VL-7B-Instruct-f16.gguf";
            extraFiles."mmproj-Qwen2.5-VL-7B-Instruct-f16.gguf" = {
              url  = "https://huggingface.co/ggml-org/Qwen2.5-VL-7B-Instruct-GGUF/resolve/main/mmproj-Qwen2.5-VL-7B-Instruct-f16.gguf";
              hash = "sha256-wkp/X8/GgobwohcCO2c45zvqTxF4ekPoI41LsbhgTN4=";
            };
          };

          # Whisper's weights.  Declared here rather than in roles.speech so
          # there is ONE fetcher and one hash-verified store for everything the
          # GPU tier loads — the speech role names the filename and nothing
          # else.  It is not a GGUF and llama-server never loads it; the
          # inference role skips non-LLM entries when rendering the preset INI.
          whisper-large-v3-turbo = {
            url  = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin";
            hash = "sha256-OUIhcJzVrR9AxG5gMcphvOiJMebgiMGIKUxtWlX/p+I=";
            filename    = "ggml-large-v3-turbo-q5_0.bin";
            description = "Whisper large-v3-turbo (q5_0)";
            # Unused for this entry — whisper-server takes neither — but the
            # option is required, deliberately, so that no model can be
            # declared without someone stating its window.
            contextLength = 1;
            kvCacheType   = "f16";
            servedByLlama = false;
          };

          # ── M21: the diffusion checkpoint, in the SAME store ────────────
          #
          # SDXL base 1.0.  Declared here rather than by a second fetcher for
          # the reason the whisper entry above gives — one hash-verified tree,
          # one place to look when a file is missing — and `servedByLlama =
          # false` is the same escape hatch: llama-server cannot load a
          # safetensors checkpoint and a preset section pointing at one would
          # be a load error per request.
          #
          # `subdir` (added by M21) is what keeps ComfyUI's directory scan
          # honest.  ComfyUI discovers models by category directory, and
          # `folder_paths.py`'s supported_pt_extensions includes `.bin` — so
          # against a flat store it would offer Whisper's
          # ggml-large-v3-turbo-q5_0.bin as a diffusion checkpoint while
          # correctly ignoring the GGUFs.  The subdirectory name IS the
          # ComfyUI category, and the generated extra_model_paths.yaml is
          # derived from these declarations rather than written out again.
          #
          # WHY SDXL AND NOT FLUX.  Two reasons, one of them fatal to Flux
          # here.  Flux.1-dev is GATED on HuggingFace — the fetcher would meet
          # a token wall, not a file, and the failure would look like a broken
          # URL.  And the VRAM budget only works by eviction: the card is
          # 24560 MiB and the coder model holds 21799 of it, so whatever is
          # declared has to fit ALONE after the exclusive group evicts the LLM.
          # SDXL at 6.9 GiB does so with room for the VAE and a large latent;
          # a 17 GiB single-file Flux would fit but leaves nothing spare and
          # buys a slower first token on every image.
          #
          # VERIFIED TWICE, 2026-09-09, because this repo has shipped a
          # nonexistent model reference twice: `nix store prefetch-file`
          # returned the hash below, and its base16 form
          # (31e35c80fc4829d14f90153f4c74cd59c90b779f6afe05a74cd6120b893f7e5b)
          # matches HuggingFace's own LFS oid for the file.  Two independent
          # sources agreeing, not one download trusted.
          sdxl-base-1_0 = {
            url  = "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors";
            hash = "sha256-MeNcgPxIKdFPkBU/THTNWckLd59q/gWnTNYSC4k/fls=";
            filename    = "sd_xl_base_1.0.safetensors";
            subdir      = "checkpoints";
            description = "Stable Diffusion XL base 1.0";
            # Neither applies to a diffusion model; both are required options,
            # deliberately, so that nothing can be declared without a stated
            # window.  Same non-answer the whisper entry gives.
            contextLength = 1;
            kvCacheType   = "f16";
            servedByLlama = false;
          };
        };

        # ── ernst: voice ────────────────────────────────────────────────
        #
        # whisper.cpp, NOT Speaches.  Speaches is not in nixpkgs at all, and
        # its STT path runs through CTranslate2, whose GPU backend is CUDA — on
        # a 7900 XTX that is a CPU path with extra steps.  pkgs.whisper-cpp
        # builds with rocmSupport for gfx1100 out of the flake's own nixpkgs,
        # and whisper-server takes --inference-path, so it is OpenAI-shaped
        # with no wrapper and no new flake input.
        roles.speech.machines.ernst.settings = {
          model    = "ggml-large-v3-turbo-q5_0.bin";
          # "auto" rather than "de": this household dictates German prose with
          # English package names in it, and pinning the language gets the
          # second half wrong.
          language = "auto";
        };

        # ── ernst: image generation ─────────────────────────────────────
        #
        # ENABLED BY M21, and it is three lines because the milestone spent
        # itself on the two decisions rather than on configuration.
        #
        # THE IMAGE DECISION WENT THE OTHER WAY.  M19 left this unset pending
        # a digest to pin; the survey found nothing worth pinning.  AMD's own
        # docker.io/rocm/comfyui is built PYTORCH_ROCM_ARCH=gfx942;gfx950 and
        # has no kernels for this card at all; the best-provenance community
        # image copies ComfyUI into a volume on first run so its digest pins
        # only the first install; the one image that fits has a single GitHub
        # star.  And llama-swap — unprivileged — could never have started or
        # stopped a rootful container, which is what eviction requires.
        #
        # So ComfyUI is BUILT (service-modules/pkgs/comfyui) and spawned by
        # llama-swap like every other backend.  It is not on the podman tier,
        # takes no uid, no MAC and no address, and uid 3035 / sequence 10 /
        # 10.0.90.24 went back to M20.  Full argument in docs/roadmap.md §M21.
        roles.imagegen.machines.ernst.settings = {
          # Only what ComfyUI itself writes — outputs, inputs, temp, user
          # settings, an empty custom_nodes.  On zdata (invariant #7).  The
          # WEIGHTS are not here: they are declared in roles.models above and
          # live in the one hash-verified model store, which ComfyUI is
          # pointed at through a generated extra_model_paths.yaml.
          stateDir = "/srv/state/comfyui";

          # ── THE ONE FLAG WITHOUT WHICH THE PROMPT IS IGNORED ───────────
          #
          # PyTorch's SDPA cross-attention is SILENTLY WRONG on this stack
          # (torch 2.11 + ROCm 7.2.3, gfx1100).  Not slow, not an error — it
          # returns garbage for the cross-attention shapes SDXL uses, which is
          # where the text conditioning enters the UNet.  Self-attention is
          # unaffected, so the images come out sharp, detailed and coherent
          # and have NOTHING TO DO WITH THE PROMPT.
          #
          # BISECTED ON ernst 2026-09-10, same checkpoint / seed / workflow,
          # prompt "a photograph of a red apple on a white table":
          #
          #   GPU, pytorch attention (default)      -> psychedelic poster
          #   GPU, --fp32-text-enc                  -> a landscape
          #   CPU (--cpu)                           -> A RED APPLE
          #   GPU, --use-split-cross-attention      -> A RED APPLE
          #
          # The CPU arm is what proves it is not the packaging: identical
          # derivation, identical pure-Python comfy-kitchen and comfy-aimdo
          # wheels, identical everything but the device.  And --fp32-text-enc
          # rules out text-encoder precision, which was the obvious suspect
          # and the wrong one.
          #
          # THIS IS EXACTLY THE SHAPE M19 WARNS ABOUT and it is worth saying
          # again: the deployment looked correct at every level anyone would
          # check.  ROCm reported `Device: cuda:0 AMD Radeon RX 7900 XTX :
          # native`, VRAM moved, the LLM was evicted and restored, the
          # exclusive group worked, generation took seconds rather than
          # minutes — every signal said "working GPU path", and the only
          # symptom was that the pictures were of the wrong thing.
          #
          # Do NOT drop this flag on a llama.cpp/ROCm bump without re-running
          # the apple test above.  It costs some speed and it is the
          # difference between image generation and an expensive random image
          # generator.
          extraArgs = [ "--use-split-cross-attention" ];

          # NOTHING ELSE BELONGS HERE.  --lowvram and friends are for a card
          # that has to share, and this one does not: the exclusive group
          # evicts the 21799 MiB coder model before ComfyUI is spawned, so
          # SDXL gets essentially the whole 24560 MiB.  Reaching for them
          # would be treating a broken exclusion as a memory problem.
        };

        # ── ernst: the web client ───────────────────────────────────────
        roles.webui.machines.ernst.settings = {
          # MAC / address / uid allocated in the tables in
          # machines/ernst/networking.nix.  The DHCP reservation for
          # 02:00:00:90:00:0f → 10.0.90.23 lives on the UDM-Pro and must exist
          # BEFORE this is deployed.
          mac = "02:00:00:90:00:0f";
          uid = 3034;

          # Technitium record required BEFORE the name is typed anywhere —
          # M17's NXDOMAIN lesson.  Also in `protectedHosts` in
          # containers/ingress-policy.nix, in the same commit.
          hostName = "chat.goclan.org";

          # OIDC against Authelia, the Grafana pattern: forward-auth at the
          # edge AND real OIDC inside, so the app knows who the user is rather
          # than merely that Traefik let them past.
          oidc.enable = true;

          # Host end of THIS container's veth to ernst.  fdca:fe91::/64, one
          # /64 along from monitoring's fdca:fe90::/64, so the two
          # point-to-point links cannot be confused in a routing table.
          inferenceAddress = "fdca:fe91::1";

          # Voice in.  Points at llama-swap, so Whisper's VRAM is arbitrated
          # by the same exclusive group as everything else rather than being a
          # second, unaccounted consumer.
          speechUrl = "http://[fdca:fe91::1]:11434";

          # Image out.  SAME bridge as chat and STT — no new listener, no new
          # firewall rule, which is what the exposeOn list above already
          # provides.
          #
          # ── THE `/upstream/comfyui` SUFFIX IS LOAD-BEARING ────────────────
          #
          # llama-swap normally picks a backend by reading a `model` field out
          # of an OpenAI-shaped request body.  Open WebUI's ComfyUI client
          # speaks ComfyUI's OWN API instead — POST /prompt, GET /history/<id>,
          # GET /view, and a websocket at /ws — none of which carry a model
          # name anywhere llama-swap could find one.
          #
          # `/upstream/<model>/<path>` is llama-swap's answer: it proxies ANY
          # request to that backend, starting it through the normal swap path
          # first, so the exclusive group still evicts the LLM
          # (internal/server/api.go's handleUpstream, registered at
          # server.go:230).  Without the suffix every image request would be a
          # 404 from a router that could not tell what it was for.
          #
          # It survives the websocket too, which was checked rather than
          # hoped: Open WebUI builds its socket URL as
          # `base_url.replace('http://','ws://') + '/ws?clientId=...'`
          # (utils/images/comfyui.py:190), and every HTTP endpoint it uses is
          # an `f'{base_url}/...'` append — so a base URL carrying a path
          # prefix works throughout rather than only for the first call.
          imageUrl = "http://[fdca:fe91::1]:11434/upstream/comfyui";

          # The checkpoint Open WebUI asks ComfyUI to load.  ASSERTED against
          # roles.models above — it must name an entry declared there with
          # `subdir = "checkpoints"`, so a typo is a build error rather than an
          # image request that fails inside ComfyUI.
          #
          # Without it, IMAGE_GENERATION_MODEL is the empty string and Open
          # WebUI's bundled workflow asks for a checkpoint that does not exist.
          imageModel = "sd_xl_base_1.0.safetensors";

          # 1024x1024 because that is what SDXL is trained at.  Open WebUI
          # defaults to 512x512, which this checkpoint degrades at — it would
          # have produced working-but-poor images, which is worse than a clean
          # failure because nothing reports it.
          imageSize = "1024x1024";

          # img2img: upload a picture with a prompt and transform it. Same
          # ComfyUI, same bridge, same checkpoint — Open WebUI just keeps
          # editing as a separate subsystem with its own enable flag, and
          # ships no default workflow for it, so the graph lives in the role.
          imageEditEnable = true;
        };

        # ── miralda: unchanged, and out of scope ────────────────────────
        # Phoenix iGPU (gfx1103) is missing from stock ROCm kernel libraries,
        # hence the override.  Migrating this machine to llama.cpp is a
        # separate question with a different answer — an iGPU running out of
        # shared system RAM is not the case M19 measured.
        roles.ollama.machines.miralda.settings = {
          # qwen3-coder publishes only 30b/480b — there is no 8b, which is why
          # ollama-model-loader had been failing since this was configured.
          models = [ "qwen2.5-coder:7b" ];
          hsaOverrideGfxVersion = "11.0.3";
          # 4096 is what this tag derives on its own; pinning it says so out
          # loud so a future model bump cannot move it silently.
          contextLength = 4096;
        };
        roles.opencode.machines.miralda.settings = {
          user  = "lgo";
          # miralda talks to its OWN ollama, so the provider id and model name
          # are ollama's, not llama-swap's.
          providerName = "ollama";
          model        = "ollama/qwen2.5-coder:7b";
        };

        # jens has no local inference: its iGPU is Intel, where the ROCm stack
        # this module is built around does not apply, and a 30B MoE on CPU is
        # not something to sit in front of.  So opencode here talks to ernst's
        # card over an SSH forward, with the listener staying loopback-only at
        # both ends of the tunnel.
        roles.opencode.machines.jens.settings = {
          user  = "lgo";
          # Must match a KEY in ernst's roles.models above — no longer an
          # ollama registry tag, which is the class of mistake that put
          # `qwen3-coder:8b` into a restart loop for months.
          model = "local/qwen3-coder-30b";
          tunnel.enable = true;
        };
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

          # M18.  CrowdSec, which watches the WAN entrypoint the same
          # milestone opened.
          #
          # THE ADDRESS IS TRAEFIK'S, and that is deliberate rather than a
          # copy-paste: CrowdSec runs INSIDE the traefik container's network
          # namespace, because that is the only namespace that sees the
          # pre-DNAT source address of a WAN request (br0 forwards those
          # frames at layer 2 and br_netfilter is not loaded — measured on
          # ernst 2026-09-03).  See machines/ernst/containers/crowdsec.nix.
          #
          # This is the one target that carries an alert, and the reason is
          # the asymmetry M18 introduced: Traefik or Authelia going down is an
          # outage somebody reports within minutes, while CrowdSec going down
          # is silent — the house stays up, the internet stays reachable, and
          # nothing is watching it.  Exposed and unprotected.
          crowdsec.address = "10.0.90.12";

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

            # Navidrome, added 2026-09-08.  THE SAME ADDRESS AS arrAddress —
            # it is a unit inside the arr container, not a container of its
            # own — but a separate option, because placement is a decision
            # here and not a property of the module.
            #
            # THE ONLY AUTHENTICATED SCRAPE IN THIS FLEET.  Navidrome's
            # /metrics rides the ordinary application port and demands HTTP
            # Basic, so the password file is not optional; monitoring.nix
            # asserts on the pair rather than letting the job 401, because a
            # 401 presents as `up == 0` and reads as an outage.
            #
            # The path is INSIDE the monitoring container, staged there by
            # monitoring-secrets from the `navidrome-metrics` generator that
            # machines/ernst/containers/arr.nix declares.  One generator, two
            # containers, two staging units — see that file for why the same
            # secret is emitted in two formats.
            navidromeAddress             = "10.0.90.13";
            navidromeMetricsPasswordFile = "/run/monitoring-secrets/navidrome-metrics-password";
          };

          # M19.  The inference stack — THE TARGET M13 WANTED AND COULD NOT
          # HAVE.
          #
          # M13 asked for four media-stack targets and shipped three, because
          # ollama 0.32.3 answered 404 on /metrics and a job for it could only
          # ever be `up == 0`.  llama-swap serves real metrics, so the fourth
          # arrives here instead.
          #
          # No address and no model name: the stack is on ernst itself and
          # monitoring.nix already knows how this container reaches the host,
          # and llama-swap's /metrics is a plain scrape that is up whether or
          # not a model is resident.
          localAi.enable = true;
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
          # Failed units INSIDE the seven nspawn containers, which
          # exporters.systemd above cannot see: it reads the host's systemd and
          # each container runs its own init.  ernst is the only machine in the
          # fleet with containers at all, so it is the only consumer.
          exporters.containers = true;
          # Crash loops.  ernst is where processes crash unattended: the couch
          # session relaunches Kodi on its own, and the containers restart
          # their services, so a process can die repeatedly without any unit
          # ever changing state.  The laptops have someone sitting in front of
          # them when something crashes.
          exporters.coredumps  = true;
          # M18 follow-up.  SN2's IPv4-only decision, made observable instead
          # of re-measured by hand.  ernst only, and not because the other
          # machines do not matter: they ROAM, and a café network handing out
          # a v6 prefix is normal there.  ernst never leaves VLAN 90, so a
          # global address on ernst means the line itself changed — and after
          # M18 that is the event that would make every router in the house
          # reachable on a path the `wan` entryPoint does not gate.
          exporters.ipv6Guard  = true;
        };

        # The laptops take node_exporter and nothing else.  miralda and biene
        # are ZFS machines, but a single-vdev laptop pool going degraded IS the
        # laptop dying, and ZED already reports that; smartctl re-queries every
        # device on a timer, which is a battery cost for data nobody acts on
        # before the machine is replaced anyway.
        roles.client.machines.miralda = { };
        roles.client.machines.jens    = { };
        roles.client.machines.biene   = { };
        roles.client.machines.birte   = { };
      };

      # ── Software: browsers and email clients ─────────────────────────────
      # miralda/lgo, jens/lgo:  all five browsers, no email.
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
        # browsers — lgo on jens, the same five
        roles.librewolf.machines.jens.settings.user     = "lgo";
        roles.firefox.machines.jens.settings.user       = "lgo";
        roles.chromium.machines.jens.settings.user      = "lgo";
        roles.chrome.machines.jens.settings.user        = "lgo";
        roles.edge.machines.jens                        = { };
        # browsers — deck, in birte's Desktop Mode.  Gaming Mode has Steam's
        # own built-in browser; these are for the KDE session behind
        # "Switch to Desktop".  Chromium carries the same hardened flags and
        # managed policies as the laptops (the overlay in lib/overlays.nix
        # now reaches unstable too), and Chrome is here for the same reason
        # it is anywhere — DRM and SSO that Chromium refuses.
        roles.chromium.machines.birte.settings.user     = "deck";
        roles.chrome.machines.birte.settings.user       = "deck";
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
