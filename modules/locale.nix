{ lib, config, ... }:
let
  cfg = config.clanarchy.locale;
  localeStr = if cfg.language == "de_DE" then "de_DE.UTF-8" else "en_US.UTF-8";
in
{
  # ── Locale & keyboard options ────────────────────────────────────────────────
  #
  # language      — sets i18n.defaultLocale and all LC_* vars.
  # keyboard.*    — XKB layout wired to both GNOME/GDM (services.xserver.xkb)
  #                 and Niri (niri-hm.nix reads osConfig.clanarchy.locale.keyboard).
  #                 XKB_DEFAULT_* env vars are also exported so other Wayland
  #                 compositors pick them up automatically.
  #
  # German Umlauts on a US keyboard (lgo/miralda):
  #   Set keyboard.options = "compose:ralt"
  #   Right Alt becomes the Compose key.  Standard sequences:
  #     Compose " a → ä   Compose " o → ö   Compose " u → ü
  #     Compose " A → Ä   Compose " O → Ö   Compose " U → Ü
  #     Compose s s → ß

  options.clanarchy.locale = {
    language = lib.mkOption {
      type        = lib.types.enum [ "en_US" "de_DE" ];
      default     = "en_US";
      description = ''
        System locale and application language.
        "en_US" → English US for CLI and GUI.
        "de_DE" → German for CLI and GUI (GNOME displays in German).
      '';
    };

    keyboard = {
      layout = lib.mkOption {
        type        = lib.types.str;
        default     = "us";
        description = ''
          XKB keyboard layout (e.g. "us", "de").
          Applied to GDM/X11 sessions and exported as XKB_DEFAULT_LAYOUT.
          Niri reads this via osConfig in niri-hm.nix.
        '';
      };

      variant = lib.mkOption {
        type        = lib.types.nullOr lib.types.str;
        default     = null;
        description = "XKB keyboard variant. null = use the layout's default variant.";
      };

      options = lib.mkOption {
        type        = lib.types.nullOr lib.types.str;
        default     = null;
        description = ''
          XKB options, comma-separated. null = no extra options.
          Example: "compose:ralt" makes Right Alt the Compose key,
          enabling German Umlaut input on a US keyboard.
        '';
      };
    };
  };

  config = {
    # ── System locale ────────────────────────────────────────────────────────
    i18n.defaultLocale = localeStr;

    i18n.extraLocaleSettings = {
      LC_ADDRESS        = localeStr;
      LC_IDENTIFICATION = localeStr;
      LC_MEASUREMENT    = localeStr;
      LC_MONETARY       = localeStr;
      LC_NAME           = localeStr;
      LC_NUMERIC        = localeStr;
      LC_PAPER          = localeStr;
      LC_TELEPHONE      = localeStr;
      LC_TIME           = localeStr;
    };

    # ── XKB for X11/GDM (used by GNOME) ─────────────────────────────────────
    services.xserver.xkb = {
      layout  = cfg.keyboard.layout;
      variant = if cfg.keyboard.variant != null then cfg.keyboard.variant else "";
      options = if cfg.keyboard.options != null then cfg.keyboard.options else "";
    };

    # ── XKB env vars for Wayland compositors ─────────────────────────────────
    # Niri reads keyboard config from its own KDL (niri-hm.nix wires it directly),
    # but XKB_DEFAULT_* are exported as a fallback for other compositors / tools.
    environment.variables =
      { XKB_DEFAULT_LAYOUT = cfg.keyboard.layout; }
      // lib.optionalAttrs (cfg.keyboard.variant != null) { XKB_DEFAULT_VARIANT = cfg.keyboard.variant; }
      // lib.optionalAttrs (cfg.keyboard.options != null) { XKB_DEFAULT_OPTIONS = cfg.keyboard.options; };
  };
}
