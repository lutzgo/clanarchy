# machines/ernst/containers/arr/storage.nix
#
# Every host-side directory the `arr` container binds, and the one unit that
# builds the audiobooks tree.
#
# ── THIS FILE CO-DEFINES NOTHING INSIDE THE CONTAINER ───────────────────────
#
# It is host-side only: tmpfiles rules and `audiobooks-tree.service`. It is
# separate from ./common.nix because the per-directory reasoning is the
# largest single body of text in this service — which dataset, which mode,
# which group, and what went wrong the time it was different — and none of it
# is needed to read the container's own definition.
#
# containers/storyteller.nix depends on `audiobooks-tree.service`, so that
# unit's name is part of this file's interface rather than an internal detail.
{ config, lib, pkgs, ... }:
let
  ids = import ./ids.nix;

  # The old flat names — see ./video.nix for why the bodies are unchanged.
  inherit (ids) stateRoot audiobooksRoot;
  sonarrUid = ids.uids.sonarr;
  radarrUid = ids.uids.radarr;
  prowlarrUid = ids.uids.prowlarr;
  bazarrUid = ids.uids.bazarr;
  cleanuparrUid = ids.uids.cleanuparr;
  mediathekarrUid = ids.uids.mediathekarr;
  jellyseerrUid = ids.uids.jellyseerr;
  janitorrUid = ids.uids.janitorr;
  scraparrUid = ids.uids.scraparr;
  lidarrUid = ids.uids.lidarr;
  soularrUid = ids.uids.soularr;
  kapowarrUid = ids.uids.kapowarr;
  questarrUid = ids.uids.questarr;
  audiobookshelfUid = ids.uids.audiobookshelf;
  binderyUid = ids.uids.bindery;
  komgaUid = ids.uids.komga;
  navidromeUid = ids.uids.navidrome;
  prowlarrGid = ids.gids.prowlarr;
  jellyseerrGid = ids.gids.jellyseerr;
  scraparrGid = ids.gids.scraparr;
  questarrGid = ids.gids.questarr;
  mediaGid = ids.gids.media;
  beetsStagingRoot = ids.paths.beetsStaging;
  beetsStateDir    = ids.paths.beetsState;
in
{
  # State directories on zdata.
  #
  # 0700 and owned by the service, exactly like /srv/state/jellyfin: nothing
  # else needs to read an *arr database, and the media group has no business
  # in it.
  #
  # NUMERIC ids on purpose.  `media` exists on the host (jellyfin.nix declares
  # it) but sonarr/radarr/prowlarr do NOT — they are container users, and the
  # host has no matching passwd entry.  tmpfiles takes numeric ids happily and
  # this is the same shape jellyfin.nix uses for uid 964.
  #
  # These rules matter beyond first creation: systemd's StateDirectory= logic
  # inside the container adjusts ownership of the state directory when it does
  # not match, and a recursive chown of a directory holding an *arr database is
  # not something to trigger by accident on every boot.  Getting the ownership
  # right here means it always matches and nothing recurses.
  systemd.tmpfiles.rules = [
    "d ${stateRoot}/sonarr   0700 ${toString sonarrUid}   ${toString mediaGid}    -"
    "d ${stateRoot}/radarr   0700 ${toString radarrUid}   ${toString mediaGid}    -"
    "d ${stateRoot}/prowlarr 0700 ${toString prowlarrUid} ${toString prowlarrGid} -"

    # M12.  Same shape, same reasoning — numeric ids because these are
    # container users with no passwd entry on the host.
    "d ${stateRoot}/bazarr       0700 ${toString bazarrUid}       ${toString mediaGid} -"
    "d ${stateRoot}/cleanuparr   0700 ${toString cleanuparrUid}   ${toString mediaGid} -"
    "d ${stateRoot}/mediathekarr 0700 ${toString mediathekarrUid} ${toString mediaGid} -"

    # MediathekArr's download tree, and it is NOT under ${stateRoot}.
    #
    # It is media, not state: the downloader writes .mkv files here and the
    # *arr then HARDLINK them into the library.  A hardlink cannot cross a
    # filesystem boundary, so this has to live inside the /srv/media dataset
    # like every other download source (see the hardlink section of the
    # header).  Putting it on zdata/state would turn every Mediathek import
    # into a copy, silently — the failure mode invariant #2 exists to prevent.
    #
    # 2770 root:media, matching the tmpfiles rules containers/jellyfin.nix and
    # microvms/wg-qbittorrent.nix declare for the rest of the tree: setgid so
    # everything created inside inherits `media`, group-writable so sonarr and
    # radarr can remove the source after a successful import.
    "d /srv/media/torrents/mediathek            2770 root ${toString mediaGid} -"
    "d /srv/media/torrents/mediathek/incomplete 2770 root ${toString mediaGid} -"
    "d /srv/media/torrents/mediathek/complete   2770 root ${toString mediaGid} -"

    # ── M13 ────────────────────────────────────────────────────────────────
    #
    # Two state directories in the usual shape.  Scraparr gets none: it holds
    # no state at all — it reads REST APIs and answers /metrics from memory,
    # and its entire configuration arrives as an EnvironmentFile.
    #
    # Jellyseerr's directory is named `jellyseerr` on zdata but binds to
    # /var/lib/SEERR inside, and the mismatch is deliberate — see the bind
    # mount below for why the two names differ.
    "d ${stateRoot}/jellyseerr 0700 ${toString jellyseerrUid} ${toString jellyseerrGid} -"
    "d ${stateRoot}/janitorr   0700 ${toString janitorrUid}   ${toString mediaGid}      -"

    # Janitorr's "Leaving Soon" tree, and — like MediathekArr's download tree
    # above — it is NOT under ${stateRoot}.
    #
    # It has to be inside /srv/media, but for a different reason than the
    # hardlink one.  This directory holds SYMLINKS to library files, and
    # Jellyfin is pointed at it as an extra library so that "Movies (Leaving
    # Soon)" shows up on the couch.  Jellyfin only sees /srv/media, so a tree
    # anywhere else would resolve to nothing from its side.
    #
    # 2770 root:media, matching the rest of the tree: Janitorr (uid 3015,
    # group media) creates and tears down folders in here on every run —
    # `file-system.from-scratch` rebuilds the whole thing — and Jellyfin
    # (uid 964, also in media) has to be able to read what it finds.
    #
    # DELETING THIS DIRECTORY DELETES SYMLINKS, NOT MEDIA.  Worth stating
    # plainly next to a path owned by a service whose job is deletion: nothing
    # under here is a real file.
    "d /srv/media/leaving-soon 2770 root ${toString mediaGid} -"

    # The *arr RECYCLE BIN, and it is NOT under ${stateRoot} either.
    #
    # IT MUST BE INSIDE /srv/media, and for the same reason the hardlink
    # section of the header gives, in its other direction: "delete to recycle
    # bin" is a RENAME.  A rename cannot cross a filesystem boundary, so a bin
    # on another dataset silently degrades into copy-then-delete — which for a
    # 60 GB remux means minutes of IO and a temporary doubling of its space,
    # on the exact operation that is supposed to be cheap and reversible.
    #
    # This is the second of the two safety nets M13 requires before Janitorr's
    # dry-run is ever turned off.  The other is dry-run itself.
    #
    # 2770 root:media so sonarr and radarr (both group media) can move files
    # in, and so anything landing here inherits the group and stays removable.
    #
    # SETTING THE PATH IS STILL A UI STEP in each *arr — this rule only
    # guarantees the directory exists with the right ownership when they are
    # pointed at it.  Faking the setting from Nix would be a second source of
    # truth for a value the applications own; see the Cleanuparr block.
    "d /srv/media/.recycle-bin 2770 root ${toString mediaGid} -"

    # ── M14 ────────────────────────────────────────────────────────────────
    #
    # State directories, in the usual 0700 shape with numeric ids.
    #
    # Soularr gets one even though it is a one-shot script, and it is NOT
    # optional: soularr.py writes `.soularr.lock` into its --var-dir and
    # refuses to start while it is present.  That lock is what stops two timer
    # firings from overlapping on a long search, so it has to live somewhere
    # that survives a restart — a tmpfs would silently disable the interlock.
    # It also keeps `.current_page.txt` and `failed_imports.json` there.
    "d ${stateRoot}/lidarr         0700 ${toString lidarrUid}         ${toString mediaGid}    -"

    # LIDARR'S `.config` PARENT — and this one is not housekeeping, it is what
    # makes Lidarr able to start at all.
    #
    # ── THE DEADLOCK, MEASURED ON ernst 2026-08-28 ─────────────────────────
    #
    # The nixpkgs lidarr module ships its OWN tmpfiles rule:
    #
    #     d /var/lib/lidarr/.config/Lidarr 0700 lidarr media -
    #
    # To honour it, systemd-tmpfiles must first create the intermediate
    # `.config` — and it creates missing PARENTS as root:root 0755, not as the
    # rule's owner.  Having done so it then refuses to descend through the
    # ownership change it just created:
    #
    #     Detected unsafe path transition /var/lib/lidarr (owned by lidarr)
    #     → /var/lib/lidarr/.config (owned by root) during canonicalization
    #
    # So the rule leaves behind a root-owned `.config`, never creates `Lidarr`
    # inside it, and never recovers on a later run — the transition is just as
    # unsafe next boot.  Lidarr, running as uid 3017, then cannot create its
    # data directory and dies on startup:
    #
    #     System.UnauthorizedAccessException: Access to the path
    #     '/var/lib/lidarr/.config/Lidarr' is denied.
    #
    # The exception surfaces inside Sentry's transport initialisation, which
    # sends anyone reading the stack trace looking for a network or telemetry
    # problem.  It is a plain permission error two frames further down.
    #
    # ── WHY sonarr DOES NOT HIT THIS ──────────────────────────────────────
    #
    # Its `/var/lib/sonarr/.config` is owned by sonarr, created by Sonarr
    # itself on a much earlier deploy before any such rule existed.  The
    # deadlock only bites a service whose state directory is EMPTY the first
    # time tmpfiles runs — i.e. exactly a newly added one, which is why this
    # was invisible until M14.
    #
    # ── THE FIX IS TO PRE-EMPT THE PARENT, NOT TO FIGHT THE MODULE ────────
    #
    # Creating `.config` here, owned by lidarr, means there is no ownership
    # transition for tmpfiles to object to, and the module's own rule then
    # completes normally on the same run.  This declares a path NOTHING ELSE
    # declares (the module owns `.config/Lidarr`, this owns `.config`), so it
    # does not reintroduce the two-declarations-take-turns problem the
    # MediathekArr note above warns about.
    "d ${stateRoot}/lidarr/.config 0700 ${toString lidarrUid}         ${toString mediaGid}    -"
    "d ${stateRoot}/soularr        0700 ${toString soularrUid}        ${toString mediaGid}    -"
    "d ${stateRoot}/kapowarr       0700 ${toString kapowarrUid}       ${toString mediaGid}    -"
    "d ${stateRoot}/questarr       0700 ${toString questarrUid}       ${toString questarrGid} -"
    "d ${stateRoot}/audiobookshelf 0700 ${toString audiobookshelfUid} ${toString mediaGid}    -"

    # 2026-09-08 — Komga's and Navidrome's state, on zdata for the reason
    # everything else here is: zroot ROLLS BACK on every boot (invariant #7),
    # and both of these hold a SQLite database that is not cheap to rebuild.
    #
    # Navidrome's especially: the DB is not just an index of the library, it
    # holds play counts, star ratings, playlists, per-user progress and the
    # per-player transcoding assignments.  Rebuilding it from a rescan
    # recovers the music and loses everything the household actually created.
    # That is also why it gets a backup schedule of its own — a rollback is
    # not the only way to lose it, and ZFS snapshots of this dataset are NOT
    # currently running (see the note in the navidrome block below).
    "d ${stateRoot}/komga          0700 ${toString komgaUid}          ${toString mediaGid}    -"
    "d ${stateRoot}/navidrome      0700 ${toString navidromeUid}      ${toString mediaGid}    -"

    # ── THE BACKUP DIRECTORY IS NOT OPTIONAL, AND UPSTREAM DOES NOT MAKE IT ──
    #
    # navidrome.service failed to start on the first deploy with:
    #
    #   Failed to set up mount namespacing:
    #     /var/lib/navidrome/backup: No such file or directory
    #   Failed at step NAMESPACE ... status=226/NAMESPACE
    #
    # AN UPSTREAM GAP, not a mistake in the settings above.  nixpkgs' module
    # adds `Backup.Path` to the unit's `BindPaths` whenever the setting exists:
    #
    #   BindPaths = optional (cfg.settings ? DataFolder) …
    #            ++ optional (cfg.settings ? CacheFolder) …
    #            ++ optional (cfg.settings ? Backup.Path) cfg.settings.Backup.Path;
    #
    # but its `tmpfiles.settings.navidromeDirs` creates only DataFolder,
    # CacheFolder and MusicFolder.  `BindPaths` requires the source to EXIST —
    # systemd will not create it — so merely CONFIGURING backups produces a
    # unit that can never start.  Navidrome would create the directory itself
    # at first backup, but it never gets to run.
    #
    # Created here rather than with a `systemd.tmpfiles` rule inside the
    # container because /var/lib/navidrome IS this directory through the bind
    # mount, and the host-side rules already run before container@arr starts.
    # One place, and it is the place the dataset actually lives.
    #
    # 0700 like its parent: backups of the database are exactly as sensitive
    # as the database.
    "d ${stateRoot}/navidrome/backup 0700 ${toString navidromeUid} ${toString mediaGid} -"

    # M17 — Bindery's state.  Owned by the service uid so there is no
    # ownership transition on the FIRST run for tmpfiles to deadlock on —
    # the lidarr lesson above, applied pre-emptively to a service whose
    # state directory is guaranteed empty on deploy day.
    "d ${stateRoot}/bindery        0700 ${toString binderyUid}        ${toString mediaGid}    -"

    # THE MUSIC LIBRARY — Lidarr's import TARGET, and it is inside /srv/media
    # because that is the hardlink domain.
    #
    # It sits beside library/{movies,tvshows}, which containers/jellyfin.nix
    # declares.  This one is declared HERE rather than there, following the
    # same rule the MediathekArr note above states: one declaration per path,
    # and the path belongs to the file that owns the service which writes it.
    # Jellyfin does not serve music in this deployment; Lidarr is the only
    # thing that writes here.
    "d /srv/media/library/music 2770 root ${toString mediaGid} -"

    # ── THE BEETS STAGING TREE ──────────────────────────────────────────────
    #
    # sldl (containers/../microvms/wg-qbittorrent.nix) writes playlist
    # downloads as `<Playlist>/<whatever the uploader named it>` — flat, no
    # artist directories, filenames like `11-iriepathie-lang_her.mp3`.
    #
    # MEASURED BEFORE BUILDING ANY OF THIS (2026-10-03, 239 files): 236 carry
    # artist AND title AND album, 1 lacks album, 2 carry nothing.  So the
    # FILENAMES are junk and the TAGS are good, which is exactly the case a
    # tag-driven organiser solves and a path-driven one cannot.  beets reads
    # those tags and writes `Artist/Album/Title` here.
    #
    # ── THE DESTINATION IS NAVIDROME, NOT LIDARR.  CORRECTED 2026-10-04 ─────
    #
    # An earlier revision of this comment said beets wrote "the shape Lidarr's
    # Library Import consumes natively", and that this kept Lidarr the only
    # writer of /srv/media/library/music.  BOTH CLAIMS WERE WRONG and were
    # believed for a day:
    #
    #   1. THIS LIDARR HAS NO LIBRARY IMPORT.  That is a Sonarr/Radarr
    #      feature.  A full scan of the 3.1.0.4875 UI bundle's routes gives
    #      `/add/search` and `/unmapped` and nothing else — `/add/import` is a
    #      404.
    #   2. LIDARR CANNOT MATCH THIS CORPUS IN BULK ANYWAY.  Its
    #      `/api/v1/manualimport` against the staged tree returned all 255
    #      files with `"albumReleaseId": 0` and `"tracks": []` — nothing
    #      identified, every file needing an artist and album chosen by hand.
    #      That is Lidarr being artist/album-shaped meeting a corpus of ~219
    #      artists holding one track each; it is not a misconfiguration.
    #
    # So the staged tree is copied into /srv/media/library/music, which
    # Navidrome serves and indexes BY TAGS rather than by path.  Lidarr lists
    # the result under `/unmapped` and leaves it alone, because it manages
    # only artists it tracks.  Lidarr stays the right tool for the handful of
    # artists worth monitoring — added through `/add/search`, after which it
    # adopts their files out of the same root folder.
    #
    # The procedure, including the permission step that `cp` gets wrong, is
    # docs/guides/music-pipeline.md.
    #
    # Inside /srv/media, so the copy into the library stays within one dataset
    # (invariant #2 — the domain is the dataset).
    "d /srv/media/staging          2770 root ${toString mediaGid} -"
    "d ${beetsStagingRoot}         2770 root ${toString mediaGid} -"
    "d ${beetsStateDir}            0770 root ${toString mediaGid} -"

    # KAPOWARR'S DOWNLOAD TREE, and — like MediathekArr's — it is NOT under
    # ${stateRoot}.  It is media: Kapowarr downloads .cbz files here and then
    # files them into its own library, and both ends must be inside the one
    # dataset or the move degrades into a copy.
    "d /srv/media/torrents/comics 2770 root ${toString mediaGid} -"
    "d /srv/media/library/comics  2770 root ${toString mediaGid} -"

    # M17 — BINDERY'S TREES, the same shape for the same reason: download and
    # library ends BOTH inside /srv/media, so the import is a rename (or a
    # hardlink) on one dataset rather than a copy across two (invariant #2).
    "d /srv/media/torrents/books  2770 root ${toString mediaGid} -"
    "d /srv/media/library/books   2770 root ${toString mediaGid} -"

    # The AUDIOBOOK download tree, a SIBLING of torrents/books rather than a
    # subdirectory of it — same argument slskd's and sldl's trees get in
    # machines/ernst/microvms/wg-qbittorrent.nix: "which client wrote this"
    # is a question someone will ask of a stuck file at 0200.
    #
    # It is here under /srv/media and NOT under /srv/audiobooks, even though
    # the finished audiobooks land on the latter.  The one-dataset invariant
    # cannot be satisfied for this path in any case: BINDERY_AUDIOBOOK_DIR is
    # ${audiobooksRoot}/library, a different dataset, so Bindery's audiobook
    # import is a cross-dataset COPY wherever the download sits.  Given that,
    # the download tree stays with the download client's other trees, and
    # /srv/audiobooks keeps the read-only posture the unit below argues for.
    #
    # The comment that used to sit here said "Bindery's audiobook capability
    # is deliberately left unrouted".  That was falsified on 2026-09-27 and
    # the unit below has said so since; this removes the last copy of the
    # claim rather than leaving the two statements to contradict each other.
    "d /srv/media/torrents/audiobooks 2770 root ${toString mediaGid} -"

    # AUDIOBOOKSHELF'S TREE, on its own dataset.
    #
    # Three directories, and the split is what makes Storyteller and
    # Audiobookshelf complementary rather than overlapping:
    #
    #   library/      finished audiobooks.  Audiobookshelf scans this.
    #   ebooks/       the DRM-free ebook halves, staged by hand.
    #
    #                 A WARNING EARNED ON 2026-09-17: this directory is a
    #                 STAGING POOL AND NOTHING SCANS IT.  Storyteller takes its
    #                 input through its own web UI, so anything left here is
    #                 inert until a human picks it up — and the entire Calibre
    #                 library restored from the old Arch server (4472 books,
    #                 12.4 GB) sat in it unnoticed for weeks precisely because
    #                 this comment reads like a description of a pipeline.  It
    #                 is not one.  Those books now live in CWA's library at
    #                 /srv/media/library/calibre; see containers/cwa.nix, "THE
    #                 LIBRARY IS NO LONGER EMPTY".  The directory is empty
    #                 again and still belongs to Storyteller.
    #   storyteller/  Storyteller's ENTIRE /data volume — its database, the
    #                 originals it has been given, and the synced EPUB3s it
    #                 produces.  It is here rather than under ${stateRoot}
    #                 BECAUSE IT IS NOT PURELY STATE: the outputs are library
    #                 content, and putting them on the same dataset as
    #                 Audiobookshelf's library is what lets ABS be pointed at
    #                 them without a copy.
    #
    # A NOTE ON WHAT IS *NOT* CLAIMED HERE.  Storyteller takes its input
    # through its own web UI and writes its output inside /data; there is no
    # verified watch-a-directory hand-off between it and Audiobookshelf, and
    # this repo does not pretend otherwise.  Adding the produced files as an
    # Audiobookshelf library is an lgo UI step in the PR body.  Upstream ships
    # exactly ONE volume, and mounting it somewhere useful is the whole of the
    # integration.
    #
    # THESE THREE ARE NOT tmpfiles RULES — see audiobooks-tree.service below.
    # A tmpfiles rule here would create them on zroot whenever the dataset is
    # not mounted, which is exactly the failure that took ernst down on
    # 2026-08-28 (in its other direction).

    # QUESTARR'S GAME TREE, on zdata/games — a THIRD dataset, and deliberately
    # not /srv/media.
    #
    # Games are not media and have no hardlink relationship with anything in
    # the library; /srv/games already exists for exactly this kind of content
    # (see machines/ernst/disko.nix, where it carries exec=on because game
    # binaries must run — which is precisely why nothing else in this container
    # is allowed near it).
    #
    # 0750 questarr:questarr, NOT 2770 root:media.  Questarr is the only writer
    # and the only reader, so there is no group to share with — and giving
    # `media` a foothold on the one dataset on this pool where files are
    # ALLOWED TO EXECUTE would be the worst place in the fleet to do it.
    "d /srv/games/questarr 0750 ${toString questarrUid} ${toString questarrGid} -"
  ];

  ##############################################################################
  # The /srv/audiobooks tree — a UNIT, not tmpfiles rules, and the distinction
  # is what stops this dataset taking the machine down a second time.
  #
  # ── WHY THIS IS NOT A tmpfiles RULE ──────────────────────────────────────
  #
  # tmpfiles runs early and unconditionally.  If zdata/audiobooks is not
  # mounted — not created yet, wrong `mountpoint` property, pool imported late
  # — a tmpfiles rule cheerfully creates /srv/audiobooks/{library,ebooks} ON
  # zroot, which ROLLS BACK on every boot (invariant #7).  Audiobookshelf would
  # then scan an empty library, write cover art into it, and lose the lot at
  # the next reboot, with nothing anywhere saying why.
  #
  # containers/jellyfin.nix and containers/tubesync.nix already make this
  # argument for their own download trees ("a tmpfiles rule alone races the
  # mount") and pair theirs with an ordered oneshot.  This is the same pattern
  # with one addition: it VERIFIES the mount rather than merely ordering after
  # it, because `Requires=` on a mount marked `nofail` does not fail the way an
  # unqualified reader would expect.
  #
  # ── WHY IT FAILS INSTEAD OF FIXING ITSELF ────────────────────────────────
  #
  # It could `zfs set mountpoint=legacy` and mount the dataset itself.  It
  # deliberately does not: a unit that silently repairs storage layout is a
  # unit that hides the fact that the layout was wrong, and the next surprise
  # is a dataset nobody meant to create being adopted into the tree.  Failing
  # loudly, in a unit named after the problem, is the M13/`clanarchy-
  # impermanence-check` precedent — that one exists because ernst was silently
  # not impermanent for a month.
  #
  # ── BLAST RADIUS, WHICH IS THE WHOLE POINT ───────────────────────────────
  #
  # `before`, NOT `requiredBy`, on container@arr.  If this unit fails, the arr
  # container STILL STARTS: Sonarr, Radarr, Prowlarr, Bazarr and the rest have
  # nothing to do with audiobooks and must not go down because a library
  # dataset is missing.  Audiobookshelf inside it will show an empty library,
  # which is the visible-and-harmless failure this is aiming for.
  #
  # Storyteller is the exception and is handled in containers/storyteller.nix:
  # its ENTIRE /data lives on this dataset, so `storyteller-data-dir.service`
  # really does require the mount and `podman-storyteller` really is blocked by
  # it.  A Storyteller that starts without its database is not a degraded
  # Storyteller, it is a new empty one.
  #
  # On 2026-08-28 the machine went to emergency — no sshd, no containers, no
  # microvm — because this dataset's mount failed and a `fileSystems` entry is
  # `RequiredBy` local-fs.target by default.  `nofail` in machines/ernst/disko.nix
  # is the other half of the fix and carries the full account.
  ##############################################################################
  systemd.services.audiobooks-tree = {
    description = "Verify zdata/audiobooks is mounted and create its tree";
    wantedBy = [ "multi-user.target" ];
    after    = [ "srv-audiobooks.mount" ];
    # Ordering only.  See BLAST RADIUS above — a failure here must not stop
    # the arr container.
    before   = [ "container@arr.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.util-linux pkgs.coreutils ];
    script = ''
      set -eu

      # findmnt, not `mountpoint`: this has to check WHAT is mounted, not just
      # that something is.  With `nofail` the mount unit can fail while
      # /srv/audiobooks still exists as an ordinary directory on zroot, and
      # that is precisely the case a bare mountpoint test would pass.
      src=$(findmnt --noheadings --output SOURCE --target ${audiobooksRoot} || true)
      fstype=$(findmnt --noheadings --output FSTYPE --target ${audiobooksRoot} || true)

      if [ "$src" != "zdata/audiobooks" ] || [ "$fstype" != "zfs" ]; then
        echo "audiobooks-tree: ${audiobooksRoot} is NOT zdata/audiobooks." >&2
        echo "  found: source='$src' fstype='$fstype'" >&2
        echo "" >&2
        echo "  Refusing to create the tree, because doing so would put the" >&2
        echo "  audiobook library on zroot, which rolls back on every boot." >&2
        echo "" >&2
        echo "  The dataset must exist AND carry mountpoint=legacy — a ZFS" >&2
        echo "  dataset without it cannot be mounted by mount(8) at all:" >&2
        echo "" >&2
        echo "    zfs create -o mountpoint=legacy -o recordsize=1M \\" >&2
        echo "      -o exec=off -o setuid=off -o devices=off -o atime=off \\" >&2
        echo "      -o com.sun:auto-snapshot=true zdata/audiobooks" >&2
        echo "" >&2
        echo "  If it exists already:  zfs set mountpoint=legacy zdata/audiobooks" >&2
        echo "  Then:                  systemctl start srv-audiobooks.mount" >&2
        echo "  See docs/guides/ernst-zdata-datasets.md." >&2
        exit 1
      fi

      # 2770 root:media, matching the rest of the shared trees: setgid so
      # everything created inside inherits the group, group-writable so
      # Audiobookshelf (in the arr container) and Storyteller (in its own
      # podman netns, uid 3022) can both manage what they find.
      install -d -o root -g ${toString mediaGid} -m 2770 ${audiobooksRoot}
      install -d -o root -g ${toString mediaGid} -m 2770 ${audiobooksRoot}/library
      install -d -o root -g ${toString mediaGid} -m 2770 ${audiobooksRoot}/ebooks
    '';
  };

}
