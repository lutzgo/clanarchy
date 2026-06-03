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
    home-manager.users.sabine = { pkgs, config, lib, osConfig, ... }:
    let
      # Seed content for plugins.json — written as a writable regular file so
      # Noctalia can update it at runtime (track download status, installed state).
      # Unlike xdg.configFile (Nix store symlink), Noctalia can write back to this.
      initialPluginsJson = pkgs.writeText "noctalia-plugins-seed.json" (builtins.toJSON {
        sources = [
          {
            enabled = true;
            name    = "Noctalia Plugins";
            url     = "https://github.com/noctalia-dev/noctalia-plugins";
          }
        ];
        states = {
          "clipper"             = { enabled = true; sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins"; };
          "file-search"         = { enabled = true; sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins"; };
          "keybind-cheatsheet"  = { enabled = true; sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins"; };
          "network-manager-vpn" = { enabled = true; sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins"; };
          "screen-shot-and-record" = { enabled = true; sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins"; };
          "screen-toolkit"      = { enabled = true; sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins"; };
          "shell-profiles"      = { enabled = true; sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins"; };
          "usb-drive-manager"   = { enabled = true; sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins"; };
          "valent-connect"      = { enabled = true; sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins"; };
          "todo"                = { enabled = true; sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins"; };
        };
        version = 2;
      });
    in
    {
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
      ];

      # Seed the "simple_mouse" native Noctalia profile on fresh installs.
      # .config is persisted via impermanence, so this only runs when the profile
      # directory is absent (first boot after clan machines install).
      # The profile files are archived in modules/users/sabine-noctalia/simple_mouse/.
      home.activation.seedNoctaliaProfile = lib.hm.dag.entryAfter ["linkGeneration"] ''
        _profile_dir="$HOME/.config/noctalia/profiles/simple_mouse"
        if [ ! -d "$_profile_dir" ]; then
          $DRY_RUN_CMD mkdir -p "$_profile_dir"
          $DRY_RUN_CMD cp ${./sabine-noctalia/simple_mouse/settings.json}   "$_profile_dir/settings.json"
          $DRY_RUN_CMD cp ${./sabine-noctalia/simple_mouse/colors.json}     "$_profile_dir/colors.json"
          $DRY_RUN_CMD cp ${./sabine-noctalia/simple_mouse/plugins.json}    "$_profile_dir/plugins.json"
          $DRY_RUN_CMD cp ${./sabine-noctalia/simple_mouse/wallpapers.json} "$_profile_dir/wallpapers.json"
          $DRY_RUN_CMD cp ${./sabine-noctalia/simple_mouse/meta.json}       "$_profile_dir/meta.json"
          $DRY_RUN_CMD chmod -R 644 "$_profile_dir"/*
        fi
      '';

      # Seed plugins.json as a writable regular file — Noctalia must be able to
      # update it at runtime to track which plugin files have been downloaded.
      # xdg.configFile would create a read-only Nix store symlink, which blocks
      # the plugin installer and leaves all plugins in the "unconnected" state.
      # This hook only writes the seed if the file is absent or still a symlink
      # (i.e. left over from a previous xdg.configFile deployment). Once Noctalia
      # has written its own state, subsequent rebuilds leave the file untouched.
      home.activation.seedNoctaliaPlugins = lib.hm.dag.entryAfter ["linkGeneration"] ''
        _json="$HOME/.config/noctalia/plugins.json"
        if [ ! -e "$_json" ] || [ -L "$_json" ]; then
          rm -f "$_json"
          cp ${initialPluginsJson} "$_json"
          chmod 644 "$_json"
        fi
      '';
    };
  };
}
