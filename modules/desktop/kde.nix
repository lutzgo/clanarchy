{ config, lib, pkgs, ... }:
{
  options.clanarchy.desktop.kde = {
    enable = lib.mkEnableOption "KDE Plasma 6 desktop environment";

    fprintd.enable = lib.mkEnableOption "fingerprint authentication via fprintd";
  };

  config = lib.mkIf config.clanarchy.desktop.kde.enable {

    # KDE Plasma 6 — Wayland session via SDDM
    services.displayManager.sddm = {
      enable         = true;
      wayland.enable = true;
    };
    services.desktopManager.plasma6.enable = true;

    # NetworkManager
    networking.networkmanager.enable = true;

    # Pipewire audio
    security.rtkit.enable = true;
    services.pipewire = {
      enable            = true;
      alsa.enable       = true;
      alsa.support32Bit = true;
      pulse.enable      = true;
    };

    # UPower — battery / power status in Plasma panel
    services.upower.enable = true;

    # Optional fingerprint auth
    services.fprintd.enable                  = lib.mkDefault config.clanarchy.desktop.kde.fprintd.enable;
    security.pam.services.login.fprintAuth   = lib.mkIf config.clanarchy.desktop.kde.fprintd.enable true;
    security.pam.services.sddm.fprintAuth    = lib.mkIf config.clanarchy.desktop.kde.fprintd.enable true;
    security.pam.services.sudo.fprintAuth    = lib.mkIf config.clanarchy.desktop.kde.fprintd.enable true;

    # Fonts — same set as Niri machines for consistency
    fonts.packages = with pkgs; [
      nerd-fonts.monaspace
      noto-fonts
      noto-fonts-color-emoji
      inter
    ];
    fonts.fontconfig = {
      defaultFonts = {
        monospace = [ "MonaspiceAr Nerd Font Mono" "Noto Sans Mono" ];
        sansSerif = [ "Inter"                       "Noto Sans"      ];
        serif     = [ "MonaspiceXe Nerd Font Propo" "Noto Serif"     ];
        emoji     = [ "Noto Color Emoji" ];
      };
      hinting  = { enable = true; style = "slight"; };
      subpixel = { rgba = "rgb"; lcdfilter = "default"; };
    };

    environment.variables = {
      XCURSOR_SIZE   = "24";
      XCURSOR_THEME  = "Adwaita";
      NIXOS_OZONE_WL = "1";
    };
  };
}
