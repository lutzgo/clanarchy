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
{ pkgs, inputs, ... }:

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
  # NOTE: google-chrome (unfree) is installed as a system package in apps.nix.
  # nixpkgs.config.allowUnfreePredicate in a home-manager NixOS module does
  # not affect the pkgs argument used by home.packages — the pkgs argument
  # always comes from the system evaluation in this setup.  The allowUnfree
  # predicate and the google-chrome package entry both live in apps.nix.


  # ============================================================
  # BROWSER 1 — ungoogled-chromium (daily Chromium driver)
  # ============================================================

  programs.chromium = {
    enable  = true;
    # Replace standard pkgs.chromium (remove it from apps.nix).
    # ungoogled-chromium ships with Google API keys removed and a
    # Chromium-Web-Store patch that restores the extension install UI.
    # Flags are baked into the binary via the pkgsForSystem overlay in clan.nix.
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
    # ── Extensions ────────────────────────────────────────────────────
    #
    # HM writes ~/.config/chromium/External Extensions/<id>.json per entry.
    # ungoogled-chromium blocks external extension installation by default;
    # --extension-mime-request-handling=always-prompt-for-install (in
    # commandLineArgs below) re-enables the External Extensions mechanism
    # so that CWS entries auto-install on next launch.
    #
    # IDs marked ⚠ were spec-provided and could not be confirmed against the
    # live Web Store — if one fails to install, open chrome://extensions and
    # verify the correct ID via the Web Store search.
    extensions = [
      # chromium-web-store — restores the Web Store UI in ungoogled-chromium
      {
        id        = "cinhimbnkkaeohfgghhklpknlkffjgod";
        updateUrl = "https://github.com/NeverDecaf/chromium-web-store/releases/latest/download/update.xml";
      }
      # uBlock Origin — verified CWS: cjpalhdlnbpafiamejdnhcphjbkeiagm
      { id = "cjpalhdlnbpafiamejdnhcphjbkeiagm"; }
      # KeePassXC-Browser — verified CWS: oboonakemofpalcgghocfoadofidjkkk
      { id = "oboonakemofpalcgghocfoadofidjkkk"; }
      # Vimium — verified CWS: dbepggeogbaibhgnhhndojpepiihcmeb
      # After first launch: Options → Custom key mappings →
      #   map <a-b> createTab https://YOUR_LINKWARDEN_INSTANCE/links
      { id = "dbepggeogbaibhgnhhndojpepiihcmeb"; }
      # SideTab Pro (vertical tabs) — ⚠ ID spec-provided, unverified
      { id = "fehfojhhnbfbclgpffmffigfgngbpnmj"; }
      # Linkwarden — ⚠ ID spec-provided, unverified
      { id = "pnidmkljnhbjfffciajlenmpaoemnjlo"; }
    ];

  };

  # ── Desktop entries ───────────────────────────────────────────────────
  # ungoogled-chromium ships both chromium.desktop and chromium-browser.desktop.
  # Shadow chromium.desktop to ensure a clean single entry; hide chromium-browser.
  xdg.desktopEntries.chromium = {
    name        = "Chromium";
    genericName = "Web Browser";
    exec        = "chromium %U";
    icon        = "chromium";
    categories  = [ "Network" "WebBrowser" ];
    mimeType    = [ "text/html" "text/xml" "application/xhtml+xml" "x-scheme-handler/http" "x-scheme-handler/https" ];
  };
  xdg.desktopEntries.chromium-browser = {
    name      = "Chromium Browser";
    exec      = "chromium %U";
    noDisplay = true;
  };

  # ── Chromium policies ─────────────────────────────────────────────────
  # Managed policies are now in apps.nix via environment.etc
  # (/etc/chromium/policies/managed/privacy.json, root-owned).

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

        # ── userChrome.css — required to hide the horizontal tab bar ─
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
      };

      # ── Hide horizontal tab bar (vertical tabs active) ───────────────
      # Firefox does not hide the horizontal tab bar when the vertical
      # sidebar is enabled — the user must either toggle it in Firefox's
      # right-click menu on the tab bar, or force it via userChrome.css.
      # This CSS hides it unconditionally; remove if you want it back.
      userChrome = ''
        /* Hide the horizontal tab bar — vertical tabs sidebar is used instead */
        #TabsToolbar {
          display: none !important;
        }
      '';

      # ── Extensions ──────────────────────────────────────────────────
      #
      # Installed declaratively via NUR (nur.repos.rycee.firefox-addons).
      # NUR overlay is applied in desktop.nix via home-manager.sharedModules.
      # Linkwarden is Chrome-only; install from AMO manually if an
      # official Firefox listing appears.
      extensions.packages =
        let nurPkgs = inputs.nur.legacyPackages.${pkgs.stdenv.hostPlatform.system};
        in with nurPkgs.repos.rycee.firefox-addons; [
          ublock-origin
          keepassxc-browser
          vimium  # AMO slug is "vimium-ff" but NUR rycee attr is "vimium"
        ];

      # ── Search engines ───────────────────────────────────────────────
      search = {
        default        = "ddg";   # home-manager now uses engine IDs, not display names
        privateDefault = "ddg";
        force          = true; # overwrite profile's search.json.sqlite on activation
        engines = {
          "Startpage" = {
            urls           = [{ template = "https://www.startpage.com/search?q={searchTerms}"; }];
            definedAliases = [ "@sp" ];
          };
          # Hide noisy default engines (referenced by ID, not display name)
          "google".metaData.hidden         = true;
          "bing".metaData.hidden           = true;
          "amazondotcom-us".metaData.hidden = true;
          "ebay".metaData.hidden           = true;
        };
      };
    };
  };

  # Stylix Firefox target — must know the profile name to write
  # userChrome/userContent overrides into the correct profile directory.
  stylix.targets.firefox.profileNames = [ "hardened" ];

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
  # Package is installed in apps.nix (system level) alongside the
  # allowUnfreePredicate entry for "google-chrome".
  # No extensions, no policies — intentionally minimal.

  # ── KeePassXC native messaging host for google-chrome ────────────────
  home.file.".config/google-chrome/NativeMessagingHosts/org.keepassxc.keepassxc_browser.json".text =
    keepassxcChromeManifest [ "chrome-extension://oboonakemofpalcgghocfoadofidjkkk/" ];
}
