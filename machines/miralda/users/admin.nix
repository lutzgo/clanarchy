{ pkgs, config, ... }:
{
  users.mutableUsers = false;

  programs.zsh.enable = true;

  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    hashedPasswordFile = config.clan.core.vars.generators.admin-password.files."hashed-password".path;
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../clanarchy_admin.pub)
      (builtins.readFile ../yubikey_rsa.pub)
    ];
  };

  users.users.root = {
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../clanarchy_admin.pub)
      (builtins.readFile ../yubikey_rsa.pub)
    ];
  };

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users.admin = import ../home/admin.nix;
}
