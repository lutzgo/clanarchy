# machines/ernst/containers/arr/common.nix
#
# The `arr` container itself: its veth, its storage, its firewall, its users,
# and `arr-api-keys` — the unit that extracts every service's API key at
# start so the rest of the stack can be configured declaratively.
#
# ── ONE CONTAINER, SIX FILES ────────────────────────────────────────────────
#
# This file DECLARES containers.arr. The five beside it add to it:
#
#     ./video.nix      sonarr, radarr, bazarr, seerr, recyclarr
#     ./indexers.nix   prowlarr, flaresolverr, umlautadaptarr, mediathekarr
#     ./music.nix      lidarr, soularr, navidrome, the beets staging tool
#     ./books.nix      audiobookshelf, komga, kapowarr, questarr, bindery
#     ./lifecycle.nix  janitorr, cleanuparr, scraparr
#     ./ids.nix        the numbers, addresses and paths they share (data)
#
# `containers.<name>.config` is a module option, so those five merge into the
# one declared here — the same mechanism containers/crowdsec.nix uses to put
# CrowdSec inside Traefik's namespace, and the one containers/homepage.nix
# already used to add a service to THIS container before the split.
#
# ── WHY IT WAS SPLIT ────────────────────────────────────────────────────────
#
# It was one 6,218-line file, which is about 87k tokens: two and a half times
# the context window of the model this repo is meant to be workable with, and
# past the point where a human finds anything either. The split is by MEDIA
# DOMAIN rather than by mechanism because that is how these services were
# added and how they are changed — a film-pipeline change touches Sonarr,
# Radarr and Bazarr together and nothing else.
#
# The service definitions themselves were MOVED, not rewritten. Each file
# re-exposes the handful of shared names its own blocks use (`ids.ports.sonarr`
# aliased back to `sonarrPort`), so the bodies are identical to what they were
# and the whole split is verifiable as a no-op: ernst's derivation hash is
# unchanged by it.
#
# ── THE SYSCALL FILTER IS APPLIED PER FILE, AND THAT IS DELIBERATE ──────────
#
# `ids.syscallFilter` is applied by each file to its own units. common.nix
# must NOT map it over `config.systemd.services` to catch them all: the
# attrset being read would be the one being defined, which is infinite
# recursion at eval. If a global application is ever wanted it needs an
# explicit list of unit names, not a fold over the service set.
{ config, lib, pkgs, inputs, ... }:
let
  ids = import ./ids.nix;

  # The old flat names, so every block below is unchanged from the file it
  # came out of. See the header.
  inherit (ids) stateRoot audiobooksRoot;
  arrSyscallFilter = ids.syscallFilter;
  arrSecretsDir    = ids.secretsDirs.arrApiKeys;
  arrMac   = "02:00:00:90:00:05";
  vlanId   = 90;
  vethName = "vb-arr";
  mediaGid = ids.gids.media;
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
  sonarrPort = ids.ports.sonarr;
  radarrPort = ids.ports.radarr;
  prowlarrPort = ids.ports.prowlarr;
  flaresolverrPort = ids.ports.flaresolverr;
  bazarrPort = ids.ports.bazarr;
  cleanuparrPort = ids.ports.cleanuparr;
  jellyseerrPort = ids.ports.jellyseerr;
  scraparrPort = ids.ports.scraparr;
  janitorrPort = ids.ports.janitorr;
  lidarrPort = ids.ports.lidarr;
  kapowarrPort = ids.ports.kapowarr;
  questarrPort = ids.ports.questarr;
  audiobookshelfPort = ids.ports.audiobookshelf;
  binderyPort = ids.ports.bindery;
  komgaPort = ids.ports.komga;
  navidromePort = ids.ports.navidrome;
  mediathekarrDownloaderPort = ids.ports.mediathekarrDownloader;
  umlautadaptarrPort         = ids.ports.umlautadaptarr;
  umlautadaptarrProxyPort    = ids.ports.umlautadaptarrProxy;
  traefikAddr    = ids.peers.traefik;
  monitoringAddr = ids.peers.monitoring;
  massAddr       = ids.peers.mass;
  beetsStagingRoot = ids.paths.beetsStaging;
  beetsStateDir    = ids.paths.beetsState;
  janitorrSecretsDir  = ids.secretsDirs.janitorr;
  navidromeSecretsDir = ids.secretsDirs.navidrome;
  soularrSecretsDir   = ids.secretsDirs.soularr;
in
{
  ##############################################################################
  # Host-side wiring.
  ##############################################################################

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

  # Host side of the container's veth — a VLAN-90 port on br0.
  #
  # There is deliberately NO `networking.firewall.allowedTCPPorts` here.  The
  # three web UIs are opened inside the container's own netns (below); on the
  # host they are not ports at all.  Reachability from the management VLANs is
  # the UDM-Pro's job — ledger row L4 in docs/ledger.md.
  #
  # KeepMaster, not Bridge=: nspawn creates this link AND enslaves it to br0
  # itself (--network-bridge=br0), so Bridge= would make networkd fight nspawn
  # over the master.  KeepMaster leaves the enslavement alone while still
  # applying the [BridgeVLAN] section, which is the only thing wanted from it.
  #
  # No L3 of its own: a bridge port carries no address, and IPv6AcceptRA on a
  # port would have it answer router advertisements meant for the container.
  #
  # 60- prefix so it sorts after the 50-* topology units in
  # machines/ernst/networking.nix and well ahead of the 99-* wildcards.
  systemd.network.networks."60-${vethName}" = {
    matchConfig.Name = vethName;
    networkConfig = {
      KeepMaster          = true;
      LinkLocalAddressing = "no";
      IPv6AcceptRA        = false;
    };
    bridgeVLANs = [ { VLAN = vlanId; PVID = vlanId; EgressUntagged = vlanId; } ];
    # A bridge port's terminal operational state is "enslaved"; it never
    # becomes routable, and waiting for that would hang boot.
    linkConfig.RequiredForOnline = "enslaved";
  };

  # Re-assert the VLAN membership after nspawn has created the veth.
  #
  # Same real race as vb-jellyfin: networkd applies [BridgeVLAN] only once it
  # observes the link's master, and nspawn sets that master out of band from
  # container@arr.service.  With DefaultPVID = "none" on br0 a miss is
  # fail-CLOSED — no connectivity at all — rather than fail-open onto VLAN 50,
  # which is the right failure but still presents as "the arr is down".
  #
  # `bridge vlan add` is idempotent, so this agrees with networkd rather than
  # competing with it.  The "-" prefix is deliberate: a backstop must not
  # become a new failure mode, so `bridge` exiting non-zero (link already gone
  # during a restart, say) must not fail the container and restart-loop it.
  #
  # `bridge vlan show dev vb-arr` remains the check — do not trust silence
  # from either mechanism.  networkd won unaided for both vb-jellyfin and
  # tap-vpn across the 2026-08-20 reboot; that is not a guarantee.
  systemd.services."container@arr".serviceConfig.ExecStartPost = [
    "-${pkgs.iproute2}/bin/bridge vlan add dev ${vethName} vid ${toString vlanId} pvid untagged"
  ];

  ##############################################################################
  # The container itself.
  ##############################################################################
  containers.arr = {
    autoStart = true;
    ephemeral = false;          # state persists via the bind mounts below

    # Own netns, own L2 identity.  See the file header for why this is a veth
    # on br0 and not a macvlan or a tap.
    privateNetwork  = true;
    hostBridge      = "br0";
    localMacAddress = arrMac;

    bindMounts = {
      # THE MEDIA TREE, read-write, at the IDENTICAL PATH.
      #
      # Identical on all three sides — host, this container, and M3's guest —
      # which is what lets Sonarr/Radarr take qBittorrent's reported save path
      # verbatim and find the same inode.  Do not "tidy" this into
      # /media/... or /data/...: the moment the strings differ, every import
      # needs a Remote Path Mapping in the UI, and a missing one presents as a
      # permissions error rather than as a path error.
      #
      # The whole dataset is bound rather than library/ and torrents/
      # separately, and that is load-bearing too: two separate binds of two
      # subdirectories are two mounts, and Sonarr checks `st_dev` before it
      # tries to hardlink.  One bind, one st_dev, one hardlink domain.
      "/srv/media" = {
        hostPath   = "/srv/media";
        isReadOnly = false;
      };

      # Per-service state, remapped to each package's upstream default path so
      # the packaged units need no dataDir override.
      "/var/lib/sonarr" = {
        hostPath   = "${stateRoot}/sonarr";
        isReadOnly = false;
      };
      "/var/lib/radarr" = {
        hostPath   = "${stateRoot}/radarr";
        isReadOnly = false;
      };
      "/var/lib/prowlarr" = {
        hostPath   = "${stateRoot}/prowlarr";
        isReadOnly = false;
      };

      # ── beets' CATALOGUE, AND IT IS NOT OPTIONAL STATE ─────────────────────
      #
      # Shipped missing in #269 and found on 2026-10-04.  `beetsStateDir` is a
      # HOST path, and only `/srv/media` was mounted in — so
      # `nixos-container run arr -- music-stage` wrote library.db to the
      # container's PRIVATE /srv/state/beets, on zroot, which rolls back.
      #
      # THE SYMPTOM IS NOT AN EMPTY CATALOGUE, IT IS DUPLICATE AUDIO.  With no
      # record of what it already staged, beets cannot apply
      # `duplicate_action: skip`; it copies the file again and disambiguates
      # the name, so a second run of the same CSVs produced
      # `Elephant Gun.flac` AND `Elephant Gun.1.flac`.  At ten thousand tracks
      # over weeks of re-runs that is the whole library, several times over.
      #
      # The path is the same inside and out, unlike the `/var/lib/<svc>`
      # entries above, because `music-stage`'s config is generated from
      # `beetsStateDir` and the two must agree.
      "${beetsStateDir}" = {
        hostPath   = beetsStateDir;
        isReadOnly = false;
      };

      # M12.  Same pattern: each service's UPSTREAM DEFAULT state path, so
      # nothing needs a dataDir override.
      #
      # UmlautAdaptarr has no entry, and that is not an omission — it has no
      # persistent state at all.  See its block below.
      "/var/lib/bazarr" = {
        hostPath   = "${stateRoot}/bazarr";
        isReadOnly = false;
      };
      "/var/lib/cleanuparr" = {
        hostPath   = "${stateRoot}/cleanuparr";
        isReadOnly = false;
      };
      "/var/lib/mediathekarr" = {
        hostPath   = "${stateRoot}/mediathekarr";
        isReadOnly = false;
      };

      # ── M13 ──────────────────────────────────────────────────────────────
      #
      # /var/lib/SEERR, not /var/lib/jellyseerr, and the name change is not
      # cosmetic — it is a 26.05 breaking change this file has to land on the
      # right side of.
      #
      # nixpkgs RENAMED the module: `services.jellyseerr` is now an alias for
      # `services.seerr` (mkRenamedOptionModule), the package attribute is
      # `seerr`, and the module picks its state path from stateVersion:
      #
      #   stateVersion >= 26.05   StateDirectory=seerr,      /var/lib/seerr
      #   stateVersion <  26.05   StateDirectory=jellyseerr, /var/lib/jellyseerr/config
      #
      # This container declares stateVersion = "26.05", so the NEW path is the
      # one that applies and this bind has to match it or the module writes to
      # a directory nothing preserves.
      #
      # The zdata side keeps the name `jellyseerr` deliberately: on the pool
      # these directories are read by a human doing `ls -n /srv/state`, and
      # "jellyseerr" is what the service is called everywhere else in this
      # repo — in the Traefik router, in the DNS name, and in the uid table.
      "/var/lib/seerr" = {
        hostPath   = "${stateRoot}/jellyseerr";
        isReadOnly = false;
      };

      # Janitorr's state.  Small — it keeps no library database, only its own
      # bookkeeping — but it must survive a container restart, and zroot rolls
      # back (invariant #7).
      #
      # Its CONFIG does not live here: application.yml is rendered into a
      # tmpfs under /run on every start, because it contains four API keys and
      # a password.  See the janitorr-config block.
      "/var/lib/janitorr" = {
        hostPath   = "${stateRoot}/janitorr";
        isReadOnly = false;
      };

      # Scraparr has no bind mount, and that is not an omission — it has no
      # persistent state at all.  Same situation as UmlautAdaptarr above.

      # Janitorr's Jellyfin credentials, READ-ONLY, at the same path as on the
      # host.  One of the two bind mounts in this file that carry a secret.
      "${janitorrSecretsDir}" = {
        hostPath   = janitorrSecretsDir;
        isReadOnly = true;
      };

      # The other one: slskd's API key, for Soularr.  Same shape, same reason —
      # a clan var's own /run/secrets path does not exist inside the container.
      "${soularrSecretsDir}" = {
        hostPath   = soularrSecretsDir;
        isReadOnly = true;
      };

      # The THIRD: Navidrome's Prometheus password.  Same shape and the same
      # reason as the two above — see navidromeSecretsDir in the let block.
      "${navidromeSecretsDir}" = {
        hostPath   = navidromeSecretsDir;
        isReadOnly = true;
      };

      # ── M14 ──────────────────────────────────────────────────────────────
      #
      # Per-service state, each at its package's upstream default path so
      # nothing needs a dataDir override.
      #
      # LIDARR'S IS THE ONE WITH A TWIST.  The servarr module's dataDir
      # defaults to `/var/lib/lidarr/.config/Lidarr` — NOT `/var/lib/lidarr`
      # like sonarr's and radarr's — and, unlike sonarr's, its unit has NO
      # StateDirectory at all.  So the bind is the HOME directory and Lidarr
      # creates `.config/Lidarr` inside it on first start.  Binding the deeper
      # path instead would work until Lidarr wrote anything else into its home.
      "/var/lib/lidarr" = {
        hostPath   = "${stateRoot}/lidarr";
        isReadOnly = false;
      };
      "/var/lib/soularr" = {
        hostPath   = "${stateRoot}/soularr";
        isReadOnly = false;
      };
      "/var/lib/kapowarr" = {
        hostPath   = "${stateRoot}/kapowarr";
        isReadOnly = false;
      };
      "/var/lib/questarr" = {
        hostPath   = "${stateRoot}/questarr";
        isReadOnly = false;
      };
      "/var/lib/audiobookshelf" = {
        hostPath   = "${stateRoot}/audiobookshelf";
        isReadOnly = false;
      };

      # 2026-09-08.  Komga's and Navidrome's state, remapped onto each
      # module's own default path so neither needs a directory override —
      # the same trick lidarr's bind above uses, and jellyfin.nix for
      # /var/lib/jellyfin.
      #
      #   komga      services.komga.stateDir defaults to /var/lib/komga
      #              (verified by evaluating the option).
      #   navidrome  the module hard-codes WorkingDirectory=/var/lib/navidrome
      #              and StateDirectory=navidrome, and DataFolder defaults to
      #              the WorkingDirectory.  So this bind is what puts the
      #              database on zdata, and DataFolder is deliberately LEFT
      #              UNSET below rather than pointed somewhere else.
      "/var/lib/komga" = {
        hostPath   = "${stateRoot}/komga";
        isReadOnly = false;
      };
      "/var/lib/navidrome" = {
        hostPath   = "${stateRoot}/navidrome";
        isReadOnly = false;
      };

      # ── M17 ──────────────────────────────────────────────────────────────
      #
      # Bindery's SQLite database and image cache.  Both paths inside are set
      # EXPLICITLY in its unit — BINDERY_DB_PATH does not follow
      # BINDERY_DATA_DIR (measured; see ./pkgs/bindery.nix), so leaving either
      # unset points the service at the compiled-in /config default and it
      # dies on mkdir at first start.
      "/var/lib/bindery" = {
        hostPath   = "${stateRoot}/bindery";
        isReadOnly = false;
      };

      # Audiobookshelf's LIBRARY, on its own dataset.  Read-write: it writes
      # cached cover art and, when asked, renames files it has scanned.
      #
      # At the identical path on both sides, like /srv/media — for the same
      # reason, and here it matters for a second one: Storyteller writes into
      # ${audiobooksRoot}/synced from a DIFFERENT container, and the two only
      # agree about what a path means if neither of them rewrites it.
      "${audiobooksRoot}" = {
        hostPath   = audiobooksRoot;
        isReadOnly = false;
      };

      # Questarr's game tree.  ONLY the subdirectory it owns, not /srv/games.
      #
      # This is the one bind mount in this file that is deliberately narrower
      # than the dataset it comes from, and the reason is in the tmpfiles rule
      # above: /srv/games carries exec=on, and it also holds the HTPC's Steam
      # library, which has nothing to do with this container.  Binding the
      # whole dataset would hand every service in this netns — prowlarr,
      # flaresolverr, an opaque .NET indexer proxy — a writable, EXECUTABLE
      # tree.  One subdirectory is what Questarr needs.
      "/srv/games/questarr" = {
        hostPath   = "/srv/games/questarr";
        isReadOnly = false;
      };
    };

    ############################################################################
    # NixOS config for the container's own root filesystem.
    ############################################################################
    config = { config, pkgs, lib, ... }: {
      system.stateVersion = "26.05";

      # Matches the host.  Unlike Jellyfin, these three are calendar- and
      # schedule-driven: Sonarr's air dates, the RSS sync interval and every
      # timestamp in the UI are rendered in the container's local time, and a
      # container that silently defaults to UTC makes "why did this grab an
      # hour late" a two-hour question.
      time.timeZone = "Europe/Berlin";

      ##########################################################################
      # Networking.  The container owns its netns, so it owns all of this.
      ##########################################################################

      # services.resolved asserts !networking.useHostResolvConf, and with a
      # private netns the host's resolv.conf is a stale snapshot of someone
      # else's resolver anyway.  virtualisation/container-config.nix sets it
      # `mkDefault true`, so a plain `false` wins without mkForce.
      networking.useHostResolvConf = false;

      networking.useNetworkd  = true;
      services.resolved.enable = true;

      # eth0 — renamed from host0 by container-init before stage 2 runs.
      #
      # ADDRESS: DHCP, reserved on the UDM-Pro against the pinned MAC.
      # RESOLVER: declared, not inherited.  UseDNS/UseDomains = false so a
      # future change to the Services network's DHCP options cannot silently
      # move the arr off Technitium.  "~." is a ROUTING domain, so every lookup
      # goes to 10.0.5.3 and Technitium's blocklists and logging cover this
      # container too; "skynet.lan" is the bare-hostname search suffix.
      #
      # Check on ernst with:  nixos-container run arr -- resolvectl status eth0
      systemd.network.networks."10-eth0" = {
        matchConfig.Name = "eth0";
        networkConfig = {
          DHCP         = "ipv4";
          DNS          = "10.0.5.3";
          Domains      = "~. skynet.lan";
          IPv6AcceptRA = false;
        };
        dhcpV4Config = {
          UseDNS     = false;
          UseDomains = false;
        };
        linkConfig.RequiredForOnline = "routable";
      };

      # 20 s, for the reason machines/ernst/containers/jellyfin.nix explains at
      # length: container@arr is Type=notify with TimeoutStartSec=1min, so a
      # wait-online that blocks for the stock 120 s turns a missing DHCP
      # reservation into a container the host kills and restart-loops, with no
      # reachable state to debug.  At 20 s the container always finishes
      # booting and leaves one obviously failed unit instead.
      systemd.network.wait-online.timeout = 20;

      # The container's own firewall, in its own netns — the only enforcement
      # point in the repo for these ports.  Cross-VLAN reachability is the
      # UDM-Pro's job.
      #
      # One explicit list rather than three `openFirewall = true`s.  The
      # servarr modules are well-behaved (unlike Jellyfin's, they open exactly
      # `settings.server.port` and nothing else), so this is not the safety
      # argument it was in jellyfin.nix — it is that the set of open ports has
      # to be checked against the UDM-Pro rule by a human, and one list in one
      # place is what makes that check take ten seconds.
      #
      # flaresolverrPort (8191) is ABSENT on purpose and must stay absent.  It
      # is a service whose entire API is "fetch this URL for me"; opening it to
      # the Services VLAN would hand every host on that VLAN an SSRF primitive.
      # Prowlarr is in this netns and reaches it on 127.0.0.1.
      #
      # ── M5: THE THREE UIs ARE NOW TRAEFIK-ONLY ────────────────────────────
      #
      # These were `allowedTCPPorts = [ prowlarrPort sonarrPort radarrPort ]`
      # until M5, i.e. open to everything on VLAN 90.  The list is now EMPTY so
      # that nothing grants them unconditionally before the restricted rules
      # below are reached, and access is source-restricted to Traefik.
      #
      # The "one list in one place" argument above still holds — it has just
      # moved down three lines.  The set of reachable ports still has to be
      # checked against the UDM-Pro rule by a human, and it is still one list.
      #
      # Why extraCommands and not the newer extraInputRules: that option is
      # declared unconditionally in firewall-nftables.nix but consumed only
      # when networking.nftables.enable is true, which it is not here.  Setting
      # it would produce no rule and no warning — a bypass protection that
      # silently does not exist.  extraCommands is the iptables backend's own
      # escape hatch and fails loudly if a rule will not insert.
      #
      # PLACEMENT: firewall-iptables.nix's start script emits the
      # allowedTCPPorts accepts, then extraCommands, then the catch-all
      # `-j nixos-fw-log-refuse`.  Appending here therefore lands before the
      # refuse and after everything else.  Nothing is needed in
      # extraStopCommands — the chain is flushed and rebuilt on every start and
      # reload, so these do not accumulate.
      #
      # NOTHING ELSE NEEDED THESE PORTS, which is why the restriction costs
      # nothing: Prowlarr pushes to Sonarr and Radarr on 127.0.0.1, recyclarr
      # reads both APIs on 127.0.0.1, and the *arr reach qBittorrent OUTBOUND.
      # There was never a second inbound client.
      #
      # CONSEQUENCE: `curl http://10.0.90.13:8989` from a laptop now fails, and
      # that is the milestone working.  For debugging, go in through the
      # container, where `lo` is always trusted by the NixOS firewall:
      #     nixos-container run arr -- curl -sS -o /dev/null -w '%{http_code}\n' \
      #       http://localhost:8989/
      #
      # ── M12: THREE MORE PORTS, AND THREE THAT STAY OFF THE LIST ───────────
      #
      # The list below is the only mechanism.  M12's prompt is explicit that a
      # second one must not be added and that extraInputRules in particular
      # must not be reached for — it is declared unconditionally but consumed
      # only under networking.nftables, so it would produce no rule and no
      # warning.  Extending this list is the whole of it.
      #
      # ADDED (a human opens these in a browser, so they go through Traefik):
      #   6767   bazarr        subtitle management, used regularly
      #   11011  cleanuparr    its ENTIRE configuration is its web UI
      #   5007   mediathekarr  the downloader's setup wizard
      #
      # NOT ADDED, and this is the more important half:
      #   8191   flaresolverr            (as before — an SSRF primitive)
      #   5008   mediathekarr indexer    Prowlarr reaches it on 127.0.0.1
      #   5005   umlautadaptarr API      Prowlarr reaches it on 127.0.0.1
      #   5006   umlautadaptarr proxy    ditto
      #
      # The last three matter because those processes bind 0.0.0.0/[::], not
      # localhost — measured 2026-08-26, before this file was written.  Inside
      # this netns that means they are on the veth, and the ONLY thing keeping
      # them off VLAN 90 is that this list does not name them and the chain
      # ends in nixos-fw-log-refuse.  The firewall is load-bearing here, not
      # belt-and-braces.
      #
      # UmlautAdaptarr's proxy port is the one to think hardest about before
      # ever adding it: 5006 is an HTTP PROXY, and an open HTTP proxy on the
      # Services VLAN is the same class of gift as FlareSolverr's 8191.
      #
      # ── M13: ONE MORE THROUGH TRAEFIK, AND A SECOND SOURCE ────────────────
      #
      # ADDED TO THE TRAEFIK LIST:
      #   5055   jellyseerr    the household's request UI
      #
      # ADDED TO A NEW, SEPARATE LIST — and the separation is the point:
      #   7100   scraparr      /metrics, scraped by Prometheus at 10.0.90.14
      #
      # Until M13 every rule in this file named one source, so a single
      # concatMapStrings over one port list said everything.  A metrics
      # endpoint has a DIFFERENT client, so it needs a different source — and
      # the two lists are kept apart rather than merged into a list of
      # (source, port) pairs because the question a human actually asks here is
      # "what can Traefik reach?", and that question must stay answerable by
      # reading one list.
      #
      # Scraparr binds 0.0.0.0 by default (GENERAL_ADDRESS, verified in
      # scraparr.py at v3.1.0), so — exactly like UmlautAdaptarr's ports — the
      # ONLY thing keeping 7100 off VLAN 90 generally is that it appears in a
      # source-restricted rule and nowhere else.
      #
      # NOT ADDED, and this is again the more important half:
      #   8978   janitorr      it has NO web UI at all (see the port block at
      #                        the top of this file).  It is additionally bound
      #                        to 127.0.0.1 by its own configuration, so this
      #                        list and the application agree rather than the
      #                        firewall carrying the whole burden.
      networking.firewall.allowedTCPPorts = [ ];
      networking.firewall.extraCommands =
        lib.concatMapStrings (port: ''
          iptables -A nixos-fw -p tcp -s ${traefikAddr}/32 --dport ${toString port} -j nixos-fw-accept
        '') [
          prowlarrPort
          sonarrPort
          radarrPort
          bazarrPort
          cleanuparrPort
          mediathekarrDownloaderPort
          jellyseerrPort

          # ── M14: FOUR MORE THROUGH TRAEFIK ───────────────────────────────
          #
          # All four are browser UIs a human opens more than once, so all four
          # go through the proxy and none of them anywhere else.
          #
          # THE ONE TO THINK ABOUT IS QUESTARR, and it is worth a line because
          # its posture is the umlautadaptarr/scraparr situation again:
          # measured at v1.4.2 by running it, it binds 0.0.0.0 by default and
          # its config dump confirms `"host": "0.0.0.0"`.  Inside this netns
          # that means it is on the veth, on VLAN 90, and the ONLY thing
          # keeping it off that VLAN generally is that this rule names one
          # source and the chain ends in nixos-fw-log-refuse.  The firewall is
          # load-bearing here, not belt-and-braces.
          #
          # Kapowarr and Audiobookshelf are the same shape — both are given
          # --Host/host = 0.0.0.0 explicitly above, deliberately, because the
          # alternative (127.0.0.1) would make them unreachable from Traefik in
          # another container while adding no security this rule does not
          # already provide.
          #
          # SOULARR IS ABSENT AND STAYS ABSENT.  It listens on nothing: its
          # bundled Flask web UI is not packaged at all.  See ./pkgs/soularr.nix.
          lidarrPort
          kapowarrPort
          questarrPort
          audiobookshelfPort

          # ── M17: ONE MORE THROUGH TRAEFIK ────────────────────────────────
          #
          # Bindery is the questarr posture yet again: measured binding
          # 0.0.0.0 (`ss` shows *:8787 with BINDERY_PORT set), so this
          # source-restricted rule is the ONLY thing keeping it off VLAN 90
          # generally.  Load-bearing, not belt-and-braces.  Its API demands a
          # key (401 without one, measured) — defence the three above don't
          # all have, noted but NOT leaned on.
          binderyPort

          # ── 2026-09-08: TWO MORE THROUGH TRAEFIK, AND THESE TWO FACE THE ──
          #    INTERNET
          #
          # Same rule, same source restriction, but the consequence is not the
          # same and it should not be read as routine.  Every other port in
          # this list is reachable from the LAN through a Traefik router that
          # names `websecure` only.  Komga and Navidrome are in `wanExposed`
          # (containers/traefik.nix), so requests arriving here can have come
          # from the public internet by way of the UDM-Pro DNAT.
          #
          # THIS RULE IS UNCHANGED BY THAT AND IS STILL CORRECT.  The source
          # is Traefik's address either way — the proxy is what connects to
          # this port, never the external client — so restricting to
          # traefikAddr is exactly as tight as it was.  What changes is
          # what stands behind it: for these two the application's own user
          # database is the boundary, not Authelia.  See ingress-policy.nix.
          #
          # Both bind 0.0.0.0 by configuration below (Komga's `server.servlet`
          # address and Navidrome's `Address`), for the audiobookshelf reason:
          # loopback would make them unreachable from Traefik in another netns
          # while adding no protection this rule does not already give.
          komgaPort
          navidromePort
        ]
        + lib.concatMapStrings (port: ''
          iptables -A nixos-fw -p tcp -s ${monitoringAddr}/32 --dport ${toString port} -j nixos-fw-accept
        '') [
          scraparrPort

          # Navidrome's /metrics rides its ORDINARY port rather than getting a
          # listener of its own, so this opens the whole application to the
          # monitoring container — the same trade containers/jellyfin.nix
          # states plainly for its own metrics.  It is acceptable here for the
          # same reason: the far end is a container on this host that already
          # scrapes every other service, and the endpoint itself demands HTTP
          # Basic (measured: 401 without, 200 with — see the block below).
          navidromePort
        ]
        # ── M30: NAVIDROME'S THIRD SOURCE, AND ITS FIRST APPLICATION CLIENT ──
        #
        # A third source list rather than a merged list of (source, port) pairs,
        # for the reason stated above the first one: "what can Traefik reach?"
        # has to stay answerable by reading one list, and so does this.
        #
        # ONE PORT, ONE SOURCE.  Music Assistant reads the library over the
        # Subsonic API at /rest/** and touches nothing else in this container —
        # not Lidarr, not the *arr APIs, not Komga.  The acquisition pipeline and
        # the playback controller share exactly one surface, and it is this.
        #
        # `/metrics` RIDES THIS PORT TOO, which is the trade the monitoring rule
        # above already states plainly: source-restricting to one address is what
        # keeps that acceptable, and the endpoint demands HTTP Basic regardless.
        + lib.concatMapStrings (port: ''
          iptables -A nixos-fw -p tcp -s ${massAddr}/32 --dport ${toString port} -j nixos-fw-accept
        '') [
          navidromePort
        ];

      ##########################################################################
      # Users.  Numeric ids are the interface across the nspawn boundary.
      ##########################################################################

      # gid 3000 — must match the host numerically or every file these services
      # write lands in a group the host cannot name.  Fixed on the host in
      # containers/jellyfin.nix.
      users.groups.media = { gid = mediaGid; };

      # Sonarr and Radarr: `media` as the PRIMARY group.  The upstream modules
      # create users.users.{sonarr,radarr} only when `user` is left at its
      # default name, and set uid from config.ids.uids.* (274 / 275).  We keep
      # the default names — so the module still creates the accounts and we do
      # not have to restate `home` — and override just the uid.
      #
      # mkForce is required (the module's definition is a plain one), and
      # isSystemUser must come with it: NixOS asserts that a user is either
      # isNormalUser or "effectively a system user", and the latter is inferred
      # from uid < 1000.  3002 is not, so the inference stops working the
      # moment the uid is overridden.  Without isSystemUser this fails
      # evaluation with "Exactly one of ... isSystemUser and ... isNormalUser
      # must be set", which reads like a typo and is not one.
      users.users.sonarr = {
        isSystemUser = true;
        uid          = lib.mkForce sonarrUid;
      };
      users.users.radarr = {
        isSystemUser = true;
        uid          = lib.mkForce radarrUid;
      };

      # Prowlarr: its own user and group, declared in full because the upstream
      # module declares none — see the DynamicUser note under services.prowlarr
      # below.  No media membership: it never touches a file under /srv/media.
      users.users.prowlarr = {
        isSystemUser = true;
        uid          = prowlarrUid;
        group        = "prowlarr";
        home         = "/var/lib/prowlarr";
      };
      users.groups.prowlarr = { gid = prowlarrGid; };

      # ── M12 users ─────────────────────────────────────────────────────────
      #
      # BAZARR takes the same shape as sonarr/radarr and for the same reason:
      # it writes .srt sidecars NEXT TO THE MEDIA, so `media` must be its
      # PRIMARY group, not a supplementary one.  The header's PrivateUsers
      # explanation is the reason and is not re-derived here.
      #
      # Simpler than sonarr/radarr in one respect, though: the upstream module
      # declares users.users.bazarr WITHOUT a uid (it leaves the allocation to
      # NixOS), so setting one here is a new definition of an unset option and
      # needs no mkForce.  The module also declares the `bazarr` GROUP only
      # when services.bazarr.group == "bazarr"; it is "media" below, so no
      # stray group is created.
      users.users.bazarr.uid = bazarrUid;

      # CLEANUPARR and MEDIATHEKARR are declared in full — there is no upstream
      # module for either, so nothing else creates them.
      #
      # Both take `media` as PRIMARY, and for once the reason is not
      # PrivateUsers (neither unit sets it):
      #
      #   cleanuparr    DELETES files under /srv/media.  Removing a directory
      #                 entry needs write on the PARENT directory, and those
      #                 are 2770 root:media — so group membership is the whole
      #                 of its access, and a supplementary membership squashed
      #                 by some future hardening directive would present as a
      #                 cleaner that silently cleans nothing.
      #   mediathekarr  WRITES video into the download tree and then remuxes
      #                 it in place.
      #
      # `home` points at each service's state directory so that anything
      # reaching for $HOME lands somewhere writable rather than at /.
      users.users.cleanuparr = {
        isSystemUser = true;
        uid          = cleanuparrUid;
        group        = "media";
        home         = "/var/lib/cleanuparr";
      };
      users.users.mediathekarr = {
        isSystemUser = true;
        uid          = mediathekarrUid;
        group        = "media";
        home         = "/var/lib/mediathekarr";
      };

      # ── M13 users ─────────────────────────────────────────────────────────
      #
      # JELLYSEERR is declared in full even though `services.seerr` exists,
      # because that module creates NO user at all — it runs DynamicUser and
      # therefore has nothing to name.  Turning DynamicUser off (see its block)
      # means this file owns the account outright.
      #
      # OWN GROUP, NO MEDIA.  It is the prowlarr shape and for the prowlarr
      # reason: Jellyseerr talks to Sonarr, Radarr and Jellyfin over REST and
      # never opens a file under /srv/media.  Giving it gid 3000 "so it matches
      # the others" would be a strictly larger blast radius for no capability —
      # and this is the one service in the container that the whole household
      # can reach without authenticating to Authelia, so it is the last one
      # that should hold a handle to 47 TB.
      users.users.jellyseerr = {
        isSystemUser = true;
        uid          = jellyseerrUid;
        group        = "jellyseerr";
        home         = "/var/lib/seerr";
      };
      users.groups.jellyseerr = { gid = jellyseerrGid; };

      # JANITORR takes `media` as PRIMARY, and here the reason IS the one the
      # cleanuparr block dismisses: it deletes files it does not own.  Removing
      # a directory entry needs write on the PARENT directory, and those are
      # 2770 root:media — so group membership is the whole of its access.
      #
      # It also CREATES: the "Leaving Soon" symlink tree under
      # /srv/media/leaving-soon, which Jellyfin reads as an extra library.
      users.users.janitorr = {
        isSystemUser = true;
        uid          = janitorrUid;
        group        = "media";
        home         = "/var/lib/janitorr";
      };

      # SCRAPARR: own group, no media.  It reads REST APIs and serves
      # /metrics; it has no reason to be able to name a file in the library.
      users.users.scraparr = {
        isSystemUser = true;
        uid          = scraparrUid;
        group        = "scraparr";
        home         = "/var/empty";
      };
      users.groups.scraparr = { gid = scraparrGid; };

      # ── M14 users ─────────────────────────────────────────────────────────
      #
      # LIDARR takes the sonarr/radarr shape exactly, mkForce and all: the
      # servarr module declares users.users.lidarr WITH a uid, taken from
      # config.ids.uids.lidarr, so this is an override of an existing plain
      # definition and not a new one.  isSystemUser must come with it for the
      # reason the sonarr block gives — 3017 is not < 1000, so NixOS stops
      # inferring "effectively a system user" and asserts.
      #
      # media PRIMARY, and here the PrivateUsers reason does NOT apply: unlike
      # sonarr's and radarr's, LIDARR'S UPSTREAM UNIT HAS NO HARDENING AT ALL
      # (see its service block below).  It is media-primary because it must
      # hardlink out of slskd's download tree, and that access is entirely its
      # group membership — the same argument the cleanuparr block makes.
      users.users.lidarr = {
        isSystemUser = true;
        uid          = lib.mkForce lidarrUid;
      };

      # SOULARR, KAPOWARR and AUDIOBOOKSHELF are declared in full where nothing
      # else creates them, and `home` points at each one's state directory so
      # anything reaching for $HOME lands somewhere writable rather than at /.
      #
      # SOULARR IS media PRIMARY, AND THAT IS NOT OBVIOUS.  It looks like a
      # pure REST client — it drives Lidarr and slskd over HTTP — which would
      # make it the prowlarr shape, own group and no media.  It is not: it
      # reads ID3 tags out of the downloaded files with `music-tag` to decide
      # whether a release actually matches, and it moves rejected downloads
      # aside.  Both need real access to slskd's tree under /srv/media.
      users.users.soularr = {
        isSystemUser = true;
        uid          = soularrUid;
        group        = "media";
        home         = "/var/lib/soularr";
      };

      users.users.kapowarr = {
        isSystemUser = true;
        uid          = kapowarrUid;
        group        = "media";
        home         = "/var/lib/kapowarr";
      };

      # M17 — BINDERY: media PRIMARY, the kapowarr shape and for the kapowarr
      # reason.  It downloads into /srv/media/torrents/books and files into
      # /srv/media/library/books, and every file it creates must stay
      # manageable by the group (UMask 0002 in its unit is the other half).
      users.users.bindery = {
        isSystemUser = true;
        uid          = binderyUid;
        group        = "media";
        home         = "/var/lib/bindery";
      };

      # AUDIOBOOKSHELF is media PRIMARY for a tree that is NOT /srv/media, and
      # the distinction is worth stating so nobody "fixes" it later.
      #
      # Its library is /srv/audiobooks, a separate dataset (see the header of
      # the let-binding above).  That tree is 2770 root:media, so `media` is
      # what gets it write access there — and it is shared with Storyteller,
      # which writes synced EPUB3s into the same tree from a different
      # container as a different uid.  A private `audiobookshelf` group would
      # mean the two services could not see each other's output, which is the
      # entire reason they are on one dataset.
      #
      # The module declares users.users.audiobookshelf without a uid (leaving
      # allocation to NixOS), so setting one needs no mkForce — the bazarr
      # situation.  It declares the `audiobookshelf` GROUP only when group ==
      # "audiobookshelf"; it is "media" below, so no stray group appears.
      users.users.audiobookshelf.uid = audiobookshelfUid;

      # ── 2026-09-08: KOMGA and NAVIDROME.  media PRIMARY, READ-ONLY BY UNIT ─
      #
      # `media` because the library directories are 2770 root:media, i.e. mode
      # 0 for world — there is no way to read them from outside the group, so
      # group membership is not optional.
      #
      # THAT GRANT IS WRITE, AND IT IS TAKEN BACK PER UNIT.  2770 means group
      # write, so `media` alone would let either of these modify the library
      # the *arr manage.  Neither should ever do that: Komga can delete book
      # files from its UI, and Navidrome is explicitly required not to touch
      # the tree Lidarr owns.  What enforces it is a read-only bind in each
      # unit's own mount namespace (`BindReadOnlyPaths` / `ReadOnlyPaths`
      # below), which the process cannot undo — not the group, and not a
      # setting inside the application that a future admin could toggle.
      #
      # Both modules declare their user WITHOUT a uid, so pinning one here is
      # a merge and needs no mkForce (the bazarr/audiobookshelf situation, not
      # the sonarr one).  Both declare their private group only when
      # `group == "<name>"`; it is "media" for both, so no stray group appears.
      users.users.komga = {
        isSystemUser = true;
        uid          = komgaUid;
        group        = "media";
        home         = "/var/lib/komga";
      };
      users.users.navidrome = {
        isSystemUser = true;
        uid          = navidromeUid;
        group        = "media";
        home         = "/var/lib/navidrome";
      };

      # QUESTARR: own group, no media — the prowlarr shape.  It talks to IGDB
      # and Prowlarr over REST and writes only to /srv/games/questarr, which is
      # a different dataset and not part of the hardlink domain.  It has no
      # reason to be able to name a file in the media library.
      users.users.questarr = {
        isSystemUser = true;
        uid          = questarrUid;
        group        = "questarr";
        home         = "/var/lib/questarr";
      };
      users.groups.questarr = { gid = questarrGid; };


      ##########################################################################
      # Recyclarr — TRaSH-Guides quality definitions, synced on a timer.
      #
      # SCOPE NOTE: M4's prompt says "recyclarr is explicitly OUT of scope; it
      # is a backlog item to evaluate after this settles."  It is here because
      # lgo asked for it during the milestone, not because the boundary drifted.
      # Recorded so the prompt and the tree do not silently disagree.
      #
      # It is a good fit for this repo: the NixOS module takes the entire
      # recyclarr config as a Nix attrset, so "which quality definitions apply"
      # becomes a reviewable diff instead of UI state nobody can reconstruct.
      # That is the same argument the root folders lost — those only exist in
      # the UI, so they stay a documented manual step; this one does not have
      # to.
      ##########################################################################

      # THE API KEYS, and why they are not a clan var.
      #
      # Recyclarr authenticates to Sonarr and Radarr with their API keys.  Those
      # keys are not ours to choose: each app generates one on first run and
      # writes it into its own config.xml on zdata.  There are two ways to get
      # them to recyclarr and only one of them stays true.
      #
      #   A clan-vars prompt would work today and rot tomorrow.  It would mean
      #   pasting a value that already exists elsewhere, creating a second copy
      #   with no link to the first — and the day an API key is regenerated in
      #   the UI (Settings → General → API Key, one button), the var still holds
      #   the old one and every sync fails 401 while the repo looks correct.
      #
      #   Reading config.xml keeps ONE source of truth.  The key lives where the
      #   app that owns it put it; rotating it in the UI is picked up on the
      #   next sync with no deploy and no re-prompt.
      #
      # So this oneshot stages both keys into a root-only tmpfs directory, and
      # services.recyclarr's `_secret` mechanism turns them into LoadCredential=
      # entries.  The key is never in the Nix store and never in the repo, so
      # invariant #8 is satisfied without a generator — there is no secret here
      # that this machine did not already hold.
      #
      # CORRECTION, measured on ernst 2026-08-26.  An earlier version of this
      # paragraph also claimed the key is "never in config.yml on disk".  THAT
      # IS FALSE, and the correction matters more than the original claim did.
      # The recyclarr module's ExecStartPre (recyclarr-pre-start) reads each
      # credential and SUBSTITUTES IT INTO /var/lib/recyclarr/config.yml before
      # the sync runs.  On this machine that file is:
      #
      #     -rw-r--r-- 1 recyclarr recyclarr  /var/lib/recyclarr/config.yml
      #     drwxr-xr-x 7 recyclarr recyclarr  /var/lib/recyclarr
      #
      # i.e. both API keys in PLAINTEXT, world-readable, inside the container.
      #
      # It is left alone, deliberately, and the reasoning is worth writing down
      # rather than re-deriving: the exposure is to processes already inside
      # this netns, and every one of them — sonarr, radarr, prowlarr, bazarr,
      # cleanuparr, mediathekarr, umlautadaptarr — either owns one of these keys
      # or is handed it on purpose.  Widening nothing is what the uid boundary
      # already does; the keys' real protection is that the container is not
      # reachable except through Traefik.
      #
      # WHAT WOULD CHANGE THIS: a service landing in this container that is NOT
      # trusted with *arr API access.  There is no such tenant today.  If one
      # arrives, this is the line that has to be revisited, and the fix is
      # upstream's (the module should chmod its rendered config), not a second
      # mechanism here.
      #
      # RuntimeDirectoryPreserve = "yes" with RemainAfterExit = false is the
      # combination that makes this re-run.  Without the preserve, the runtime
      # directory is deleted the instant this oneshot exits — i.e. before
      # recyclarr.service starts and before LoadCredential can read it.  With
      # RemainAfterExit = true instead, the unit would stay active and never run
      # again, so a rotated key would be staged once and then be stale forever.
      # This pair keeps the directory and re-runs the extraction on every sync.
      #
      # M12 RENAMED THIS UNIT from recyclarr-api-keys to arr-api-keys, because
      # it now has two consumers: recyclarr reads the two key files through
      # `_secret`, and UmlautAdaptarr reads an environment file written from
      # the same two keys.  The alternative was a second copy of this hardened
      # unit reading the same two config.xml files, which is one source of
      # truth too many for a value that can be rotated with one button in a UI.
      systemd.services.arr-api-keys = {
        description = "Stage Sonarr/Radarr API keys for recyclarr and UmlautAdaptarr";
        before     = [ "recyclarr.service" "umlautadaptarr.service" ];
        requiredBy = [ "recyclarr.service" "umlautadaptarr.service" ];
        serviceConfig = {
          Type                    = "oneshot";
          RemainAfterExit         = false;
          RuntimeDirectory        = "arr-api-keys";
          RuntimeDirectoryMode    = "0700";
          RuntimeDirectoryPreserve = "yes";
          UMask                   = "0077";

          # This unit is ours, so nothing upstream hardens it and a bare root
          # oneshot scores 9.4 UNSAFE.  It runs as root for exactly one reason —
          # the two config.xml files live under 0700 directories owned by
          # sonarr and radarr — so everything that is not "read two files and
          # write two files" is taken away.
          #
          # CapabilityBoundingSet is CAP_DAC_READ_SEARCH and NOT empty, which
          # is the one thing here that cannot be tightened.  Root's ability to
          # read another user's 0700 directory IS that capability; dropping the
          # whole set would leave a root process that cannot read the files it
          # exists to read, and the failure would look like a path bug.
          #
          # It is also NOT CAP_DAC_OVERRIDE, and the difference is load-bearing
          # rather than pedantic: READ_SEARCH grants read and traverse only, so
          # this unit can read sonarr's config.xml and still cannot write over
          # anything it can see.  The first version of the script tripped on
          # exactly that — it created its output with `install -m 0400` and then
          # failed to write to it — which is the correct capability catching a
          # sloppy script, not a reason to widen the set.  See the ExecStart.
          #
          # PrivateNetwork is the big one: this handles credentials and has no
          # business having a network stack at all.
          PrivateNetwork          = true;
          IPAddressDeny           = "any";
          CapabilityBoundingSet   = [ "CAP_DAC_READ_SEARCH" ];
          NoNewPrivileges         = true;
          ProtectSystem           = "strict";
          ProtectHome             = true;
          PrivateTmp              = true;
          PrivateDevices          = true;
          ProtectClock            = true;
          ProtectControlGroups    = true;
          ProtectHostname         = true;
          ProtectKernelLogs       = true;
          ProtectKernelModules    = true;
          ProtectKernelTunables   = true;
          ProtectProc             = "invisible";
          RestrictAddressFamilies = [ "AF_UNIX" ];
          RestrictNamespaces      = true;
          RestrictRealtime        = true;
          RestrictSUIDSGID        = true;
          RemoveIPC               = true;
          LockPersonality         = true;
          SystemCallArchitectures = "native";
          SystemCallFilter        = arrSyscallFilter;

          ExecStart = pkgs.writeShellScript "recyclarr-stage-api-keys" ''
            set -euo pipefail

            stage() {
              app=$1; xml=$2; out=$3

              if [ ! -r "$xml" ]; then
                echo "$app: cannot read $xml — has $app finished its first-run wizard?" >&2
                exit 1
              fi

              # Assign, then test.  A command substitution that fails inside an
              # argument does NOT trip `set -e`, so building the file in one
              # step would turn an unreadable config.xml into an EMPTY api key
              # and a 401 with nothing in the log to explain it.  That exact
              # shape shipped once in this repo — see the render script in
              # microvms/wg-qbittorrent.nix and PR #84.
              key=$(${pkgs.gnused}/bin/sed -n 's:.*<ApiKey>\(.*\)</ApiKey>.*:\1:p' "$xml" | head -n1)
              if [ -z "$key" ]; then
                echo "$app: no <ApiKey> element in $xml" >&2
                exit 1
              fi

              # Create it WRITABLE and let UMask=0077 set the mode; do not
              # `install -m 0400` first and write afterwards.
              #
              # Writing to a 0400 file you own still needs CAP_DAC_OVERRIDE —
              # owner permission checks use the owner bits, and root is not
              # exempt once the capability is gone.  The bounding set below
              # grants CAP_DAC_READ_SEARCH and nothing else, deliberately, so
              # the earlier install-then-write form failed with "Permission
              # denied" on its own output.  Measured on ernst 2026-08-21.
              #
              # That the READ of sonarr's 0700-directory config.xml succeeded
              # in the same run is the useful half: DAC_READ_SEARCH is exactly
              # the right capability, and the script simply must not create
              # files it then cannot write.
              #
              # rm -f first: a leftover 0400 file from an older generation
              # could not be reopened for writing either.  Unlinking needs
              # write on the DIRECTORY, which root has by ownership, so no
              # capability is involved.
              ${pkgs.coreutils}/bin/rm -f "$out"
              printf '%s' "$key" > "$out"
            }

            stage sonarr /var/lib/sonarr/.config/NzbDrone/config.xml ${arrSecretsDir}/sonarr-api-key
            stage radarr /var/lib/radarr/.config/Radarr/config.xml   ${arrSecretsDir}/radarr-api-key

            # ── M14: LIDARR, FOR SOULARR ─────────────────────────────────
            #
            # Same servarr <ApiKey> element in the same config.xml shape, so it
            # reuses stage() unchanged — the third consumer of this stager and
            # the reason it was renamed out of `recyclarr-secrets` in M12.
            #
            # The PATH is the thing to get right, and it is NOT the pattern
            # sonarr and radarr follow.  Lidarr's servarr module defaults
            # dataDir to `/var/lib/lidarr/.config/Lidarr` — the same nesting —
            # but the directory component is `Lidarr`, not an NzbDrone-style
            # legacy name.  Checked against the module rather than guessed from
            # Sonarr's, which is where the `.config/NzbDrone` surprise lives.
            #
            # MANDATORY, like M13's three and for a related reason: Soularr
            # cannot do anything at all without Lidarr's key, and its
            # ExecStartPre refuses to write a config.ini containing an empty
            # one.  Failing here names the wizard that has not been run.
            stage lidarr /var/lib/lidarr/.config/Lidarr/config.xml   ${arrSecretsDir}/lidarr-api-key

            # ── M13: THREE MORE KEYS, FOR SCRAPARR ───────────────────────
            #
            # Prowlarr's is the same <ApiKey> element in the same servarr
            # config.xml shape, so it reuses stage() unchanged.  Bazarr and
            # Jellyseerr keep theirs in their own formats and get their own
            # extractors below.
            #
            # ALL THREE ARE MANDATORY, not best-effort, and that is forced by
            # how Scraparr validates rather than chosen.  It builds a service's
            # config from ANY matching env var, then requires both `url` and
            # `api_key` — so a URL with no key AND a key with no URL are both
            # `sys.exit(1)`.  There is no partial mode.  The first deploy
            # shipped URLs without keys and produced, on ernst:
            #
            #   [ERROR] Invalid config: prowlarr (instance 0): missing 'api_key'
            #   [ERROR] Invalid config: bazarr (instance 0): missing 'api_key'
            #   [ERROR] Invalid config: seerr (instance 0): missing 'api_key'
            #   scraparr.service: Scheduled restart job, restart counter at 41
            #
            # Failing loudly HERE, naming the wizard that has not been run, is
            # much better than a restart loop in a different unit's journal.
            stage prowlarr /var/lib/prowlarr/config.xml ${arrSecretsDir}/prowlarr-api-key

            # Bazarr: YAML, under `auth:`.  There are three `apikey:` keys in
            # that file — the other two are provider credentials and are
            # normally empty — so this walks to the `auth:` block first rather
            # than taking the first match.  Verified against the live file on
            # ernst, 2026-08-26.
            bazarr_out=${arrSecretsDir}/bazarr-api-key
            bazarr_cfg=/var/lib/bazarr/config/config.yaml
            if [ ! -r "$bazarr_cfg" ]; then
              echo "bazarr: cannot read $bazarr_cfg — has Bazarr started at least once?" >&2
              exit 1
            fi
            bazarr_key=$(${pkgs.gawk}/bin/awk '
              /^auth:/            { inauth = 1; next }
              /^[^[:space:]]/     { inauth = 0 }
              inauth && $1 == "apikey:" { gsub(/^['"'"'"]|['"'"'"]$/, "", $2); print $2; exit }
            ' "$bazarr_cfg")
            if [ -z "$bazarr_key" ]; then
              echo "bazarr: no apikey under auth: in $bazarr_cfg" >&2
              exit 1
            fi
            ${pkgs.coreutils}/bin/rm -f "$bazarr_out"
            printf '%s' "$bazarr_key" > "$bazarr_out"

            # Jellyseerr: JSON, `.main.apiKey`.  jq rather than a regex,
            # because "apiKey" appears more than once in settings.json and
            # `head -1` would be a coin flip between the real key and a
            # per-service one.
            seerr_out=${arrSecretsDir}/jellyseerr-api-key
            seerr_cfg=/var/lib/seerr/settings.json
            if [ ! -r "$seerr_cfg" ]; then
              echo "jellyseerr: cannot read $seerr_cfg — has its first-run wizard been completed?" >&2
              exit 1
            fi
            seerr_key=$(${pkgs.jq}/bin/jq -r '.main.apiKey // empty' "$seerr_cfg")
            if [ -z "$seerr_key" ]; then
              echo "jellyseerr: no .main.apiKey in $seerr_cfg" >&2
              exit 1
            fi
            ${pkgs.coreutils}/bin/rm -f "$seerr_out"
            printf '%s' "$seerr_key" > "$seerr_out"

            # ── UmlautAdaptarr's environment file (M12) ──────────────────
            #
            # Same two keys, different shape.  UmlautAdaptarr is an ASP.NET
            # application configured entirely through environment variables,
            # and its appsettings.json declares Sonarr and Radarr as ARRAYS —
            # so the indexed form (Sonarr__0__…) is the one that binds onto
            # element 0 rather than fighting it.  The non-indexed form in
            # upstream's docker-compose works too; the indexed one is used
            # here because it matches the file it is overriding.
            #
            # localhost, because all of this shares one netns — the same
            # payoff the Prowlarr→Sonarr/Radarr wiring gets: no port opened,
            # nothing to firewall.
            #
            # Written with the same rm-then-write dance as the key files, and
            # for the same measured reason: this unit holds
            # CAP_DAC_READ_SEARCH and NOT CAP_DAC_OVERRIDE, so it must never
            # create a file it cannot subsequently write.
            env_out=${arrSecretsDir}/umlautadaptarr.env
            ${pkgs.coreutils}/bin/rm -f "$env_out"
            {
              echo "Sonarr__0__Enabled=true"
              echo "Sonarr__0__Name=Sonarr"
              echo "Sonarr__0__Host=http://localhost:${toString sonarrPort}"
              echo "Sonarr__0__ApiKey=$(${pkgs.coreutils}/bin/cat ${arrSecretsDir}/sonarr-api-key)"

              # RADARR IS OFF, AND NOT BECAUSE OF A PREFERENCE.
              #
              # UmlautAdaptarr HAS NO RADARR SUPPORT.  Its feature table lists
              # "Radarr Support — in Arbeit" (work in progress), and the
              # codebase agrees: UmlautAdaptarr/Providers/ contains
              # ArrClientBase, SonarrClient, LidarrClient and ReadarrClient —
              # there is no RadarrClient.cs at all.
              #
              # Confirmed on the running service, ernst 2026-08-26: with
              # Radarr__0__Enabled=true the journal shows only
              #   [INF] Init SonarrClient (Sonarr)
              # and never mentions Radarr again.  The setting was accepted and
              # silently ignored.
              #
              # It is set to FALSE rather than deleted so that the next person
              # reading this file learns the answer here instead of re-deriving
              # it from an empty log.  Flip it to true when upstream ships a
              # RadarrClient — the radarr-api-key file above is already staged
              # for that day.
              echo "Radarr__0__Enabled=false"
              # Ports, stated here rather than left to appsettings.json, so
              # that the numbers the firewall list above reasons about and the
              # numbers the service binds are the same numbers in one repo.
              echo "Kestrel__Endpoints__Http__Url=http://[::]:${toString umlautadaptarrPort}"
              echo "Settings__ProxyPort=${toString umlautadaptarrProxyPort}"
            } > "$env_out"
          '';
        };
      };

      # recyclarr's uid is NOT pinned, and that is the deliberate opposite of
      # sonarr/radarr/prowlarr above.  The 3000-range convention exists because
      # nspawn passes numeric ids through unmapped, so an id chosen in here is
      # an id on zdata.  Recyclarr never touches /srv/media — it talks to two
      # REST APIs on localhost and caches the TRaSH guides in its own state
      # directory — so no number it uses is ever visible outside this container
      # and there is nothing to keep in step.  Its state stays on the
      # container's own filesystem for the same reason: /var/lib/recyclarr holds
      # a re-downloadable guide cache plus a config.yml generated from this
      # file, so there is nothing on it worth a zdata bind.  (It survives
      # anyway — ernst persists /var/lib/nixos-containers — but it would not
      # matter if it did not.)

      ##########################################################################
      # Hardening.
      #
      # MEASURED, not asserted.  `systemd-analyze security --offline=true
      # --root=<container toplevel>/etc/systemd/system` scores the units this
      # file actually generates, which is how these can be checked before a
      # deploy rather than after one:
      #
      #   service                  upstream directives   this file
      #   prowlarr                 8.2 EXPOSED           1.3 OK
      #   sonarr                   1.5 OK                1.3 OK
      #   radarr                   1.5 OK                1.3 OK
      #   flaresolverr             3.0 OK                3.0 OK  (untouched)
      #   recyclarr                3.9 OK                3.9 OK  (untouched)
      #   arr-api-keys             9.4 UNSAFE            1.0 OK  (ours)
      #   ── M12, measured 2026-08-26 ──────────────────────────────────────
      #   bazarr                   9.0 UNSAFE            1.4 OK
      #   umlautadaptarr           9.4 UNSAFE            1.3 OK
      #   cleanuparr               9.0 UNSAFE            1.4 OK
      #   mediathekarr-indexer     9.0 UNSAFE            1.4 OK
      #   mediathekarr-downloader  9.0 UNSAFE            1.4 OK
      #
      # WHAT THE M12 "UPSTREAM" COLUMN MEANS, because it is not the same thing
      # it means for prowlarr.  Bazarr's 9.0 is REAL upstream: the nixpkgs
      # module sets Type, User, Group, SyslogIdentifier, ExecStart, Restart,
      # KillSignal and SuccessExitStatus, and no hardening directive of any
      # kind.  The other four have no upstream unit at all, so their baseline
      # is the unit anybody would write first — Type, User, Group, ExecStart —
      # measured against the same nixpkgs.  UmlautAdaptarr's 9.4 is higher than
      # the rest for the same reason arr-api-keys' was: with no User= it would
      # be root.
      #
      # Both columns were produced with
      #   systemd-analyze security --offline=true --root=<toplevel> <unit>
      # against generated units, which is how they can be checked before a
      # deploy rather than after one.
      #
      # Three of the original rows need a word.
      #
      # FlareSolverr is left exactly as upstream ships it, and its 3.0 is the
      # honest price of what it does: RestrictNamespaces has to permit `user`
      # so Chromium can build its own sandbox, and tightening that would
      # replace a browser sandbox with a systemd one — a worse trade. Its
      # confinement comes from DynamicUser and from NOT being in group media,
      # not from these directives.
      #
      # Recyclarr's own module is already sensible (ProtectSystem=strict,
      # ReadWritePaths pinned to its state directory, no capabilities); its 3.9
      # is mostly the network access it genuinely needs, to two localhost APIs
      # and to GitHub for the guides.
      #
      # arr-api-keys is OURS, so nothing upstream hardens it, and a bare
      # root oneshot scores 9.4 UNSAFE. That number is the reason the block
      # below exists rather than a bare ExecStart: it handles credentials, so
      # it is the last unit here that should be the least confined. 1.0 is the
      # tightest score in the container.
      #
      # Offline analysis does credit DynamicUser='s implications (ProtectSystem,
      # PrivateTmp, NoNewPrivileges, RemoveIPC, RestrictSUIDSGID all score ✓ in
      # the baseline), so prowlarr's 8.2 is not an artefact of scoring a
      # switched-off DynamicUser — it is everything DynamicUser never implied:
      # no CapabilityBoundingSet, no SystemCallFilter, no
      # RestrictAddressFamilies, no PrivateDevices, no ProtectKernel*.
      #
      # What still scores ✗ at 1.3, and why each is left alone: PrivateNetwork
      # (the container has one interface and that is the point),
      # RestrictAddressFamilies AF_INET/AF_INET6/AF_UNIX (an indexer proxy and
      # two metadata clients), IPAddressDeny (see REJECTED below),
      # MemoryDenyWriteExecute (see REJECTED below), RootDirectory (nspawn IS
      # the root directory), and UMask — 0002 is world-readable by
      # systemd-analyze's standard, deliberately, for the reason given below.
      ##########################################################################

      # PROWLARR — the one that needed real work.
      #
      # Upstream runs it with DynamicUser = true and StateDirectory = prowlarr,
      # i.e. state under /var/lib/private/prowlarr owned by a uid systemd
      # allocates at run time.  That is a bad fit for a bind mount from zdata,
      # and this repo has already paid for the lesson once: see the Ollama rows
      # in docs/history.md, where DynamicUser plus persistent state left a
      # stale symlink and a directory nothing could read.  The dynamic uid is
      # derived from the unit name and is usually stable — "usually" is the
      # problem, because the failure is a database the service cannot open.
      #
      # So: static uid 3004, and the state directory is a plain
      # /var/lib/prowlarr rather than the /var/lib/private indirection.
      #
      # THE COST, stated because it is easy to miss: DynamicUser=true silently
      # implies NoNewPrivileges, PrivateTmp, ProtectSystem=strict,
      # ProtectHome=read-only, RemoveIPC and RestrictSUIDSGID.  Turning it off
      # drops ALL of them, and upstream's serviceConfig sets none of them
      # explicitly — so a naive `DynamicUser = false` would quietly make
      # Prowlarr the least confined service on the box.  Everything the switch
      # removed is restated below, plus the rest of the sonarr/radarr set, so
      # the net result is strictly more confined than upstream.
      #
      # ProtectSystem=strict needs no ReadWritePaths here: StateDirectory=
      # makes /var/lib/prowlarr writable implicitly, and Prowlarr writes
      # nowhere else.  PrivateTmp covers /tmp and /var/tmp.
      documentation.enable       = false;
      documentation.nixos.enable = false;
    };
  };
}
