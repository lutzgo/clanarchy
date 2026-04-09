{ ... }:
{
  networking.hostName = "miralda";
  networking.hostId = "ebeed95c";
  time.timeZone = "Europe/Berlin";

  # Keep flakes usable on the installed system too
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Ensure SSH daemon is present (inventory sshd service manages keys/config)
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # Use systemd-boot (EFI)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ZFS in initrd (disko creates pool/datasets, this ensures boot support)
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  boot.initrd.systemd.enable = true;

  # Plymouth splash screen (Stylix generates the theme in stylix.nix)
  boot.plymouth.enable = true;
  boot.kernelParams = [ "quiet" "splash" ];

  # Impermanence requires these to be available early
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/home".neededForBoot = true;

  # HM backup extension: when nixos-rebuild finds a regular file where it wants to
  # create a managed symlink (e.g. niri/config.kdl written by niri itself), back it
  # up with this suffix rather than failing. Applies to all users.
  home-manager.backupFileExtension = "bak";

  # Make zsh available as a valid login shell (/etc/shells) for use as fallback.
  # nushell is set as lgo's login shell; this lets `chsh -s zsh` work and
  # keeps existing SSH sessions that start zsh functional.
  programs.zsh.enable = true;

  # clan vars generate runs as root, leaving shared vars root-owned.
  # Re-chown after every activation so lgo can enter devShell without sudo.
  system.activationScripts.clanVarsOwnership.text = ''
    chown -R lgo:users /home/lgo/Projects/clanarchy/vars/shared/zerotier-controller || true
  '';

  # Required
  system.stateVersion = "25.11";
}
