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

    directories = [
      "/var/lib/nixos"
      "/var/log"
      "/var/lib/systemd"
      "/var/lib/sops-nix"
    ];

    files = [
      "/etc/machine-id"
    ];

    users.admin = {
      directories = [
        ".ssh"
        ".gnupg"
        ".config"
        ".local/share"
      ];
    };
  };
}
