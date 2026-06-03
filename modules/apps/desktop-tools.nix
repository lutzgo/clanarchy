{ config, lib, pkgs, ... }:
let cfg = config.clanarchy.apps.desktopTools;
in {
  options.clanarchy.apps.desktopTools.enable =
    lib.mkEnableOption "desktop utility apps (terminal, fastfetch, document tools, color calibration, LibreOffice)";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      foot          # Wayland terminal emulator
      fastfetch     # system info
      libreoffice

      # Document tools
      gnome-decoder # QR code scanner
      pdfarranger   # PDF manipulation
      ocrmypdf      # OCR + PDF
      normcap       # OCR screen capture

      # Wayland utilities
      wtype         # keyboard input injection (xdotool equivalent for Wayland)
      xdg-utils
    ];
  };
}
