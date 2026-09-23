# Shared Home Manager module for any graphical user — loaded by modules/desktop/niri.nix
# via home-manager.sharedModules.  `osConfig` exposes clanarchy.desktop.niri options.
{
  pkgs,
  pkgs-unstable,
  inputs,
  config,
  lib,
  osConfig,
  ...
}: {
  imports = [
    inputs.niri-flake.homeModules.config  # provides programs.niri.settings
    ./noctalia-hm.nix                     # shared Noctalia settings, starship, packages
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
      outputs."eDP-1" = {
        scale = osConfig.clanarchy.desktop.niri.display.scale;
      };

      prefer-no-csd = true;

      # Top-left hot corner (opens the Overview) off. It sits exactly where a
      # maximized window's close/menu controls are, so it fires constantly by
      # accident. Note this config binds no `toggle-overview` key, so with the
      # corner off the Overview is unreachable — add a bind below if it is
      # ever wanted deliberately.
      #
      # niri 26.04 has no per-corner toggle — `hot-corners { top-left false }`
      # is rejected by `niri validate` — and top-left is the only corner niri
      # binds, so disabling the feature wholesale is exactly equivalent here.
      gestures.hot-corners.enable = false;

      spawn-at-startup = [
        {command = ["uwsm" "app" "--" "noctalia-shell"];}
        {command = ["keepassxc" "--minimized"];}
      ];

      # An unset colour must leave `active` / `inactive` unmentioned entirely,
      # not set to null and not set via mkIf. niri-flake types them as a
      # nullOr of colour-or-gradient defaulting to null, so writing
      # `active.color = lib.mkIf false …` defines `active` as an attrset whose
      # `color` has no value — which fails at eval with "was accessed but has
      # no value defined" rather than falling back to niri's default. Hence
      # optionalAttrs at the parent level.
      layout.border = let
        b = osConfig.clanarchy.desktop.niri.border;
      in
        {
          enable = b.enable;
          width = b.width;
        }
        // lib.optionalAttrs (b.activeColor != null) {active.color = b.activeColor;}
        // lib.optionalAttrs (b.inactiveColor != null) {inactive.color = b.inactiveColor;};

      layout.focus-ring = let
        r = osConfig.clanarchy.desktop.niri.focusRing;
      in
        {
          enable = r.enable;
          width = r.width;
        }
        // lib.optionalAttrs (r.activeColor != null) {active.color = r.activeColor;}
        // lib.optionalAttrs (r.inactiveColor != null) {inactive.color = r.inactiveColor;};

      # Only written when enabled, so a machine that leaves shadows off gets
      # the same config.kdl it had before the option existed — niri emits no
      # `shadow` node of its own accord. `inactive-color` is omitted when null,
      # which is how niri is told to reuse `color` for unfocused windows.
      layout.shadow = let
        s = osConfig.clanarchy.desktop.niri.shadow;
      in
        lib.mkIf s.enable {
          enable = true;
          softness = s.softness;
          spread = s.spread;
          offset = {
            x = s.offset.x;
            y = s.offset.y;
          };
          draw-behind-window = s.drawBehindWindow;
          color = s.color;
          inactive-color = s.inactiveColor;
        };

      input = {
        keyboard.xkb = {
          layout = osConfig.clanarchy.locale.keyboard.layout;
          # niri-flake types these as string, not nullOr string — convert null → ""
          variant = let
            v = osConfig.clanarchy.locale.keyboard.variant;
          in
            if v != null
            then v
            else "";
          options = let
            o = osConfig.clanarchy.locale.keyboard.options;
          in
            if o != null
            then o
            else "";
        };

        touchpad = {
          tap = true;
          tap-button-map = "left-right-middle"; # 1/2/3-finger tap → left/right/middle
          natural-scroll = true;
          dwt = true; # disable-while-typing
          accel-speed = osConfig.clanarchy.desktop.niri.input.pointerSpeed;
        };
        mouse = {
          # natural-scroll omitted → defaults false (regular wheel direction)
          accel-speed = osConfig.clanarchy.desktop.niri.input.pointerSpeed;
        };
      };

      # Window rules: rounded corners, focus-aware opacity.
      # Rules are evaluated in order; the last matching rule for each property wins.
      # Baseline, terminal override and inactive dim all come from
      # clanarchy.desktop.niri.opacity. The opaqueApps rule is last and matches
      # on is-focused=true, so those apps are opaque while focused and dim and
      # blur like everything else once they are not.
      window-rules = [
        {
          # Global baseline: rounded corners + focused opacity
          geometry-corner-radius = let
            r = osConfig.clanarchy.desktop.niri.cornerRadius;
          in {
            top-left = r;
            top-right = r;
            bottom-right = r;
            bottom-left = r;
          };
          clip-to-geometry = true;
          opacity = osConfig.clanarchy.desktop.niri.opacity.focused;
        }
        {
          # Foot terminals: more opaque than the global baseline, so terminal
          # text stays readable. This rule is later than the baseline, so it is
          # opacity.terminal — not opacity.focused — that governs a focused
          # foot window.
          matches = [{app-id = "^foot$";}];
          opacity = osConfig.clanarchy.desktop.niri.opacity.terminal;
        }
        {
          # Unfocused windows dim
          matches = [{is-focused = false;}];
          opacity = osConfig.clanarchy.desktop.niri.opacity.unfocused;
        }
        {
          # Heavy GUI apps, *while focused*: they render their own chrome and
          # are unreadable translucent. Each match carries is-focused=true, so
          # when one of these loses focus it falls through to the dim rule above
          # and to the is-focused=false blur rule — receding like everything
          # else instead of staying a bright opaque slab.
          #
          # The list is clanarchy.desktop.niri.opacity.opaqueApps. An app that
          # is missing from it looks transparent *and* unblurred while focused,
          # because blur is only applied to foot and to unfocused windows.
          matches =
            map (id: {
              app-id = id;
              is-focused = true;
            })
            (osConfig.clanarchy.desktop.niri.opacity.opaqueApps
              ++ osConfig.clanarchy.desktop.niri.opacity.extraOpaqueApps);
          opacity = 1.0;
        }

        # Floating terminal scratchpad (Mod+Shift+Return → foot -T scratch)
        {
          matches = [
            {
              app-id = "^foot$";
              title = "^scratch$";
            }
          ];
          open-floating = true;
          default-column-width = {fixed = 1000;};
          default-window-height = {fixed = 650;};
        }

        # KeePassXC — floating scratchpad at a comfortable size
        {
          matches = [{app-id = "^org\\.keepassxc\\.KeePassXC$";}];
          open-floating = true;
          default-column-width = {fixed = 900;};
          default-window-height = {fixed = 650;};
        }

        # Nextcloud Window disappearing workaround
        {
          matches = [{app-id = "^nextcloud$";} {app-id = "^org\\.nextcloud\\.NEXTCLOUD$";}];
          open-floating = true;
        }

        # Chromium — open maximized. "chromium-browser" is the app-id
        # ungoogled-chromium actually reports on Wayland; the two patterns
        # below it never matched anything, which is why this rule appeared to
        # do nothing.
        {
          matches = [
            {app-id = "^chromium-browser$";}
            {app-id = "^chromium$";}
            {app-id = "^org\\.chromium\\.Chromium$";}
          ];
          open-maximized = true;
        }

        # Lazygit floating terminal (foot -T lazygit -e lazygit)
        {
          matches = [
            {
              app-id = "^foot$";
              title = "^lazygit$";
            }
          ];
          open-floating = true;
          default-column-width = {fixed = 1200;};
          default-window-height = {fixed = 800;};
        }
      ]
      # Per-focus shadow. niri's layout-level `shadow` varies only by colour
      # between focused and unfocused, so a differently *shaped* shadow on
      # unfocused windows has to be a window-rule. Each field falls back to the
      # focused value, so only what actually differs needs stating.
      ++ lib.optional osConfig.clanarchy.desktop.niri.shadow.unfocused.enable (let
        s = osConfig.clanarchy.desktop.niri.shadow;
        u = s.unfocused;
        or' = a: b:
          if a != null
          then a
          else b;
      in {
        matches = [{is-focused = false;}];
        shadow = {
          enable = true;
          softness = or' u.softness s.softness;
          spread = or' u.spread s.spread;
          offset = {
            x = or' u.offset.x s.offset.x;
            y = or' u.offset.y s.offset.y;
          };
          draw-behind-window = s.drawBehindWindow;
          color = or' u.color s.color;
        };
      });

      # All app launches prefixed with "uwsm app --" so they run as systemd units
      binds = {
        # --- Focus navigation ---
        # h/l = columns (horizontal axis), j/k = workspaces (vertical axis)
        "Mod+H".action.focus-column-left = {};
        "Mod+L".action.focus-column-right = {};
        "Mod+J".action.focus-workspace-down = {};
        "Mod+K".action.focus-workspace-up = {};

        # --- Move windows/columns ---
        "Mod+Shift+H".action.move-column-left = {};
        "Mod+Shift+L".action.move-column-right = {};
        "Mod+Shift+J".action.move-window-to-workspace-down = {};
        "Mod+Shift+K".action.move-window-to-workspace-up = {};

        # --- Monitor navigation ---
        "Mod+Ctrl+H".action.focus-monitor-left = {};
        "Mod+Ctrl+L".action.focus-monitor-right = {};
        "Mod+Ctrl+K".action.focus-monitor-up = {};
        "Mod+Ctrl+J".action.focus-monitor-down = {};
        "Mod+Shift+Ctrl+H".action.move-column-to-monitor-left = {};
        "Mod+Shift+Ctrl+L".action.move-column-to-monitor-right = {};
        "Mod+Shift+Ctrl+K".action.move-column-to-monitor-up = {};
        "Mod+Shift+Ctrl+J".action.move-column-to-monitor-down = {};
        # Cycle Kamvas Pro 24 clockwise: Normal→90°CW→180°→270°CW→Normal
        # Looks up by model name so it works regardless of which DP port the tablet lands on.
        # (niri transforms are CCW, so CW cycle = Normal→270→180→90→Normal)
        "Mod+Ctrl+R".action.spawn = ["sh" "-c" "O=$(niri msg -j outputs | jq -r 'to_entries[]|select(.value.model==\"Kamvas Pro 24\")|.key'); [ -z \"$O\" ] && exit 0; T=$(niri msg -j outputs | jq -r --arg o \"$O\" '.[$o].logical.transform'); case $T in Normal) niri msg output \"$O\" transform 270;; 270) niri msg output \"$O\" transform 180;; 180) niri msg output \"$O\" transform 90;; *) niri msg output \"$O\" transform normal;; esac"];

        # --- Launch ---
        "Mod+Return".action.spawn = ["uwsm" "app" "--" "foot"];
        # foot -T scratch → matched by window rule → opens floating
        "Mod+Shift+Return".action.spawn = ["uwsm" "app" "--" "foot" "-T" "scratch"];
        "Mod+Space".action.spawn = ["noctalia-shell" "ipc" "call" "launcher" "toggle"];
        "Mod+c".action.spawn = ["noctalia-shell" "ipc" "call" "plugin:clipper" "toggle"];
        "Mod+E".action.spawn = [
          "uwsm"
          "app"
          "--"
          "foot"
          "-e"
          (
            if (osConfig.clanarchy.users.lgo.editor or "govim") == "govim"
            then "nvim"
            else "hx"
          )
          "."
        ];
        "Mod+F".action.spawn = ["uwsm" "app" "--" "foot" "-e" "yazi"];

        # KeePassXC toggle — show from tray or minimize back to tray.
        # KeePassXC must have "minimize to tray on close" enabled in its settings.
        "Mod+P".action.spawn = ["sh" "-c" "if niri msg --json focused-window 2>/dev/null | grep -q KeePassXC; then niri msg action close-window; else keepassxc; fi"];

        # --- Window management ---
        "Mod+Q".action.close-window = {};
        "Mod+V".action.toggle-window-floating = {};
        "Mod+M".action.maximize-column = {};
        "Mod+F11".action.fullscreen-window = {};
        "Mod+Tab".action.focus-window-previous = {};

        # --- Layout control ---
        "Mod+R".action.switch-preset-column-width = {};
        "Mod+Shift+C".action.center-column = {};
        "Mod+BracketLeft".action.consume-or-expel-window-left = {};
        "Mod+BracketRight".action.consume-or-expel-window-right = {};
        "Mod+Minus".action.set-column-width = "-10%";
        "Mod+Equal".action.set-column-width = "+10%";
        "Mod+Shift+Minus".action.set-window-height = "-10%";
        "Mod+Shift+Equal".action.set-window-height = "+10%";

        # --- Session ---
        "Mod+Shift+E".action.quit = {};
        # Reload config via spawn (load-config-file is CLI-only, not a keybind action)
        "Mod+Shift+R".action.spawn = ["niri" "msg" "action" "load-config-file"];

        # --- Screenshots (Noctalia plugin:screenshot) ---
        "Print".action.spawn = ["noctalia-shell" "ipc" "call" "plugin:screenshot" "takeScreenshot" "region"];
        "Mod+Print".action.spawn = ["noctalia-shell" "ipc" "call" "plugin:screenshot" "takeScreenshot" "screen"];

        # --- Media / Brightness (Noctalia IPC for OSD) ---
        "XF86AudioRaiseVolume".action.spawn = ["noctalia-shell" "ipc" "call" "volume" "increase"];
        "XF86AudioLowerVolume".action.spawn = ["noctalia-shell" "ipc" "call" "volume" "decrease"];
        "XF86AudioMute".action.spawn = ["noctalia-shell" "ipc" "call" "volume" "muteOutput"];
        "XF86AudioPlay".action.spawn = ["noctalia-shell" "ipc" "call" "media" "playPause"];
        "XF86AudioNext".action.spawn = ["noctalia-shell" "ipc" "call" "media" "next"];
        "XF86AudioPrev".action.spawn = ["noctalia-shell" "ipc" "call" "media" "previous"];
        "XF86MonBrightnessUp".action.spawn = ["noctalia-shell" "ipc" "call" "brightness" "increase"];
        "XF86MonBrightnessDown".action.spawn = ["noctalia-shell" "ipc" "call" "brightness" "decrease"];

        # --- Workspaces 1-9 ---
        "Mod+1".action.focus-workspace = 1;
        "Mod+2".action.focus-workspace = 2;
        "Mod+3".action.focus-workspace = 3;
        "Mod+4".action.focus-workspace = 4;
        "Mod+5".action.focus-workspace = 5;
        "Mod+6".action.focus-workspace = 6;
        "Mod+7".action.focus-workspace = 7;
        "Mod+8".action.focus-workspace = 8;
        "Mod+9".action.focus-workspace = 9;
        "Mod+Shift+1".action.move-window-to-workspace = 1;
        "Mod+Shift+2".action.move-window-to-workspace = 2;
        "Mod+Shift+3".action.move-window-to-workspace = 3;
        "Mod+Shift+4".action.move-window-to-workspace = 4;
        "Mod+Shift+5".action.move-window-to-workspace = 5;
        "Mod+Shift+6".action.move-window-to-workspace = 6;
        "Mod+Shift+7".action.move-window-to-workspace = 7;
        "Mod+Shift+8".action.move-window-to-workspace = 8;
        "Mod+Shift+9".action.move-window-to-workspace = 9;
      }
      # --- Convertible / 2-in-1 only ---
      # Folding the panel back puts the physical keyboard face-down, so there
      # has to be a way to summon an on-screen one without it.  Guarded on the
      # hardware option (modules/hardware/convertible.nix), which is off on
      # every clamshell — the bind is simply absent there rather than pointing
      # at a package that isn't installed.
      // lib.optionalAttrs osConfig.clanarchy.hardware.convertible.enable {
        # Toggle: wvkbd has no toggle of its own, so kill it if it's up.
        "Mod+O".action.spawn = [
          "sh"
          "-c"
          "pkill -x wvkbd-mobintl || uwsm app -- wvkbd-mobintl -L 250"
        ];
      };

      # Lid switch events — only spawn actions are supported.
      # lid-close: turn off all outputs except the internal display so they don't
      # receive signal during sleep and resume cleanly.
      # lid-open: restore them on resume.
      switch-events = {
        lid-close.action.spawn = [
          "sh"
          "-c"
          "niri msg -j outputs | ${pkgs.jq}/bin/jq -r 'keys[] | select(. != \"eDP-1\")' | xargs -r -I{} niri msg output {} off"
        ];
        lid-open.action.spawn = [
          "sh"
          "-c"
          "niri msg -j outputs | ${pkgs.jq}/bin/jq -r 'keys[] | select(. != \"eDP-1\")' | xargs -r -I{} niri msg output {} on"
        ];
      };
    };
  };

  # Raw KDL injection. niri-flake's Nix schema has no `blur { }`,
  # `background-effect { }` or `xwayland-satellite { }` nodes at the current
  # pin, so we take the string niri-flake generated
  # (`programs.niri.finalConfig`), append raw KDL, and re-run `niri validate`
  # before installing.
  xdg.configFile.niri-config.source = lib.mkIf (
    osConfig.clanarchy.desktop.niri.blur.enable
    || osConfig.clanarchy.desktop.niri.xwayland.enable
  ) (lib.mkForce (
    pkgs.runCommand "config.kdl" {
      passAsFile = ["config"];
      config =
        config.programs.niri.finalConfig
        + lib.optionalString osConfig.clanarchy.desktop.niri.xwayland.enable ''

        // ---- injected by modules/desktop/niri-hm.nix (xwayland.enable) ----

        // X11 support. niri opens the X11 sockets itself and spawns
        // xwayland-satellite lazily on the first X client connection, so
        // DISPLAY is allocated from session start and costs nothing until
        // something actually uses it. Pinned to the store path rather than
        // relying on a PATH lookup, so the binary is a closure dependency of
        // this config file.
        //
        // niri only exports DISPLAY to processes it spawns itself. That covers
        // the keybinds here — `uwsm app` launches apps as a scope, ie. as a
        // fork of the caller, so foot and everything started from it inherit
        // it. Anything launched from a systemd user unit instead (environment
        // from the user manager, not from niri) will not see DISPLAY.
        xwayland-satellite {
            path "${pkgs.xwayland-satellite}/bin/xwayland-satellite"
        }
      ''
        + lib.optionalString osConfig.clanarchy.desktop.niri.blur.enable ''

        // ---- injected by modules/desktop/niri-hm.nix (blur.enable) ----

        // Global blur parameters, from clanarchy.desktop.niri.blur.* — see
        // modules/desktop/niri.nix for what each one costs. Nix renders floats
        // with six decimals ("3.000000"), which KDL takes as a float literal;
        // a bare "3" would not parse where niri wants one.
        blur {
            passes ${toString osConfig.clanarchy.desktop.niri.blur.passes}
            offset ${toString osConfig.clanarchy.desktop.niri.blur.offset}
            noise ${toString osConfig.clanarchy.desktop.niri.blur.noise}
            saturation ${toString osConfig.clanarchy.desktop.niri.blur.saturation}
        }

        // Foot terminal: blur its wallpaper even when focused (opacity 0.95).
        window-rule {
            match app-id="^foot$"
            background-effect {
                blur true
            }
        }

        // Any unfocused window (opacity 0.65 baseline) gets a blurred backdrop.
        // Fully-opaque apps (Chromium/GIMP/LibreOffice — see window-rules above)
        // still render blur but it's invisible through their opaque surface;
        // xray mode makes this cheap so we don't try to exclude them.
        window-rule {
            match is-focused=false
            background-effect {
                blur true
            }
        }

        // Noctalia UI layer surfaces. Only the visible ones — background,
        // wallpaper, overview, fade-overlay, exclusion, and trigger zones
        // deliberately do NOT get a rule (they are either invisible or ARE
        // the backdrop).
        //
        // noctalia-notifications-* and noctalia-toast-* are excluded on
        // purpose. niri applies a background-effect to the whole layer
        // surface rectangle, not to what the surface paints. Those two are
        // the only Noctalia surfaces that are much larger than their visible
        // content: Notification.qml/Toast.qml size the window to
        // notifWidth + shadowPadding*2 by the height of the entire stack,
        // then draw rounded, gapped cards inside it. Blurring that gives a
        // hard-edged square block behind (and below, and between) the cards.
        // Bar/dock/launcher/OSD wrap their content tightly, so the square
        // blur region coincides with what they paint and is invisible.
        layer-rule {
            match namespace="^noctalia-bar-content-"
            match namespace="^noctalia-dock-"
            match namespace="^noctalia-launcher-"
            match namespace="^noctalia-osd-"
            background-effect {
                blur true
            }
        }
      '';
    } ''
      ${pkgs.niri}/bin/niri validate -c $configPath
      cp $configPath $out
    ''
  ));
}
