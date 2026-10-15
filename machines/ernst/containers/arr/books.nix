# machines/ernst/containers/arr/books.nix
#
# The reading half of the `arr` container: Audiobookshelf, Komga, Kapowarr
# (comics), Questarr (games — it lives here because it is the same *arr shape,
# not because a game is a book) and Bindery, which is this household's ebook
# acquisition path.
#
# ── THIS FILE CO-DEFINES containers.arr ─────────────────────────────────────
#
# It creates no container; see ./video.nix for the mechanism and the reason
# the split is by media domain.
{ config, lib, pkgs, ... }:
let
  ids = import ./ids.nix;

  # The old flat names — see ./video.nix.
  arrSyscallFilter   = ids.syscallFilter;
  audiobookshelfPort = ids.ports.audiobookshelf;
  komgaPort          = ids.ports.komga;
  kapowarrPort       = ids.ports.kapowarr;
  questarrPort       = ids.ports.questarr;
  binderyPort        = ids.ports.bindery;
  audiobooksRoot     = ids.audiobooksRoot;
  traefikAddr        = ids.peers.traefik;
in
{
  # ── Inside the container ──────────────────────────────────────────────────
  containers.arr.config = { config, pkgs, lib, ... }: let
    # Packaged in this repo; each domain file calls the ones its units need.
    kapowarr = pkgs.callPackage ../pkgs/kapowarr.nix { };
    questarr = pkgs.callPackage ../pkgs/questarr.nix { };
    bindery  = pkgs.callPackage ../pkgs/bindery.nix { };
  in {

  ##########################################################################
  # M14 (c) — KAPOWARR.  Comics acquisition.
  #
  # Komga and CWA serve the READING side; this is the acquisition half
  # only.  ./pkgs/kapowarr.nix records why it was chosen over Mylar3 (short
  # version: Mylar3 is Usenet-first and this fleet has measurably no
  # Usenet).
  #
  # CORRECTED 2026-09-08.  This sentence used to read "Komga and CWA
  # ALREADY serve", and it was not true when it was written: neither
  # existed anywhere in this repo, on this host, or in Technitium.  It
  # described an intention, and M14's placement argument for Kapowarr
  # leaned on it as though it were a fact.  Both now exist — Komga is a
  # unit in this container (see its block below) and CWA is on the podman
  # tier (containers/cwa.nix) — so the claim is finally accurate.  Left
  # annotated rather than silently fixed, because "already" was doing
  # load-bearing work in an argument and the correction is the interesting
  # part.
  #
  # NOTE THE HAND-OFF THAT DOES NOT EXIST YET: Kapowarr writes to
  # /srv/media/library/comics and Komga READS that tree directly, so the
  # comics path is complete.  The EBOOK path is not — Bindery writes to
  # /srv/media/library/books, Komga reads it, and CWA owns a separate
  # Calibre library it manages itself.  Wiring Bindery's output into CWA's
  # ingest folder is a deliberate non-decision; see containers/cwa.nix.
  #
  # It re-executes itself to implement in-app restart, which is why the
  # derivation wraps a python env rather than patching a shebang — see its
  # header.  For systemd that means the unit's MAINPID is the supervisor and
  # the real work happens in a child, so Type=simple and KillMode default
  # (control-group) are both correct: stopping the unit must take the child
  # with it.
  ##########################################################################
  systemd.services.kapowarr = {
    description = "Kapowarr — comic book library manager";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "network.target" ];

    serviceConfig = {
      Type  = "simple";
      User  = "kapowarr";
      Group = "media";

      # -o binds the listener.  0.0.0.0 INSIDE this netns, where the
      # container firewall admits ${traefikAddr} and nothing else on this
      # port — the same posture every other web UI here has.
      ExecStart = lib.concatStringsSep " " [
        (lib.getExe kapowarr)
        "--DatabaseFolder /var/lib/kapowarr"
        "--LogFolder /var/lib/kapowarr"
        "--TempDownloadFolder /srv/media/torrents/comics"
        "--Host 0.0.0.0"
        "--Port ${toString kapowarrPort}"
      ];

      Restart    = "on-failure";
      RestartSec = "30s";

      UMask = "0002";

      NoNewPrivileges  = true;
      PrivateTmp       = true;
      ProtectSystem    = "strict";
      ProtectHome      = true;
      RemoveIPC        = true;
      RestrictSUIDSGID = true;

      ReadWritePaths = [ "/srv/media" "/var/lib/kapowarr" ];

      CapabilityBoundingSet   = "";
      PrivateDevices          = true;
      ProtectClock            = true;
      ProtectControlGroups    = true;
      ProtectHostname         = true;
      ProtectKernelLogs       = true;
      ProtectKernelModules    = true;
      ProtectKernelTunables   = true;
      ProtectProc             = "invisible";
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      RestrictNamespaces      = true;
      RestrictRealtime        = true;
      LockPersonality         = true;
      SystemCallArchitectures = "native";

      # NOT the usual filter set.  Kapowarr's supervisor uses
      # multiprocessing with the default start method plus Popen, and
      # `~@privileged` is fine but a stricter list would block the
      # process-control calls the restart mechanism depends on.
      SystemCallFilter = arrSyscallFilter;
    };
  };

  ##########################################################################
  # M14 (d) — QUESTARR.  Games.
  #
  # ── IT NEEDS A WRITABLE WorkingDirectory HOLDING ITS MIGRATIONS ──────
  #
  # Read ./pkgs/questarr.nix's header before changing anything here.
  # Questarr resolves BOTH its Drizzle migrations directory AND its
  # server.log from process.cwd(), so the working directory has to be
  # writable AND contain `migrations/`.  Neither a store path nor a bare
  # state directory satisfies both.
  #
  # The tmpfiles `L+` rule below is what reconciles them: the state
  # directory is the cwd, and `migrations` inside it is a forced symlink
  # into the package.  `L+` rather than `L` because the store path changes
  # on every upgrade and a plain `L` would leave the old link in place,
  # which would run LAST DEPLOY'S migrations against this deploy's schema.
  ##########################################################################
  systemd.tmpfiles.rules = [
    "L+ /var/lib/questarr/migrations - - - - ${questarr}/lib/questarr/migrations"
  ];

  systemd.services.questarr = {
    description = "Questarr — game library manager";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "network.target" ];

    environment = {
      PORT = toString questarrPort;
      # Its default is 0.0.0.0 already; stated so the bind address is not a
      # thing a reader has to go and look up in the built JavaScript.
      HOST = "0.0.0.0";
      SQLITE_DB_PATH = "/var/lib/questarr/questarr.db";
    };

    serviceConfig = {
      Type  = "simple";
      User  = "questarr";
      Group = "questarr";      # OWN group — no media, see the users block

      WorkingDirectory = "/var/lib/questarr";
      ExecStart        = lib.getExe questarr;
      Restart          = "on-failure";
      RestartSec       = "30s";

      # 0027, not 0002.  This is the one M14 service whose output NO other
      # uid ever needs to read: it owns /srv/games/questarr outright and
      # shares no group with anything.  The 0002 everywhere else in this
      # file exists to make `media` able to manage a shared tree; there is
      # no shared tree here, so the looser mask would be a permission
      # granted to nobody.
      UMask = "0027";

      NoNewPrivileges  = true;
      PrivateTmp       = true;
      ProtectSystem    = "strict";
      ProtectHome      = true;
      RemoveIPC        = true;
      RestrictSUIDSGID = true;

      ReadWritePaths = [ "/var/lib/questarr" "/srv/games/questarr" ];

      CapabilityBoundingSet   = "";
      PrivateDevices          = true;
      ProtectClock            = true;
      ProtectControlGroups    = true;
      ProtectHostname         = true;
      ProtectKernelLogs       = true;
      ProtectKernelModules    = true;
      ProtectKernelTunables   = true;
      ProtectProc             = "invisible";
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      RestrictNamespaces      = true;
      RestrictRealtime        = true;
      LockPersonality         = true;
      SystemCallArchitectures = "native";
      SystemCallFilter        = arrSyscallFilter;

      # NOT MemoryDenyWriteExecute: V8 JITs, exactly like the .NET services
      # above.  Same rejection, different runtime.
    };
  };

  ##########################################################################
  # M14 (e) — AUDIOBOOKSHELF.  The one service here that owes no hardlink
  # proof, and the one whose upstream unit is least hardened.
  #
  # ── ITS MODULE HAS NO HARDENING EITHER, AND LESS THAN LIDARR'S ───────
  #
  # nixpkgs' services.audiobookshelf unit is Type, User, Group,
  # StateDirectory, WorkingDirectory, ExecStart, Restart.  That is all of
  # it — no CapabilityBoundingSet, no NoNewPrivileges, no ProtectSystem,
  # nothing.  Read at ernst's pin on 2026-08-28.
  #
  # So this is the second module in M14 whose hardening has to be supplied
  # rather than adjusted, and it makes the same point Lidarr's block does:
  # read the unit.
  #
  # ── COMPLEMENTARY TO STORYTELLER, NOT OVERLAPPING ────────────────────
  #
  # Audiobookshelf SERVES the library; Storyteller PRODUCES synced EPUB3s
  # from ebook+audiobook pairs.  They share one dataset on purpose, so that
  # Storyteller's output under ${audiobooksRoot}/synced is a directory
  # Audiobookshelf can simply be pointed at.  See
  # machines/ernst/containers/storyteller.nix.
  #
  # ── WHY IT BEATS A JELLYFIN AUDIOBOOK LIBRARY ────────────────────────
  #
  # Per-user progress that actually works across devices, and good handling
  # of children's accounts.  Jellyfin tracks position per item, not per
  # user per item, in a way that makes a shared audiobook unusable for two
  # people at once — which is the whole use case in this household.
  ##########################################################################
  services.audiobookshelf = {
    enable = true;
    user   = "audiobookshelf";
    group  = "media";           # for /srv/audiobooks, NOT /srv/media

    # BOTH of these differ from the module's defaults, and both have to.
    #
    #   port  the module defaults to 8000; 13378 is what upstream, every
    #         client and docs/history.md use.
    #   host  the module defaults to 127.0.0.1, which would make it
    #         unreachable from Traefik in another container entirely.  The
    #         container firewall is what restricts it, as everywhere else
    #         in this file.
    port = audiobookshelfPort;
    host = "0.0.0.0";

    openFirewall = false;       # explicit list above
  };

  systemd.services.audiobookshelf.serviceConfig = {
    # Group-writable: Storyteller (uid 3022, group media, different
    # container) writes into the same tree, and Audiobookshelf writes cover
    # art and — when asked — renames scanned files.  Neither can manage the
    # other's output at 0022.
    UMask = "0002";

    # Everything upstream omits.
    CapabilityBoundingSet = "";
    NoNewPrivileges       = true;
    PrivateDevices        = true;
    PrivateTmp            = true;
    ProtectClock          = true;
    ProtectControlGroups  = true;
    ProtectHostname       = true;
    ProtectKernelLogs     = true;
    ProtectKernelModules  = true;
    ProtectKernelTunables = true;
    ProtectProc           = "invisible";
    RemoveIPC             = true;
    RestrictNamespaces    = true;
    RestrictRealtime      = true;
    RestrictSUIDSGID      = true;
    LockPersonality       = true;
    SystemCallArchitectures = "native";
    SystemCallFilter        = arrSyscallFilter;
    RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];

    ProtectSystem  = "strict";
    ReadWritePaths = [ audiobooksRoot "/var/lib/audiobookshelf" ];

    # NOT ProtectHome: its home IS /var/lib/audiobookshelf, the same
    # situation Lidarr is in.
    #
    # NOT MemoryDenyWriteExecute: Node, so V8 JITs.  Third rejection of the
    # same directive in this file, for the third runtime.
    #
    # NO /srv/media ANYWHERE.  This service has no business in the film and
    # television library and this is the line that says so.
  };

  ##########################################################################
  # KOMGA — the comics and ebook READER.  Kapowarr's consumer.
  #
  # containers/traefik.nix's kapowarr block said "Komga and CWA already
  # serve the READING side in this household".  They did not: there was no
  # Komga anywhere in this repo, no container on ernst, and no Technitium
  # record.  The claim described an intention.  This is the service that
  # makes it true, and it is greenfield — nothing is migrated, no library
  # is restructured, and Kapowarr's output path is untouched.
  #
  # ── WHAT IT IS POINTED AT, AND WHAT IT MUST NOT DO ───────────────────
  #
  # /srv/media/library/comics  Kapowarr's output.  237 series as of today.
  # /srv/media/library/books   Bindery's output.  Empty as of today, which
  #                            is expected — M17 landed the acquisition
  #                            half and nothing has been filed yet.
  #
  # BOTH READ-ONLY, ENFORCED BY THE UNIT.  Komga's UI can delete book files
  # and can rewrite embedded metadata; neither is acceptable against a tree
  # the *arr and Kapowarr manage, because their databases are the source of
  # truth for what is in it.  `ProtectSystem = "strict"` makes the whole
  # filesystem read-only and `ReadWritePaths` names ONLY its own state, so
  # the library is read-only by omission rather than by a setting.
  #
  # That is deliberately not "trust the group": komga is in `media`, the
  # library is 2770 root:media, so the group grants write.  The unit is
  # what takes it away, and the process cannot undo its own mount
  # namespace.
  ##########################################################################
  services.komga = {
    enable   = true;
    user     = "komga";
    group    = "media";        # for /srv/media/library/**, read-only per above
    stateDir = "/var/lib/komga";

    # `settings.server.port`, NOT the top-level `port`.  The latter still
    # works and is what most documentation shows, but it is a RENAMED
    # ALIAS at this pin and emits an eval warning telling you so.  It is
    # also why the option appeared to have "no default" when queried
    # directly — an alias carries none.
    #
    # `settings` is a freeform YAML passthrough rendered to Komga's
    # application.yml, so anything Komga accepts can go here.
    settings.server = {
      port = komgaPort;

      # 0.0.0.0 for the audiobookshelf reason: Traefik is in a different
      # netns, so loopback would make it unreachable.  The container
      # firewall above restricts the port to Traefik's address.
      address = "0.0.0.0";
    };

    openFirewall = false;      # explicit list above
  };

  systemd.services.navidrome.serviceConfig = {
    # The module's own hardening is unusually complete for nixpkgs — it
    # already sets RootDirectory, BindReadOnlyPaths, PrivateUsers,
    # CapabilityBoundingSet="" and a syscall filter.  What follows is the
    # small remainder, plus one restatement that is load-bearing.
    #
    # ProtectSystem/ReadWritePaths RESTATED: the module achieves read-only
    # music through RootDirectory + BindReadOnlyPaths, which is a stronger
    # mechanism than this one but is also an upstream implementation
    # detail.  Naming the property here means a future nixpkgs bump that
    # drops the chroot cannot silently make the music library writable.
    ProtectSystem  = "strict";
    ReadWritePaths = [ "/var/lib/navidrome" ];

    # ── PrivateTmp IS LOAD-BEARING, AND `ProtectSystem = "strict"` ABOVE ──
    #    IS WHY
    #
    # Without it the scan runs, reports success, and imports NOTHING:
    #
    #   level=warning msg="gotaglib: Error reading metadata from file.
    #     Skipping" error="init module: get runtime once: create directory
    #     /tmp/go-taglib-wasm: mkdir /tmp: read-only file system"
    #   Scanner: Completed processing folder audioCount=526 tracksImported=0
    #
    # `audioCount=526 tracksImported=0` is the shape of this failure: 526
    # files seen, every one skipped, scan "Completed", exit status fine,
    # unit active.  The only symptom is an empty library.
    #
    # Since 0.60 Navidrome reads tags through a WASM taglib that
    # materialises its runtime under /tmp — the same WASM engine the
    # module's own `MemoryDenyWriteExecute = false` comment is about.
    # Upstream sets that one and not this one, because upstream does not
    # set `ProtectSystem` at all: with the module alone /tmp is writable
    # and the problem does not arise.
    #
    # SO THIS IS A COST OF THE LINE ABOVE, NOT AN UPSTREAM BUG.  Keeping
    # ProtectSystem = "strict" is still right — it is what stops a future
    # nixpkgs bump that drops the chroot from silently making the music
    # library writable — but it has to come with somewhere to write.
    #
    # PrivateTmp rather than adding /tmp to ReadWritePaths: this gets a
    # private tmpfs that dies with the unit, instead of a handle on the
    # container's shared /tmp.  For a service whose whole purpose here is
    # to read a tree it must never modify, the isolated option is the one
    # to take.
    PrivateTmp     = true;

    ProtectProc    = "invisible";
    RemoveIPC      = true;
    ProtectHostname = true;

    # NOT MemoryDenyWriteExecute — the module explicitly sets it false
    # with a comment ("0.60.0 Taglib introduces WASM JIT that requires
    # this"), and overriding that would break tag reading on every scan.
    # Fifth runtime in this file that JITs; do not add it.
    #
    # NOT a SystemCallFilter override.  The module already ships
    # "@system-service" + "~@privileged", which is the same shape as
    # arrSyscallFilter WITHOUT the trailing "@chown" re-permit.  Navidrome
    # never chowns anything — it writes only into its own StateDirectory,
    # which systemd has already created with the right ownership — so
    # adding the re-permit would widen the filter for no caller.  The
    # audiobookshelf incident this file records (killed at startup by the
    # filter, status=31/SYS) was a service that DID need it; this one does
    # not, and the difference is worth stating rather than copying the
    # binding out of habit.
  };
  ##########################################################################
  # M17 — BINDERY.  Ebooks: the last media class with no acquisition
  # automation.  Readarr is archived (its metadata backend died);
  # Bindery is the successor picked on FIT — see ./pkgs/bindery.nix for
  # the survey correction (upstream's own repo description was the stale
  # artifact) and docs/history.md's M17 for the full comparison.
  #
  # ── EVERY M14 DEPLOY DEFECT, ANSWERED IN PLACE ───────────────────────
  #
  #   1. "Read the unit" — there is no unit to read: no module exists,
  #      so this one is written whole, with the full directive set and
  #      arrSyscallFilter (whose trailing @chown is M14's SIGSYS fix).
  #   2. Empty-state-dir tmpfiles deadlock — the state dir is created
  #      already OWNED by uid 3028 (tmpfiles above), and both DB_PATH
  #      and DATA_DIR are pinned inside it, so first start creates files
  #      in a directory it owns and nothing transitions ownership.
  #   3. Credentials it cannot read — Bindery has none staged: it MINTS
  #      its own API key (Settings → General) and holds its own client
  #      credentials in its DB.  Prowlarr's Torznab keys and
  #      qBittorrent's login are entered in its UI (manual steps in the
  #      PR), the same posture as Sonarr/Radarr.  Nothing here does a
  #      bare `cat` of a root-owned file on a timer.
  #   4. Failed-oneshot-on-a-timer invisibility — NOT APPLICABLE BY
  #      SHAPE: this is a long-running service, and a long-running
  #      service that dies is loud (SN4's own distinction).  No timer,
  #      no OnFailure debt.
  #
  # ── BINDERY_AUDIOBOOK_DIR — SET, AND THE OLD NOTE WAS FALSIFIED ──────
  #
  #   This block used to say the variable was "deliberately not
  #   configured", because "audiobook acquisition is NOT set up in its
  #   UI".  THAT SECOND CLAUSE WAS NEVER CHECKED AGAINST THE RUNNING
  #   SERVICE, AND IT WAS WRONG.  Measured 2026-09-27: Bindery's
  #   Audiobookshelf import created 32 book rows with media_type
  #   `audiobook` or `both`, every one of them monitored, and by the time
  #   anyone looked it had acquired FOUR audiobooks — 2.8 GB of MP3 and
  #   M4B — and filed them exactly where the first clause predicted:
  #
  #     /srv/media/library/books/Ayn Rand/Atlas Shrugged (2012)/…m4b
  #     /srv/media/library/books/Blake Crouch/Dark Matter- A Novel (2016)/
  #     …
  #
  #   So the guard was one unset environment variable in front of a code
  #   path that was already live.  The comment described an intention;
  #   the tree recorded what actually happened.  Do not restore it.
  #
  #   THE VARIABLE IS NOW SET, and that is a REVERSAL of M17's read-only
  #   posture rather than a tidy-up, so it is argued rather than asserted.
  #   M17 mounted /srv/audiobooks read-only for this service on the
  #   grounds that "a second writer into that tree from another product's
  #   quality logic is the two-systems-one-library failure M4/M12 exist to
  #   avoid".  That argument is still correct in the abstract.  What
  #   changed is that the alternative turned out to be WORSE: with the
  #   variable unset the audiobooks do not stop arriving, they arrive in
  #   the EBOOK library instead — so the choice was never "one writer or
  #   two", it was "audiobooks in the audiobook tree, or audiobooks in the
  #   wrong tree".  Between those, the audiobook tree wins.
  #
  #   lgo asked for Bindery and Audiobookshelf to be connected
  #   (2026-09-27); this is that connection, and the read-only enforcement
  #   it costs is named here so nobody re-reads M17 and thinks the mount
  #   drifted by accident.
  #
  #   IT TAKES TWO VARIABLES, not one.  BINDERY_AUDIOBOOK_DIR is where
  #   finished audiobooks are FILED; BINDERY_AUDIOBOOK_DOWNLOAD_DIR is
  #   where they are DOWNLOADED, and it does not follow
  #   BINDERY_DOWNLOAD_DIR any more than BINDERY_DB_PATH follows
  #   BINDERY_DATA_DIR.  Left unset it falls back to the ebook download
  #   dir, which is the same shape of bug one level down: the audiobooks
  #   still arrive, they just arrive in the ebook tree.  Measured
  #   2026-10-03, with it unset and the qBittorrent `audiobooks` category
  #   carrying no save path of its own, 55 audiobook torrents had
  #   collected in qBittorrent's default `torrents/complete/audiobooks`
  #   and Bindery's own download-client health check reported `error`.
  #
  #   NARROWED AS FAR AS IT GOES: ReadWritePaths gains
  #   ${audiobooksRoot}/library and NOT ${audiobooksRoot}.  Storyteller's
  #   output tree (${audiobooksRoot}/synced) and its staging pool
  #   (${audiobooksRoot}/ebooks) stay read-only to this service, so the
  #   one thing M14 and M17 both cared about — that nothing else writes
  #   into Storyteller's directories — is still enforced by the unit.
  #
  # ── WHAT IS DELIBERATELY NOT CONFIGURED ──────────────────────────────
  #
  #   BINDERY_TRUSTED_PROXY / BINDERY_URL_BASE.  Distinct hostname, no
  #   subpath, and nothing consumes client IPs from it — same as every
  #   other *arr here.
  #
  #   A MINIMUM-SEEDERS FILTER, because there is nothing to configure.
  #   Bindery has no such concept — the only seed-related setting it has
  #   is `seed_ratio`, which is the upload side — so it grabs 0-seed
  #   releases as readily as well-seeded ones and then fails them as
  #   "stalled: no peers".  Prowlarr's `appMinimumSeeders` does NOT reach
  #   it either: that field is only propagated to *arr apps on sync.
  #   The queue therefore needs periodic sweeping, which is a runbook and
  #   not a setting — see docs/runbooks/bindery-dead-torrent-sweep.md.
  ##########################################################################
  systemd.services.bindery = {
    description = "Bindery — ebook acquisition and library manager";
    wantedBy    = [ "multi-user.target" ];

    # ── PROWLARR IS AN ORDERING DEPENDENCY, FOUND BY READING FAILURES ──
    #
    # `after = [ "network.target" ]` alone was not enough, and the
    # evidence is in Bindery's own log: on the 2026-09-26 18:47 boot its
    # startup sync failed with
    #
    #   prowlarr startup sync failed … dial tcp 10.0.90.13:9696:
    #   connect: connection refused
    #
    # at 18:47:13 — the same second prowlarr.service entered active.  Six
    # of the fifteen queue failures found on 2026-09-27 were the same
    # race one step later ("fetch torrent content: … context deadline
    # exceeded" against that address), NOT the dead-torrent failures they
    # were sitting next to and were initially mistaken for.
    #
    # `wants` rather than `requires`: Prowlarr being down should make
    # Bindery's searches fail, which is visible, rather than refuse to
    # start it at all, which is not.
    after       = [ "network.target" "prowlarr.service" ];
    wants       = [ "prowlarr.service" ];

    environment = {
      BINDERY_PORT         = toString binderyPort;
      BINDERY_DATA_DIR     = "/var/lib/bindery";
      # Does NOT follow DATA_DIR — measured, see ./pkgs/bindery.nix.
      # Unset, the compiled-in default is /config/bindery.db and the
      # service dies on mkdir at first start.
      BINDERY_DB_PATH      = "/var/lib/bindery/bindery.db";
      BINDERY_LIBRARY_DIR  = "/srv/media/library/books";
      BINDERY_DOWNLOAD_DIR = "/srv/media/torrents/books";
      # The AUDIOBOOK download tree, and it does NOT follow
      # BINDERY_DOWNLOAD_DIR — see the block above for why leaving it
      # unset made audiobooks share the ebook download dir.  Must match
      # the qBittorrent `audiobooks` category's save path exactly;
      # Bindery's download-client health check compares the two and
      # reports `error` when they disagree.
      BINDERY_AUDIOBOOK_DOWNLOAD_DIR = "/srv/media/torrents/audiobooks";

      # Audiobooks go to Audiobookshelf's library, NOT to the ebook
      # library dir.  See the long block above for why this reverses
      # M17's read-only posture and why the alternative was worse.
      BINDERY_AUDIOBOOK_DIR = "${audiobooksRoot}/library";
      # Phone-home off, same call as every service here that offers it.
      BINDERY_TELEMETRY_DISABLED = "true";
    };

    serviceConfig = {
      Type  = "simple";
      User  = "bindery";
      Group = "media";

      ExecStart  = lib.getExe bindery;
      Restart    = "on-failure";
      RestartSec = "30s";

      # Group-writable output: the import chain into /srv/media depends
      # on it, exactly as the slskd UMask finding proved for music.
      UMask = "0002";

      NoNewPrivileges  = true;
      PrivateTmp       = true;
      ProtectSystem    = "strict";
      RemoveIPC        = true;
      RestrictSUIDSGID = true;

      # ${audiobooksRoot}/library and NOT ${audiobooksRoot}: see the
      # BINDERY_AUDIOBOOK_DIR block above.  Storyteller's `synced` output
      # and its `ebooks` staging pool stay read-only to this service, so
      # the M14 rule that nothing else writes into Storyteller's
      # directories survives this change and is enforced here rather than
      # being a convention.
      ReadWritePaths = [
        "/srv/media"
        "/var/lib/bindery"
        "${audiobooksRoot}/library"
      ];

      CapabilityBoundingSet   = "";
      PrivateDevices          = true;
      ProtectClock            = true;
      ProtectControlGroups    = true;
      ProtectHostname         = true;
      ProtectKernelLogs       = true;
      ProtectKernelModules    = true;
      ProtectKernelTunables   = true;
      ProtectProc             = "invisible";
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      RestrictNamespaces      = true;
      RestrictRealtime        = true;
      LockPersonality         = true;
      SystemCallArchitectures = "native";
      SystemCallFilter        = arrSyscallFilter;

      # ProtectHome CAN be true here, unlike lidarr's and
      # audiobookshelf's units: the directive shields /home and /root,
      # not /var/lib, and this service's home is /var/lib/bindery — so
      # it costs nothing and closes two directories nothing here reads.
      ProtectHome = true;

      # Go does not JIT — the first unit in THIS container that can
      # carry the directive (every earlier rejection in this file is a
      # .NET or V8 runtime).
      MemoryDenyWriteExecute = true;
    };
  };
  };
}
