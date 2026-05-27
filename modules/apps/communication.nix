{ config, lib, pkgs, ... }:
let cfg = config.clanarchy.apps.communication;
in {
  options.clanarchy.apps.communication.enable =
    lib.mkEnableOption "communication and connectivity apps (Signal, Anytype, Valent/KDE Connect)";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      signal-desktop           # messaging (unfree)
      anytype                  # knowledge base / notes (unfree)
      valent                   # KDE Connect protocol
      glib                     # provides gdbus — needed by Noctalia valent-connect plugin
      kdePackages.qtwebsockets # required by valent
    ];

    # Valent — GCR_SSH_AGENT_PIPE="" prevents gcr from importing the TLS key into
    # gpg-agent (which would trigger a blocking pinentry prompt for the headless service).
    systemd.user.services.valent = {
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

    # Valent / KDE Connect protocol — ports 1714-1764 TCP+UDP
    networking.firewall = {
      allowedTCPPortRanges = [{ from = 1714; to = 1764; }];
      allowedUDPPortRanges = [{ from = 1714; to = 1764; }];
    };
  };
}
