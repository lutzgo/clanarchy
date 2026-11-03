# Valent (KDE Connect protocol), one copy for every machine that runs it.
# Turned on by clanarchy.apps.communication (miralda, jens) and by
# clanarchy.desktop.labwc.valent (biene).
#
# ONE INSTANCE, AND ALWAYS valent.service. Valent is a GApplication: whichever
# process takes the bus name first is THE instance, and every later `valent`
# just forwards to it. Only valent.service carries GCR_SSH_AGENT_PIPE="", which
# stops gcr handing Valent's TLS key (~/.config/valent/private.pem) to
# gpg-agent — the "Please enter a passphrase to protect the received secret
# key" pinentry. Any other way in won that race unguarded:
#
#   XDG autostart   the package's entry      -> hidden below (Hidden=true)
#   the launcher    Exec=valent %U, direct   -> the wrapper starts the unit
#                                              first, then forwards to it
#   D-Bus           activation by name       -> SystemdService=valent.service
#
# Type = dbus is what makes the launcher path safe: `systemctl start` returns
# only once the unit OWNS the bus name, so the window can no longer take it.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.clanarchy.apps.valent;
  busName = "ca.andyholmes.Valent";

  guarded = pkgs.symlinkJoin {
    name = "valent-guarded-${pkgs.valent.version}";
    paths = [pkgs.valent];
    postBuild = ''
      rm "$out/bin/valent"
      cat > "$out/bin/valent" <<EOF
      #!${pkgs.runtimeShell}
      export GCR_SSH_AGENT_PIPE=
      case " \$* " in
        *" --gapplication-service "*) ;;
        *) ${pkgs.systemd}/bin/systemctl --user start valent.service || true ;;
      esac
      exec ${pkgs.valent}/bin/valent "\$@"
      EOF
      chmod +x "$out/bin/valent"

      svc="$out/share/dbus-1/services/${busName}.service"
      rm "$svc"
      printf '%s\n' '[D-BUS Service]' 'Name=${busName}' \
        "Exec=$out/bin/valent --gapplication-service" \
        'SystemdService=valent.service' > "$svc"
    '';
  };
in {
  options.clanarchy.apps.valent.enable =
    lib.mkEnableOption "Valent, the KDE Connect protocol daemon, as a single systemd-managed instance";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      guarded
      pkgs.glib # gdbus — Noctalia's valent-connect plugin calls it
      pkgs.kdePackages.qtwebsockets # required by valent
    ];

    systemd.user.services.valent = {
      description = "Valent - KDE Connect protocol";
      wantedBy = ["graphical-session.target"];
      partOf = ["graphical-session.target"];
      environment.GCR_SSH_AGENT_PIPE = "";
      serviceConfig = {
        Type = "dbus";
        BusName = busName;
        ExecStart = "${pkgs.valent}/bin/valent --gapplication-service";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # Same file name, Hidden=true, in /etc/xdg — first in XDG_CONFIG_DIRS
    # (MEASURED on miralda), ahead of the package's copy.
    environment.etc."xdg/autostart/ca.andyholmes.Valent-autostart.desktop".source =
      pkgs.writeText "valent-autostart-hidden.desktop" "[Desktop Entry]\nType=Application\nName=Valent\nHidden=true\n";

    # KDE Connect protocol: 1714-1764, TCP and UDP.
    networking.firewall = let
      range = [
        {
          from = 1714;
          to = 1764;
        }
      ];
    in {
      allowedTCPPortRanges = range;
      allowedUDPPortRanges = range;
    };
  };
}
