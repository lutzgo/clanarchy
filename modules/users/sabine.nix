{ config, lib, pkgs, ... }:
let
  cfg = config.clanarchy.users.sabine;
in
{
  options.clanarchy.users.sabine = {
    enable = lib.mkEnableOption "sabine user profile (COSMIC, LibreOffice, Thunderbird, Firefox)";

    git = {
      name  = lib.mkOption { type = lib.types.str; default = "Sabine"; };
      email = lib.mkOption { type = lib.types.str; default = ""; };
    };
  };

  config = lib.mkIf cfg.enable {

    # COSMIC desktop — required for sabine's graphical session
    clanarchy.desktop.cosmic.enable = lib.mkDefault true;

    users.users.sabine = {
      isNormalUser = true;
      extraGroups  = [ "wheel" "networkmanager" "video" "audio" ];
      shell        = pkgs.zsh;
      hashedPasswordFile = config.clan.core.vars.generators.sabine-password.files."hashed-password".path;
    };

    # Clan vars: sabine password generator
    clan.core.vars.generators.sabine-password = {
      files."hashed-password" = {
        secret    = true;
        neededFor = "users";
      };
      prompts."password" = {
        description = "Password for the sabine user (used for sudo and local console login)";
        type        = "hidden";
      };
      script = ''
        ${pkgs.mkpasswd}/bin/mkpasswd -m sha-512 "$(cat "$prompts/password")" > "$out/hashed-password"
      '';
      runtimeInputs = [ pkgs.mkpasswd ];
    };

    # Impermanence paths for sabine
    environment.persistence."/persist".users.sabine = {
      directories = [
        ".config"
        ".local/share"
        ".cache"
        "Documents"
        "Downloads"
        "Pictures"
        "Music"
        "Videos"
        "Desktop"
        "Public"
      ];
    };

    # Home Manager configuration
    home-manager.users.sabine = { pkgs, ... }: {
      home.username      = "sabine";
      home.homeDirectory = "/home/sabine";
      home.stateVersion  = "25.11";

      xdg.userDirs = {
        enable              = true;
        createDirectories   = true;
        setSessionVariables = true;
      };

      programs.git = {
        enable   = true;
        settings = {
          user.name  = cfg.git.name;
          user.email = cfg.git.email;
        };
      };

      programs.zsh.enable = true;

      programs.firefox = {
        enable   = true;
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
