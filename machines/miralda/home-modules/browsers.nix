# ============================================================
# BROWSER STACK — machines/miralda/home-modules/browsers.nix
# ============================================================
#
# Four browsers with defined roles:
#   1. ungoogled-chromium  — daily Chromium driver, privacy-hardened
#   2. librewolf           — daily Gecko driver, fingerprint resistance
#   3. firefox + arkenfox  — hardened Mozilla-compatible fallback
#   4. google-chrome       — work / DRM / SSO (unfree, minimal config)
#
# CHANGES REQUIRED IN apps.nix (alongside importing this module):
#   REMOVE "chromium"  — now managed by programs.chromium below
#   REMOVE "firefox"   — now managed by programs.firefox below
#   KEEP   "librewolf" — no home-manager module exists for LibreWolf
#   KEEP   "keepassxc" — system package; do not duplicate here
#
# ============================================================
{ pkgs, lib, ... }:

let
  # ── KeePassXC native messaging manifest helpers ──────────────────────
  #
  # NixOS-specific reason for home.file (not GUI toggle):
  #   KeePassXC's "Connect browser extension" toggle writes a native
  #   messaging manifest with the runtime binary path.  On NixOS,
  #   keepassxc-proxy lives in the Nix store at a hash-prefixed path
  #   that changes on every package update.  home.file pins the manifest
  #   to the correct ${pkgs.keepassxc} store path at build time and
  #   re-links it on activation, so the extension never loses its host.

  # Chrome / Chromium: allowed_origins with chrome-extension:// scheme
  keepassxcChromeManifest = allowed_origins: builtins.toJSON {
    name             = "org.keepassxc.keepassxc_browser";
    description      = "KeePassXC integration with native messaging";
    path             = "${pkgs.keepassxc}/bin/keepassxc-proxy";
    type             = "stdio";
    inherit allowed_origins;
  };

  # Firefox / LibreWolf: allowed_extensions with AMO extension ID.
  # Note: the spec lists "allowed_origins: chrome-extension://..."
  # for LibreWolf — that is the Chrome manifest format.  Firefox-based
  # browsers require "allowed_extensions" with the WebExtension ID
  # (as declared in the extension's manifest.json).
  keepassxcFirefoxManifest = builtins.toJSON {
    name               = "org.keepassxc.keepassxc_browser";
    description        = "KeePassXC integration with native messaging";
    path               = "${pkgs.keepassxc}/bin/keepassxc-proxy";
    type               = "stdio";
    allowed_extensions = [ "keepassxc-browser@keepassxc.org" ];
  };

in
{
  # ── Unfree allowance scoped to google-chrome ─────────────────────────
  #
  # home-manager.useGlobalPkgs is not set in this config, so home-manager
  # evaluates its own pkgs instance.  This predicate configures that HM-
  # internal pkgs so that pkgs.google-chrome (below) is buildable.
  # If useGlobalPkgs were ever set to true, move "google-chrome" into the
  # allowUnfreePredicate in apps.nix instead (NixOS-level).
  nixpkgs.config.allowUnfreePredicate = pkg:
    lib.getName pkg == "google-chrome";


  # ============================================================
  # BROWSER 1 — ungoogled-chromium (daily Chromium driver)
  # ============================================================

  programs.chromium = {
    enable  = true;
    # Replace standard pkgs.chromium (remove it from apps.nix).
    # ungoogled-chromium ships with Google API keys removed and a
    # Chromium-Web-Store patch that restores the extension install UI.
    package = pkgs.ungoogled-chromium;

    # ── Extensions ────────────────────────────────────────────────────
    #
    # Strategy: programs.chromium.extensions generates an
    # ExtensionInstallForcelist managed policy.  Each entry needs an
    # updateUrl; omitting it falls back to Google's CWS update server
    # (https://clients2.google.com/service/update2/crx), which
    # ungoogled-chromium can still reach.
    #
    # chromium-web-store is listed first; it bootstraps the Store UI so
    # that additional extensions can also be installed manually without
    # touching this file.
    #
    # IDs marked ⚠ were supplied in the spec and match the expected
    # Chrome Web Store format but could not be confirmed via a live Store
    # lookup at generation time.  If an extension fails to auto-install,
    # open the (bootstrapped) Web Store UI and search by name to find the
    # correct ID, then update this file.
    extensions = [
      # chromium-web-store — bootstraps the Web Store UI in ungoogled-chromium
      # Verified: github.com/NeverDecaf/chromium-web-store releases
      {
        id        = "cinhimbnkkaeohfgghhklpknlkffjgod";
        updateUrl = "https://github.com/NeverDecaf/chromium-web-store/releases/latest/download/update.xml";
      }

      # uBlock Origin — verified CWS: cjpalhdlnbpafiamejdnhcphjbkeiagm
      { id = "cjpalhdlnbpafiamejdnhcphjbkeiagm"; }

      # KeePassXC-Browser — verified CWS: oboonakemofpalcgghocfoadofidjkkk
      { id = "oboonakemofpalcgghocfoadofidjkkk"; }

      # Vimium — verified CWS: dbepggeogbaibhgnhhndojpepiihcmeb
      { id = "dbepggeogbaibhgnhhndojpepiihcmeb"; }

      # SideTab Pro (vertical tabs)
      # ⚠ ID fehfojhhnbfbclgpffmffigfgngbpnmj — spec-provided; could not
      #   be independently confirmed against the live Web Store.  If this
      #   fails to install, search the Store for "SideTab Pro" or consider
      #   "Sidewise Tree Style Tabs" (verified extension) as an alternative.
      { id = "fehfojhhnbfbclgpffmffigfgngbpnmj"; }

      # Linkwarden bookmark manager
      # ⚠ ID pnidmkljnhbjfffciajlenmpaoemnjlo — spec-provided; could not
      #   be confirmed against the live Web Store.  Verify by searching
      #   chromewebstore.google.com for "Linkwarden" before first use.
      { id = "pnidmkljnhbjfffciajlenmpaoemnjlo"; }
    ];

    # ── commandLineArgs (ungoogled-chromium specific) ──────────────────
    #
    # Both flags are present in the ungoogled-chromium patch set and in
    # the Bromite flags.md from which it descends.  Unknown flags are
    # silently ignored by Chromium, so these are safe to leave even if
    # a future build drops them.
    commandLineArgs = [
      "--no-pings"                         # disable hyperlink auditing (ping= attr)
      "--disable-search-engine-collection" # prevent automatic search engine detection
    ];

    # ── extraOpts (Chrome Enterprise managed policy) ───────────────────
    extraOpts = {

      # ── Telemetry and account features ──────────────────────────
      MetricsReportingEnabled                     = false;
      # SafeBrowsingEnabled is deprecated in Chrome 130+ in favour of
      # SafeBrowsingProtectionLevel.  Both are included for compatibility.
      SafeBrowsingEnabled                         = false;
      SafeBrowsingProtectionLevel                 = 0; # 0 = disabled
      PasswordManagerEnabled                      = false;
      AutofillAddressEnabled                      = false;
      AutofillCreditCardEnabled                   = false;
      UserFeedbackAllowed                         = false;
      UrlKeyedAnonymizedDataCollectionEnabled      = false;

      # ── Privacy Sandbox — disable all ad-targeting APIs ─────────
      PrivacySandboxAdMeasurementEnabled          = false;
      PrivacySandboxAdTopicsEnabled               = false;
      PrivacySandboxSiteEnabledAdsEnabled         = false;

      # ── Cookies and tracking ─────────────────────────────────────
      # BlockThirdPartyCookies was deprecated in Chrome 130 (3PC blocking
      # is now the default).  Kept here for explicitness; harmless on
      # newer versions.
      BlockThirdPartyCookies                      = true;
      DefaultCookiesSetting                       = 1; # 1 = allow first-party

      # ── Network leak prevention ──────────────────────────────────
      WebRtcIPHandlingPolicy                      = "disable_non_proxied_udp";
      NetworkPredictionOptions                    = 2; # 2 = disabled
      SearchSuggestEnabled                        = false;

      # ── Encrypted DNS (DoH — locked to secure mode) ─────────────
      DnsOverHttpsMode                            = "secure";
      DnsOverHttpsTemplates                       = "https://dns.quad9.net/dns-query";

      # ── Permission defaults (2 = block) ─────────────────────────
      DefaultGeolocationSetting                   = 2;
      DefaultNotificationsSetting                 = 2;
      DefaultCameraSetting                        = 2;
      DefaultMicrophoneSetting                    = 2;
      DefaultPopupsSetting                        = 2;
      DefaultSensorsSetting                       = 2;
      DefaultSerialSetting                        = 2;
      DefaultHidSetting                           = 2;
      DefaultBluetoothSetting                     = 2;
      DefaultFileSystemReadGuardSetting           = 2;
      DefaultFileSystemWriteGuardSetting          = 2;

      # ── JavaScript JIT ───────────────────────────────────────────
      # Correct policy name is DefaultJavaScriptJitSetting (the spec
      # listed "JavaScriptJit" which is not a valid Chrome policy key).
      # Value 2 = block JIT globally; sites can be re-enabled via
      # JavaScriptJitAllowedForSites without a browser restart, which
      # is the advantage of the policy approach over a command-line flag.
      DefaultJavaScriptJitSetting                 = 2;
      JavaScriptJitAllowedForSites                = [
        # Add patterns for sites that require JIT, e.g.:
        # "https://[*.]figma.com"
        # "https://[*.]google.com"
      ];

      # ── Search engines ───────────────────────────────────────────
      DefaultSearchProviderEnabled                = true;
      DefaultSearchProviderName                   = "DuckDuckGo";
      DefaultSearchProviderSearchURL              = "https://duckduckgo.com/?q={searchTerms}";
      DefaultSearchProviderSuggestURL             = "https://duckduckgo.com/ac/?q={searchTerms}&type=list";

      # ManagedSearchEngines: available in Chrome 116+.
      # nixpkgs 25.11 ships Chromium 131+, so this key should be valid.
      # If it causes a policy error, comment it out and add Startpage
      # manually via chrome://settings/searchEngines.
      ManagedSearchEngines = [
        {
          name    = "Startpage";
          keyword = "sp";
          url     = "https://www.startpage.com/search?q={searchTerms}";
        }
      ];
    };
  };

  # ── KeePassXC native messaging host for Chromium ──────────────────────
  home.file.".config/chromium/NativeMessagingHosts/org.keepassxc.keepassxc_browser.json".text =
    keepassxcChromeManifest [ "chrome-extension://oboonakemofpalcgghocfoadofidjkkk/" ];

  # ── Vimium: Linkwarden keyboard shortcut ──────────────────────────────
  #
  # Vimium settings cannot be managed declaratively via Chromium policy.
  # After first launch, open the Vimium options page and add the following
  # to the "Custom key mappings" field:
  #
  #   map <a-b> createTab https://YOUR_LINKWARDEN_INSTANCE/links
  #
  # Replace YOUR_LINKWARDEN_INSTANCE with your Linkwarden server URL.


  # ============================================================
  # BROWSER 2 — LibreWolf (daily Gecko driver)
  # ============================================================
  #
  # LibreWolf is installed as a system package in apps.nix.
  # No home-manager programs.* module exists for LibreWolf.
  # Configuration is managed entirely via home.file.
  #
  # ── S-3: DNS-level blocking note ────────────────────────────────────
  # LibreWolf hard-codes three Mozilla domains in its binary that cannot
  # be fully suppressed via prefs.  These domains serve Remote Settings
  # (filter-list metadata, not telemetry), but still make outbound
  # connections on startup.  Block them in your DNS resolver or add them
  # to networking.hosts in configuration.nix if zero idle connections
  # are required:
  #
  #   firefox.settings.services.mozilla.com
  #   firefox-settings-attachments.cdn.mozilla.net
  #   content-signature-2.cdn.mozilla.net

  # ── LibreWolf user prefs override ─────────────────────────────────────
  home.file.".librewolf/librewolf.overrides.cfg".text = ''
    // librewolf.overrides.cfg
    // Evaluated after LibreWolf's built-in defaults.  Uses Firefox pref syntax.

    // ── Mozilla push WebSocket ──────────────────────────────────────────
    // The push WebSocket resolves to Google Cloud infrastructure
    // (observable via Wireshark / ngrep on port 443 to push.services.mozilla.com).
    // Disabling it also disables Web Push notifications — re-enable per-origin
    // via the site permissions panel if a site requires it.
    user_pref("dom.push.connection.enabled", false);
    user_pref("dom.push.enabled", false);

    // ── uBlock Origin filter list updates ──────────────────────────────
    // Intentionally NOT disabled.  These are legitimate functional
    // connections (filter list downloads), not telemetry.

    // ── Additional telemetry hardening ─────────────────────────────────
    user_pref("toolkit.telemetry.enabled", false);
    user_pref("toolkit.telemetry.unified", false);
    user_pref("datareporting.healthreport.uploadEnabled", false);
    user_pref("datareporting.policy.dataSubmissionEnabled", false);
    user_pref("app.shield.optoutstudies.enabled", false);
    user_pref("app.normandy.enabled", false);
    user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
    user_pref("browser.newtabpage.activity-stream.telemetry", false);
    user_pref("browser.ping-centre.telemetry", false);
    user_pref("breakpad.reportURL", "");
  '';

  # ── KeePassXC native messaging host for LibreWolf ─────────────────────
  home.file.".librewolf/native-messaging-hosts/org.keepassxc.keepassxc_browser.json".text =
    keepassxcFirefoxManifest;

  # ── Manual extension install — LibreWolf ──────────────────────────────
  #
  # LibreWolf has no declarative extension installation mechanism.
  # Install on first launch from the AMO (addons.mozilla.org):
  #
  #   uBlock Origin      https://addons.mozilla.org/firefox/addon/ublock-origin/
  #   Vimium-FF          https://addons.mozilla.org/firefox/addon/vimium-ff/
  #   KeePassXC-Browser  https://addons.mozilla.org/firefox/addon/keepassxc-browser/
  #   Linkwarden         https://addons.mozilla.org/firefox/addon/linkwarden/
  #                      (verify this AMO listing exists — the extension may be
  #                       Chrome-only; check the Linkwarden project repository)
  #
  # uBlock Origin medium mode setup (after first launch):
  #   uBO dashboard → My rules → add:
  #     * * 3p-script block
  #     * * 3p-frame block
  #   Whitelist sites as needed.  Expect ~1 week of settling.


  # ============================================================
  # BROWSER 3 — Firefox + arkenfox (hardened Mozilla-compatible)
  # ============================================================

  programs.firefox = {
    enable = true;

    profiles.hardened = {

      # ── arkenfox-derived settings ──────────────────────────────────
      #
      # Translated from https://github.com/arkenfox/user.js (master).
      # Key sections only — consult arkenfox for the full reference.
      # home-manager merges these into the profile's user.js at build time.
      #
      # ⚠ Conflict resolved: privacy.firstparty.isolate = true breaks
      #   KeePassXC-Browser cross-origin autofill.  Replaced below by
      #   network.cookie.cookieBehavior = 5 (Total Cookie Protection /
      #   dFPI), which provides equivalent cross-site isolation and is
      #   compatible with browser extensions.
      settings = {

        # ── Startup and new tab ────────────────────────────────────
        "browser.startup.page"                                        = 0;
        "browser.startup.homepage"                                    = "about:blank";
        "browser.newtabpage.enabled"                                  = false;
        "browser.newtabpage.activity-stream.feeds.telemetry"          = false;
        "browser.newtabpage.activity-stream.telemetry"                = false;
        "browser.newtabpage.activity-stream.feeds.snippets"           = false;
        "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
        "browser.newtabpage.activity-stream.feeds.discoverystreamfeed" = false;
        "browser.newtabpage.activity-stream.showSponsored"            = false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites"    = false;
        "browser.newtabpage.activity-stream.default.sites"            = "";

        # ── Geolocation ────────────────────────────────────────────
        "geo.enabled"                    = false;
        "geo.provider.use_corelocation"  = false;
        "geo.provider.use_gpsd"          = false;
        "geo.provider.use_geoclue"       = false;

        # ── WebRTC IP leak prevention ──────────────────────────────
        # media.peerconnection.enabled = false disables WebRTC entirely
        # and breaks video calls.  The three settings below prevent IP
        # leaks while keeping WebRTC functional.
        "media.peerconnection.ice.default_address_only"       = true;
        "media.peerconnection.ice.no_host"                    = true;
        "media.peerconnection.ice.proxy_only_if_behind_proxy" = true;

        # ── Fingerprinting resistance ──────────────────────────────
        # resistFingerprinting spoofs timezone to UTC and may break
        # locale-sensitive sites.  Disable per-site via about:config
        # if needed.
        "privacy.resistFingerprinting"                        = true;
        "privacy.resistFingerprinting.block_mozAddonManager"  = true;

        # ── Total Cookie Protection (replaces firstparty.isolate) ──
        # cookieBehavior = 5 = Total Cookie Protection (dFPI).
        # Equivalent to first-party isolation but extension-compatible.
        "network.cookie.cookieBehavior"                       = 5;

        # ── Telemetry — all disabled ───────────────────────────────
        "toolkit.telemetry.enabled"                           = false;
        "toolkit.telemetry.unified"                           = false;
        "toolkit.telemetry.server"                            = "data:,";
        "toolkit.telemetry.archive.enabled"                   = false;
        "toolkit.telemetry.newProfilePing.enabled"            = false;
        "toolkit.telemetry.shutdownPingSender.enabled"        = false;
        "toolkit.telemetry.updatePing.enabled"                = false;
        "toolkit.telemetry.bhrPing.enabled"                   = false;
        "toolkit.telemetry.firstShutdownPing.enabled"         = false;
        "toolkit.telemetry.coverage.opt-out"                  = true;
        "toolkit.coverage.endpoint.base"                      = "";
        "browser.ping-centre.telemetry"                       = false;
        "datareporting.healthreport.uploadEnabled"            = false;
        "datareporting.policy.dataSubmissionEnabled"          = false;
        "app.shield.optoutstudies.enabled"                    = false;
        "app.normandy.enabled"                                = false;
        "app.normandy.api_url"                                = "";
        "breakpad.reportURL"                                  = "";
        "browser.tabs.crashReporting.sendReport"              = false;

        # ── Safe Browsing — disable Google cloud connection ────────
        # These disable the update/hash-check requests to Google.
        # Local blocklists are also disabled; if you want local-only
        # protection, set just the URL prefs to "" and leave
        # malware.enabled / phishing.enabled = true.
        "browser.safebrowsing.malware.enabled"                        = false;
        "browser.safebrowsing.phishing.enabled"                       = false;
        "browser.safebrowsing.blockedURIs.enabled"                    = false;
        "browser.safebrowsing.provider.google4.gethashURL"            = "";
        "browser.safebrowsing.provider.google4.updateURL"             = "";
        "browser.safebrowsing.provider.google.gethashURL"             = "";
        "browser.safebrowsing.provider.google.updateURL"              = "";
        "browser.safebrowsing.provider.google4.dataSharingURL"        = "";
        "browser.safebrowsing.downloads.enabled"                      = false;
        "browser.safebrowsing.downloads.remote.enabled"               = false;
        "browser.safebrowsing.downloads.remote.block_potentially_unwanted" = false;
        "browser.safebrowsing.downloads.remote.block_uncommon"        = false;
        "browser.safebrowsing.allowOverride"                          = false;

        # ── OCSP hard-fail ─────────────────────────────────────────
        "security.OCSP.enabled"  = 1;    # 1 = enabled (0 = disabled)
        "security.OCSP.require"  = true; # hard-fail: reject cert if OCSP unreachable

        # ── Referrer trimming ──────────────────────────────────────
        # XOriginPolicy = 2: send no referrer for cross-origin requests
        # XOriginTrimmingPolicy = 2: trim to scheme+host+port cross-origin
        "network.http.referer.XOriginPolicy"         = 2;
        "network.http.referer.XOriginTrimmingPolicy" = 2;

        # ── DOM storage isolation ──────────────────────────────────
        "dom.storage.next_gen" = true;

        # ── History sanitization on close ──────────────────────────
        # Cookies, cache, and sessions are cleared; browsing history
        # and downloads are preserved across sessions.
        "privacy.sanitize.sanitizeOnShutdown"  = true;
        "privacy.clearOnShutdown.cookies"      = true;
        "privacy.clearOnShutdown.cache"        = true;
        "privacy.clearOnShutdown.sessions"     = true;
        "privacy.clearOnShutdown.history"      = false;
        "privacy.clearOnShutdown.downloads"    = false;

        # ── Built-in password manager — disable ───────────────────
        # KeePassXC-Browser replaces Firefox's password manager.
        "signon.rememberSignons" = false;

        # ── Vertical tabs (Firefox 131+) ───────────────────────────
        # nixpkgs 25.11 ships Firefox 133+, so this pref is active.
        # Remove if it causes issues on older builds.
        "sidebar.verticalTabs" = true;
      };

      # ── Extensions ──────────────────────────────────────────────────
      #
      # pkgs.firefox-addons is available in nixpkgs 25.11.
      # If the `packages` subkey is rejected by your home-manager version,
      # change to the older list syntax:
      #   extensions = with pkgs.firefox-addons; [ ublock-origin ... ];
      #
      # vimium-ff: include it if pkgs.firefox-addons.vimium-ff exists in
      # your nixpkgs; otherwise install from AMO (URL in LibreWolf section).
      # Uncomment the line below after confirming the attribute is present.
      #
      # Linkwarden: not in pkgs.firefox-addons as of nixpkgs 25.11.
      # Install manually: https://addons.mozilla.org/firefox/addon/linkwarden/
      extensions.packages = with pkgs.firefox-addons; [
        ublock-origin
        keepassxc-browser
        # vimium-ff  # uncomment if pkgs.firefox-addons.vimium-ff exists
      ];

      # ── Search engines ───────────────────────────────────────────────
      search = {
        default        = "DuckDuckGo";
        privateDefault = "DuckDuckGo";
        force          = true; # overwrite profile's search.json.sqlite on activation
        engines = {
          "Startpage" = {
            urls           = [{ template = "https://www.startpage.com/search?q={searchTerms}"; }];
            definedAliases = [ "@sp" ];
          };
          # Hide noisy default engines
          "Google".metaData.hidden     = true;
          "Bing".metaData.hidden       = true;
          "Amazon.com".metaData.hidden = true;
          "eBay".metaData.hidden       = true;
        };
      };
    };
  };

  # ── KeePassXC native messaging host for Firefox ───────────────────────
  home.file.".mozilla/native-messaging-hosts/org.keepassxc.keepassxc_browser.json".text =
    keepassxcFirefoxManifest;


  # ============================================================
  # BROWSER 4 — google-chrome (work / DRM / SSO fallback)
  # ============================================================
  #
  # Use for: Widevine DRM, enterprise SSO, sites broken by ungoogled patches
  # Do NOT use for privacy-sensitive browsing — no hardening applied
  # KeePassXC is wired for convenience (passwords still needed for work sites)
  #
  # No extensions, no policies, no extraOpts — intentionally minimal.

  home.packages = [ pkgs.google-chrome ];

  # ── KeePassXC native messaging host for google-chrome ────────────────
  home.file.".config/google-chrome/NativeMessagingHosts/org.keepassxc.keepassxc_browser.json".text =
    keepassxcChromeManifest [ "chrome-extension://oboonakemofpalcgghocfoadofidjkkk/" ];
}
