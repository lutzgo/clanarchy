{ config, lib, pkgs, ... }:
{
  options.clanarchy.roles.vm = {
    enable = lib.mkEnableOption "VM role (QEMU/KVM guest, server defaults + optional desktop)";
  };

  config = lib.mkIf config.clanarchy.roles.vm.enable {

    # Server defaults (headless baseline)
    services.openssh = {
      enable   = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin        = "prohibit-password";
      };
    };

    nix.settings.auto-optimise-store = true;

    nix.gc = {
      automatic = true;
      dates     = "weekly";
      options   = "--delete-older-than 30d";
    };

    # VM-appropriate desktop defaults (1080p at 1x scale, no fingerprint reader)
    clanarchy.desktop.niri.display.scale            = lib.mkDefault 1.0;
    clanarchy.desktop.niri.display.resolution.width  = lib.mkDefault 1920;
    clanarchy.desktop.niri.display.resolution.height = lib.mkDefault 1080;
    clanarchy.desktop.niri.fprintd.enable            = lib.mkDefault false;

    # QEMU guest tools
    services.qemuGuest.enable      = true;
    services.spice-vdagentd.enable = true;
  };
}
