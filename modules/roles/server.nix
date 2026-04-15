{ config, lib, ... }:
{
  options.clanarchy.roles.server = {
    enable = lib.mkEnableOption "server role (headless, SSH, no GUI)";
  };

  config = lib.mkIf config.clanarchy.roles.server.enable {

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
  };
}
