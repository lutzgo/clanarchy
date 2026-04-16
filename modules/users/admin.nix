{ config, lib, pkgs, ... }:
{
  options.clanarchy.users.admin.enable =
    lib.mkEnableOption "admin user profile (SSH keys, zsh, minimal tools)";

  config = lib.mkIf config.clanarchy.users.admin.enable {

    # System-wide HM settings — set here since admin is always the first user enabled
    users.mutableUsers = false;
    home-manager.useGlobalPkgs   = true;
    home-manager.useUserPackages = true;

    users.users.admin = {
      isNormalUser = true;
      extraGroups  = [ "wheel" ];
      shell        = pkgs.zsh;
      hashedPasswordFile = config.clan.core.vars.generators.admin-password.files."hashed-password".path;
      openssh.authorizedKeys.keys = [
        (builtins.readFile ../../machines/miralda/clanarchy_admin.pub)
        (builtins.readFile ../../machines/miralda/yubikey_ed25519.pub)
      ];
    };

    users.users.root = {
      openssh.authorizedKeys.keys = [
        (builtins.readFile ../../machines/miralda/clanarchy_admin.pub)
        (builtins.readFile ../../machines/miralda/yubikey_ed25519.pub)
      ];
    };

    # Clan vars: SSH key + password generators
    clan.core.vars.generators.admin-ssh = {
      files."id_ed25519".secret = true;
      files."id_ed25519.pub".secret = false;
      script = ''
        mkdir -p "$out"
        ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -N "" -f "$out/id_ed25519"
      '';
      runtimeInputs = [ pkgs.openssh ];
    };

    clan.core.vars.generators.admin-password = {
      files."hashed-password" = {
        secret    = true;
        neededFor = "users";
      };
      prompts."password" = {
        description = "Password for the admin user (used for sudo and local console login)";
        type        = "hidden";
      };
      script = ''
        ${pkgs.mkpasswd}/bin/mkpasswd -m sha-512 "$(cat "$prompts/password")" > "$out/hashed-password"
      '';
      runtimeInputs = [ pkgs.mkpasswd ];
    };

    # Impermanence paths for admin
    environment.persistence."/persist".users.admin = {
      directories = [
        ".ssh"
        ".gnupg"
        ".config"
        ".local/share"
        ".cache/noctalia"  # shell-state.json (version tracking → no wizard/changelog on rollback)
        ".cache/zellij"    # compiled WASM + plugin permission cache (avoids "Allow?" prompt on boot)
        "Pictures"         # Noctalia wallpaper manager (Wallpapers subdirectory lives here)
      ];
    };

    # Home Manager configuration
    home-manager.users.admin = { pkgs, ... }: {
      home.username      = "admin";
      home.homeDirectory = "/home/admin";
      home.stateVersion  = "25.11";

      programs.git.enable = true;
      programs.zsh.enable = true;

      home.packages = with pkgs; [ htop ripgrep fd ];
    };
  };
}
