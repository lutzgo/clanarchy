# Shared Home Manager module for labwc desktop — loaded by modules/desktop/labwc.nix
# via home-manager.sharedModules. `osConfig` exposes clanarchy.desktop.labwc options.
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
    inputs.noctalia.homeModules.default # provides programs.noctalia-shell option
  ];

  # labwc window decoration colors — patches the active openbox theme with Stylix colors.
  # themerc-override is read last so these values win over the base theme.
  xdg.configFile."labwc/themerc-override" = {
    force = true;
    text = let
      c = config.lib.stylix.colors;
    in ''
      # Active window: title bar + border pop with the accent color
      window.active.title.bg: flat solid
      window.active.title.bg.color: #${c.base01}
      window.active.label.text.color: #${c.base05}
      window.active.border.color: #${c.base0D}
      window.active.title.separator.color: #${c.base0D}

      # Active buttons (close/max/min icons)
      window.active.button.unpressed.image.color: #${c.base04}
      window.active.button.hover.bg.color: #${c.base02}
      window.active.button.hover.image.color: #${c.base05}
      window.active.button.pressed.bg.color: #${c.base02}
      window.active.button.pressed.image.color: #${c.base05}

      # Inactive window: recedes into the background
      window.inactive.title.bg: flat solid
      window.inactive.title.bg.color: #${c.base00}
      window.inactive.label.text.color: #${c.base03}
      window.inactive.border.color: #${c.base02}

      # Inactive buttons
      window.inactive.button.unpressed.image.color: #${c.base02}

      # Resize handle strip at window bottom
      window.active.handle.bg: flat solid
      window.active.handle.bg.color: #${c.base01}
      window.inactive.handle.bg: flat solid
      window.inactive.handle.bg.color: #${c.base00}

      # Geometry
      border.width: 1
      padding.height: 4
      padding.width: 6
      window.label.text.justify: center
    '';
  };

  # labwc compositor config — written to ~/.config/labwc/rc.xml
  # Keybindings use single-letter modifier prefixes: W=Super, S=Shift, C=Ctrl, A=Alt
  xdg.configFile."labwc/rc.xml" = {
    force = true;
    text = ''
      <?xml version="1.0"?>
      <labwc_config>
        <core gap="4" reuseOutputMode="yes" />
        <theme cornerRadius="8" />

        <libinput>
          <device category="touch">
            <tap>yes</tap>
            <tapButtonMap>lrm</tapButtonMap>
            <naturalScroll>yes</naturalScroll>
            <disableWhileTyping>yes</disableWhileTyping>
            <pointerSpeed>${toString osConfig.clanarchy.desktop.labwc.input.pointerSpeed}</pointerSpeed>
          </device>
          <device category="pointer">
            <pointerSpeed>${toString osConfig.clanarchy.desktop.labwc.input.pointerSpeed}</pointerSpeed>
          </device>
        </libinput>

        <keyboard>
          <default />
          <!-- Launch terminal -->
          <keybind key="W-Return">
            <action name="Execute"><command>uwsm app -- foot</command></action>
          </keybind>
          <!-- App launcher (Noctalia) -->
          <keybind key="W-space">
            <action name="Execute"><command>noctalia-shell ipc call launcher toggle</command></action>
          </keybind>
          <!-- Clipboard (Noctalia clipper) -->
          <keybind key="W-c">
            <action name="Execute"><command>noctalia-shell ipc call plugin:clipper toggle</command></action>
          </keybind>
          <!-- File manager (yazi in foot) -->
          <keybind key="W-e">
            <action name="Execute"><command>uwsm app -- foot -e yazi</command></action>
          </keybind>
          <!-- KeePassXC -->
          <keybind key="W-p">
            <action name="Execute"><command>uwsm app -- keepassxc</command></action>
          </keybind>
          <!-- Close window -->
          <keybind key="W-q">
            <action name="Close" />
          </keybind>
          <!-- Maximize -->
          <keybind key="W-m">
            <action name="ToggleMaximize" />
          </keybind>
          <!-- Fullscreen -->
          <keybind key="W-F11">
            <action name="ToggleFullscreen" />
          </keybind>
          <!-- Focus floating / tiling toggle (labwc is stacking; float is implicit) -->
          <!-- Session menu via Noctalia -->
          <keybind key="W-S-e">
            <action name="Execute"><command>noctalia-shell ipc call sessionMenu toggle</command></action>
          </keybind>
          <!-- Focus next/prev window -->
          <keybind key="A-Tab">
            <action name="NextWindow" />
          </keybind>
          <keybind key="A-S-Tab">
            <action name="PreviousWindow" />
          </keybind>
          <!-- Virtual desktops 1-4 -->
          <keybind key="W-1">
            <action name="GoToDesktop"><to>1</to></action>
          </keybind>
          <keybind key="W-2">
            <action name="GoToDesktop"><to>2</to></action>
          </keybind>
          <keybind key="W-3">
            <action name="GoToDesktop"><to>3</to></action>
          </keybind>
          <keybind key="W-4">
            <action name="GoToDesktop"><to>4</to></action>
          </keybind>
          <!-- Move window to desktop -->
          <keybind key="W-S-1">
            <action name="SendToDesktop"><to>1</to><follow>no</follow></action>
          </keybind>
          <keybind key="W-S-2">
            <action name="SendToDesktop"><to>2</to><follow>no</follow></action>
          </keybind>
          <keybind key="W-S-3">
            <action name="SendToDesktop"><to>3</to><follow>no</follow></action>
          </keybind>
          <keybind key="W-S-4">
            <action name="SendToDesktop"><to>4</to><follow>no</follow></action>
          </keybind>
          <!-- Snap window to screen halves -->
          <keybind key="W-Left">
            <action name="SnapToEdge"><direction>left</direction></action>
          </keybind>
          <keybind key="W-Right">
            <action name="SnapToEdge"><direction>right</direction></action>
          </keybind>
          <keybind key="W-Up">
            <action name="SnapToEdge"><direction>up</direction></action>
          </keybind>
          <keybind key="W-Down">
            <action name="SnapToEdge"><direction>down</direction></action>
          </keybind>
          <!-- Media keys → Noctalia IPC -->
          <keybind key="XF86AudioRaiseVolume">
            <action name="Execute"><command>noctalia-shell ipc call volume increase</command></action>
          </keybind>
          <keybind key="XF86AudioLowerVolume">
            <action name="Execute"><command>noctalia-shell ipc call volume decrease</command></action>
          </keybind>
          <keybind key="XF86AudioMute">
            <action name="Execute"><command>noctalia-shell ipc call volume muteOutput</command></action>
          </keybind>
          <keybind key="XF86AudioPlay">
            <action name="Execute"><command>noctalia-shell ipc call media playPause</command></action>
          </keybind>
          <keybind key="XF86AudioNext">
            <action name="Execute"><command>noctalia-shell ipc call media next</command></action>
          </keybind>
          <keybind key="XF86AudioPrev">
            <action name="Execute"><command>noctalia-shell ipc call media previous</command></action>
          </keybind>
          <!-- Brightness → Noctalia IPC -->
          <keybind key="XF86MonBrightnessUp">
            <action name="Execute"><command>noctalia-shell ipc call brightness increase</command></action>
          </keybind>
          <keybind key="XF86MonBrightnessDown">
            <action name="Execute"><command>noctalia-shell ipc call brightness decrease</command></action>
          </keybind>
          <!-- Screenshots → Noctalia plugin -->
          <keybind key="Print">
            <action name="Execute"><command>noctalia-shell ipc call plugin:screenshot takeScreenshot region</command></action>
          </keybind>
          <keybind key="W-Print">
            <action name="Execute"><command>noctalia-shell ipc call plugin:screenshot takeScreenshot screen</command></action>
          </keybind>
        </keyboard>

        <desktops>
          <popupTime>0</popupTime>
          <desktop name="1" />
          <desktop name="2" />
          <desktop name="3" />
          <desktop name="4" />
        </desktops>

        <windowRules>
          <!-- Foot floating scratchpad -->
          <windowRule identifier="foot" title="scratch">
            <action name="SetDecorations"><decorations>none</decorations></action>
          </windowRule>
          <!-- KeePassXC: open maximized -->
          <windowRule identifier="org.keepassxc.KeePassXC" matchType="identifier">
          </windowRule>
        </windowRules>
      </labwc_config>
    '';
  };

  # labwc autostart — executed by labwc on compositor start.
  # Use `uwsm app --` so each process is tracked as a systemd user unit.
  xdg.configFile."labwc/autostart" = {
    force = true;
    text = ''
      uwsm app -- noctalia-shell &
      uwsm app -- keepassxc -- keepassxc --minimized &
    '';
    executable = true;
  };

  # Display configuration via kanshi — labwc delegates output management to wlroots clients.
  services.kanshi = {
    enable = true;
    settings = [
      {
        profile.name = "builtin";
        profile.outputs = [
          {
            criteria = "eDP-1";
            status = "enable";
            scale = osConfig.clanarchy.desktop.labwc.display.scale;
          }
        ];
      }
    ];
  };

  # Noctalia shell — configured declaratively via noctalia HM module.
  # Launched via autostart with UWSM so it runs as a tracked systemd unit.
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
        avatarImage = "/home/sabine/.face";
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
        showChangelogOnStartup = false;
        telemetryEnabled = false;
        enableLockScreenCountdown = true;
        lockScreenCountdownDuration = 10000;
        autoStartAuth = true;
        allowPasswordWithFprintd = false;
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
          {
            enabled = true;
            id = "calendar-header-card";
          }
          {
            enabled = true;
            id = "calendar-month-card";
          }
          {
            enabled = true;
            id = "weather-card";
          }
        ];
      };

      wallpaper = {
        enabled = true;
        overviewEnabled = false;
        directory = "/home/sabine/Pictures/Wallpapers";
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
        screenshotAnnotationTool = "";
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
          {
            enabled = true;
            id = "profile-card";
          }
          {
            enabled = true;
            id = "shortcuts-card";
          }
          {
            enabled = true;
            id = "audio-card";
          }
          {
            enabled = true;
            id = "brightness-card";
          }
          {
            enabled = true;
            id = "weather-card";
          }
          {
            enabled = true;
            id = "media-sysmon-card";
          }
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
          {
            action = "lock";
            command = "";
            countdownEnabled = true;
            enabled = true;
            keybind = "1";
          }
          {
            action = "suspend";
            command = "";
            countdownEnabled = true;
            enabled = true;
            keybind = "2";
          }
          {
            action = "hibernate";
            command = "";
            countdownEnabled = true;
            enabled = true;
            keybind = "3";
          }
          {
            action = "reboot";
            command = "";
            countdownEnabled = true;
            enabled = true;
            keybind = "4";
          }
          {
            action = "logout";
            command = "";
            countdownEnabled = true;
            enabled = true;
            keybind = "5";
          }
          {
            action = "shutdown";
            command = "";
            countdownEnabled = true;
            enabled = true;
            keybind = "6";
          }
          {
            action = "rebootToUefi";
            command = "";
            countdownEnabled = true;
            enabled = false;
            keybind = "";
          }
          {
            action = "userspaceReboot";
            command = "";
            countdownEnabled = true;
            enabled = false;
            keybind = "";
          }
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
          Text = {
            bg = "mOutline";
            separator = "mSurface";
            fg = "mOnSurface";
          };
          Image = {
            bg = "mTertiary";
            separator = "mSurface";
            fg = "mOnTertiary";
          };
          Link = {
            bg = "mPrimary";
            separator = "mSurface";
            fg = "mOnPrimary";
          };
          Code = {
            bg = "mSecondary";
            separator = "mSurface";
            fg = "mOnSecondary";
          };
          Color = {
            bg = "mSecondary";
            separator = "mSurface";
            fg = "mOnSecondary";
          };
          Emoji = {
            bg = "mHover";
            separator = "mSurface";
            fg = "mOnHover";
          };
          File = {
            bg = "mError";
            separator = "mSurface";
            fg = "mOnError";
          };
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
        detectedCompositor = "labwc";
        labwcConfigPath = "~/.config/labwc/rc.xml";
        niriConfigPath = "~/.config/niri/config.kdl";
        hyprlandConfigPath = "~/.config/hypr/hyprland.conf";
        modKeyVariable = "$mod";
        windowHeight = 850;
        windowWidth = 1400;
      };

      usb-drive-manager = {
        autoMount = false;
        fileBrowser = "yazi";
        terminalCommand = "foot";
        showNotifications = true;
        hideWhenEmpty = true;
        showBadge = true;
      };
    };
  };

  # Lock Noctalia before the system enters sleep.
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

  # Stylix targets
  stylix.targets.noctalia-shell.enable = true;
  stylix.targets.kde.enable = false;

  # Noctalia uses Stylix colors directly (Catppuccin Mocha on biene) —
  # no forced color overrides here unlike the miralda/Gruvbox setup.
  xdg.configFile."noctalia/colors.json".force = true;
  xdg.configFile."noctalia/settings.json".force = true;
  xdg.configFile."noctalia/plugins/clipper/settings.json".force = true;
  xdg.configFile."noctalia/plugins/screen-recorder/settings.json".force = true;
  xdg.configFile."noctalia/plugins/assistant-panel/settings.json".force = true;
  xdg.configFile."noctalia/plugins/keybind-cheatsheet/settings.json".force = true;
  xdg.configFile."noctalia/plugins/usb-drive-manager/settings.json".force = true;

  gtk.gtk4.theme = null;

  gtk.iconTheme = {
    name = osConfig.clanarchy.iconTheme.name;
    package = osConfig.clanarchy.iconTheme.package;
  };

  # Foot terminal
  programs.foot = {
    enable = true;
    settings = {
      main = {
        term = "xterm-256color";
        pad = "8x8";
        resize-delay-ms = 100;
        dpi-aware = "no";
      };
      bell = {
        urgent = false;
        notify = false;
        visual = false;
      };
      scrollback = {
        lines = 10000;
        multiplier = 3.0;
      };
      url = {
        launch = "xdg-open \${url}";
        label-letters = "sadfjklewcmpgh";
        osc8-underline = "url-mode";
      };
      cursor = {
        style = "block";
        blink = false;
      };
      mouse = {
        hide-when-typing = true;
        alternate-scroll-mode = "yes";
      };
      key-bindings = {
        clipboard-copy = "Control+Shift+c XF86Copy";
        clipboard-paste = "Control+Shift+v XF86Paste";
        font-increase = "Control+plus Control+equal Control+KP_Add";
        font-decrease = "Control+minus Control+KP_Subtract";
        font-reset = "Control+0 Control+KP_0";
        scrollback-up-page = "Shift+Page_Up";
        scrollback-down-page = "Shift+Page_Down";
        search-start = "Control+Shift+r";
        show-urls-launch = "Control+Shift+o";
      };
    };
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
        format = "[](bold fg:yellow)[󰪢 $duration](bold bg:yellow fg:black)[](bold fg:yellow)";
      };

      directory = {
        truncation_length = 6;
        truncation_symbol = "••/";
        home_symbol = "  ";
        read_only = " 󰌾";
        style = "fg:black bg:green";
        format = "[](bold fg:green)[󰉋 $path]($style)[](bold fg:green)";
      };

      git_branch = {
        symbol = "󰘬";
        format = "󰜥 [](bold fg:cyan)[$symbol $branch(:$remote_branch)](fg:black bg:cyan)[ ](bold fg:cyan)";
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
        format = "[•$hostname](bg:cyan bold fg:black)[](bold fg:cyan)";
        trim_at = ".local";
        disabled = false;
      };

      username = {
        style_user = "bold bg:cyan fg:black";
        style_root = "red bold";
        format = "[](bold fg:cyan)[$user]($style)";
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

  systemd.user.sessionVariables.NOCTALIA_PAM_SERVICE = "noctalia";

  # Idle management: lock after 5 min, monitors off after 5.5 min.
  # wlopm turns outputs off/on via wlr-output-power-management protocol (labwc/wlroots).
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
      {
        timeout = 330;
        command = "${pkgs.wlopm}/bin/wlopm --off '*'";
        resumeCommand = "${pkgs.wlopm}/bin/wlopm --on '*'";
      }
    ];
  };

  home.packages = with pkgs; [
    grim
    slurp
    wl-clipboard
    playerctl
    nextcloud-client
    wlopm
  ];

  systemd.user.services.nextcloud-client = {
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
