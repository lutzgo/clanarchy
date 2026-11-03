# lgo's KeePassXC settings, declarative — including KeeShare's signing key.
#
# WHY NOT home-manager's programs.keepassxc.settings: it links keepassxc.ini
# into the Nix store, which is world-readable, and KeeShare keeps its PRIVATE
# signing key in that same file. So the file is written instead: on every
# switch, and at boot (home-manager-lgo.service), from the settings below
# plus the key from a clan var. It stays a plain writable file, so KeePassXC
# does not complain about it — but anything changed in its settings dialog is
# overwritten at the next switch. Change it here.
#
# KEESHARE shares one group of a database through a separate container file,
# signed with this key so the importing side can verify the signer. It does
# not touch the main .kdbx, so the database synced to Android (KeePassDX,
# Keepass2Android — neither speaks KeeShare) is unaffected; shared groups just
# only sync on KeePassXC.
{
  config,
  lib,
  pkgs,
  ...
}: let
  enabled = config.clanarchy.users.lgo.enable;
  keeshare = config.clan.core.vars.generators.keepassxc-keeshare-lgo;

  # Everything but [KeeShare], which carries the secret and is appended at
  # runtime. Keys and sections are KeePassXC's own (src/core/Config.cpp).
  settings = {
    General = {
      ConfigVersion = 2;
      HideWindowOnCopy = true;
      MinimizeAfterUnlock = true;
      MinimizeOnOpenUrl = true;
    };
    GUI = {
      MinimizeOnClose = true;
      MinimizeOnStartup = true;
      MinimizeToTray = true;
      ShowTrayIcon = true;
      TrayIconAppearance = "monochrome-light";
    };
    Security = {
      IconDownloadFallback = true;
      # Never lock on idle. The screen lock still covers an unattended session.
      LockDatabaseIdle = false;
    };
  };
  baseIni = (pkgs.formats.ini {}).generate "keepassxc-base.ini" settings;

  # QSettings' INI form of KeeShare's XML values: quoted, inner quotes
  # escaped, and the trailing newline QXmlStreamWriter's writeEndDocument()
  # leaves, written as a literal \n — byte-for-byte what KeePassXC itself
  # wrote here. <Import/><Export/> are the two "allow" switches; empty
  # <Active/> means KeeShare is off.
  activeXml = ''<?xml version=\"1.0\"?><KeeShare><Active><Import/><Export/></Active></KeeShare>\n'';
in {
  config = lib.mkIf enabled {
    # One key for both laptops (share = true): the signer is the person, not
    # the machine. Format per KeePassXC 2.8 src/keeshare/KeeShareSettings.cpp:
    # Own::generate makes RSA-2048; Key::serialize and Certificate::serialize
    # both write the PKCS#8 DER of the PRIVATE key as base64, and Signer is
    # $USER.
    clan.core.vars.generators.keepassxc-keeshare-lgo = {
      share = true;
      files."own.ini-value" = {
        secret = true;
        neededFor = "services";
        owner = "lgo";
      };
      runtimeInputs = [pkgs.openssl pkgs.coreutils];
      script = ''
        # `pkcs8 -topk8`: genpkey's DER is PKCS#1 here (MEASURED: asn1parse
        # shows no AlgorithmIdentifier), and Botan::PKCS8::load_key wants
        # PKCS#8 — KeePassXC would drop the key with "Failed to deserialize".
        key=$(openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -quiet |
          openssl pkcs8 -topk8 -nocrypt -outform DER | base64 -w0)
        printf '%s' "\"<?xml version=\\\"1.0\\\"?><KeeShare><PrivateKey>$key</PrivateKey><PublicKey><Signer>lgo</Signer><Key>$key</Key></PublicKey></KeeShare>\\n\"" \
          > "$out/own.ini-value"
      '';
    };

    home-manager.users.lgo = {lib, ...}: {
      home.activation.keepassxcSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
        _ini="$HOME/.config/keepassxc/keepassxc.ini"
        _own=${lib.escapeShellArg keeshare.files."own.ini-value".path}
        if [ -n "''${DRY_RUN:-}" ]; then
          verboseEcho "keepassxc: would rewrite $_ini"
        elif [ -r "$_own" ]; then
          run mkdir -p "$HOME/.config/keepassxc"
          _tmp=$(mktemp "$_ini.XXXXXX")
          {
            cat ${baseIni}
            printf '\n[KeeShare]\n'
            printf 'Active="%s"\n' ${lib.escapeShellArg activeXml}
            printf 'Own=%s\n' "$(cat "$_own")"
            printf 'QuietSuccess=true\n'
          } > "$_tmp"
          chmod 600 "$_tmp"
          run mv "$_tmp" "$_ini"
        else
          warnEcho "keepassxc: KeeShare key $_own not readable; keepassxc.ini left as it is"
        fi
      '';
    };
  };
}
