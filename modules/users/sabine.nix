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

      # NO profile activation any more.
      #
      # This used to copy modules/users/sabine-noctalia/simple_mouse/*.json
      # into ~/.config/noctalia/profiles/ and then over the live config, so
      # the "simple_mouse" profile was reapplied on every rebuild. Every part
      # of that is v4: profiles were a feature of the `shell-profiles` plugin,
      # and the files were settings.json + colors.json + plugins.json. v5 has
      # no such plugin, reads config.toml, and takes its palette from
      # palettes/<name>.json, which the stylix target writes.
      #
      # Copying those files onto a v5 install would be inert at best. The
      # layout they encoded is preserved instead as declarative settings in
      # modules/desktop/noctalia-hm.nix, branched on the username. The JSON is
      # kept in-tree as the record of what Sabine actually chose, which is
      # worth more than the dead activation was.
      #
      # See docs/guides/noctalia-profiles.md.
    };
  };
}
