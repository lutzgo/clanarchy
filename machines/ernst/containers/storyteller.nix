# machines/ernst/containers/storyteller.nix
#
# Storyteller — M14.  It takes a DRM-free ebook and the matching audiobook and
# emits a single EPUB3 with the audio embedded and sentence-level synchronised
# playback ("guided narration" / EPUB media overlays), produced by forced
# alignment.
#
# ── WHY IT IS IN SCOPE AT ALL ───────────────────────────────────────────────
#
#   lgo has matched ebook + audiobook pairs.  That is the PRECONDITION, and it
#   is what moves this from "interesting" to "in scope": without both halves
#   DRM-free for the same title Storyteller does nothing whatsoever.  Stated
#   first so nobody adds it speculatively elsewhere.
#
#   THE SLOT IS JUSTIFIED ON LANGUAGE LEARNING AND ACCESSIBILITY, not on
#   convenience, and docs/history.md is explicit that a convenience argument
#   would not survive the CPU cost.  Reading while listening, with the text
#   tracking the narration, is the whole point.
#
# ── COMPLEMENTARY TO AUDIOBOOKSHELF, NOT OVERLAPPING ────────────────────────
#
#   Audiobookshelf SERVES a library.  Storyteller PRODUCES synced artifacts
#   from pairs.  Both are true at once, which is why they share one dataset
#   (zdata/audiobooks) and why neither is a reason to drop the other.
#
#   What is NOT claimed: there is no automatic hand-off between them.
#   Storyteller writes its output inside its /data volume, and pointing
#   Audiobookshelf at the result is a UI step in the PR body, not something
#   this file implements.
#
#   CORRECTED 2026-09-27: this paragraph used to add "Storyteller takes its
#   input through its own web UI", and that was not the design decision it
#   sounded like.  The container mounted /data and nothing else, so uploading
#   through the browser was the only thing it COULD do — the sentence
#   described a limitation of this file and attributed it to upstream.  Both
#   source libraries are now mounted READ-ONLY (see `volumes`), so a pair can
#   be aligned from the trees the household already has.  The upload path
#   still works and is still the only way to align something that is in
#   neither library.
#
# ── TIER: PODMAN, AND THE ROADMAP'S OWN ESCAPE HATCH IS WHAT PUTS IT HERE ──
#
#   docs/history.md instructs: "VERIFY the deploy story against the upstream
#   GitLab repo, not blog posts.  If no sane non-Docker path exists, that
#   argues for the PODMAN TIER M9 is opening, NOT for oci-containers inside
#   nspawn."  Verified on 2026-08-28, and there is no sane non-Docker path.
#
#   FIRST, THE ROADMAP POINTS AT THE WRONG REPOSITORY.  It names
#   gitlab.com/smoores/storyteller.  That namespace is ARCHIVED and read-only,
#   last activity 2025-07-06.  The live project moved to
#   gitlab.com/storyteller-platform/storyteller (active the day this was
#   written), mirrored to github.com/smoores-dev/storyteller.  Anyone
#   "verifying against upstream" via the roadmap's link would be reading a
#   tree a year stale.
#
#   SECOND, THE BUILD.  Reading the live Dockerfile:
#
#     - a Next.js STANDALONE build over YARN BERRY WORKSPACES, spanning
#       several internal libraries;
#     - NATIVE PREBUILDS for the alignment library, shipped per-architecture;
#     - WHISPER.CPP BINARIES, vendored per-variant, plus a bundled tiny.en
#       model;
#
#       THIS IS CORRECT — and a correction added here on 2026-09-27 claiming
#       otherwise was WRONG and is retracted.  The image really does carry
#       /home/storyteller/.local/share/ghost-story/whisper-cpp/1.8.3/
#       {linux-x64-cpu,linux-x64-cpu-legacy}/bin/whisper-cli, a bundled
#       ggml-tiny.en.bin, and a config.json naming
#       "installedVariant": "linux-x64-cpu-legacy".
#
#       What misled the first diagnosis was the app's own log line, "No
#       variant configured or installed. Falling back to platform detection."
#       That is true from the process's point of view and false about the
#       image: the binaries are present and UNREACHABLE.  See the
#       /home/storyteller volume in `volumes` below for why, and note the
#       general shape — an application reporting a thing is "not installed"
#       is reporting what it can SEE, which under a forced --user is not the
#       same as what is there.
#     - a READIUM BINARY lifted out of a DIFFERENT container image
#       (ghcr.io/readium/readium);
#     - and a SQLite UUID extension compiled in-line with gcc.
#
#   Packaging that in Nix is not "a derivation": it is a yarn-berry offline
#   cache, a whisper.cpp build, an out-of-band binary extraction and a Next.js
#   standalone install, for one service.  Compare questarr.nix next door —
#   plain npm, a committed lockfile and one native module — which is exactly
#   where the line falls.
#
#   So this takes the podman tier, and it is that tier's SECOND occupant after
#   M9's TubeSync.  `virtualisation.oci-containers` INSIDE AN NSPAWN CONTAINER
#   IS REJECTED, as every milestone adding a service is required to restate:
#   the entire value of containers/arr.nix is that upstream units, upstream
#   hardening and `systemd-analyze` scores are legible, and an opaque image
#   inside it is opaque to all three.  The escape hatch is this tier, not that
#   hybrid.
#
#   THE COST, accepted explicitly and identically to M9's: an opaque image, a
#   package tree we do not build, and a `systemd-analyze security` score for
#   `podman-storyteller.service` that measures podman rather than the
#   application.
#
# ── THE IMAGE IS PINNED BY DIGEST, AND `latest` IS A TRAP HERE ─────────────
#
#   Measured 2026-08-28 with skopeo:
#
#     web-v2.9.3   sha256:9f7fac6b…   created 2026-03-15   ← newest STABLE
#     latest       sha256:f063fcd8…   created 2026-08-18   ← a 3.0.0 BETA
#
#   Upstream's own compose file uses `:latest`, and on this registry `latest`
#   currently resolves to a `web-v3.0.0-beta.N` build.  Following the compose
#   file would have put a beta of a major version into a household service.
#   That is the general argument for digest-pinning made concrete.
#
#   TO BUMP: pick the new tag, then
#     skopeo inspect --format '{{.Digest}}' \
#       docker://registry.gitlab.com/storyteller-platform/storyteller:<tag>
#   and update BOTH lines below.  Never point this at a tag.
#
#   THE PLAIN TAG IS THE CPU BUILD, AND THAT IS DELIBERATE.  Upstream also
#   publishes -blas, -cuda-*, -sycl, -vulkan and -rocm variants of every tag.
#
#     -rocm REJECTED.  ernst's RX 7900 XTX is Ollama's ROCm card and drives the
#       TV (architecture invariant #5).  M11 measured a fully-resident Ollama at
#       64k context leaving roughly 2 GB of VRAM — so a second ROCm claimant
#       would contend for the scarcest resource on the box, to accelerate a
#       batch job nobody is waiting on, and would degrade the one workload whose
#       slowdown is most visible (an interactive coding session).
#     -blas NOT TAKEN YET, and it is the first thing to try if alignment turns
#       out too slow.  It is a CPU build with an accelerated BLAS, so it raises
#       no GPU question at all.  Left off the first deploy because "it is
#       probably faster" is not a measurement, and this deploy has no baseline
#       to compare against yet.
#
# ── THE CPU LIMITS ARE NOT OPTIONAL ────────────────────────────────────────
#
#   Forced alignment is CPU-heavy.  Sixteen Zen 5 cores make that a non-issue
#   in absolute terms and NOT in relative ones: this box also runs a Jellyfin
#   transcode, an HTPC session on the TV, and — new since M11 — an interactive
#   Ollama session.  That third claimant did not exist when this was first
#   sketched and it is the one whose degradation is most visible, because "the
#   coding agent got slower for no apparent reason" is not something anyone
#   diagnoses quickly.
#
#   So the unit is nice'd and CPUWeight-limited.  See the unit below.
#
# ── ALIGNMENT QUALITY: BIND ONE PAIR AND CHECK IT BY HAND ─────────────────
#
#   Claimed accuracy is 90–95% on clean sources, and it degrades on long
#   musical intros and messy EPUB formatting.  docs/history.md requires ONE
#   known-good pair to be bound and its sync checked by hand BEFORE any batch,
#   and that is in the PR test plan rather than here because nothing in Nix can
#   enforce it.
{ config, pkgs, lib, ... }:

let
  # uid 3022, reserved for this service in machines/ernst/allocations.nix.
  #
  # LITERAL ON zdata, because this container is ROOTFUL AND UNMAPPED — the same
  # decision containers/tubesync.nix records at length.  Rootless podman always
  # remaps uids through a subuid range, so a number chosen inside the container
  # would NOT be that number on the pool, and the shared `media` group would
  # stop meaning anything across the boundary.
  storytellerUid = 3022;
  mediaGid       = 3000;

  # ── L2 / L3 ───────────────────────────────────────────────────────────────
  #
  # Next free sequence in machines/ernst/allocations.nix:
  # 08 and 09 are RESERVED (M15 tdarr, M16 jellyseerr), 0a went to M8's
  # tvheadend and 0b to M9's tubesync.  So 0c, and the last octet follows that
  # table's 8 + <seq> convention: 10.0.90.20.
  netns    = "storyteller";
  vethHost = "vb-storyteller";

  # `st0`, NOT `eth0` — AND THIS IS NOT COSMETIC.
  #
  # ── THE COLLISION, MEASURED ON ernst 2026-08-28 ─────────────────────────
  #
  # containers/tubesync.nix names its namespace interface `eth0`.  Copying
  # that here produced a Storyteller namespace with NO IPv4 ADDRESS AT ALL,
  # and a dhcp unit that reported success:
  #
  #   storyteller-dhcp.service: Deactivated successfully.
  #   dhcpcd[21555]: sending commands to dhcpcd process
  #
  # That second line is the whole story.  dhcpcd keys its pidfile and control
  # socket on the INTERFACE NAME, not on the network namespace:
  #
  #   /run/dhcpcd/eth0-4.pid
  #   /run/dhcpcd/eth0-4.sock
  #
  # These units differ only in their NETWORK namespace — `NetworkNamespacePath=`
  # changes nothing about the mount namespace — so both see the same /run.
  # TubeSync's dhcpcd starts first and creates `eth0-4.sock`; Storyteller's
  # then finds it, concludes that dhcpcd is already managing "eth0", hands its
  # arguments to that instance as a CLIENT, and exits 0.  The lease it asks
  # for is applied in TubeSync's namespace, where it is a no-op.
  #
  # It fails silently in the worst way: the unit succeeds, the container
  # starts, the veth is up with the right MAC and the right VLAN — and the
  # service is simply unreachable, which presents as a 502 from Traefik.
  # `Restart = on-failure` cannot help, because nothing failed.
  #
  # ── THE RULE FOR THE NEXT ONE ──────────────────────────────────────────
  #
  # EVERY podman-tier namespace must use a UNIQUE interface name.  M9's file
  # anticipated that its choices should be re-examined "before the SECOND
  # podman service, not after"; this is the item that re-examination would
  # have caught.  A third service must not be called `eth0` or `st0` either.
  #
  # Nothing else depends on the name: podman joins the namespace rather than
  # building it, the DHCP reservation keys on the MAC, and the namespace
  # firewall below matches on `lo` and addresses, never on this interface.
  vethNs   = "st0";
  mac      = "02:00:00:90:00:0c";
  vlanId   = 90;

  # Upstream's own port, from its compose file.  Not configurable in the image
  # without more effort than it is worth.
  webPort = 8001;

  # Traefik's veth address — the ONLY source permitted to reach the web UI.
  # Same one-hop-on-br0 caveat as every sibling: these frames never reach the
  # UDM-Pro, so the netns firewall below is the only enforcement point.  The
  # adjacency that makes it matter is real — 10.0.90.11 is the qBittorrent and
  # slskd microvm, one layer-2 hop away.
  traefikAddr = "10.0.90.12";

  # /data, and it is on zdata/audiobooks rather than under /srv/state.
  #
  # Upstream ships exactly ONE volume and everything lives in it: the database,
  # the originals it has been given, and the synced EPUB3s it produces.  That
  # last part is why this is not state — the outputs are library content, and
  # putting them on the same dataset as Audiobookshelf's library is what lets
  # ABS be pointed at them without a copy.  See the tmpfiles block in
  # containers/arr.nix, which owns that tree.
  dataDir    = "/srv/audiobooks/storyteller";
  secretsDir = "/run/storyteller-secrets";

  # ── THE AUTO-IMPORT STAGING DIRECTORY ──────────────────────────────────────
  #
  # Storyteller has exactly TWO ways in, and neither is "read the library":
  # chunked upload through the browser (POST /api/v2/books/upload) and an
  # auto-import watcher on a directory.  There is no import-from-server-path
  # flow — checked against the deployed 2.9.3 build's route table, which has
  # books/upload, books/merge and books/[bookId]/process and nothing else.
  #
  # That makes upload useless here for the case that matters.  The first pair
  # anyone actually wants to align is Consider Phlebas: a 562 KB EPUB and
  # 2.2 GB of FLAC that are ALREADY ON THIS HOST.  Uploading them means
  # pulling 2.2 GB down to a laptop and pushing it back through Traefik to
  # reach a path two directories away.  So the watcher is the mechanism, and
  # it needs somewhere to watch.
  #
  # WHY A NEW DIRECTORY RATHER THAN POINTING THE WATCHER AT THE LIBRARIES:
  #
  #   /library/audiobooks is 116 GB.  Pointing auto-import there would sweep
  #   the entire household audiobook collection into Storyteller and start
  #   whisper transcription across all of it — the single most CPU-expensive
  #   thing this box can do, against a Jellyfin transcode, the HTPC session
  #   and an interactive Ollama session.  The header's "bind ONE pair and
  #   check it by hand" rule exists precisely to stop that, and a watcher on
  #   the whole library is that rule inverted.
  #
  #   /library/ebooks is only 14 MB and would be harmless, but ebooks alone
  #   produce half-books waiting for an audio half, which is not a pair.
  #
  #   Both are also mounted READ-ONLY and must stay that way (see `volumes`).
  #
  # WHY IT LIVES ON zdata/audiobooks, AND THIS IS THE WHOLE POINT:
  #
  #   Same dataset as /srv/audiobooks/library and as dataDir.  So staging an
  #   audiobook is `ln` — a HARDLINK, instant, zero bytes copied, however many
  #   gigabytes the book is.  Put this on zdata/media, or anywhere else, and
  #   every pair costs a full copy of the audio twice over.  The ebook half
  #   does cost a real copy because it comes from zdata/media, and at
  #   kilobytes that is not worth solving.
  importDir  = "/srv/audiobooks/storyteller-import";

  # $HOME for the container, and the ONLY path in this file that is not on
  # zdata/audiobooks.  It has to be on zdata/state because that is the one
  # dataset here with `exec=on` — whisper.cpp is a downloaded binary and the
  # media datasets refuse to execute.  See the /home/storyteller volume.
  homeDir    = "/srv/state/storyteller/home";

  # See the header.  web-v2.9.3, the newest STABLE tag — NOT `latest`, which is
  # currently a 3.0.0 beta.
  imageTag    = "web-v2.9.3";
  imageDigest = "sha256:9f7fac6ba3217e131cf3eaefe0b5107b8b6c431ace91e73c06cb530cd43ff4b8";

  # `storyteller-stage` — bound here rather than inline in systemPackages so
  # the weekly pair watcher below can invoke THE SAME derivation. Two copies
  # of the script would be two matchers, and a watcher announcing pairs the
  # staging tool would then reject is precisely the drift the header forbids.
  storytellerStage = pkgs.writeShellApplication {
    name = "storyteller-stage";

    runtimeInputs = with pkgs; [
      coreutils findutils gnused gnugrep sqlite
    ];

    text = ''
      IMPORT=${importDir}
      EBOOKS=/srv/media/library/books
      AUDIO=/srv/audiobooks/library
      INGEST=/srv/media/ingest/cwa
      UID_=${toString storytellerUid}
      GID_=${toString mediaGid}
      # Storyteller's own database, read-only, for `new`'s already-imported
      # check.  Lives on zdata with the rest of its state (see the header).
      DB=${dataDir}/storyteller.db

      ${builtins.readFile ../storyteller-stage.sh}
    '';
  };
in
{
  ##############################################################################
  # Podman is already enabled by containers/tubesync.nix (M9), which is the
  # tier's first occupant.  It is NOT re-enabled here.
  #
  # Stated rather than silently omitted, because the obvious move when adding
  # the second podman service is to copy the whole block — and two plain
  # `virtualisation.podman.enable = true` definitions are fine, while two
  # differing `dockerCompat` or `dockerSocket` definitions are a merge conflict
  # that only appears when someone changes one of them.  One owner, one place.
  ##############################################################################

  ##############################################################################

  ##############################################################################
  # Secrets.
  ##############################################################################

  # STORYTELLER_SECRET_KEY — GENERATED, not prompted.
  #
  # Same call as M9's Django key and for the same reason: nobody types this,
  # nothing outside the repo needs to know it, and a prompt would only invite a
  # weak value.  Upstream's install instruction is literally
  # `openssl rand -base64 32`, which is what this does.
  #
  # It signs sessions.  Losing it logs everyone out; leaking it is worse.
  clan.core.vars.generators.storyteller-secret = {
    files."secret-key".secret = true;
    runtimeInputs = [ pkgs.coreutils pkgs.openssl ];
    script = ''
      openssl rand -base64 32 | tr -d '\n' > "$out/secret-key"
    '';
  };

  # Stage it where the container unit can read it.
  #
  # THE IMAGE WANTS A FILE, NOT A VARIABLE — `STORYTELLER_SECRET_KEY_FILE`,
  # which upstream's compose satisfies with a docker secret.  That is better
  # than an environment variable (it stays out of /proc/<pid>/environ) and it
  # means this stages a file and mounts it, rather than writing an env file.
  #
  # A directory WE own, rather than a bind of /run/secrets — which is a symlink
  # to a per-generation directory REPLACED on every deploy, so a mount
  # established at container start would keep exposing a deleted generation.
  # M5, M9 and M13 all record this.
  #
  # requiredBy, NOT wantedBy: unlike M9's Jellyfin key, this one is not
  # optional.  Storyteller will not start without a secret key at all, so a
  # container that starts anyway would just be a restart loop in a different
  # unit's journal.
  systemd.services.storyteller-secrets = {
    description = "Stage Storyteller's secret key for the container";
    requiredBy = [ "podman-storyteller.service" ];
    before     = [ "podman-storyteller.service" ];
    after      = [ "local-fs.target" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root ${secretsDir}
      # 0440 root:<media>, and readable by the container's uid through its
      # group.  The container runs as ${toString storytellerUid} and reads this
      # itself — unlike an EnvironmentFile, which PID 1 would read before
      # dropping privileges — so it cannot be 0400 root:root.
      ${pkgs.coreutils}/bin/install -m 0440 -o root -g ${toString mediaGid} \
        ${config.clan.core.vars.generators.storyteller-secret.files."secret-key".path} \
        ${secretsDir}/secret-key
    '';
  };

  ##############################################################################
  # The container.
  ##############################################################################

  ##############################################################################
  # The container.
  ##############################################################################
  #
  # Declared through modules/containers/podman-netns.nix, which generates the
  # netns unit, the DHCP client, the host-side networkd file, the dirs unit,
  # the oci-containers entry and the ordering between them.
  #
  # `storyteller-secrets` STAYS HAND-WRITTEN: it installs a whole file at 0440
  # root:media for a container that reads it as a FILE
  # (`STORYTELLER_SECRET_KEY_FILE`), not as an env var — so the module's
  # `secrets` option, which composes `KEY=value` lines, is the wrong shape.
  clanarchy.podmanContainers.storyteller = {
    enable = true;
    mac    = "02:00:00:90:00:0c";
    interface = "st0";

    # Rootful and unmapped: these ids land on zdata, where a rootless subuid
    # remap would write files the rest of the host cannot name.
    uidgid = "${toString storytellerUid}:${toString mediaGid}";

    # THREE DATASETS, AND EACH GUARD NAMES ITS MOUNT POINT — not the
    # subdirectory under it, because the dirs unit derives a mount unit from
    # this path. /srv/state is the host default and is already guarded.
    extraGuardedMounts = [
      { path = "/srv/audiobooks"; source = "zdata/audiobooks"; fstype = "zfs"; }
      { path = "/srv/media";      source = "zdata/media";      fstype = "zfs"; }
    ];

    stateDirs = [
      { path = dataDir;   owner = storytellerUid; group = mediaGid; mode = "0750"; }
      # 2770 so a human can drop an epub+audiobook pair in for staging.
      { path = importDir; owner = storytellerUid; group = mediaGid; mode = "2770"; }
      { path = homeDir;   owner = storytellerUid; group = mediaGid; mode = "0750"; }
    ];

    allowFrom = [
      { peer = traefikAddr; port = webPort; }
    ];

    images.storyteller = {
      image = "registry.gitlab.com/storyteller-platform/storyteller@${imageDigest}";
      environment = {
        TZ = "Europe/Berlin";
        STORYTELLER_SECRET_KEY_FILE = "/run/secrets/secret-key";
      };
      volumes = [
        "${dataDir}:/data"
        "${secretsDir}/secret-key:/run/secrets/secret-key:ro"
        # The two source libraries, READ-ONLY: this service reads what the
        # *arr stack and Bindery produce and writes only into its own tree.
        "/srv/media/library/books:/library/ebooks:ro"
        "/srv/audiobooks/library:/library/audiobooks:ro"
        "${importDir}:/import"
        "${homeDir}:/home/storyteller"
      ];
      ports = [ ];
    };
  };

  # The audiobooks tree is built by its own unit in containers/arr.nix, and
  # the generated dirs unit knows only about MOUNTS — so the dependency on
  # that unit is merged on here rather than forked into a second dirs unit.
  systemd.services.storyteller-dirs = {
    after    = [ "audiobooks-tree.service" ];
    requires = [ "audiobooks-tree.service" ];
  };

  ##############################################################################
  # `storyteller-stage` — putting a pair where the watcher will find it.
  #
  # Here rather than in the guide for the reason rom-import.sh gives: the
  # constants (uid 3022, the media gid, importDir, both library roots) are
  # DEFINED in this file, and a copy of them in a document goes stale silently.
  # The tool is generated from the same `let` bindings the container is, so it
  # cannot disagree with the deployment.
  #
  # WHY A TOOL AND NOT `cp`.  Four things have to be right, and three of them
  # have already cost time in this milestone:
  #
  #   1. BOTH HALVES IN ONE SUBDIRECTORY.  That is what makes Storyteller pair
  #      them into a single item instead of two unmatched halves needing a
  #      manual merge afterwards.
  #   2. HARDLINK THE AUDIO.  The staging directory is on zdata/audiobooks
  #      precisely so this is free; a naive `cp` of a 4.4 GB audiobook works
  #      and quietly costs 4.4 GB every time.  The tool checks `stat -c %d`
  #      and links when it can, copies when it cannot.
  #   3. OWNERSHIP.  A fresh directory is root:root; the setgid bit fixes the
  #      GROUP of new files and never the owner, so the container (uid 3022)
  #      would see files it cannot read.
  #   4. EPUB ONLY.  Storyteller cannot take azw3 or mobi.  `storyteller-stage`
  #      refuses them with the conversion route rather than staging something
  #      that will fail an hour into transcription.
  #
  # `storyteller-stage pairs` answers the question that actually gates this
  # workflow — which titles exist in BOTH libraries — and it compares TITLES,
  # not author directories, because Audiobookshelf files Banks under
  # "Iain M. Banks" and Bindery under "Iain Banks". An author-level join misses
  # real pairs; that trap cost a wrong answer during M17's follow-up.
  ##############################################################################
  environment.systemPackages = [ storytellerStage ];

  ############################################################################
  # The weekly pair watcher.
  #
  # IT NOTIFIES; IT DOES NOT STAGE.  That is the whole design, and it came out
  # of measuring the libraries rather than from caution: 26 EPUBs and 31
  # audiobooks yield exactly ONE pairable title (Consider Phlebas, 2026-09-28).
  # The two shelves barely overlap — the ebooks are Banks/Le Guin/Wilde, the
  # audiobooks are Vinge/Weir/Tchaikovsky plus a large German shelf — so an
  # auto-stager would wake up, find nothing, and go back to sleep for weeks.
  # The scarce thing is a matching second half, not the two minutes it takes
  # to run `storyteller-stage`.
  #
  # AND ALIGNMENT COSTS HOURS OF CPU PER BOOK.  A stager that found four pairs
  # at once would commit the machine to most of a day of whisper without
  # anyone deciding to.  Notifying puts that decision back in front of a
  # human, which is where it belongs while this is a handful of titles a year.
  #
  # ONE MORE REASON, AND IT IS NOW THE LOAD-BEARING ONE: AUTO-IMPORT DOES NOT
  # START PROCESSING.  An earlier revision of this comment said auto-import had
  # "never been observed working"; that was written before the leg had been
  # exercised and is RETRACTED — Consider Phlebas was imported by the watcher
  # on 2026-09-27 18:07 and aligned on 2026-09-28.  What the watcher does,
  # read out of the deployed 2.9.3 bundle's scanner, is create the book row,
  # pull metadata and cover art out of the EPUB, and log `Scanning complete`.
  # It enqueues NO work.  Transcode/transcribe/align begins only when a human
  # presses CREATE READALOUD on the book's page in the web UI — the route
  # behind it is `POST /api/v2/books/<id>/process`, but nothing on screen says
  # "process".
  #
  # And the scanner DUPLICATES: every change fires two concurrent scans, each
  # holding a book list snapshotted at its own start, so three pairs staged in
  # one sitting became six books on 2026-10-05.  Another reason an auto-stager
  # would be a liability rather than a convenience.  See the guide.
  #
  # So an auto-stager would not spend a single CPU-second anyway — it would
  # only fill the library with unprocessed rows, while still committing the
  # staging decision nobody made.  Announcing the pair puts the one decision
  # that matters in front of the person who then has to press the button.
  ############################################################################
  systemd.services.storyteller-pair-watch = lib.mkIf config.clanarchy.zfs.ntfy.enable {
    description = "Announce Storyteller-pairable titles not yet imported";
    # Reuses the ZFS alerting topic on purpose — see the splitScript option in
    # modules/observability/zfs-ntfy.nix, which exists precisely so that every
    # publisher in this fleet normalises the var identically and lands on ONE
    # topic. A second topic here would be a second thing to reserve, mute and
    # rotate.
    serviceConfig = {
      Type = "oneshot";
      # Read-only work: a library scan and a read-only sqlite open.
      ProtectSystem = "strict";
      ReadOnlyPaths = [ "/srv/media/library/books" "/srv/audiobooks" ];
      PrivateTmp    = true;
    };
    path = [ pkgs.curl pkgs.coreutils ];
    script = ''
      set -eu

      # The SAME derivation that is on the operator's PATH — not a second copy
      # of the script. `new` announcing pairs that `storyteller-stage` would
      # then refuse to stage is exactly the drift this file's header forbids.
      new=$(${lib.getExe storytellerStage} new) || true

      # Empty stdout is the "no news" signal. Exit before touching the network
      # so a quiet week costs nothing and pages nobody.
      [ -n "$new" ] || exit 0

      count=$(printf '%s\n' "$new" | wc -l)
      body=$(printf '%s\n' "$new" | cut -f1 | sed 's/^/• /')

      if ! SPLIT=$(${config.clanarchy.zfs.ntfy.splitScript} \
            ${config.clan.core.vars.generators.zfs-ntfy.files."url".path}); then
        echo "storyteller-pair-watch: cannot read a topic out of the zfs-ntfy var" >&2
        exit 1
      fi
      NTFY_URL="''${SPLIT%% *}/''${SPLIT##* }"

      post() {
        curl -sSf --max-time 10 "$@" \
          -H "Title: $count new Storyteller pair(s)" \
          -H "Tags: books" \
          -d "$body

Stage with: storyteller-stage <slug> <ebook> <audiobook-dir>
List them:  storyteller-stage new
Then press Create readaloud in the web UI — the watcher imports but
never aligns. Stage one at a time (the scanner duplicates), and verify
the ebook path first (the matcher over-matches)." \
          "$NTFY_URL" >/dev/null
      }

      ${lib.optionalString config.clanarchy.zfs.ntfy.auth.enable ''
      # Same argv-avoiding form as the zedlet: the token goes file → pipe →
      # curl via `-K -`, never an argument, never an env var. ernst carries an
      # unprivileged couch account that can read /proc.
      TOKEN_FILE='${config.clan.core.vars.generators.zfs-ntfy-token.files."token".path}'
      if [ -r "$TOKEN_FILE" ]; then
        {
          printf 'header = "Authorization: Bearer '
          tr -d '[:space:]' < "$TOKEN_FILE"
          printf '"\n'
        } | post -K -
        exit 0
      fi
      echo "storyteller-pair-watch: auth enabled but $TOKEN_FILE is unreadable" >&2
      exit 1
      ''}

      post
    '';
  };

  systemd.timers.storyteller-pair-watch = lib.mkIf config.clanarchy.zfs.ntfy.enable {
    description = "Weekly check for Storyteller-pairable titles";
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnCalendar   = "Mon 09:00";
      Persistent   = true;   # a week the machine was down still gets its check
      RandomizedDelaySec = "30m";
    };
  };

  # ── SCHEDULING PRIORITY, MERGED ONTO THE GENERATED UNIT ─────────────────────
  #
  # Ordering comes from the module. These two numbers do not: they are a
  # judgement about THIS workload, and this one is niced harder than cwa's or
  # romm's because forced alignment is pure batch — nobody is ever waiting on
  # it — whereas a library scan sometimes has a human behind it.
  #
  # Forced alignment pins a core for hours per book, competing with a Jellyfin
  # transcode, the HTPC session on the TV, and an interactive Ollama session —
  # the last being the claimant whose degradation is hardest to attribute.
  #
  # TWO MECHANISMS, because neither is sufficient alone:
  #
  #   Nice = 15        lowers scheduling priority against everything on the
  #                    box, including processes outside this cgroup.
  #   CPUWeight = 20   biases the cgroup's share when there IS contention
  #                    (default 100). Under no contention it still gets the
  #                    whole machine, which is the point.
  #
  # NOT CPUQuota: a hard cap would make alignment slower even on an idle box,
  # trading away the only thing this workload has going for it.
  systemd.services.podman-storyteller.serviceConfig = {
    Nice      = 15;
    CPUWeight = 20;
  };
}
