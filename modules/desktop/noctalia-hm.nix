# Shared Home Manager module for Noctalia-based Wayland desktops.
# Imported by niri-hm.nix and labwc-hm.nix; compositor-specific conditionals
# use isNiri / isLabwc derived from osConfig.
{
  pkgs,
  pkgs-unstable,
  config,
  lib,
  osConfig,
  inputs,
  ...
}: let
  # Safe checks: niri/labwc options only exist when the respective compositor module is imported.
  isNiri  = (osConfig.clanarchy.desktop ? niri)  && osConfig.clanarchy.desktop.niri.enable;
  isLabwc = (osConfig.clanarchy.desktop ? labwc) && osConfig.clanarchy.desktop.labwc.enable;
  # Per-USER gate, deliberately not folded into isNiri. The two happen to
  # select the same machine today (lgo is the only niri user), and that is
  # exactly why they must stay separate: a plugin scoped to a person is not a
  # plugin scoped to a compositor, and conflating them breaks silently the
  # first time lgo runs labwc or a second person runs niri.
  isLgo   = config.home.username == "lgo";
in {
  imports = [
    inputs.noctalia.homeModules.default  # provides programs.noctalia-shell option
    ./foot-hm.nix                        # shared foot terminal config
  ];

  # Noctalia shell — configured declaratively via noctalia HM module.
  # Launched via compositor autostart with UWSM so it runs as a tracked systemd unit.
  programs.noctalia-shell = {
    enable = true;
    settings = {
      bar = {
        barType = "simple";
        position = "top";
        monitors = ["eDP-1"];
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
          ] ++ lib.optionals isNiri [
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
          ] ++ [
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
                labwcConfigPath = "~/.config/labwc/rc.xml";
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
                installedLangs = ["eng"];
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
          ] ++ lib.optionals isLabwc [
            {
              defaultSettings = {
                profilesDir      = "";
                icon             = "wand";
                iconColor        = "primary";
                includeWallpapers = true;
                lastAppliedProfile = "";
                backupEnabled    = true;
                backupCount      = 5;
              };
              id = "plugin:shell-profiles";
            }
          ] ++ [
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
        avatarImage = "${config.home.homeDirectory}/.face";
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
        # fprintd available on niri (miralda/Framework) — allows fingerprint unlock.
        allowPasswordWithFprintd = isNiri;
        clockStyle = "custom";
        clockFormat = "HH:MM dd, yyyy-MM-dd ";
        passwordChars = true;
        lockScreenMonitors = [];
        lockScreenBlur = 0.3;
        lockScreenTint = 0;
        keybinds = {
          keyUp = ["Up" "Ctrl+K"];
          keyDown = ["Down" "Ctrl+J"];
          keyLeft = ["Left" "Ctrl+H"];
          keyRight = ["Right" "Ctrl+L"];
          keyEnter = ["Return" "Enter"];
          keyEscape = ["Esc" "Ctrl+Q"];
          keyRemove = ["Del" "Ctrl+D"];
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
        directory = "${config.home.homeDirectory}/Pictures/Wallpapers";
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
        transitionType = ["fade" "disc" "stripes" "wipe" "pixelate" "honeycomb"];
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
        screenshotAnnotationTool = if isLabwc then "satty" else "";
        overviewLayer = false;
        density = "compact";
      };

      controlCenter = {
        position = "close_to_bar_button";
        diskPath = "/";
        shortcuts = {
          left = [
            {id = "Network";}
            {id = "Bluetooth";}
            {id = "NoctaliaPerformance";}
            {id = "PowerProfile";}
          ];
          right = [
            {id = "KeepAwake";}
            {id = "NightLight";}
            {id = "AirplaneMode";}
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
          { action = "lock";           command = ""; countdownEnabled = true; enabled = true;  keybind = "1"; }
          { action = "suspend";        command = ""; countdownEnabled = true; enabled = true;  keybind = "2"; }
          { action = "hibernate";      command = ""; countdownEnabled = true; enabled = true;  keybind = "3"; }
          { action = "reboot";         command = ""; countdownEnabled = true; enabled = true;  keybind = "4"; }
          { action = "logout";         command = ""; countdownEnabled = true; enabled = true;  keybind = "5"; }
          { action = "shutdown";       command = ""; countdownEnabled = true; enabled = true;  keybind = "6"; }
          { action = "rebootToUefi";   command = ""; countdownEnabled = true; enabled = false; keybind = ""; }
          { action = "userspaceReboot";command = ""; countdownEnabled = true; enabled = false; keybind = ""; }
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
        enabledTypes = [0 1 2];
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
        # Not a color source — the surface colors come from the Stylix
        # noctalia-shell target.  This is what ColorSchemeService feeds to
        # gsettings (syncGsettings below) as org.gnome.desktop.interface
        # color-scheme, so GTK apps must be told the same side of the palette
        # Stylix already picked, or they render dark chrome on a light desktop.
        darkMode = osConfig.stylix.polarity != "light";
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
        cardColors = {
          Text  = { bg = "mOutline";   separator = "mSurface"; fg = "mOnSurface"; };
          Image = { bg = "mTertiary";  separator = "mSurface"; fg = "mOnTertiary"; };
          Link  = { bg = "mPrimary";   separator = "mSurface"; fg = "mOnPrimary"; };
          Code  = { bg = "mSecondary"; separator = "mSurface"; fg = "mOnSecondary"; };
          Color = { bg = "mSecondary"; separator = "mSurface"; fg = "mOnSecondary"; };
          Emoji = { bg = "mHover";     separator = "mSurface"; fg = "mOnHover"; };
          File  = { bg = "mError";     separator = "mSurface"; fg = "mOnError"; };
        };
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
        cheatsheetData = [];
        detectedCompositor = if isNiri then "niri" else "labwc";
        niriConfigPath = "~/.config/niri/config.kdl";
        labwcConfigPath = "~/.config/labwc/rc.xml";
        hyprlandConfigPath = "~/.config/hypr/hyprland.conf";
        modKeyVariable = "$mod";
        windowHeight = 850;
        windowWidth = 1400;
      };

      usb-drive-manager = {
        autoMount = isNiri;
        fileBrowser = "yazi";
        terminalCommand = "foot";
        showNotifications = true;
        hideWhenEmpty = true;
        showBadge = true;
      };
    } // lib.optionalAttrs isNiri {
      niri-auto-tile = {
        enabled = true;
        perWorkspace = true;
        onlyAtMax = true;
        maxVisible = 2;
        debounceMs = 300;
        maxEventsPerSecond = 20;
      };
    };
  };

  # Lock Noctalia before the system enters sleep — runs as a systemd user pre-sleep service.
  systemd.user.services.noctalia-lock-before-sleep = {
    Unit = {
      Description = "Lock Noctalia screen before system sleep";
      Before = "sleep.target";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${config.programs.noctalia-shell.package}/bin/noctalia-shell ipc call lockScreen lock";
      TimeoutSec = "5s";
    };
    Install = {
      WantedBy = ["sleep.target"];
    };
  };

  stylix.targets.noctalia-shell.enable = true;
  stylix.targets.kde.enable = false;

  # Override Noctalia accent colors for the active Stylix palette (niri/miralda only).
  # lib.mkForce overrides the Stylix target's default base16 color assignments.
  programs.noctalia-shell.colors = lib.mkIf isNiri (lib.mkForce (
    let
      c = config.lib.stylix.colors;
    in {
      mPrimary          = "#${c.base09}";
      mOnPrimary        = "#${c.base00}";
      mSecondary        = "#${c.base0C}";
      mOnSecondary      = "#${c.base00}";
      mTertiary         = "#${c.base0B}";
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
  ));

  # force = true: noctalia replaces HM symlinks with regular files at runtime (saves
  # settings). On next nixos-rebuild HM would fail with "would be clobbered". Force lets
  # HM overwrite them back to managed symlinks; deSymlinkNoctalia then converts back.
  xdg.configFile."noctalia/colors.json".force = true;
  xdg.configFile."noctalia/settings.json".force = true;
  xdg.configFile."noctalia/plugins/clipper/settings.json".force = true;
  xdg.configFile."noctalia/plugins/screen-recorder/settings.json".force = true;
  xdg.configFile."noctalia/plugins/assistant-panel/settings.json".force = true;
  xdg.configFile."noctalia/plugins/keybind-cheatsheet/settings.json".force = true;
  xdg.configFile."noctalia/plugins/usb-drive-manager/settings.json".force = true;
  xdg.configFile."noctalia/plugins/niri-auto-tile/settings.json" = lib.mkIf isNiri { force = true; };

  # Seed Noctalia plugins.json with merge semantics — preserves existing download state.
  # If plugins.json is missing or a Nix store symlink: seed with the full declared list.
  # If it's a real file (managed by Noctalia at runtime): merge in any missing entries.
  home.activation.seedNoctaliaPlugins =
    let
      sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
      mkPlugin  = { enabled = true; inherit sourceUrl; };
      seed = pkgs.writeText "noctalia-plugins-seed.json" (builtins.toJSON {
        sources = [{ enabled = true; name = "Noctalia Plugins"; url = sourceUrl; }];
        states = {
          assistant-panel        = mkPlugin;
          calibre-provider       = mkPlugin;
          clipper                = mkPlugin;
          color-scheme-creator   = mkPlugin;
          display-settings       = mkPlugin;
          file-search            = mkPlugin;
          hassio                 = mkPlugin;
          khal-agenda-widget     = mkPlugin;
          keybind-cheatsheet     = mkPlugin;
          mirror-mirror          = mkPlugin;
          mullvad                = mkPlugin;
          network-manager-vpn    = mkPlugin;
          nvim-session-provider  = mkPlugin;
          obs-control            = mkPlugin;
          polkit-agent           = mkPlugin;
          screen-recorder        = mkPlugin;
          screen-shot-and-record = mkPlugin;
          screenshot             = mkPlugin;
          screen-toolkit         = mkPlugin;
          shell-profiles         = mkPlugin;
          todo                   = mkPlugin;
          usb-drive-manager      = mkPlugin;
          valent-connect         = mkPlugin;
          weekly-calendar        = mkPlugin;
        } // lib.optionalAttrs isNiri {
          niri-auto-tile         = mkPlugin;
        } // lib.optionalAttrs isLgo {
          # Giphy GIF search from the launcher (`>gif <query>`). lgo only.
          #
          # DELIBERATELY NO `pluginSettings.giphy-search` ENTRY, no
          # xdg.configFile force entry, and no _delink line — unlike clipper,
          # screen-recorder and the rest. That is not an omission.
          #
          # The plugin REQUIRES a Giphy API key (manifest.json:
          # defaultSettings = { api_key = ""; rating = "g"; }; free key from
          # developers.giphy.com). Declaring its settings here would do two
          # bad things at once:
          #
          #   1. A key written into a Nix-rendered settings.json lands in the
          #      WORLD-READABLE STORE. That is what invariant #8 forbids and
          #      what M7 went out of its way to avoid, staging Grafana's OIDC
          #      digest out of sops into a file rather than into the config.
          #   2. Worse, a DECLARED-EMPTY key would be re-applied on every
          #      rebuild. The force/_delink pair above exists precisely so
          #      "Nix-declared defaults are re-applied on every rebuild" — so
          #      `api_key = ""` here would silently WIPE the real key on every
          #      `clan machines update miralda`, and the plugin would break
          #      each deploy for no visible reason.
          #
          # So the key is typed once into the plugin's own Settings UI and
          # lives only in the runtime-owned settings.json. This is M4's
          # configuration policy — where a setting exists only in the UI, do
          # not fake it — and it is also the majority shape here: most plugins
          # in this list carry no pluginSettings block at all. The plugin
          # self-defaults `rating = "g"` from its manifest, so nothing is lost.
          #
          # (`pluginSettings.assistant-panel.translator.deeplApiKey = ""`
          # above has the same wipe-on-rebuild shape. It is inert today
          # because that backend is "google", but it is worth knowing about
          # before anyone switches it to DeepL and wonders where the key went.)
          giphy-search           = mkPlugin;
        };
        version = 2;
      });
    in
    lib.hm.dag.entryAfter ["linkGeneration"] ''
      _json="$HOME/.config/noctalia/plugins.json"
      if [ ! -e "$_json" ] || [ -L "$_json" ]; then
        rm -f "$_json"
        cp ${seed} "$_json"
        chmod 644 "$_json"
      else
        _tmp=$(mktemp)
        ${pkgs.jq}/bin/jq --slurpfile seed ${seed} \
          '.states = ($seed[0].states + .states)' \
          "$_json" > "$_tmp" && mv "$_tmp" "$_json"
      fi
    '';

  # Convert Noctalia-managed symlinks to writable regular files after each activation.
  # Noctalia needs to write back to these files at runtime; plain symlinks into the
  # read-only Nix store would fail silently or require Noctalia to unlink+recreate.
  # Nix-declared defaults are re-applied on every rebuild (symlink recreated, then converted).
  home.activation.deSymlinkNoctalia = lib.hm.dag.entryAfter ["linkGeneration"] ''
    _delink() {
      local f="$1"
      if [ -L "$f" ]; then
        local src tmp
        src=$(readlink "$f")
        tmp="$f.tmp"
        cp "$src" "$tmp"
        chmod 644 "$tmp"
        mv "$tmp" "$f"
      fi
      rm -f "$f.bak"
    }
    _delink "$HOME/.config/noctalia/colors.json"
    _delink "$HOME/.config/noctalia/settings.json"
    _delink "$HOME/.config/noctalia/plugins/clipper/settings.json"
    _delink "$HOME/.config/noctalia/plugins/screen-recorder/settings.json"
    _delink "$HOME/.config/noctalia/plugins/assistant-panel/settings.json"
    _delink "$HOME/.config/noctalia/plugins/keybind-cheatsheet/settings.json"
    _delink "$HOME/.config/noctalia/plugins/usb-drive-manager/settings.json"
    ${lib.optionalString isNiri ''
      _delink "$HOME/.config/noctalia/plugins/niri-auto-tile/settings.json"
    ''}
    ${lib.optionalString isLabwc ''
      _delink "$HOME/.cache/noctalia/wallpapers.json"
    ''}
  '';

  gtk.gtk4.theme = lib.mkForce null;   # newer stylix sets a non-null theme; mkForce keeps Noctalia's no-GTK4-theme intent

  gtk.iconTheme = {
    name    = osConfig.clanarchy.iconTheme.name;
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
        $cmd_duration 󰜥 $directory $git_branch
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
      before-sleep = "${config.programs.noctalia-shell.package}/bin/noctalia-shell ipc call lockScreen lock; sleep 1";
      after-resume = "${config.programs.noctalia-shell.package}/bin/noctalia-shell ipc call lockScreen lock";
    };
    timeouts = [
      {
        timeout = 300;
        command = "loginctl lock-session";
      }
      ({
        timeout = 330;
        command = if isNiri
          then "niri msg action power-off-monitors"
          else "${pkgs.wlopm}/bin/wlopm --off '*'";
      } // lib.optionalAttrs isLabwc {
        resumeCommand = "${pkgs.wlopm}/bin/wlopm --on '*'";
      })
    ];
  };

  home.packages = with pkgs; [
    grim
    slurp
    wl-clipboard
    playerctl
  ] ++ lib.optionals isNiri [ ghostty ]
    ++ lib.optionals isLabwc [ wlopm ]
    ++ (if isNiri
        then [ pkgs.nextcloud-client ]
        else lib.optional osConfig.clanarchy.desktop.labwc.nextcloud.enable pkgs.nextcloud-client);

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
