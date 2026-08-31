{ pkgs, ... }:
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
      desktopSession = "plasma-bigscreen-wayland";
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

  environment.systemPackages = [
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
        desktop|plasma|plasma-wayland|plasma-x11)
          exec ${pkgs.steamos-manager}/bin/steamosctl switch-to-desktop-mode
          ;;
        *)
          exec ${pkgs.holo-session-selection}/bin/holo-session-select "$arg"
          ;;
      esac
    '')
  ];
}
