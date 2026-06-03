{ config, lib, pkgs, ... }:
let
  cfg = config.clanarchy.display;
  s   = cfg.scale;
in
{
  options.clanarchy.display = {
    scale = lib.mkOption {
      type        = lib.types.float;
      default     = 1.0;
      description = ''
        Physical display scale hint. Set to 1.0 for standard-DPI panels
        (e.g. 1366×768 at ~100 PPI), 1.25 for mid-range (e.g. Framework 13
        2256×1504 at ~200 PPI), or 2.0 for 4K/5K at ≥ 220 PPI.

        This value controls pre-compositor settings (systemd-boot console
        mode, Linux console font). The compositor output scale is configured
        separately via clanarchy.desktop.{niri,labwc}.display.scale.
      '';
    };
  };

  config = {
    # systemd-boot console mode: force 80×25 text mode on displays where the
    # native EFI framebuffer would produce unreadably small boot-menu text.
    # "0" = 80×25 (largest chars); "auto" = systemd picks based on screen size.
    boot.loader.systemd-boot.consoleMode =
      lib.mkDefault (if s >= 1.25 then "0" else "auto");

    # Linux console font: terminus bitmap fonts in sizes proportional to scale.
    # earlySetup embeds the font in the initrd so it's active before plymouth.
    console = lib.mkIf (s >= 1.25) {
      font      = if s >= 2.0 then "ter-v32n" else "ter-v24n";
      packages  = [ pkgs.terminus_font ];
      earlySetup = true;
    };
  };
}
