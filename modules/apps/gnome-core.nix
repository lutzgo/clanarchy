# A handful of GNOME *applications* — not the GNOME desktop, which was
# removed along with modules/desktop/gnome.nix and the `gnome` desktop role.
#
# Sole consumer: biene (`clanarchy.apps.gnomeCoreApps.enable = true` in
# machines/biene/configuration.nix). biene runs labwc + Noctalia; these apps
# are just GTK programs that happen to ship under the GNOME umbrella, so they
# stand on their own with no GNOME session behind them. Kept for that reason
# when the desktop stack went away.
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
