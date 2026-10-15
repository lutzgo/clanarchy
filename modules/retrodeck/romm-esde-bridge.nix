{ config, lib, pkgs, ... }:
#
# Publish RomM's ES-DE export into the layout ES-DE actually reads.
#
# ── The problem ──────────────────────────────────────────────────────────
#
# ernst's RomM exports ES-DE metadata into the ROM tree, and Syncthing
# replicates that tree to birte, so the Deck already holds everything:
#
#   roms/<system>/gamelist.xml            names, desc, genre, developer,
#                                         publisher, releasedate, rating, …
#   roms/<system>/assets/covers/…         artwork, named by ROM basename
#
# ES-DE reads neither path.  Two independent mismatches, verified on birte
# 2026-09-07 against the one system ES-DE had scraped itself (atari2600):
#
#   metadata   RomM writes roms/<sys>/gamelist.xml
#              ES-DE reads  ES-DE/gamelists/<sys>/gamelist.xml
#              (es_settings.xml has LegacyGamelistFileLocation = false)
#
#   artwork    RomM writes roms/<sys>/assets/covers/<basename>.png
#              ES-DE reads  ES-DE/downloaded_media/<sys>/covers/<basename>.png
#
# The artwork half is the nastier one, because ES-DE *ignores* the
# <thumbnail>/<image> paths in gamelist.xml — its own generated gamelists do
# not even contain those tags.  It locates media purely by directory
# convention, so flipping LegacyGamelistFileLocation would have produced
# metadata with no pictures.  The one lucky break is that RomM names assets by
# ROM basename, which is exactly ES-DE's convention, so the trees can simply be
# pointed at each other.
#
# ── Why gamelists are COPIED and media is SYMLINKED ──────────────────────
#
# es_settings.xml has SaveGamelistsMode = "always": ES-DE rewrites gamelist.xml
# itself.  A symlink into the Syncthing-replicated ROM tree would let it
# clobber RomM's export *and* propagate the damage back to ernst.  So gamelists
# are copied (small — 8 MB at the largest) and media directories are symlinked
# (large, and read-mostly).
#
# ── Why "skip systems that already have a gamelist" is WRONG ─────────────
#
# The obvious guard — don't touch a system ES-DE already has a gamelist for —
# self-destructs on the second run.  Because SaveGamelistsMode is "always",
# ES-DE writes its own gamelist for *every* system on first launch, so that
# rule would match everything from then on and the bridge would silently stop
# updating.  It would look like it worked once and then rotted.
#
# So the refresh rule is an mtime comparison against the source instead, and
# systems you deliberately scrape with ES-DE itself go in `excludeSystems`.
#
let
  cfg = config.clanarchy.retrodeck.rommBridge;

  # RomM's ASSET_DIRS (utils/gamelist_exporter.py) mapped onto ES-DE's media
  # directory names, confirmed against ES-DE's own downloaded_media tree.
  # Most agree; three do not, and two RomM types have no ES-DE equivalent
  # (miximages_v2, bezels) and are deliberately left unlinked.
  mediaMap = {
    covers       = "covers";
    screenshots  = "screenshots";
    backcovers   = "backcovers";
    fanart       = "fanart";
    marquees     = "marquees";
    miximages    = "miximages";
    titlescreens = "titlescreens";
    videos       = "videos";
    manuals      = "manuals";
    boxes        = "3dboxes";      # RomM "boxes" is ES-DE "3dboxes"
    physical     = "physicalmedia";
  };

  mapPairs = lib.concatStringsSep " " (
    lib.mapAttrsToList (romm: esde: "${romm}:${esde}") mediaMap
  );

  bridge = pkgs.writeShellApplication {
    name = "romm-esde-bridge";
    runtimeInputs = [ pkgs.coreutils pkgs.findutils ];
    text = ''
      roms=${lib.escapeShellArg cfg.romsDir}
      gamelists=${lib.escapeShellArg cfg.esdeDir}/gamelists
      media=${lib.escapeShellArg cfg.esdeDir}/downloaded_media
      owner=${lib.escapeShellArg "${cfg.user}:${cfg.group}"}
      excluded=${lib.escapeShellArg (lib.concatStringsSep " " cfg.excludeSystems)}

      bridged=0; refreshed=0; skipped=0

      for dir in "$roms"/*/; do
        sys=$(basename "$dir")
        src="$dir/gamelist.xml"
        [ -f "$src" ] || continue

        # A platform directory RomM created but that holds no ROMs is noise:
        # RomM emits one per platform it knows about, ~570 of them.
        if [ -z "$(find "$dir" -maxdepth 1 -type f ! -name gamelist.xml -print -quit)" ]; then
          continue
        fi

        case " $excluded " in
          *" $sys "*) skipped=$((skipped+1)); continue ;;
        esac

        install -d -o "''${owner%%:*}" -g "''${owner##*:}" "$gamelists/$sys" "$media/$sys"

        # Refresh on mtime, so a re-export after a scan wins over whatever
        # ES-DE last wrote back. See the header for why "already exists" is
        # not a usable test here.
        dst="$gamelists/$sys/gamelist.xml"
        if [ ! -f "$dst" ] || [ "$src" -nt "$dst" ]; then
          cp -f "$src" "$dst"
          chown "$owner" "$dst"
          refreshed=$((refreshed+1))
        fi

        for pair in ${mapPairs}; do
          from=''${pair%%:*}
          to=''${pair##*:}
          [ -d "$dir/assets/$from" ] || continue
          target="$media/$sys/$to"
          # Never replace a real directory: that would be ES-DE's own scraped
          # media for this system, which is richer than RomM's export.
          if [ -e "$target" ] && [ ! -L "$target" ]; then
            echo "romm-esde-bridge: $target is a real directory (ES-DE's own media) — left alone" >&2
            continue
          fi
          ln -sfn "$dir/assets/$from" "$target"
          chown -h "$owner" "$target"
        done

        bridged=$((bridged+1))
      done

      echo "romm-esde-bridge: bridged=$bridged gamelists_refreshed=$refreshed excluded=$skipped"
    '';
  };
in
{
  options.clanarchy.retrodeck.rommBridge = {
    enable = lib.mkEnableOption "publishing RomM's ES-DE export into RetroDECK's ES-DE layout";

    romsDir = lib.mkOption {
      type = lib.types.str;
      default = "/games/retrodeck/roms";
      description = "RetroDECK's ROM tree — the Syncthing replica of ernst's /srv/roms/roms.";
    };

    esdeDir = lib.mkOption {
      type = lib.types.str;
      default = "/games/retrodeck/ES-DE";
      description = "RetroDECK's ES-DE data directory, holding gamelists/ and downloaded_media/.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "deck";
      description = "Owner of the published gamelists and media links (the user RetroDECK runs as).";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "users";
      description = "Group of the published gamelists and media links.";
    };

    excludeSystems = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "atari2600" ];
      example = [ "atari2600" "nes" ];
      description = ''
        Systems left entirely to ES-DE's own scraper.  A system scraped in
        ES-DE gets descriptions, videos, manuals, miximages and 3D boxes, which
        is richer than RomM's export — atari2600 was scraped that way before
        this bridge existed and is excluded so it is not downgraded.

        This is the *only* opt-out: every other system is refreshed whenever
        RomM re-exports, on purpose.  See the note in this module about why
        "skip if a gamelist already exists" cannot be used instead.
      '';
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "30min";
      description = ''
        How often to re-check for a newer RomM export.  Cheap — the common
        case is a handful of stat calls and no writes.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.romm-esde-bridge = {
      description = "Publish RomM's ES-DE export into RetroDECK's ES-DE layout";
      # The ROM tree is a btrfs subvolume outside the impermanence rollback, so
      # it is there as soon as local filesystems are.
      after    = [ "local-fs.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe bridge;
        # Runs as root: it chowns to the deck user, and the ROM tree is owned
        # by syncthing rather than by deck.
        PrivateNetwork = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ cfg.esdeDir ];
        NoNewPrivileges = true;
      };
    };

    systemd.timers.romm-esde-bridge = {
      description = "Re-publish RomM's ES-DE export when it changes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "3min";
        OnUnitActiveSec = cfg.interval;
        Persistent = true;
      };
    };
  };
}
