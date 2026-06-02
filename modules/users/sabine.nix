{ config, lib, pkgs, ... }:
let
  cfg = config.clanarchy.users.sabine;
in
{
  options.clanarchy.users.sabine.enable =
    lib.mkEnableOption "sabine user profile (GNOME, LibreOffice, Thunderbird, Firefox)";

  config = lib.mkIf cfg.enable {

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
          "screen-toolkit"      = { enabled = true; sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins"; };
          "shell-profiles"      = { enabled = true; sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins"; };
          "usb-drive-manager"   = { enabled = true; sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins"; };
          "valent-connect"      = { enabled = true; sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins"; };
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

      # Populate ~/Pictures/Wallpapers with the Stylix-generated wallpaper so
      # Noctalia's wallpaper picker has something to display on first login.
      # The activation hook runs before linkGeneration so the dir exists when
      # home.file creates the symlink inside it.
      home.activation.createWallpaperDir = lib.hm.dag.entryBefore ["linkGeneration"] ''
        mkdir -p "$HOME/Pictures/Wallpapers"
      '';
      home.file."Pictures/Wallpapers/clanarchy.png" = {
        force  = true;
        source = osConfig.stylix.image;
      };

      home.packages = with pkgs; [
        libreoffice
        htop
        ripgrep
      ];

      # Auto-apply the "Sabine" Noctalia shell profile after each HM activation.
      # The profile is stored in the persisted shell-profiles plugin directory.
      # Workflow: Sabine configures her preferred layout in the Noctalia UI →
      # saves it as "Sabine" via Settings → Shell Profiles → Save Profile.
      # Every subsequent rebuild then automatically restores her settings.
      #
      # To pin a profile in Nix (survive fresh installs), add:
      #   xdg.configFile."noctalia/plugins/shell-profiles/assets/profiles/Sabine/settings.json".source = ./sabine-noctalia-settings.json;
      home.activation.applyNoctaliaProfile = lib.hm.dag.entryAfter ["linkGeneration"] ''
        _profile_dir="$HOME/.config/noctalia/plugins/shell-profiles/assets/profiles/Sabine"
        _apply_script="$HOME/.config/noctalia/plugins/shell-profiles/assets/scripts/apply-profile.sh"
        _cfg_dir="$HOME/.config/noctalia/"
        if [ -d "$_profile_dir" ] && [ -f "$_apply_script" ]; then
          $DRY_RUN_CMD sh "$_apply_script" "$_profile_dir" "$_cfg_dir"
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
