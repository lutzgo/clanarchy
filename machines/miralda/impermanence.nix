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
      "/var/lib/sops-nix"
      "/var/log"
      "/var/lib/systemd"
      "/var/cache/tuigreet"  # remember-user-session: persists last session per user across reboots
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
        "Pictures/Wallpapers"  # Noctalia wallpaper manager
      ];
    };

    users.lgo = {
      directories = [
        ".gnupg"       # GPG keyring with YubiKey stubs
        ".config"
        ".local/share"
        "Pictures/Wallpapers"  # Noctalia wallpaper manager
      ];
      files = [
        ".age/yubikey-identity.txt"  # PIV-backed age identity (recipient stored in clan vars)
      ];
    };
  };
}
