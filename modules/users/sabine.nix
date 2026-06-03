{ config, lib, pkgs, ... }:
let
  cfg = config.clanarchy.users.sabine;
in
{
  options.clanarchy.users.sabine.enable =
    lib.mkEnableOption "sabine user profile (GNOME, LibreOffice, Thunderbird, Firefox)";

  config = lib.mkIf cfg.enable {

    # nushell must be in /etc/shells for accounts-daemon to enumerate sabine.
    # Without this regreet can't pre-select her; she'd have to type the username every login.
    environment.shells = [ pkgs.nushell ];

    users.users.sabine = {
      isNormalUser = true;
      extraGroups  = [ "wheel" "networkmanager" "video" "audio" ];
      shell        = pkgs.nushell;
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
    home-manager.users.sabine = { pkgs, config, lib, osConfig, ... }: {
      home.username      = "sabine";
      home.homeDirectory = "/home/sabine";
      home.stateVersion  = "25.11";

      xdg.userDirs = {
        enable              = true;
        createDirectories   = true;
        setSessionVariables = true;
      };

      programs.nushell = {
        enable      = true;
        extraConfig = ''
          $env.config.show_banner = false
        '';
      };

      programs.zsh.enable = true;

      xdg.mimeApps = {
        enable = true;
        defaultApplications = {
          "text/html"              = [ "librewolf.desktop" ];
          "x-scheme-handler/http"  = [ "librewolf.desktop" ];
          "x-scheme-handler/https" = [ "librewolf.desktop" ];
          "application/xhtml+xml"  = [ "librewolf.desktop" ];
        };
      };

      home.packages = with pkgs; [
        libreoffice
        htop
        ripgrep
        zellij
        yazi
        bat
      ];

      # Apply the "simple_mouse" native Noctalia profile on every rebuild.
      # Runs after deSymlinkNoctalia (which converts noctalia-hm.nix symlinks to
      # regular files) so the cp -f overwrites the HM-generated settings with the
      # profile's settings, making simple_mouse the persistently active profile.
      # The profile files are archived in modules/users/sabine-noctalia/simple_mouse/.
      home.activation.applyNoctaliaProfile = lib.hm.dag.entryAfter ["deSymlinkNoctalia"] ''
        _profile_dir="$HOME/.config/noctalia/profiles/simple_mouse"
        $DRY_RUN_CMD mkdir -p "$_profile_dir"
        $DRY_RUN_CMD cp -f ${./sabine-noctalia/simple_mouse/settings.json}   "$_profile_dir/settings.json"
        $DRY_RUN_CMD cp -f ${./sabine-noctalia/simple_mouse/colors.json}     "$_profile_dir/colors.json"
        $DRY_RUN_CMD cp -f ${./sabine-noctalia/simple_mouse/plugins.json}    "$_profile_dir/plugins.json"
        $DRY_RUN_CMD cp -f ${./sabine-noctalia/simple_mouse/wallpapers.json} "$_profile_dir/wallpapers.json"
        $DRY_RUN_CMD cp -f ${./sabine-noctalia/simple_mouse/meta.json}       "$_profile_dir/meta.json"
        $DRY_RUN_CMD chmod 644 "$_profile_dir"/*
        # Apply as the active config (deSymlinkNoctalia already converted these to regular files)
        $DRY_RUN_CMD cp -f ${./sabine-noctalia/simple_mouse/settings.json} "$HOME/.config/noctalia/settings.json"
        $DRY_RUN_CMD cp -f ${./sabine-noctalia/simple_mouse/colors.json}   "$HOME/.config/noctalia/colors.json"
        $DRY_RUN_CMD chmod 644 "$HOME/.config/noctalia/settings.json" "$HOME/.config/noctalia/colors.json"
      '';

    };
  };
}
