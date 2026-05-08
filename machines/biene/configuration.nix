{...}: {
  networking.hostName = "biene";
  networking.hostId = "cd9ef50b";
  networking.search = ["skynet.lan"];

  # No targetHost set — clan auto-discovers biene via ZeroTier (same as miralda).
  # For initial deploy or when ZeroTier is unreachable, use:
  #   BIENE_HOST=biene.local deploy-biene
  time.timeZone = "Europe/Berlin";

  # --- Module activation ---
  # machine-type (laptop, no Framework hw) and desktop (gnome + sabine dconf)
  # are assigned via inventory.instances in clan.nix.
  # Home wifi is provisioned via the clan wifi service (clan.nix).
  # Fritz!Box is biene-specific — managed via the bespoke modules/wifi.nix.
  clanarchy.hardware.cpu       = "intel";
  clanarchy.users.admin.enable = true;

  # Fritz!Box 7590 MX — biene-specific second wifi network.
  # Run `clan vars generate biene --generator wifi-fritzbox` to store the PSK.
  clanarchy.wifi.networks = [
    { ssid = "Fritz!Box 7590 MX"; varName = "wifi-fritzbox"; }
  ];

  # Keep flakes usable on the installed system too
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # SSH daemon
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # EFI boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ZFS boot support
  boot.supportedFilesystems = ["zfs"];
  boot.zfs.forceImportRoot = false;
  boot.initrd.systemd.enable = true;

  # Plymouth splash
  boot.plymouth.enable = true;
  boot.kernelParams = ["quiet" "splash"];

  # Impermanence requires these early
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/home".neededForBoot = true;

  home-manager.backupFileExtension = "bak";

  # Stylix auto-enables the KDE target for all HM users; disable it globally
  # since biene uses GNOME.
  home-manager.sharedModules = [{ stylix.targets.kde.enable = false; }];


  programs.zsh.enable = true;

  system.stateVersion = "25.11";
}
