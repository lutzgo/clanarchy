{ lib, ... }:
#
# @clanarchy/software — browser and email application profiles for machines.
#
# Multiple roles can be combined: a machine can be assigned to any subset of
# browser and email roles simultaneously (e.g. librewolf + thunderbird + geary).
#
# Each role has a `user` setting controlling which Home Manager user receives
# the browser/email configuration (overrides, native-messaging manifests, etc.).
#
# Browser roles: librewolf  firefox  chromium  chrome  edge
# Email roles:   thunderbird  geary
#
{
  _class = "clan.service";
  manifest.name = "@clanarchy/software";
  manifest.description = "Browser and email application profiles (librewolf, firefox, chromium, chrome, edge, thunderbird, geary).";


  # ═══════════════════════════════════════════════════════════════════════════
  # BROWSER ROLES
  # ═══════════════════════════════════════════════════════════════════════════

  # ── LibreWolf ──────────────────────────────────────────────────────────────
  # System package + privacy overrides + KeePassXC native-messaging manifest.
  # No HM module exists for LibreWolf; configuration is via home.file.
  roles.librewolf = {
    description = "LibreWolf browser: system package, privacy overrides, KeePassXC native messaging.";
    interface.options.user = lib.mkOption {
      type        = lib.types.str;
      default     = "sabine";
      description = "Home Manager user to configure LibreWolf for.";
    };

    perInstance = { settings, ... }: {
      nixosModule = { pkgs, ... }:
        let
          # Capture the NixOS-level keepassxc path for the native-messaging manifest.
          # Using a let-binding so the HM module can reference it via closure without
          # receiving a separate pkgs argument.
          keepassxcProxy = "${pkgs.keepassxc}/bin/keepassxc-proxy";
        in
        {
          environment.systemPackages = [ pkgs.librewolf pkgs.keepassxc ];

          home-manager.users.${settings.user} = { ... }: {

            # ── Privacy overrides ────────────────────────────────────────
            # Evaluated after LibreWolf's built-in defaults (librewolf.cfg).
            # Mirrors the configuration used on miralda (home-modules/browsers.nix).
            home.file.".librewolf/librewolf.overrides.cfg".text = ''
              // librewolf.overrides.cfg — evaluated after LibreWolf's built-in defaults.

              // ── Mozilla push WebSocket ────────────────────────────────────
              // Resolves to Google Cloud infrastructure on startup (port 443,
              // push.services.mozilla.com).  Disabling it also disables Web Push
              // notifications; re-enable per-origin via site permissions if needed.
              user_pref("dom.push.connection.enabled", false);
              user_pref("dom.push.enabled", false);

              // ── Telemetry hardening ───────────────────────────────────────
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

            # ── KeePassXC native-messaging manifest ───────────────────────
            # Firefox-based browsers use "allowed_extensions" with the WebExtension
            # ID (not the Chrome-style "allowed_origins" with chrome-extension://).
            home.file.".librewolf/native-messaging-hosts/org.keepassxc.keepassxc_browser.json".text =
              builtins.toJSON {
                name               = "org.keepassxc.keepassxc_browser";
                description        = "KeePassXC integration with native messaging";
                path               = keepassxcProxy;
                type               = "stdio";
                allowed_extensions = [ "keepassxc-browser@keepassxc.org" ];
              };
          };
        };
    };
  };


  # ── Firefox ───────────────────────────────────────────────────────────────
  # Enables Firefox and wires the HM module.  Profile creation and Stylix
  # theming (stylix.targets.firefox.profileNames) are intentionally left to the
  # per-machine config (browsers.nix / users/sabine.nix) so that this role can
  # be added without conflicting with an existing profile setup (e.g. lgo's
  # "hardened" arkenfox profile on miralda).
  roles.firefox = {
    description = "Firefox browser; profile setup and Stylix theming left to per-machine config.";
    interface.options.user = lib.mkOption {
      type        = lib.types.str;
      default     = "sabine";
      description = "Home Manager user to enable Firefox for.";
    };

    perInstance = { settings, ... }: {
      nixosModule = { ... }: {
        home-manager.users.${settings.user} = { ... }: {
          programs.firefox = {
            enable     = true;
            # Explicit path silences the stateVersion < 26.05 migration warning.
            configPath = ".mozilla/firefox";
          };
        };
      };
    };
  };


  # ── ungoogled-chromium ────────────────────────────────────────────────────
  # Installs the privacy-hardened Chromium fork.  Privacy flags are baked into
  # the binary via the pkgsForSystem overlay in clan.nix; managed policies and
  # extensions should be configured per-machine in environment.etc and/or a
  # dedicated home-module (see machines/miralda/home-modules/browsers.nix for
  # the full miralda setup).
  roles.chromium = {
    description = "ungoogled-chromium (privacy-hardened Chromium; flags via clan.nix overlay).";
    interface.options.user = lib.mkOption {
      type        = lib.types.str;
      default     = "sabine";
      description = "Home Manager user to configure Chromium for (reserved for future use).";
    };

    perInstance = { ... }: {
      nixosModule = { pkgs, ... }: {
        environment.systemPackages = [ pkgs.ungoogled-chromium ];
      };
    };
  };


  # ── Google Chrome ─────────────────────────────────────────────────────────
  # Unfree package.  Intended for work / DRM / SSO fallback only.
  # KeePassXC native-messaging is wired for convenience.
  roles.chrome = {
    description = "Google Chrome (unfree) for work, DRM, and SSO fallback.";
    interface.options.user = lib.mkOption {
      type        = lib.types.str;
      default     = "sabine";
      description = "Home Manager user to install the KeePassXC native-messaging manifest for Chrome.";
    };

    perInstance = { settings, ... }: {
      nixosModule = { pkgs, ... }:
        let
          keepassxcProxy = "${pkgs.keepassxc}/bin/keepassxc-proxy";
        in
        {
          environment.systemPackages = [ pkgs.google-chrome pkgs.keepassxc ];

          home-manager.users.${settings.user} = { ... }: {
            # Chrome / Chromium manifest format: allowed_origins with chrome-extension:// scheme.
            home.file.".config/google-chrome/NativeMessagingHosts/org.keepassxc.keepassxc_browser.json".text =
              builtins.toJSON {
                name            = "org.keepassxc.keepassxc_browser";
                description     = "KeePassXC integration with native messaging";
                path            = keepassxcProxy;
                type            = "stdio";
                allowed_origins = [ "chrome-extension://oboonakemofpalcgghocfoadofidjkkk/" ];
              };
          };
        };
    };
  };


  # ── Microsoft Edge ────────────────────────────────────────────────────────
  # Unfree package.  No additional configuration applied.
  roles.edge = {
    description = "Microsoft Edge (unfree).";
    perInstance = { ... }: {
      nixosModule = { pkgs, ... }: {
        environment.systemPackages = [ pkgs.microsoft-edge ];
      };
    };
  };


  # ═══════════════════════════════════════════════════════════════════════════
  # EMAIL ROLES
  # ═══════════════════════════════════════════════════════════════════════════

  # ── Thunderbird ───────────────────────────────────────────────────────────
  roles.thunderbird = {
    description = "Mozilla Thunderbird email client.";
    interface.options.user = lib.mkOption {
      type        = lib.types.str;
      default     = "sabine";
      description = "Home Manager user to install Thunderbird for.";
    };

    perInstance = { settings, ... }: {
      nixosModule = { pkgs, ... }: {
        home-manager.users.${settings.user} = { ... }: {
          home.packages = [ pkgs.thunderbird ];
        };
      };
    };
  };


  # ── Geary ─────────────────────────────────────────────────────────────────
  roles.geary = {
    description = "GNOME Geary email client.";
    interface.options.user = lib.mkOption {
      type        = lib.types.str;
      default     = "sabine";
      description = "Home Manager user to install Geary for.";
    };

    perInstance = { settings, ... }: {
      nixosModule = { pkgs, ... }: {
        home-manager.users.${settings.user} = { ... }: {
          home.packages = [ pkgs.geary ];
        };
      };
    };
  };
}
