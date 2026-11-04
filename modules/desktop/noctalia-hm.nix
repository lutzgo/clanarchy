# Shared Home Manager module for Noctalia-based Wayland desktops.
# Imported by niri-hm.nix and labwc-hm.nix; compositor-specific conditionals
# use isNiri / isLabwc derived from osConfig.
{
  pkgs,
  config,
  lib,
  osConfig,
  inputs,
  ...
}: let
  # Safe checks: niri/labwc options only exist when the respective compositor module is imported.
  isNiri = (osConfig.clanarchy.desktop ? niri) && osConfig.clanarchy.desktop.niri.enable;
  isLabwc = (osConfig.clanarchy.desktop ? labwc) && osConfig.clanarchy.desktop.labwc.enable;
  # Per-USER gate, deliberately not folded into isNiri. The two happen to
  # select the same machine today (lgo is the only niri user), and that is
  # exactly why they must stay separate: a plugin scoped to a person is not a
  # plugin scoped to a compositor, and conflating them breaks silently the
  # first time lgo runs labwc or a second person runs niri.
  isLgo = config.home.username == "lgo";

  # Who gets lgo's desktop — his bar, plugins and launcher setup. lgo, and the
  # two couch accounts whose screens he set up the same way: deck (birte's
  # Desktop Mode) and go (ernst's TV desktop). What stays lgo's ALONE is his
  # (`isLgo`): the CalDAV account, which logs in as him. Couch-only changes
  # on top of this (dock, autostart) are modules/desktop/couch-hm.nix.
  lgoLayout = builtins.elem config.home.username ["lgo" "deck" "go"];

  # The local-ai `opencode` role's generated config, when this user has one.
  # It embeds a store path (the instructions file), so drop the string
  # context before parsing — only plain values are read from it.
  opencodeCfg =
    if config.xdg.configFile ? "opencode/config.json"
    then builtins.fromJSON (builtins.unsafeDiscardStringContext config.xdg.configFile."opencode/config.json".text)
    else null;
  opencodeProvider =
    if opencodeCfg != null
    then builtins.head (lib.splitString "/" opencodeCfg.model)
    else null;

  # Where Mimir (plain OpenAI-compatible chat) talks to, or null for no Mimir.
  #   - a user with the `opencode` role (lgo): that role's provider — the SSH
  #     tunnel to ernst's llama.cpp — and its model, read back from config.json;
  #   - a user ON the machine running llama-swap (go on ernst): straight to
  #     llama-swap's loopback port. The model is the fleet's default
  #     (clan.nix, roles.opencode defaultModel "ernst/qwen3.6-35b-a3b").
  #   - anyone else (deck on birte): no Mimir. birte could only reach ernst
  #     through the opencode role's tunnel, which brings its own key — a
  #     `clan vars generate` — and the OpenCode CLI with it.
  # OpenCode itself only where its role is: the companion runs `opencode
  # serve`, which needs the CLI and the role's config.json.
  #
  # WHICH widgets exist is decided from the username and the NixOS config,
  # never from `opencodeCfg`: that reads xdg.configFile's names, and Noctalia's
  # own config.toml is one of them — so a plugin list that depended on it is
  # an infinite recursion. The role is on lgo (miralda, jens); only the VALUES
  # below read its config.json, lazily.
  hasOpencode = isLgo;
  hasMimir = isLgo || osConfig.services.llama-swap.enable;
  mimir =
    if opencodeCfg != null
    then {
      endpoint = opencodeCfg.provider.${opencodeProvider}.options.baseURL;
      model = lib.removePrefix "${opencodeProvider}/" opencodeCfg.model;
    }
    else {
      endpoint = "http://127.0.0.1:${toString osConfig.services.llama-swap.port}/v1";
      model = "qwen3.6-35b-a3b";
    };
  # Bar instances in the AI capsule (g3), OpenCode then Mimir.
  aiWidgets = lib.optional hasOpencode "opencode" ++ lib.optional hasMimir "mimir";
in {
  imports = [
    inputs.noctalia.homeModules.default # provides programs.noctalia
    ./foot-hm.nix # shared foot terminal config
  ];

  # Noctalia shell — configured declaratively via the noctalia HM module.
  # Launched via compositor autostart with UWSM so it runs as a tracked
  # systemd unit.
  #
  # ── v5: THIS BLOCK IS DELIBERATELY SHORT ───────────────────────────────
  #
  # The pre-v5 version of this file set ~910 lines of settings through typed
  # options, most of which restated upstream defaults.  v5 takes freeform
  # TOML (`pkgs.formats.toml`) and validates it at BUILD time by running
  # `noctalia config validate` on the generated file, so the safe shape is
  # the opposite: write only what differs from the defaults and let the
  # validator catch the rest.  `noctalia config export full` prints the
  # complete default schema if you need to see what you are overriding.
  #
  # Keys are snake_case now and several sections were renamed:
  #   general -> shell          notifications -> notification
  #   ui      -> shell/theme    nightLight    -> nightlight
  #   controlCenter -> control_center         systemMonitor -> system.monitor
  #   location.name -> location.address
  # Bar widgets are no longer inline objects: `bar.<profile>.{start,center,
  # end}` are lists of widget NAMES, and per-widget options live in their own
  # `widget.<name>` table.
  #
  # ── STYLIX OWNS SIX OF THESE VALUES ────────────────────────────────────
  #
  # stylix's noctalia target writes `theme.*`, `shell.font_family`,
  # `wallpaper.default.path` and the three `background_opacity` keys on dock,
  # notification and osd.  Freeform TOML still merges like any attrset, so
  # `lib.mkForce` is how we win where we deliberately disagree — which is
  # only the opacities.  Do NOT set `theme.*` or `shell.font_family` here;
  # stylix is the source of truth for both and a plain definition would
  # collide rather than override.
  programs.noctalia = {
    enable = true;
    settings =
      lib.recursiveUpdate {
        shell = {
          avatar_path = "${config.home.homeDirectory}/.face";
          settings_show_advanced = true;
        };

        bar = {
          order = ["default"];
          default = {
            enabled = true;
            position = "top";
            # The panel, not every monitor: this is a laptop and the bar
            # belongs on its built-in screen.
            capsule = true;
            capsule_opacity = lib.mkForce 1.0;
            background_opacity = lib.mkForce 1.0;
            font_scale = 1.0;
            widget_spacing = 6;
            margin_edge = 4;
            margin_ends = 4;
            show_on_workspace_switch = true;

            # Widget NAMES, in order; per-widget options live in their own
            # `widget.<name>` tables.
            #
            # Sabine's layout: clock and battery centre, status on the right,
            # nothing on the left. See docs/guides/noctalia-profiles.md.
            #
            # lgo's three lists are NOT here: his block below sets all three
            # and wins in the recursiveUpdate.  They used to be repeated here
            # behind `isLgo` — an older layout that never reached the output.
            start = [];
            center = ["clock" "battery"];
            end = ["tray" "notifications" "control-center"];
          };
        };

        dock = {
          # Sabine gets the dock; lgo drives everything from the bar and the
          # launcher, and a second always-present strip is just lost rows.
          enabled = !isLgo;
          position = "bottom";
          auto_hide = true;
          background_opacity = lib.mkForce 0.9;
          active_monitor_only = true;
        };

        notification = {
          position = "top_right";
          background_opacity = lib.mkForce 0.8;
        };

        osd = {
          position = "top_right";
          hide_delay_ms = 2000;
          background_opacity = lib.mkForce 0.9;
        };

        wallpaper = {
          enabled = true;
          directory = "${config.home.homeDirectory}/Pictures/Wallpapers";
        };

        location.address = "Duesseldorf";
        weather.enabled = true;
      } (
        lib.optionalAttrs lgoLayout {
          # ── lgo's layout, captured from the running shell ────────────────────
          #
          # Taken from ~/.local/state/noctalia/settings.toml on jens (saved there
          # as the "lgoPower" config-swap profile), 2026-11-02. That is where v5
          # writes runtime changes; config.toml — this file's output — is the
          # declarative base it layers on top of. So these two coexist: tweak in
          # the UI and the state file wins until you fold the change back here.
          #
          # Runtime-only keys were deliberately NOT captured: `config_version`,
          # `wallpaper.last`, and the lockscreen widget geometry (pixel
          # positions per output). They describe where things currently are, not
          # what was chosen.
          # The bar as you arranged it, recaptured 2026-11-02 after the btrfs
          # reinstall. Widget names ending in a number are instances declared
          # in `widget.*` below; `group:<id>` refers to a capsule_group.
          #
          # CAPSULE GROUPS are the new shape: rather than listing every widget
          # inline, related ones are bundled into a bordered capsule and the
          # bar references the group. Members are widget instance names, so
          # a group is a layout container, not a widget in its own right.
          bar.default = {
            background_opacity = lib.mkForce 0.49;
            contact_shadow = true;
            font_family = "MonaspiceNe Nerd Font Propo";
            margin_edge = 5;
            margin_ends = 9;
            # As arranged on jens, 2026-11-03 15:00, with the session button on
            # the left only.
            start = ["session" "workspaces" "group:g2" "spacer" "active_window"];
            center = ["launcher" "clock" "keybinds"];
            end = ["group:g1" "tray" "battery"] ++ lib.optional (aiWidgets != []) "group:g3";

            # TOML `[[bar.default.capsule_group]]` — an ARRAY of tables, so a
            # Nix list of attrsets. Order in the list is order on the bar.
            capsule_group =
              [
                {
                  id = "g1";
                  # udiskie, OBS, the Vial keymap, config-swap.
                  members = ["status_4" "status_3" "vial" "widget_2"];
                  enabled = true;
                  accordion = false;
                  accordion_direction = "end";
                  border_width = 1.0;
                  fill = "surface_container";
                  opacity = 1.0;
                  padding = 6.0;
                }
                {
                  id = "g2";
                  members = ["widget_4" "widget_5"];
                  enabled = true;
                  accordion = false;
                  accordion_direction = "end";
                  border_width = 1.0;
                  fill = "surface_container";
                  opacity = 1.0;
                  padding = 6.0;
                }
              ]
              # The AI plugins, OpenCode then Mimir — each only where it has
              # something to talk to (see `mimir` above). jens's UI named these
              # instances `widget` and `status`; they are `opencode` and
              # `mimir` here (widget.* below) — same widgets, readable names.
              ++ lib.optional (aiWidgets != []) {
                id = "g3";
                members = aiWidgets;
                enabled = true;
                accordion = false;
                accordion_direction = "end";
                border_width = 1.0;
                fill = "surface_container";
                opacity = 1.0;
                padding = 6.0;
              };
          };

          location.auto_locate = true;

          # Lockscreen widgets off. The saved profile also carries the login
          # box's pixel geometry (cx/cy/box_width/… for eDP-1 at 1536x960)
          # and its appearance settings, but the widget is DISABLED — that is
          # leftover placement for something not drawn. Captured as the choice
          # it is; re-save the profile if you turn them on and want the layout
          # kept here too.
          lockscreen_widgets.enabled = false;

          plugins.enabled =
            [
              "noctalia/kaomoji"
              "noctalia/screen_recorder"
              "tadomika_ari/config-swap"
              "kenn/keybind-cheatsheet"
              "ayagmar/obs-control"
              "egno/vial_keymap"
              "yocraft/qrcode"
              "abuamar142/qr-share"
              "alexander/screen-toolkit"
              "aristides/udiskie"
            ]
            ++ lib.optional hasOpencode "weinguyen/opencode-companion"
            ++ lib.optional hasMimir "alexander/mimir";

          # Per-plugin panel placement, as set in the UI.
          plugin_settings =
            {
              "abuamar142/qr-share".panel_placement = "attached";
              "ayagmar/obs-control".controls_placement = "attached";
              "kenn/keybind-cheatsheet".cheatsheet_placement = "attached";
              "tadomika_ari/config-swap".panel_placement = "attached";
              "yocraft/qrcode".panel_placement = "attached";

              # The Voyager's layout, as exported from Vial (File → Save current
              # layout) to this path. Until that file exists the overlay says
              # "File not found" with the path — nothing else breaks.
              #
              # alt_layout off: it draws a SECOND OS layout's letters on each
              # cap, found through `hyprctl`, and without Hyprland it falls back
              # to a built-in Russian table. lgo types one layout (us, Compose
              # on Right Alt), so there is nothing to draw there.
              "egno/vial_keymap" = {
                vil_path = "${config.home.homeDirectory}/Documents/voyager.vil";
                alt_layout_enabled = false;
              };
            }
            # The AI plugins, each only where it has something to talk to — see
            # `mimir`/`hasOpencode` at the top. opencode-companion, "auto": runs
            # its own `opencode serve` on loopback, which reads the role's
            # config.json — so the model and the tunnel endpoint stay chosen in
            # one place (clan.nix, roles.opencode.*).
            // lib.optionalAttrs hasOpencode {
              "weinguyen/opencode-companion" =
                {
                  server_mode = "auto";
                  auto_start = true;
                  default_workspace = "${config.home.homeDirectory}/Projects";
                }
                // lib.optionalAttrs (opencodeCfg != null) {
                  default_model = opencodeCfg.model;
                };
            }
            # mimir: plain OpenAI-compatible chat, at the endpoint chosen in
            # `mimir` above, model id without any `<provider>/` prefix, and no
            # API key — llama.cpp needs none, and mimir sends no Authorization
            # header when the key is empty.
            // lib.optionalAttrs hasMimir {
              "alexander/mimir" = {
                api_endpoint = mimir.endpoint;
                default_model = mimir.model;
              };
            };

          # Widget instances. A plugin widget is named `<plugin-id>:<widget>`,
          # and the table name is what the bar or a capsule_group references —
          # so `widget_4` in group g2 resolves to the qrcode plugin here.
          #
          # Only the ones the current layout actually uses. The previous
          # capture also carried date, launcher, file-search, keybinds_2, ocr
          # and an emoji-picker instance; those widgets are no longer on the
          # bar, and three of their plugins are no longer enabled.
          widget =
            {
              launcher.glyph = "rocket";
              clock = {
                anchor = true;
                format = "{:%A} {:%Y-%m-%d} {:%H:%M}";
                actions.left = "panel-toggle control-center home";
              };
              keybinds.type = "kenn/keybind-cheatsheet:keybinds";
              status_3.type = "ayagmar/obs-control:status";
              vial.type = "egno/vial_keymap:icon";
              status_4.type = "aristides/udiskie:status";
              widget_2.type = "tadomika_ari/config-swap:widget";
              widget_4.type = "yocraft/qrcode:widget";
              widget_5.type = "alexander/screen-toolkit:widget";
            }
            // lib.optionalAttrs hasOpencode {opencode.type = "weinguyen/opencode-companion:widget";}
            // lib.optionalAttrs hasMimir {mimir.type = "alexander/mimir:status";};

          calendar = lib.mkIf isLgo {
            enabled = true;
            dedupe_events = true;
            # CalDAV against the household Nextcloud. No password here — Noctalia
            # prompts and stores it in its own secret store; a clan var would have
            # to be readable by the shell at runtime, which is a worse trade.
            account.lgo = {
              name = "lgo";
              provider = "custom";
              type = "caldav";
              server_url = "https://cloud.goclan.org/remote.php/dav";
              username = "lgo";
            };
          };

          control_center = {
            calendar = {
              show_events_location = true;
              show_week_numbers = true;
            };
            shortcuts = [
              {type = "wifi";}
              {type = "bluetooth";}
              {type = "notification";}
              {type = "power_profile";}
            ];
          };

          shell = {
            app_icon_colorize = true;
            password_style = "random";
            settings_window_translucent = true;
            launcher = {
              compact = true;
              search_position = "top";
              show_app_actions = true;
              providers = {
                calculator.prefix = "calc";
                emoji = {
                  global = true;
                  prefix = "emo";
                };
                panels = {
                  global = false;
                  prefix = "pan";
                };
                session = {
                  global = true;
                  prefix = "session";
                };
                windows = {
                  global = true;
                  prefix = "win";
                };
              };
            };
            panel = {
              clipboard_placement = "attached";
              launcher_placement = "attached";
              transparency_mode = "glass";
            };
            window_switcher.style = "compact";
          };

          desktop_widgets.enabled = false;
          idle.pre_action_fade_seconds = 30;
          osd.kinds = {
            caffeine = false;
            nightlight = false;
          };
        }
      );
  };

  stylix.targets.noctalia.enable = true;
  stylix.targets.kde.enable = false;

  # Override Noctalia's accent colours for the active Stylix palette
  # (niri/miralda only).
  #
  # Stylix's own target writes `customPalettes.stylix.dark` using exactly
  # these key names and sets `settings.theme.custom_palette = "stylix"`, so
  # the override is now a per-key mkForce on that attrset rather than a
  # separate option. Keep the name "stylix" in step with the target — it is
  # hardcoded there (modules/noctalia/hm.nix: `theme = "stylix"`).
  #
  # What differs from Stylix's defaults, and why: Stylix maps mPrimary to
  # base0D (blue) and mHover to base0C. This fleet's accent is base09.
  programs.noctalia.customPalettes.stylix.dark = lib.mkIf isNiri (
    let
      c = config.lib.stylix.colors;
    in {
      mPrimary = lib.mkForce "#${c.base09}";
      mOnPrimary = lib.mkForce "#${c.base00}";
      mSecondary = lib.mkForce "#${c.base0C}";
      mOnSecondary = lib.mkForce "#${c.base00}";
      mTertiary = lib.mkForce "#${c.base0B}";
      mOnTertiary = lib.mkForce "#${c.base00}";
      mHover = lib.mkForce "#${c.base09}";
      mOnHover = lib.mkForce "#${c.base00}";
    }
  );

  # force = true: noctalia rewrites its own config at runtime when you change
  # something in the settings UI, replacing HM's symlink with a regular file.
  # On the next rebuild HM would refuse with "would be clobbered". force lets
  # HM put the managed symlink back; deSymlinkNoctalia then converts it to a
  # regular file again so the UI stays writable.
  #
  # One file: colours live in palettes/<name>.json (written by the stylix
  # target), everything else is config.toml.
  xdg.configFile."noctalia/config.toml".force = true;

  # Plugins are `settings.plugins.enabled` (lgo's twelve, above). Noctalia
  # fetches them itself into ~/.local/state/noctalia/plugins — see the
  # `noctalia-plugin-sources` unit below for the one way that goes wrong.
  # Screenshot and clipboard are built in, not plugins
  # (`noctalia msg screenshot-*`, `shell.clipboard_*`).

  # lgo's bar (and deck's and go's) comes ONLY from the settings above. Noctalia layers its runtime
  # state file over config.toml, so a bar arranged in the UI would otherwise
  # keep winning until someone deletes it by hand — which is how jens and
  # miralda came to show different bars. Every switch drops the `bar`,
  # `widget` and `dock` tables from that state file; everything else in it
  # (lockscreen, plugin state, …) is left alone. Takes effect when Noctalia
  # next starts. `dock` since the couch accounts' dock is declared too
  # (couch-hm.nix) — deck's UI-set opacity would otherwise keep winning.
  home.activation.noctaliaBarFromConfig = lib.mkIf lgoLayout (lib.hm.dag.entryAfter ["writeBoundary"] (let
    py = pkgs.python3.withPackages (ps: [ps.tomli-w]);
    strip = pkgs.writeText "noctalia-strip-bar.py" ''
      import os, sys, tomllib, tomli_w
      path = sys.argv[1]
      with open(path, "rb") as f:
          state = tomllib.load(f)
      dropped = [k for k in ("bar", "widget", "dock") if state.pop(k, None) is not None]
      if dropped:
          tmp = path + ".tmp"
          with open(tmp, "wb") as f:
              tomli_w.dump(state, f)
          os.chmod(tmp, os.stat(path).st_mode)
          os.replace(tmp, path)
          print("noctalia: removed UI overrides for " + ", ".join(dropped))
    '';
  in ''
    _state="$HOME/.local/state/noctalia/settings.toml"
    if [ -f "$_state" ]; then
      run ${py}/bin/python3 ${strip} "$_state"
    fi
  ''));

  # Convert HM's managed symlink back into a regular file, so noctalia can
  # write to it when you change something in the settings UI. The pair with
  # `force = true` above: HM relinks on every rebuild, this undoes it once.
  home.activation.deSymlinkNoctalia = lib.hm.dag.entryAfter ["linkGeneration"] ''
    _delink() {
      if [ -L "$1" ]; then
        _target=$(readlink -f "$1")
        $DRY_RUN_CMD rm -f "$1"
        $DRY_RUN_CMD cp -f "$_target" "$1"
        $DRY_RUN_CMD chmod 644 "$1"
      fi
    }
    _delink "$HOME/.config/noctalia/config.toml"
  '';

  # ── PLUGIN SOURCES: CLONED ONCE THE NETWORK IS UP ─────────────────────────
  #
  #   `plugins.enabled` names the plugins; Noctalia fetches them at runtime by
  #   git-cloning its two default sources into ~/.local/state, and it tries
  #   that exactly ONCE, at startup.  On miralda (2026-11-03) it started at
  #   login before Wi-Fi was up:
  #
  #     [plugins] plugin source 'official': cannot prepare source cache …
  #     fatal: unable to access 'https://github.com/…': Could not resolve host
  #
  #   and never retried — so the same config.toml drew jens's bar on jens and
  #   a bar with every plugin widget missing (OBS, OpenCode, Mimir, recorder…)
  #   on miralda.  Neither `plugins update` (fetches into an EXISTING clone)
  #   nor `config-reload` re-attempts the clone.
  #
  #   What does work, measured on miralda: clone with Noctalia's own command
  #   (from its log), then `noctalia msg plugins update <source>` — the
  #   running shell materialises every enabled plugin live, no restart.  This
  #   unit does that, and only when a clone is missing; on a machine where
  #   Noctalia managed it itself the unit exits immediately.
  #
  #   The two sources are Noctalia's DEFAULTS (`noctalia config export full`,
  #   [[plugins.source]]), restated because they are not in our config.  If
  #   upstream renames them, `noctalia msg plugins source list` shows the
  #   new names.  `WAYLAND_DISPLAY` is what `noctalia msg` needs to find the
  #   shell; the user manager has it once the niri session is up, which is
  #   why this hangs off graphical-session.target.
  systemd.user.services.noctalia-plugin-sources = lib.mkIf lgoLayout {
    Unit = {
      Description = "Clone Noctalia's plugin sources if the startup clone failed";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Install.WantedBy = ["graphical-session.target"];
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "noctalia-plugin-sources" ''
        set -u
        base="$HOME/.local/state/noctalia/plugins/sources"
        missing=""
        for s in official community; do
          [ -d "$base/$s/repo/.git" ] || missing="$missing $s"
        done
        [ -n "$missing" ] || exit 0

        # Up to ten minutes for DNS, polling — a user unit cannot order
        # itself after the system's network-online.target.
        for _ in $(${pkgs.coreutils}/bin/seq 120); do
          ${pkgs.getent}/bin/getent hosts github.com >/dev/null && break
          ${pkgs.coreutils}/bin/sleep 5
        done

        for s in $missing; do
          ${pkgs.coreutils}/bin/rm -rf "$base/$s/repo"
          ${pkgs.coreutils}/bin/mkdir -p "$base/$s"
          ${pkgs.git}/bin/git clone -q --origin origin --filter=blob:none --no-checkout \
            "https://github.com/noctalia-dev/$s-plugins" "$base/$s/repo" \
            || { echo "noctalia-plugin-sources: clone of $s failed" >&2; exit 1; }
          echo "noctalia-plugin-sources: cloned $s"
        done

        # If the shell is not up yet it will find the clones itself when it
        # starts; if it is, this makes it materialise the plugins now.
        for s in $missing; do
          ${lib.getExe config.programs.noctalia.package} msg plugins update "$s" \
            || echo "noctalia-plugin-sources: shell not reachable; it will load $s on next start" >&2
        done
      ''}";
    };
  };

  gtk.gtk4.theme = lib.mkForce null; # newer stylix sets a non-null theme; mkForce keeps Noctalia's no-GTK4-theme intent

  gtk.iconTheme = {
    name = osConfig.clanarchy.iconTheme.name;
    package = osConfig.clanarchy.iconTheme.package;
  };

  # Starship prompt — uses '' strings to preserve embedded Nerd Font codepoints.
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    enableNushellIntegration = true;
    settings = {
      format = ''
        $cmd_duration 󰜥 $directory ''${custom.jj}''${custom.git_branch}
        $character'';

      add_newline = false;

      character = {
        success_symbol = "[   ](bold blue)";
        error_symbol = "[   ](bold red)";
      };

      cmd_duration = {
        min_time = 0;
        format = "[](bold fg:yellow)[󰪢 $duration](bold bg:yellow fg:black)[](bold fg:yellow)";
      };

      directory = {
        truncation_length = 6;
        truncation_symbol = "••/";
        home_symbol = "  ";
        read_only = " 󰌾";
        style = "fg:black bg:green";
        format = "[](bold fg:green)[󰉋 $path]($style)[](bold fg:green)";
      };

      git_branch = {
        symbol = "󰘬";
        format = "󰜥 [](bold fg:cyan)[$symbol $branch(:$remote_branch)](fg:black bg:cyan)[ ](bold fg:cyan)";
        truncation_length = 12;
        truncation_symbol = "";
        style = "bg:cyan";
      };

      # jj (Jujutsu) in the prompt, and why git_branch alone no longer works.
      #
      # This repo is driven with jj colocated with git, and jj keeps git's HEAD
      # DETACHED — it points at the parent of the working-copy revision, not at
      # a branch. The builtin git_branch module therefore renders the literal
      # string "HEAD" in every clanarchy shell, which is accurate about git and
      # useless to the reader.
      #
      # So: show jj's own answer inside a jj repo, and fall back to the builtin
      # everywhere else. Both are driven by `when`, not `detect_folders`, so
      # they work in subdirectories too — `jj root` walks up, a folder test does
      # not.
      #
      # `--ignore-working-copy` is load-bearing on both jj calls. Without it jj
      # snapshots the working copy on every prompt render, which is slow and,
      # worse, means drawing a prompt MUTATES the repo.
      custom = {
        jj = {
          description = "jj bookmark, or change id, when inside a jj repo";
          when = "jj root --ignore-working-copy > /dev/null 2>&1";
          # starship pipes `command` to this shell on stdin — do NOT add -c.
          shell = ["bash" "--noprofile" "--norc"];
          command = ''
            jj log -r @ -n1 --ignore-working-copy --no-graph \
              -T 'coalesce(bookmarks.join(" "), separate("~", parents.map(|p| p.bookmarks().join(" ")).join(""), change_id.shortest(6)))'
          '';
          # Reads as the bookmark when @ carries one (`feat/foo`), and as
          # `<parent bookmark>~<change id>` when it does not (`main~sksuvx`) —
          # which is the common state right after `jj new main`.
          symbol = "󰘬";
          format = "󰜥 [](bold fg:cyan)[$symbol $output](fg:black bg:cyan)[ ](bold fg:cyan)";
          ignore_timeout = true;
        };

        # The builtin, re-rendered through `starship module` so it keeps its own
        # settings above (symbol, truncation, the powerline caps) — but only
        # where it tells the truth, i.e. outside a jj repo.
        git_branch = {
          description = "builtin git_branch, suppressed inside a jj repo";
          when = "! jj root --ignore-working-copy > /dev/null 2>&1";
          shell = ["bash" "--noprofile" "--norc"];
          command = "starship module git_branch";
          format = "$output";
          ignore_timeout = true;
        };
      };

      git_commit = {
        commit_hash_length = 4;
        tag_symbol = " ";
      };

      git_status = {
        conflicted = " 🏳 ";
        ahead = " 🏎💨 ";
        behind = " 😰 ";
        diverged = " 😵 ";
        untracked = " 🤷‍ ";
        stashed = " 📦 ";
        modified = " 📝 ";
        staged = "[++($count)](green)";
        renamed = " ✍️ ";
        deleted = " 🗑 ";
      };

      git_state = {
        format = "[\($state( $progress_current of $progress_total)\)]($style) ";
        cherry_pick = "[🍒 PICKING](bold red)";
      };

      hostname = {
        ssh_only = false;
        format = "[•$hostname](bg:cyan bold fg:black)[](bold fg:cyan)";
        trim_at = ".local";
        disabled = false;
      };

      username = {
        style_user = "bold bg:cyan fg:black";
        style_root = "red bold";
        format = "[](bold fg:cyan)[$user]($style)";
        disabled = false;
        show_always = true;
      };

      package.disabled = true;
      memory_usage = {
        disabled = true;
        threshold = -1;
      };
      time.disabled = true;
      line_break.disabled = false;

      nix_shell = {format = "via [❄️ $state( \\($name\\))](bold blue) ";};
      python = {format = "via [🐍 $version](bold green) ";};
      rust = {format = "via [⚡ $version](bold orange) ";};
      nodejs = {format = "via [⬢ $version](bold green) ";};
    };
  };

  # Point Noctalia's lockscreen at the dedicated PAM service (noctalia.nix).
  # Without this, Noctalia falls back to the "login" service (LockContext.qml default).
  systemd.user.sessionVariables.NOCTALIA_PAM_SERVICE = "noctalia";

  # Idle management: lock after 5 min idle, monitors off after 5.5 min, lock before sleep.
  # -w: swayidle holds the sleep inhibitor until the before-sleep command exits.
  # "sleep 1" gives Noctalia time to paint the lockscreen before the system suspends.
  # after-resume: re-lock to ensure lockscreen is visible when display comes back on.
  services.swayidle = {
    enable = true;
    extraArgs = ["-w"];
    events = {
      before-sleep = "${lib.getExe config.programs.noctalia.package} msg session lock; sleep 1";
      after-resume = "${lib.getExe config.programs.noctalia.package} msg session lock";
    };
    timeouts = [
      {
        timeout = 300;
        command = "loginctl lock-session";
      }
      ({
          timeout = 330;
          command =
            if isNiri
            then "niri msg action power-off-monitors"
            else "${pkgs.wlopm}/bin/wlopm --off '*'";
        }
        // lib.optionalAttrs isLabwc {
          resumeCommand = "${pkgs.wlopm}/bin/wlopm --on '*'";
        })
    ];
  };

  home.packages = with pkgs;
    [
      grim
      slurp
      wl-clipboard
      playerctl
      # Plugin runtime dependencies. None of these plugins declares its
      # binaries, so each absence shows up as a widget that loads and then
      # fails — which is exactly how they were found on jens.
      #
      #   gpu-screen-recorder  noctalia/screen_recorder
      #   udiskie              aristides/udiskie
      #   imagemagick          fel/ocr, yocraft/qrcode  (the `magick` binary)
      #   qrencode             yocraft/qrcode, abuamar142/qr-share
      #   tesseract            fel/ocr
      #
      # grim and slurp are already above — fel/ocr lists them in the same
      # error, but they were present all along.
      gpu-screen-recorder
      udiskie
      imagemagick
      qrencode
      tesseract
      # alexander/screen-toolkit: `hyprpicker` for the colour picker,
      # `zbarimg` for the QR reader. Both are looked up only when the feature
      # starts, so their absence looked like the tool simply not working.
      hyprpicker
      zbar
      # …and for its recordings: `ffmpeg`/`ffprobe` (GIF conversion,
      # thumbnails) and `pactl` (default audio source). pactl is linked out of
      # the pulseaudio package ALONE: the whole package would also put
      # pulseaudio.service/.socket into the user's unit path, and that socket
      # claims the one pipewire-pulse serves.
      ffmpeg
      (pkgs.runCommand "pactl-only" {} ''
        mkdir -p $out/bin
        ln -s ${lib.getExe' pkgs.pulseaudio "pactl"} $out/bin/pactl
      '')
      # ayagmar/obs-control drives obs-websocket through a Python helper and
      # checks for the `websocket-client` module by import, not by binary —
      # so a bare python3 is not enough.
      (python3.withPackages (ps: [ps.websocket-client]))
    ]
    ++ lib.optionals isNiri [ghostty]
    ++ lib.optionals isLabwc [wlopm]
    ++ (
      if isNiri
      then [pkgs.nextcloud-client]
      else lib.optional osConfig.clanarchy.desktop.labwc.nextcloud.enable pkgs.nextcloud-client
    );

  systemd.user.services.nextcloud-client = lib.mkIf (isNiri || osConfig.clanarchy.desktop.labwc.nextcloud.enable) {
    Unit = {
      Description = "Nextcloud Desktop Client";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${pkgs.nextcloud-client}/bin/nextcloud --background";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
