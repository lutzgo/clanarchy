{ config, lib, pkgs, ... }:
let cfg = config.clanarchy.apps.graphics;
in {
  options.clanarchy.apps.graphics = {
    simple.enable = lib.mkEnableOption "image editing (GIMP, Inkscape, image viewer)";
    power.enable  = lib.mkEnableOption "professional graphics tools (darktable, Krita, color calibration)";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.simple.enable {
      environment.systemPackages = with pkgs; [
        gimp
        inkscape
        loupe
      ];
    })

    (lib.mkIf cfg.power.enable {
      services.colord.enable = true;

      environment.systemPackages = with pkgs; [
        darktable
        krita
        argyllcms
        displaycal
      ];
    })
  ];
}
