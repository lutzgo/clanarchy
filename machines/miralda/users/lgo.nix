{ pkgs, config, ... }:
{
  users.users.lgo = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "input" ];
    shell = pkgs.nushell;  # zsh stays available as fallback via programs.zsh in HM
    hashedPasswordFile = config.clan.core.vars.generators.lgo-password.files."hashed-password".path;
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../clanarchy_admin.pub)
    ];
  };

  home-manager.users.lgo = import ../home/lgo.nix;
}
