# Shared Home Manager module for any graphical user on miralda.
{ pkgs, pkgs-unstable, inputs, ... }:
{
  imports = [
    inputs.niri-flake.homeModules.config  # provides programs.niri.settings
    inputs.noctalia.homeModules.default   # provides programs.noctalia-shell option
  ];

  # Niri user config — declarative settings (niri-flake homeModules.config maps to KDL)
  # Note: niri-flake's HM module has no `enable` option; defining settings is sufficient.
  # UWSM manages the session lifecycle, so no niri-side systemd integration is needed.
  #
  # Use pkgs.niri (nixpkgs 25.11) for config.kdl validation instead of niri-flake's
  # bundled niri-stable (25.08), which fails with EMFILE in the Nix sandbox test suite.
  programs.niri = {
    package = pkgs.niri;
    settings = {
      # Framework 13 AMD — 2256x1504 panel at 1.5 scale
      outputs."eDP-1" = {
        scale = 1.5;
      };

      prefer-no-csd = true;

      input = {
        touchpad = {
          tap = true;
          natural-scroll = true;
          dwt = true;  # disable-while-typing
        };
      };

      # All app launches prefixed with "uwsm app --" so they run as systemd units
      binds = {
        "Mod+Return".action.spawn = [ "uwsm" "app" "--" "ghostty" ];
        "Mod+Q".action.close-window = {};
        "Mod+Space".action.spawn = [ "uwsm" "app" "--" "fuzzel" ];
        "Mod+Shift+E".action.quit = {};
        "Mod+1".action.focus-workspace = 1;
        "Mod+2".action.focus-workspace = 2;
        "Mod+3".action.focus-workspace = 3;
        "Mod+Shift+1".action.move-window-to-workspace = 1;
        "Mod+Shift+2".action.move-window-to-workspace = 2;
        "Mod+Shift+3".action.move-window-to-workspace = 3;
      };
    };
  };

  # Noctalia shell — configured declaratively via noctalia HM module
  # systemd.enable: creates a user service that starts after graphical-session.target,
  # replacing the fragile spawn-at-startup approach (which fires too early in the session).
  programs.noctalia-shell = {
    enable = true;
    systemd.enable = true;
    # Prevent noctalia from regenerating colors.json from its built-in scheme.
    # AppThemeService calls applyScheme(predefinedScheme) on wallpaper changes —
    # including startup when the wallpaper dir is empty. With predefinedScheme = "",
    # resolveSchemePath returns an invalid path, schemeReader fails silently, and
    # the Stylix-written colors.json is left intact.
    settings.colorSchemes.predefinedScheme = "";
  };

  # Stylix targets — noctalia needs explicit opt-in; KDE has a shellcheck bug so disable it.
  stylix.targets.noctalia-shell.enable = true;
  stylix.targets.kde.enable = false;

  # Adopt gtk4 default — stateVersion < 26.05 otherwise inherits gtk3 theme; stylix handles gtk4 theming via css.
  gtk.gtk4.theme = null;

  # Common graphical packages for all desktop users
  home.packages = with pkgs; [
    ghostty
    fuzzel
    grim
    slurp
    wl-clipboard
    playerctl
  ];
}
