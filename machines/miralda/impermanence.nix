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
      "/var/lib/syncthing"  # syncthing device DB, peer state, and runtime config
      "/var/lib/fprint"     # enrolled fingerprints must survive ZFS rollback
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
        ".cache/noctalia"  # shell-state.json (version tracking → no wizard/changelog on rollback)
        "Pictures"         # Noctalia wallpaper manager (Wallpapers subdirectory lives here)
      ];
    };

    users.lgo = {
      directories = [
        ".gnupg"           # GPG keyring with YubiKey stubs
        ".claude"          # Claude Code credentials + session data
        ".config"          # gh auth token, noctalia/helix/zellij settings, etc.
        ".local/share"
        ".cache/noctalia"  # shell-state.json (version tracking → no wizard/changelog on rollback)
        "Pictures"         # includes Wallpapers/ subdirectory
        "Documents"
        "Downloads"
        "Music"
        "Videos"
        "Desktop"
        "Projects"
        "Public"
      ];
      files = [
        ".age/yubikey-identity.txt"  # PIV-backed age identity (recipient stored in clan vars)
      ];
    };
  };
}
