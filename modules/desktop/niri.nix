{ config, lib, pkgs, pkgs-unstable, inputs, ... }:
{
  options.clanarchy.desktop.niri = {
    enable = lib.mkEnableOption "Niri Wayland compositor with Noctalia";

    display = {
      scale = lib.mkOption {
        type        = lib.types.float;
        default     = 1.25;
        description = "Output scale factor for the primary display (eDP-1).";
      };
      resolution = {
        width = lib.mkOption {
          type        = lib.types.int;
          default     = 2256;
          description = "Horizontal resolution of the primary display.";
        };
        height = lib.mkOption {
          type        = lib.types.int;
          default     = 1504;
          description = "Vertical resolution of the primary display.";
        };
      };
    };

    fprintd.enable = lib.mkEnableOption "fingerprint authentication via fprintd" // { default = true; };

    opacity = {
      focused = lib.mkOption {
        type        = lib.types.float;
        default     = 0.9;
        description = "Baseline window opacity for focused windows.";
      };
      unfocused = lib.mkOption {
        type        = lib.types.float;
        default     = 0.75;
        description = "Window opacity for unfocused windows.";
      };
    };

    wallpaper.workspaceColors = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [ "red" "blue" "green" "purple" "orange" ];
      description = "Per-workspace accent colors (5 entries for workspaces 1-5). Reserved for future Noctalia workspace theming.";
    };
  };

  config = lib.mkIf config.clanarchy.desktop.niri.enable {

    # Niri compositor
    programs.niri.enable = true;

    # ReGreet — GTK4 greeter via cage; Stylix-themed in stylix.nix
    programs.regreet.enable = true;

    # UWSM — binPath must be niri-session (not niri): exports WAYLAND_DISPLAY/NIRI_SOCKET
    # to systemd user manager; without --session, UWSM's waitenv times out (30s).
    programs.uwsm = {
      enable = true;
      waylandCompositors.niri = {
        prettyName = "Niri";
        comment    = "Niri compositor managed by UWSM";
        binPath    = "/run/current-system/sw/bin/niri-session";
      };
    };

    # XDG portal — gtk portal is the recommended choice for Niri
    xdg.portal = {
      enable       = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
      config.common.default = "gtk";
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

    # UPower — required by Noctalia battery widget
    services.upower.enable = true;

    # fprintd service (controlled by fprintd option)
    services.fprintd.enable = lib.mkDefault config.clanarchy.desktop.niri.fprintd.enable;

    # Fingerprint PAM auth
    security.pam.services = lib.mkIf config.clanarchy.desktop.niri.fprintd.enable {
      login.fprintAuth  = true;
      greetd.fprintAuth = true;
      sudo.fprintAuth   = true;
    };

    # Fonts
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

    # Shared HM desktop module for all graphical users
    home-manager.sharedModules   = [ ./niri-hm.nix ];
    home-manager.extraSpecialArgs = {
      inherit inputs pkgs-unstable;
    };
  };
}
