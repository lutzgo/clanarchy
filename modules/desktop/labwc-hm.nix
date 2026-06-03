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
  imports = [./noctalia-hm.nix];

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
    '' + lib.optionalString osConfig.clanarchy.desktop.labwc.keepassxc.enable ''
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
}
