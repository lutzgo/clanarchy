{
  config,
  lib,
  pkgs,
  ...
}:
#
# Jovian-NixOS wiring for the Steam Deck (OLED / Galileo).
#
# Boot flow:
#   power on → SDDM auto-logs `deck` → gamescope-session → Steam Big Picture
#   "Switch to Desktop" → SDDM → niri (UWSM) + Noctalia
#
# The niri desktop itself (niri, UWSM, Noctalia, pipewire, fonts) is the
# inventory `desktop` service's niri role, as on jens and miralda. SDDM is
# Jovian's.
# `programs.steam` + Proton-GE come from modules/gaming-common.nix.
#
{
  jovian = {
    # Steam Deck hardware: audio DSP, controller firmware, backlight, gyro,
    # jupiter-hw-support helpers. Covers both LCD (Jupiter) and OLED (Galileo)
    # — Jovian detects the model at runtime.
    devices.steamdeck.enable = true;

    steam = {
      enable = true;
      autoStart = true; # boot straight into Gaming Mode
      user = "deck"; # Jovian provisions the `deck` user

      # "Switch to Desktop" lands in niri, through UWSM — the same session
      # jens and miralda log into (niri-uwsm.desktop, from
      # programs.uwsm.waylandCompositors in modules/desktop/niri.nix).
      #
      # steamos-manager accepts any session FILE it can find under
      # $XDG_DATA_DIRS/wayland-sessions (session.rs, valid_desktop_sessions;
      # anything named *gamescope* excluded). The ones registered with the
      # display manager are not on that path by themselves — see
      # environment.systemPackages below.
      #
      # This was Plasma, and before that Plasma Bigscreen, whose controller
      # input died in xdg-desktop-portal 1.22.1 (see docs/history.md).
      desktopSession = "niri-uwsm";
    };

    # Decky Loader — plugin manager for the Steam overlay.
    decky-loader.enable = true;
  };

  # Decky keeps installed plugins and their settings here. Without this the
  # rollback discards every plugin on each boot, and Decky comes back looking
  # freshly installed with no indication why.
  environment.persistence."/persist".directories = ["/var/lib/decky-loader"];

  # Jovian owns the display manager on this machine: SDDM, auto-logging
  # `deck` into gamescope and back into whatever "Switch to Desktop" picked.
  # The niri role's regreet (modules/desktop/desktop-common.nix) would be a
  # second display manager fighting it for the seat.
  services.displayManager.regreet.enable = lib.mkForce false;

  # Every Jovian package below is reached through `pkgs.jovianPackages.*`, not
  # `pkgs.*`.  Jovian moved its whole package set into a `makeScope` namespace
  # (overlay.nix: `jovianPackages = lib.makeScope newScope`) and re-exports
  # nothing at top level, so the short names fail at EVAL with
  # `attribute 'holo-session-selection' missing` — loudly, which is the one
  # mercy here.  Do not "simplify" these back.
  #
  # Steam's in-UI "Switch to Desktop" button shells out to
  # `steamos-session-select`. Jovian no longer ships that name: the script was
  # renamed upstream to `holo-session-select` (pkgs.jovianPackages.holo-session-selection),
  # and switching is now supposed to go through steamos-manager over D-Bus.
  # This Steam client does not use the D-Bus path — it runs the binary
  # unconditionally — so with nothing under the old name the button silently
  # does nothing and Gaming Mode appears to hang:
  #
  #   steam[2135]: sh: line 1: steamos-session-select: command not found
  #
  # holo-session-select is itself Jovian's compatibility shim ("This script is
  # now deprecated, please use steamosctl. It exists for Steam client
  # compatibility"), so this only restores the name in front of it.
  #
  # modules/roles/htpc.nix reimplements this script from scratch for ernst,
  # which is not a Deck and has no Jovian. Here the real thing exists and only
  # needs exposing — do not import the htpc version.

  # Decky shells out to `systemctl`, `killall` and `python3` by bare name, and
  # Jovian's unit sets no PATH of its own, so without this they fail.  `path`
  # is sufficient as of Decky 3.3.0 and was NOT sufficient before it, which is
  # worth recording because the difference cost a day:
  #
  # Up to 3.2.x, `localplatformlinux.run()` defaulted to
  # `env = {"LD_LIBRARY_PATH": ""}` and handed that to
  # `create_subprocess_exec`, REPLACING the environment.  No PATH reached any
  # subprocess, the lookup fell back to `os.defpath` (`:/bin:/usr/bin`), and on
  # NixOS that holds `sh` and `env` and nothing else.  3.3.0 changed the
  # default to `{"PATH": os.getenv("PATH", ""), …}`, so the unit's PATH is
  # finally inherited and this line does what it has always claimed to.
  #
  # Keep `systemd` here.  Jovian's own package only prefixes coreutils and
  # psmisc onto the wrapper, so `killall` arrives from upstream but `systemctl`
  # does not, and `service_active`/`service_restart` are on the path Decky
  # takes whenever it has to recover its injection.
  systemd.services.decky-loader.path = [pkgs.systemd pkgs.python3];

  # A way back to Gaming Mode that does not require a terminal.
  #
  # SteamOS ships a "Return to Gaming Mode" desktop shortcut; Jovian does not.
  # On a Deck with no keyboard attached a terminal is no way out, so this
  # entry — found by Noctalia's launcher — is the way back to Steam without
  # SSH.
  environment.systemPackages = [
    # Every registered session's .desktop file, on $XDG_DATA_DIRS — which is
    # where steamos-manager looks for valid desktop sessions (see
    # jovian.steam.desktopSession above). services.displayManager.sessionPackages
    # (where programs.uwsm registers niri-uwsm.desktop) only reaches SDDM's
    # own SessionDir, so without this jovian-setup-desktop-session fails with
    # "Invalid desktop session niri-uwsm.desktop" on every boot.
    config.services.displayManager.sessionData.desktops

    (pkgs.makeDesktopItem {
      name = "return-to-gaming-mode";
      desktopName = "Return to Gaming Mode";
      comment = "Leave the desktop and go back to Steam Big Picture";
      icon = "steam";
      exec = "steamos-session-select gamescope";
      categories = ["Game"];
    })

    (pkgs.writeShellScriptBin "steamos-session-select" ''
      # holo-session-select understands the SteamOS session names but not the
      # bare "desktop" that older Steam builds pass. Map it to the
      # *non-persistent* Wayland session: "Switch to Desktop" is meant to last
      # until the next boot, matching SteamOS. The -persistent variants also
      # run `set-default-login-mode desktop`, which makes the Deck boot into
      # the desktop from then on — not what the button implies, and easy to
      # trigger by accident.
      #
      # The desktop arms deliberately do NOT go through holo-session-select.
      # Every one of its plasma cases hardcodes plasma.desktop or
      # plasmax11.desktop, which would silently override
      # jovian.steam.desktopSession — and no longer exist here. Calling
      # switch-to-desktop-mode with no argument uses the default session,
      # which jovian-setup-desktop-session sets from that option — so the Nix
      # config stays the single source of truth.
      arg="''${1:-gamescope}"
      case "$arg" in
        gamescope|steamos|gaming)
          exec ${pkgs.jovianPackages.holo-session-selection}/bin/holo-session-select gamescope
          ;;
        desktop|plasma|plasma-wayland|plasma-x11|bigscreen|niri)
          exec ${pkgs.jovianPackages.steamos-manager}/bin/steamosctl switch-to-desktop-mode
          ;;
        *)
          exec ${pkgs.jovianPackages.holo-session-selection}/bin/holo-session-select "$arg"
          ;;
      esac
    '')
  ];
}
