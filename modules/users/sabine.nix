{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.clanarchy.users.sabine;
in {
  options.clanarchy.users.sabine.enable =
    lib.mkEnableOption "sabine user profile (GNOME, LibreOffice, Thunderbird, Firefox)";

  config = lib.mkIf cfg.enable {
    # nushell must be in /etc/shells for accounts-daemon to enumerate sabine.
    # Without this regreet can't pre-select her; she'd have to type the username every login.
    environment.shells = [pkgs.nushell];

    users.users.sabine = {
      isNormalUser = true;
      extraGroups = ["wheel" "networkmanager" "video" "audio"];
      shell = pkgs.nushell;
      hashedPasswordFile = config.clan.core.vars.generators.sabine-password.files."hashed-password".path;
    };

    # Clan vars: sabine password generator
    clan.core.vars.generators.sabine-password = {
      files."hashed-password" = {
        secret = true;
        neededFor = "users";
      };
      prompts."password" = {
        description = "Password for the sabine user (used for sudo and local console login)";
        type = "hidden";
      };
      script = ''
        ${pkgs.mkpasswd}/bin/mkpasswd -m sha-512 "$(cat "$prompts/password")" > "$out/hashed-password"
      '';
      runtimeInputs = [pkgs.mkpasswd];
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
        # Lutris's default install directory; Wine prefixes for iTunes and
        # any iPhone backups it holds live here. Must persist across ZFS
        # rollback or every reboot wipes the iTunes install.
        "Games"
      ];
    };

    # Home Manager configuration
    home-manager.users.sabine = {
      pkgs,
      config,
      lib,
      osConfig,
      ...
    }: {
      home.username = "sabine";
      home.homeDirectory = "/home/sabine";
      home.stateVersion = "25.11";

      xdg.userDirs = {
        enable = true;
        createDirectories = true;
        setSessionVariables = true;
      };

      programs.nushell = {
        enable = true;
        extraConfig = ''
          $env.config.show_banner = false
        '';
      };

      programs.zsh.enable = true;

      xdg.mimeApps = {
        enable = true;
        defaultApplications = {
          "text/html" = ["librewolf.desktop"];
          "x-scheme-handler/http" = ["librewolf.desktop"];
          "x-scheme-handler/https" = ["librewolf.desktop"];
          "application/xhtml+xml" = ["librewolf.desktop"];
        };
      };

      home.packages = with pkgs; [
        libreoffice
        htop
        ripgrep
        zellij
        yazi
        bat
        # iTunes-on-Wine for iPhone music sync. Install via Lutris's
        # community install script ("iTunes" on lutris.net) after first
        # launch; the script handles Wine version pinning and winetricks
        # dependencies. iPhone photos can be browsed directly in Nautilus
        # (GVfs AFC, wired at the system level in biene/configuration.nix).
        lutris
      ];

      # Sabine's bar (clock and battery centred, status on the right) is
      # declarative config in modules/desktop/noctalia-hm.nix, branched on
      # the username. See docs/guides/noctalia-profiles.md.
    };
  };
}
