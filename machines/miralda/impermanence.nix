{ lib, ... }:
{
  # Roll back root + home on every boot (systemd stage 1).
  # You create the @blank snapshots in the post-install ritual.
  boot.initrd.systemd.services.rollback = {
    description = "Rollback ZFS datasets to blank";
    wantedBy = [ "initrd.target" ];
    after = [ "zfs-import-zroot.service" ];
    before = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      zfs rollback -r zroot/root@blank || true
      zfs rollback -r zroot/home@blank || true
    '';
  };

  environment.persistence."/persist" = {
    hideMounts = true;

    # System-level paths; user paths are defined in modules/users/{lgo,admin}.nix
    directories = [
      "/var/lib/nixos"
      "/var/lib/sops-nix"
      "/var/log"
      "/var/lib/systemd"
      "/var/lib/syncthing"  # syncthing device DB, peer state, and runtime config
      "/var/lib/fprint"     # enrolled fingerprints must survive ZFS rollback
    ];

    files = [
      "/etc/machine-id"
    ];
  };
}
