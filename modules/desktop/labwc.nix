{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  inputs,
  ...
}: {
  imports = [../icon-theme.nix];

  options.clanarchy.desktop.labwc = {
    enable = lib.mkEnableOption "labwc Wayland compositor with Noctalia";

    display.scale = lib.mkOption {
      type = lib.types.float;
      default = 1.25;
      description = "Output scale factor for the primary display (eDP-1).";
    };

    input.pointerSpeed = lib.mkOption {
      type = lib.types.float;
      default = 0.4;
      description = "Touchpad acceleration speed. Range: -1.0 (slowest) to 1.0 (fastest).";
    };

    keepassxc.enable = lib.mkEnableOption "autostart KeePassXC password manager";
    nextcloud.enable  = lib.mkEnableOption "autostart Nextcloud desktop sync client";
  };

  config = lib.mkIf config.clanarchy.desktop.labwc.enable {
    environment.systemPackages = with pkgs; [labwc wlopm];

    # ReGreet — GTK4 greeter via cage; Stylix-themed in stylix.nix.
    # Must pass --sessions /run/current-system/sw/share/wayland-sessions;
    # never use --remember-session (panics after ZFS rollback wipes cache).
    programs.regreet.enable = true;

    # UWSM — session management for labwc.
    # Creates a uwsm-labwc.desktop session file picked up by regreet.
    programs.uwsm = {
      enable = true;
      waylandCompositors.labwc = {
        prettyName = "labwc";
        comment = "labwc compositor managed by UWSM";
        binPath = "/run/current-system/sw/bin/labwc";
      };
    };

    # polkit — required for UWSM privilege escalation and labwc session management
    security.polkit.enable = true;

    # XDG portal — wlr for screen capture, gtk for file chooser
    xdg.portal = {
      enable = true;
      extraPortals = [pkgs.xdg-desktop-portal-wlr pkgs.xdg-desktop-portal-gtk];
      config.common.default = ["wlr" "gtk"];
    };

    # NetworkManager
    networking.networkmanager.enable = true;

    # Pipewire audio
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    # UPower — required by Noctalia battery widget
    services.upower.enable = true;

    # udisks2 — required by Noctalia USB drive manager (D-Bus device detection + auto-mount)
    services.udisks2.enable = true;

    # accounts-daemon — required by regreet ≥ 0.3.0 for user enumeration via the
    # org.freedesktop.Accounts D-Bus API.
    services.accounts-daemon.enable = true;

    # Noctalia PAM service — required for the lock screen's PamContext authentication.
    # Without this, Noctalia falls back to the "login" PAM service.
    security.pam.services.noctalia = {};

    # Fonts
    fonts.packages = with pkgs; [
      nerd-fonts.monaspace
      noto-fonts
      noto-fonts-color-emoji
      inter
    ];
    fonts.fontconfig = {
      defaultFonts = {
        monospace = ["MonaspiceAr Nerd Font Mono" "Noto Sans Mono"];
        sansSerif = ["Inter" "Noto Sans"];
        serif = ["MonaspiceXe Nerd Font Propo" "Noto Serif"];
        emoji = ["Noto Color Emoji"];
      };
      hinting = {
        enable = true;
        style = "slight";
      };
      subpixel = {
        rgba = "rgb";
        lcdfilter = "default";
      };
    };

    environment.variables = {
      XCURSOR_SIZE = "24";
      XCURSOR_THEME = "Adwaita";
      NIXOS_OZONE_WL = "1";
    };

    # Shared HM desktop module for all graphical users
    home-manager.sharedModules = [./labwc-hm.nix];
    home-manager.extraSpecialArgs = {
      inherit inputs pkgs-unstable;
    };
  };
}
