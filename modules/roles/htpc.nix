# HTPC role — couch machine: boots into Steam Big Picture, switches to a
# KDE Plasma desktop and back.  The Steam Deck experience on ordinary
# hardware.
#
# ── Why this is not Jovian ────────────────────────────────────────────────
# Jovian-NixOS is Steam *Deck hardware* enablement (Deck kernel, OLED
# panel, controller, power, firmware) and upstream supports only
# nixos-unstable.  Gaming Mode itself is not Jovian's: nixpkgs 26.05 ships
# `programs.steam.gamescopeSession`, which registers a gamescope-driven
# Steam session with the display manager.  A desktop HTPC needs the
# session, not the Deck hardware — so this role runs entirely on the
# fleet's stable channel and stays compatible with ZFS.  birte still uses
# Jovian because birte really is a Deck.
#
# ── What Jovian *does* provide that we reimplement ────────────────────────
# `steamos-session-select`, the helper behind Steam's in-UI "Switch to
# Desktop" button.  It is not in nixpkgs (checked 26.05: absent from both
# nixos/modules and pkgs).  Rather than adopting Jovian for one script, the
# role ships its own — see the session plumbing below.
#
# ── How switching works ───────────────────────────────────────────────────
# `services.displayManager.defaultSession` is evaluated at build time, so it
# cannot be flipped at runtime.  Instead the display manager is pointed at a
# single wrapper session, `clanarchy-htpc`, whose Exec reads a state file and
# execs either the gamescope Steam session or Plasma.  Switching is then
# "write the file, restart the display manager" — the same shape as SteamOS.
#
#   /var/lib/clanarchy-session/current   "gamescope" | "plasma" | "bigscreen"
#
# The directory is owned by the couch user so the switch needs no root, and a
# polkit rule lets that user restart display-manager.service (and nothing
# else).
#
# ── The third mode: bigscreen ─────────────────────────────────────────────
# "bigscreen" is not a display-manager session.  Plasma Bigscreen only exists
# on nixpkgs-unstable, and its Plasma generation cannot share a system with
# the 6.6.6 one this machine runs — see modules/desktop/bigscreen.nix for the
# full reasoning — so it lives in an nspawn container that owns the TV GPU
# outright.  Selecting it therefore means "stop the display manager, start
# the container" rather than "exec a different session binary", and the two
# arms are mutually exclusive because both want KMS on the same card.
{ config, lib, pkgs, ... }:
let
  cfg = config.clanarchy.roles.htpc;

  stateDir = "/var/lib/clanarchy-session";
  stateFile = "${stateDir}/current";

  # Presence of this file means "bigscreen is the active mode".
  #
  # It exists so the display manager can be kept from starting *at all* in
  # that mode, via ConditionPathExists below.  The alternative — letting the
  # DM start and having the boot dispatcher stop it again — races with
  # autologin and shows a Plasma session flashing up on the TV before it is
  # torn down.  A condition is evaluated at unit start, so the DM is simply
  # skipped instead.
  flagFile = "${stateDir}/bigscreen-active";

  # Drop-box the Bigscreen container writes into to ask for a session change.
  #
  # The container has no route to host systemd, and giving it one (the host
  # D-Bus socket, or systemctl over the boundary) would hand it far more than
  # "switch my session".  Instead the only thing that crosses is a short
  # string in a file on the already-shared state directory; the host reads it,
  # validates it against the same three names the switcher accepts, and acts.
  requestFile = "${stateDir}/request";

  # The nspawn unit backing the "bigscreen" mode. Named here so the switcher,
  # the boot dispatcher and the polkit rule cannot drift apart.
  bigscreenUnit = "container@${config.clanarchy.desktop.bigscreen.containerName}.service";

  # The exact set of units the couch user may start/stop. Kept as a list so
  # the polkit rule below is a membership test rather than a growing chain of
  # string comparisons.
  manageableUnits = [
    "display-manager.service"
  ]
  ++ lib.optional cfg.bigscreen.enable bigscreenUnit;

  # Wait for the TV before handing the card to a compositor.
  #
  # gamescope opens the DRM node of the GPU it selects, and if that card has no
  # connected connector it fails backend creation and then segfaults on the way
  # out.  Verified on ernst 2026-08-19, three times in a row:
  #
  #   drm: opening DRM node '/dev/dri/card1'
  #   drm:   HDMI-A-1 (disconnected)     [DP-1..3 likewise]
  #   drm: cannot find any connected connector!
  #   Error drm: Failed to find a primary plane
  #   Failed to create backend.
  #   steam-gamescope: … Segmentation fault (core dumped)
  #
  # A TV that is switched off — or showing another input — drops HPD, so the
  # connector really does read `disconnected`.  That is the ordinary resting
  # state of a living-room machine, not an edge case, and it must not be what
  # decides whether the machine has a session.  Without this the session exits
  # in under a second, SDDM falls back to the greeter, and the TV shows a login
  # form forever after — the couch user never gets Big Picture at all.
  #
  # Waiting holds the VT instead, and Big Picture starts the moment the TV
  # wakes.  It applies to every arm: Plasma's kwin has no more to do with a
  # card that has no output than gamescope does.
  #
  # The card is resolved from the PCI address at RUNTIME and never from a cardN
  # name: numbering on this board is inverted (the dGPU is card1) and can flip
  # on a kernel bump — the same reason machines/ernst/containers/jellyfin.nix
  # pins the iGPU by PCI path.
  #
  # Fail-open when the address resolves to no DRM card: that is a configuration
  # error rather than a dark TV, and blocking on it would turn a typo into a
  # machine with neither a session nor a greeter.  Start, fail visibly, and let
  # the relogin loop below make the failure repeat where it can be read.
  waitForDisplay = lib.optionalString (cfg.display.gpuPciAddress != null) ''
    drmDir=/sys/bus/pci/devices/${cfg.display.gpuPciAddress}/drm
    set -- "$drmDir"/card[0-9]*
    if [ ! -d "$1" ]; then
      printf 'clanarchy-session: no DRM card at PCI %s — starting anyway\n' \
        '${cfg.display.gpuPciAddress}' >&2
    else
      card=$1
      waited=0
      until [ -n "''${connected:-}" ]; do
        for statusFile in "$card"/*/status; do
          [ -e "$statusFile" ] || continue
          [ "$(< "$statusFile")" = connected ] && connected=yes
        done
        [ -n "''${connected:-}" ] && break
        if [ $(( waited % 60 )) -eq 0 ]; then
          printf 'clanarchy-session: no connected output on %s — waiting for the TV\n' \
            "$card" >&2
        fi
        ${pkgs.coreutils}/bin/sleep 2
        waited=$(( waited + 2 ))
      done
    fi
  '';

  # Runtime session dispatcher.  Runs as the logged-in user; only reads.
  #
  # `steam-gamescope` is referenced through /run/current-system/sw/bin rather
  # than by store path on purpose: nixpkgs builds it as a private `let`
  # binding inside programs/steam.nix and only exposes it by appending it to
  # environment.systemPackages when gamescopeSession.enable is set.  It is
  # NOT part of `programs.steam.package` — pointing there yields a path that
  # does not exist, and the session fails to start.  The system profile is
  # the only stable handle we get.
  sessionRun = pkgs.writeShellScript "clanarchy-session-run" ''
    set -eu
    mode="$(cat ${stateFile} 2>/dev/null || echo ${cfg.defaultSession})"
    ${waitForDisplay}
    case "$mode" in
      ${
        # "bigscreen" lands on Plasma only while that arm is actually built.
        # If the display manager is running at all then bigscreen is not the
        # active mode — the boot dispatcher stops the DM before starting the
        # container — so reaching this point with mode=bigscreen means
        # something got out of step, and Plasma is a usable desktop rather
        # than a black screen.
        #
        # With the arm not built, a recorded "bigscreen" is stale state from
        # when it was (the value survives in /persist), and honouring it would
        # land the couch user in a mouse-and-keyboard desktop on a machine
        # configured to boot into Big Picture.  Let it fall through to the
        # default instead.
        if cfg.bigscreen.enable then "plasma|bigscreen)" else "plasma)"
      } exec ${pkgs.kdePackages.plasma-workspace}/bin/startplasma-wayland ;;
      *)      exec /run/current-system/sw/bin/steam-gamescope ;;
    esac
  '';

  # One wrapper session for the display manager to target.
  sessionFile =
    (pkgs.writeTextDir "share/wayland-sessions/clanarchy-htpc.desktop" ''
      [Desktop Entry]
      Name=Clanarchy HTPC
      Comment=Steam Big Picture or Plasma, selected at runtime
      Exec=${sessionRun}
      Type=Application
    '').overrideAttrs
      (_: { passthru.providedSessions = [ "clanarchy-htpc" ]; });

  # The switcher.  Accepts our own names plus the ones SteamOS uses, so the
  # same binary can back the `steamos-session-select` shim below.
  sessionSelect = pkgs.writeShellApplication {
    name = "clanarchy-session-select";
    # coreutils for touch/rm on the flag file. Not optional: this is also
    # invoked from clanarchy-session-request.service, whose PATH is systemd's
    # minimal one rather than a login shell's.
    runtimeInputs = [ pkgs.systemd pkgs.coreutils ];
    text = ''
      mode="''${1:-}"
      case "$mode" in
        gamescope|gamescope-wayland|steamos|gaming) mode=gamescope ;;
        plasma|plasma-wayland|plasma-x11|desktop)   mode=plasma ;;
        ${
          # Only accept "bigscreen" when the container was actually built —
          # otherwise the switcher would happily record a mode whose unit
          # does not exist and leave the machine with no session at all.
          lib.optionalString cfg.bigscreen.enable ''
            bigscreen|tv|mediacenter)                   mode=bigscreen ;;
          ''
        }
        *)
          echo "usage: clanarchy-session-select {gamescope|plasma${
            lib.optionalString cfg.bigscreen.enable "|bigscreen"
          }}" >&2
          exit 2
          ;;
      esac

      # The state dir is owned by the HTPC user (tmpfiles rule below), so
      # this deliberately does not need root.
      printf '%s\n' "$mode" > ${stateFile}

      # The display manager and the Bigscreen container both want KMS on the
      # TV's GPU, so exactly one of them may run.  Whichever we are leaving
      # is stopped first and allowed to release the card before the other is
      # started — hence stop/start rather than a single restart on this path.
      #
      # The flag file is what keeps the two apart across reboots: while it
      # exists the display manager's start condition fails, so nothing else
      # has to remember to hold it back.
      if [ "$mode" = bigscreen ]; then
        touch ${flagFile}
        systemctl stop display-manager.service || true
        exec systemctl start ${bigscreenUnit}
      fi

      ${lib.optionalString cfg.bigscreen.enable ''
        rm -f ${flagFile}
        systemctl stop ${bigscreenUnit} || true
      ''}

      # Restarting the display manager tears down the current session —
      # this is how SteamOS does it too, and why the write happens first.
      exec systemctl restart display-manager.service
    '';
  };

  # Steam's Big Picture "Switch to Desktop" button shells out to
  # `steamos-session-select`.  Provide it under that name so the in-UI
  # button works instead of only our own launcher.
  steamosShim = pkgs.writeShellApplication {
    name = "steamos-session-select";
    runtimeInputs = [ sessionSelect ];
    text = ''
      # Steam passes "plasma" / "plasma-wayland" / "desktop" here; anything
      # we don't recognise falls through to the usage error.
      mode="''${1:-desktop}"
      ${lib.optionalString cfg.bigscreen.enable ''
        # With the Bigscreen arm built, "leave Gaming Mode" should land on the
        # TV shell rather than a mouse-and-keyboard Plasma desktop — Steam's
        # own "Switch to Desktop" button is the only in-UI exit from Big
        # Picture, and on a couch machine the thing you want on the other side
        # of it is Bigscreen.  Plain Plasma is still reachable deliberately,
        # via `clanarchy-session-select plasma`.
        case "$mode" in
          plasma|plasma-wayland|plasma-x11|desktop) mode=bigscreen ;;
        esac
      ''}
      exec clanarchy-session-select "$mode"
    '';
  };

  # Desktop-mode launcher for the trip back, so returning to Gaming Mode
  # doesn't require a terminal.
  returnLauncher = pkgs.makeDesktopItem {
    name = "clanarchy-return-to-gaming";
    desktopName = "Return to Gaming Mode";
    comment = "Restart into the Steam Big Picture session";
    icon = "steam";
    exec = "${sessionSelect}/bin/clanarchy-session-select gamescope";
    categories = [ "Game" ];
  };
in
{
  imports = [
    ../desktop/kde.nix
    ../desktop/bigscreen.nix
    ../gaming-common.nix
  ];

  options.clanarchy.roles.htpc = {
    enable = lib.mkEnableOption "HTPC role (Steam Big Picture + Plasma with runtime session switching)";

    user = lib.mkOption {
      type = lib.types.str;
      description = ''
        The couch user. Owns the session state directory and is the one
        permitted to restart the display manager, so it must be a real
        declared NixOS user.
      '';
      example = "htpc";
    };

    defaultSession = lib.mkOption {
      type = lib.types.enum [ "gamescope" "plasma" "bigscreen" ];
      default = "gamescope";
      description = ''
        Which session to land in when no choice has been made yet — i.e.
        first boot, and after `/persist` is reset. Deck-like behaviour is
        `gamescope`; use `plasma` if the machine should feel like a desktop
        that happens to game, or `bigscreen` for a TV media appliance.

        `bigscreen` requires `bigscreen.enable`.
      '';
    };

    display.gpuPciAddress = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "0000:03:00.0";
      description = ''
        PCI address of the GPU the TV hangs off.

        When set, the session waits for a connected connector on that card
        before starting a compositor, instead of starting one against a card
        with no output — which gamescope answers with a failed backend and a
        segfault, and which then drops the machine to a login screen it will
        never leave on its own.

        Find it with `lspci -D | grep VGA`, and confirm which card actually
        drives the TV with:

        ```
        for c in /sys/class/drm/card*-*/; do
          printf '%s %s\n' "$(basename "$c")" "$(cat "$c/status")"
        done
        ```

        Deliberately a PCI address and not a `cardN` name: numbering is not
        stable across kernel bumps, and on a two-GPU box a flip would point
        this at the wrong head.

        Leave null on a machine with a single GPU and a permanently attached
        display; the wait is then skipped entirely.
      '';
    };

    bigscreen = {
      enable = lib.mkEnableOption ''
        the Plasma Bigscreen mode, run from an nspawn container carrying its
        own nixpkgs channel.

        Off by default because it is a heavier proposition than the other two
        arms: it builds a second, complete Plasma generation from
        nixpkgs-unstable (see modules/desktop/bigscreen.nix for why it cannot
        share the host's), and it takes exclusive KMS ownership of the TV's
        GPU while active
      '';

      gpu.pciAddress = lib.mkOption {
        type = lib.types.str;
        description = ''
          PCI address of the GPU driving the TV — passed straight through to
          `clanarchy.desktop.bigscreen.gpu.pciAddress`, which documents how
          to find it.
        '';
        example = "0000:03:00.0";
      };

      uid = lib.mkOption {
        type = lib.types.int;
        description = ''
          Numeric uid of the couch user. Must match the host's, since nspawn
          does not remap ids across the bind-mounted home.
        '';
        example = 1001;
      };

      gid = lib.mkOption {
        type = lib.types.int;
        default = 100;
        description = "Numeric primary gid of the couch user. Same matching requirement as `uid`.";
      };

      extraPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = ''
          Applications to install inside the container. Must come from
          `pkgs-unstable`, not the host's `pkgs` — see the corresponding
          option in modules/desktop/bigscreen.nix.
        '';
        example = lib.literalExpression "[ pkgs-unstable.jellyfin-media-player ]";
      };
    };

    mediaClient = {
      enable =
        lib.mkEnableOption "a couch media client alongside the gaming session"
        // { default = true; };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.jellyfin-media-player;
        defaultText = lib.literalExpression "pkgs.jellyfin-media-player";
        description = ''
          Media client to install. Defaults to Jellyfin Media Player, which
          has its own 10-foot TV interface and talks to the Jellyfin server
          ernst already runs in an nspawn container.

          Plasma Bigscreen would have been the obvious "KDE for TV" answer
          but is not packaged in 26.05 — the top-level attribute is a
          throwing alias pointing at `kdePackages.plasma-bigscreen`, which
          does not exist. So the 10-foot UI is Steam Big Picture, with this
          client added to it as a launcher entry (see the note below).
        '';
      };
    };

    controller.enable =
      lib.mkEnableOption ''
        wireless Xbox controller support — Bluetooth plus the xpadneo driver.

        Wired controllers already work without this: xpad is in-tree and
        `hardware.steam-hardware.enable` (which programs.steam brings in)
        ships the udev rules. This is for Xbox One S / Series pads over
        Bluetooth, which the in-tree driver handles poorly — xpadneo is what
        gives correct button mapping, rumble and battery reporting.

        Worth a deliberate look on a machine that is also a NAS: it puts a
        Bluetooth stack on the box, which is attack surface that was not
        there before. The radio is host hardware and the driver is a kernel
        module, so neither can live in a container — only the *use* of the
        controller does, via /dev/input

        This is the software half only, and it cannot conjure a working
        radio. ernst's onboard MediaTek MT7927 has no Bluetooth support on
        the current kernel and no firmware blob published, so a USB dongle
        (or a cable) is what actually carries a pad there — see
        docs/guides/htpc-controllers.md
      ''
      // {
        default = true;
      };

    autologin.enable = lib.mkEnableOption ''
      passwordless autologin for the couch user.

      Off by default, and worth a deliberate decision: on a machine that
      also serves a NAS, autologin means anyone with physical access lands
      in a logged-in session with that user's rights. Enable it for the
      living-room-appliance feel; leave it off to keep a login prompt in
      front of the array
    '';
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.defaultSession == "bigscreen" -> cfg.bigscreen.enable;
        message = ''
          clanarchy.roles.htpc.defaultSession = "bigscreen" requires
          clanarchy.roles.htpc.bigscreen.enable = true — otherwise the
          container the boot dispatcher would start does not exist.
        '';
      }
    ];

    # KDE Plasma 6 + SDDM + pipewire + fonts. The role owns the decision;
    # the desktop module owns the implementation.
    clanarchy.desktop.kde.enable = true;

    # Bigscreen mode. The role holds the couch-user identity; the desktop
    # module owns the container and the GPU plumbing.
    clanarchy.desktop.bigscreen = lib.mkIf cfg.bigscreen.enable {
      enable = true;
      user = cfg.user;
      inherit (cfg.bigscreen)
        uid
        gid
        extraPackages
        ;
      gpu.pciAddress = cfg.bigscreen.gpu.pciAddress;
    };

    # Wireless controller support.
    #
    # xpadneo is a kernel module and the radio is host hardware, so both are
    # necessarily host-side even though the session that consumes the pad may
    # be containerised: a container shares the host kernel and cannot load a
    # driver of its own. What crosses the boundary is the resulting evdev
    # node — /dev/input is already bound into the Bigscreen container, so a
    # controller paired here shows up there with no further plumbing.
    hardware.bluetooth = lib.mkIf cfg.controller.enable {
      enable = true;
      # A TV appliance should not need someone to run `bluetoothctl power on`
      # after every reboot before the pad works.
      powerOnBoot = true;
    };

    hardware.xpadneo.enable = lib.mkIf cfg.controller.enable true;

    # Steam + Proton-GE.  `persistenceDirectories` keeps its default
    # ([ ".steam" ]): HTPC machines are impermanent like the rest of the
    # fleet — home is rolled back on boot — so the Steam runtime bootstrap
    # genuinely does need declaring.  The remaining per-user paths
    # (.config, .local/share, .local/state, .cache) are declared by the
    # machine's user module, which is also where the library symlink lives.
    clanarchy.gaming = {
      enable = true;
      user = cfg.user;
    };

    # The stock gamescope Steam session from nixpkgs — no Jovian.
    programs.steam.gamescopeSession.enable = true;

    # Steam and Proton are unfree.  birte gets this from the pkgs instance
    # built in lib/mk-machine.nix (`allowUnfree = true` baked in), but HTPC
    # machines run on the stable channel where nothing sets it.
    #
    # A predicate rather than a blanket `allowUnfree`: this role is expected
    # to land on otherwise-headless boxes (ernst fronts the NAS array), and
    # "we needed Steam" shouldn't quietly open the whole machine to unfree
    # packages.  Extend the list when a genuinely required package is
    # rejected, rather than widening to allowUnfree.
    #
    # NOTE: `nixpkgs.config` cannot be set on machines using
    # `clanarchy.channel = "unstable"` (an externally-created pkgs instance
    # trips a NixOS assertion), so this role and that option are mutually
    # exclusive by construction.
    nixpkgs.config.allowUnfreePredicate =
      pkg:
      builtins.elem (lib.getName pkg) [
        "steam"
        "steam-unwrapped"
        "steam-original"
        "steam-run"
        "steam-jupiter-unwrapped"
        "proton-ge-bin"
      ];

    # Point the display manager at the wrapper session rather than at
    # "steam" or "plasma" directly; the wrapper decides at launch.
    services.displayManager.sessionPackages = [ sessionFile ];
    services.displayManager.defaultSession = "clanarchy-htpc";

    services.displayManager.autoLogin = lib.mkIf cfg.autologin.enable {
      enable = true;
      user = cfg.user;
    };

    # Autologin again when a session ends, rather than once per display-manager
    # start.
    #
    # SDDM's default (Relogin=false) is right for a desktop: log out, get the
    # greeter. On an appliance it is a one-way door — any session exit, whether
    # a crash or Steam's own "Exit" item, parks the TV on a login form that
    # nobody in the living room has a keyboard for, and it stays there until
    # someone SSHes in and restarts the display manager. That is exactly what
    # ernst was found doing on 2026-08-19: autologin had worked, the session
    # died against a dark TV, and the greeter sat on tty1 for hours.
    #
    # Paired with waitForDisplay above, which is what keeps this from becoming
    # a hot crash-relogin loop while the TV is off — the session blocks instead
    # of exiting, so there is nothing to relogin.
    services.displayManager.sddm.autoLogin.relogin = lib.mkIf cfg.autologin.enable true;

    # The media client is installed system-wide (not just into the session)
    # so it shows up in Plasma's launcher too, and so Steam's "Add a
    # Non-Steam Game" browser can find it on PATH.
    #
    # NOTE — one manual step: Steam stores non-Steam shortcuts in
    # `shortcuts.vdf`, a *binary* VDF blob inside the user's Steam data dir.
    # Generating that declaratively is possible but brittle across Steam
    # versions, so the launcher entry is added once by hand from Big
    # Picture (Library → Add a Non-Steam Game → Jellyfin Media Player).  It
    # survives reboots because `.local/share` is persisted for the couch
    # user — see the machine's user module.
    environment.systemPackages = [
      sessionSelect
      steamosShim
      returnLauncher
    ] ++ lib.optional cfg.mediaClient.enable cfg.mediaClient.package;

    # Owned by the couch user so switching needs no privilege escalation.
    systemd.tmpfiles.rules = [
      "d ${stateDir} 0755 ${cfg.user} ${config.users.users.${cfg.user}.group} -"
    ];

    # Survive impermanence rollback, so the machine comes back up in the
    # session it was left in.
    environment.persistence."/persist".directories = [
      stateDir
    ]
    # Controller pairings. This machine rolls its root back on every boot, so
    # without persisting them the pad would have to be re-paired after each
    # reboot — exactly the papercut impermanence is meant to make you notice
    # once and then fix for good.
    ++ lib.optional cfg.controller.enable "/var/lib/bluetooth";

    # Boot dispatcher.
    #
    # The other two arms are display-manager sessions, so graphical.target
    # brings them up on its own.  Bigscreen is a container that must instead
    # replace the display manager, and `services.displayManager.defaultSession`
    # is a build-time value that cannot express "no DM at all today".  So the
    # choice is re-applied once at boot from the same state file the switcher
    # writes, which also makes the machine come back up in the mode it was
    # left in after a reboot.
    systemd.services.clanarchy-htpc-boot = lib.mkIf cfg.bigscreen.enable {
      description = "Apply the persisted HTPC session choice at boot";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-user-sessions.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.systemd pkgs.coreutils ];
      # Only has to handle the container half now.  The display manager takes
      # care of itself: its start condition tests the same flag file, so in
      # bigscreen mode it is skipped rather than started-and-stopped, and this
      # no longer has to race it.
      script = ''
        mode="$(cat ${stateFile} 2>/dev/null || echo ${cfg.defaultSession})"

        # Reconcile the flag with the recorded mode, so a hand-edited state
        # file or a first boot with defaultSession = "bigscreen" still lines up.
        if [ "$mode" = bigscreen ]; then
          touch ${flagFile}
          systemctl start ${bigscreenUnit}
        else
          rm -f ${flagFile}
          systemctl stop ${bigscreenUnit} || true
        fi
      '';
    };

    # The display manager must not run while Bigscreen owns the GPU.
    #
    # A failed condition is not a failed unit: systemd records
    # "Condition check resulted in ... being skipped" and moves on, so
    # graphical.target still completes and nothing shows up in
    # `systemctl --failed`.
    systemd.services.display-manager.unitConfig =
      lib.mkIf cfg.bigscreen.enable { ConditionPathExists = "!${flagFile}"; };

    # Host-side listener for session-change requests from inside the container.
    #
    # A path unit rather than a socket: the payload is one short word, the
    # writer is an unprivileged desktop launcher with no networking, and a
    # file on a directory both sides already share needs no new plumbing.
    systemd.paths.clanarchy-session-request = lib.mkIf cfg.bigscreen.enable {
      description = "Watch for session-change requests from the Bigscreen container";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathChanged = requestFile;
        # The request file lives in a directory the couch user owns, so it may
        # legitimately not exist yet at boot.
        MakeDirectory = false;
      };
    };

    systemd.services.clanarchy-session-request = lib.mkIf cfg.bigscreen.enable {
      description = "Apply a session-change request from the Bigscreen container";
      path = [ pkgs.coreutils ];
      serviceConfig.Type = "oneshot";
      # Runs as root, so no polkit hop — but it only ever passes the request
      # through the same switcher the couch user could have called directly,
      # which rejects anything outside the known session names. The container
      # gains no capability it did not already have from a host login; it just
      # gains a way to ask from where it actually is.
      script = ''
        req="$(cat ${requestFile} 2>/dev/null || true)"
        : > ${requestFile} || true

        [ -n "$req" ] || exit 0
        exec ${sessionSelect}/bin/clanarchy-session-select "$req"
      '';
    };

    # Let the couch user manage *only* the display manager and, when the
    # bigscreen arm is built, its container. Narrower than adding them to
    # wheel or handing out a blanket systemd sudo rule.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        var allowed = ${builtins.toJSON manageableUnits};
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            allowed.indexOf(action.lookup("unit")) !== -1 &&
            subject.user == "${cfg.user}") {
          return polkit.Result.YES;
        }
      });
    '';
  };
}
