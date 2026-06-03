{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [./desktop-common.nix];

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
    valent.enable     = lib.mkEnableOption "Valent KDE Connect daemon (for Noctalia valent-connect plugin)";
  };

  config = lib.mkIf config.clanarchy.desktop.labwc.enable {
    # labwc compositor + Wayland utilities
    environment.systemPackages = with pkgs;
      [ labwc wlopm swappy satty ]
      ++ lib.optionals config.clanarchy.desktop.labwc.valent.enable [ valent glib ];

    # UWSM — creates a uwsm-labwc.desktop session file picked up by regreet.
    programs.uwsm.waylandCompositors.labwc = {
      prettyName = "labwc";
      comment = "labwc compositor managed by UWSM";
      binPath = "/run/current-system/sw/bin/labwc";
    };

    # XDG portal — wlr for screen capture, gtk for file chooser
    xdg.portal = {
      enable = true;
      extraPortals = [pkgs.xdg-desktop-portal-wlr pkgs.xdg-desktop-portal-gtk];
      config.common.default = ["wlr" "gtk"];
    };

    # Noctalia PAM service — required for the lock screen's PamContext authentication.
    # Without this, Noctalia falls back to the "login" PAM service.
    security.pam.services.noctalia = {};

    # Shared HM desktop module for all graphical users
    home-manager.sharedModules = [./labwc-hm.nix];

    # Valent — KDE Connect protocol daemon for Noctalia valent-connect plugin.
    # GCR_SSH_AGENT_PIPE="" prevents gcr from importing the TLS key into gpg-agent
    # (which would trigger a blocking pinentry prompt for the headless service).
    systemd.user.services.valent = lib.mkIf config.clanarchy.desktop.labwc.valent.enable {
      description = "Valent - KDE Connect protocol";
      wantedBy    = [ "graphical-session.target" ];
      partOf      = [ "graphical-session.target" ];
      environment.GCR_SSH_AGENT_PIPE = "";
      serviceConfig = {
        ExecStart = "${pkgs.valent}/bin/valent --gapplication-service";
        Restart    = "on-failure";
        RestartSec = 5;
      };
    };

    networking.firewall = lib.mkIf config.clanarchy.desktop.labwc.valent.enable {
      allowedTCPPortRanges = [{ from = 1714; to = 1764; }];
      allowedUDPPortRanges = [{ from = 1714; to = 1764; }];
    };
  };
}
