# Nix-Anarchy wallpaper for biene — same SVG source as miralda, adapted for
# the 1366×768 panel and Catppuccin Mocha Stylix palette.
# One wallpaper (logo-blue.svg) in Catppuccin accent colors.
{
  pkgs,
  config,
  lib,
  ...
}: let
  c = config.lib.stylix.colors;

  fetchSvg = name: sha256:
    pkgs.fetchurl {
      url = "https://github.com/krebs/nix-anarchy/raw/master/${name}.svg";
      inherit sha256;
    };

  mkWallpaper = {
    name,
    src,
    accent,
    accentShade,
    blue,
  }:
    pkgs.runCommand "nix-anarchy-biene-${name}.png"
    {nativeBuildInputs = [pkgs.gnused pkgs.librsvg pkgs.imagemagick];}
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

      # Render at 600px height — fits centered on 1366×768 with comfortable margin.
      rsvg-convert -h 600 recolored.svg -o rendered.png

      # Composite centered on native 1366×768 canvas.
      magick -size 1366x768 "xc:#${c.base00}" \
        rendered.png -gravity center -composite "$out"
    '';

  wallpaper = mkWallpaper {
    name = "clanarchy";
    src = fetchSvg "logo-blue" "18l5ha4xi2mb21vgm7byf8lw3m9xfvdm5rg1ym01vxpb13pfzjc1";
    accent = c.base0D; # Catppuccin blue (#89b4fa)
    accentShade = c.base01;
    blue = c.base0C; # Catppuccin teal (#89dceb)
  };
in {
  # Use the Nix-Anarchy SVG as the stylix image (regreet greeter + plymouth).
  stylix.image = lib.mkForce wallpaper;

  # Install for sabine: seed the wallpaper and pin it as Noctalia's selection.
  home-manager.users.sabine = {lib, ...}: {
    home.activation.seedWallpaper = lib.hm.dag.entryAfter ["linkGeneration"] ''
      mkdir -p "$HOME/Pictures/Wallpapers"
      _wp_tmp="$HOME/Pictures/Wallpapers/clanarchy.png.tmp"
      cp ${wallpaper} "$_wp_tmp"
      chmod 644 "$_wp_tmp"
      mv "$_wp_tmp" "$HOME/Pictures/Wallpapers/clanarchy.png"
    '';

    # v5 setting, not a cache file.  This used to write
    # ~/.cache/noctalia/wallpapers.json; v5 does not read that, and keeps the
    # selection in config.toml under `wallpaper.default` instead — declared in
    # its schema as app-managed state, which is why it is absent from
    # `noctalia config export full`.  Leaving the old file in place is what
    # made jens come up with stylix.image rather than the Nix-Anarchy logo.
    #
    # mkForce because the Stylix noctalia target writes the same key.
    programs.noctalia.settings.wallpaper.default.path =
      lib.mkForce "/home/sabine/Pictures/Wallpapers/clanarchy.png";
  };
}
