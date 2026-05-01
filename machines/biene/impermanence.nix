{ ... }:
{
  # Roll back root + home on every boot (systemd stage 1).
  # You create the @blank snapshots in the post-install ritual.
  boot.initrd.systemd.services.rollback = {
    description = "Rollback ZFS datasets to blank";
    wantedBy    = [ "initrd.target" ];
    after       = [ "zfs-import-zroot.service" ];
    before      = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      zfs rollback -r zroot/root@blank || true
      zfs rollback -r zroot/home@blank || true
    '';
  };

  environment.persistence."/persist" = {
    hideMounts = true;

    # System-level paths; user paths are defined in modules/users/{admin,sabine}.nix
    directories = [
      "/var/lib/nixos"
      "/var/log"
      "/var/lib/systemd"
    ];

    files = [
      "/etc/machine-id"
    ];
  };
}
