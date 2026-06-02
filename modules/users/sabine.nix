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
    home-manager.users.sabine = { pkgs, config, lib, ... }: {
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

      # Declare which Noctalia plugins are installed/enabled. Plugins
      # installed via the Noctalia UI survive reboots (impermanence) but are
      # re-set to this list on each rebuild. Add to the states map whenever
      # a new plugin should be pinned declaratively.
      xdg.configFile."noctalia/plugins.json" = {
        force = true;
        text = builtins.toJSON {
          sources = [
            {
              enabled   = true;
              name      = "Noctalia Plugins";
              url       = "https://github.com/noctalia-dev/noctalia-plugins";
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
        };
      };
    };
  };
}
