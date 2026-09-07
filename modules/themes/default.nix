# Themed Stylix wiring for lgo's Niri workstations (miralda, jens).
#
# This is the *mechanism* half of modules/themes; ./palettes.nix is the data
# half. Splitting them is the whole point: everything below is identical for
# every theme, so a new theme costs one entry in palettes.nix, and a machine
# switches with one line:
#
#     clanarchy.theme = "selenized-black";   # machines/<name>/configuration.nix
#
# Previously each theme was a ~75-line file that machines imported from
# flake.nix, of which ~65 lines were a byte-identical copy of the wallpaper
# generator below. Two themes meant two copies to keep in step, and switching
# meant editing an import list in flake.nix.
#
# Machines with a genuinely bespoke Stylix setup (biene, birte — machine-native
# wallpaper resolutions, no regreet on birte) keep their own
# machines/<name>/stylix.nix and do not import this.
{ config, lib, pkgs, ... }:
let
  palettes = import ./palettes.nix;
  theme = palettes.${config.clanarchy.theme};

  # Stylix exposes the resolved colors under config.lib.stylix.colors once
  # enabled — so the wallpaper follows the selected scheme with no per-theme
  # code at all.
  c = config.lib.stylix.colors;

  # Grain-textured background with the clanarchy snowflake emblem, generated
  # from the active scheme.  Used by regreet and Plymouth; the Noctalia desktop
  # wallpaper is superseded per-workspace by modules/wallpapers/nix-anarchy.nix.
  nixWallpaper =
    pkgs.runCommand "clanarchy-wallpaper.png"
      {
        nativeBuildInputs = [ pkgs.imagemagick ];
      }
      ''
        set -eu

        outpng="$out"

        # Dimensions (change if you want)
        W=3840
        H=2160

        # Background + accents from the active Stylix scheme
        BG="#${c.base00}"
        FG="#${c.base05}"
        A1="#${c.base0D}"  # typically "blue"
        A2="#${c.base0A}"  # typically "yellow"
        A3="#${c.base08}"  # typically "red"

        # Create background with grain, snowflake emblem, and label
        magick -size ''${W}x''${H} xc:"$BG" \
          \( +clone -noise 2 -blur 0x1 \) -compose overlay -composite \
          -stroke "$A1" -strokewidth 18 -fill none \
          -draw "line $((W/2)),$((H/2-320)) $((W/2)),$((H/2+320))" \
          -draw "line $((W/2-277)),$((H/2-160)) $((W/2+277)),$((H/2+160))" \
          -draw "line $((W/2-277)),$((H/2+160)) $((W/2+277)),$((H/2-160))" \
          -stroke "$A2" -strokewidth 18 \
          -draw "circle $((W/2)),$((H/2-320)) $((W/2+1)),$((H/2-320))" \
          -draw "circle $((W/2)),$((H/2+320)) $((W/2+1)),$((H/2+320))" \
          -draw "circle $((W/2-277)),$((H/2-160)) $((W/2-276)),$((H/2-160))" \
          -draw "circle $((W/2+277)),$((H/2+160)) $((W/2+278)),$((H/2+160))" \
          -draw "circle $((W/2-277)),$((H/2+160)) $((W/2-276)),$((H/2+160))" \
          -draw "circle $((W/2+277)),$((H/2-160)) $((W/2+278)),$((H/2-160))" \
          -fill "$FG" -stroke none \
          -font "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf" \
          -pointsize 44 \
          -gravity southeast -annotate +80+70 "clanarchy" \
          "$outpng"
      '';
in
{
  imports = [ ../stylix-base.nix ];

  options.clanarchy.theme = lib.mkOption {
    # enum over the registry keys, so a typo names the valid alternatives
    # instead of silently picking the default.
    type = lib.types.enum (lib.attrNames palettes);
    default = "selenized-black";
    example = "gruvbox-light-hard";
    description = ''
      Which entry of modules/themes/palettes.nix to apply: base16 scheme,
      polarity, and font sizes. Add a theme by adding an entry there.
    '';
  };

  config.stylix = {
    base16Scheme = "${pkgs.base16-schemes}/share/themes/${theme.scheme}.yaml";
    image = nixWallpaper;

    # Overrides the fleet default (lib.mkDefault "dark") in ../stylix-base.nix.
    polarity = theme.polarity;

    fonts.sizes = {
      applications = 11;
      terminal     = 12;
      desktop      = 11;
      popups       = 11;
    } // (theme.fontSizes or { });

    # Both consumers use regreet; mkDefault so a future one can opt out.
    targets.regreet.enable = lib.mkDefault true;
  };
}
