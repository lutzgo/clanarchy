{ pkgs, config, ... }:
let
  # Pick a Base16/Base24 from https://tinted-theming.github.io/tinted-gallery/.
  schemePath = "${pkgs.base16-schemes}/share/themes/selenized-black.yaml";

  # Stylix exposes the resolved colors under config.lib.stylix.colors once enabled.
  c = config.lib.stylix.colors;

  # Generate wallpaper using ImageMagick with scheme colors.
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
  imports = [ ../../modules/stylix-base.nix ];

  stylix = {
    base16Scheme = schemePath;
    image = nixWallpaper;

    fonts.sizes = {
      applications = 11;
      terminal     = 12;
      desktop      = 11;
      popups       = 11;
    };

    targets.regreet.enable = true;
  };
}
