# machines/ernst/containers/immich.nix
#
# Immich — the household photo library (M22 in docs/roadmap.md).  An nspawn
# container on VLAN 90, serving `photos.goclan.org` through Traefik on BOTH
# entrypoints, with its own accounts and no forward-auth.
#
# ── WHAT THIS SERVES, AND FOR WHOM ──────────────────────────────────────────
#
#   lgo      FP5 app auto-backup, plus finished darktable exports pushed from
#            miralda and jens (see modules/desktop/immich-upload-hm.nix).
#   sgo      FP4 app auto-backup.  Sarinah's own account, her own library.
#   Sabine   NO ACCOUNT.  She is sent shared album links, which Immich serves
#            UNAUTHENTICATED to whoever holds the URL.  That is a property of
#            the deployment and not an oversight — see the wan section below,
#            because it is the single strongest argument against putting this
#            vhost behind forward-auth and it is also its own small risk.
#
#   The TV reads it through Kodi (modules/roles/pkgs/immich-kodi.nix), over
#   `https://photos.goclan.org` like any other client — NOT over a direct
#   VLAN-90 hop.  That is deliberate and it is the reason this container's
#   firewall has exactly one source address in it; see "THE KODI PATH" below.
#
# ── TIER: NSPAWN, AND IT IS NOT A CLOSE CALL ────────────────────────────────
#
#   Invariant #1's middle tier is "trusted, storage-heavy", which is this
#   service exactly: `services.immich` is a first-class NixOS module at this
#   pin (2.7.5), it owns 150–200 GB on zdata, and it runs a PostgreSQL and a
#   Redis of its own.  There is no image to escape to and nothing to escape
#   from — the podman tier exists here for upstreams that ship only an OCI
#   image (storyteller, cwa, romm, tubesync), and Immich is not one.
#
#   IT IS NOT PROMOTED TO THE MICROVM TIER EITHER, despite being reachable
#   from the internet, and the reason is the one M20 had to re-derive: the
#   microvm tier is for KILLSWITCH-CARRYING workloads — the VPN guest, whose
#   entire purpose is that traffic must not leave except through a tunnel.
#   Jellyfin, Audiobookshelf, Komga, Navidrome and CWA are all internet-facing
#   and all on this tier.  An internet-facing service does not move up a tier
#   for being internet-facing; it moves up for needing its own kernel.
#
# ── STORAGE: TWO DATASETS, AND THE SPLIT IS LOAD-BEARING ────────────────────
#
#   /srv/photos       zdata/photos, recordsize=1M, auto-snapshot=true.  The
#                     LIBRARY: originals, thumbnails, previews, encoded video.
#                     Bound at /var/lib/immich, which is both the module's
#                     default mediaLocation AND its StateDirectory, so nothing
#                     has to be overridden to make the two agree.
#   /srv/state/immich zdata/state, 128K recordsize.  The DATABASE (PostgreSQL)
#                     and the machine-learning model cache.  Small random
#                     writes; 1M here would turn every index update into a
#                     read-modify-write.
#
#   Splitting them is why each can carry the properties it wants.  Putting the
#   library under /srv/state would give 200 GB of photographs a 128K
#   recordsize; putting the database under /srv/photos would give SQLite-shaped
#   writes a 1M one.  See machines/ernst/disko.nix for the full argument and
#   docs/guides/ernst-zdata-datasets.md for the `zfs create` that must be run
#   BEFORE the first deploy carrying this file.
#
#   REDIS IS THE ONE THING NOT ON zdata, deliberately.  It is a job queue and a
#   cache — Immich refills it by re-running jobs — and it lives on the
#   container's own rootfs under /var/lib/nixos-containers/immich, which #54
#   persists.  A bind for it would be a third mount buying nothing.
#
# ── THE DATABASE AND THE CACHE TALK OVER UNIX SOCKETS, SO THERE IS NO SECRET ─
#
#   `services.immich.database.host` defaults to /run/postgresql and
#   `redis.host` to the module's own unix socket.  The module asserts that a
#   secretsFile is required only when postgres is NOT reached over a socket:
#
#     assertion = !isPostgresUnixSocket -> cfg.secretsFile != null;
#
#   Both stay on their sockets here, so THIS FILE DECLARES NO CLAN VAR AND NO
#   STAGING UNIT.  That is worth stating rather than leaving as an absence: the
#   roadmap's M22 brief budgeted a `immich-db-password` generator and a
#   `immich-secrets` oneshot in the traefik-secrets shape, and neither is
#   needed.  Every failure mode those two would have introduced — a var
#   generated after the deploy so `.path` is `/no-such-path`, a staged copy
#   going stale until someone restarts the unit, a blank prompt stored as an
#   empty credential — is absent by construction rather than handled.
#
#   THE ONE CREDENTIAL THIS SERVICE DOES INVOLVE is an Immich API key, and it
#   does not exist until after the first deploy: it is minted in the web UI by
#   an account that cannot be created before the server is running.  It is
#   therefore NOT a clan var on this machine.  `photo-import` takes it from the
#   environment at the moment an operator runs it (see below), and the laptop
#   uploader — which is a recurring timer and so genuinely needs a stored one —
#   takes it from a clan var on ITS machine, generated as an explicit ordered
#   step.  See modules/desktop/immich-upload-hm.nix.
#
# ── AUTH: THE APPLICATION'S, AND THIS IS THE FLEET'S THIRD app-API NAME ─────
#
#   `photos.goclan.org` is in `ingressPolicy.appApiHosts`, so the guard in
#   containers/traefik.nix REFUSES TO BUILD if anyone attaches the `authelia`
#   middleware to its router.  The argument is the one in that policy file:
#   CAN EVERY CLIENT OF THIS HOSTNAME RENDER A LOGIN PAGE AND FOLLOW A 302?
#
#     Immich mobile (FP5, FP4)  no.  It posts to /api/auth/login and then
#                               carries a bearer token; a 302 to a portal is
#                               an opaque network error to it.
#     The Kodi add-on           no.  It speaks `x-api-key` over http.client
#                               with no cookie jar and no browser at all.
#     A SHARED ALBUM LINK       no, and this one is different in kind — see
#                               below.
#
#   THE SHARED-LINK CLAUSE IS THE INTERESTING ONE AND IT CUTS BOTH WAYS.  A
#   shared album is a URL that Immich answers to an ANONYMOUS caller by
#   design; that is the entire feature, and it is how Sabine sees the albums
#   lgo sends her.  Forward-auth would break it completely — she has no account
#   here and could not get past the portal.  So the exemption is not merely
#   about native clients; part of this vhost is MEANT to be unauthenticated.
#
#   WHICH MEANS THE HONEST STATEMENT OF THE POSTURE IS NOT "Immich's accounts
#   are the boundary".  It is: Immich's accounts are the boundary for the
#   LIBRARY, and possession of a link is the boundary for anything explicitly
#   shared.  A leaked link is a leaked album, permanently, until it is revoked
#   in the UI.  Immich supports an expiry date and a password on each shared
#   link; USE THEM for anything that is not meant to be world-readable, because
#   nothing in this file can.
#
#   WHAT COMPENSATES ON THE PUBLIC PATH, in the order it is relied on:
#     1. Immich's own accounts, which must be strong — a precondition this
#        file cannot enforce; it is in the deploy checklist.
#     2. `wan-ratelimit` + `wan-inflight`, inherited by the wan router.
#     3. `wan-login-ratelimit` on /api/auth/login, a much stricter limit on a
#        higher-priority router — see `wanLoginPaths` in traefik.nix.
#     4. CrowdSec, which sees Immich's 401s in Traefik's access log.
#
# ── THE FIRST-RUN WINDOW, AND THE TWO THINGS THAT CLOSE IT ──────────────────
#
#   Immich's admin signup is UNAUTHENTICATED BY CONSTRUCTION: with no admin
#   yet, /auth/admin-sign-up creates one for whoever posts to it first.  That
#   is the Audiobookshelf failure mode (see traefik.nix's `wanExposed` header),
#   and M14/M18 answered it with "create the account immediately", i.e. with
#   speed.  This file does better, because Immich gives it a mechanism:
#
#     1. `IMMICH_ALLOW_SETUP` (`?? true` in 2.7.5, verified by reading the
#        built server).  `adminSetupOpen` below sets it, and it is FALSE.  The
#        endpoint is off until someone deliberately opens it for one deploy.
#     2. THE PUBLIC A RECORD IS CREATED LAST.  `photos.goclan.org` is on the
#        `wan` entrypoint from the moment this lands, but a name with no public
#        A record is not reachable from the internet no matter what Traefik is
#        willing to serve.  The manual steps in docs/roadmap.md M22 put the
#        record AFTER both accounts exist, deliberately.
#
#   Either one alone would be sufficient.  Both are used because the cost is a
#   boolean and an ordering line, and because Immich additionally refuses a
#   second signup once an admin exists — so after the first login all three are
#   redundant, which is exactly when nobody is paying attention any more.
#
# ── GPU: NONE.  `accelerationDevices = [ ]`, AND THAT IS INVARIANT #5 ───────
#
#   Immich can use a GPU for two different things and this container is denied
#   both, for two different reasons:
#
#     Machine learning (CLIP search, face detection) would want the RX 7900
#     XTX at 0000:03:00.0 — which is the TV's KMS device AND llama-swap's ROCm
#     card, the member of an EXCLUSIVE `gpu` group whose whole point since M21
#     is that only one workload holds it at a time.  A photo indexer that wakes
#     up whenever a phone uploads is the worst possible third claimant.
#     Video thumbnailing/transcoding would want the Granite Ridge iGPU at
#     0000:7b:00.0 — which invariant #5 assigns to Jellyfin's VAAPI, the one
#     job on this machine where a stall is visible on a television.
#
#   So ML and transcoding both run on the CPU.  The cost is real and bounded:
#   the initial smart-search and face-detection pass over ~35k images is hours
#   of 16-core AM5, once, in the background; steady state is a handful of new
#   photos a day.  `accelerationDevices = [ ]` is not merely "do not configure
#   a GPU" — the module turns it into `PrivateDevices = true`, so the container
#   cannot reach a render node even by accident.
#
# ── THE ML MODELS ARE FETCHED FROM THE INTERNET AT RUNTIME ──────────────────
#
#   Stated rather than buried, because this repo has rejected the pattern
#   before: M20 refused Open WebUI's default embedding model precisely because
#   it would have pulled an unpinned, un-hash-verified `all-MiniLM-L6-v2` off
#   HuggingFace at runtime, and containers/traefik.nix refuses Yaegi plugins
#   for the same reason.
#
#   Immich's ML worker does exactly that: on first use it downloads its CLIP
#   and face-recognition models from HuggingFace into /var/cache/immich.  It
#   is accepted here rather than dodged, and the difference from the two
#   rejected cases is the blast radius, not the mechanism:
#
#     - it is NOT in the start path.  A failed download degrades search and
#       face grouping; it does not stop the server, and nothing else in the
#       house is behind it.  The Traefik case was a network fetch in the start
#       path of the proxy every service sits behind.
#     - the cache is on zdata and persists, so it is a first-run event and not
#       a per-boot dependency.
#     - there is no way to avoid it short of packaging the model set, which is
#       an ONNX-repackaging job with no upstream Nix expression.
#
#   If it should ever be closed properly: pre-seed /srv/state/immich/ml-cache
#   from a hash-verified fetch and the runtime download never fires.  Recorded
#   as the escape route, not done here.
#
# ── THE KODI PATH: THROUGH TRAEFIK, WHICH IS WHY THE FIREWALL IS ONE LINE ───
#
#   M8 paid a round for the opposite choice.  Kodi runs on the ERNST HOST,
#   whose only address is on VLAN 50, so a direct hop to a VLAN-90 service is
#   ROUTED through the UDM-Pro and meets the `Internal -> Services: Block All`
#   zone default — which drops silently, with no RST.  Tvheadend's HTSP needed
#   a bespoke ZBF policy (ledger L12) AND a /32 in its container firewall, and
#   the first deploy failed with SYNs retransmitting into nothing.
#
#   The Immich add-on needs none of that, because it speaks ordinary HTTPS and
#   can therefore use `https://photos.goclan.org` like every other client.
#   Host -> 10.0.90.12:443 is M5's permanent `Allow Traefik` policy, which
#   already exists.  So:
#
#     * NO new UDM-Pro rule and NO new ledger row for the TV path.
#     * This container's firewall admits ONE address — Traefik — and nothing
#       else on VLAN 90 reaches port 2283 at all.
#     * The add-on gets TLS and the same rate limits as every other client,
#       rather than plaintext on a flat L2 hop.
#
#   Do not "simplify" this later by pointing the add-on at 10.0.90.25:2283 and
#   widening the rule.  That trade was already made once, in the other
#   direction, and it cost a ZBF policy that is broader than the thing it
#   permits.
{ config, lib, pkgs, ... }:
let
  # Allocated in machines/ernst/networking.nix.  nspawn passes uids through
  # unmapped, so 3036 inside this container IS 3036 on zdata.
  immichUid = 3036;
  immichGid = 3036;

  # PostgreSQL's id is not ours to choose: it is a well-known NixOS static id
  # (`ids.uids.postgres`), and it lands on zdata unmapped like every other
  # container uid here.  Pinned in the tmpfiles rule below so the bind mount is
  # pre-owned rather than chowned by a module at first start.
  postgresUid = 71;
  postgresGid = 71;

  # ── ADMIN SIGNUP: OFF ──────────────────────────────────────────────────────
  #
  # TRUE FOR EXACTLY ONE DEPLOY, EVER, and then back to false.  With no admin
  # account yet, Immich's /auth/admin-sign-up hands the server to whoever posts
  # to it first; this is the flag that closes that endpoint.  See "THE
  # FIRST-RUN WINDOW" in the file header for why this exists at all and for the
  # second, independent control (the public A record is created last).
  #
  # The procedure, in order, is in docs/roadmap.md M22's manual steps.  If you
  # are reading this because signup returns an error: that is this line doing
  # its job, and flipping it is a deploy, not a restart.
  adminSetupOpen = false;

  # The one VLAN-90 peer allowed to reach this service.  Every client —
  # phones, the TV, a browser, the import tool — arrives through it.
  traefikAddr = "10.0.90.12";

  # The monitoring container (M6), and the only thing permitted to read the
  # telemetry endpoint.  Separate from the line above because it is a different
  # port with a different justification, not because it is a different kind of
  # peer.
  monitoringAddr = "10.0.90.14";

  immichPort  = 2283;   # services.immich.port default; the app itself
  metricsPort = 8081;   # IMMICH_API_METRICS_PORT || 8081, read off the build

  photosRoot = "/srv/photos";
  stateRoot  = "/srv/state/immich";

  ##############################################################################
  # ── THE IMPORT, AND WHY ITS SOURCE LISTS ARE NIX AND NOT A GLOB ───────────
  #
  # /srv/unsorted is the retired Arch server (tomala-server001) as it was found:
  # one 26-directory tree accumulated over a decade, ~485 GB, holding
  # photographs, documents, ebooks, audiobooks and per-person folders all
  # interleaved.  machines/ernst/disko.nix names it "unsorted" deliberately,
  # because it is a holding area and not a final home.
  #
  # "Import the photos from the old server" is therefore a TRIAGE DECISION, not
  # a script.  Measured on ernst 2026-09-11:
  #
  #   /srv/unsorted/Bilder    67 GB   ~11.5k jpg + 3.4k dng, and also
  #                                   wallpapers, icons, avatars and ASCII art
  #   /srv/unsorted/Sarinah  101 GB   ~22k jpg + 3.5k png + 1.2k mp4, and also
  #                                   PDFs, spreadsheets, job applications and
  #                                   personal records
  #   /srv/unsorted/Lutz      61 GB   2.7k dng + 582 jpg, and a Biochemie
  #                                   coursework tree
  #
  # So the lists below name DIRECTORIES THAT WERE LOOKED AT, one per line, and
  # extending one is a pull request rather than an edit to a glob on a running
  # machine.  `photo-import survey` is what you run before adding a line.
  #
  # TWO INDEPENDENT FILTERS, because either alone would be trusted too much:
  # the source list decides which trees are visited, and `--include-extensions`
  # decides what may be uploaded out of them.  A directory listed by mistake
  # still cannot put a PDF in the photo library.
  #
  # THE LISTS ARE CONSERVATIVE ON PURPOSE.  Everything ambiguous is left OUT
  # and named below, because the cost of the two mistakes is not symmetric:
  # omitting a folder is noticed and fixed in a line, while importing someone's
  # private documents into a library that is reachable from the internet and
  # browsable on a television is not undone by deleting them afterwards.
  ##############################################################################

  importServer = "https://photos.goclan.org";

  # Accepted extensions.  RAW is `.dng` only — that is what this corpus
  # actually contains, and lgo's decision is that the EXISTING DNGs come along
  # (they are the only copy of those shots) while the ILCE's new ARWs do not:
  # that pipeline sends finished exports, and Immich is not a raw archive.
  # Adding `.arw` here would quietly reverse that.
  importExtensions = ".jpg,.jpeg,.png,.heic,.heif,.dng,.tif,.tiff,.mp4,.mov,.m4v,.3gp,.avi,.mts";

  # Directory patterns immich-go refuses anywhere in the tree, case-insensitive.
  # These are the NON-PHOTOGRAPHS that live inside otherwise photographic
  # directories — Bilder is a picture folder that also became a scratch space
  # for desktop wallpaper and icon sets.
  #
  # The extension filter does not cover these: a wallpaper is a real .jpg.  It
  # is the CONTENT that does not belong in a family photo library, and only a
  # path rule can express that.
  importBan = ''
    wallpaper/
    icons/
    avatars/
    ascii/
    Gif/
    Gifs/
    Screenshot/
    Screenshots/
  '';

  # lgo's trees.  MEASURED on ernst 2026-09-11 with `photo-import survey`:
  #
  #   /srv/unsorted/Bilder          15,628 images   129 videos   100 other   67 GB
  #   /srv/unsorted/Lutz/Pictures    3,434 images     0 videos    58 other   25 GB
  #
  # `Bilder` whole, minus the banned subdirectories above — its year folders
  # (2006, 2016–2023, 201910_italia) plus Raw, WhatsApp, Gerichte and the loose
  # LRM_EXPORT_* files at its root are all photographs.  The ban list removes
  # 302 files / ~580 MB of wallpaper, icons, avatars, ASCII art, GIFs and
  # screenshots from that count.
  #
  # NOT `Lutz` whole: `Lutz/Biochemie` is coursework.
  #
  # ── /srv/unsorted/Lutz/Signal WAS IN THIS LIST AND THE SURVEY TOOK IT OUT ──
  #
  #   It looked like a photo folder — a per-year tree next to `Pictures`, 36 GB
  #   of it, in a directory called Signal where a phone's received images would
  #   plausibly live.  It is not.  `photo-import survey` reported ONE image and
  #   THREE other files in 36 GB, and the three are encrypted Signal
  #   application backups (`signal-2021-11-02-…backup`, 13 GB each).
  #
  #   Nothing would have been uploaded either way — the extension filter refuses
  #   `.backup`, which is the second filter doing exactly its job — but
  #   immich-go would have walked 36 GB of opaque blobs to find one PNG.  The
  #   reason to record it is narrower and more useful than "a directory was
  #   removed": IT IS THE CASE THAT MAKES `survey` WORTH HAVING.  A source list
  #   written from a directory LISTING looks right and is wrong; one written
  #   from a directory's CONTENTS is not.
  #
  # LEFT IN, and worth knowing about: `Bilder/Sarinah` and `Bilder/Lutz` are
  # nested per-person folders INSIDE the shared picture tree, so importing
  # `Bilder` pulls both into lgo's library.  That is accepted — they are family
  # photographs in a family picture folder — but it is the one place where the
  # lgo/sgo split is not clean, and it is stated rather than discovered later.
  importSourcesLgo = ''
    /srv/unsorted/Bilder
    /srv/unsorted/Lutz/Pictures
  '';

  # Sarinah's trees (sgo).
  #
  # DELIBERATELY THE UNAMBIGUOUS ONES ONLY.  Her folder is the largest in the
  # corpus and the most mixed: alongside the photographs it holds `Bewerbung`
  # (job applications), `Audio`, spreadsheets and personal health records.
  # None of that is in this list and none of it should be added to it.
  #
  # MEASURED on ernst 2026-09-11 with `photo-import survey`:
  #
  #   Sarinah/Bilder                    13,811 images  658 videos   20 other  80 GB
  #   Sarinah/WhatsApp                   6,381 images  261 videos    1 other 2.5 GB
  #   Sarinah/20200711_sg_motog5s_bak    3,146 images  183 videos    0 other  11 GB
  #   Sarinah/Videos                         0 images   52 videos    0 other 1.4 GB
  #
  # TWO ENTRIES WERE REMOVED BY THAT SURVEY, and both are worth recording:
  #
  #   Sarinah/Sarinah  DOES NOT EXIST.  It came from misreading `find -maxdepth
  #                    1 -type d`, which prints the START DIRECTORY as well as
  #                    its children — so the tree's own name appeared to be a
  #                    subdirectory of itself.  The tool reported MISSING and
  #                    `photo-import` refuses to run with a source that is not
  #                    there, which is why that check exists.
  #   Sarinah/Signal   0 images, 0 videos, 3.2 GB.  Encrypted Signal
  #                    application backups, the same as lgo's — see above.
  #
  # NOT LISTED, PENDING HER OWN DECISION rather than mine: `DIY`, `Haekeln`,
  # `Makrame`, `Stricken`, `Pflanzen`, `Shopping`, `Käthes Geb` and
  # `anderen schicken wa` (~2.9 GB between them).  These are almost certainly
  # craft and reference photographs and probably belong in the library — but
  # they are her files, and the right way to add them is to run
  # `photo-import survey` on each and then add a line here, not to have had
  # them swept in by an agent writing a source list from a directory listing.
  #
  # NEVER TO BE LISTED: `Bewerbung` (job applications), `Audio`, and the loose
  # spreadsheets and personal health records at the root of her tree.  The
  # extension filter already refuses all of it, but this library is reachable
  # from the internet and browsable on a television, so the source list is not
  # the place to rely on a second mechanism.
  importSourcesSgo = ''
    /srv/unsorted/Sarinah/Bilder
    /srv/unsorted/Sarinah/WhatsApp
    /srv/unsorted/Sarinah/20200711_sg_motog5s_bak
    /srv/unsorted/Sarinah/Videos
  '';
in
{
  ##############################################################################
  # Host side — the state tree, the media-location guard, and the veth.
  ##############################################################################

  # The database and the ML model cache.  NUMERIC ids on purpose: `immich` and
  # `postgres` are container users and the host has no matching passwd entries.
  # Same shape containers/traefik.nix uses for uid 3005.
  #
  # 0700 on both.  Nothing outside this container has any business in either,
  # and unlike /srv/media there is no shared `media` group here — Immich
  # hardlinks nothing, shares nothing, and is read by no other service.
  #
  # /srv/photos is DELIBERATELY ABSENT from this list.  It is created by the
  # unit below instead, and the distinction is the one containers/arr.nix
  # spells out for /srv/audiobooks: tmpfiles runs early and unconditionally, so
  # a rule here would cheerfully create the photo library ON zroot whenever
  # zdata/photos is not mounted.
  systemd.tmpfiles.rules = [
    "d ${stateRoot}            0700 ${toString immichUid}   ${toString immichGid}   -"
    "d ${stateRoot}/postgresql 0700 ${toString postgresUid} ${toString postgresGid} -"
    "d ${stateRoot}/ml-cache   0700 ${toString immichUid}   ${toString immichGid}   -"
  ];

  # ── Verify zdata/photos is mounted, then create the library root ──────────
  #
  # The audiobooks-tree pattern from containers/arr.nix, with ONE deliberate
  # difference: this unit BLOCKS ITS CONTAINER, and that one does not.
  #
  # containers/arr.nix uses `before` only, on the argument that Sonarr and
  # Radarr have nothing to do with audiobooks and must not go down because a
  # library dataset is missing — Audiobookshelf showing an empty library is a
  # visible, harmless failure.
  #
  # THAT ARGUMENT DOES NOT TRANSFER.  /srv/photos is not one library among
  # several inside a shared container; it is this container's ENTIRE reason to
  # exist and also its StateDirectory.  An Immich that starts without it is not
  # a degraded Immich — it is a NEW, EMPTY one on zroot, which will accept a
  # phone's whole camera roll, report success to the app, and lose the lot at
  # the next boot with the database pointing at files that no longer exist.
  # That is containers/storyteller.nix's case, not containers/arr.nix's, so it
  # gets storyteller's treatment: `requires` + `requiredBy`.
  #
  # It FAILS rather than repairing itself, for the reason arr.nix gives: a unit
  # that silently fixes storage layout hides the fact that the layout was wrong.
  systemd.services.photos-tree = {
    description = "Verify zdata/photos is mounted and create Immich's media location";
    wantedBy   = [ "multi-user.target" ];
    after      = [ "srv-photos.mount" ];
    requires   = [ "srv-photos.mount" ];
    before     = [ "container@immich.service" ];
    requiredBy = [ "container@immich.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.util-linux pkgs.coreutils ];
    script = ''
      set -eu

      # findmnt, not `mountpoint`: this has to check WHAT is mounted, not just
      # that something is.  /srv/photos carries `nofail` (machines/ernst/disko.nix),
      # so the mount unit can fail while /srv/photos still exists as an ordinary
      # directory on zroot — precisely the case a bare mountpoint test passes.
      src=$(findmnt --noheadings --output SOURCE --target ${photosRoot} || true)
      fstype=$(findmnt --noheadings --output FSTYPE --target ${photosRoot} || true)

      if [ "$src" != "zdata/photos" ] || [ "$fstype" != "zfs" ]; then
        echo "photos-tree: ${photosRoot} is NOT zdata/photos." >&2
        echo "  found: source='$src' fstype='$fstype'" >&2
        echo "" >&2
        echo "  Refusing to create it, because doing so would put the family's" >&2
        echo "  photo library on zroot, which rolls back on every boot — and" >&2
        echo "  Immich would report every upload as successful in the meantime." >&2
        echo "" >&2
        echo "  The dataset must exist AND carry mountpoint=legacy — a ZFS" >&2
        echo "  dataset without it cannot be mounted by mount(8) at all:" >&2
        echo "" >&2
        echo "    zfs create -o mountpoint=legacy -o recordsize=1M \\" >&2
        echo "      -o exec=off -o setuid=off -o devices=off -o atime=off \\" >&2
        echo "      -o com.sun:auto-snapshot=true zdata/photos" >&2
        echo "" >&2
        echo "  If it exists already:  zfs set mountpoint=legacy zdata/photos" >&2
        echo "  Then:                  systemctl start srv-photos.mount" >&2
        echo "  See docs/guides/ernst-zdata-datasets.md." >&2
        exit 1
      fi

      # 0700 immich:immich, matching what the module's own tmpfiles rule
      # asserts for mediaLocation.  No `media` group and no setgid: nothing
      # else on this machine reads these files, which is the whole difference
      # from the 2770 root:media trees under /srv/media.
      install -d -o ${toString immichUid} -g ${toString immichGid} -m 0700 ${photosRoot}
    '';
  };

  # Host side of the container's veth — a VLAN-90 port on br0.  Identical
  # rationale to vb-jellyfin / vb-arr / vb-tvheadend; see containers/traefik.nix
  # for the long form of KeepMaster-not-Bridge and why a bridge port carries no
  # address of its own.
  systemd.network.networks."60-vb-immich" = {
    matchConfig.Name = "vb-immich";
    networkConfig = {
      KeepMaster          = true;
      LinkLocalAddressing = "no";
      IPv6AcceptRA        = false;
    };
    bridgeVLANs = [ { VLAN = 90; PVID = 90; EgressUntagged = 90; } ];
    linkConfig.RequiredForOnline = "enslaved";
  };

  # Same VLAN race, same idempotent backstop, same "-" prefix as every other
  # nspawn container on br0: networkd applies [BridgeVLAN] only once it observes
  # the link's master, and nspawn sets that master out of band.  With
  # DefaultPVID = "none" on br0 a miss is fail-CLOSED.
  # `bridge vlan show dev vb-immich` is the check.
  systemd.services."container@immich".serviceConfig.ExecStartPost = [
    "-${pkgs.iproute2}/bin/bridge vlan add dev vb-immich vid 90 pvid untagged"
  ];

  ##############################################################################
  # `photo-import` — the one-way migration out of /srv/unsorted.
  #
  # ON THE HOST, NOT IN THE CONTAINER, and that is the whole reason this is
  # possible at all: immich-go speaks the HTTP API, so the tool needs to see
  # the source files and reach the server, and the host is the only namespace
  # where both are true.  /srv/unsorted is deliberately NOT bind-mounted into
  # the container — Immich has no business holding a handle to the rest of the
  # old server's data, and this design means it never does.
  #
  # It goes through `photos.goclan.org` like every other client rather than
  # straight to 10.0.90.25:2283, for the reason in "THE KODI PATH" above: the
  # host reaches Traefik under M5's existing policy and reaches nothing else on
  # VLAN 90.  So the import needs no new firewall rule either.
  #
  # A COPY, NOT A MOVE, and nothing here deletes anything.  Immich ingests by
  # copying into its own storage-template path under /srv/photos; the originals
  # stay in /srv/unsorted until a human removes them, which should not happen
  # until the library has been looked at and the snapshots have caught up.
  # `rom-import` makes the same choice for the same kind of reason.
  #
  # The body is machines/ernst/photo-import.sh; the constants below are what
  # stop it from drifting away from what was deployed.
  ##############################################################################
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "photo-import";

      runtimeInputs = with pkgs; [
        immich-go
        coreutils findutils
        curl           # `photo-import check`, and the error messages that
                       # distinguish "no route" from "bad key"
      ];

      text = ''
        SERVER=${importServer}
        EXTENSIONS=${importExtensions}
        LOGDIR=/var/log/photo-import

        BAN="${importBan}"
        SRC_LGO="${importSourcesLgo}"
        SRC_SGO="${importSourcesSgo}"

        ${builtins.readFile ../photo-import.sh}
      '';
    })
  ];

  ##############################################################################
  # The container.
  ##############################################################################
  containers.immich = {
    autoStart = true;
    ephemeral = false;

    # MAC from the allocation table in machines/ernst/networking.nix; the DHCP
    # reservation 10.0.90.25 on the UDM-Pro keys on it (manual step).  Sequence
    # 11, and the last octet is 8 + seq as everywhere else on this bridge.
    privateNetwork  = true;
    hostBridge      = "br0";
    localMacAddress = "02:00:00:90:00:11";

    bindMounts = {
      # The library, remapped to the module's own default so that
      # mediaLocation and StateDirectory agree with no override at all.
      "/var/lib/immich" = {
        hostPath   = photosRoot;
        isReadOnly = false;
      };

      # The database.  The PARENT is bound, not the version subdirectory, so a
      # future PostgreSQL major bump lands beside the old one on zdata instead
      # of on the container's rootfs.
      "/var/lib/postgresql" = {
        hostPath   = "${stateRoot}/postgresql";
        isReadOnly = false;
      };

      # The ML model cache (`CacheDirectory = "immich"` in the module).  On
      # zdata so the HuggingFace download is a first-run event rather than
      # something that repeats whenever this directory is lost.
      "/var/cache/immich" = {
        hostPath   = "${stateRoot}/ml-cache";
        isReadOnly = false;
      };
    };

    config = { config, pkgs, lib, ... }: {
      # Pins the PostgreSQL major version through
      # `services.postgresql.package`'s stateVersion-derived default, which is
      # the thing that must not move under a running database.  A bump is then
      # a deliberate edit plus a dump/restore, not a side effect of a channel.
      system.stateVersion = "26.05";

      ##########################################################################
      # Networking — one leg, the ordinary VLAN-90 shape.
      ##########################################################################
      networking.useHostResolvConf = false;
      networking.useNetworkd = true;
      services.resolved.enable = true;

      systemd.network.networks."10-eth0" = {
        matchConfig.Name = "eth0";
        networkConfig = {
          DHCP         = "ipv4";
          DNS          = "10.0.5.3";
          Domains      = "~. skynet.lan";
          IPv6AcceptRA = false;
          # SN2: v4 only.  M18 measured that IPv6AcceptRA alone blocks an RA
          # but NOT link-local assignment, and that a container with only the
          # former still carries an fe80:: address.  This is the line that
          # actually makes `ip -6 addr show dev eth0` empty.
          LinkLocalAddressing = "no";
        };
        dhcpV4Config = {
          UseDNS     = false;
          UseDomains = false;
        };
        linkConfig.RequiredForOnline = "routable";
      };

      # Same 20 s cap as every sibling: a DHCP failure must leave a RUNNING
      # container with one failed unit, not a host-side restart loop.
      systemd.network.wait-online.timeout = 20;

      # ── The container firewall — the only enforcement point for br0-local
      #    traffic, since those frames are one L2 hop and the UDM-Pro never
      #    sees them.
      #
      #   2283/tcp  ONLY from Traefik.  Every client of this service arrives
      #             through the proxy, including the TV — see "THE KODI PATH"
      #             in the file header for why that is a design decision and
      #             not an accident of convenience.  This is the backend-bypass
      #             hardening M5 calls mechanism (a).
      #   8081/tcp  ONLY from the monitoring container.  Immich's telemetry
      #             endpoint carries no authentication of its own.
      #
      # extraCommands, not extraInputRules: the latter is declared
      # unconditionally but consumed only under networking.nftables, so here it
      # would produce no rule and no warning.  containers/arr.nix carries the
      # long form of that warning.
      networking.firewall.allowedTCPPorts = [ ];
      networking.firewall.extraCommands = ''
        iptables -A nixos-fw -p tcp -s ${traefikAddr}/32    --dport ${toString immichPort}  -j nixos-fw-accept
        iptables -A nixos-fw -p tcp -s ${monitoringAddr}/32 --dport ${toString metricsPort} -j nixos-fw-accept
      '';

      ##########################################################################
      # The service.
      ##########################################################################
      services.immich = {
        enable = true;

        # 0.0.0.0, with the firewall above as the actual boundary — the
        # questarr/bindery shape.  The module's default is `localhost`, which
        # would make the service unreachable from Traefik entirely; binding the
        # DHCP-assigned address instead is not expressible here, because the
        # address is the UDM-Pro's to hand out and this container deliberately
        # does not declare it (see the MAC table in networking.nix for why that
        # rule points this way).
        host = "0.0.0.0";
        port = immichPort;

        # The module's default, restated because the bind mount above has to
        # agree with it and one binding is cheaper to keep in step than two
        # string literals.
        mediaLocation = "/var/lib/immich";

        # Local PostgreSQL with pgvector + VectorChord, over the unix socket at
        # /run/postgresql.  `database.host` is left at that default, which is
        # what makes `secretsFile` unnecessary — see the file header.
        database.enable = true;

        # Local Redis, also over its unix socket.
        redis.enable = true;

        machine-learning.enable = true;

        # Invariant #5.  `[ ]` is not "unset" — the module turns it into
        # PrivateDevices = true, so the container cannot reach a render node at
        # all.  `null` would have given it every device on the machine,
        # including the card driving the television.
        accelerationDevices = [ ];

        environment = {
          # Immich sits behind Traefik, so without this every request appears
          # to come from 10.0.90.12 and its own logs — the ones CrowdSec reads
          # through Traefik's access log, and the ones an operator reads when
          # an account is being brute-forced — name the proxy instead of the
          # client.
          IMMICH_TRUSTED_PROXIES = traefikAddr;

          # See `adminSetupOpen` in the let block.  Boolean-typed upstream
          # (`IMMICH_ALLOW_SETUP ?? true`), so the string must be exactly
          # "true"/"false".
          IMMICH_ALLOW_SETUP = lib.boolToString adminSetupOpen;

          # Prometheus telemetry on ${toString metricsPort}.  UNVERIFIED AT
          # WRITE TIME and it must not be reported as working until it has been
          # looked at: this was read off the built server's env-var table
          # (`IMMICH_API_METRICS_PORT || 8081`) rather than measured against a
          # running instance.  M13 dropped Ollama's scrape target for exactly
          # this reason — it was assumed to serve /metrics and answered 404.
          # The M22 test plan checks for `immich_*` series in Prometheus and
          # says so either way.
          IMMICH_TELEMETRY_INCLUDE = "all";
        };
      };

      # Pin the ids.  The module creates `immich` with no uid, which would make
      # it whatever the container's useradd picks — and nspawn passes ids
      # through unmapped, so that number is what ends up on every file in
      # /srv/photos.  An unpinned id here is a library that changes owner when
      # an unrelated user is added to this container.
      users.users.immich.uid  = immichUid;
      users.groups.immich.gid = immichGid;

      # `curl` is the test plan's instrument for proving this backend is
      # reachable from Traefik and from nowhere else.
      environment.systemPackages = with pkgs; [ curl ];
      documentation.enable       = false;
      documentation.nixos.enable = false;
    };
  };
}
