# Shared NixOS config for all Noctalia-based Wayland compositors (niri, labwc).
# Imported by both niri.nix and labwc.nix; each machine only loads one compositor
# module so this file is never double-imported within a single configuration.
{ pkgs, pkgs-unstable, inputs, ... }:
{
  imports = [../icon-theme.nix];

  # ReGreet — GTK4 greeter via cage; Stylix-themed in stylix.nix.
  # Must pass --sessions /run/current-system/sw/share/wayland-sessions;
  # never use --remember-session (panics after ZFS rollback wipes cache).
  programs.regreet.enable = true;

  # Persist regreet state so it remembers the last user/session across reboots.
  # state.toml records last_user and user_to_last_sess — without this the user
  # must manually pick their name and session after every boot (root rolls back).
  environment.persistence."/persist".directories = [ "/var/lib/regreet" ];

  # UWSM — compositor-specific waylandCompositors entry is set per compositor.
  programs.uwsm.enable = true;

  # polkit — required for UWSM privilege escalation and session management.
  security.polkit.enable = true;

  # NetworkManager
  networking.networkmanager.enable = true;

  # Pipewire audio
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # UPower — required by Noctalia battery widget
  services.upower.enable = true;

  # udisks2 — required by Noctalia USB drive manager (D-Bus device detection + auto-mount)
  services.udisks2.enable = true;

  # accounts-daemon — required by regreet ≥ 0.3.0 for user enumeration via the
  # org.freedesktop.Accounts D-Bus API.  Without it regreet panics on first start
  # ("The name is not activatable") and leaves cage showing a white screen until
  # greetd recovers (~44 s later).
  services.accounts-daemon.enable = true;

  # ── VPN.  Mullvad is gone as of 2026-09-07; IVPN runs through NetworkManager
  #
  #   The switch away from Mullvad is lgo's, on the grounds of who its
  #   leadership funds politically.  It is not a technical judgement about the
  #   client and nothing here should be read as one.
  #
  #   THERE IS DELIBERATELY NO `services.ivpn.enable` AND NO ivpn PACKAGE.
  #   nixpkgs has all three (`ivpn`, `ivpn-service`, `ivpn-ui`) and they are
  #   not used, because the daemon manages its own WireGuard interface outside
  #   NetworkManager.  That would break the one thing that was asked for: the
  #   bar indicator.
  #
  #   Noctalia shipped a vendor `mullvad` plugin and ships nothing for IVPN,
  #   so the only widget that can follow this VPN is `network-manager-vpn` —
  #   and it only sees NetworkManager connections.  Running ivpn-service
  #   alongside would additionally give two things authority over the default
  #   route, which is how a kill-switch turns into an outage nobody can
  #   diagnose.
  #
  #   SO THE TUNNEL IS AN NM WIREGUARD PROFILE.  NetworkManager has had native
  #   WireGuard support since 1.16 and `networkmanagerapplet` is already in
  #   systemPackages below for exactly this.  Import the .conf files from
  #   IVPN's account area with:
  #
  #       nmcli connection import type wireguard file ivpn-<server>.conf
  #
  #   THE TRADE, STATED SO NOBODY "FIXES" IT BACK: IVPN's own kill-switch,
  #   multihop and AntiTracker are not in this path.  What is bought is a VPN
  #   whose state the desktop can actually see, and one process in charge of
  #   routing instead of two.  If the kill-switch is ever wanted more than the
  #   indicator, the change is `services.ivpn.enable = true` here plus dropping
  #   `network-manager-vpn` in noctalia-hm.nix — do both or neither.

  # Noctalia plugin runtime dependencies — packages required by specific Noctalia
  # plugins regardless of compositor.
  environment.systemPackages = with pkgs; [
    gpu-screen-recorder   # screen-shot-and-record: GPU-accelerated screen capture
    calibre               # calibre-provider: book library search via >cb launcher
    obs-studio            # obs-control: recording/streaming control from bar
    khal                  # khal-agenda-widget: upcoming events for next 7 days
    evolution-data-server # weekly-calendar: CalendarService.qml backend (D-Bus activated)
    wlr-randr             # display-settings: live display info and configuration
    fd                    # file-search: fast file lookup via >file launcher
    networkmanagerapplet  # network-manager-vpn: nm-connection-editor for VPN profiles
    kdePackages.qtwebsockets # hassio + obs-control: Qt6 WebSocket support
  ];

  # Fonts
  fonts.packages = with pkgs; [
    nerd-fonts.monaspace
    noto-fonts
    noto-fonts-color-emoji
    inter
  ];
  fonts.fontconfig = {
    defaultFonts = {
      monospace = ["MonaspiceAr Nerd Font Mono" "Noto Sans Mono"];
      sansSerif = ["Inter" "Noto Sans"];
      serif = ["MonaspiceXe Nerd Font Propo" "Noto Serif"];
      emoji = ["Noto Color Emoji"];
    };
    hinting = {
      enable = true;
      style = "slight";
    };
    subpixel = {
      rgba = "rgb";
      lcdfilter = "default";
    };
  };

  environment.variables = {
    XCURSOR_SIZE  = "24";
    XCURSOR_THEME = "Adwaita";
    NIXOS_OZONE_WL = "1";
  };

  home-manager.extraSpecialArgs = {
    inherit inputs pkgs-unstable;
  };
}
