{ ... }:
{
  users.mutableUsers = false;

  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users.admin = import ../home/admin.nix;
}
