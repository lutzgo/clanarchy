{ lib, ... }:
{
  # Roll back root + home on every boot.
  # You create the @blank snapshots in the post-install ritual.
  boot.initrd.postDeviceCommands = lib.mkAfter ''
    zfs rollback -r zroot/root@blank || true
    zfs rollback -r zroot/home@blank || true
  '';

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
