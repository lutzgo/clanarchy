{
  config,
  lib,
  pkgs,
  pkgs-unstable,
  inputs,
  ...
}: {
  imports = [../icon-theme.nix];

  options.clanarchy.desktop.niri = {
    enable = lib.mkEnableOption "Niri Wayland compositor with Noctalia";

    display = {
      scale = lib.mkOption {
        type = lib.types.float;
        default = 1.25;
        description = "Output scale factor for the primary display (eDP-1).";
      };
      resolution = {
        width = lib.mkOption {
          type = lib.types.int;
          default = 2256;
          description = "Horizontal resolution of the primary display.";
        };
        height = lib.mkOption {
          type = lib.types.int;
          default = 1504;
          description = "Vertical resolution of the primary display.";
        };
      };
    };

    fprintd.enable = lib.mkEnableOption "fingerprint authentication via fprintd" // {default = true;};

    opacity = {
      focused = lib.mkOption {
        type = lib.types.float;
        default = 0.9;
        description = "Baseline window opacity for focused windows.";
      };
      unfocused = lib.mkOption {
        type = lib.types.float;
        default = 0.75;
        description = "Window opacity for unfocused windows.";
      };
    };

    input.pointerSpeed = lib.mkOption {
      type = lib.types.float;
      default = 0.0;
      description = "Pointer acceleration speed applied to both touchpad and mouse. Range: -1.0 (slowest) to 1.0 (fastest). 0.0 is libinput's neutral baseline.";
    };

    wallpaper.workspaceColors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["red" "blue" "green" "purple" "orange"];
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
        comment = "Niri compositor managed by UWSM";
        binPath = "/run/current-system/sw/bin/niri-session";
      };
    };

    # XDG portal — gtk portal is the recommended choice for Niri
    xdg.portal = {
      enable = true;
      extraPortals = [pkgs.xdg-desktop-portal-gtk];
      config.common.default = "gtk";
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
    # org.freedesktop.Accounts D-Bus API.  Without it regreet panics on first start
    # ("The name is not activatable") and leaves cage showing a white screen until
    # greetd recovers (~44 s later).
    services.accounts-daemon.enable = true;

    # V4L2 loopback — virtual camera device used by OBS's "Start Virtual Camera".
    # UVC input (Sony ILCE, etc.) works via the built-in uvcvideo module; no extra config needed.
    # exclusive_caps=1 makes apps (Meet, Zoom, …) enumerate the loopback as a capture device.
    # video_nr=10 avoids collisions with physical cameras at /dev/video0…
    boot.extraModulePackages = [config.boot.kernelPackages.v4l2loopback];
    boot.kernelModules = ["v4l2loopback"];
    boot.extraModprobeConfig = lib.mkAfter ''
      options v4l2loopback devices=1 video_nr=10 card_label="OBS Virtual Camera" exclusive_caps=1
    '';
    environment.systemPackages = with pkgs; [
      v4l-utils
      # Noctalia plugin runtime dependencies
      calibre               # calibre-provider: book library search via >cb launcher
      obs-studio            # obs-control: recording/streaming control from bar
      khal                  # khal-agenda-widget: upcoming events for next 7 days
      evolution-data-server # weekly-calendar: CalendarService.qml backend (D-Bus activated)
      wlr-randr             # display-settings: live display info and configuration
      fd                    # file-search: fast file lookup via >file launcher
      networkmanagerapplet  # network-manager-vpn: nm-connection-editor for VPN profiles
      kdePackages.qtwebsockets # hassio + obs-control: Qt6 WebSocket support
    ];

    # Mullvad VPN — mullvad Noctalia plugin requires the daemon + mullvad CLI.
    services.mullvad-vpn.enable = true;

    # fprintd service (controlled by fprintd option)
    services.fprintd.enable = lib.mkDefault config.clanarchy.desktop.niri.fprintd.enable;

    # Fingerprint PAM auth — use per-service sub-attribute form so each service's
    # other options (unixAuth, etc.) are preserved via normal submodule merging.
    security.pam.services.login.fprintAuth   = lib.mkIf config.clanarchy.desktop.niri.fprintd.enable true;
    security.pam.services.greetd.fprintAuth  = lib.mkIf config.clanarchy.desktop.niri.fprintd.enable true;
    security.pam.services.sudo.fprintAuth    = lib.mkIf config.clanarchy.desktop.niri.fprintd.enable true;
    # Noctalia lockscreen — PamContext in QML requires a dedicated PAM service.
    security.pam.services.noctalia.fprintAuth = lib.mkIf config.clanarchy.desktop.niri.fprintd.enable true;

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
    home-manager.sharedModules = [./niri-hm.nix];
    home-manager.extraSpecialArgs = {
      inherit inputs pkgs-unstable;
    };
  };
}
