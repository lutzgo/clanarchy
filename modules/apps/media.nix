{ config, lib, pkgs, ... }:
let cfg = config.clanarchy.apps.media;
in {
  options.clanarchy.apps.media.enable =
    lib.mkEnableOption "media apps (OBS Studio, VLC, calibre)";

  config = lib.mkIf cfg.enable {
    programs.obs-studio = {
      enable  = true;
      plugins = with pkgs.obs-studio-plugins; [
        obs-vaapi             # AMD/Intel VAAPI hardware encoding
        obs-backgroundremoval # AI portrait segmentation
      ];
    };

    environment.systemPackages = with pkgs; [
      vlc
      calibre
    ];
  };
}
