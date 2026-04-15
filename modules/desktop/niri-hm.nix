# Shared Home Manager module for any graphical user — loaded by modules/desktop/niri.nix
# via home-manager.sharedModules.  `osConfig` exposes clanarchy.desktop.niri options.
{ pkgs, pkgs-unstable, inputs, config, lib, osConfig, ... }:
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
      outputs."eDP-1" = {
        scale = osConfig.clanarchy.desktop.niri.display.scale;
      };

      prefer-no-csd = true;

      spawn-at-startup = [
        { command = [ "keepassxc" "--minimized" ]; }
      ];

      layout.border = { enable = true; width = 1; };
      layout.focus-ring.width = 1;

      input = {
        touchpad = {
          tap = true;
          natural-scroll = true;
          dwt = true;  # disable-while-typing
        };
      };

      # Window rules: rounded corners, focus-aware opacity.
      # Rules are evaluated in order; the last matching rule for each property wins.
      # Baseline:  focused = 0.90, unfocused = 0.75
      # Exception: heavy GUI apps (Chromium, GIMP, LibreOffice) stay fully opaque.
      window-rules = [
        {
          # Global baseline: 8px rounded corners + focused opacity
          geometry-corner-radius = {
            top-left = 8.0;
            top-right = 8.0;
            bottom-right = 8.0;
            bottom-left = 8.0;
          };
          clip-to-geometry = true;
          opacity = osConfig.clanarchy.desktop.niri.opacity.focused;
        }
        {
          # Foot terminals: slightly more opaque than the global baseline
          matches = [{ app-id = "^foot$"; }];
          opacity = 0.95;
        }
        {
          # Unfocused windows dim
          matches = [{ is-focused = false; }];
          opacity = osConfig.clanarchy.desktop.niri.opacity.unfocused;
        }
        {
          # Heavy GUI apps: always fully opaque regardless of focus
          matches = [
            { app-id = "^org\\.chromium\\.Chromium$"; }
            { app-id = "^chromium$"; }
            { app-id = "^org\\.gimp\\.GIMP$"; }
            { app-id = "^gimp$"; }
            { app-id = "^libreoffice"; }
            { app-id = "^soffice$"; }
            { app-id = "^darktable$"; }
          ];
          opacity = 1.0;
        }

        # Floating terminal scratchpad (Mod+Shift+Return → foot -T scratch)
        {
          matches = [{ app-id = "^foot$"; title = "^scratch$"; }];
          open-floating = true;
          default-column-width = { fixed = 1000; };
          default-window-height = { fixed = 650; };
        }

        # KeePassXC — floating scratchpad at a comfortable size
        {
          matches = [{ app-id = "^org\\.keepassxc\\.KeePassXC$"; }];
          open-floating = true;
          default-column-width = { fixed = 900; };
          default-window-height = { fixed = 650; };
        }

        # GIMP — open floating (toolboxes are separate windows)
        {
          matches = [{ app-id = "^gimp$"; } { app-id = "^org\\.gimp\\.GIMP$"; }];
          open-floating = true;
        }

        # Chromium — open maximized
        {
          matches = [{ app-id = "^chromium$"; } { app-id = "^org\\.chromium\\.Chromium$"; }];
          open-maximized = true;
        }

        # Lazygit floating terminal (foot -T lazygit -e lazygit)
        {
          matches = [{ app-id = "^foot$"; title = "^lazygit$"; }];
          open-floating = true;
          default-column-width = { fixed = 1200; };
          default-window-height = { fixed = 800; };
        }
      ];

      # All app launches prefixed with "uwsm app --" so they run as systemd units
      binds = {
        # --- Focus navigation ---
        # h/l = columns (horizontal axis), j/k = workspaces (vertical axis)
        "Mod+H".action.focus-column-left     = {};
        "Mod+L".action.focus-column-right    = {};
        "Mod+J".action.focus-workspace-down  = {};
        "Mod+K".action.focus-workspace-up    = {};

        # --- Move windows/columns ---
        "Mod+Shift+H".action.move-column-left                  = {};
        "Mod+Shift+L".action.move-column-right                 = {};
        "Mod+Shift+J".action.move-window-to-workspace-down     = {};
        "Mod+Shift+K".action.move-window-to-workspace-up       = {};

        # --- Monitor navigation ---
        "Mod+Ctrl+H".action.focus-monitor-left  = {};
        "Mod+Ctrl+L".action.focus-monitor-right = {};
        "Mod+Ctrl+K".action.focus-monitor-up    = {};
        "Mod+Ctrl+J".action.focus-monitor-down  = {};
        "Mod+Shift+Ctrl+H".action.move-column-to-monitor-left  = {};
        "Mod+Shift+Ctrl+L".action.move-column-to-monitor-right = {};
        "Mod+Shift+Ctrl+K".action.move-column-to-monitor-up    = {};
        "Mod+Shift+Ctrl+J".action.move-column-to-monitor-down  = {};

        # --- Launch ---
        "Mod+Return".action.spawn = [ "uwsm" "app" "--" "foot" ];
        # foot -T scratch → matched by window rule → opens floating
        "Mod+Shift+Return".action.spawn = [ "uwsm" "app" "--" "foot" "-T" "scratch" ];
        "Mod+Space".action.spawn        = [ "noctalia-shell" "ipc" "call" "launcher" "toggle" ];
        "Mod+c".action.spawn = [ "noctalia-shell" "ipc" "call" "plugin:clipper" "toggle" ];
        "Mod+E".action.spawn = [ "uwsm" "app" "--" "foot" "-e" "hx" "." ];
        "Mod+F".action.spawn = [ "uwsm" "app" "--" "foot" "-e" "yazi" ];

        # KeePassXC toggle — show from tray or minimize back to tray.
        # KeePassXC must have "minimize to tray on close" enabled in its settings.
        "Mod+P".action.spawn = [ "sh" "-c" "if niri msg --json focused-window 2>/dev/null | grep -q KeePassXC; then niri msg action close-window; else keepassxc; fi" ];

        # --- Window management ---
        "Mod+Q".action.close-window           = {};
        "Mod+V".action.toggle-window-floating = {};
        "Mod+M".action.maximize-column        = {};
        "Mod+F11".action.fullscreen-window    = {};
        "Mod+Tab".action.focus-window-previous = {};

        # --- Layout control ---
        "Mod+R".action.switch-preset-column-width              = {};
        "Mod+Shift+C".action.center-column                     = {};
        "Mod+BracketLeft".action.consume-or-expel-window-left  = {};
        "Mod+BracketRight".action.consume-or-expel-window-right = {};
        "Mod+Minus".action.set-column-width  = "-10%";
        "Mod+Equal".action.set-column-width  = "+10%";
        "Mod+Shift+Minus".action.set-window-height = "-10%";
        "Mod+Shift+Equal".action.set-window-height = "+10%";

        # --- Session ---
        "Mod+Shift+E".action.quit = {};
        # Reload config via spawn (load-config-file is CLI-only, not a keybind action)
        "Mod+Shift+R".action.spawn = [ "niri" "msg" "action" "load-config-file" ];

        # --- Media / Brightness (Noctalia IPC for OSD) ---
        "XF86AudioRaiseVolume".action.spawn  = [ "noctalia-shell" "ipc" "call" "volume" "increase" ];
        "XF86AudioLowerVolume".action.spawn  = [ "noctalia-shell" "ipc" "call" "volume" "decrease" ];
        "XF86AudioMute".action.spawn         = [ "noctalia-shell" "ipc" "call" "volume" "muteOutput" ];
        "XF86AudioPlay".action.spawn         = [ "noctalia-shell" "ipc" "call" "media" "playPause" ];
        "XF86AudioNext".action.spawn         = [ "noctalia-shell" "ipc" "call" "media" "next" ];
        "XF86AudioPrev".action.spawn         = [ "noctalia-shell" "ipc" "call" "media" "previous" ];
        "XF86MonBrightnessUp".action.spawn   = [ "noctalia-shell" "ipc" "call" "brightness" "increase" ];
        "XF86MonBrightnessDown".action.spawn = [ "noctalia-shell" "ipc" "call" "brightness" "decrease" ];

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
      };
    };
  };

  # Noctalia shell — configured declaratively via noctalia HM module.
  # systemd.enable: creates a user service that starts after graphical-session.target,
  # replacing the fragile spawn-at-startup approach (which fires too early in the session).
  #
  # Full settings ported from live Noctalia IPC dump — survives ZFS rollback (cache wipe).
  programs.noctalia-shell = {
    enable = true;
    systemd.enable = true;
    settings = {

      bar = {
        barType = "simple";
        position = "top";
        monitors = [];
        density = "default";
        showOutline = false;
        showCapsule = true;
        capsuleOpacity = lib.mkForce 1.0;
        capsuleColorKey = "none";
        widgetSpacing = 6;
        contentPadding = 2;
        fontScale = 1.0;
        enableExclusionZoneInset = true;
        backgroundOpacity = lib.mkForce 1.0;
        useSeparateOpacity = false;
        marginVertical = 4;
        marginHorizontal = 4;
        frameThickness = 8;
        frameRadius = 12;
        outerCorners = true;
        hideOnOverview = false;
        displayMode = "always_visible";
        autoHideDelay = 500;
        autoShowDelay = 150;
        showOnWorkspaceSwitch = true;
        widgets = {
          left = [
            {
              defaultSettings = {
                ai = {
                  maxHistoryLength = 100;
                  model = "gemini-2.5-flash";
                  openaiBaseUrl = "https://api.openai.com/v1/chat/completions";
                  openaiLocal = false;
                  provider = "google";
                  systemPrompt = "You are a helpful assistant integrated into a Linux desktop shell. Be concise and helpful.";
                  temperature = 0.7;
                };
                maxHistoryLength = 100;
                panelDetached = true;
                panelHeightRatio = 0.85;
                panelPosition = "right";
                panelWidth = 520;
                scale = 1.0;
                translator = {
                  backend = "google";
                  deeplApiKey = "";
                  realTimeTranslation = true;
                  sourceLanguage = "auto";
                  targetLanguage = "en";
                };
              };
              id = "plugin:assistant-panel";
            }
            {
              characterCount = 2;
              colorizeIcons = false;
              emptyColor = "secondary";
              enableScrollWheel = true;
              focusedColor = "primary";
              followFocusedScreen = false;
              fontWeight = "bold";
              groupedBorderOpacity = 1.0;
              hideUnoccupied = false;
              iconScale = 0.8;
              id = "Workspace";
              labelMode = "index";
              occupiedColor = "secondary";
              pillSize = 0.6;
              showApplications = false;
              showApplicationsHover = false;
              showBadge = true;
              showLabelsOnlyWhenOccupied = true;
              unfocusedIconsOpacity = 1.0;
            }
            {
              defaultSettings = {
                debounceMs = 300;
                enabled = true;
                language = "auto";
                maxEventsPerSecond = 20;
                maxVisible = 4;
                perWorkspace = false;
                workspaceMaxVisible = {};
              };
              id = "plugin:niri-auto-tile";
            }
            {
              colorizeIcons = false;
              hideMode = "hidden";
              id = "ActiveWindow";
              maxWidth = 145;
              scrollingMode = "hover";
              showIcon = true;
              textColor = "none";
              useFixedWidth = false;
            }
            {
              id = "Spacer";
              width = 5;
            }
            {
              compactMode = false;
              hideMode = "hidden";
              hideWhenIdle = false;
              id = "MediaMini";
              maxWidth = 145;
              panelShowAlbumArt = true;
              scrollingMode = "hover";
              showAlbumArt = true;
              showArtistFirst = true;
              showProgressRing = true;
              showVisualizer = false;
              textColor = "none";
              useFixedWidth = false;
              visualizerType = "linear";
            }
          ];
          center = [
            {
              colorizeSystemIcon = "primary";
              customIconPath = "";
              enableColorization = true;
              icon = "rocket";
              iconColor = "none";
              id = "Launcher";
              useDistroLogo = true;
            }
            {
              id = "Spacer";
              width = 5;
            }
            {
              clockColor = "none";
              customFont = "";
              formatHorizontal = "HH:mm ddd, MMM dd";
              formatVertical = "HH mm - dd MM";
              id = "Clock";
              tooltipFormat = "HH:mm ddd, MMM dd";
              useCustomFont = false;
            }
            {
              compactMode = true;
              diskPath = "/";
              iconColor = "none";
              id = "SystemMonitor";
              showCpuCores = false;
              showCpuFreq = false;
              showCpuTemp = true;
              showCpuUsage = true;
              showDiskAvailable = false;
              showDiskUsage = true;
              showDiskUsageAsPercent = false;
              showGpuTemp = false;
              showLoadAverage = false;
              showMemoryAsPercent = false;
              showMemoryUsage = true;
              showNetworkStats = true;
              showSwapUsage = false;
              textColor = "none";
              useMonospaceFont = true;
              usePadding = false;
            }
            {
              id = "Spacer";
              width = 5;
            }
            {
              defaultSettings = {
                autoHeight = true;
                cheatsheetData = [];
                columnCount = 3;
                detectedCompositor = "";
                hyprlandConfigPath = "~/.config/hypr/hyprland.conf";
                modKeyVariable = "$mod";
                niriConfigPath = "~/.config/niri/config.kdl";
                windowHeight = 0;
                windowWidth = 1400;
              };
              id = "plugin:keybind-cheatsheet";
            }
          ];
          right = [
            {
              defaultSettings = {
                colorHistory = [];
                detectedRecorder = "";
                installedLangs = [ "eng" ];
                paletteColors = [];
                selectedOcrLang = "eng";
                transAvailable = false;
              };
              id = "plugin:screen-toolkit";
            }
            {
              defaultSettings = {};
              id = "plugin:mirror-mirror";
            }
            {
              defaultSettings = {};
              id = "plugin:screenshot";
            }
            {
              defaultSettings = {
                audioCodec = "opus";
                audioSource = "default_output";
                colorRange = "limited";
                copyToClipboard = false;
                customReplayDuration = "30";
                directory = "";
                filenamePattern = "recording_yyyyMMdd_HHmmss";
                frameRate = "60";
                hideInactive = false;
                iconColor = "none";
                quality = "very_high";
                replayDuration = "30";
                replayEnabled = false;
                replayStorage = "ram";
                resolution = "original";
                restorePortalSession = false;
                showCursor = true;
                videoCodec = "h264";
                videoSource = "portal";
              };
              id = "plugin:screen-recorder";
            }
            {
              id = "Spacer";
              width = 5;
            }
            {
              blacklist = [];
              chevronColor = "none";
              colorizeIcons = false;
              drawerEnabled = true;
              hidePassive = false;
              id = "Tray";
              pinned = [];
            }
            {
              defaultSettings = {};
              id = "plugin:usb-device-manager";
            }
            {
              hideWhenZero = false;
              hideWhenZeroUnread = false;
              iconColor = "none";
              id = "NotificationHistory";
              showUnreadBadge = true;
              unreadBadgeColor = "primary";
            }
            {
              deviceNativePath = "__default__";
              displayMode = "graphic-clean";
              hideIfIdle = false;
              hideIfNotDetected = true;
              id = "Battery";
              showNoctaliaPerformance = true;
              showPowerProfiles = true;
            }
            {
              defaultSettings = {
                mainDeviceId = "";
              };
              id = "plugin:valent-connect";
            }
            {
              colorizeDistroLogo = false;
              colorizeSystemIcon = "secondary";
              customIconPath = "";
              enableColorization = true;
              icon = "noctalia";
              id = "ControlCenter";
              useDistroLogo = false;
            }
          ];
        };
        mouseWheelAction = "none";
        reverseScroll = false;
        mouseWheelWrap = true;
        middleClickAction = "none";
        middleClickFollowMouse = false;
        middleClickCommand = "";
        rightClickAction = "controlCenter";
        rightClickFollowMouse = true;
        rightClickCommand = "";
        screenOverrides = [];
      };

      general = {
        avatarImage = "/home/lgo/.face";
        dimmerOpacity = 0.2;
        showScreenCorners = false;
        forceBlackScreenCorners = false;
        scaleRatio = 1.0;
        radiusRatio = 1.0;
        iRadiusRatio = 1.0;
        boxRadiusRatio = 1.0;
        screenRadiusRatio = 1.0;
        animationSpeed = 1.3;
        animationDisabled = false;
        compactLockScreen = false;
        lockScreenAnimations = true;
        lockOnSuspend = true;
        showSessionButtonsOnLockScreen = true;
        showHibernateOnLockScreen = false;
        enableLockScreenMediaControls = true;
        enableShadows = true;
        enableBlurBehind = true;
        shadowDirection = "bottom_right";
        shadowOffsetX = 2;
        shadowOffsetY = 3;
        language = "";
        allowPanelsOnScreenWithoutBar = true;
        # Suppress startup popups: changelog and setup wizard are shown when
        # shell-state.json is absent (cache lost after ZFS rollback).
        showChangelogOnStartup = false;
        telemetryEnabled = false;
        enableLockScreenCountdown = true;
        lockScreenCountdownDuration = 10000;
        autoStartAuth = true;
        allowPasswordWithFprintd = true;
        clockStyle = "custom";
        clockFormat = "HH:MM dd, yyyy-MM-dd ";
        passwordChars = true;
        lockScreenMonitors = [];
        lockScreenBlur = 0.3;
        lockScreenTint = 0;
        keybinds = {
          keyUp    = [ "Up" "Ctrl+K" ];
          keyDown  = [ "Down" "Ctrl+J" ];
          keyLeft  = [ "Left" "Ctrl+H" ];
          keyRight = [ "Right" "Ctrl+L" ];
          keyEnter = [ "Return" "Enter" ];
          keyEscape = [ "Esc" "Ctrl+Q" ];
          keyRemove = [ "Del" "Ctrl+D" ];
        };
        reverseScroll = false;
        smoothScrollEnabled = true;
      };

      ui = {
        fontDefault = lib.mkForce "MonaspiceNe Nerd Font Propo";
        fontFixed = lib.mkForce "MonaspiceAr Nerd Font Mono";
        fontDefaultScale = 1.0;
        fontFixedScale = 1.0;
        tooltipsEnabled = true;
        scrollbarAlwaysVisible = true;
        boxBorderEnabled = false;
        panelBackgroundOpacity = lib.mkForce 0.9;
        translucentWidgets = true;
        panelsAttachedToBar = true;
        settingsPanelMode = "attached";
        settingsPanelSideBarCardStyle = false;
      };

      location = {
        name = "Duesseldorf";
        weatherEnabled = true;
        weatherShowEffects = true;
        useFahrenheit = false;
        use12hourFormat = false;
        showWeekNumberInCalendar = true;
        showCalendarEvents = true;
        showCalendarWeather = true;
        analogClockInCalendar = false;
        firstDayOfWeek = 1;
        hideWeatherTimezone = false;
        hideWeatherCityName = false;
      };

      calendar = {
        cards = [
          { enabled = true; id = "calendar-header-card"; }
          { enabled = true; id = "calendar-month-card"; }
          { enabled = true; id = "weather-card"; }
        ];
      };

      wallpaper = {
        enabled = true;
        overviewEnabled = false;
        # Matches where wallpapers.nix installs PNGs; explicit so it survives
        # any future XDG_PICTURES_DIR changes.
        directory = "/home/lgo/Pictures/Wallpapers";
        monitorDirectories = [];
        enableMultiMonitorDirectories = false;
        showHiddenFiles = false;
        viewMode = "single";
        setWallpaperOnAllMonitors = true;
        fillMode = "crop";
        fillColor = "#000000";
        useSolidColor = false;
        solidColor = "#1a1a2e";
        automationEnabled = false;
        wallpaperChangeMode = "random";
        randomIntervalSec = 300;
        transitionDuration = 1500;
        transitionType = [ "fade" "disc" "stripes" "wipe" "pixelate" "honeycomb" ];
        skipStartupTransition = false;
        transitionEdgeSmoothness = 0.05;
        panelPosition = "follow_bar";
        hideWallpaperFilenames = false;
        useOriginalImages = false;
        overviewBlur = 0.4;
        overviewTint = 0.6;
        useWallhaven = false;
        wallhavenQuery = "";
        wallhavenSorting = "relevance";
        wallhavenOrder = "desc";
        wallhavenCategories = "111";
        wallhavenPurity = "100";
        wallhavenRatios = "";
        wallhavenApiKey = "";
        wallhavenResolutionMode = "atleast";
        wallhavenResolutionWidth = "";
        wallhavenResolutionHeight = "";
        sortOrder = "name";
        favorites = [];
      };

      appLauncher = {
        enableClipboardHistory = true;
        autoPasteClipboard = false;
        enableClipPreview = true;
        clipboardWrapText = true;
        enableClipboardSmartIcons = true;
        enableClipboardChips = true;
        clipboardWatchTextCommand = "wl-paste --type text --watch cliphist store";
        clipboardWatchImageCommand = "wl-paste --type image --watch cliphist store";
        position = "center";
        pinnedApps = [];
        sortByMostUsed = true;
        terminalCommand = "foot -e";
        customLaunchPrefixEnabled = false;
        customLaunchPrefix = "";
        viewMode = "list";
        showCategories = true;
        iconMode = "native";
        showIconBackground = false;
        enableSettingsSearch = true;
        enableWindowsSearch = true;
        enableSessionSearch = true;
        ignoreMouseInput = false;
        screenshotAnnotationTool = "";
        overviewLayer = false;
        density = "compact";
      };

      controlCenter = {
        position = "close_to_bar_button";
        diskPath = "/";
        shortcuts = {
          left = [
            { id = "Network"; }
            { id = "Bluetooth"; }
            { id = "NoctaliaPerformance"; }
            { id = "PowerProfile"; }
          ];
          right = [
            { id = "KeepAwake"; }
            { id = "NightLight"; }
            { id = "AirplaneMode"; }
            {
              defaultSettings = {
                enableTodoIntegration = false;
                notecardsEnabled = true;
                pincardsEnabled = true;
                showCloseButton = true;
              };
              id = "plugin:clipper";
            }
          ];
        };
        cards = [
          { enabled = true; id = "profile-card"; }
          { enabled = true; id = "shortcuts-card"; }
          { enabled = true; id = "audio-card"; }
          { enabled = true; id = "brightness-card"; }
          { enabled = true; id = "weather-card"; }
          { enabled = true; id = "media-sysmon-card"; }
        ];
      };

      systemMonitor = {
        cpuWarningThreshold = 80;
        cpuCriticalThreshold = 90;
        tempWarningThreshold = 80;
        tempCriticalThreshold = 90;
        gpuWarningThreshold = 80;
        gpuCriticalThreshold = 90;
        memWarningThreshold = 80;
        memCriticalThreshold = 90;
        swapWarningThreshold = 80;
        swapCriticalThreshold = 90;
        diskWarningThreshold = 80;
        diskCriticalThreshold = 90;
        diskAvailWarningThreshold = 20;
        diskAvailCriticalThreshold = 10;
        batteryWarningThreshold = 20;
        batteryCriticalThreshold = 5;
        enableDgpuMonitoring = false;
        useCustomColors = false;
        warningColor = "";
        criticalColor = "";
        externalMonitor = "resources || missioncenter || jdsystemmonitor || corestats || system-monitoring-center || gnome-system-monitor || plasma-systemmonitor || mate-system-monitor || ukui-system-monitor || deepin-system-monitor || pantheon-system-monitor";
      };

      noctaliaPerformance = {
        disableWallpaper = true;
        disableDesktopWidgets = true;
      };

      dock = {
        enabled = true;
        position = "bottom";
        displayMode = "auto_hide";
        dockType = "floating";
        backgroundOpacity = lib.mkForce 0.9;
        floatingRatio = 1.0;
        size = 1.0;
        onlySameOutput = true;
        monitors = [];
        pinnedApps = [];
        colorizeIcons = true;
        showLauncherIcon = true;
        launcherPosition = "start";
        launcherUseDistroLogo = true;
        launcherIcon = "";
        launcherIconColor = "primary";
        pinnedStatic = true;
        inactiveIndicators = true;
        groupApps = true;
        groupContextMenuMode = "extended";
        groupClickAction = "cycle";
        groupIndicatorStyle = "dots";
        deadOpacity = 0.6;
        animationSpeed = 1.0;
        sitOnFrame = false;
        showDockIndicator = true;
        indicatorThickness = 3;
        indicatorColor = "primary";
        indicatorOpacity = 0.6;
      };

      network = {
        airplaneModeEnabled = false;
        bluetoothRssiPollingEnabled = false;
        bluetoothRssiPollIntervalMs = 60000;
        networkPanelView = "wifi";
        wifiDetailsViewMode = "list";
        bluetoothDetailsViewMode = "grid";
        bluetoothHideUnnamedDevices = false;
        disableDiscoverability = false;
        bluetoothAutoConnect = true;
      };

      sessionMenu = {
        enableCountdown = true;
        countdownDuration = 5000;
        position = "center";
        showHeader = true;
        showKeybinds = true;
        largeButtonsStyle = false;
        largeButtonsLayout = "single-row";
        powerOptions = [
          { action = "lock";     command = ""; countdownEnabled = true; enabled = true; keybind = "1"; }
          { action = "suspend";  command = ""; countdownEnabled = true; enabled = true; keybind = "2"; }
          { action = "hibernate"; command = ""; countdownEnabled = true; enabled = true; keybind = "3"; }
          { action = "reboot";   command = ""; countdownEnabled = true; enabled = true; keybind = "4"; }
          { action = "logout";   command = ""; countdownEnabled = true; enabled = true; keybind = "5"; }
          { action = "shutdown"; command = ""; countdownEnabled = true; enabled = true; keybind = "6"; }
          { action = "rebootToUefi";     command = ""; countdownEnabled = true; enabled = false; keybind = ""; }
          { action = "userspaceReboot";  command = ""; countdownEnabled = true; enabled = false; keybind = ""; }
        ];
      };

      notifications = {
        enabled = true;
        enableMarkdown = true;
        density = "default";
        monitors = [];
        location = "top_right";
        overlayLayer = true;
        backgroundOpacity = lib.mkForce 0.8;
        respectExpireTimeout = false;
        lowUrgencyDuration = 3;
        normalUrgencyDuration = 8;
        criticalUrgencyDuration = 15;
        clearDismissed = true;
        saveToHistory = {
          low = true;
          normal = true;
          critical = true;
        };
        sounds = {
          enabled = false;
          volume = 0.5;
          separateSounds = false;
          criticalSoundFile = "";
          normalSoundFile = "";
          lowSoundFile = "";
          excludedApps = "discord,firefox,chrome,chromium,edge";
        };
        enableMediaToast = false;
        enableKeyboardLayoutToast = true;
        enableBatteryToast = true;
      };

      osd = {
        enabled = true;
        location = "top_right";
        autoHideMs = 2000;
        overlayLayer = true;
        backgroundOpacity = lib.mkForce 0.9;
        enabledTypes = [ 0 1 2 ];
        monitors = [];
      };

      audio = {
        volumeStep = 5;
        volumeOverdrive = false;
        spectrumFrameRate = 30;
        visualizerType = "linear";
        spectrumMirrored = true;
        mprisBlacklist = [];
        preferredPlayer = "";
        volumeFeedback = false;
        volumeFeedbackSoundFile = "";
      };

      brightness = {
        brightnessStep = 5;
        enforceMinimum = true;
        enableDdcSupport = true;
        backlightDeviceMappings = [];
      };

      # predefinedScheme = "" prevents noctalia from regenerating colors.json.
      # AppThemeService calls applyScheme(predefinedScheme) on wallpaper changes;
      # with "", resolveSchemePath fails silently, leaving Stylix colors intact.
      colorSchemes = {
        useWallpaperColors = false;
        predefinedScheme = "";
        darkMode = true;
        schedulingMode = "off";
        manualSunrise = "06:30";
        manualSunset = "18:30";
        generationMethod = "tonal-spot";
        monitorForColors = "";
        syncGsettings = true;
      };

      templates = {
        activeTemplates = [];
        enableUserTheming = false;
      };

      nightLight = {
        enabled = false;
        forced = false;
        autoSchedule = true;
        nightTemp = "4000";
        dayTemp = "6500";
        manualSunrise = "06:30";
        manualSunset = "18:30";
      };

      hooks = {
        enabled = false;
        wallpaperChange = "";
        darkModeChange = "";
        screenLock = "";
        screenUnlock = "";
        performanceModeEnabled = "";
        performanceModeDisabled = "";
        startup = "";
        session = "";
        colorGeneration = "";
      };

      plugins = {
        autoUpdate = false;
        notifyUpdates = true;
      };

      idle = {
        enabled = false;
        screenOffTimeout = 600;
        lockTimeout = 660;
        suspendTimeout = 1800;
        fadeDuration = 5;
        screenOffCommand = "";
        lockCommand = "";
        suspendCommand = "";
        resumeScreenOffCommand = "";
        resumeLockCommand = "";
        resumeSuspendCommand = "";
        customCommands = "[]";
      };

      desktopWidgets = {
        enabled = false;
        overviewEnabled = true;
        gridSnap = false;
        gridSnapScale = false;
        monitorWidgets = [];
      };

    };

    # Per-plugin settings — written to ~/.config/noctalia/plugins/<name>/settings.json.
    # These are the actual user preferences (may differ from bar widget defaultSettings).
    pluginSettings = {
      clipper = {
        enableTodoIntegration = false;
        pincardsEnabled = true;
        notecardsEnabled = true;
        showCloseButton = false;
        fullscreenMode = false;
        hidePanelBackground = false;
        autoPaste = false;
        autoPasteOnRightClick = false;
        autoPasteDelay = 300;
        # Card colors use Noctalia theme variables — follows color scheme automatically.
        cardColors = {
          Text  = { bg = "mOutline";    separator = "mSurface"; fg = "mOnSurface"; };
          Image = { bg = "mTertiary";   separator = "mSurface"; fg = "mOnTertiary"; };
          Link  = { bg = "mPrimary";    separator = "mSurface"; fg = "mOnPrimary"; };
          Code  = { bg = "mSecondary";  separator = "mSurface"; fg = "mOnSecondary"; };
          Color = { bg = "mSecondary";  separator = "mSurface"; fg = "mOnSecondary"; };
          Emoji = { bg = "mHover";      separator = "mSurface"; fg = "mOnHover"; };
          File  = { bg = "mError";      separator = "mSurface"; fg = "mOnError"; };
        };
      };

      niri-auto-tile = {
        enabled = true;
        perWorkspace = true;
        onlyAtMax = true;
        maxVisible = 2;
        debounceMs = 300;
        maxEventsPerSecond = 20;
      };

      screen-recorder = {
        hideInactive = false;
        iconColor = "none";
        directory = "";
        filenamePattern = "recording_yyyyMMdd_HHmmss";
        frameRate = "60";
        customFrameRate = "60";
        audioCodec = "opus";
        videoCodec = "h264";
        quality = "very_high";
        colorRange = "limited";
        showCursor = true;
        copyToClipboard = true;
        audioSource = "default_output";
        videoSource = "portal";
        resolution = "original";
        restorePortalSession = false;
        replayEnabled = false;
        replayDuration = "30";
        customReplayDuration = "30";
        replayStorage = "ram";
      };

      # API key omitted — add it manually in the Noctalia assistant-panel settings UI.
      assistant-panel = {
        ai = {
          provider = "google";
          models = {};
          temperature = 0.7;
          systemPrompt = "You are a helpful assistant integrated into a Linux desktop shell. Be concise and helpful.";
          openaiLocal = false;
          openaiBaseUrl = "https://api.openai.com/v1/chat/completions";
          model = "";
        };
        translator = {
          backend = "google";
          deeplApiKey = "";
          realTimeTranslation = true;
        };
        maxHistoryLength = 100;
        panelDetached = false;
        panelPosition = "left";
        panelHeightRatio = 0.85;
        panelWidth = 520;
        attachmentStyle = "connected";
        scale = 1;
      };

      keybind-cheatsheet = {
        # cheatsheetData auto-generated by the plugin from niri config — omitted here.
        cheatsheetData = [];
        detectedCompositor = "niri";
        niriConfigPath = "~/.config/niri/config.kdl";
        hyprlandConfigPath = "~/.config/hypr/hyprland.conf";
        modKeyVariable = "$mod";
        windowHeight = 850;
        windowWidth = 1400;
      };
    };
  };

  # Stylix targets — noctalia needs explicit opt-in; KDE has a shellcheck bug so disable it.
  stylix.targets.noctalia-shell.enable = true;
  stylix.targets.kde.enable = false;

  # Override Noctalia accent colors for a distinctly Gruvbox look.
  # The Stylix target defaults mPrimary=base0D (muted teal) which doesn't read as Gruvbox.
  # Orange (base09) as primary, teal/aqua (base0C) as secondary — both iconic Gruvbox accents.
  # lib.mkForce overrides the Stylix target's default assignments.
  programs.noctalia-shell.colors = lib.mkForce (
    let c = config.lib.stylix.colors; in {
      mPrimary          = "#${c.base09}";  # Gruvbox orange
      mOnPrimary        = "#${c.base00}";
      mSecondary        = "#${c.base0C}";  # Gruvbox teal/aqua
      mOnSecondary      = "#${c.base00}";
      mTertiary         = "#${c.base0B}";  # Gruvbox green
      mOnTertiary       = "#${c.base00}";
      mError            = "#${c.base08}";
      mOnError          = "#${c.base00}";
      mSurface          = "#${c.base00}";
      mOnSurface        = "#${c.base05}";
      mHover            = "#${c.base09}";
      mOnHover          = "#${c.base00}";
      mSurfaceVariant   = "#${c.base01}";
      mOnSurfaceVariant = "#${c.base04}";
      mOutline          = "#${c.base03}";
      mShadow           = "#${c.base00}";
    }
  );

  # force = true: noctalia replaces HM symlinks with regular files at runtime (saves
  # settings). On next nixos-rebuild HM would fail with "would be clobbered". Force lets
  # HM overwrite them back to managed symlinks. niri/config.kdl is handled by
  # home-manager.backupFileExtension in configuration.nix (niri-flake uses a different
  # internal home.file key, so adding force here would create a conflicting target).
  xdg.configFile."noctalia/colors.json".force = true;
  xdg.configFile."noctalia/settings.json".force = true;
  xdg.configFile."noctalia/plugins/clipper/settings.json".force = true;
  xdg.configFile."noctalia/plugins/niri-auto-tile/settings.json".force = true;
  xdg.configFile."noctalia/plugins/screen-recorder/settings.json".force = true;
  xdg.configFile."noctalia/plugins/assistant-panel/settings.json".force = true;
  xdg.configFile."noctalia/plugins/keybind-cheatsheet/settings.json".force = true;

  # Adopt gtk4 default — stateVersion < 26.05 otherwise inherits gtk3 theme; stylix handles gtk4 theming via css.
  gtk.gtk4.theme = null;

  # Foot terminal — Stylix manages colors and font (MonaspiceAr via stylix.fonts.monospace).
  # dpi-aware=no: Niri handles HiDPI scaling at the compositor level; foot must not double-scale.
  programs.foot = {
    enable = true;
    settings = {
      main = {
        term              = "xterm-256color";
        pad               = "8x8";
        resize-delay-ms   = 100;
        dpi-aware         = "no";
      };
      bell       = { urgent = false; notify = false; visual = false; };
      scrollback = { lines = 10000; multiplier = 3.0; };
      url = {
        launch        = "xdg-open \${url}";
        label-letters = "sadfjklewcmpgh";
        osc8-underline = "url-mode";
      };
      cursor = { style = "block"; blink = false; };
      mouse  = { hide-when-typing = true; alternate-scroll-mode = "yes"; };
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

  # Starship prompt — copied verbatim from ~/nixconfig/home-modules/shell/starship.nix.
  # Uses '' strings to preserve embedded Nerd Font codepoints literally (Nix has no \u escapes).
  programs.starship = {
    enable = true;
    enableBashIntegration    = true;
    enableZshIntegration     = true;
    enableNushellIntegration = true;
    settings = {
      format = ''
        $cmd_duration 󰜥 $directory $git_branch
        $character'';

      add_newline = false;

      character = {
        success_symbol = "[   ](bold blue)";
        error_symbol = "[   ](bold red)";
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
      memory_usage = { disabled = true; threshold = -1; };
      time.disabled = true;
      line_break.disabled = false;

      nix_shell = { format = "via [❄️ $state( \\($name\\))](bold blue) "; };
      python    = { format = "via [🐍 $version](bold green) "; };
      rust      = { format = "via [⚡ $version](bold orange) "; };
      nodejs    = { format = "via [⬢ $version](bold green) "; };
    };
  };

  # Point Noctalia's lockscreen at the dedicated PAM service (noctalia.nix).
  # Without this, Noctalia falls back to the "login" service (LockContext.qml default).
  systemd.user.sessionVariables.NOCTALIA_PAM_SERVICE = "noctalia";

  # Idle management: lock after 5 min idle, monitors off after 5.5 min, lock before sleep.
  # -w: swayidle holds the sleep inhibitor until the before-sleep command exits.
  # "sleep 2" gives Noctalia time to display its lockscreen before the system suspends.
  # loginctl lock-session sends the org.freedesktop.login1 Lock signal → Noctalia lockscreen.
  services.swayidle = {
    enable = true;
    extraArgs = [ "-w" ];
    events = {
      before-sleep = "loginctl lock-session; sleep 2";
    };
    timeouts = [
      { timeout = 300; command = "loginctl lock-session"; }
      { timeout = 330; command = "niri msg action power-off-monitors"; }
    ];
  };

  # Common graphical packages for all desktop users
  home.packages = with pkgs; [
    ghostty   # secondary terminal (foot is default via Mod+Return)
    grim
    slurp
    wl-clipboard
    playerctl
    nextcloud-client
  ];

  # Nextcloud desktop client — syncs files in the background
  systemd.user.services.nextcloud-client = {
    Unit = {
      Description = "Nextcloud Desktop Client";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.nextcloud-client}/bin/nextcloud --background";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
