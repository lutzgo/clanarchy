{
  pkgs,
  config,
  ...
}: let
  schemePath = "${pkgs.base16-schemes}/share/themes/selenized-bright.yaml";

  c = config.lib.stylix.colors;

  nixWallpaper =
    pkgs.runCommand "biene-wallpaper.png"
    {nativeBuildInputs = [pkgs.imagemagick];}
    ''
      set -eu

      outpng="$out"

      W=3840
      H=2160

      BG="#${c.base00}"
      FG="#${c.base05}"
      A1="#${c.base0D}"
      A2="#${c.base0A}"

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
        -gravity southeast -annotate +80+70 "clanarchy / biene" \
        "$outpng"
    '';
in {
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
        applications = 11;
        terminal = 12;
        desktop = 11;
        popups = 11;
      };
    };

    cursor = {
      package = pkgs.adwaita-icon-theme;
      name = "Adwaita";
      size = 24;
    };

    targets.plymouth.enable = true; # Boot splash
  };
}
