# Shared foot terminal config — imported by both niri-hm.nix and labwc-hm.nix.
# Sets MonaspiceAr Nerd Font Mono explicitly (lib.mkForce overrides Stylix injection
# which can fail to render the Nerd Font variant) and scales the point size with
# osConfig.clanarchy.display.scale so HiDPI and SD panels both get a comfortable size.
{ osConfig, lib, ... }:
let
  scale    = osConfig.clanarchy.display.scale;
  fontSize =
    if scale >= 2.0 then 14
    else if scale >= 1.25 then 12
    else 11;
in
{
  programs.foot = {
    enable = true;
    settings = {
      main = {
        term            = "xterm-256color";
        pad             = "8x8";
        resize-delay-ms = 100;
        # dpi-aware=no: the compositor handles output scaling; foot must not double-scale.
        dpi-aware       = "no";
        font            = lib.mkForce "MonaspiceAr Nerd Font Mono:size=${toString fontSize}";
      };
      bell = {
        urgent = false;
        notify = false;
        visual = false;
      };
      scrollback = {
        lines      = 10000;
        multiplier = 3.0;
      };
      url = {
        launch         = "xdg-open \${url}";
        label-letters  = "sadfjklewcmpgh";
        osc8-underline = "url-mode";
      };
      cursor = {
        style = "block";
        blink = false;
      };
      mouse = {
        hide-when-typing      = true;
        alternate-scroll-mode = "yes";
      };
      key-bindings = {
        clipboard-copy       = "Control+Shift+c XF86Copy";
        clipboard-paste      = "Control+Shift+v XF86Paste";
        font-increase        = "Control+plus Control+equal Control+KP_Add";
        font-decrease        = "Control+minus Control+KP_Subtract";
        font-reset           = "Control+0 Control+KP_0";
        scrollback-up-page   = "Shift+Page_Up";
        scrollback-down-page = "Shift+Page_Down";
        search-start         = "Control+Shift+r";
        show-urls-launch     = "Control+Shift+o";
      };
    };
  };
}
