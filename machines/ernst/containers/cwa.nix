# machines/ernst/containers/cwa.nix
#
# Calibre-Web-Automated — the ebook library, its OPDS catalogue, its Kobo sync
# endpoint and its KOReader progress-sync server.
#
# ── IT DID NOT EXIST BEFORE THIS FILE, WHATEVER THE OTHER COMMENTS SAY ──────
#
#   containers/arr.nix says "Komga and CWA already serve the READING side in
#   this household" and docs/history.md repeats it in four places.  It was not
#   true: there was no CWA in this repo, no container on ernst, no podman
#   workload, and no Technitium record.  The sentence described an intention
#   that was never built, and it was load-bearing in the wrong direction —
#   Kapowarr's placement argument leans on it.
#
#   So this is GREENFIELD.  There is no deployed version to report, no pin to
#   bump, and no 3.x→4.x migration to perform, because there is no 3.x here to
#   migrate from.  It starts at 4.0.6 with an empty library.
#
#   THAT LAST SENTENCE STOPPED BEING TRUE ON 2026-09-17 — see "THE LIBRARY IS
#   NO LONGER EMPTY" below.  The greenfield paragraph above is kept as written
#   because it is the record of how this was BUILT, and every argument in it
#   still holds; what changed is the contents, not the deployment.
#
# ── TIER: PODMAN, and the reason is not a preference ────────────────────────
#
#   CWA IS NOT IN nixpkgs.  What nixpkgs has is `calibre-web` 0.6.26 — the
#   UPSTREAM project, a different codebase.  Calibre-Web-Automated is
#   crocodilestick's fork, and everything this deployment is for lives only in
#   the fork: the ingest pipeline, the Kobo endpoint, the KOReader sync server,
#   the OIDC support.  Checked before assuming: `pkgs.calibre-web.version`
#   evaluates to "0.6.26-unstable-2026-03-01" at ernst's pin.
#
#   Upstream ships a container image and a compose file and nothing else, which
#   is the same test M9's TubeSync, M14's Storyteller and RomM applied, with
#   the same answer.  So it takes the podman tier as its FOURTH occupant.
#
#   `virtualisation.oci-containers` INSIDE AN NSPAWN CONTAINER IS REJECTED, as
#   every service on this tier is required to restate: the value of
#   containers/arr.nix is that upstream units and their `systemd-analyze`
#   scores stay legible, and an opaque image inside it is opaque to all three.
#
#   THE COST, accepted explicitly: an image we do not build, and a
#   `systemd-analyze security` score for `podman-cwa.service` that measures
#   podman rather than CWA.
#
# ── NETWORKING: THE cloudflared PAIR, REUSED ────────────────────────────────
#
#   02:00:00:90:00:0d / 10.0.90.21 was M16's cloudflared container and was
#   marked FREE AGAIN by M18 when the tunnel was deleted.  This takes it back
#   rather than allocating .23, because an address marked free and then never
#   reused is how the allocation table stops being trusted.
#
#   THE DHCP RESERVATION ON THE UDM-Pro MUST BE RE-POINTED, NOT ADDED
#   ALONGSIDE.  allocations.nix already warns that a reservation for a
#   MAC nothing uses is how an address gets handed out twice; the MAC here is
#   the same one cloudflared had, so if the old reservation still exists it is
#   already correct and nothing needs doing.  Verify before deploying — this is
#   in the manual checklist.
#
# ── INGRESS: app-API tier, and the web UI is handled DIFFERENTLY ────────────
#
#   `cwa.goclan.org` is in `appApiHosts` (containers/ingress-policy.nix), so
#   its Traefik router carries NO forward-auth and the guard in traefik.nix
#   refuses to build if anyone adds it.  Three separate app protocols make that
#   necessary, and each is a distinct path — verified by reading the routes in
#   the v4.0.6 source rather than from documentation:
#
#     /opds/**                    OPDS, HTTP Basic.
#     /kobo/<auth_token>/v1/...   the Kobo device sync.  THE TOKEN IS IN THE
#                                 URL PATH (`Blueprint("kobo", url_prefix=
#                                 "/kobo/<auth_token>")`), and a Kobo e-reader
#                                 has no browser at all — there is nothing on
#                                 the device that could render a login page.
#     /kosync/**                  KOReader's progress protocol, RFC 7617
#                                 header auth.
#
#   THE WEB UI IS NOT LEFT UNAUTHENTICATED, and this is the part a proxy-level
#   bypass alone cannot reach.  CWA speaks OIDC natively, so the browser
#   surface goes to Authelia's OIDC provider INSIDE the application: real
#   two-factor, Authelia's per-user regulation, the same identity as every
#   other service here.  The client is registered declaratively in
#   containers/authelia.nix.
#
#   BUT THE CWA SIDE OF THAT IS A MANUAL STEP, AND IT CANNOT BE OTHERWISE.
#   Verified by grepping every `os.environ` read in the v4.0.6 source: the only
#   OAuth-related environment variable that exists is `OAUTH_SSL_STRICT`.  The
#   provider, client id, client secret and metadata URL are rows in CWA's
#   app.db, written through Admin → Edit Basic Configuration.  There is no
#   config file to template and no env var to set.  Do not add one to this file
#   on the strength of a documentation page; it will be silently ignored.
#
# ── KOREADER SYNC: DEFAULT OFF AT 4.0.6, AND ENABLING IT IS ALSO MANUAL ─────
#
#   The README says KOReader sync is "enabled by default".  IT IS NOT, and the
#   README is stale.  From the v4.0.6 source:
#
#     scripts/cwa_schema.sql:53
#       koreader_sync_enabled SMALLINT DEFAULT 0 NOT NULL
#
#   and `cps/progress_syncing/settings.py` reads that column and nothing else,
#   with an except-branch that returns False "to avoid unexpected DB writes
#   when setting is missing".  It fails closed.  The v4.0.6 release notes say
#   why the default moved: disabling it "prevents background checksum
#   calculations and database table creation".
#
#   THE STARTUP COST, in upstream's own words, logged when you turn it on
#   (cps/cwa_functions.py):
#
#     "KOReader sync enabled: checksum backfill runs at startup and may
#      temporarily lock metadata.db.  Disable and restart the container to
#      stop a running backfill."
#
#   So on a library of any size the first start after enabling is slow and the
#   web UI may block on metadata.db while it runs.  On an EMPTY library the
#   backfill is trivial, which was the reason to turn it on before the library
#   filled rather than after.
#
#   THAT ADVICE WAS TAKEN AND THE BILL HAS NOW BEEN PAID, which is worth a
#   measurement rather than a worry: the 2026-09-17 import (below) triggered a
#   backfill over all 5268 format rows and it completed in UNDER A MINUTE —
#   5195 queued, 0 failed, 73 skipped.  "Slow first start" is real but the
#   scale here was seconds, not the outage the warning implies.
#
#   IT IS A UI TOGGLE (`cwa_settings.html`, "Enable KOReader Sync (CWA
#   Plugin)"), stored in app.db, with no environment override.  A web search
#   suggested an env var exists; the source says it does not, and the source
#   wins.  The step is in docs/guides/ernst-app-api-ingress.md.  Its tooltip
#   notes it does NOT require a restart to take effect.
#
# ── THE LIBRARY: ITS OWN, AND KOMGA'S IS NOT TOUCHED ────────────────────────
#
#   CWA needs a CALIBRE LIBRARY — a directory with a metadata.db and an
#   Author/Title/ tree it restructures files into.  That is not what
#   /srv/media/library/books is: that is Bindery's plain output directory, and
#   it is also one of the two trees Komga reads.
#
#   POINTING CWA AT IT WAS REJECTED.  CWA would convert the tree in place,
#   which is exactly the "do not restructure the library" constraint, and it
#   would do it to a directory another service is serving.  Komga's library
#   configuration is deliberately untouched by this file.
#
#   So CWA gets ITS OWN library root, and the two are complementary rather than
#   overlapping — the same call M14 made for Audiobookshelf and Storyteller:
#
#     /srv/media/library/books    Bindery writes, Komga reads.  UNCHANGED.
#     /srv/media/library/comics   Kapowarr writes, Komga reads.  UNCHANGED.
#     /srv/media/library/calibre  CWA owns entirely.  Started empty; holds the
#                                 old Arch server's library since 2026-09-17.
#     /srv/media/ingest/cwa       CWA's watch folder.  Files are DELETED after
#                                 processing — that is upstream's documented
#                                 behaviour, so nothing that matters may be the
#                                 only copy in here.
#
#   ── THE LIBRARY IS NO LONGER EMPTY (2026-09-17) ──────────────────────────
#
#   /srv/media/library/calibre now holds 4472 BOOKS, 12.4 GB, 1759 author
#   directories.  They came from the old Arch server.
#
#   WHERE THEY WERE, AND WHY NOBODY FOUND THEM: the whole Calibre library —
#   metadata.db, the Author/Title (id) tree, metadata_db_prefs_backup.json —
#   had been restored into /srv/audiobooks/ebooks, which containers/arr.nix
#   declares as "the DRM-free ebook halves, staged by hand" for Storyteller.
#   NOTHING SCANS THAT DIRECTORY — Storyteller takes its input through its own
#   web UI — so a complete library sat inert in it for weeks while this file
#   described itself as empty.  arr.nix's comment is corrected alongside.
#
#   HOW IT WAS MOVED, and the two options that were rejected:
#
#     REJECTED — pour the files through /cwa-book-ingest.  5268 files, one
#       ebook-convert each, and the curated metadata re-fetched from scratch
#       rather than kept.  Days of CPU for a WORSE library, and ingest deletes
#       what it processes.
#     REJECTED — repoint this file's libraryDir at /srv/audiobooks/ebooks.  One
#       line and no copy, but CWA restructures a tree in place and that tree is
#       on another service's dataset — the same argument the section above
#       makes against /srv/media/library/books, for the same reason.
#     DONE — rsync the library wholesale into the root CWA already owns, chown
#       to cwa:cwa.  A Calibre library is self-contained, so CWA adopted it
#       with no import step at all: metadata, series, tags and covers intact.
#
#   THE SCHEMA MIGRATION THIS FILE SAID WOULD NEVER HAPPEN, DID.  The header's
#   4.0.x paragraph argues that starting empty means "none of those migration
#   paths is ever exercised here".  The imported database is Calibre schema
#   user_version 25, so 4.0.6 was handed exactly the case that paragraph
#   expected to avoid.  IT WENT THROUGH CLEANLY — no migration error, no
#   sqlite3.OperationalError, 4472 books readable afterwards.  Recorded as a
#   measurement, not as a reason to relax the pin.
#
#   73 DANGLING FORMAT ROWS CAME WITH IT, and they are NOT import damage.  The
#   backfill logged 73 "SKIP: File not found"; each one was checked against the
#   SOURCE tree and is missing there too — rows in the old metadata.db whose
#   files were lost on the Arch server long before this copy.  Do not go
#   looking for them in a snapshot of /srv/media; the copy is byte-complete and
#   was verified file-by-file against the source before the source was emptied.
#
#   /srv/audiobooks/ebooks IS NOW EMPTY and remains Storyteller's staging pool,
#   still created by arr.nix's audiobooks-tree.service as 2770 root:media.  The
#   12 GB it gave up does not return to the pool immediately: zdata/audiobooks
#   carries com.sun:auto-snapshot=true, so the data is pinned in the auto-snaps
#   until retention rolls over.
#
#   THE PRE-IMPORT STATE IS KEPT at /srv/state/cwa/pre-import-backup-20260917/
#   — the one-book metadata.db this deployment had accumulated, plus its Dune
#   test import.  DELETABLE once nobody is nervous; it is not referenced by
#   anything and CWA does not read it.
#
#   WIRING BINDERY'S OUTPUT INTO CWA'S INGEST IS NOW DONE — lgo's decision,
#   2026-09-27.  This paragraph used to leave it as "an explicit non-decision",
#   on the grounds that it would move ebook acquisition from "Komga reads a
#   plain tree" to "CWA owns the tree and Komga reads CWA's output".
#
#   BOTH HALVES OF THAT OBJECTION ARE GONE, and for different reasons:
#
#     1. KOMGA NO LONGER READS EBOOKS AT ALL.  It serves comics, and its
#        /srv/media/library/books library was removed by lgo on 2026-09-27.
#        So there is no second reader whose topology could change.
#     2. IT IS NOT A REDIRECT, IT IS A COPY.  Bindery's own CWA integration
#        (`cwa.ingest_path`, set in its UI) copies the finished file into the
#        ingest folder and KEEPS ITS OWN — upstream's wording, and measured:
#        BINDERY_LIBRARY_DIR is untouched by it.  So the thing the paragraph
#        feared — CWA taking ownership of Bindery's tree — does not happen in
#        either direction.  /srv/media/library/books stays exactly as it is.
#
#   THE COST, stated rather than buried: every acquired ebook exists twice, in
#   Bindery's plain tree and again inside CWA's Calibre library, and the second
#   copy is a COPY rather than a hardlink because CWA converts and restructures
#   what it ingests.  This is the one path into /srv/media that deliberately
#   breaks invariant #2's hardlink property, and it is affordable only because
#   ebooks are kilobytes to a few megabytes.  Do not reach for this shape for
#   anything measured in gigabytes.
#
#   AND THE INGEST FOLDER STILL DELETES WHAT IT PROCESSES, which is now a
#   SAFETY property rather than a hazard: the copy is the disposable one and
#   Bindery holds the original.
#
# ── SHELFMARK ─────────────────────────────────────────────────────────────
#
#   Not configured anywhere in this fleet — no Nix, no container, no DNS
#   record, no reference in any file.  There is nothing pointed at BookLore to
#   flag, because there is no Shelfmark and no BookLore either.  Recorded
#   because the absence was checked rather than assumed.
#
# ── Storage layout on this host (see machines/ernst/disko.nix) ──────────────
#
#   /srv/state/cwa/config      zdata/state   RW at /config
#     app.db                                 CWA's own settings, users, OAuth
#                                            client config and the KOReader
#                                            toggle.  NOT re-derivable.
#   /srv/media/library/calibre zdata/media   RW at /calibre-library
#   /srv/media/ingest/cwa      zdata/media   RW at /cwa-book-ingest
{ config, lib, pkgs, ... }:
let
  ############################################################################
  # Identity.
  ############################################################################

  netns     = "cwa";
  vethHost  = "vb-cwa";

  # ── `cw0`, NOT `eth0`.  THIS FILE SHIPPED WITH `eth0` AND IT DID NOT WORK ──
  #
  # containers/storyteller.nix states the rule at length under "THE RULE FOR
  # THE NEXT ONE": every podman-tier namespace must use a UNIQUE interface
  # name, and "a third service must not be called `eth0` or `st0` either".
  # This was the fourth, it was called `eth0`, and it reproduced the documented
  # failure exactly — including the log line that file quotes verbatim:
  #
  #   cwa-dhcp.service: Deactivated successfully.
  #   dhcpcd[769633]: sending commands to dhcpcd process
  #
  # dhcpcd keys its pidfile and control socket on the INTERFACE NAME
  # (/run/dhcpcd/eth0-4.sock), and these units differ only in their NETWORK
  # namespace — `NetworkNamespacePath=` does not change the mount namespace, so
  # they all see the same /run.  TubeSync owns `eth0`; this instance found its
  # socket, handed over its arguments as a client and exited 0.  The lease was
  # applied in TubeSync's namespace, where it is a no-op.
  #
  # THE FAILURE IS SILENT IN THE WORST WAY, which is why the name is worth this
  # much comment: the unit SUCCEEDS, the container starts and reports healthy,
  # the veth is up with the right MAC on the right VLAN — and `ip -4 addr show`
  # in the namespace is empty, so Traefik 502s. `Restart = on-failure` cannot
  # help because nothing failed.
  #
  # `eth0` was copied from the nspawn containers, where it IS correct —
  # container-init renames host0 to eth0 and each has its own mount namespace,
  # so there is no shared /run to collide in. The two tiers look alike here and
  # are not. A FIFTH podman service must not be `eth0`, `st0`, `rm0` or `cw0`.
  vethNs    = "cw0";
  mac       = "02:00:00:90:00:0d";   # reused from M16's cloudflared — see header
  vlanId    = 90;

  # Continuing the 3000-range family.  Next free was 3031 before this round;
  # containers/arr.nix took 3031 (komga) and 3032 (navidrome) in the same
  # change, so this is 3033.  The table in machines/ernst/allocations.nix is
  # updated alongside.
  #
  # OWN GROUP, NOT `media`.  CWA writes only into trees it owns outright — its
  # own Calibre library and its own ingest folder — and has no hardlink
  # relationship with anything the *arr manage.  Putting it in `media` would
  # hand an internet-facing service a write handle on the film and television
  # library for no reason it could use.
  cwaUid = 3033;
  cwaGid = 3033;

  # Podman passes uids through unmapped (rootful), so a number chosen here is a
  # number on zdata — the same property tubesync, storyteller and romm rely on.
  # PUID/PGID below must agree with it.
  webPort = 8083;

  traefikAddr = "10.0.90.12";

  # The `media` gid, for the INGEST DIRECTORY ONLY — see the cwa-dirs script.
  # CWA itself is deliberately NOT a member of this group; the paragraph above
  # is unchanged and still the reason.
  mediaGid = 3000;

  stateDir   = "/srv/state/cwa";
  libraryDir = "/srv/media/library/calibre";
  ingestDir  = "/srv/media/ingest/cwa";

  ############################################################################
  # The image, pinned by DIGEST — never by tag.
  #
  # Measured with skopeo on 2026-09-08:
  #   ghcr.io/…/calibre-web-automated:v4.0.6  sha256:c31a738b…  built 2026-02-04
  #   ghcr.io/…/calibre-web-automated:latest  sha256:c31a738b…  ← the same image
  #
  # TO BUMP: pick the new tag, then
  #   skopeo inspect --format '{{.Digest}}' docker://<image>:<tag>
  # and update BOTH lines of the pair.
  #
  # 4.0.6 IS THE NEWEST STABLE and the tag list is worth a note, because it
  # looks alarming and is not: there are ~200 `dev-NNN` tags published after
  # it, the newest being dev-424.  Those are CI builds of `main`, not releases.
  # The stable line has been quiet since February; that is upstream's release
  # cadence, not an abandoned project.  Do not "upgrade" to a dev tag.
  #
  # THE 4.0.x SERIES WAS BUMPY AND 4.0.6 IS THE POINT TO START AT.  From the
  # release notes, the run of fixes between 4.0.0 and 4.0.6 is mostly database:
  # sqlite3.OperationalError migration lockups and an app.db healthcheck
  # (4.0.1), SQLAlchemy 2.x InvalidRequestError during migrations and Calibre 9
  # schema changes (4.0.2), a metadata.db rebuild-from-OPF recovery path
  # (4.0.4), and WAL-mode handling for network shares (4.0.5).  Starting at
  # 4.0.6 with an empty library was supposed to mean none of those migration
  # paths is ever exercised here.
  #
  # IT NO LONGER MEANS THAT, and the correction matters more than the original
  # claim did: the 2026-09-17 import handed 4.0.6 a schema-25 Calibre database
  # of 4472 books, which is precisely the migration case the 4.0.1–4.0.5 fixes
  # are about.  It was clean — but "this deployment never migrates" is no
  # longer a reason to be relaxed about a version bump.  See "THE LIBRARY IS NO
  # LONGER EMPTY" in the header.
  ############################################################################
  cwaTag    = "v4.0.6";
  cwaDigest = "sha256:c31a738b6d5ec6982c050063dd3f063b6943eb1051fc81144789f840d9093a8d";
in
{
  ##############################################################################
  # Podman is enabled by containers/tubesync.nix (M9), the tier's first
  # occupant, and is NOT re-enabled here — one owner, one place.
  ##############################################################################

  users.users.cwa = {
    isSystemUser = true;
    uid          = cwaUid;
    group        = "cwa";
    home         = stateDir;
  };
  users.groups.cwa.gid = cwaGid;


  ##############################################################################
  # The container.
  ##############################################################################
  #
  # Declared through modules/containers/podman-netns.nix, which generates the
  # netns unit (namespace, veth, MAC, DROP policy and its accepts, teardown),
  # the DHCP client, the host-side networkd file, the dirs unit, the
  # oci-containers entry and the ordering between them.
  clanarchy.podmanContainers.cwa = {
    enable = true;
    mac    = "02:00:00:90:00:0d";
    interface = "cw0";

    # NO `uidgid`: this image runs its entrypoint as root and drops to
    # PUID/PGID itself, which is passed as environment below.

    # THE LIBRARY AND THE INGEST TREE ARE BOTH UNDER /srv/media, so the guard
    # names the MOUNT POINT. The dirs unit derives a mount unit from this
    # path, and a subdirectory would produce a `Requires=` on a unit nothing
    # defines; `findmnt --target` walks up to the same filesystem anyway.
    extraGuardedMounts = [
      { path = "/srv/media"; source = "zdata/media"; fstype = "zfs"; }
    ];

    stateDirs = [
      { path = stateDir;            owner = cwaUid; group = cwaGid;   mode = "0750"; }
      { path = "${stateDir}/config"; owner = cwaUid; group = cwaGid;   mode = "0750"; }
      { path = libraryDir;          owner = cwaUid; group = cwaGid;   mode = "0750"; }
      # 2770 and group `media`, so Bindery can drop ebooks in. Re-applied
      # after start by cwa-ingest-perms below — see its header for why.
      { path = ingestDir;           owner = cwaUid; group = mediaGid; mode = "2770"; }
    ];

    allowFrom = [
      { peer = traefikAddr; port = webPort; }
    ];

    # The health poll the ingest-perms unit below waits on. `podman-cwa` is
    # "started" once the container is CREATED, so anything that needs a
    # RUNNING CWA has to wait for this instead.
    healthcheck.enable = true;

    images.cwa = {
      image = "ghcr.io/crocodilestick/calibre-web-automated@${cwaDigest}";
      environment = {
        TZ = "Europe/Berlin";
        PUID = toString cwaUid;
        PGID = toString cwaGid;
        CWA_PORT_OVERRIDE = toString webPort;
      };
      volumes = [
        "${stateDir}/config:/config"
        "${libraryDir}:/calibre-library"
        "${ingestDir}:/cwa-book-ingest"
      ];
      ports = [ ];
    };
  };

  ##############################################################################
  # THE INGEST DIRECTORY'S PERMISSIONS, RE-APPLIED AFTER THE CONTAINER STARTS.
  #
  # ── WHY THIS UNIT EXISTS: cwa-dirs IS NOT ENOUGH, MEASURED ─────────────────
  #
  #   PR #250 gave the ingest directory `2770 cwa:media` in cwa-dirs so Bindery
  #   (uid 3028, gid media) could drop ebooks into it.  That shipped, deployed
  #   cleanly, and DID NOT WORK.  Measured on ernst immediately after:
  #
  #     $ stat -c '%A %U:%G' /srv/media/ingest/cwa   # after cwa-dirs
  #       drwxrws--- cwa:media                       # correct
  #     $ systemctl restart podman-cwa.service
  #     $ stat -c '%A %U:%G' /srv/media/ingest/cwa   # after the container
  #       drwxr-xr-x cwa:cwa                         # reverted
  #
  #   The image is a LinuxServer.io base, and its s6 init chowns and chmods the
  #   paths it has been given to PUID:PGID on EVERY start.  So cwa-dirs sets
  #   the directory correctly during activation and the container undoes it
  #   moments later, every boot and every restart.  Bindery then gets EPERM and
  #   its CWA push fails silently — the integration logs a copy failure, not a
  #   permission error, so this would have been slow to attribute.
  #
  #   THE GENERAL LESSON, worth more than this directory: a tmpfiles or
  #   install-time mode on a path that is bind-mounted into an opaque image is
  #   an OPENING BID, not a setting.  The image gets the last word.  Anywhere
  #   else in this file that assumes otherwise is wrong for the same reason.
  #
  # ── WHY IT WAITS FOR HEALTHY RATHER THAN RUNNING IMMEDIATELY ───────────────
  #
  #   podman-cwa.service is considered started once the container is created;
  #   the s6 init that does the chown runs asynchronously INSIDE it afterwards.
  #   An ExecStartPost firing straight away would race that init and lose about
  #   as often as it won — the worst kind of fix, because it would appear to
  #   work whenever anyone checked by hand.  The container declares a
  #   healthcheck (podman reports health_status=healthy), so this waits for it
  #   and then re-applies.  Bounded at ~120s so a genuinely broken container
  #   fails this unit rather than hanging the boot.
  #
  #   Separate unit rather than ExecStartPost on podman-cwa, for two reasons:
  #   a two-minute ExecStartPost would keep podman-cwa in `activating` for the
  #   same window and hold up anything ordered after it, and a failure here
  #   should be legible as "the ingest permissions did not stick" rather than
  #   as "CWA failed to start".
  ##############################################################################
  systemd.services.cwa-ingest-perms = {
    description = "Re-apply ${ingestDir} ownership after CWA's image resets it";

    # Runs whenever the container starts, including on every restart — not
    # just at boot.  `wantedBy` on the container unit rather than on
    # multi-user.target is what ties the two together.
    wantedBy = [ "podman-cwa.service" ];

    # ORDERED AFTER THE HEALTH POLL, not after `podman-cwa`. That unit is
    # "started" once the container is CREATED, which is before the image's s6
    # init has run its chown pass — so this used to carry its own 60×2s
    # `podman inspect` loop waiting for health. `healthcheck.enable` in the
    # declaration above generates exactly that wait as `cwa-healthy.service`,
    # with the same 120 s budget, so the loop is gone and the dependency says
    # what it means. `requires` as well as `after`: if the container never
    # becomes healthy there is nothing to correct, and a chown against a
    # half-initialised tree is worse than not running.
    after    = [ "cwa-healthy.service" ];
    requires = [ "cwa-healthy.service" ];

    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -eu

      # Same line as cwa-dirs, and deliberately a duplicate rather than a
      # refactor: cwa-dirs must still create the directory correctly BEFORE
      # the container first mounts it, and this must correct it AFTER.  Both
      # are needed, and collapsing them into one helper would hide that.
      ${pkgs.coreutils}/bin/install -d \
        -o ${toString cwaUid} -g ${toString mediaGid} -m 2770 ${ingestDir}

      echo "re-applied 2770 ${toString cwaUid}:${toString mediaGid} on ${ingestDir}"
    '';
  };


  # ── SCHEDULING PRIORITY, MERGED ONTO THE GENERATED UNIT ─────────────────────
  #
  # Ordering comes from the module (the netns and dirs units declare it from
  # their side). These two numbers do not: they are a judgement about THIS
  # workload, they differ per service — Storyteller is niced harder — and a
  # module option for them would be a passthrough with three different
  # answers and no shared meaning.
  #
  # Ingest conversion is the expensive path: CWA shells out to Calibre's
  # ebook-convert, single-threaded but CPU-hungry, once per book. Add the
  # KOReader checksum backfill, which reads every file in the library, and
  # this competes with Jellyfin transcodes, the HTPC session and an
  # interactive Ollama session on the same box.
  #
  #   Nice = 10        lowers priority against everything on the box.
  #   CPUWeight = 40   biases the cgroup's share only under contention.
  #
  # Not CPUQuota: nobody is waiting on an import, so it should be free to use
  # an otherwise idle box at full speed.
  systemd.services.podman-cwa.serviceConfig = {
    Nice      = 10;
    CPUWeight = 40;
  };
}
