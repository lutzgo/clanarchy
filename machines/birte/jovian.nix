{ lib, pkgs, ... }:
#
# Jovian-NixOS wiring for the Steam Deck (OLED / Galileo).
#
# Boot flow:
#   power on → SDDM auto-logs `deck` → gamescope-session → Steam Big Picture
#   "Switch to Desktop" → SDDM → Plasma 6 session
#
# The KDE Plasma 6 stack itself (SDDM, plasma6, pipewire, fonts) is provided
# by modules/desktop/kde.nix via the inventory `desktop` service (kde role).
# `programs.steam` + Proton-GE come from modules/gaming-common.nix.
#
{
  jovian = {
    # Steam Deck hardware: audio DSP, controller firmware, backlight, gyro,
    # jupiter-hw-support helpers. Covers both LCD (Jupiter) and OLED (Galileo)
    # — Jovian detects the model at runtime.
    devices.steamdeck.enable = true;

    steam = {
      enable    = true;
      autoStart = true;             # boot straight into Gaming Mode
      user      = "deck";           # Jovian provisions the `deck` user

      # "Switch to Desktop" lands in Plasma Bigscreen, not the ordinary Plasma
      # desktop. Bigscreen is a 10-foot shell built for a controller, which is
      # what a Deck has; the pointer-driven desktop is the wrong shape for it.
      #
      # birte can run this natively because it tracks nixpkgs-unstable
      # (clanarchy.channel = "unstable"), where kdePackages.plasma-bigscreen
      # exists at 6.7.4 — the same Plasma generation as the rest of the
      # machine. ernst cannot: it is on stable, so modules/desktop/bigscreen.nix
      # puts Bigscreen in an nspawn container instead. Do not reach for that
      # module here; the container exists solely to work around the channel.
      #
      # The plain Plasma session stays registered (services.desktopManager
      # .plasma6 via the `kde` desktop role) so it can still be picked from
      # SDDM when a real desktop is needed — Bigscreen has no file manager.
      #
      # Deliberately "plasma" and not "plasma-bigscreen-wayland", even though
      # the latter is a registered session and passes Jovian's assertion.
      # steamos-manager keeps its own fixed allowlist —
      # `steamosctl get-valid-desktop-sessions` returns exactly plasma.desktop
      # and plasmax11.desktop — and rejects anything else with
      #
      #   Error: Invalid desktop session plasma-bigscreen-wayland.desktop
      #
      # which makes jovian-setup-desktop-session.service fail on every boot.
      # The value here therefore only has to keep that unit happy; the session
      # actually launched is forced by clanarchy-switch-to-desktop below.
      desktopSession = "plasma";
    };

    # Decky Loader — plugin manager for the Steam overlay.
    decky-loader.enable = true;
  };

  # Decky keeps installed plugins and their settings here. Without this the
  # rollback discards every plugin on each boot, and Decky comes back looking
  # freshly installed with no indication why.
  environment.persistence."/persist".directories = [ "/var/lib/decky-loader" ];

  # Registers plasma-bigscreen-wayland.desktop with the display manager.
  # jovian.steam.desktopSession is validated against
  # services.displayManager.sessionData.sessionNames, so without this the
  # setting above fails to evaluate rather than silently doing nothing.
  # Bigscreen is registered and selectable from SDDM, but it is NOT what
  # "Switch to Desktop" lands in.
  #
  # It runs and renders fine here, but its only input bridge is broken:
  # plasma-bigscreen-inputhandler reads the D-pad and sticks correctly and
  # maps them to keycodes, then injects them through the XDG RemoteDesktop
  # portal — which Bigscreen hardcodes via PLASMA_INTEGRATION_USE_PORTAL=1.
  # xdg-desktop-portal 1.22.1 then drops every event on an internal
  # assertion:
  #
  #   xdg-desktop-portal: g_hash_table_lookup: assertion 'hash_table != NULL'
  #
  # firing once per keypress. The result is a shell navigable only by
  # touchscreen, since touch goes straight to KWin and never enters the
  # portal. That is upstream, not configuration — see docs/roadmap.md.
  #
  # An earlier revision shadowed plasma.desktop with Bigscreen so that
  # steamos-manager's fixed allowlist would land there. That worked, and is
  # the technique to restore once the portal is fixed; it is reverted rather
  # than left in place because a session nobody can navigate is worse than
  # the plain desktop.
  services.displayManager.sessionPackages = [ pkgs.kdePackages.plasma-bigscreen ];

  # Steam's in-UI "Switch to Desktop" button shells out to
  # `steamos-session-select`. Jovian no longer ships that name: the script was
  # renamed upstream to `holo-session-select` (pkgs.holo-session-selection),
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
  # Decky shells out to `systemctl` and `python3` by bare name, but Jovian's
  # unit sets no PATH, so both fail at startup:
  #
  #   [helpers][WARNING]: Failed to execute get_system_pythonpaths():
  #     [Errno 2] No such file or directory: 'python3'
  #   FileNotFoundError: [Errno 2] No such file or directory: 'systemctl'
  #
  # The loader survives and serves plugins, but its service_stop/service_active
  # helpers are dead, so anything Decky wants to restart silently does nothing.
  systemd.services.decky-loader.path = [ pkgs.systemd pkgs.python3 ];

  # A way back to Gaming Mode that does not require a terminal.
  #
  # SteamOS ships a "Return to Gaming Mode" desktop shortcut; Jovian does not,
  # and neither does anything else here — ~deck/Desktop is empty. In Plasma
  # that is merely annoying, since Konsole can run steamos-session-select.
  # In Bigscreen it is a trap: there is no terminal and no file manager, so
  # without this entry the only way out is SSH.
  environment.systemPackages = [
    # Not redundant with sessionPackages above: that only registers the
    # .desktop file, it does not put anything on PATH. plasma-bigscreen-wayland
    # is a shell script whose first line is
    #
    #   . plasma-bigscreen-common-env
    #
    # sourced by bare name, and it calls its other helpers the same way. With
    # the package off PATH that source fails, the script exits immediately,
    # and SDDM logs a session that starts and closes in the same second with
    # no error of its own — a black screen with nothing to go on.
    pkgs.kdePackages.plasma-bigscreen

    # Bigscreen's homescreen applet — its entire main UI — imports the
    # org.kde.kdeconnect QML module in the header, and one missing module
    # takes the whole shell down:
    #
    #   error when loading applet "org.kde.bigscreen.homescreen"
    #     HomeHeader.qml: Type Indicators.KdeConnect unavailable
    #     KdeConnect.qml: module "org.kde.kdeconnect" is not installed
    #
    # plasma-bigscreen does not depend on it, so it has to be installed
    # alongside. This is the QML module, not the phone-pairing feature —
    # unrelated to clanarchy.apps.communication's Valent on other machines.
    pkgs.kdePackages.kdeconnect-kde

    (pkgs.makeDesktopItem {
      name = "return-to-gaming-mode";
      desktopName = "Return to Gaming Mode";
      comment = "Leave the desktop and go back to Steam Big Picture";
      icon = "steam";
      exec = "steamos-session-select gamescope";
      categories = [ "Game" ];
      # Bigscreen's launcher only lists applications that declare themselves
      # for it; without this the entry is invisible in exactly the session
      # that most needs it.
      extraConfig.X-KDE-PluginInfo-Category = "Application";
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
      # jovian.steam.desktopSession and land in the ordinary Plasma desktop
      # instead of Bigscreen. Calling switch-to-desktop-mode with no argument
      # uses the default session, which jovian-setup-desktop-session sets from
      # that option — so the Nix config stays the single source of truth.
      arg="''${1:-gamescope}"
      case "$arg" in
        gamescope|steamos|gaming)
          exec ${pkgs.holo-session-selection}/bin/holo-session-select gamescope
          ;;
        desktop|plasma|plasma-wayland|plasma-x11|bigscreen)
          # plasma.desktop *is* Bigscreen (see sessionPackages above), so the
          # ordinary switch lands in the right place and needs no special
          # casing here.
          exec ${pkgs.steamos-manager}/bin/steamosctl switch-to-desktop-mode
          ;;
        *)
          exec ${pkgs.holo-session-selection}/bin/holo-session-select "$arg"
          ;;
      esac
    '')
  ];
}
