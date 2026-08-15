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
#   /var/lib/clanarchy-session/current   "gamescope" | "plasma"
#
# The directory is owned by the couch user so the switch needs no root, and a
# polkit rule lets that user restart display-manager.service (and nothing
# else).
{ config, lib, pkgs, ... }:
let
  cfg = config.clanarchy.roles.htpc;

  stateDir = "/var/lib/clanarchy-session";
  stateFile = "${stateDir}/current";

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
      plasma) exec ${pkgs.kdePackages.plasma-workspace}/bin/startplasma-wayland ;;
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
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      mode="''${1:-}"
      case "$mode" in
        gamescope|gamescope-wayland|steamos|gaming) mode=gamescope ;;
        plasma|plasma-wayland|plasma-x11|desktop)   mode=plasma ;;
        *)
          echo "usage: clanarchy-session-select {gamescope|plasma}" >&2
          exit 2
          ;;
      esac

      # The state dir is owned by the HTPC user (tmpfiles rule below), so
      # this deliberately does not need root.
      printf '%s\n' "$mode" > ${stateFile}

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
      type = lib.types.enum [ "gamescope" "plasma" ];
      default = "gamescope";
      description = ''
        Which session to land in when no choice has been made yet — i.e.
        first boot, and after `/persist` is reset. Deck-like behaviour is
        `gamescope`; use `plasma` if the machine should feel like a desktop
        that happens to game.
      '';
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
    # KDE Plasma 6 + SDDM + pipewire + fonts. The role owns the decision;
    # the desktop module owns the implementation.
    clanarchy.desktop.kde.enable = true;

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

    environment.systemPackages = [
      sessionSelect
      steamosShim
      returnLauncher
    ];

    # Owned by the couch user so switching needs no privilege escalation.
    systemd.tmpfiles.rules = [
      "d ${stateDir} 0755 ${cfg.user} ${config.users.users.${cfg.user}.group} -"
    ];

    # Survive impermanence rollback, so the machine comes back up in the
    # session it was left in.
    environment.persistence."/persist".directories = [ stateDir ];

    # Let the couch user restart *only* the display manager. Narrower than
    # adding them to wheel or handing out a blanket systemd sudo rule.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.systemd1.manage-units" &&
            action.lookup("unit") == "display-manager.service" &&
            subject.user == "${cfg.user}") {
          return polkit.Result.YES;
        }
      });
    '';
  };
}
