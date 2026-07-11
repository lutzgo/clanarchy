{ pkgs, config, ... }:
let
  schemePath = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";

  c = config.lib.stylix.colors;

  nixWallpaper =
    pkgs.runCommand "clanarchy-wallpaper-biene.png"
      { nativeBuildInputs = [ pkgs.imagemagick ]; }
      ''
        set -eu

        # Native screen resolution (eDP-1, 1366×768, scale 1.0)
        W=1366
        H=768

        BG="#${c.base00}"
        FG="#${c.base05}"
        A1="#${c.base0D}"
        A2="#${c.base0A}"

        # Geometry scaled from miralda's 3840×2160 reference design:
        #   ARM=320 DX=277 DY=160 SW=18 pointsize=44
        ARM=$((H * 320 / 2160))   # ≈113
        DX=$((ARM * 866 / 1000))  # ≈98  (ARM × sin60°)
        DY=$((ARM / 2))           # ≈56
        SW=$((H * 18 / 2160))     # ≈6
        PS=$((W * 44 / 3840))     # ≈15
        CX=$((W / 2))
        CY=$((H / 2))

        magick -size ''${W}x''${H} xc:"$BG" \
          \( +clone -noise 2 -blur 0x1 \) -compose overlay -composite \
          -stroke "$A1" -strokewidth "$SW" -fill none \
          -draw "line $CX,$((CY - ARM)) $CX,$((CY + ARM))" \
          -draw "line $((CX - DX)),$((CY - DY)) $((CX + DX)),$((CY + DY))" \
          -draw "line $((CX - DX)),$((CY + DY)) $((CX + DX)),$((CY - DY))" \
          -stroke "$A2" -strokewidth "$SW" \
          -draw "circle $CX,$((CY - ARM)) $((CX + 1)),$((CY - ARM))" \
          -draw "circle $CX,$((CY + ARM)) $((CX + 1)),$((CY + ARM))" \
          -draw "circle $((CX - DX)),$((CY - DY)) $((CX - DX + 1)),$((CY - DY))" \
          -draw "circle $((CX + DX)),$((CY + DY)) $((CX + DX + 1)),$((CY + DY))" \
          -draw "circle $((CX - DX)),$((CY + DY)) $((CX - DX + 1)),$((CY + DY))" \
          -draw "circle $((CX + DX)),$((CY - DY)) $((CX + DX + 1)),$((CY - DY))" \
          -fill "$FG" -stroke none \
          -font "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf" \
          -pointsize "$PS" \
          -gravity southeast -annotate +30+20 "clanarchy" \
          "$out"
      '';
in
{
  imports = [ ../../modules/stylix-base.nix ];

  stylix = {
    base16Scheme = schemePath;
    image = nixWallpaper;

    fonts.sizes = {
      applications = 9;
      terminal     = 10;
      desktop      = 9;
      popups       = 9;
    };

    targets.regreet.enable = true;
  };
}
