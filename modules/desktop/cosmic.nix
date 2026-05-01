{ config, lib, pkgs, ... }:
{
  options.clanarchy.desktop.cosmic = {
    enable = lib.mkEnableOption "COSMIC desktop environment";

    fprintd.enable = lib.mkEnableOption "fingerprint authentication via fprintd";
  };

  config = lib.mkIf config.clanarchy.desktop.cosmic.enable {

    # COSMIC desktop (provided by the nixos-cosmic flake module imported in flake.nix)
    services.desktopManager.cosmic.enable = true;

    # Binary cache for pre-built COSMIC packages
    nix.settings = {
      substituters      = [ "https://cosmic.cachix.org/" ];
      trusted-public-keys = [ "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85d2Y=" ];
    };

    # ReGreet — GTK4 greeter via cage; same pattern as Niri machines.
    # COSMIC session will appear in /run/current-system/sw/share/wayland-sessions/.
    programs.regreet.enable = true;

    # XDG portal — COSMIC ships its own portal backend
    xdg.portal = {
      enable       = true;
      extraPortals = [ pkgs.xdg-desktop-portal-cosmic ];
      config.common.default = "cosmic";
    };

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

    # UPower — battery status in COSMIC panel
    services.upower.enable = true;

    # Optional fingerprint auth
    services.fprintd.enable = lib.mkDefault config.clanarchy.desktop.cosmic.fprintd.enable;
    security.pam.services.login.fprintAuth  = lib.mkIf config.clanarchy.desktop.cosmic.fprintd.enable true;
    security.pam.services.greetd.fprintAuth = lib.mkIf config.clanarchy.desktop.cosmic.fprintd.enable true;
    security.pam.services.sudo.fprintAuth   = lib.mkIf config.clanarchy.desktop.cosmic.fprintd.enable true;

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
