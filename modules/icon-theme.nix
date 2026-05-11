# modules/icon-theme.nix — shared GTK icon theme option
#
# Declares clanarchy.iconTheme.{name,package} and applies the theme to all
# Home Manager users via gtk.iconTheme.  Imported by the desktop modules
# (modules/desktop/gnome.nix and modules/desktop/niri.nix) so any machine
# using a graphical desktop gets the option automatically.
#
# Default: a Papirus-Dark variant whose folder icons are recolored to match
# the active Stylix base0D accent color.  Falls back to plain Papirus-Dark
# when Stylix is not enabled (e.g. homeserver).
{ config, lib, pkgs, ... }:
let
  # Build a Papirus-Dark copy with the folder blue replaced by base0D.
  # Papirus-Dark uses three blue shades in its places/ SVG files:
  #   #5294e2  main folder body
  #   #4877b1  folder tab / shadow
  #   #3a87e5  lighter highlight on some variants
  # We replace all three; the tab shade is darkened by 15 % relative to base0D
  # so the folder silhouette still reads as 3-D.
  styledPapirus =
    let
      c = config.lib.stylix.colors;
    in
    pkgs.runCommand "papirus-stylix" {
      nativeBuildInputs = [ pkgs.python3 pkgs.findutils ];
    } ''
      set -eu

      mkdir -p "$out/share/icons"

      # Copy Papirus-Dark as the starting point
      cp -r "${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark" \
            "$out/share/icons/Papirus-Stylix"
      chmod -R +w "$out/share/icons/Papirus-Stylix"

      # Derive a 15 %-darker shade for the folder tab / shadow
      darker=$(python3 -c "
h='${c.base0D}'
r,g,b = int(h[:2],16), int(h[2:4],16), int(h[4:6],16)
print(f'{int(r*0.85):02x}{int(g*0.85):02x}{int(b*0.85):02x}')
")

      # Replace only place SVGs (where the folder colors live)
      find "$out/share/icons/Papirus-Stylix" -path '*/places/*.svg' \
        -exec sed -i \
          -e "s/#5294e2/#${c.base0D}/g" \
          -e "s/#4877b1/#$darker/g"     \
          -e "s/#3a87e5/#${c.base0D}/g" \
          {} +

      # Rename theme and drop the breeze-dark Inherits dependency
      sed -i \
        -e 's/^Name=Papirus-Dark$/Name=Papirus-Stylix/'                       \
        -e 's/^Comment=.*$/Comment=Papirus Dark with Stylix accent folders/'  \
        -e 's/^Inherits=.*/Inherits=hicolor/'                                 \
        "$out/share/icons/Papirus-Stylix/index.theme"
    '';
in
{
  options.clanarchy.iconTheme = {
    name = lib.mkOption {
      type        = lib.types.str;
      description = ''
        GTK icon theme name applied to all graphical users.
        Must match the Name field in the theme package's index.theme.
      '';
      default = if config.stylix.enable then "Papirus-Stylix" else "Papirus-Dark";
    };

    package = lib.mkOption {
      type        = lib.types.package;
      description = ''
        Icon theme package.  The default builds a Stylix-recolored Papirus-Dark:
        folder icons are tinted with the Stylix base0D accent color.
        Set to pkgs.papirus-icon-theme (and name to "Papirus-Dark") to opt out
        of the color customization.
      '';
      default = if config.stylix.enable then styledPapirus else pkgs.papirus-icon-theme;
    };
  };

  config = {
    # Apply icon theme to every Home Manager user on this machine.
    # Desktop-specific dconf wiring (GNOME's org.gnome.desktop.interface
    # icon-theme key) is handled in modules/desktop/gnome.nix.
    home-manager.sharedModules = [{
      gtk.iconTheme = {
        name    = config.clanarchy.iconTheme.name;
        package = config.clanarchy.iconTheme.package;
      };
    }];
  };
}
