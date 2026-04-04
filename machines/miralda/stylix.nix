 { pkgs, config, lib, ... }:

let
  # Pick a Base16/Base24 from https://tinted-theming.github.io/tinted-gallery/.
  schemePath = "${pkgs.base16-schemes}/share/themes/selenized-dark.yaml";

  # Helper: read base16 colors from the scheme file
  # Stylix exposes the resolved colors under config.lib.stylix.colors once enabled.
  # We'll generate the image *after* stylix has its colors by using those values.
  #
  # Note: this file is a NixOS module, so config is available.
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
  stylix = {
    enable = true;
    polarity = "dark";

    # Declarative scheme selection — change schemePath above to switch themes
    base16Scheme = schemePath;

    # Declarative wallpaper generation (built by Nix, colored by the selected scheme)
    image = nixWallpaper;

    fonts = {
      serif     = { package = pkgs.nerd-fonts.monaspace; name = "MonaspiceXe Nerd Font Propo"; };
      sansSerif = { package = pkgs.nerd-fonts.monaspace; name = "MonaspiceNe Nerd Font Propo"; };
      monospace = { package = pkgs.nerd-fonts.monaspace; name = "MonaspiceAr Nerd Font Mono";  };
      emoji     = { package = pkgs.noto-fonts-color-emoji; name = "Noto Color Emoji"; };
      sizes = {
        applications = 11;
        terminal     = 12;
        desktop      = 11;
        popups       = 11;
      };
    };

    # Adwaita cursor — matches XCURSOR_THEME env var set in desktop.nix
    cursor = {
      package = pkgs.adwaita-icon-theme;
      name = "Adwaita";
      size = 24;
    };

    targets.regreet.enable = true;   # GTK4 login screen — themed by Stylix
    targets.plymouth.enable = true;  # Boot splash — Stylix generates a spinner theme

};
}
