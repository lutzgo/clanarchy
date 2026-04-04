# Per-workspace wallpapers: nix-anarchy SVGs recolored to the active Stylix base16 palette.
#
# All 5 SVGs share the same 22-color palette.  This module replaces those colors
# with Stylix base16 equivalents using sed, renders to PNG via rsvg-convert, then
# composites centered on a matching dark 1920×1080 background via ImageMagick.
#
# Each workspace gets a distinct accent color from the active Stylix scheme so
# workspaces are visually distinct at a glance:
#   ws1 logo.svg           → base08 red
#   ws2 logo-blue.svg      → base0D blue/teal
#   ws3 logo-smash.svg     → base0B green
#   ws4 logo-smash-alt.svg → base0E purple
#   ws5 logo-shirt-v1.svg  → base09 orange
#
# PNGs are symlinked into ~/Pictures/Wallpapers/ so the Noctalia picker finds them.
# wallpapers.json is overridden (lib.mkForce + force=true) to pin ws1 as the
# default, superseding the Stylix noctalia target's static image.

{ pkgs, config, lib, ... }:

let
  c = config.lib.stylix.colors;

  # ---------------------------------------------------------------------------
  # Source SVG fetches
  # ---------------------------------------------------------------------------
  fetchSvg = name: sha256: pkgs.fetchurl {
    url = "https://github.com/krebs/nix-anarchy/raw/master/${name}.svg";
    inherit sha256;
  };

  # ---------------------------------------------------------------------------
  # Recolor + render derivation
  #
  # Original SVG palette → Stylix base16 mapping:
  #   #ffffff           → base00  (white bg → dark bg)
  #   #000000           → base05  (black outlines → foreground)
  #   #4e4d52           → base02  (dark gray shadow)
  #   #666666           → base03  (medium gray)
  #   #adadad           → base04  (light gray)
  #   #5c201e           → base01  (darkest red → near-bg, blends in)
  #   #800000           → accentShade  (dark red → dark accent shade)
  #   #cc0001,#c24a46,
  #   #c53a3a           → accent  (bright/medium red → workspace accent)
  #   #d98d8a           → base06  (lightest salmon → light foreground)
  #   all 11 blue stops → blue    (nix-snowflake gradient → secondary accent)
  # ---------------------------------------------------------------------------
  mkWallpaper = { name, src, accent, accentShade, blue }:
    pkgs.runCommand "nix-anarchy-${name}.png"
      { nativeBuildInputs = [ pkgs.gnused pkgs.librsvg pkgs.imagemagick ]; }
      ''
        sed \
          -e 's/#ffffff/#${c.base00}/g' \
          -e 's/#000000/#${c.base05}/g' \
          -e 's/#4e4d52/#${c.base02}/g' \
          -e 's/#666666/#${c.base03}/g' \
          -e 's/#adadad/#${c.base04}/g' \
          -e 's/#5c201e/#${c.base01}/g' \
          -e 's/#800000/#${accentShade}/g' \
          -e 's/#cc0001/#${accent}/g' \
          -e 's/#c24a46/#${accent}/g' \
          -e 's/#c53a3a/#${accent}/g' \
          -e 's/#d98d8a/#${c.base06}/g' \
          -e 's/#415e9a/#${blue}/g' \
          -e 's/#4a6baf/#${blue}/g' \
          -e 's/#5277c3/#${blue}/g' \
          -e 's/#637ddf/#${blue}/g' \
          -e 's/#6478fa/#${blue}/g' \
          -e 's/#649afa/#${blue}/g' \
          -e 's/#699ad7/#${blue}/g' \
          -e 's/#719efa/#${blue}/g' \
          -e 's/#7363df/#${blue}/g' \
          -e 's/#7eb1dd/#${blue}/g' \
          -e 's/#7ebae4/#${blue}/g' \
          ${src} > recolored.svg

        # Render at 900px height (largest portrait SVGs are ~651px tall natively;
        # this keeps the logo well within 1080px).  Width scales automatically.
        rsvg-convert -h 900 recolored.svg -o rendered.png

        # Composite centered on a solid base00 1920×1080 canvas.
        magick -size 1920x1080 "xc:#${c.base00}" \
          rendered.png -gravity center -composite "$out"
      '';

  # ---------------------------------------------------------------------------
  # Per-workspace wallpaper derivations
  # ---------------------------------------------------------------------------
  wallpapers = {
    ws1 = mkWallpaper {
      name        = "ws1";
      src         = fetchSvg "logo"           "09q7pgj6bnk5q4pzfd9fbf2l27q2zlknw3h1abqb7yqaabn3yc00";
      accent      = c.base08;   # red
      accentShade = c.base01;
      blue        = c.base0D;
    };
    ws2 = mkWallpaper {
      name        = "ws2";
      src         = fetchSvg "logo-blue"      "18l5ha4xi2mb21vgm7byf8lw3m9xfvdm5rg1ym01vxpb13pfzjc1";
      accent      = c.base0D;   # blue/teal
      accentShade = c.base01;
      blue        = c.base0C;
    };
    ws3 = mkWallpaper {
      name        = "ws3";
      src         = fetchSvg "logo-smash"     "01wn76hnjr7jga23nm6knkdrq3dqrawn9km24zqvh5jn4yff6m7g";
      accent      = c.base0B;   # green
      accentShade = c.base01;
      blue        = c.base0C;
    };
    ws4 = mkWallpaper {
      name        = "ws4";
      src         = fetchSvg "logo-smash-alt" "0bbixs80gqlpfq34rmfsfsvzlrvs9nl3r6s6ds8p2ib4jmmm5xns";
      accent      = c.base0E;   # purple
      accentShade = c.base01;
      blue        = c.base0D;
    };
    ws5 = mkWallpaper {
      name        = "ws5";
      src         = fetchSvg "logo-shirt-v1"  "15s06ny62wgkpxw2jn6cvncl7kz4xcrb1pdc39wjx5g3ci6ysln1";
      accent      = c.base09;   # orange
      accentShade = c.base01;
      blue        = c.base0A;
    };
  };

in {
  # ---------------------------------------------------------------------------
  # Install wallpapers into ~/Pictures/Wallpapers/ for both desktop users.
  # Noctalia's picker scans that directory.
  # wallpapers.json is overridden with lib.mkForce to supersede the Stylix
  # noctalia target, which writes a plain { defaultWallpaper: <stylix-image> }.
  # force=true lets HM overwrite the file even if Noctalia replaced the symlink
  # at runtime.
  # ---------------------------------------------------------------------------
  home-manager.users.lgo = { lib, ... }: {
    home.file = {
      "Pictures/Wallpapers/ws1.png".source = wallpapers.ws1;
      "Pictures/Wallpapers/ws2.png".source = wallpapers.ws2;
      "Pictures/Wallpapers/ws3.png".source = wallpapers.ws3;
      "Pictures/Wallpapers/ws4.png".source = wallpapers.ws4;
      "Pictures/Wallpapers/ws5.png".source = wallpapers.ws5;

      ".cache/noctalia/wallpapers.json" = lib.mkForce {
        force = true;
        text = builtins.toJSON {
          wallpapers          = { "eDP-1" = "/home/lgo/Pictures/Wallpapers/ws1.png"; };
          defaultWallpaper    = "/home/lgo/Pictures/Wallpapers/ws1.png";
          usedRandomWallpapers = {};
        };
      };
    };
  };
}
