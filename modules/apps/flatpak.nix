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
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
        ExecStart       = "${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo";
      };
    };
  };
}
