{ lib, ... }:
{
  # All clanarchy machines target x86_64-linux. Machines that have a
  # generated facter.json can still override this (mkDefault → lower priority).
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  boot.loader.systemd-boot.enable      = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.plymouth.enable                 = true;
  boot.kernelParams                    = [ "quiet" "splash" ];

  home-manager.backupFileExtension = "bak";

  # Home Manager 26.11 vs Nixpkgs 26.05 — HM is intentionally ahead of the
  # clan-core-pinned nixpkgs.  Silence the per-profile version-mismatch
  # warning for every HM user in the clan; we track HM upstream manually.
  home-manager.sharedModules = [ { home.enableNixpkgsReleaseCheck = false; } ];

  # Make zsh available as a valid login shell (/etc/shells) for use as fallback.
  programs.zsh.enable = true;

  # SSH hardening — clan sshd service adds keys; these settings lock down auth.
  services.openssh = {
    enable   = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin        = "prohibit-password";
    };
  };
}
