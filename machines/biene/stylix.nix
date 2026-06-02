{ pkgs, config, ... }:
let
  schemePath = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";

  c = config.lib.stylix.colors;

  nixWallpaper =
    pkgs.runCommand "clanarchy-wallpaper-biene.png"
      { nativeBuildInputs = [ pkgs.imagemagick ]; }
      ''
        set -eu

        W=1920
        H=1080

        BG="#${c.base00}"
        FG="#${c.base05}"
        A1="#${c.base0D}"
        A2="#${c.base0A}"

        # Snowflake geometry (proportional to H)
        ARM=$((H / 7))
        DX=$((ARM * 866 / 1000))
        DY=$((ARM / 2))
        SW=$((H / 120))
        PS=$((H / 50))
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
          -gravity southeast -annotate +40+35 "clanarchy" \
          "$out"
      '';
in
{
  stylix = {
    enable = true;
    polarity = "dark";

    base16Scheme = schemePath;
    image = nixWallpaper;

    fonts = {
      serif = {
        package = pkgs.nerd-fonts.monaspace;
        name = "MonaspiceXe Nerd Font Propo";
      };
      sansSerif = {
        package = pkgs.nerd-fonts.monaspace;
        name = "MonaspiceNe Nerd Font Propo";
      };
      monospace = {
        package = pkgs.nerd-fonts.monaspace;
        name = "MonaspiceAr Nerd Font Mono";
      };
      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };
      sizes = {
        applications = 9;
        terminal = 10;
        desktop = 9;
        popups = 9;
      };
    };

    cursor = {
      package = pkgs.adwaita-icon-theme;
      name = "Adwaita";
      size = 24;
    };

    targets.regreet.enable  = true;
    targets.plymouth.enable = true;
  };
}
