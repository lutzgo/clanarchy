{ config, lib, pkgs, ... }:
let cfg = config.clanarchy.apps.media;
in {
  options.clanarchy.apps.media.enable =
    lib.mkEnableOption "media creation apps (OBS Studio, GIMP, darktable, Krita, gpu-screen-recorder, calibre)";

  config = lib.mkIf cfg.enable {
    programs.obs-studio = {
      enable  = true;
      plugins = with pkgs.obs-studio-plugins; [
        obs-vaapi             # AMD/Intel VAAPI hardware encoding
        obs-backgroundremoval # AI portrait segmentation
      ];
    };

    environment.systemPackages = with pkgs; [
      gimp
      darktable
      krita
      gpu-screen-recorder
      calibre
    ];
  };
}
