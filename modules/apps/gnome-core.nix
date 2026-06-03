{ config, lib, pkgs, ... }:
let cfg = config.clanarchy.apps.gnomeCoreApps;
in {
  options.clanarchy.apps.gnomeCoreApps.enable =
    lib.mkEnableOption "GNOME core apps (text editor, calculator, software center)";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      gnome-text-editor
      gnome-calculator
      gnome-software
    ];
  };
}
