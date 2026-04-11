{ pkgs, lib, ... }:
let
  # ── Chromium extension installation via initial_preferences ───────────
  # The NixOS chromium package patches the binary to read
  # /etc/chromium/initial_preferences (see chromium-initial-prefs.patch).
  # first_run_tabs opens CRX URLs on first launch (when First Run is absent).
  # With --extension-mime-request-handling=always-prompt-for-install (baked
  # in via clan.nix overlay) each CRX URL shows an install prompt.
  crxUrl = id:
    "https://clients2.google.com/service/update2/crx"
    + "?response=redirect&acceptformat=crx2,crx3"
    + "&prodversion=${pkgs.ungoogled-chromium.version}"
    + "&x=id%3D${id}%26uc";

  chromiumFirstRunTabs = [
    "https://github.com/NeverDecaf/chromium-web-store/releases/latest/download/Chromium.Web.Store.crx"
    (crxUrl "cjpalhdlnbpafiamejdnhcphjbkeiagm")  # uBlock Origin
    (crxUrl "oboonakemofpalcgghocfoadofidjkkk")  # KeePassXC-Browser
    (crxUrl "dbepggeogbaibhgnhhndojpepiihcmeb")  # Vimium
  ];
in
{
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "anytype"
    "anytype-heart"
    "claude-code"
    "signal-desktop"
    "google-chrome"  # work / DRM / SSO fallback (see home-modules/browsers.nix)
  ];
  environment.systemPackages = with pkgs; [
    #anytype
    argyllcms
    displaycal
    calibre
    # chromium: removed — managed by programs.chromium (ungoogled-chromium) in home-modules/browsers.nix
    google-chrome   # unfree work/fallback; allowUnfreePredicate above
    librewolf
    fastfetch
    gpu-screen-recorder
    kdePackages.qtwebsockets
    # firefox: removed — managed by programs.firefox in home-modules/browsers.nix
    signal-desktop
    keepassxc
    valent          # KDE Connect protocol — replaces kdePackages.kdeconnect-kde (lighter deps)
    helix
    fzf
    zellij
    yazi
    lazygit
    foot
    libreoffice
    gimp
    darktable
    krita
    normcap         # OCR screen capture
    obs-studio
    bat             # cat with syntax highlighting and paging
    ripgrep
    fd
    xdg-utils
    wtype           # Wayland keyboard input injection (xdotool equivalent)
    claude-code
  ];

  # Color Calibration
  services.colord.enable = true;

  # Valent / KDE Connect protocol — ports 1714-1764 TCP+UDP
  networking.firewall = {
    allowedTCPPortRanges = [{ from = 1714; to = 1764; }];
    allowedUDPPortRanges = [{ from = 1714; to = 1764; }];
  };

  # Podman
  virtualisation.containers.enable = true;
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  # Flatpak
  services.flatpak.enable = true;

  # ── Chromium managed policies (system-level, root-owned) ──────────────
  #
  # Chromium silently rejects mandatory policy files that are user-owned.
  # System-level policies at /etc/chromium/policies/managed/ (owned by root
  # via environment.etc) are the only reliable way to apply managed policies
  # on Linux.  home.file entries at ~/.config/chromium/policies/managed/ do
  # not work as mandatory policies even though Chromium creates the directory.
  environment.etc."chromium/policies/managed/privacy.json".text =
    builtins.toJSON {

      # ── Telemetry and account features ──────────────────────────
      MetricsReportingEnabled                  = false;
      SafeBrowsingEnabled                      = false; # deprecated in 130+
      SafeBrowsingProtectionLevel              = 0;     # 0 = disabled
      PasswordManagerEnabled                   = false;
      AutofillAddressEnabled                   = false;
      AutofillCreditCardEnabled                = false;
      UserFeedbackAllowed                      = false;
      UrlKeyedAnonymizedDataCollectionEnabled  = false;

      # ── Privacy Sandbox ──────────────────────────────────────────
      PrivacySandboxAdMeasurementEnabled       = false;
      PrivacySandboxAdTopicsEnabled            = false;
      PrivacySandboxSiteEnabledAdsEnabled      = false;

      # ── Cookies ──────────────────────────────────────────────────
      BlockThirdPartyCookies                   = true;  # deprecated 130+, harmless
      DefaultCookiesSetting                    = 1;     # 1 = allow first-party

      # ── Network leaks ────────────────────────────────────────────
      WebRtcIPHandlingPolicy                   = "disable_non_proxied_udp";
      NetworkPredictionOptions                 = 2; # 2 = disabled
      SearchSuggestEnabled                     = false;

      # ── Encrypted DNS (secure mode) ──────────────────────────────
      DnsOverHttpsMode                         = "secure";
      DnsOverHttpsTemplates                    = "https://dns.quad9.net/dns-query";

      # ── Permission defaults (2 = block) ─────────────────────────
      DefaultGeolocationSetting                = 2;
      DefaultNotificationsSetting              = 2;
      DefaultCameraSetting                     = 2;
      DefaultMicrophoneSetting                 = 2;
      DefaultPopupsSetting                     = 2;
      DefaultSensorsSetting                    = 2;
      DefaultSerialSetting                     = 2;
      DefaultHidSetting                        = 2;
      DefaultBluetoothSetting                  = 2;
      DefaultFileSystemReadGuardSetting        = 2;
      DefaultFileSystemWriteGuardSetting       = 2;

      # ── JavaScript JIT ───────────────────────────────────────────
      DefaultJavaScriptJitSetting              = 2;  # 2 = block globally
      JavaScriptJitAllowedForSites             = [
        # Add URL patterns for sites that need JIT, e.g.:
        # "https://[*.]figma.com"
      ];

      # ── Search engines ───────────────────────────────────────────
      DefaultSearchProviderEnabled             = true;
      DefaultSearchProviderName                = "DuckDuckGo";
      DefaultSearchProviderSearchURL           = "https://duckduckgo.com/?q={searchTerms}";
      DefaultSearchProviderSuggestURL          = "https://duckduckgo.com/ac/?q={searchTerms}&type=list";
      # ManagedSearchEngines: Chrome 116+.  nixpkgs 25.11 = Chromium 131+.
      ManagedSearchEngines = [
        {
          name    = "Startpage";
          keyword = "sp";
          url     = "https://www.startpage.com/search?q={searchTerms}";
        }
      ];
    };

  # ── Chromium initial_preferences (extension first-run tabs) ───────────
  # Patched chromium reads this from /etc/chromium/initial_preferences.
  environment.etc."chromium/initial_preferences".text =
    builtins.toJSON { first_run_tabs = chromiumFirstRunTabs; };

  # ── Reset First Run when extension list changes ────────────────────────
  # Runs at boot; deletes ~/.config/chromium/First Run for all users when
  # chromiumFirstRunTabs changes (hash mismatch), so install tabs re-open
  # on the next Chromium launch.  Hash stored in /persist (survives ZFS
  # rollback; .config/chromium is also persisted so First Run survives).
  systemd.services.chromiumFirstRun = {
    description = "Reset Chromium first-run sentinel on extension config change";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "local-fs.target" ];
    serviceConfig.Type = "oneshot";
    script =
      let hash = builtins.hashString "sha256" (builtins.toJSON chromiumFirstRunTabs);
      in ''
        HASH_FILE="/persist/chromium-config.hash"
        EXPECTED="${hash}"
        if [ ! -f "$HASH_FILE" ] || [ "$(cat "$HASH_FILE" 2>/dev/null)" != "$EXPECTED" ]; then
          for d in /home/*; do
            rm -f "$d/.config/chromium/First Run"
          done
          echo "$EXPECTED" > "$HASH_FILE"
        fi
      '';
  };
}
