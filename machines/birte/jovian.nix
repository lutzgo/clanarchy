{ ... }:
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
}
