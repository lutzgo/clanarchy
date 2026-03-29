 { pkgs, config, lib, ... }:

let
  # Pick a Base16 Gruvbox Dark scheme from base16-schemes package.
  # (You can swap to gruvbox-dark-soft / medium if you prefer, depending on what exists in your nixpkgs.)
  schemePath = "${pkgs.base16-schemes}/share/themes/gruvbox-dark-medium.yaml";

  # Helper: read base16 colors from the scheme file
  # Stylix exposes the resolved colors under config.lib.stylix.colors once enabled.
  # We'll generate the image *after* stylix has its colors by using those values.
  #
  # Note: this file is a NixOS module, so config is available.
  c = config.lib.stylix.colors;

  # Generate wallpaper using ImageMagick with scheme colors.
  nixWallpaper =
    pkgs.runCommand "clanarchy-wallpaper-nix-gruvbox.png"
      {
        nativeBuildInputs = [ pkgs.imagemagick ];
      }
      ''
        set -eu

        outpng="$out"

        # Dimensions (change if you want)
        W=3840
        H=2160

        # Gruvbox-ish background + accents from the active Stylix scheme
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

    # Declarative scheme selection (Gruvbox Dark)
    base16Scheme = schemePath;

    # Declarative wallpaper generation (built by Nix, colored by the selected scheme)
    image = nixWallpaper;

    # HiDPI-appropriate font sizes for Framework 13 at 1.5x scale
    fonts.sizes = {
      applications = 11;
      terminal = 13;
      desktop = 11;
      popups = 11;
    };

    # Adwaita cursor — matches XCURSOR_THEME env var set in desktop.nix
    cursor = {
      package = pkgs.adwaita-icon-theme;
      name = "Adwaita";
      size = 24;
    };

};
}
