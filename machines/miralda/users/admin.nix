{ pkgs, ... }:
{
  users.mutableUsers = false;

  programs.zsh.enable = true;

  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../clanarchy_admin.pub)
    ];
  };

  users.users.root = {
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../clanarchy_admin.pub)
    ];
  };

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users.admin = import ../home/admin.nix;
}
