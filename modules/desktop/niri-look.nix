# lgo's niri look — an accent-coloured glow instead of a drop shadow (the
# shadow takes the palette's base0D at alpha 0x50, no offset), no border and
# no focus ring, stronger blur, 10px corners, translucent windows.
#
# ONE COPY for every niri machine: miralda and jens (lgo), birte (deck) and
# ernst's TV desktop (go). It used to be written out in miralda's and jens's
# configuration.nix with a "keep the two in step" note; a third and fourth
# copy would have made that note a promise nobody keeps. A machine adds to it
# in its own config (jens: smaller gaps for the 12" panel).
#
# NixOS-level, because these are clanarchy.desktop.niri options; `config` is
# taken for the Stylix palette (config.lib.stylix.colors).
{config, ...}: {
  clanarchy.desktop.niri = {
    shadow = {
      enable = true;
      softness = 15;
      spread = 3;
      offset.y = 0;
      offset.x = 0;
      color = "#${config.lib.stylix.colors.base0D}50";
      unfocused = {
        enable = false;
      };
    };
    blur = {
      passes = 5;
      offset = 6.5;
      noise = 0.0;
      saturation = 1.5;
    };
    cornerRadius = 10.0;
    border = {
      enable = false;
      width = 0;
    };
    opacity = {
      focused = 0.75;
      unfocused = 0.65;
      terminal = 0.75;
    };
    focusRing.enable = false;
  };
}
