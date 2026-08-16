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

  # userborn creates users declaratively instead of NixOS's perl activation
  # script.  It is NOT compatible with impermanence under default settings
  # (https://github.com/nix-community/impermanence/pull/223), and every
  # clanarchy machine is impermanent.
  #
  # 26.05 leaves it off, so this is currently a no-op — it is here to keep a
  # future nixpkgs or clan-core default flip from silently breaking user
  # creation across the whole fleet.  srvos guards the same way, disabling
  # userborn whenever it detects `options.environment ? persistence`; we can
  # state it unconditionally because impermanence is universal here.
  #
  # If this is ever lifted, it must be paired with impermanence's
  # userborn-compatible settings — not simply deleted.
  services.userborn.enable = false;
}
