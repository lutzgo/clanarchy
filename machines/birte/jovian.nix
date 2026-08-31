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
      enable         = true;
      autoStart      = true;        # boot straight into Gaming Mode
      desktopSession = "plasma";    # matches services.desktopManager.plasma6
      user           = "deck";      # Jovian provisions the `deck` user
    };

    # Decky Loader — plugin manager for the Steam overlay.
    decky-loader.enable = true;
  };

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
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "steamos-session-select" ''
      # holo-session-select understands the SteamOS session names but not the
      # bare "desktop" that older Steam builds pass. Map it to the
      # *non-persistent* Wayland session: "Switch to Desktop" is meant to last
      # until the next boot, matching SteamOS. The -persistent variants also
      # run `set-default-login-mode desktop`, which makes the Deck boot into
      # KDE from then on — not what the button implies, and easy to trigger by
      # accident. Anything else Steam passes goes through untouched.
      arg="''${1:-gamescope}"
      case "$arg" in
        desktop) arg=plasma-wayland ;;
      esac
      exec ${pkgs.holo-session-selection}/bin/holo-session-select "$arg"
    '')
  ];
}
