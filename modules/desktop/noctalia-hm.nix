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
in {
  imports = [
    inputs.noctalia.homeModules.default # provides programs.noctalia (v5; was programs.noctalia-shell)
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
    settings = {
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

          # Widget NAMES, in order.  v4 listed inline objects with their own
          # settings; v5 takes names here and per-widget options in their own
          # `widget.<name>` tables.
          #
          # Eleven `plugin:` entries are gone from both layouts — v5 replaced
          # the QML plugin API with Luau and only screen-recorder has a port.
          # Two were not really losses: screenshot and clipboard are built in
          # now (`noctalia msg screenshot-*`, `shell.clipboard_*`).
          #
          # Sabine's layout is the shape her "simple_mouse" profile had, kept
          # by hand because the shell-profiles plugin that used to apply it
          # does not exist for v5: clock and battery centre, status on the
          # right, nothing on the left. See docs/guides/noctalia-profiles.md.
          start =
            if isLgo
            then ["workspaces" "active_window" "spacer"]
            else [];
          center =
            if isLgo
            then ["launcher" "spacer" "clock" "spacer"]
            else ["clock" "battery"];
          end =
            if isLgo
            then ["tray" "battery" "session"]
            else ["tray" "notifications" "control-center"];
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

      # Plugins, declared rather than installed by hand in the UI.
      #
      # `enabled` takes catalogue IDs. The two default sources — noctalia's
      # `official` and `community` repos — are already on, so an ID from
      # either resolves without naming a source here.
      #
      # ONE entry, because v5's plugin API is Luau and the 25 QML plugins
      # left over from v4 under ~/.config/noctalia/plugins/ cannot load.
      # Those directories are inert, not active; deleting them is safe.
      # screen_recorder is the only one of them with a same-name port.
      #
      # It shells out to gpu-screen-recorder, which is NOT pulled in by the
      # plugin — added to home.packages below, or the widget appears and
      # every recording fails.
      plugins.enabled = ["noctalia/screen_recorder"];

      location.address = "Duesseldorf";
      weather.enabled = true;
    };
  };

  stylix.targets.noctalia.enable = true;
  stylix.targets.kde.enable = false;

  # Override Noctalia's accent colours for the active Stylix palette
  # (niri/miralda only).
  #
  # v5 moved these: there is no `programs.noctalia-shell.colors` any more.
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
  # v5 writes ONE file. The v4 set — colors.json, settings.json and a
  # settings.json per plugin — is gone: colours live in palettes/<name>.json
  # (written by the stylix target), everything else is config.toml, and the
  # plugins those entries named do not exist for v5.
  xdg.configFile."noctalia/config.toml".force = true;

  # NO plugin seeding any more.
  #
  # v4 declared eleven plugins in `noctalia/plugins.json` and seeded that file
  # with merge semantics so runtime download state survived a rebuild. v5
  # replaced the QML plugin API with Luau and ships a different catalogue, so
  # ten of those eleven have no port and the file they were listed in is not
  # read. Two of them stopped being plugins at all — screenshot and clipboard
  # are built into v5 (`noctalia msg screenshot-*`, `shell.clipboard_*`).
  #
  # Plugins are now declared in `settings.plugins` (sources + an `enabled`
  # list) if any are wanted again. See docs/guides/noctalia-profiles.md.

  # Convert HM's managed symlink back into a regular file, so noctalia can
  # write to it when you change something in the settings UI. The pair with
  # `force = true` above: HM relinks on every rebuild, this undoes it once.
  #
  # One file for v5, where v4 had seven.
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
      # Driven by the screen_recorder plugin, which declares no dependency
      # on it — without this the widget loads and every recording fails.
      gpu-screen-recorder
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
