{ pkgs, config, ... }:
# Stylix theming for birte (Steam Deck OLED).
#
# Scheme: Catppuccin Mocha (dark) — deep blacks look good on the AMOLED panel.
# Wallpaper: Nix-Anarchy SVG (logo-blue) recolored to the Mocha palette,
# rendered at native 1280×800.
# Targets: plymouth only (via stylix-base). SDDM and Plasma 6 aren't NixOS-level
# stylix targets in the pinned rev — they'd need HM wiring against the `deck`
# user which Jovian provisions itself, so we leave them at Jovian's defaults.
let
  schemePath = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";

  c = config.lib.stylix.colors;

  fetchSvg = name: sha256: pkgs.fetchurl {
    url    = "https://github.com/krebs/nix-anarchy/raw/master/${name}.svg";
    inherit sha256;
  };

  wallpaper =
    pkgs.runCommand "nix-anarchy-birte-clanarchy.png"
      { nativeBuildInputs = [ pkgs.gnused pkgs.librsvg pkgs.imagemagick ]; }
      ''
        sed \
          -e 's/#ffffff/#${c.base00}/g' \
          -e 's/#000000/#${c.base05}/g' \
          -e 's/#4e4d52/#${c.base02}/g' \
          -e 's/#666666/#${c.base03}/g' \
          -e 's/#adadad/#${c.base04}/g' \
          -e 's/#5c201e/#${c.base01}/g' \
          -e 's/#800000/#${c.base01}/g' \
          -e 's/#cc0001/#${c.base0D}/g' \
          -e 's/#c24a46/#${c.base0D}/g' \
          -e 's/#c53a3a/#${c.base0D}/g' \
          -e 's/#d98d8a/#${c.base06}/g' \
          -e 's/#415e9a/#${c.base0C}/g' \
          -e 's/#4a6baf/#${c.base0C}/g' \
          -e 's/#5277c3/#${c.base0C}/g' \
          -e 's/#637ddf/#${c.base0C}/g' \
          -e 's/#6478fa/#${c.base0C}/g' \
          -e 's/#649afa/#${c.base0C}/g' \
          -e 's/#699ad7/#${c.base0C}/g' \
          -e 's/#719efa/#${c.base0C}/g' \
          -e 's/#7363df/#${c.base0C}/g' \
          -e 's/#7eb1dd/#${c.base0C}/g' \
          -e 's/#7ebae4/#${c.base0C}/g' \
          ${fetchSvg "logo-blue" "18l5ha4xi2mb21vgm7byf8lw3m9xfvdm5rg1ym01vxpb13pfzjc1"} \
          > recolored.svg

        # Render at 640px height — leaves comfortable margin on 1280×800.
        rsvg-convert -h 640 recolored.svg -o rendered.png

        # Composite centered on the Deck's native 1280×800 panel.
        magick -size 1280x800 "xc:#${c.base00}" \
          rendered.png -gravity center -composite "$out"
      '';
in
{
  imports = [ ../../modules/stylix-base.nix ];

  stylix = {
    base16Scheme = schemePath;
    image = wallpaper;

    fonts.sizes = {
      applications = 10;
      terminal     = 11;
      desktop      = 10;
      popups       = 10;
    };
  };

  # Stylix's KDE HM target is disabled for `admin` ONLY — not for `deck`.
  #
  # The target builds `stylix-kde-apply-plasma-theme` with
  # `pkgs.writeShellApplication`, and stylix passes the account name through
  # `runtimeEnv`, which emits a `username=<user>` preamble line.  ShellCheck
  # rejects that line with SC2209 ("use var=$(command) to assign output")
  # when the value happens to be the name of a command it knows — and
  # `admin` is such a name.  `deck` is not:
  #
  #   writeShellApplication { runtimeEnv.username = "deck";  … }  → builds
  #   writeShellApplication { runtimeEnv.username = "admin"; … }  → SC2209
  #
  # This used to be disabled for every user on birte, which meant the
  # headless admin stub — an account that never opens Plasma — was the
  # reason `deck`, the account that only ever sees Plasma in Desktop Mode,
  # got no Plasma theming at all.  Scoping the workaround to the account
  # that actually trips it lets Desktop Mode follow the Stylix palette
  # properly, rather than only picking it up second-hand through the
  # GTK/Qt/cursor targets.
  home-manager.users.admin.stylix.targets.kde.enable = false;
}
