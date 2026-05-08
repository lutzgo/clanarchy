{ lib, ... }:
#
# @clanarchy/desktop — assign each machine a desktop environment via inventory.
#
# Replaces the previous pattern of importing all modules/desktop/*.nix into every
# machine in flake.nix and toggling them with clanarchy.desktop.*.enable options.
# Now each machine is assigned to exactly one desktop role and only that module
# is imported and enabled.
#
# Roles:
#   niri   — Niri Wayland compositor, UWSM, Noctalia, regreet
#   gnome  — GNOME desktop with GDM
#   kde    — KDE Plasma 6 with SDDM
#
{
  _class = "clan.service";
  manifest.name = "@clanarchy/desktop";
  manifest.description = "Assign each machine a desktop environment (niri, gnome, kde).";
  manifest.readme = builtins.readFile ./desktop.md;

  roles.niri = {
    description = "Niri Wayland compositor with UWSM session management and Noctalia shell.";
    interface.options = {
      display.scale = lib.mkOption {
        type = lib.types.float;
        default = 1.25;
        description = "Output scale factor for the primary display (eDP-1).";
      };
      display.width = lib.mkOption {
        type = lib.types.int;
        default = 2256;
        description = "Horizontal resolution of the primary display.";
      };
      display.height = lib.mkOption {
        type = lib.types.int;
        default = 1504;
        description = "Vertical resolution of the primary display.";
      };
      input.pointerSpeed = lib.mkOption {
        type = lib.types.float;
        default = 0.4;
        description = "Touchpad/pointer acceleration. Range: -1.0 (slowest) to 1.0 (fastest).";
      };
    };

    perInstance =
      { settings, ... }:
      {
        nixosModule =
          { ... }:
          {
            imports = [ ../modules/desktop/niri.nix ];
            clanarchy.desktop.niri.enable = true;
            clanarchy.desktop.niri.display.scale = settings.display.scale;
            clanarchy.desktop.niri.display.resolution.width = settings.display.width;
            clanarchy.desktop.niri.display.resolution.height = settings.display.height;
            clanarchy.desktop.niri.input.pointerSpeed = settings.input.pointerSpeed;
          };
      };
  };

  roles.gnome = {
    description = "GNOME desktop environment with GDM, optional per-user dconf defaults.";
    interface.options.sabine =
      lib.mkEnableOption "Sabine's personal GNOME dconf defaults (extensions, keybindings)";

    perInstance =
      { settings, ... }:
      {
        nixosModule =
          { ... }:
          {
            imports = [ ../modules/desktop/gnome.nix ];
            clanarchy.desktop.gnome.enable = true;
            clanarchy.desktop.gnome.sabine = settings.sabine;
          };
      };
  };

  roles.kde = {
    description = "KDE Plasma 6 desktop environment with SDDM Wayland session.";
    perInstance =
      { ... }:
      {
        nixosModule =
          { ... }:
          {
            imports = [ ../modules/desktop/kde.nix ];
            clanarchy.desktop.kde.enable = true;
          };
      };
  };
}
