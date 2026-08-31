{ config, lib, pkgs, ... }:
let cfg = config.clanarchy.apps.flatpak;
in {
  options.clanarchy.apps.flatpak.enable =
    lib.mkEnableOption "Flatpak sandbox with Flathub remote";

  config = lib.mkIf cfg.enable {
    services.flatpak.enable = true;

    # Flatpak app state (installed apps, runtimes, remotes) must survive ZFS rollback.
    environment.persistence."/persist".directories = [ "/var/lib/flatpak" ];

    # XDG_DATA_DIRS must include flatpak export paths so launchers (Noctalia/Quickshell)
    # see installed apps' .desktop files. NixOS adds these via /etc/profile.d/flatpak.sh
    # (login-shell only), but UWSM imports env from PAM — sessionVariables writes to
    # /etc/environment via pam_env, which is read by all PAM sessions including greetd.
    environment.sessionVariables.XDG_DATA_DIRS = [
      "/var/lib/flatpak/exports/share"
      "$HOME/.local/share/flatpak/exports/share"
    ];

    systemd.services.flatpak-add-flathub = {
      description = "Add Flathub remote for Flatpak";
      wantedBy    = [ "multi-user.target" ];
      after       = [ "network-online.target" ];
      wants       = [ "network-online.target" ];
      # network-online.target above is necessary but not sufficient: it fires
      # when a link is up, which on a wifi-only machine can still precede
      # working DNS. birte failed every boot with
      #   error: Can't load uri https://dl.flathub.org/repo/... [6] Could not
      #   resolve hostname
      # and then succeeded immediately when run by hand minutes later. Retry
      # rather than tightening the ordering, since there is no target that
      # means "resolver answers".
      startLimitIntervalSec = 300;
      startLimitBurst       = 5;
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
        Restart         = "on-failure";
        RestartSec      = 15;
        ExecStart       = "${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo";
      };
    };
  };
}
