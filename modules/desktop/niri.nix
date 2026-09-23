{
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [./desktop-common.nix];

  options.clanarchy.desktop.niri = {
    enable = lib.mkEnableOption "Niri Wayland compositor with Noctalia";

    display = {
      scale = lib.mkOption {
        type = lib.types.float;
        default = 1.25;
        description = "Output scale factor for the primary display (eDP-1).";
      };
      resolution = {
        width = lib.mkOption {
          type = lib.types.int;
          default = 2256;
          description = "Horizontal resolution of the primary display.";
        };
        height = lib.mkOption {
          type = lib.types.int;
          default = 1504;
          description = "Vertical resolution of the primary display.";
        };
      };
    };

    fprintd.enable = lib.mkEnableOption "fingerprint authentication via fprintd" // {default = true;};

    # This is niri's "dim inactive": niri has no dim-inactive setting of its
    # own, so an unfocused window is dimmed by dropping its opacity through a
    # `matches is-focused=false` window-rule. Lower means more dimmed. Some
    # apps opt out of it entirely — see the always-opaque rule in niri-hm.nix.
    opacity = {
      focused = lib.mkOption {
        type = lib.types.float;
        default = 0.8;
        description = "Baseline window opacity for focused windows.";
      };
      unfocused = lib.mkOption {
        type = lib.types.float;
        default = 0.65;
        description = "Window opacity for unfocused windows — the fleet's inactive-dim setting. The gap between this and `focused` is the dim; setting them equal removes it.";
      };

      terminal = lib.mkOption {
        type = lib.types.float;
        default = 0.95;
        description = "Opacity of focused foot terminals, overriding `focused` for them alone — terminals want to stay readable where other windows can afford to be translucent. This is a later window-rule than the `focused` baseline, so for a foot window `focused` has no effect at all; change this instead. Unfocused foot windows still take `unfocused`.";
      };

      opaqueApps = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          # ungoogled-chromium reports "chromium-browser" on Wayland — not
          # "chromium", and not the reverse-DNS "org.chromium.Chromium" its
          # desktop file suggests. Verified with `niri msg windows`.
          "^chromium-browser$"
          "^org\\.chromium\\.Chromium$"
          "^chromium$"
          "^google-chrome$"
          "^microsoft-edge$"
          "^org\\.gimp\\.GIMP$"
          "^gimp$"
          "^libreoffice"
          "^soffice$"
          "^darktable$"
        ];
        description = "app-id regexes held at full opacity while focused. These are the apps that render their own chrome and become unreadable when translucent. Unfocused they fall through to `unfocused` and get blurred like anything else. Note that a focused window not on this list gets no blur either — blur is applied to foot and to unfocused windows only — so an app missing from here looks transparent *and* unblurred. Setting this replaces the list; to keep the defaults and add to them, use `extraOpaqueApps`. Check an app's real app-id with `niri msg windows`.";
      };

      extraOpaqueApps = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["^Element$"];
        description = "app-id regexes appended to `opaqueApps`. Use this rather than `opaqueApps` when a machine needs one more entry, so it keeps picking up changes to the shared default.";
      };
    };

    # Two separate outlines, and they are easy to confuse. The *border* is drawn
    # around every window; the *focus ring* only around the focused one, outside
    # the border. Turning the border off therefore does not remove the outline
    # you see around the active window — that one is the ring, and niri's stock
    # ring colour is a light blue, which is where the unexplained cyan outline
    # comes from.
    #
    # Every colour option here (and shadow.color / shadow.inactiveColor) takes a
    # plain "#RRGGBB" or "#RRGGBBAA" string, so it can be fed from the active
    # Stylix palette instead of a literal — `config.lib.stylix.colors` is
    # available at the NixOS level, not just in Home Manager. Take `config` in
    # the machine's configuration.nix and write:
    #
    #     focusRing.activeColor = config.lib.stylix.colors.withHashtag.base0D;
    #     shadow.color = "#${config.lib.stylix.colors.base0E}40";   # + alpha
    #
    # Reading the palette in the same file that sets `clanarchy.theme` does not
    # recurse. Done this way the outline follows the machine's theme, so
    # switching clanarchy.theme stays the one-word change it is meant to be.
    border = {
      enable = lib.mkEnableOption "a border drawn around every window" // {default = true;};

      width = lib.mkOption {
        type = lib.types.ints.between 0 32;
        default = 1;
        description = "Window border thickness in logical pixels. Drawn outside the window, so raising it eats into the gaps rather than into the window.";
      };

      activeColor = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "#c4a7e7";
        description = "Border colour of the focused window, as #RRGGBB or #RRGGBBAA. Null keeps niri's own default.";
      };

      inactiveColor = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "#26233a";
        description = "Border colour of unfocused windows. Null keeps niri's own default.";
      };
    };

    focusRing = {
      enable = lib.mkEnableOption "a ring drawn around the focused window, outside its border" // {default = true;};

      width = lib.mkOption {
        type = lib.types.ints.between 0 32;
        default = 1;
        description = "Focus-ring thickness in logical pixels.";
      };

      activeColor = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "#c4a7e7";
        description = "Focus-ring colour on the focused window, as #RRGGBB or #RRGGBBAA. Null keeps niri's own default, which is a light blue and reads as cyan against most palettes.";
      };

      inactiveColor = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "#26233a";
        description = "Focus-ring colour on unfocused windows — visible only on the active window of an unfocused monitor. Null keeps niri's own default.";
      };
    };

    cornerRadius = lib.mkOption {
      type = lib.types.float;
      default = 8.0;
      description = "Rounded-corner radius for windows, in logical pixels. 0.0 gives square corners. Applied to all four corners together and paired with clip-to-geometry, so window content is clipped to the rounding instead of poking through it.";
    };

    # Drop shadows. Unlike blur, this is off by default: niri emits no `shadow`
    # node unless asked, and the fleet has never had one, so leaving it enabled
    # would be a look change smuggled in under an option. `niri-hm.nix` only
    # writes the node when `enable` is set, which keeps the generated
    # config.kdl byte-identical for a machine that does not opt in.
    #
    # The remaining defaults are niri's own, so `enable = true` alone gives
    # niri's stock shadow rather than something invented here.
    shadow = {
      enable = lib.mkEnableOption "drop shadows behind windows";

      softness = lib.mkOption {
        type = lib.types.numbers.nonnegative;
        default = 30;
        description = "Blur radius of the shadow, in logical pixels. This is the soft falloff at the edge; 0 gives a hard-edged slab.";
      };

      spread = lib.mkOption {
        type = lib.types.numbers.between (-64) 64;
        default = 5;
        description = "How far the shadow extends past the window before the falloff starts, in logical pixels. Negative values pull it inside the window's footprint.";
      };

      offset = {
        x = lib.mkOption {
          type = lib.types.numbers.between (-64) 64;
          default = 0;
          description = "Horizontal shadow displacement in logical pixels. Positive moves it right.";
        };
        y = lib.mkOption {
          type = lib.types.numbers.between (-64) 64;
          default = 5;
          description = "Vertical shadow displacement in logical pixels. Positive moves it down, which is what makes the window read as lifted.";
        };
      };

      drawBehindWindow = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Draw the shadow behind the window rather than only around it. niri cannot know a client-side-decorated window's corner radius and assumes square corners, which leaves shadow artifacts inside the rounded corners of CSD windows; this fixes them. Keep it false while windows are translucent — every window here is, via clanarchy.desktop.niri.opacity — because a shadow drawn behind a window is visible through it.";
      };

      color = lib.mkOption {
        type = lib.types.str;
        default = "#00000070";
        description = "Shadow color of the focused window, as #RRGGBBAA. The alpha channel is the shadow's strength; niri's default is 70/255.";
      };

      inactiveColor = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "#00000040";
        description = "Shadow color for unfocused windows, as #RRGGBBAA. Null keeps niri's own behaviour, which already draws inactive windows with a more transparent version of `color` — set this only to override how far it fades. This is the colour-only path; for a differently *shaped* shadow on unfocused windows, use `shadow.unfocused` below.";
      };

      # niri's layout-level shadow varies only by colour between focused and
      # unfocused. Anything else — a tighter shadow when a window recedes, no
      # offset, a smaller spread — has to come from a window-rule matching
      # is-focused=false, which is what this block emits.
      unfocused = {
        enable = lib.mkEnableOption "a separately shaped shadow for unfocused windows, emitted as an is-focused=false window-rule";

        softness = lib.mkOption {
          type = lib.types.nullOr lib.types.numbers.nonnegative;
          default = null;
          description = "Shadow softness for unfocused windows. Null inherits `shadow.softness`.";
        };

        spread = lib.mkOption {
          type = lib.types.nullOr (lib.types.numbers.between (-64) 64);
          default = null;
          description = "Shadow spread for unfocused windows. Null inherits `shadow.spread`.";
        };

        offset = {
          x = lib.mkOption {
            type = lib.types.nullOr (lib.types.numbers.between (-64) 64);
            default = null;
            description = "Horizontal shadow offset for unfocused windows. Null inherits `shadow.offset.x`.";
          };
          y = lib.mkOption {
            type = lib.types.nullOr (lib.types.numbers.between (-64) 64);
            default = null;
            description = "Vertical shadow offset for unfocused windows. Null inherits `shadow.offset.y`.";
          };
        };

        color = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "#00000030";
          description = "Shadow colour for unfocused windows. Null inherits `shadow.color`. Set here rather than in `shadow.inactiveColor` when you are already using this block — the window-rule is evaluated after the layout node, so this wins.";
        };
      };
    };

    input.pointerSpeed = lib.mkOption {
      type = lib.types.float;
      default = 0.0;
      description = "Pointer acceleration speed applied to both touchpad and mouse. Range: -1.0 (slowest) to 1.0 (fastest). 0.0 is libinput's neutral baseline.";
    };

    # Background blur (niri v26.04+). niri-flake's Nix schema does not yet
    # expose the `blur { }` block or `background-effect { }` rule child, so
    # `niri-hm.nix` injects raw KDL into the final config.kdl behind this flag.
    # The four parameters below are niri's own defaults, per the v26.04 wiki;
    # they are the whole of the global `blur { }` node. Which surfaces get a
    # blurred backdrop is a separate matter, decided by the window-rules and
    # layer-rules in `niri-hm.nix` and deliberately not an option — those rules
    # carry reasoning (notification surfaces are excluded because niri blurs
    # the surface rectangle, not what it paints) that a machine should not be
    # able to override by accident.
    blur = {
      enable = lib.mkEnableOption "background blur behind translucent windows and Noctalia layer surfaces" // {default = true;};

      passes = lib.mkOption {
        type = lib.types.ints.between 1 10;
        default = 3;
        description = "Number of dual-Kawase blur passes. Each pass widens the blur and costs a further GPU round-trip over the whole blurred region.";
      };

      offset = lib.mkOption {
        type = lib.types.float;
        default = 3.0;
        description = "Sampling offset per pass, in pixels. Widens the blur more cheaply than another pass does, at the cost of banding once it outruns the sample count.";
      };

      noise = lib.mkOption {
        type = lib.types.float;
        default = 0.02;
        description = "Film grain mixed into the blurred backdrop, 0.0 to 1.0. Masks the banding a blurred gradient otherwise shows.";
      };

      saturation = lib.mkOption {
        type = lib.types.float;
        default = 1.5;
        description = "Saturation of the blurred backdrop. 1.0 leaves colors as sampled; above 1.0 compensates for the wash-out that averaging the wallpaper causes.";
      };
    };

    # Xwayland. Niri has no built-in X server; without xwayland-satellite an
    # X11-only app sees no DISPLAY at all and dies at XOpenDisplay. Wired the
    # same way as blur — niri-flake's schema has no `xwayland-satellite { }`
    # node either, so `niri-hm.nix` injects it as raw KDL.
    xwayland.enable = lib.mkEnableOption "Xwayland for X11-only applications, via xwayland-satellite" // {default = true;};

    wallpaper.workspaceColors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["red" "blue" "green" "purple" "orange"];
      description = "Per-workspace accent colors (5 entries for workspaces 1-5). Reserved for future Noctalia workspace theming.";
    };
  };

  config = lib.mkIf config.clanarchy.desktop.niri.enable {
    # Niri compositor
    programs.niri.enable = true;

    # UWSM — binPath must be niri-session (not niri): exports WAYLAND_DISPLAY/NIRI_SOCKET
    # to systemd user manager; without --session, UWSM's waitenv times out (30s).
    programs.uwsm.waylandCompositors.niri = {
      prettyName = "Niri";
      comment = "Niri compositor managed by UWSM";
      binPath = "/run/current-system/sw/bin/niri-session";
    };

    # XDG portal — gtk portal is the recommended choice for Niri
    xdg.portal = {
      enable = true;
      extraPortals = [pkgs.xdg-desktop-portal-gtk];
      config.common.default = "gtk";
    };

    # V4L2 loopback — virtual camera device used by OBS's "Start Virtual Camera".
    # UVC input (Sony ILCE, etc.) works via the built-in uvcvideo module; no extra config needed.
    # exclusive_caps=1 makes apps (Meet, Zoom, …) enumerate the loopback as a capture device.
    # video_nr=10 avoids collisions with physical cameras at /dev/video0…
    boot.extraModulePackages = [config.boot.kernelPackages.v4l2loopback];
    boot.kernelModules = ["v4l2loopback"];
    boot.extraModprobeConfig = lib.mkAfter ''
      options v4l2loopback devices=1 video_nr=10 card_label="OBS Virtual Camera" exclusive_caps=1
    '';
    environment.systemPackages = [ pkgs.v4l-utils ];

    # fprintd service (controlled by fprintd option)
    services.fprintd.enable = lib.mkDefault config.clanarchy.desktop.niri.fprintd.enable;

    # Fingerprint PAM auth — use per-service sub-attribute form so each service's
    # other options (unixAuth, etc.) are preserved via normal submodule merging.
    security.pam.services.login.fprintAuth   = lib.mkIf config.clanarchy.desktop.niri.fprintd.enable true;
    security.pam.services.greetd.fprintAuth  = lib.mkIf config.clanarchy.desktop.niri.fprintd.enable true;
    security.pam.services.sudo.fprintAuth    = lib.mkIf config.clanarchy.desktop.niri.fprintd.enable true;
    # Noctalia lockscreen — PamContext in QML requires a dedicated PAM service.
    security.pam.services.noctalia.fprintAuth = lib.mkIf config.clanarchy.desktop.niri.fprintd.enable true;

    # Shared HM desktop module for all graphical users
    home-manager.sharedModules = [./niri-hm.nix];
  };
}
