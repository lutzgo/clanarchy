# Shared Stylix baseline for all headful clanarchy machines.
#
# Each machine's own stylix.nix imports this and layers on the per-machine
# bits: `stylix.base16Scheme`, `stylix.image`, `stylix.fonts.sizes`, and
# `stylix.targets.regreet.enable` where the machine actually uses regreet
# (birte skips it — SDDM is provisioned by Jovian).
{
  lib,
  pkgs,
  ...
}: {
  stylix = {
    enable = true;

    # mkDefault, not a plain value: modules/themes/default.nix sets polarity
    # from the machine's chosen palette (modules/themes/palettes.nix), and a
    # light palette overrides this. Machines with no palette take the default.
    polarity = lib.mkDefault "dark";

    # Stylix's release version follows a different cadence than NixOS 26.05;
    # the warning about "different Stylix and NixOS versions" is expected in
    # this pin and safe to silence — we track upstream stylix manually.
    enableReleaseChecks = false;

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
    };

    # Adwaita cursor — matches XCURSOR_THEME env var set by desktop modules.
    cursor = {
      package = pkgs.adwaita-icon-theme;
      name = "Adwaita";
      size = 24;
    };

    # Boot splash — Stylix generates a spinner theme from the active scheme.
    targets.plymouth.enable = true;
  };
}
