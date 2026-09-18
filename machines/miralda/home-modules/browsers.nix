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
# System packages for all four browsers are installed by the
# @clanarchy/software roles in service-modules/software.nix.
# Privacy policies for Chromium live in that role too.
# Extension first-run tabs and the chromiumFirstRun reset service
# are in modules/users/lgo.nix (lgo-specific extension list).
#
# ── THIS FILE IS SHARED, DESPITE ITS PATH ───────────────────────────────
#
# It lives under machines/miralda/ for historical reasons only.  Nothing in
# flake.nix imports it; modules/users/lgo.nix does, so every machine carrying
# `roles.lgo` gets it — miralda AND jens.  One edit here changes both.
#
# ── FOUR BROWSERS, FOUR DIFFERENT EXTENSION MECHANISMS ──────────────────
#
# That is not untidiness waiting to be unified; each is the only thing that
# works for its browser, and the reasons are written at each site:
#
#   ungoogled-chromium  External Extensions JSON (the forcelist policy is
#                       ignored by this fork), fetched from the Web Store
#   Firefox             NUR-packaged .xpi, STORE-PINNED and hash-verified
#   LibreWolf           an ExtensionSettings policy merged into the wrapper's
#                       own distribution/policies.json, fetched from AMO
#                       (service-modules/software.nix, values in clan.nix)
#   google-chrome       an ExtensionSettings managed policy in /etc
#                       (modules/users/lgo.nix — HM asserts against setting
#                       `programs.chromium.extensions` for Chrome on Linux)
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
    # THE MECHANISM IS External Extensions, NOT ExtensionInstallForcelist.
    # This block used to carry two stacked comments that contradicted each
    # other on exactly that point; the forcelist one was wrong twice over.
    #
    #   What HM actually does: `programs.chromium.extensions` writes
    #   ~/.config/chromium/External Extensions/<id>.json per entry, each
    #   containing an `external_update_url`.  Chromium reads that directory on
    #   startup and installs what it finds.
    #
    #   Why the forcelist would not work here even if HM emitted one:
    #   ungoogled-chromium IGNORES ExtensionInstallForcelist entirely
    #   (ungoogled-software/ungoogled-chromium#2523) — the policy depends on
    #   Web Store update infrastructure the fork removes, and the symptom is
    #   nothing at all in chrome://extensions and nothing in the log.
    #
    # ungoogled-chromium blocks the External Extensions mechanism by default
    # too; `--extension-mime-request-handling=always-prompt-for-install`
    # re-enables it.  That flag is baked into the binary by the overlay in
    # lib/overlays.nix — NOT by a `commandLineArgs` in this file, which an
    # earlier version of this comment claimed and which would be ignored,
    # since clan-core force-sets `nixpkgs.pkgs` before any module runs.
    #
    # THE SECOND LIST.  modules/users/lgo.nix carries a parallel set of CRX
    # URLs in `chromiumFirstRunTabs`, a belt-and-braces path that prompts on
    # first run.  THE TWO HAVE DRIFTED — that list is missing SideTab Pro, and
    # the drift predates M27 and is not fixed here.  New entries go in both.
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
      { id = "dbepggeogbaibhgnhhndojpepiihcmeb"; }
      # SideTab Pro (vertical tabs) — ⚠ ID spec-provided, unverified
      { id = "fehfojhhnbfbclgpffmffigfgngbpnmj"; }
      # Vertical Tabs (nicedoc.io) — FOSS, ~100K users
      # github.com/samihaddad/vertical-tabs-chrome-extension
      # Toggle: Alt+V (configurable at chrome://extensions/shortcuts)
      # NOTE: rendering bug reported in Chrome 145 (issue #117 on GitHub)
      # — monitor upstream; extension is on Chrome 146 which fixes the
      # Chrome-side bug. If sidebar stops rendering, check issue tracker.
      { id = "efobhjmgoddhfdhaflheioeagkcknoji"; }

      # ── M27's reading stack ─────────────────────────────────────────
      #
      # THESE TWO REPLACE A LINKWARDEN ENTRY THAT POINTED AT NOTHING.  This
      # list carried `pnidmkljnhbjfffciajlenmpaoemnjlo`, marked "⚠ ID
      # spec-provided, unverified", alongside comments elsewhere in this file
      # that doubted whether the Firefox listing existed and a Vimium
      # keybinding whose target was the literal string
      # YOUR_LINKWARDEN_INSTANCE.  There has never been a Linkwarden server
      # anywhere in this fleet.  All of it is deleted rather than finally
      # built, because Karakeep takes the role — see
      # machines/ernst/containers/karakeep.nix.
      #
      # Karakeep — verified CWS: kgcjekpmcjjogibpjebkhaanilehneje
      # Saves the current page to karakeep.goclan.org.
      { id = "kgcjekpmcjjogibpjebkhaanilehneje"; }
      # floccus bookmarks sync — verified CWS: fnaicdffflnofjppbagibeoednhnbjhg
      # Syncs THIS browser's own bookmark tree into the same Karakeep, which
      # is what makes the two halves one stack rather than two tools.
      { id = "fnaicdffflnofjppbagibeoednhnbjhg"; }
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

  # ── Vimium: a keyboard shortcut to the bookmark library ───────────────
  #
  # Vimium settings cannot be managed declaratively via Chromium policy, so
  # this is a manual step and stays one.  After first launch, open the Vimium
  # options page and add the following to "Custom key mappings":
  #
  #   map <a-b> createTab https://karakeep.goclan.org/dashboard/bookmarks
  #
  # This used to name YOUR_LINKWARDEN_INSTANCE, a placeholder for a server
  # that was never built (M27).


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

  # ── LibreWolf user prefs + KeePassXC native messaging ────────────────
  # Managed by the @clanarchy/software librewolf role (service-modules/software.nix).
  # lgo is assigned to that role in clan.nix → configs are generated there.

  # ── Extensions — LibreWolf ────────────────────────────────────────────
  #
  # PARTLY DECLARATIVE SINCE M27, and this comment used to say flatly that no
  # mechanism existed.  Karakeep and Floccus are installed by the `librewolf`
  # role's `extensions` setting in service-modules/software.nix — an
  # `ExtensionSettings` policy merged into the wrapper's own
  # distribution/policies.json, which is the same mechanism LibreWolf itself
  # uses to ship uBlock Origin.  The values are in clan.nix.
  #
  # THE OLDER THREE ARE STILL MANUAL, deliberately: they are already installed
  # and already configured on both machines, and moving a working extension
  # from "installed by hand" to "installed by policy" is a migration with no
  # benefit.  New ones go through the role.  On a fresh machine, install these
  # on first launch from the AMO (addons.mozilla.org):
  #
  #   uBlock Origin      https://addons.mozilla.org/firefox/addon/ublock-origin/
  #   Vimium-FF          https://addons.mozilla.org/firefox/addon/vimium-ff/
  #   KeePassXC-Browser  https://addons.mozilla.org/firefox/addon/keepassxc-browser/
  #
  # (A Linkwarden line used to sit here, with a note doubting whether the AMO
  # listing existed.  It did not, and neither did the server — M27.)
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
    configPath = ".mozilla/firefox"; # silence stateVersion < 26.05 migration warning

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
      # Installed declaratively via NUR (nur.repos.rycee.firefox-addons), and
      # STORE-PINNED: each entry is a fetched, hash-verified .xpi in the Nix
      # store, not a runtime download.  That is the one place Firefox's
      # arrangement here is strictly stronger than Chromium's and LibreWolf's,
      # both of which fetch from a live store on first launch.
      #
      # `inputs.nur` is reached directly rather than through an overlay.  A
      # comment here used to say the overlay was applied "in desktop.nix via
      # home-manager.sharedModules"; no file in this repo applies a NUR overlay
      # at all, and none can — `home-manager.useGlobalPkgs` makes HM's `pkgs`
      # the overlay-frozen instance clan-core builds, so `nixpkgs.overlays`
      # inside an HM module is a no-op.  The flake input is the working route.
      extensions.packages =
        let nurPkgs = inputs.nur.legacyPackages.${pkgs.stdenv.hostPlatform.system};
        in with nurPkgs.repos.rycee.firefox-addons; [
          ublock-origin
          keepassxc-browser
          vimium  # AMO slug is "vimium-ff" but NUR rycee attr is "vimium"

          # ── M27's reading stack ───────────────────────────────────────
          #
          # Karakeep saves a page to karakeep.goclan.org; Floccus syncs THIS
          # browser's own bookmark tree into the same Karakeep, which is what
          # makes them one stack.  Both replace a Linkwarden that never
          # existed — see the Chromium list above.
          #
          # BOTH NEED A SERVER URL AND AN API KEY ENTERED BY HAND on first
          # use, in every browser, on both machines.  Neither exposes a
          # managed-storage schema, so there is nothing for a policy to set.
          # That is eight small manual steps and no way around them.
          karakeep
          floccus
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
  #
  # STILL MINIMAL, WITH ONE EXCEPTION SINCE M27.  Karakeep and Floccus are
  # installed here too, because the point of Floccus is that the SAME bookmark
  # tree is present in every browser and a browser left out of the sync is a
  # browser whose bookmarks silently diverge — which is worse than not having
  # it at all.  Nothing else about this browser's posture changed: no
  # hardening, no privacy policies, still not for privacy-sensitive browsing.
  #
  # The mechanism is NOT `programs.chromium.extensions`: home-manager asserts
  # against setting that for google-chrome on Linux.  It is an
  # `ExtensionSettings` managed policy under /etc/opt/chrome, declared in
  # modules/users/lgo.nix beside the other lgo-specific extension list.

  # ── KeePassXC native messaging host for google-chrome ────────────────
  # Managed by the @clanarchy/software chrome role (service-modules/software.nix).
}
