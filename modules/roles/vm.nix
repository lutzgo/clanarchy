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

    # QEMU guest tools
    services.qemuGuest.enable      = true;
    services.spice-vdagentd.enable = true;
  };
}
