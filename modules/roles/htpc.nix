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
    case "$mode" in
      # "bigscreen" deliberately lands here too.  If the display manager is
      # running at all then bigscreen is not the active mode — the boot
      # dispatcher stops the DM before starting the container — so reaching
      # this point with mode=bigscreen means something got out of step.
      # Falling back to Plasma leaves a usable desktop on the TV rather than
      # a black screen.
      plasma|bigscreen) exec ${pkgs.kdePackages.plasma-workspace}/bin/startplasma-wayland ;;
      *)                exec /run/current-system/sw/bin/steam-gamescope ;;
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
    runtimeInputs = [ pkgs.systemd ];
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
      if [ "$mode" = bigscreen ]; then
        systemctl stop display-manager.service || true
        exec systemctl start ${bigscreenUnit}
      fi

      ${lib.optionalString cfg.bigscreen.enable ''
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
      exec clanarchy-session-select "''${1:-plasma}"
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
    environment.persistence."/persist".directories = [ stateDir ];

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
      # Ordered *after* the display manager rather than before it.  The DM is
      # pulled in by graphical.target on its own schedule, and there is no
      # ordering that reliably prevents a `wantedBy` unit from starting — so
      # rather than race it for the card, let it start and then stop it.  If
      # graphical.target is never reached (ernst's current posture), an After=
      # on a unit that was never queued is simply a no-op and this still runs.
      after = [ "display-manager.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.systemd ];
      script = ''
        mode="$(cat ${stateFile} 2>/dev/null || echo ${cfg.defaultSession})"
        if [ "$mode" = bigscreen ]; then
          systemctl stop display-manager.service || true
          systemctl start ${bigscreenUnit}
        else
          systemctl stop ${bigscreenUnit} || true
        fi
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
