{ pkgs, lib, ... }:
let
  # CRX install via first_run_tabs: patched chromium reads /etc/chromium/initial_preferences;
  # --extension-mime-request-handling=always-prompt-for-install (baked in clan.nix overlay).
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
    (crxUrl "efobhjmgoddhfdhaflheioeagkcknoji")  # Vertical Tabs (nicedoc.io)
  ];
in
{
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "claude-code"
    "signal-desktop"
    "google-chrome"  # work / DRM / SSO fallback
  ];
  environment.systemPackages = with pkgs; [
    argyllcms
    displaycal
    calibre
    google-chrome   # unfree work/fallback; allowUnfreePredicate above
    librewolf
    fastfetch
    gpu-screen-recorder
    kdePackages.qtwebsockets
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

  # Flatpak + Flathub
  # XDG_DATA_DIRS must include flatpak export paths so launchers (Noctalia/Quickshell)
  # see installed apps' .desktop files. NixOS adds these via /etc/profile.d/flatpak.sh
  # (login-shell only), but UWSM imports env from PAM — sessionVariables writes to
  # /etc/environment via pam_env, which is read by all PAM sessions including greetd.
  services.flatpak.enable = true;
  environment.sessionVariables.XDG_DATA_DIRS = [
    "/var/lib/flatpak/exports/share"
    "$HOME/.local/share/flatpak/exports/share"
  ];
  systemd.services.flatpak-add-flathub = {
    description = "Add Flathub remote for Flatpak";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.flatpak}/bin/flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo";
    };
  };

  # Chromium managed policies — must be root-owned (/etc/); home.file paths
  # are silently rejected as mandatory policies even if the dir exists.
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

  # Extension first-run tabs — patched chromium reads /etc/chromium/initial_preferences
  environment.etc."chromium/initial_preferences".text =
    builtins.toJSON { first_run_tabs = chromiumFirstRunTabs; };

  # Reset ~/.config/chromium/First Run on extension list change (hash in /persist)
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
