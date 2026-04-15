{ config, lib, pkgs, ... }:
{
  options.clanarchy.users.sgo = {
    enable = lib.mkEnableOption "sgo office user profile (Niri, LibreOffice, Thunderbird, Firefox)";
    git = {
      name  = lib.mkOption { type = lib.types.str; default = "sgo"; };
      email = lib.mkOption { type = lib.types.str; default = ""; };
    };
  };

  config = lib.mkIf config.clanarchy.users.sgo.enable {

    # Niri desktop — required for office use
    clanarchy.desktop.niri.enable = lib.mkDefault true;

    users.users.sgo = {
      isNormalUser = true;
      extraGroups  = [ "wheel" "networkmanager" "video" "audio" ];
      shell        = pkgs.nushell;
      hashedPasswordFile = config.clan.core.vars.generators.sgo-password.files."hashed-password".path;
    };

    # Clan vars: sgo password generator
    clan.core.vars.generators.sgo-password = {
      files."hashed-password" = {
        secret    = true;
        neededFor = "users";
      };
      prompts."password" = {
        description = "Password for the sgo user (used for sudo and local console login)";
        type        = "hidden";
      };
      script = ''
        ${pkgs.mkpasswd}/bin/mkpasswd -m sha-512 "$(cat "$prompts/password")" > "$out/hashed-password"
      '';
      runtimeInputs = [ pkgs.mkpasswd ];
    };

    # Home Manager configuration
    home-manager.users.sgo = { pkgs, config, lib, ... }: {
      home.username      = "sgo";
      home.homeDirectory = "/home/sgo";
      home.stateVersion  = "25.11";

      xdg.userDirs = {
        enable              = true;
        createDirectories   = true;
        setSessionVariables = true;
      };

      programs.git = {
        enable   = true;
        settings = {
          user.name  = config.clanarchy.users.sgo.git.name;
          user.email = config.clanarchy.users.sgo.git.email;
        };
      };

      programs.nushell = {
        enable      = true;
        extraConfig = ''
          $env.config.show_banner = false
        '';
      };

      programs.zsh.enable = true;

      programs.firefox = {
        enable = true;
        profiles.default = { };
      };

      home.packages = with pkgs; [
        libreoffice
        thunderbird
        htop
        ripgrep
      ];
    };
  };
}
