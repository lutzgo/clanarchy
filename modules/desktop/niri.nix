{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [./desktop-common.nix];

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
        default = 0.8;
        description = "Baseline window opacity for focused windows.";
      };
      unfocused = lib.mkOption {
        type = lib.types.float;
        default = 0.65;
        description = "Window opacity for unfocused windows.";
      };
    };

    input.pointerSpeed = lib.mkOption {
      type = lib.types.float;
      default = 0.0;
      description = "Pointer acceleration speed applied to both touchpad and mouse. Range: -1.0 (slowest) to 1.0 (fastest). 0.0 is libinput's neutral baseline.";
    };

    # Background blur (niri v26.04+). niri-flake's Nix schema does not yet
    # expose the `blur { }` block or `background-effect { }` rule child, so
    # `niri-hm.nix` injects raw KDL into the final config.kdl behind this flag.
    blur.enable = lib.mkEnableOption "background blur behind translucent windows and Noctalia layer surfaces" // {default = true;};

    wallpaper.workspaceColors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["red" "blue" "green" "purple" "orange"];
      description = "Per-workspace accent colors (5 entries for workspaces 1-5). Reserved for future Noctalia workspace theming.";
    };
  };

  config = lib.mkIf config.clanarchy.desktop.niri.enable {
    # Niri compositor
    programs.niri.enable = true;

    # UWSM — binPath must be niri-session (not niri): exports WAYLAND_DISPLAY/NIRI_SOCKET
    # to systemd user manager; without --session, UWSM's waitenv times out (30s).
    programs.uwsm.waylandCompositors.niri = {
      prettyName = "Niri";
      comment = "Niri compositor managed by UWSM";
      binPath = "/run/current-system/sw/bin/niri-session";
    };

    # XDG portal — gtk portal is the recommended choice for Niri
    xdg.portal = {
      enable = true;
      extraPortals = [pkgs.xdg-desktop-portal-gtk];
      config.common.default = "gtk";
    };

    # V4L2 loopback — virtual camera device used by OBS's "Start Virtual Camera".
    # UVC input (Sony ILCE, etc.) works via the built-in uvcvideo module; no extra config needed.
    # exclusive_caps=1 makes apps (Meet, Zoom, …) enumerate the loopback as a capture device.
    # video_nr=10 avoids collisions with physical cameras at /dev/video0…
    boot.extraModulePackages = [config.boot.kernelPackages.v4l2loopback];
    boot.kernelModules = ["v4l2loopback"];
    boot.extraModprobeConfig = lib.mkAfter ''
      options v4l2loopback devices=1 video_nr=10 card_label="OBS Virtual Camera" exclusive_caps=1
    '';
    environment.systemPackages = [ pkgs.v4l-utils ];

    # fprintd service (controlled by fprintd option)
    services.fprintd.enable = lib.mkDefault config.clanarchy.desktop.niri.fprintd.enable;

    # Fingerprint PAM auth — use per-service sub-attribute form so each service's
    # other options (unixAuth, etc.) are preserved via normal submodule merging.
    security.pam.services.login.fprintAuth   = lib.mkIf config.clanarchy.desktop.niri.fprintd.enable true;
    security.pam.services.greetd.fprintAuth  = lib.mkIf config.clanarchy.desktop.niri.fprintd.enable true;
    security.pam.services.sudo.fprintAuth    = lib.mkIf config.clanarchy.desktop.niri.fprintd.enable true;
    # Noctalia lockscreen — PamContext in QML requires a dedicated PAM service.
    security.pam.services.noctalia.fprintAuth = lib.mkIf config.clanarchy.desktop.niri.fprintd.enable true;

    # Shared HM desktop module for all graphical users
    home-manager.sharedModules = [./niri-hm.nix];
  };
}
