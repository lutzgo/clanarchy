# machines/ernst/containers/arr.nix
#
# Prowlarr + Sonarr + Radarr + Bazarr + UmlautAdaptarr + Cleanuparr +
# MediathekArr, in one declarative systemd-nspawn NixOS container.
#
# ── M12: five services added, one skipped, one split out ─────────────────────
#
#   M12 is the arr-helpers milestone.  EVERYTHING IT ADDS LANDS IN THIS
#   CONTAINER — no new veth, no new MAC, no new DHCP reservation, no UDM-Pro
#   work — deliberately, so that the packaging risk it exists to prove (four
#   services with no nixpkgs package and no NixOS module) is never in flight
#   at the same time as a networking change.
#
#     (a) Byparr          SPLIT OUT.  See "BYPARR IS NOT HERE" below.
#     (b) UmlautAdaptarr  hand-rolled derivation, ./pkgs/umlautadaptarr.nix
#     (c) Bazarr          upstream module, hardened here from nothing
#     (d) Cleanuparr      hand-rolled derivation, ./pkgs/cleanuparr.nix
#     (e) Unpackerr       SKIPPED on a measurement.  See its block below.
#     (f) MediathekArr    hand-rolled derivation, ./pkgs/mediathekarr.nix,
#                         TWO units — upstream ships two processes
#     (g) recyclarr       three more instances, no new service
#
#   ── BYPARR IS NOT HERE, AND FLARESOLVERR STAYS ────────────────────────────
#
#   M12 (a) called for Byparr to replace FlareSolverr as a drop-in: same port
#   8191, same /v1 API, same Prowlarr indexer-proxy entry, "Camoufox-based
#   rather than undetected-chromedriver".
#
#   The /v1 half survived checking.  The rest did not.  Byparr v3.0.4
#   (2026-08-18) IS NOT CAMOUFOX-BASED — it is Playwright plus
#   `invisible-playwright`, and packaging it means three PyPI packages nixpkgs
#   does not have (invisible-playwright, invisible-core, playwright-captcha), a
#   pin of playwright==1.60.* against the 1.59.1 in ernst's nixpkgs, Python
#   3.14 exactly, and a sealed patched-Firefox engine that invisible-core
#   downloads and verifies against its own digest at run time.  That last one
#   is packageable as a fixed-output derivation, but only after working out
#   how the seal is computed.
#
#   That is a browser-packaging milestone wearing an arr-helper's clothes, and
#   its realistic failure mode is the worst kind available here: a Byparr that
#   starts, answers /v1, and never actually solves a challenge.  Split out on
#   2026-08-26 rather than half-done.  FlareSolverr is untouched below and
#   still works; what it does not do is 2026 Turnstile, which is the whole
#   reason the replacement was wanted.
#
#   ── THE EXIT-COUNTRY MEASUREMENT WAS RE-RUN, NOT INHERITED ────────────────
#
#   M12 requires it, because a measurement carried forward untested is the
#   failure M2b's item 1 warns about.  2026-08-26, the same URL M4 used:
#
#     from this container   https://eztvx.to/   HTTP 200
#     from the IVPN exit    https://eztvx.to/   HTTP 451
#                           exit 95.211.172.88, country NL (Leaseweb)
#
#   Identical to M4's 2026-08-21 result, and it is what keeps FlareSolverr —
#   and, when it lands, Byparr — on this side of the tier boundary.  It is
#   also what decides MediathekArr's placement, in the opposite direction: see
#   that block.
#
#   FlareSolverr's footprint, for the comparison M12 asks for when Byparr
#   arrives: 243 MB resident, 842 MB peak, measured on ernst the same day.
#
# Why nspawn: architecture invariant #1.  These are trusted, storage-heavy
# services that never talk to the internet on their own behalf in a way that
# needs a killswitch — Prowlarr fetches from indexers, Sonarr/Radarr fetch
# metadata, and the actual downloading happens one tier up, inside M3's VPN
# microvm.  nspawn gives a real NixOS view (services.sonarr as-is, with its
# upstream hardening) while sharing the host kernel.
#
# ── Why ONE container and not three ──────────────────────────────────────────
#
#   M4's prompt asked for the single-container shape by default and for an
#   argument if it were split.  It is not split, and the argument for keeping
#   them together is stronger than "fewer files":
#
#     Prowlarr's whole job is to PUSH indexer definitions into Sonarr and
#     Radarr over their REST APIs.  In one netns that is 127.0.0.1:8989 and
#     127.0.0.1:7878 — no firewall rule, no DHCP reservation, no UDM-Pro
#     policy, and nothing that can break when the Services zone changes.
#     Split into three containers it becomes three L2 identities, three
#     reservations, and intra-zone traffic that has to be allowed explicitly.
#
#     They also share one failure domain already: all three read and write the
#     same /srv/media hardlink domain as the same group, so isolating them
#     from each other buys nothing that matters.  The boundary worth having is
#     the one between this container and the download client, and that one is
#     a microvm with its own kernel.
#
#   What splitting WOULD buy, for the record, so this is re-arguable: an
#   independent restart per service, and per-service Traefik backends in M5
#   that do not share a hostname.  Neither is worth six extra moving parts
#   today; M5 can route three paths to one address perfectly well.
#
# ── Networking: veth on br0, Services VLAN 90.  NOT host networking ──────────
#
#   M4's prompt said "v1: HOST networking, exactly like Jellyfin's v1", with a
#   veth-migration note for later.  That instruction predates M2b.  It is
#   deliberately NOT followed, and the reason is in this repo rather than in
#   taste:
#
#     - machines/ernst/networking.nix's worked example B is titled
#       "systemd-nspawn container (M4 arr, M5 Traefik)".  The topology file
#       already expects this file to be a pattern-B consumer.
#     - Host networking would re-open host ports on ernst two PRs after #82
#       deleted the last one (ledger row L3), and would book a second
#       UDM-Pro round plus a migration PR to undo it.
#     - The download client is on VLAN 90 (10.0.90.11).  On VLAN 90 this
#       container reaches it over br0 at layer 2 — the frame never reaches
#       the UDM-Pro at all, because both ports are in the same VLAN on the
#       same bridge.  So the ZBF rule M4's prompt listed as a manual step
#       does not need to exist.  Host networking would have needed one.
#
#   Copied from machines/ernst/containers/jellyfin.nix ("Networking — v2"),
#   which is the working version of this pattern: KeepMaster rather than
#   Bridge=, the ExecStartPost that settles the VLAN race, and the 20 s
#   wait-online cap that keeps a DHCP failure from restart-looping the
#   container.  Read that file's header for the full rationale; it is not
#   repeated here.
#
#   Addressing is DHCP with a reservation on the UDM-Pro keyed on the pinned
#   MAC below, NOT a static address in this file — same call as M2b, same
#   reason: the UDM-Pro owns the subnet and the pool, and a second copy here
#   diverges silently.  The RESOLVER is the opposite call and is declared
#   here (Technitium, 10.0.5.3), because a DHCP-supplied resolver that
#   quietly changes does not fail loudly.
#
#   The reservation must be INSIDE the DHCP pool (10.0.90.6–.254).  UniFi
#   accepts an address from the .2–.5 range the cutover runbook set aside and
#   then silently hands out an ordinary pool lease instead — M2b lost a round
#   to exactly that.
#
# ── uid/gid: the numbers are the interface ───────────────────────────────────
#
#   nspawn does not remap uids or gids here, so a number chosen inside this
#   container is a number on zdata, and it has to agree with the numbers M3's
#   guest and M2b's container already write with.  The allocation table lives
#   in machines/ernst/networking.nix; this file adds three rows to it.
#
#     uid 3002  sonarr    ) primary group MEDIA (gid 3000), not a
#     uid 3003  radarr    ) supplementary one — see below
#     uid 3004  prowlarr    own group, no media access at all
#
#   MEDIA IS THE PRIMARY GROUP, and that is not a style choice.  Upstream's
#   sonarr/radarr units set PrivateUsers=true, which maps only User= and
#   Group= into the service's user namespace; a supplementary membership is
#   squashed to nogroup inside it and every write to /srv/media lands
#   group-less.  M3 hit this first and its header explains it at length.
#
#   Prowlarr gets NO media access.  It is an indexer proxy: it talks to
#   trackers and to the other two services' APIs, and never touches a file
#   under /srv/media.  Giving it gid 3000 "for symmetry" would be a strictly
#   larger blast radius for no capability.
#
#   3002–3004 rather than nixpkgs' own static ids (ids.uids.sonarr = 274,
#   radarr = 275).  Those would be safe — nixpkgs reserves them fleet-wide, so
#   they cannot collide — but the media stack's ids should read as one family
#   in `ls -n` output on zdata, and M3's deployed hardlink proof already used
#   uid 3002 in group media as the stand-in for "the arr".  Keeping that
#   number means the proof and the thing it was proving are the same uid.
#   The cost is one lib.mkForce, below, and it is commented where it happens.
#
# ── Hardlinks: the entire point of this milestone ────────────────────────────
#
#   Sonarr/Radarr import by hardlinking from the download directory into the
#   library.  A hardlink cannot cross a filesystem boundary, so three things
#   must all hold at once:
#
#     1. ONE DATASET.  /srv/media is a single ZFS dataset with plain
#        subdirectories (invariant #2, enforced since #20).  Do not add
#        datasets under it — a sub-dataset silently converts every import
#        into a copy.
#     2. IDENTICAL PATHS EVERYWHERE.  /srv/media is bound at /srv/media —
#        same string on the host, in M3's guest, and in here.  qBittorrent
#        reports a completed torrent at /srv/media/torrents/tv/<x>; Sonarr
#        looks for it at /srv/media/torrents/tv/<x>; both are the same inode.
#        That is what makes *arr "Remote Path Mapping" unnecessary, and a
#        remote path mapping that is merely missing looks exactly like a
#        permissions failure.
#     3. READ **AND WRITE** ON THE SOURCE FILE.  fs.protected_hardlinks is 1
#        (kernel default) and refuses link() on a file you do not own unless
#        you have both.  qBittorrent writes as uid 3001 with UMask=0002, so
#        its files are 0664 root-inheriting-gid-media; sonarr (uid 3002, group
#        media) therefore has the write bit and link() succeeds.  M3 measured
#        this, negative control included: the same file at 0644 refused with
#        EPERM.
#
#   A link count of 1 after an import is a FAILED milestone, not a cosmetic
#   issue.  The PR test plan proves it with `stat` on both paths.
#
# ── Storage layout on this host (see machines/ernst/disko.nix) ───────────────
#
#   /srv/media            zdata/media   RW into the container at /srv/media
#     library/{movies,tvshows}          *arr root folders — the import TARGET
#     torrents/{movies,tv,complete}     qBittorrent's output — the SOURCE
#   /srv/state/sonarr     zdata/state   RW at /var/lib/sonarr
#   /srv/state/radarr     zdata/state   RW at /var/lib/radarr
#   /srv/state/prowlarr   zdata/state   RW at /var/lib/prowlarr
#
#   State is on zdata because zroot rolls back (invariant #7).  The bind
#   targets are the UPSTREAM DEFAULT state paths, so the packaged units need
#   no dataDir override — the same trick containers/jellyfin.nix uses for
#   /var/lib/jellyfin, and it is why `dataDir` is left alone below.
#
# ── Authentication is deliberately NOT declared here ─────────────────────────
#
#   The obvious move is settings.auth.method = "Forms" via the env-var
#   passthrough.  Do not: on a FIRST start, with no user in the database, an
#   already-set AuthenticationMethod skips the "Create Admin User" wizard and
#   leaves a login form no account can satisfy.  The wizard is the intended
#   bootstrap and it is a manual step in the PR body.  Pinning auth
#   declaratively is safe only AFTER an account exists, and is a follow-up.
{ config, lib, pkgs, ... }:
let
  # Numeric ids — see the file header.  These are ids on zdata, not just ids
  # inside the container.
  sonarrUid   = 3002;
  radarrUid   = 3003;
  prowlarrUid = 3004;
  prowlarrGid = 3004;

  # M12's additions.  Reserved in machines/ernst/networking.nix.
  #
  # 3010 (umlautadaptarr) and 3013 (unpackerr) are RESERVED AND UNUSED, both
  # deliberately — see the umlautadaptarr block and the M12 section of the
  # header.  They are not reassigned here; a reservation that gets quietly
  # reused is worse than one that stays empty.
  bazarrUid       = 3009;
  cleanuparrUid   = 3011;
  mediathekarrUid = 3012;

  # M13's additions.  Also reserved in machines/ernst/networking.nix, which
  # already carried these three rows before this milestone started.
  #
  # Two own-group services and one media member, and the split is the same
  # capability question the header asks of every uid here:
  #
  #   jellyseerr  REQUESTS media.  It talks to Sonarr, Radarr and Jellyfin over
  #               REST and never opens a file under /srv/media, so it gets its
  #               own group and no media access — the prowlarr shape.
  #   janitorr    DELETES media, and additionally writes a tree of symlinks for
  #               its "Leaving Soon" collections.  `media` PRIMARY.
  #   scraparr    READS REST APIs and serves /metrics.  Own group, the prowlarr
  #               shape again.
  jellyseerrUid = 3014;
  jellyseerrGid = 3014;
  janitorrUid   = 3015;
  scraparrUid   = 3016;
  scraparrGid   = 3016;

  # ── M14's additions.  Reserved in machines/ernst/networking.nix ────────────
  #
  # FIVE here and a sixth elsewhere.  slskd's 3024 is NOT in this list: it runs
  # in the MICROVM GUEST, because Soulseek is P2P on the open internet on
  # ernst's behalf and invariant #1 puts that one tier up.  See
  # machines/ernst/microvms/wg-qbittorrent.nix.
  #
  # Four `media` members and one own-group service, and the split is the same
  # capability question this file asks of every uid:
  #
  #   lidarr          IMPORTS music into the library — it hardlinks out of
  #                   slskd's download tree, which is the second write path
  #                   this whole milestone exists to prove.  media PRIMARY.
  #   soularr         drives Lidarr and slskd over REST, and never opens a file
  #                   under /srv/media... EXCEPT that it must read the download
  #                   directory to match tracks (music-tag reads ID3 out of the
  #                   downloaded files).  media PRIMARY, and this is the one
  #                   M14 uid whose group is not obvious from its description.
  #   kapowarr        DOWNLOADS comics and files them.  media PRIMARY.
  #   audiobookshelf  serves its OWN tree on zdata/audiobooks and never touches
  #                   /srv/media at all.  media PRIMARY anyway — see its block
  #                   for why that is about /srv/audiobooks, not /srv/media.
  #   questarr        OWN group, NO media.  It is the prowlarr shape: it talks
  #                   to IGDB and Prowlarr over REST and files games onto
  #                   /srv/games, which is a different dataset entirely and not
  #                   part of the hardlink domain.
  lidarrUid         = 3017;
  soularrUid        = 3018;
  kapowarrUid       = 3019;
  questarrUid       = 3020;
  questarrGid       = 3020;
  audiobookshelfUid = 3021;

  # M17.  Bindery DOWNLOADS ebooks and files them into /srv/media — the third
  # write path into the hardlink domain (after the *arr trio and slskd), which
  # is why it owes its own hardlink proof (uid-specific; M14's covered slskd's
  # uid, not this one).  media PRIMARY, the kapowarr shape.
  binderyUid        = 3028;

  # Fixed on the HOST in machines/ernst/containers/jellyfin.nix, which owns
  # `users.groups.media`.  Restated numerically here (and by name only inside
  # the container, where this file does declare the group) so that nothing in
  # arr.nix depends on jellyfin.nix's evaluation order.
  mediaGid = 3000;

  # Guest-side MAC — 02:00:00:<vlan>:00:<seq>, allocated in the table in
  # machines/ernst/networking.nix.  This is the address the UDM-Pro sees and
  # the one the DHCP reservation keys on; never the host-side vb-arr.
  arrMac = "02:00:00:90:00:05";
  vlanId = 90;

  # Host side of the veth pair.  nspawn names it vb-<container> when
  # --network-bridge= is used — "vb-", not "ve-".
  vethName = "vb-arr";

  # Web UI ports.  Upstream defaults, restated here because three things have
  # to agree: the services' own `settings.server.port`, the container's
  # firewall, and the UDM-Pro rule (ledger row L4).  Only the first two can be
  # kept in step from the repo.
  prowlarrPort = 9696;
  sonarrPort   = 8989;
  radarrPort   = 7878;

  # FlareSolverr.  Deliberately NOT in the firewall list below — Prowlarr
  # reaches it on 127.0.0.1 and nothing outside this netns ever should.
  flaresolverrPort = 8191;

  # ── M12 ports ──────────────────────────────────────────────────────────────
  #
  # Two groups, and the distinction is the whole of this file's port policy:
  #
  #   REACHABLE (through Traefik only, via the restricted list below) — the
  #   three that a human opens in a browser more than once.
  bazarrPort       = 6767;
  cleanuparrPort   = 11011;
  mediathekarrDownloaderPort = 5007;   # SABnzbd shim *and* the setup wizard
  #
  #   LOCALHOST-ONLY (absent from the list, and staying absent, exactly like
  #   flaresolverrPort) — the ones whose only client is another process in this
  #   same netns.  Nothing outside this container has any business reaching an
  #   indexer shim or a rewriting proxy.
  mediathekarrIndexerPort = 5008;      # Newznab; Prowlarr reaches it on lo
  umlautadaptarrPort      = 5005;      # its own HTTP API
  umlautadaptarrProxyPort = 5006;      # the proxy Prowlarr's indexers point at

  # ── M13 ports ──────────────────────────────────────────────────────────────
  #
  # THREE SERVICES, THREE DIFFERENT ANSWERS TO "who may reach this", and the
  # spread is wider than M12's two-way split — so it gets its own note rather
  # than being appended to the lists above.
  #
  #   REACHABLE THROUGH TRAEFIK.  Jellyseerr is the only one, and it is also
  #   the only service in this container that is NOT admin-facing: it is what
  #   the household opens to ask for a film.  Its Traefik router deliberately
  #   carries NO forward-auth middleware — see the jellyseerr block below and
  #   the router in containers/traefik.nix.
  jellyseerrPort = 5055;
  #
  #   REACHABLE FROM PROMETHEUS, AND FROM NOTHING ELSE.  This is a NEW SHAPE
  #   for this file: every restricted rule here until now named traefikAddr,
  #   because every port here until now fronted a browser.  A metrics endpoint
  #   is scraped by the monitoring container instead, so it needs a second
  #   source — see monitoringAddr below and the extraCommands block.
  scraparrPort = 7100;
  #
  #   REACHABLE BY NOBODY.  Janitorr binds a port only because Spring Boot MVC
  #   is on its classpath; it has NO web UI at all.  Verified at v2.2.0 by
  #   reading the source: zero @RestController / @Controller classes and an
  #   empty static-resources tree, and upstream's own README says "You don't
  #   have to publish ANY ports on the host machine."
  #
  #   So this number exists to be PINNED AND BOUND TO LOOPBACK, not to be
  #   opened.  Left at Spring Boot's default it would be 8080 on 0.0.0.0 —
  #   i.e. on the veth, on VLAN 90 — which is the umlautadaptarr trap again.
  #   8978 is the number docs/roadmap.md reserved for Janitorr, kept so the
  #   roadmap and the repo agree even though nothing routes to it.
  janitorrPort = 8978;

  # ── M14 ports ─────────────────────────────────────────────────────────────
  #
  # VERIFIED AGAINST UPSTREAM, as docs/roadmap.md's M14 requires — and one of
  # the four was wrong in the roadmap, which is exactly why it says "verify"
  # rather than listing them as fact:
  #
  #   lidarr          8686   correct.  The servarr settings module's default.
  #   kapowarr        5656   correct.  backend/internals/settings.py, V1.3.1.
  #   questarr        5000   correct.  Its own docs, and the PORT env var it
  #                          reads is what sets it.
  #   audiobookshelf 13378   THE ROADMAP'S NUMBER IS THE DOCKER IMAGE'S, NOT
  #                          THE MODULE'S.  nixpkgs' services.audiobookshelf
  #                          defaults to port 8000 and host 127.0.0.1.  13378
  #                          is what every Audiobookshelf client and every
  #                          upstream doc says, so it is set EXPLICITLY below
  #                          rather than left at the module default — and the
  #                          host has to be set too, or Traefik cannot reach it
  #                          at all.
  #
  # All four are REACHABLE through Traefik: each is a browser UI a human opens
  # more than once.  Audiobookshelf is the only one of them that is not
  # admin-facing — it is a household service, like Jellyseerr — but unlike
  # Jellyseerr it still gets the `authelia` middleware.  See its block.
  lidarrPort         = 8686;
  kapowarrPort       = 5656;
  questarrPort       = 5000;
  audiobookshelfPort = 13378;

  # ── M17 port ──────────────────────────────────────────────────────────────
  #
  # VERIFIED BY RUNNING THE BINARY (2026-08-29), not read off a docs page:
  # its startup log prints `"port":"8787"` and `ss` shows `*:8787` — i.e. it
  # binds 0.0.0.0, the umlautadaptarr/questarr posture, so the restricted
  # rule below is load-bearing for it too.  BINDERY_PORT is what sets it.
  # Reachable through Traefik: a browser UI a human opens more than once.
  binderyPort        = 8787;
  #
  # ── THE SYSCALL FILTER FOR EVERY UNIT IN THIS CONTAINER ──────────────────
  #
  # ONE binding, used by all of them, and it is what nixpkgs' own sonarr and
  # radarr modules already use — verified by reading sonarr.nix at ernst's pin,
  # which ends its list with exactly `"@chown"`.
  #
  # Everything hand-written in this file used to carry the first four entries
  # and drop the fifth.  `@chown` is added back after `~@privileged` removes
  # it; later entries win, so the trailing `@chown` re-permits
  # chown/fchown/lchown/fchownat.
  #
  # ── WHY, MEASURED ON ernst 2026-08-28 ───────────────────────────────────
  #
  # Audiobookshelf was killed on startup by the filter, immediately after it
  # had opened its database:
  #
  #   audiobookshelf.service: Main process exited, code=dumped, status=31/SYS
  #   audit: type=1326 uid=3021 comm="libuv-worker" sig=31 syscall=93
  #
  # `status=31/SYS` is SIGSYS — a seccomp kill, not an application error — and
  # syscall 93 on x86_64 is `fchown`.  systemd's `@privileged` set includes
  # `@chown`, so `~@privileged` removed it and the service died the first time
  # Node touched file ownership.
  #
  # ── WHY THIS COSTS ALMOST NOTHING ───────────────────────────────────────
  #
  # Every unit using this list also sets `CapabilityBoundingSet = ""`, so it
  # has no CAP_CHOWN — and without CAP_CHOWN the kernel only permits chown to
  # the caller's OWN uid/gid.  Re-allowing the syscall therefore grants the
  # ability to set ownership these services already have, and nothing more.
  #
  # What blocking it bought was not security but a CRASH: SIGSYS kills the
  # process outright rather than returning EPERM, so the failure mode is a
  # service that dies mid-operation instead of one that handles an error.
  #
  # ── AND IT IS WHAT UPSTREAM ALREADY DOES ────────────────────────────────
  #
  # nixpkgs' sonarr and radarr modules ship a filter that PERMITS chown —
  # verified both from the live units on ernst (`systemctl show sonarr -p
  # SystemCallFilter` lists `chown chown32`, ours did not) and from the module
  # source.  So this is not a laxer policy invented here; it is the policy the
  # *arrs in this same container have been running under for months.
  #
  # ── WHY IT IS APPLIED TO THE PRE-EXISTING SERVICES TOO ──────────────────
  #
  # M12's and M13's units were written with the four-entry list and have run
  # without incident, so the risk here is LATENT rather than observed — with
  # one exception worth naming, because it is the same failure that actually
  # fired:
  #
  #   seerr (Jellyseerr) is Node, and the process seccomp killed on 2026-08-28
  #   was a Node `libuv-worker` calling fchown.  Same runtime, same worker
  #   pool, same syscall — Audiobookshelf simply reached it first because it
  #   touches ownership during its initial library scan.
  #
  # The others are a spread of likelihood rather than a certainty: bazarr
  # writes .srt sidecars next to media, mediathekarr writes and remuxes video,
  # cleanuparr deletes files it does not own, and janitorr-config renders files
  # as root.  Any of them calling fchown once would be killed outright rather
  # than handed an EPERM it could report.
  #
  # NOT CHANGED, deliberately, and both are outside this container: traefik's
  # unit (containers/traefik.nix) and the qBittorrent exporter in the microvm
  # guest.  Neither writes into a shared tree, both are working, and neither
  # has any evidence of need — a filter is not something to widen across
  # ownership boundaries on symmetry alone.
  arrSyscallFilter = [ "@system-service" "~@privileged" "~@debug" "~@mount" "@chown" ];

  # SOULARR HAS NO PORT, and that is worth stating in the same place as the
  # ones that do.  It is a one-shot script driven by a timer, not a server; its
  # bundled Flask web UI is deliberately not packaged at all (see
  # ./pkgs/soularr.nix).  Nothing listens, so nothing is opened.

  # ── Janitorr's dry-run, hoisted into one place ─────────────────────────────
  #
  # This is the switch M13 says the first deploy must keep ON, and turning it
  # off is a separate, deliberate commit.  It is a binding rather than a
  # literal in the config heredoc because it now decides TWO things, and they
  # must not drift apart:
  #
  #   application.dry-run    whether Janitorr actually deletes
  #   logging level          DEBUG while dry-running, INFO once live
  #
  # ── WHY THE LOG LEVEL IS TIED TO IT ───────────────────────────────────────
  #
  # A dry run whose output is empty is not a dry run, it is a shrug — and at
  # INFO that is exactly what this produced on the first deploy.  Measured on
  # ernst 2026-08-26: Janitorr started, ran all three schedules, and logged
  # only "Tag based cleanup disabled" and "Episode based cleanup disabled".
  # The MEDIA schedule — the enabled one — printed nothing at all.
  #
  # That silence was CORRECT, and the reason is worth writing down because it
  # will recur.  Reading AbstractCleanupSchedule.scheduleDelete: when free
  # space is above every configured threshold, `determineDeletionDuration`
  # returns FOREVER, so `shouldDelete` is false AND `expiration` is FOREVER —
  # which makes both `log.info` branches unreachable:
  #
  #   if (!shouldDelete && expiration != FOREVER.duration)   → false
  #   if (leavingSoonExpiration != FOREVER.duration)         → false
  #
  # The pool was 69% free against a highest threshold of 10%, so Janitorr had
  # nothing to say and said it.  Everything that WOULD have explained the
  # decision — the computed expirations, the free-space percentage — is at
  # log.debug in MediaCleanupSchedule, and the per-title reasoning is at
  # log.trace.  Upstream's own config template says as much: "Set to DEBUG or
  # TRACE to get more info about what Janitorr is doing."
  #
  # So while dry-run is on, DEBUG is the only setting that makes the milestone
  # verifiable.  When dry-run goes off, this reverts to INFO on the same line,
  # and INFO is right then: a live Janitorr logs what it actually deleted.
  janitorrDryRun = true;

  # Where the Sonarr/Radarr API keys are staged.  A tmpfs under /run,
  # refreshed before every consumer starts — see the arr-api-keys block.
  #
  # RENAMED from /run/recyclarr-secrets in M12, and the rename is the point:
  # UmlautAdaptarr needs the same two keys, from the same two config.xml files,
  # for the same reason (they are not ours to choose — see that block).  One
  # stager with two consumers beats a second copy of a 40-line hardened unit
  # that reads the same files.
  arrSecretsDir = "/run/arr-api-keys";

  # Host state sources.  Bound to the upstream default paths inside.
  stateRoot = "/srv/state";

  # Traefik's veth address on VLAN 90 (M5, DHCP reservation on the UDM-Pro
  # keyed on 02:00:00:90:00:04).  The ONLY source permitted to reach the three
  # web UIs.
  #
  # This is the boundary that matters most in this file, and it is worth being
  # explicit about why: 10.0.90.11 — the qBittorrent microvm, the one workload
  # on ernst that talks to the open internet on its own behalf — is one
  # layer-2 hop away on this same bridge.  Its frames to .13 never reach the
  # UDM-Pro, so no gateway rule can filter them.  This one can.  The full
  # argument, and what it does not cover, is in the "BACKEND BYPASS HARDENING"
  # section of machines/ernst/containers/traefik.nix.
  traefikAddr = "10.0.90.12";

  # The monitoring container's veth address on VLAN 90 (M6, DHCP reservation
  # keyed on 02:00:00:90:00:06).  A SECOND permitted source, and the first one
  # this file has ever had.
  #
  # WHY IT CANNOT JUST GO THROUGH TRAEFIK, since that is the obvious question:
  # Prometheus scrapes over plain HTTP on a schedule and has no browser, no
  # cookie jar and no way through forward-auth.  Routing /metrics through the
  # proxy would mean either a Traefik router with no authentication at all on a
  # name in the public CT log, or an Authelia bypass rule — both strictly worse
  # than one iptables rule naming one address on the same bridge.
  #
  # It is the same layer-2 hop as traefikAddr and carries the same caveat: the
  # frames never reach the UDM-Pro, so this rule is the only enforcement point.
  # M6's containers/traefik.nix and containers/authelia.nix already accept from
  # this address for exactly the same reason (their own metrics listeners);
  # this file is the third.
  monitoringAddr = "10.0.90.14";

  # M13.  The Jellyfin container's veth address on VLAN 90 (M2b, DHCP
  # reservation keyed on 02:00:00:90:00:02) and the port it serves.
  #
  # Janitorr is the FIRST service in this container to talk to Jellyfin, and
  # that is a boundary crossing worth naming rather than inlining: everything
  # else here reaches its peers on 127.0.0.1 because they share this netns.
  # Jellyfin does not — it is a separate container with its own kernel-level
  # network namespace and its own firewall, which today accepts 8096 from
  # TRAEFIK ONLY.
  #
  # So this address is not sufficient on its own: containers/jellyfin.nix gains
  # a second source-restricted accept for this container, exactly mirroring the
  # one this file gains for the monitoring container.  Both are in the same PR.
  jellyfinAddr = "10.0.90.10";
  jellyfinPort = 8096;

  # M14.  The VPN microvm's address on VLAN 90 (M3, DHCP reservation keyed on
  # 02:00:00:90:00:03) and slskd's API port inside it.
  #
  # This is the SECOND cross-boundary peer this container has, after Jellyfin,
  # and it is the more interesting one: it is an OUTBOUND connection to the
  # guest that faces the open internet.  Soularr initiates it, the guest's
  # nftables `api_clients` set admits it, and no UDM-Pro rule exists or could
  # — vb-arr and tap-vpn are both VLAN-90 ports on br0, so the frames are
  # switched locally and the gateway never sees them.  That is M4's departure 2,
  # unchanged, and M14 reuses it rather than inventing a second mechanism.
  #
  # The guest's set gained a PORT for this, not a client: the arr container was
  # already in `api_clients` for qBittorrent's WebUI.
  slskdAddr = "10.0.90.11";
  slskdPort = 5030;

  # M14.  slskd's download tree, declared in microvms/wg-qbittorrent.nix and
  # restated here because THREE things have to agree on it verbatim: slskd's
  # own `directories.downloads`, Soularr's config.ini (which tells Lidarr where
  # to look), and Lidarr's import.
  #
  # It is a SIBLING of /srv/media/torrents rather than a subdirectory, so that
  # "which client wrote this" stays answerable — and both are inside
  # /srv/media, which is what actually matters for hardlinks (invariant #2: the
  # domain is the DATASET, not the directory layout).
  soulseekRoot        = "/srv/media/soulseek";
  soulseekDownloadDir = "${soulseekRoot}/complete";

  # M14.  Where Soularr's rendered config.ini lives — a tmpfs under /run,
  # written on every timer firing before the script runs.
  #
  # It holds TWO API keys (Lidarr's, read out of Lidarr's own config.xml by
  # arr-api-keys; and slskd's, from the clan var), so it cannot be a store
  # file.  Same shape and same reasoning as janitorr's application.yml.
  soularrConfigDir = "/run/soularr";

  # M14.  slskd's API key, generated by the slskd-credentials generator over in
  # microvms/wg-qbittorrent.nix — ONE generator, TWO consumers, so a rotation
  # cannot leave the guest and Soularr disagreeing.
  #
  # Guarded for the same reason janitorrJellyfinGen is: referencing a generator
  # that does not exist yet is an EVALUATION error naming an attribute, rather
  # than a runtime error naming the command a human forgot to run.
  slskdCredsGen =
    if config.clan.core.vars.generators ? slskd-credentials
    then config.clan.core.vars.generators.slskd-credentials
    else { files."api-key".path = "/no-such-path"; };

  # Where that key is STAGED for the container.
  #
  # `slskdCredsGen.files."api-key".path` is a HOST path under /run/secrets, and
  # /run in an nspawn container is a private tmpfs — the host's copy is simply
  # not there.  Pointing soularr's LoadCredential straight at it is what
  # shipped, and PID 1 inside the container failed every single firing with
  #
  #   soularr.service: Failed to set up credentials: No such file or directory
  #   soularr.service: Control process exited, code=exited, status=243/CREDENTIALS
  #
  # 1412 times between 2026-08-28 and 2026-09-06, during which Soularr never
  # completed one pass.  It is the same class of mistake as the "Permission
  # denied" bug the LoadCredential block below was added to fix, one layer out:
  # that fix made the LIDARR key reachable and left the slskd one unreachable.
  #
  # So the key takes the route every other secret in this file takes: a host
  # unit copies it into a directory, and that directory is bound in read-only
  # at the same path.  Modelled on janitorrSecretsDir, which does exactly this
  # and for exactly this reason.
  soularrSecretsDir = "/run/soularr-secrets";

  # M14.  Audiobookshelf's library tree, on its OWN dataset (zdata/audiobooks,
  # declared in machines/ernst/disko.nix) rather than under /srv/media.
  #
  # It is a SIBLING of /srv/media, not a child, so it creates no dataset
  # boundary inside the hardlink domain and invariant #2 is untouched.  Nothing
  # here is ever hardlinked: Audiobookshelf has no importer, and Storyteller
  # reads a pair and writes a new file rather than linking either.  That is why
  # docs/roadmap.md exempts Audiobookshelf from M14's hardlink proof.
  audiobooksRoot = "/srv/audiobooks";

  # M13.  Janitorr's Jellyfin credentials, staged host-side out of sops and
  # bound read-only into the container at the SAME path — see the generator
  # and the staging unit below for why this is not a bind of /run/secrets.
  janitorrSecretsDir = "/run/janitorr-secrets";

  # Guarded rather than selected directly, the same way
  # service-modules/monitoring.nix guards its ntfy generator: referencing a
  # generator that does not exist yet is an EVALUATION error, and an evaluation
  # error names an attribute rather than the thing a human forgot to run.  With
  # the guard, a machine whose `clan vars generate ernst` has not been run yet
  # still evaluates, and the failure moves to the staging unit at runtime where
  # the message can say what to do.
  janitorrJellyfinGen =
    if config.clan.core.vars.generators ? janitorr-jellyfin
    then config.clan.core.vars.generators.janitorr-jellyfin
    else { files."credentials.env".path = "/no-such-path"; };
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

    # KAPOWARR'S DOWNLOAD TREE, and — like MediathekArr's — it is NOT under
    # ${stateRoot}.  It is media: Kapowarr downloads .cbz files here and then
    # files them into its own library, and both ends must be inside the one
    # dataset or the move degrades into a copy.
    "d /srv/media/torrents/comics 2770 root ${toString mediaGid} -"
    "d /srv/media/library/comics  2770 root ${toString mediaGid} -"

    # M17 — BINDERY'S TREES, the same shape for the same reason: download and
    # library ends BOTH inside /srv/media, so the import is a rename (or a
    # hardlink) on one dataset rather than a copy across two (invariant #2).
    # NOT /srv/audiobooks: that dataset belongs to the Audiobookshelf +
    # Storyteller pair; Bindery's audiobook capability is deliberately left
    # unrouted (see its unit below).
    "d /srv/media/torrents/books  2770 root ${toString mediaGid} -"
    "d /srv/media/library/books   2770 root ${toString mediaGid} -"

    # AUDIOBOOKSHELF'S TREE, on its own dataset.
    #
    # Three directories, and the split is what makes Storyteller and
    # Audiobookshelf complementary rather than overlapping:
    #
    #   library/      finished audiobooks.  Audiobookshelf scans this.
    #   ebooks/       the DRM-free ebook halves, staged by hand.
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

  # The rest of the media tree is NOT declared here.  containers/jellyfin.nix
  # owns those tmpfiles rules (library/{movies,tvshows}, torrents/{movies,tv})
  # and microvms/wg-qbittorrent.nix owns torrents/{incomplete,complete}.  A
  # second set of rules for the same paths is precisely the failure M3 spent a
  # round on: tmpfiles enforces mode and ownership on EVERY run, so two
  # declarations that disagree take turns winning, silently, one per deploy.
  #
  # torrents/mediathek above is the ONE exception and does not break that rule,
  # because it is a path NO OTHER FILE DECLARES.  It belongs to this file
  # because the service that writes it lives in this file, and the ownership
  # rule the M3 lesson actually states is "one declaration per path", not "one
  # file per tree".  If a later milestone moves MediathekArr elsewhere, these
  # three rules move with it rather than being duplicated there.

  ##############################################################################
  # M13 — JANITORR'S JELLYFIN CREDENTIALS.  A clan var, and the only prompted
  # secret this container has.
  #
  # ── WHY THESE THREE CANNOT BE READ OUT OF A CONFIG FILE ────────────────────
  #
  #   Everything else this container needs is read from the application that
  #   generated it: sonarr's and radarr's API keys come out of their own
  #   config.xml (see arr-api-keys), and Jellyseerr's comes out of its own
  #   settings.json.  That keeps ONE source of truth and survives a key
  #   rotation in a UI with no deploy — M4's argument, restated in M12.
  #
  #   Jellyfin is the exception, twice over:
  #
  #     1. Its API key lives in its DATABASE, not in a file this container
  #        could read even if it had a bind mount for it (it does not — the
  #        Jellyfin container is a separate netns and a separate state tree).
  #     2. JANITORR NEEDS A REAL USER, NOT JUST AN API KEY.  Jellyfin's delete
  #        endpoint authorises against a user account with deletion rights;
  #        an API key alone cannot delete.  So a username and password are
  #        needed as well, and an account is definitionally created by a human
  #        in a UI.
  #
  #   That makes prompts the honest shape.  `clan vars generate ernst` asks for
  #   all three; the PR body carries the in-Jellyfin steps that produce them.
  #
  # ── IT IS NOT NEEDED FOR THE FIRST DEPLOY TO SUCCEED ───────────────────────
  #
  #   Deliberately.  Janitorr's first deploy runs in DRY-RUN (see its block),
  #   and dry-run does not call Jellyfin's delete endpoint at all — so a
  #   deploy that lands before the Jellyfin account exists still produces a
  #   Janitorr that starts, connects to the *arrs, and prints what it WOULD
  #   delete, which is the deliverable M13 asks for.
  #
  #   What it will not do until these are filled in is build the "Leaving
  #   Soon" collections, because those are created through the Jellyfin API.
  clan.core.vars.generators.janitorr-jellyfin = {
    files."credentials.env" = {
      secret = true;
    };
    prompts."api-key" = {
      description = "Jellyfin API key for Janitorr (Dashboard → API Keys → +)";
      type = "hidden";
    };
    prompts."username" = {
      description = "Jellyfin username for Janitorr's dedicated deletion account";
      type = "line";
    };
    prompts."password" = {
      description = "Password for that Jellyfin account";
      type = "hidden";
    };
    # Written as an EnvironmentFile rather than three separate files because
    # the consumer is a single config-rendering oneshot inside the container.
    # Values are NOT quoted: systemd's EnvironmentFile parser treats quotes as
    # part of the value unless the whole value is quoted, and a password that
    # silently gains a pair of quotes fails authentication with a message that
    # says nothing about quoting.
    script = ''
      {
        printf 'JELLYFIN_API_KEY=%s\n'  "$(cat "$prompts/api-key")"
        printf 'JELLYFIN_USERNAME=%s\n' "$(cat "$prompts/username")"
        printf 'JELLYFIN_PASSWORD=%s\n' "$(cat "$prompts/password")"
      } > "$out/credentials.env"
    '';
    runtimeInputs = [ pkgs.coreutils ];
  };

  # Stage them where the container can see them.
  #
  # Same shape and the same reasoning as containers/traefik.nix's
  # traefik-secrets: a directory WE own, bound into the container at the same
  # path, rather than a bind of /run/secrets — which is a symlink to a
  # per-generation directory that is REPLACED on every deploy, so an nspawn
  # bind established at container start would keep exposing a deleted
  # generation until the container is restarted.
  #
  # 0400 root:root.  The rendering oneshot inside the container reads this as
  # root before writing a file the janitorr uid can read; uid 3015 never opens
  # this one and must not be able to.
  #
  # GENERATE BEFORE YOU DEPLOY — but unlike traefik-secrets, a deploy that runs
  # first is NOT fatal here.  Until the var exists, `files.<n>.path` evaluates
  # to the literal "/no-such-path", so this unit fails; it is deliberately NOT
  # `requiredBy` container@arr, so the container still starts and every other
  # service in it runs.  Janitorr's config renderer degrades to a Jellyfin-less
  # configuration, which is exactly what dry-run needs.  See the janitorr-config
  # block, which is where that degradation is implemented and explained.
  #
  # ROTATING THE CREDENTIALS needs a restart, not just a deploy: if this unit's
  # text is unchanged, systemd will not re-run it when the underlying sops file
  # changes.  After `clan vars generate ernst`:
  #     systemctl restart janitorr-secrets container@arr
  systemd.services.janitorr-secrets = {
    description = "Stage Janitorr's Jellyfin credentials for container@arr";
    after       = [ "local-fs.target" ];
    before      = [ "container@arr.service" ];
    wantedBy    = [ "container@arr.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root ${janitorrSecretsDir}
      ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
        ${janitorrJellyfinGen.files."credentials.env".path} \
        ${janitorrSecretsDir}/jellyfin.env
    '';
  };

  # The same staging, for slskd's API key — see soularrSecretsDir above for why
  # soularr cannot read the clan var's own path from inside the container.
  #
  # ROTATING IT needs a restart and not just a deploy, for the same reason as
  # janitorr-secrets: unchanged unit text means systemd will not re-run this
  # when the underlying sops file changes.  After `clan vars generate ernst`:
  #     systemctl restart soularr-secrets container@arr
  systemd.services.soularr-secrets = {
    description = "Stage slskd's API key for Soularr in container@arr";
    after       = [ "local-fs.target" ];
    before      = [ "container@arr.service" ];
    wantedBy    = [ "container@arr.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    # Stage an EMPTY file rather than failing when the var is absent.
    #
    # LoadCredential is evaluated by PID 1 before ExecStartPre runs, so a
    # missing source file kills soularr at step CREDENTIALS with "No such file
    # or directory" — which names neither the key nor the command that would
    # produce it.  An empty file lets the unit reach its own render script,
    # whose emptiness check already prints the actionable message.  A source
    # that exists but cannot be copied still fails here, loudly, as it should.
    script = ''
      ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root ${soularrSecretsDir}
      if [ -r ${slskdCredsGen.files."api-key".path} ]; then
        ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
          ${slskdCredsGen.files."api-key".path} \
          ${soularrSecretsDir}/slskd-api-key
      else
        echo "soularr-secrets: no slskd API key at ${slskdCredsGen.files."api-key".path} — run 'clan vars generate ernst'. Staging an empty file so soularr reports it by name." >&2
        ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
          /dev/null ${soularrSecretsDir}/slskd-api-key
      fi
    '';
  };

  # Host side of the container's veth — a VLAN-90 port on br0.
  #
  # There is deliberately NO `networking.firewall.allowedTCPPorts` here.  The
  # three web UIs are opened inside the container's own netns (below); on the
  # host they are not ports at all.  Reachability from the management VLANs is
  # the UDM-Pro's job — ledger row L4 in docs/roadmap.md.
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
    config = { config, pkgs, lib, ... }:
    let
      # ── M12's hand-rolled derivations ───────────────────────────────────
      #
      # Four of M12's six additions have no nixpkgs package and no NixOS
      # module, surveyed against ernst's own pin on the session date rather
      # than trusted from a table (2026-08-26; the 2026-08-25 survey in
      # docs/roadmap.md still held).  Byparr is split out — see the M12 note
      # in the header — leaving three, in ./pkgs.
      #
      # callPackage from the CONTAINER's pkgs, not the host's: these end up in
      # the container's closure and should be built against the same nixpkgs
      # the rest of it is.
      #
      # Each derivation carries its own header explaining why it takes the
      # shape it does; the arguments here are only the ones with a choice in
      # them.
      umlautadaptarr = pkgs.callPackage ./pkgs/umlautadaptarr.nix { };
      cleanuparr     = pkgs.callPackage ./pkgs/cleanuparr.nix { };
      mediathekarr   = pkgs.callPackage ./pkgs/mediathekarr.nix { };

      # ── M13's hand-rolled derivations ───────────────────────────────────
      #
      # Two of M13's three additions have no nixpkgs package and no NixOS
      # module.  The third — Jellyseerr — HAS both, and the surprise there was
      # that it is now called something else: `services.jellyseerr` is a
      # mkRenamedOptionModule alias for `services.seerr`, and the package
      # attribute is `seerr`.  See the services.seerr block below.
      #
      # These two are NOT alike, and the difference is worth one line each
      # because it is the whole of M13's packaging risk:
      #
      #   janitorr   BUILT FROM SOURCE.  Upstream publishes no artifact at all
      #              — only an OCI image — so this is a real Gradle/Spring Boot
      #              build with a committed dependency lock.  Its header
      #              explains the four things that make that non-obvious.
      #   scraparr   A plain setuptools Python application whose six
      #              dependencies are all already in nixpkgs.  The easy one.
      janitorr = pkgs.callPackage ./pkgs/janitorr.nix { };
      scraparr = pkgs.callPackage ./pkgs/scraparr.nix { };

      # ── M14's hand-rolled derivations ───────────────────────────────────
      #
      # Three of M14's six additions land in this container without a nixpkgs
      # package or module.  Surveyed against ernst's own pin on the session
      # date (2026-08-28, nixpkgs fcb8fcd) — the 2026-08-25 survey in
      # docs/roadmap.md still held exactly.
      #
      # The three that DO have modules are lidarr and audiobookshelf (below)
      # and slskd (in the microvm guest).  The sixth, Storyteller, is not here
      # at all: it has no sane non-Docker build and takes the podman tier —
      # see machines/ernst/containers/storyteller.nix.
      #
      # These three are not alike, and one line each is worth it because the
      # spread is M14's whole packaging risk:
      #
      #   soularr    a SCRIPT with no build system at all.  Its own header
      #              explains why that makes it a stdenv derivation rather
      #              than buildPythonApplication, and why it runs from a timer.
      #   kapowarr   the release-artifact case docs/roadmap.md's packaging
      #              rule prefers: an upstream zip, unpacked, wrapped.
      #   questarr   the only REAL build in M14 — buildNpmPackage over a Vite
      #              frontend and a tsc server pass, because upstream publishes
      #              no release assets whatsoever.
      soularr  = pkgs.callPackage ./pkgs/soularr.nix { };
      kapowarr = pkgs.callPackage ./pkgs/kapowarr.nix { };
      questarr = pkgs.callPackage ./pkgs/questarr.nix { };
      # M17.  The release-artifact case again, and the cleanest one yet: a
      # single static Go binary out of an upstream tarball with checksums
      # and SBOMs.  See ./pkgs/bindery.nix.
      bindery  = pkgs.callPackage ./pkgs/bindery.nix { };
    in
    {
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
        ]
        + lib.concatMapStrings (port: ''
          iptables -A nixos-fw -p tcp -s ${monitoringAddr}/32 --dport ${toString port} -j nixos-fw-accept
        '') [
          scraparrPort
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
      # The services.
      ##########################################################################

      # Sonarr.  dataDir left at its default so the module keeps
      # StateDirectory=sonarr; /var/lib/sonarr is the bind mount.
      services.sonarr = {
        enable       = true;
        user         = "sonarr";
        group        = "media";     # PRIMARY group — PrivateUsers=true, see header
        openFirewall = false;       # explicit list above
        settings.server.port = sonarrPort;
      };

      services.radarr = {
        enable       = true;
        user         = "radarr";
        group        = "media";
        openFirewall = false;
        settings.server.port = radarrPort;
      };

      # RADARR'S PARENT DIRECTORY, and it is not optional — without it radarr
      # does not start at all.  Measured on ernst 2026-08-21, first deploy.
      #
      # Upstream declares exactly one tmpfiles rule,
      #   d /var/lib/radarr/.config/Radarr 0700 radarr media
      # and lets tmpfiles create the intermediate .config implicitly.  Implicit
      # parents are created ROOT-owned.  On a stock machine that is fine,
      # because /var/lib/radarr is root-owned too and the whole chain is
      # uniform — but here /var/lib/radarr is the bind mount, and the host
      # tmpfiles rule above makes it radarr-owned so the service can write to
      # it.  systemd-tmpfiles then refuses to descend:
      #
      #   Detected unsafe path transition /var/lib/radarr (owned by radarr)
      #   → /var/lib/radarr/.config (owned by root) during canonicalization
      #
      # That is its symlink-attack guard, and it is right to fire: a directory
      # owned by an unprivileged user leading into one owned by root is exactly
      # the shape an attacker wants.  systemd-tmpfiles-setup exits 73, the
      # Radarr directory is never created, and radarr dies on start with
      # "Access to the path '/var/lib/radarr/.config/Radarr' is denied" —
      # which reads like a mode problem on the leaf and is a problem two levels
      # up.
      #
      # Declaring .config explicitly with the same owner removes the transition.
      # Ordering does not matter: systemd-tmpfiles executes items sorted by
      # path, so the parent is handled before the child whatever file it came
      # from.
      #
      # SONARR NEEDS NO EQUIVALENT, and the reason is worth knowing rather than
      # inferring: its module ships no tmpfiles rule at all, so Sonarr creates
      # .config itself, at run time, as its own user.  It works by not going
      # through tmpfiles — not because its layout is different.
      systemd.tmpfiles.settings."05-radarr-config"."/var/lib/radarr/.config".d = {
        user  = "radarr";
        group = "media";
        mode  = "0700";
      };

      # Prowlarr.  dataDir left at the default: the module only wires its
      # bind-mount/tmpfiles machinery when dataDir differs from
      # /var/lib/prowlarr, and the packaged ExecStart hardcodes
      # `-data=/var/lib/prowlarr` regardless.  Our nspawn bind mount already
      # puts zdata there, so the custom-dataDir path would be a second
      # mechanism doing the same job.
      services.prowlarr = {
        enable       = true;
        openFirewall = false;
        settings.server.port = prowlarrPort;
      };

      # FlareSolverr — a headless Chromium that solves Cloudflare's JS
      # challenges on Prowlarr's behalf.
      #
      # WHY IT IS HERE AND NOT IN THE MICROVM, because architecture invariant
      # #1 says the opposite and the departure needs its evidence attached.
      #
      # The invariant says a service moves up a tier "when it starts talking to
      # the internet on its own behalf", and this one does it in the most
      # alarming way available: it renders deliberately hostile pages from
      # torrent indexers in a real browser engine. On that reading it belongs
      # in M3's guest, on its own kernel, behind the killswitch. That was the
      # first choice.
      #
      # It was measured before being built, and the measurement inverts it.
      # The same URL, 2026-08-21:
      #
      #   from ernst's home WAN   https://eztvx.to/  HTTP 200
      #     <title>EZTV - TV Torrents Online Series Download | Official</title>
      #     plus cdn-cgi/challenge-platform  → a SOLVABLE JS challenge
      #
      #   from the IVPN exit      https://eztvx.to/  HTTP 451
      #     <title>Unavailable For Legal Reasons</title>
      #                                      → a geo/legal REFUSAL
      #
      # There is nothing for FlareSolverr to solve in a 451. The exit is
      # Leaseweb NL and eztvx blocks the Netherlands outright, so the microvm
      # placement would take the target indexer from fixable to permanently
      # dead — the more correct architecture, minus the capability it exists
      # to provide. (kickass.torrentbay.st is 403 from both and is beyond
      # FlareSolverr either way.)
      #
      # WHAT MAKES THAT ACCEPTABLE rather than merely convenient: the boundary
      # that protects the library is the uid, not the container. FlareSolverr
      # keeps upstream's DynamicUser=true, so it runs as a transient uid with
      # ProtectSystem=strict, PrivateUsers, PrivateDevices and a
      # SystemCallFilter — and it is NOT in group media, so /srv/media's
      # 2770 root:media directories are closed to it. A Chromium compromise
      # would have to escape the sandbox AND escalate AND cross nspawn before
      # it reached anything this milestone cares about.
      #
      # DynamicUser IS RIGHT HERE, and that is not a contradiction of the
      # prowlarr block above. Prowlarr's problem was DynamicUser plus
      # PERSISTENT STATE on zdata: a transient uid owning a database. This has
      # RuntimeDirectory only — /run/flaresolverr, a tmpfs, thrown away on
      # every stop. Nothing to own, nothing to lose, so the trap cannot fire.
      #
      # REVISIT IF the IVPN exit ever moves out of the Netherlands: the
      # measurement above is what pins this decision, and it is a property of
      # the exit country, not of the design. Note the exit is shared with
      # qBittorrent, so changing it means regenerating the wg-qbittorrent vars.
      #
      # Prowlarr wiring is a UI step (Settings → Indexers → Indexer Proxies →
      # FlareSolverr, host http://127.0.0.1:8191, then tag the CF indexers).
      # It is not faked here, for the same reason the root folders are not.
      services.flaresolverr = {
        enable = true;
        port   = flaresolverrPort;

        # 127.0.0.1 only.  Upstream's openFirewall would open 8191 in this
        # container's netns, which would expose a remote-URL-fetching service
        # to the whole Services VLAN — an SSRF primitive with a web API in
        # front of it.  Prowlarr is in this same netns and needs no port open
        # at all.
        openFirewall = false;
      };

      ##########################################################################
      # M12 (c) — BAZARR.  Subtitles, both directions.
      #
      # The only one of M12's additions with an upstream module, and the module
      # is a thin one: it writes an ExecStart, a tmpfiles rule and a user, and
      # sets NO hardening directives at all.  Not a reduced set — none.  So the
      # `systemd.services.bazarr.serviceConfig` block further down is not a
      # tightening of upstream's choices, it is the whole of them, and its
      # before/after score is the largest movement in this milestone.
      #
      # `media` as the PRIMARY group is the one thing that must not be
      # "simplified" later: Bazarr writes .srt sidecars INTO the library, next
      # to the video files, in directories that are 2770 root:media.
      #
      # LANGUAGE PROFILES ARE A MANUAL STEP, and deliberately so.  M12 asks for
      # German and English "both directions" — German subtitles on English
      # content and English subtitles on German content — which is two profiles
      # plus per-series/per-movie assignment plus provider credentials.  All of
      # that lives in Bazarr's own database, and the argument the root folders
      # lost applies here unchanged: faking it from Nix would create a second
      # source of truth for state the application owns.  The PR body carries
      # the steps.
      services.bazarr = {
        enable       = true;
        listenPort   = bazarrPort;
        user         = "bazarr";
        group        = "media";     # PRIMARY group — see the header
        openFirewall = false;       # explicit list above
      };

      ##########################################################################
      # M12 (b) — UMLAUTADAPTARR.  The highest-value item in the milestone.
      #
      # ── WHY IT EXISTS ────────────────────────────────────────────────────
      #
      # German releases with umlauts are not imported correctly, are often not
      # FOUND at all (the *arrs search "o" for "ö"), and Sonarr/Radarr always
      # expect the ENGLISH TMDB/TVDB title — which breaks German productions
      # and translations outright.  The characteristic symptom in a Sonarr log
      # is "Found matching series/movie via grab history, but release was
      # matched to series by ID".  TRaSH's German quality-profile guide
      # recommends it by name, and the recyclarr German profiles added at the
      # bottom of this file are its other half: the profiles decide what is
      # wanted, this is what makes it findable.
      #
      # ── HOW IT WORKS, because it decides everything else ─────────────────
      #
      # It presents itself to the *arrs as an INDEXER, but it actually sits
      # BETWEEN them and the real indexer, rewriting searches and results and
      # renaming releases so the *arrs recognise them.  Two ports: 5005 is its
      # own HTTP API, 5006 is the proxy that Prowlarr's indexer definitions are
      # pointed at.
      #
      # ── IT DOES NOTHING FOR THIS FLEET'S INDEXERS.  MEASURED 2026-08-26 ──
      #
      # READ THIS BEFORE TRYING TO "FINISH WIRING IT UP".  M12 called this the
      # highest-value item in the milestone.  That judgement assumed an
      # indexer set this deployment does not have, and the service as deployed
      # is INERT — not misconfigured, not half-wired: architecturally unable to
      # help.  The evidence, in the order it was found:
      #
      # 1. ALL SIX PROWLARR INDEXERS ARE `Cardigann`.  EZTV, LimeTorrents,
      #    Nyaa.si, The Pirate Bay, TorrentDownload, YTS — every one of them a
      #    definition-driven HTML SCRAPER, all torrent protocol.  Cardigann's
      #    Site Link is a select populated from the bundled YAML definition, so
      #    the https → http edit the upstream README requires CANNOT BE MADE.
      #    That is the symptom people notice first.  It is not the cause.
      #
      # 2. BOTH INTEGRATION MODES CONVERGE ON THE SAME REQUIREMENT, and this
      #    is the cause.  Reading the source rather than the README:
      #
      #      HttpProxyService (port 5006) rewrites an intercepted request to
      #        http://localhost:5005/{apiKey}/{uri.Host}{uri.PathAndQuery}
      #      SearchController's routes are constrained on the NEWZNAB `t=`
      #        parameter — caps | movie | tvsearch | music | book | search
      #      UrlUtilities.BuildUrl then does
      #        new UriBuilder("https", domain)
      #
      #    So whichever mode is used, UmlautAdaptarr ends up fetching the
      #    indexer's own NEWZNAB/TORZNAB API over https and rewriting the XML
      #    it gets back.  THE TARGET MUST SPEAK NEWZNAB/TORZNAB AT ITS OWN
      #    DOMAIN.  A Cardigann tracker speaks HTML, and Prowlarr is what turns
      #    that into Torznab — inside Prowlarr, after the proxy hop.
      #
      # 3. SO THE INSTRUCTION WOULD HAVE BROKEN SEARCHES, NOT ENABLED THEM.  A
      #    Cardigann request carries no `t=` parameter, so no route matches and
      #    UmlautAdaptarr answers 404.  Tagging these indexers with the proxy
      #    would take six working indexers offline.  The Site Link dropdown
      #    being read-only is the only reason that did not happen.
      #
      # 4. THE NON-PROXY MODE IS NOT AN ESCAPE EITHER.  `IsValidDomain` demands
      #    a dotted host and the scheme is hardcoded to https, so
      #    `http://localhost:5005/_/localhost:9696/1/api` — pointing it at
      #    Prowlarr, whose Torznab really is XML over plain http — is rejected
      #    twice over.
      #
      # WHY IT IS STILL HERE.  It runs clean (NRestarts=0), and it does real
      # work that costs nothing: it syncs Sonarr's 139 series and resolves
      # German titles for 130 of them against the maintainer's API.  The day an
      # indexer that speaks Newznab or Torznab is added — a usenet provider, or
      # any tracker with a real API — it becomes useful with a UI change and no
      # deploy.  Removing it would mean re-deriving all of the above later.
      #
      # THE TRIGGER TO REVISIT IS AN INDEXER WITH AN API, not a Prowlarr
      # update.  This is the same shape as the Unpackerr finding one screen
      # down, and it has the same root: this stack is 100% torrent, 100%
      # Cardigann, with no usenet path at all.
      #
      # ── THE TRAP, IF THAT DAY COMES ──────────────────────────────────────
      #
      # For an indexer that DOES have an API, the README's rule applies and is
      # a genuine fails-by-succeeding: the indexer URL must change https → http
      # so this can intercept locally (the outbound leg stays https).  AN
      # INDEXER LEFT ON https WORKS FINE AND SILENTLY BYPASSES THIS ENTIRELY.
      # Configure it in PROWLARR, not per-arr — per-arr costs a speed penalty
      # on multi-indexer search.
      #
      # ── THE FORK: UmlautAdaptarr, NOT UmlautAdaptarrEX ───────────────────
      #
      # M12 asks for both to be evaluated and the choice argued.  Surveyed
      # 2026-08-26: PCJones/UmlautAdaptarr, C#, 303 stars, last pushed
      # 2026-08-10; xpsony/UmlautAdaptarrEX, TypeScript, 28 stars, last pushed
      # 2026-08-24.  Both are alive.
      #
      # The original wins on three counts, and "it is canonical" is not one of
      # them:
      #
      #   1. EX is a REWRITE, not a fork — different language, different
      #      codebase, one author, four weeks old in its current shape.  This
      #      component sits in the request path of every indexer search in the
      #      stack.  Its documented failure mode is already "works fine and
      #      does nothing", which is the worst possible property to combine
      #      with a young reimplementation nobody here can debug.
      #   2. TRaSH's German guide names the ORIGINAL.  The recyclarr German
      #      profiles in this file are transcribed from that guide, so the two
      #      halves of this milestone should be the two halves that guide
      #      describes.
      #   3. EX's advertised advantage is BROADER MULTI-LANGUAGE handling.
      #      This is a two-language household.  That is not a capability this
      #      deployment needs, so it buys nothing against the risk in (1).
      #
      # Revisit if the original goes quiet — not because EX gets newer.
      #
      # ── NO uid, AND THAT IS A DEPARTURE FROM THE ROADMAP ─────────────────
      #
      # docs/roadmap.md reserves uid 3010 for this service, "own group, no
      # media access — a proxy, same argument as prowlarr".  The access half
      # of that is kept exactly; the static uid is not, and M12's own rule is
      # what overturns it:
      #
      #   "a service with no persistent state has no reason to make that
      #    switch at all.  FlareSolverr keeps DynamicUser; Byparr should too."
      #
      # This service has no persistent state.  Verified against upstream
      # rather than assumed: zero SQLite references in the repository, caching
      # is IMemoryCache, and upstream's own docker-compose declares no volumes
      # at all.  Every scrap of its configuration arrives as an environment
      # variable, below.
      #
      # A static uid would therefore buy nothing and cost the six directives
      # DynamicUser silently implies — NoNewPrivileges, PrivateTmp,
      # ProtectSystem=strict, ProtectHome=read-only, RemoveIPC and
      # RestrictSUIDSGID — which is the Prowlarr trap in reverse, and the trap
      # M12's hardening section says to watch for.  So: DynamicUser, no media
      # group, nothing owned, nothing to lose.  uid 3010 stays reserved and
      # unused in machines/ernst/networking.nix, which says so.
      #
      # ── IT TALKS TO A THIRD-PARTY API, and that is stated not buried ─────
      #
      # appsettings.json ships Settings.UmlautAdaptarrApiHost =
      # https://umlautadaptarr.pcjones.de/api/v1, the maintainer's title
      # lookup service.  Against invariant #1 that is the same shape as
      # FlareSolverr and lands the same way: it is metadata traffic, not
      # tracker traffic; there is nothing here a killswitch protects; and the
      # microvm's Dutch exit would be no better a place for it.  It stays in
      # the nspawn tier.
      systemd.services.umlautadaptarr = {
        description = "UmlautAdaptarr — umlaut/German-title proxy for the *arrs";
        wantedBy    = [ "multi-user.target" ];

        # HARD startup dependency, and it is not advisory.  Measured
        # 2026-08-26: with no *arr reachable, UmlautAdaptarr logs
        #   The URL "http://.../api?apikey=[REDACTED]" is not reachable.
        #   Next attempt in 15 seconds...
        # and NEVER BINDS ITS PORTS.  It blocks in its own constructor until
        # an *arr answers.  That is good behaviour — it fails closed — but it
        # means ordering matters and that a restart policy is required rather
        # than optional.
        after = [ "sonarr.service" "radarr.service" "arr-api-keys.service" ];
        wants = [ "sonarr.service" "radarr.service" ];

        serviceConfig = {
          Type = "simple";

          # The two API keys, as environment variables, staged by
          # arr-api-keys.service below.  EnvironmentFile is read by PID 1
          # before privileges are dropped, so a 0600 root-owned file under
          # /run is exactly right and the DynamicUser never sees it.
          EnvironmentFile = "${arrSecretsDir}/umlautadaptarr.env";

          ExecStart = "${lib.getExe umlautadaptarr}";

          Restart    = "on-failure";
          RestartSec = "30s";

          # See the long note above.  Upstream ships no unit at all, so every
          # directive here is ours.  DynamicUser buys the six implied ones;
          # the rest is the servarr set this file already applies to prowlarr.
          DynamicUser      = true;
          RuntimeDirectory = "umlautadaptarr";

          CapabilityBoundingSet   = "";
          PrivateDevices          = true;
          PrivateUsers            = true;
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

          # NOT MemoryDenyWriteExecute — .NET, same JIT rejection this file
          # already records for sonarr/radarr/prowlarr and jellyfin.nix
          # records for Jellyfin.
          SystemCallFilter = arrSyscallFilter;
        };
      };

      ##########################################################################
      # M12 (d) — CLEANUPARR.
      #
      # ── IT RETIRES THREE THINGS, so they are not added ───────────────────
      #
      # DECLUTTARR, HUNTARR and CHECKRR.  Recorded here so that a later session
      # "discovers" one of them and finds the answer in the same file as the
      # thing that replaced it.
      #
      # ── WHY IT IS WORTH A uid ────────────────────────────────────────────
      #
      # Beyond stalled / blocked / malicious cleanup — it exists because *.lnk
      # and *.zipx files were getting stuck in *arr queues — it does
      # missing-content search, cutoff-unmet search, and custom-format score
      # upgrade search with score tracking.
      #
      # The part that earns it a place in THIS container: it removes downloads
      # that are ORPHANED, HAVE NO HARDLINKS, or are no longer referenced by
      # the *arrs.  That turns M4's link-count invariant from something proven
      # once with `stat` into something a service watches continuously, which
      # is a genuine upgrade to the property the whole stack rests on.
      #
      # ── CONFIGURE CONSERVATIVELY ON THE FIRST DEPLOY ─────────────────────
      #
      # A cleaner that deletes is a cleaner that can delete the wrong thing,
      # and this one reasons about hardlink counts on a tree whose hardlink
      # correctness is the entire point of M3 and M4.  Its configuration is a
      # SQLite database driven from its web UI — there is nothing to set here
      # — so "conservatively" is a manual step and the PR body spells it out:
      # every cleaner starts disabled, the download cleaner's unlinked/orphan
      # handling goes on LAST and only after the *arr Recycle Bin is set.
      systemd.services.cleanuparr = {
        description = "Cleanuparr — stalled/blocked/orphaned download cleanup";
        wantedBy    = [ "multi-user.target" ];
        after       = [ "sonarr.service" "radarr.service" ];
        wants       = [ "sonarr.service" "radarr.service" ];

        environment = {
          PORT = toString cleanuparrPort;

          # CLEANUPARR_CONFIG_PATH is the NON-DOCKER override, and it is the
          # only way to move the config directory off its built-in default.
          # /var/lib/cleanuparr is the zdata bind mount.
          CLEANUPARR_CONFIG_PATH = "/var/lib/cleanuparr";
        };

        serviceConfig = {
          Type      = "simple";
          User      = "cleanuparr";
          Group     = "media";
          ExecStart = "${lib.getExe cleanuparr}";
          Restart   = "on-failure";
          RestartSec = "30s";

          # Group-writable output, for the reason the sonarr/radarr UMask note
          # at the bottom of this file gives at length: 0022 would make
          # anything this service creates writable by exactly one uid, on a
          # tree whose whole point is that the `media` group can manage it.
          UMask = "0002";

          # Static uid with persistent state — the prowlarr shape, not the
          # flaresolverr one — so every directive DynamicUser would have
          # implied is restated explicitly.  This is the Prowlarr trap in
          # reverse and it is the reason this block is long.
          NoNewPrivileges  = true;
          PrivateTmp       = true;
          ProtectSystem    = "strict";
          ProtectHome      = true;
          RemoveIPC        = true;
          RestrictSUIDSGID = true;

          # It DELETES from the library and the download tree; that is the job.
          ReadWritePaths = [ "/srv/media" "/var/lib/cleanuparr" ];

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

          # NOT PrivateUsers.  sonarr and radarr carry it and it is why `media`
          # has to be their primary group; here it would buy nothing and cost
          # the same footgun, because this service's access to /srv/media is
          # ENTIRELY its group membership — it owns none of those files.
        };
      };

      ##########################################################################
      # M12 (f) — MEDIATHEKARR.  Two processes, not one.
      #
      # ARD / ZDF Mediathek as a Prowlarr indexer.  It answers a stated
      # complaint: the MediathekViewer Jellyfin plugin is poor.
      #
      # ── UPSTREAM SHIPS TWO PROCESSES AND ONLY DOCUMENTS ONE ──────────────
      #
      #   mediathekarr-downloader  5007   SABnzbd shim + the setup WIZARD +
      #                                   a full Newznab endpoint.  THIS IS THE
      #                                   ONE EVERYTHING IS POINTED AT.
      #   mediathekarr-indexer     5008   Newznab shim, plus the ruleset
      #                                   background fetcher.  Nothing points
      #                                   at it.  See below.
      #
      # CORRECTED AFTER THE DEPLOY, 2026-08-26.  This block used to say the
      # indexer on 5008 "is what Prowlarr is pointed at".  It is not.  The
      # setup wizard — which runs inside the DOWNLOADER — registers the
      # Prowlarr indexer against `http://localhost:5007`, and that works,
      # because 5007 serves the Newznab API as well.  Verified by asking both
      # ports the same question:
      #
      #   curl 'http://localhost:5007/api?t=tvsearch&q=Tatort'
      #   curl 'http://localhost:5008/api?t=tvsearch&q=Tatort'
      #
      # Both returned `total="3012"` and byte-identical, correctly-formatted
      # release titles.  So the downloader is self-sufficient and 5008 is NOT
      # in the request path of anything.
      #
      # BOTH ARE KEPT ANYWAY, deliberately.  Upstream's docker_start.sh runs
      # both, and the two are not identical: only the INDEXER registers
      # RulesetBackgroundService, which refreshes the per-show naming rules
      # from mediathekarr.pcjones.de on a timer.  The downloader's journal
      # shows no ruleset activity at all.  One matching search result is not
      # evidence that ruleset upkeep is irrelevant — and inferring that from a
      # single query is exactly the species of mistake this milestone has
      # already made four times.  It costs ~90 MB.
      #
      # TO REVISIT: if the naming ever drifts, or if the container needs the
      # memory, the question to answer FIRST is whether 5007 gets its rulesets
      # some other way.  Until then, run what upstream runs.
      #
      # Upstream's docker-compose publishes only 5007 and its README mentions
      # only 5007, so packaging just the indexer is the easy mistake — and it
      # would produce searches that return results nothing can ever download.
      # ./pkgs/mediathekarr.nix has the full account.
      #
      # ── WHY IT NEEDS A MEDIA uid WHEN PROWLARR DOES NOT ──────────────────
      #
      # Prowlarr's "no media access at all" argument does NOT transfer, and
      # assuming it did would produce a service that fails on its first
      # download.  This one really downloads: the SABnzbd half fetches video
      # and subtitles over plain HTTP from the Mediatheken, then remuxes with
      # ffmpeg and mkvmerge.  It writes into /srv/media/torrents/mediathek,
      # inside the hardlink domain, so the *arrs import from it exactly as they
      # import from qBittorrent's output.
      #
      # ── INVARIANT #1, ARGUED RATHER THAN WAVED THROUGH ───────────────────
      #
      # It talks to the internet on its own behalf — MediathekViewWeb, the
      # maintainer's ruleset API, and thetvdb for metadata — so the invariant's
      # "move it up a tier" test applies and has to be answered.  The answer is
      # that it stays here, in FlareSolverr's shape:
      #
      #   - public-broadcaster HTTP, not tracker traffic;
      #   - no killswitch value: there is nothing here a VPN protects;
      #   - and THE EXIT-COUNTRY PROBLEM RUNS THE OTHER WAY.  These are German
      #     services, best reached from a German IP.  The microvm tier's IVPN
      #     exit was re-measured for this milestone on 2026-08-26 and is still
      #     Leaseweb NL (95.211.172.88) — the wrong side of exactly the coin
      #     M4 measured at HTTP 451.  Moving this to the "more correct" tier
      #     would degrade or break the capability it exists to provide.
      #
      # NOTE FOR M8: this is the milestone that changes whether M8 needs to
      # exist at all.  See the M8 amendment in docs/roadmap.md.
      systemd.services.mediathekarr-indexer = {
        description = "MediathekArr indexer — ARD/ZDF Mediathek as Newznab";
        wantedBy    = [ "multi-user.target" ];
        after       = [ "network-online.target" ];
        wants       = [ "network-online.target" ];

        serviceConfig = {
          Type       = "simple";
          User       = "mediathekarr";
          Group      = "media";
          ExecStart  = "${lib.getExe mediathekarr.indexer}";
          Restart    = "on-failure";
          RestartSec = "30s";

          # The indexer half NEVER TOUCHES A FILE.  It is in group media only
          # because it shares a uid with the downloader half, and it is given
          # no writable path at all — ProtectSystem=strict with no
          # ReadWritePaths means the entire filesystem is read-only to it.
          NoNewPrivileges  = true;
          PrivateTmp       = true;
          ProtectSystem    = "strict";
          ProtectHome      = true;
          RemoveIPC        = true;
          RestrictSUIDSGID = true;

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
        };
      };

      systemd.services.mediathekarr-downloader = {
        description = "MediathekArr downloader — SABnzbd shim and setup wizard";
        wantedBy    = [ "multi-user.target" ];
        after       = [ "network-online.target" ];
        wants       = [ "network-online.target" ];

        environment = {
          # Config, on zdata.  Everything the wizard writes lands here.
          CONFIG_PATH = "/var/lib/mediathekarr";

          # ── THE PATHS ARE THE SAME STRING EVERYWHERE, on purpose ────────
          #
          # This is the identical-path rule from the header, applied to a
          # second download source.  The downloader reports a completed item
          # at /srv/media/torrents/mediathek/complete/<cat>/<title>.mkv;
          # Sonarr looks for it at the same string; both are the same inode,
          # in the same dataset, so the import is a HARDLINK and no *arr
          # Remote Path Mapping is needed.  Change one of these and every
          # Mediathek import silently becomes a copy — or an error that reads
          # like a permissions problem.
          DOWNLOAD_INCOMPLETE_PATH = "/srv/media/torrents/mediathek/incomplete";
          DOWNLOAD_COMPLETE_PATH   = "/srv/media/torrents/mediathek/complete";

          # The SABnzbd categories the *arrs will see.  tv and movies match
          # the two libraries this stack actually has.
          CATEGORIES = "tv,movies";
        };

        serviceConfig = {
          Type       = "simple";
          User       = "mediathekarr";
          Group      = "media";
          ExecStart  = "${lib.getExe mediathekarr.downloader}";
          Restart    = "on-failure";
          RestartSec = "30s";

          # Group-writable, same argument as sonarr/radarr/cleanuparr: what
          # this writes is imported, moved and eventually deleted by other
          # members of `media`.
          UMask = "0002";

          NoNewPrivileges  = true;
          PrivateTmp       = true;
          ProtectSystem    = "strict";
          ProtectHome      = true;
          RemoveIPC        = true;
          RestrictSUIDSGID = true;

          ReadWritePaths = [
            "/srv/media/torrents/mediathek"
            "/var/lib/mediathekarr"
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

          # ffmpeg and mkvmerge are FORKED, so the filter has to permit it —
          # @system-service already does.  What it must NOT gain is @privileged
          # or @mount, and it does not.
          SystemCallFilter        = arrSyscallFilter;
        };
      };

      ##########################################################################
      # M12 (e) — UNPACKERR IS NOT HERE, and that is a measured decision.
      #
      # M12 makes it conditional on there actually being archive-delivered
      # releases to unpack.  Measured on ernst, 2026-08-26:
      #
      #   sonarr, last 50 grabs      50/50 protocol=torrent, client qBittorrent
      #   radarr, all 30 in history  30/30 protocol=torrent, client qBittorrent
      #   download clients configured   ONE, qBittorrent.  No usenet client
      #                                 exists in either application.
      #   archives under /srv/media/torrents
      #                              0, out of 986 files
      #                              (*.rar, *.r0[0-9], *.zip, *.zipx, *.7z)
      #   archives under /srv/media/library
      #                              0
      #
      # There is nothing for it to do.  SKIPPED, recorded in docs/roadmap.md so
      # it is not re-litigated in six months, and uid 3013 stays reserved and
      # unused.
      #
      # THE TRIGGER TO REVISIT IS A USENET DOWNLOAD CLIENT, not a hunch: the
      # whole reason this stack sees no archives is that it has no usenet path.
      # Note pkgs.unpackerr exists (0.15.2) and needs a unit, not a derivation.

      ##########################################################################
      # M13 — JELLYSEERR.  The request side of the loop.
      #
      # ── THE MODULE WAS RENAMED, AND THE OPTION YOU WANT IS `services.seerr` ─
      #
      # docs/roadmap.md's M13 prompt says "jellyseerr HAS a module", surveyed
      # 2026-08-25.  It still does, but in ernst's own pin it is reached under a
      # different name: nixos/modules/services/misc/seerr.nix declares
      # `services.seerr` and imports
      #
      #   (lib.mkRenamedOptionModule [ "services" "jellyseerr" ] [ "services" "seerr" ])
      #
      # so `services.jellyseerr` still evaluates — it just emits a rename
      # warning and sets something else.  The package attribute moved too:
      # `seerr`, version 3.2.0.  This file uses the new names for both, so the
      # build produces no rename warnings and a reader grepping for "seerr"
      # finds everything.
      #
      # The 26.05 rename also moved the STATE PATH.  That is handled at the
      # bind mount, where the two candidate paths are written out.
      #
      # ── INTERNAL SCOPE ONLY.  THE EXTERNAL HALF IS M16 ─────────────────────
      #
      # lgo has decided Jellyseerr must eventually be reachable FROM THE
      # INTERNET.  THAT IS M16 AND IS DELIBERATELY NOT IMPLEMENTED HERE.
      # Nothing in this file, in containers/traefik.nix, or in the UDM-Pro
      # policy changed to admit a WAN source; M13's router rides the existing
      # permanent "Allow Traefik" rule (LAN + IoT → traefik:443) and no new
      # gateway rule was created.
      #
      # The split is the same reasoning that gave M2b its own milestone: the
      # household proves the request workflow first, and the ingress boundary
      # then gets reviewed AS an ingress change rather than as one line in a
      # library-cleanup milestone.
      #
      # ── IT DOES NOT GO BEHIND AUTHELIA, AND THAT IS DELIBERATE ─────────────
      #
      # Authelia exists (M7) and every other browser-facing service in this
      # container sits behind it.  Jellyseerr does not, for two reasons:
      #
      #   1. M16 decides the external auth posture.  Putting it behind
      #      forward-auth now and reworking it there is two changes to one
      #      router.
      #   2. IT IS NOT AN ADMIN SERVICE.  The others in this container are
      #      operator tools; this is the thing the household opens to ask for a
      #      film.  Its posture is its OWN Jellyfin-account login — the
      #      credential everyone here already has — which is also what makes
      #      "who requested this" meaningful inside Jellyseerr rather than
      #      collapsing to one Authelia identity.
      #
      # This is the same call containers/traefik.nix makes for Jellyfin itself,
      # and its header states the general form of the argument.
      services.seerr = {
        enable = true;
        port   = jellyseerrPort;

        # Explicit list above, as everywhere in this file.  The module's
        # openFirewall would set allowedTCPPorts, which is the unconditional
        # mechanism M5 emptied on purpose.
        openFirewall = false;
      };

      # ── THE PROWLARR TRAP, IN ITS THIRD FORM ──────────────────────────────
      #
      # The upstream unit runs DynamicUser = true.  A static uid is needed
      # here for the reason the file header gives — nspawn does not remap ids,
      # so the number chosen inside is a number on zdata, and /srv/state has to
      # be owned by something nameable.
      #
      # M13's brief warns that switching DynamicUser off silently loses six
      # directives it implied: NoNewPrivileges, PrivateTmp, ProtectSystem=strict,
      # ProtectHome=read-only, RemoveIPC and RestrictSUIDSGID.
      #
      # CHECKED RATHER THAN ASSUMED, and the answer is interesting: the seerr
      # module ALREADY sets all six explicitly, so unlike Prowlarr nothing is
      # actually lost here.  They are restated below anyway — not out of
      # ceremony, but because this file must not depend on an upstream module
      # continuing to be generous.  ProtectHome is tightened from the implied
      # `read-only` to `true` (which the module also does).
      #
      # What the module does NOT set, and what this block therefore adds, is
      # the second tier: CapabilityBoundingSet, RestrictAddressFamilies,
      # RestrictNamespaces, LockPersonality, SystemCallFilter,
      # SystemCallArchitectures, ProtectProc and UMask.
      systemd.services.seerr.serviceConfig = {
        DynamicUser = lib.mkForce false;
        User        = "jellyseerr";
        Group       = "jellyseerr";

        # The six DynamicUser implied.  Restated, per the paragraph above.
        NoNewPrivileges  = true;
        PrivateTmp       = true;
        ProtectSystem    = "strict";
        ProtectHome      = true;
        RemoveIPC        = true;
        RestrictSUIDSGID = true;

        # StateDirectory= already grants this, but naming it keeps the set of
        # writable paths readable in one place.
        ReadWritePaths = [ "/var/lib/seerr" ];

        # 0027, NOT 0002 — and this is the one place in this file where the
        # group-writable default is wrong.
        #
        # sonarr, radarr, bazarr, cleanuparr and mediathekarr all use 0002
        # because their output lands in /srv/media, a tree whose whole point is
        # that the `media` group can manage it.  Jellyseerr writes only its own
        # state directory, holds API keys for every *arr in that directory, and
        # is in no shared group at all — so group-writable buys nothing and
        # widens a file full of credentials.
        UMask = "0027";

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
      };

      ##########################################################################
      # M13 — JANITORR.  The reaping side of the loop.
      #
      # ── WHAT IT IS NOT ────────────────────────────────────────────────────
      #
      # IT DOES NOT DELETE AFTER WATCHING.  Someone will expect it to, because
      # that is what "media lifecycle" sounds like, and M13's brief asks for
      # this to be written into the file header rather than discovered.
      #
      # What it actually does is DISK-SPACE-AWARE EXPIRY: each threshold in
      # `movie-expiration` / `season-expiration` maps a percentage of FREE DISK
      # to an age, and nothing is deleted at all until free space falls below
      # the highest threshold named.  On a pool with room, Janitorr does
      # nothing, forever, which is the intended resting state.
      #
      # IT ONLY SEES MEDIA THE *ARRS DOWNLOADED.  It reasons entirely through
      # Sonarr's and Radarr's APIs, so anything imported by hand — and anything
      # arriving through MediathekArr's own path — is invisible to it.  That is
      # a real gap on this host, not a hypothetical one: M12 added MediathekArr
      # specifically to pull ARD/ZDF content in.
      #
      # ── IT HAS NO WEB UI.  VERIFIED, NOT ASSUMED ──────────────────────────
      #
      # At v2.2.0 the source tree contains zero @RestController and zero
      # @Controller classes and ships no static resources; upstream's README
      # says "You don't have to publish ANY ports on the host machine."
      #
      # It nonetheless BINDS one, because spring-boot-webmvc is on its
      # classpath and Spring Boot starts Tomcat regardless.  Left alone that is
      # 0.0.0.0:8080 — inside this netns, that is the veth, on VLAN 90.  So the
      # configuration below pins the port to 8978 and the ADDRESS to 127.0.0.1,
      # and the firewall list does not name it.  Two independent mechanisms,
      # because the trap that produced this note (M12's 0.0.0.0-binding
      # helpers) was found by measurement rather than by reading a manual.
      #
      # ── DRY-RUN IS ON, AND THE FIRST DEPLOY KEEPS IT ──────────────────────
      #
      # `application.dry-run: true` below.  M13 requires the first deploy to
      # ship it that way and requires the PR body to carry what Janitorr WOULD
      # have deleted, read out of the journal, as the deliverable.
      #
      # TURNING IT OFF IS A SEPARATE, DELIBERATE COMMIT.  Alongside it, the
      # *arr Recycle Bin must be configured — M13 asks for two independent
      # safety nets on the first run of a deleting service pointed at 47 TB,
      # and that one is a manual step in Sonarr's and Radarr's own settings.
      systemd.services.janitorr = {
        description = "Janitorr — disk-space-aware media expiry across the *arr stack";
        wantedBy    = [ "multi-user.target" ];
        after       = [ "sonarr.service" "radarr.service" "seerr.service" "janitorr-config.service" ];
        wants       = [ "sonarr.service" "radarr.service" "seerr.service" ];
        requires    = [ "janitorr-config.service" ];

        environment = {
          # Spring reads this as an additional config location.  `optional:` is
          # NOT used: the config renderer is a hard `requires` dependency, so
          # if the file is missing something has already failed and Janitorr
          # starting with framework defaults (every client disabled, and a
          # property-binding failure) helps nobody.
          SPRING_CONFIG_ADDITIONAL_LOCATION = "/run/janitorr/application.yml";

          # 256 MB is upstream's own recommendation, and it is not arbitrary:
          # the JVM sizes its heap from the container/cgroup limit, and
          # upstream reports 200 MB as the floor at which it still starts.
          # MemoryMax below enforces the same number from systemd's side so the
          # two agree.
          JAVA_TOOL_OPTIONS = "-XX:+UseSerialGC -Xss512k";
        };

        serviceConfig = {
          Type      = "simple";
          User      = "janitorr";
          Group     = "media";
          ExecStart = "${lib.getExe janitorr}";
          Restart   = "on-failure";
          RestartSec = "60s";

          # See the JAVA_TOOL_OPTIONS note.  A hard cap rather than MemoryHigh:
          # this is a background reaper sharing a host with Jellyfin
          # transcoding and Ollama, and a JVM that grows without bound is
          # exactly the neighbour that turns a busy evening into an OOM.
          MemoryMax = "512M";

          # Group-writable, like every other service here that writes into
          # /srv/media: the "Leaving Soon" tree has to be readable by Jellyfin
          # (uid 964, group media) and removable by Janitorr on the next run.
          UMask = "0002";

          # Static uid with persistent state, so every directive DynamicUser
          # would have implied is restated — the Prowlarr trap in reverse, the
          # same shape as the cleanuparr block above.
          NoNewPrivileges  = true;
          PrivateTmp       = true;
          ProtectSystem    = "strict";
          ProtectHome      = true;
          RemoveIPC        = true;
          RestrictSUIDSGID = true;

          # It deletes from the library and builds the Leaving Soon tree.
          ReadWritePaths = [ "/srv/media" "/var/lib/janitorr" ];

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

          # NO SystemCallFilter, and this is the one deliberate gap in the
          # hardening of this unit.
          #
          # A JVM needs @privileged-adjacent calls that the other services here
          # do not — membarrier and the perf/JIT paths in particular — and a
          # filter that kills the runtime at an unpredictable moment during
          # class loading is worse than no filter: it presents as a service
          # that starts sometimes.  Everything the filter would have bought is
          # bought instead by an empty CapabilityBoundingSet, NoNewPrivileges
          # and the Protect*/Restrict* set above.
          #
          # If this is revisited, `SystemCallFilter = [ "@system-service" ]`
          # WITHOUT the "~@privileged" subtraction is the version to test first.
        };
      };

      # ── Janitorr's configuration, rendered at start from staged secrets ────
      #
      # A separate oneshot rather than a Nix-rendered file in the store,
      # because application.yml has to contain FOUR API KEYS AND A PASSWORD and
      # /nix/store is world-readable.
      #
      # It reads from three sources, and the spread is the point:
      #
      #   sonarr, radarr    arr-api-keys, which extracts them from each
      #                     application's OWN config.xml.  One source of truth;
      #                     survives a key rotation in the UI with no deploy.
      #   jellyseerr        its own settings.json, for the same reason.  The
      #                     key is generated by Jellyseerr on first run.
      #   jellyfin          a clan var with prompts, because its key lives in a
      #                     database and it additionally needs a real user
      #                     account.  See the generator on the host side.
      #
      # DEGRADES RATHER THAN FAILS when a source is absent, and each
      # degradation is chosen so that dry-run still produces its listing:
      #
      #   no jellyseerr key   the jellyseerr client is written `enabled: false`
      #   no jellyfin creds   the jellyfin client is written `enabled: false`
      #
      # A missing SONARR OR RADARR key is fatal, correctly: those are the
      # services Janitorr reasons about, and a Janitorr with neither has
      # nothing to say.
      systemd.services.janitorr-config = {
        description = "Render Janitorr's application.yml from staged credentials";
        after      = [ "arr-api-keys.service" "seerr.service" ];
        requires   = [ "arr-api-keys.service" ];
        before     = [ "janitorr.service" ];
        serviceConfig = {
          Type                     = "oneshot";
          RemainAfterExit          = false;
          RuntimeDirectory         = "janitorr";
          RuntimeDirectoryMode     = "0750";
          RuntimeDirectoryPreserve = "yes";

          # NO User=, so this runs as root — it has to, to read other users'
          # 0700 directories.  Group=media is what makes the RuntimeDirectory
          # come out root:media 0750 WITHOUT a chown.
          #
          # systemd takes RuntimeDirectory ownership from the unit's own
          # User=/Group=, which is the mechanism the fictional
          # `RuntimeDirectoryGroup=` was reaching for.  Setting the real
          # directive gets the same result for free.
          #
          # THE FIRST FIX FOR THIS WAS A `chown` IN THE SCRIPT AND IT CRASHED:
          #
          #   janitorr-render-config: line 10: 358 Bad system call (core dumped)
          #     .../coreutils-9.11/bin/chown root:media /run/janitorr
          #   janitorr-config.service: Main process exited, status=159/n/a
          #
          # 159 is 128+31, i.e. SIGSYS — killed by this unit's own
          # SystemCallFilter.  `~@privileged` subtracts the @chown set, so
          # chown(2) is not merely denied, the process is shot.  Group= avoids
          # the syscall entirely rather than widening the filter to permit it,
          # which is the better of the two fixes: nothing here needs to change
          # the ownership of anything.
          #
          # Measured on ernst 2026-08-26, on the deploy that shipped the chown.
          Group = "media";

          # THE DIRECTORY'S GROUP IS SET IN THE SCRIPT, NOT HERE, AND THAT IS
          # NOT A STYLE CHOICE.
          #
          # The obvious spelling is `RuntimeDirectoryUser` /
          # `RuntimeDirectoryGroup`.  THOSE DIRECTIVES DO NOT EXIST.  systemd
          # has RuntimeDirectoryMode and RuntimeDirectoryPreserve and takes the
          # OWNERSHIP from the unit's own User=/Group=; the two invented names
          # are accepted by the NixOS module, written into the unit file, and
          # then dropped by systemd with
          #
          #   Unknown key 'RuntimeDirectoryGroup' in section [Service], ignoring
          #
          # — a warning in the journal and nothing else.  Caught here with
          # `systemd-analyze verify` before deploying, not on ernst.
          #
          # This unit runs as ROOT (it has to; it reads other users' 0700
          # directories), so without the chown below /run/janitorr would be
          # root:root 0750 — and a 0640 root:media file inside a directory the
          # media group cannot TRAVERSE is unreadable.  That is precisely the
          # bug microvms/wg-qbittorrent.nix documents in its staging unit:
          # "Group needs x on the directory, not just r on the file."
          #
          # CAP_CHOWN is in the bounding set above for exactly this one call.
          UMask = "0027";

          # Same posture as arr-api-keys, and for the same reason: this unit
          # handles credentials and has no business having a network stack.
          #
          # CAP_DAC_READ_SEARCH for the same reason too — sonarr's staged key
          # and Jellyseerr's settings.json both sit under directories owned by
          # someone else.  NOT CAP_DAC_OVERRIDE: read and traverse only, so
          # this unit cannot write over anything it can see.
          PrivateNetwork          = true;
          IPAddressDeny           = "any";
          # CAP_DAC_READ_SEARCH only.  CAP_CHOWN was here for the chown that
          # the Group= note above removed; it went with it.
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

          ExecStart = pkgs.writeShellScript "janitorr-render-config" ''
            set -euo pipefail

            out=/run/janitorr/application.yml

            # No chown here — see the Group= note in this unit's serviceConfig.
            # systemd already created /run/janitorr as root:media 0750, and the
            # file inherits gid media from this process's egid, so UMask=0027
            # lands it at root:media 0640 with nothing to adjust.

            # Assign, then test — the shape PR #84 got wrong and arr-api-keys
            # documents at length.  A command substitution that fails inside
            # an argument does not trip `set -e`, so building the file in one
            # step would turn an unreadable key into an EMPTY key and a 401
            # with nothing in the log to explain it.
            sonarr_key=$(${pkgs.coreutils}/bin/cat ${arrSecretsDir}/sonarr-api-key)
            radarr_key=$(${pkgs.coreutils}/bin/cat ${arrSecretsDir}/radarr-api-key)
            if [ -z "$sonarr_key" ] || [ -z "$radarr_key" ]; then
              echo "janitorr: sonarr/radarr API key is empty — has arr-api-keys run?" >&2
              exit 1
            fi

            # Jellyseerr's key comes from arr-api-keys, which extracts it from
            # Jellyseerr's own settings.json.
            #
            # M13 originally read settings.json directly here.  It now goes
            # through the stager for the reason M12 gave when it renamed that
            # unit: two consumers reading the same application's config file is
            # one extraction too many, and the stager is already a hard
            # dependency of this unit.  Still degrades rather than fails —
            # Janitorr in dry-run is useful without Jellyseerr.
            seerr_key=""
            if [ -r ${arrSecretsDir}/jellyseerr-api-key ]; then
              seerr_key=$(${pkgs.coreutils}/bin/cat ${arrSecretsDir}/jellyseerr-api-key)
            fi
            seerr_enabled=true
            if [ -z "$seerr_key" ]; then
              seerr_enabled=false
              echo "janitorr: no Jellyseerr API key yet — has its first-run wizard been completed?" >&2
            fi

            # Jellyfin's three come from the clan var staged on the host.
            # Absent until `clan vars generate ernst` has been run and the
            # in-Jellyfin account created; same degradation.
            jf_key=""; jf_user=""; jf_pass=""
            if [ -r ${janitorrSecretsDir}/jellyfin.env ]; then
              # shellcheck disable=SC1091
              . ${janitorrSecretsDir}/jellyfin.env
              jf_key="''${JELLYFIN_API_KEY:-}"
              jf_user="''${JELLYFIN_USERNAME:-}"
              jf_pass="''${JELLYFIN_PASSWORD:-}"
            fi
            jf_enabled=true
            if [ -z "$jf_key" ] || [ -z "$jf_user" ] || [ -z "$jf_pass" ]; then
              jf_enabled=false
              echo "janitorr: no Jellyfin credentials — Leaving Soon collections will not be built" >&2
            fi

            ${pkgs.coreutils}/bin/rm -f "$out"
            ${pkgs.coreutils}/bin/cat > "$out" <<EOF
            # GENERATED by janitorr-config.service.  Do not edit — it is
            # rewritten on every start of janitorr.service.  The declarative
            # source is machines/ernst/containers/arr.nix.
            server:
              # See the "IT HAS NO WEB UI" note in arr.nix.  Loopback, and not
              # in the firewall list.
              port: ${toString janitorrPort}
              address: 127.0.0.1

            logging:
              level:
                # DEBUG while dry-running, INFO once live — see the
                # janitorrDryRun binding at the top of arr.nix for why these
                # two settings are deliberately welded together.
                com.github.schaka: ${if janitorrDryRun then "DEBUG" else "INFO"}
              # NO `file:` key.  Upstream's template writes /logs/janitorr.log;
              # this runs under systemd, so stdout goes to the journal and a
              # second copy on disk is one more thing to rotate and to persist.

            file-system:
              access: true
              # Skip deletion of anything still seeding.  ON, deliberately: the
              # download client is one layer-2 hop away in M3's VPN microvm and
              # this check is what keeps a reap from cutting a live torrent.
              validate-seeding: true
              leaving-soon-dir: "/srv/media/leaving-soon"
              media-server-leaving-soon-dir: "/srv/media/leaving-soon"
              from-scratch: true
              # NOT "/".  The root filesystem here is the container's, which
              # has nothing to do with the pool Janitorr is reaping.  Pointing
              # it at / would read zroot's free space and make every expiry
              # threshold meaningless.
              free-space-check-dir: "/srv/media"

            application:
              dry-run: ${if janitorrDryRun then "true" else "false"}
              run-once: false
              whole-tv-show: false
              whole-show-seeding-check: false
              leaving-soon: 14d
              leaving-soon-threshold-offset-percent: 5
              exclusion-tags:
                - "janitorr_keep"

              media-deletion:
                enabled: true
                movie-expiration:
                  5: 180d
                  10: 365d
                season-expiration:
                  5: 180d
                  10: 365d

              # OFF on the first deploy.  Both of these act on *arr TAGS, and
              # no title in this library carries one yet — so enabling them
              # would either do nothing or, worse, do something the moment a
              # tag is added for an unrelated reason.
              tag-based-deletion:
                enabled: false
                minimum-free-disk-percent: 100
                schedules: []

              episode-deletion:
                enabled: false

            clients:
              default:
                connect-timeout: 60s
                read-timeout: 60s
                level: NONE

              # localhost throughout: all of this shares one netns, which is
              # the same payoff the Prowlarr wiring gets — no port opened,
              # nothing to firewall.
              sonarr:
                enabled: true
                url: "http://localhost:${toString sonarrPort}"
                api-key: "$sonarr_key"
                delete-empty-shows: true
              radarr:
                enabled: true
                url: "http://localhost:${toString radarrPort}"
                api-key: "$radarr_key"
              jellyfin:
                enabled: $jf_enabled
                url: "http://${jellyfinAddr}:${toString jellyfinPort}"
                api-key: "$jf_key"
                username: "$jf_user"
                password: "$jf_pass"
                # Jellyfin is a DIFFERENT container (M2b, 10.0.90.10), so this
                # one is not localhost — it is the same layer-2 hop Traefik
                # takes.  Its firewall accepts only Traefik on 8096, so this
                # needs a rule there; see containers/jellyfin.nix.
                delete: true
                exclude-favorited: true
                leaving-soon-tv: "Shows (Leaving Soon)"
                leaving-soon-movies: "Movies (Leaving Soon)"
                leaving-soon-type: MOVIES_AND_TV
              jellyseerr:
                enabled: $seerr_enabled
                url: "http://localhost:${toString jellyseerrPort}"
                api-key: "$seerr_key"
                match-server: false

              # JELLYSTAT IS DELIBERATELY OFF, and it is not merely deferred.
              #
              # M13's brief lists Jellystat as a target, on the grounds that it
              # feeds Janitorr's expiry logic.  Two things found on 2026-08-26
              # move it out of this milestone:
              #
              #   1. COST.  It is a Vite SPA plus an Express backend with no
              #      nixpkgs package, and it requires a PostgreSQL server —
              #      which this container does not have and which would be the
              #      first database in it.
              #   2. UPSTREAM NOW RECOMMENDS SOMETHING ELSE.  Janitorr's own
              #      example compose says, verbatim: "New users without an
              #      existing stats setup should only enable janitorr-stats and
              #      skip Jellystat/Streamystats entirely."
              #
              # So the watch-history feed, when it is wanted, is a
              # `janitorr-stats` question and not a Jellystat one.  Neither is
              # needed for space-based expiry, which is what M13 ships.
              jellystat:
                enabled: false
              streamystats:
                enabled: false
              janitorr-stats:
                enabled: false
            EOF

            # No chown/chmod: Group=media gives this process egid media, so the
            # redirect above creates the file root:media, and UMask=0027 makes
            # it 0640.  Both syscalls would be killed by SystemCallFilter
            # anyway — see the Group= note.
          '';
        };
      };

      ##########################################################################
      # M13 — SCRAPARR.  *arr metrics for M6, as ONE service.
      #
      # ── EXPORTARR WAS REJECTED.  RECORDING THE REJECTION ──────────────────
      #
      # Exportarr is the better-known option and it is the wrong shape for this
      # container.  It needs ONE INSTANCE PER APP: one uid, one port and one
      # firewall line each, in a file whose entire port policy is "one list in
      # one place" and whose Traefik source-restriction is literally a
      # concatMapStrings over a single explicit list.  Six *arr would mean six
      # of everything.
      #
      # Scraparr is one service, one port (7100), one configuration, with every
      # instance addressed by alias inside it.
      #
      # ── ITS CONFIGURATION IS AN EnvironmentFile, NOT A YAML ───────────────
      #
      # Scraparr merges a config.yaml with environment variables.  This deploy
      # ships NO yaml at all, and the reason is the API keys: they must not sit
      # in /nix/store, and the yaml's own `${VAR}` substitution explicitly does
      # NOT support the `*_FILE` form (upstream's config.yaml says so in a
      # comment).  Environment variables support both.
      #
      # A NOTE AGAINST docs/roadmap.md, which says "env-var mode does NOT
      # support multiple instances, so the file-based path is the only one that
      # works here."  That was true once; at v3.1.0 it is not.  Reading
      # src/scraparr/parser/__init__.py:
      #
      #   SONARR_URL           single instance
      #   SONARR_PROD_URL      instance with alias "prod"
      #   SONARR_API_KEY_FILE  reads the key from a path
      #
      # — aliases and _FILE both work in env-var mode, and they compose.  The
      # CONCLUSION the roadmap reached is still the right one; the reason it
      # gave has expired, so it is corrected here rather than propagated.
      #
      # ── IT REUSES arr-api-keys.  NO SECOND STAGING MECHANISM ──────────────
      #
      # M13 requires this explicitly, and M4's argument holds unchanged: the
      # keys are generated BY THE APPLICATIONS into their own config.xml, so
      # reading them there keeps one source of truth and survives a key
      # rotation in a UI with no deploy.  A prompted clan var would be a second
      # copy with no link to the first.
      #
      # The staged files sit in a 0700 root-owned RuntimeDirectory, so an
      # unprivileged reader cannot open them directly.  LoadCredential bridges
      # that — see the note on it below.
      systemd.services.scraparr = {
        description = "Scraparr — Prometheus exporter for the *arr suite";
        wantedBy    = [ "multi-user.target" ];
        after       = [ "sonarr.service" "radarr.service" "prowlarr.service" "arr-api-keys.service" ];
        wants       = [ "sonarr.service" "radarr.service" "prowlarr.service" ];
        requires    = [ "arr-api-keys.service" ];

        environment = {
          GENERAL_PORT = toString scraparrPort;

          # 127.0.0.1 would be wrong: Prometheus is in ANOTHER container and
          # reaches this over the veth.  0.0.0.0 is upstream's default anyway;
          # it is stated rather than left implicit because the firewall rule
          # above is what makes that safe, and the two belong in one field of
          # view.
          GENERAL_ADDRESS = "0.0.0.0";
          GENERAL_PATH    = "/metrics";

          # localhost throughout — one netns, no ports opened.
          SONARR_URL   = "http://localhost:${toString sonarrPort}";
          RADARR_URL   = "http://localhost:${toString radarrPort}";
          PROWLARR_URL = "http://localhost:${toString prowlarrPort}";
          BAZARR_URL   = "http://localhost:${toString bazarrPort}";
          SEERR_URL    = "http://localhost:${toString jellyseerrPort}";

          # The keys, by PATH rather than by value.  `_FILE` is read by
          # Scraparr itself at startup (parser/__init__.py `_get_env_value`),
          # which is what keeps them out of /proc/<pid>/environ.
          #
          # %d is systemd's credentials directory — the 0400 copies
          # LoadCredential below places there, NOT the 0700 staging directory,
          # which this unit's user cannot open.  Specifier expansion applies to
          # Environment=, so these resolve before the process starts.
          #
          # ALL FIVE, and it is all-or-nothing by Scraparr's design: it exits 1
          # on a service that has a URL without a key OR a key without a URL.
          # The URLs above and these paths have to stay in lockstep.
          SONARR_API_KEY_FILE     = "%d/sonarr-api-key";
          RADARR_API_KEY_FILE     = "%d/radarr-api-key";
          PROWLARR_API_KEY_FILE   = "%d/prowlarr-api-key";
          BAZARR_API_KEY_FILE     = "%d/bazarr-api-key";
          SEERR_API_KEY_FILE      = "%d/jellyseerr-api-key";
        };

        serviceConfig = {
          Type      = "simple";
          User      = "scraparr";
          Group     = "scraparr";
          ExecStart = "${lib.getExe scraparr}";
          Restart   = "on-failure";
          RestartSec = "30s";

          # arr-api-keys writes its output into a 0700 RuntimeDirectory owned
          # by root, so an unprivileged reader needs help.  This is the one
          # place M13 adds a path into that directory for a non-root consumer,
          # and it is done with a systemd CREDENTIAL rather than by widening
          # the directory: LoadCredential is read by PID 1 before the drop to
          # User=scraparr, and lands a 0400 copy the service can read.
          #
          # Widening the directory instead would have been the tempting fix and
          # is the wrong one — recyclarr and umlautadaptarr read from the same
          # directory, and loosening it for a third consumer loosens it for all
          # three.
          LoadCredential = [
            "sonarr-api-key:${arrSecretsDir}/sonarr-api-key"
            "radarr-api-key:${arrSecretsDir}/radarr-api-key"
            "prowlarr-api-key:${arrSecretsDir}/prowlarr-api-key"
            "bazarr-api-key:${arrSecretsDir}/bazarr-api-key"
            "jellyseerr-api-key:${arrSecretsDir}/jellyseerr-api-key"
          ];

          # No state, no media, nothing to write anywhere.
          UMask = "0077";

          NoNewPrivileges  = true;
          PrivateTmp       = true;
          ProtectSystem    = "strict";
          ProtectHome      = true;
          RemoveIPC        = true;
          RestrictSUIDSGID = true;

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
        };
      };

      ##########################################################################
      # M14 (a) — LIDARR.  Music, and the consumer end of the second write path.
      #
      # ── ITS UPSTREAM MODULE SHIPS NO HARDENING.  NONE ────────────────────
      #
      # This is the surprise of M14 and it is worth stating plainly, because
      # the sibling modules set the expectation the other way.  nixpkgs'
      # servarr modules are NOT uniform:
      #
      #   sonarr.nix    a full "# Hardening" block — CapabilityBoundingSet,
      #                 NoNewPrivileges, ProtectHome, PrivateUsers, ProtectProc,
      #                 RestrictAddressFamilies, UMask = "0022", …
      #   radarr.nix    the same
      #   lidarr.nix    Type, User, Group, EnvironmentFile, ExecStart, Restart.
      #                 THAT IS THE ENTIRE serviceConfig.
      #
      # Read at ernst's own pin on 2026-08-28, not assumed from the family
      # resemblance.  So Lidarr does not need its UMask overridden the way
      # sonarr's and radarr's do — it needs the whole set supplied, and the
      # `mkForce` those two require would be wrong here (there is no upstream
      # definition to conflict with).
      #
      # This is the Prowlarr trap in a third form.  M4 met it as "DynamicUser →
      # static uid silently drops six directives"; M12 met it as "upstream sets
      # eight of them"; here upstream sets zero and the family suggests
      # otherwise.  The lesson generalises: READ THE UNIT, do not infer it from
      # a sibling.
      #
      # ── dataDir IS NOT /var/lib/lidarr ───────────────────────────────────
      #
      # The module defaults it to `/var/lib/lidarr/.config/Lidarr`, and the
      # unit has no StateDirectory at all, so nothing creates the directory
      # either.  Left alone, that is exactly right for this container: the bind
      # mount is /var/lib/lidarr (the home), the host tmpfiles rule owns it as
      # 3017:3000, and Lidarr creates `.config/Lidarr` inside on first start.
      ##########################################################################
      services.lidarr = {
        enable       = true;
        user         = "lidarr";
        group        = "media";     # PRIMARY group — see the users block
        openFirewall = false;       # explicit list above
        settings.server.port = lidarrPort;
      };

      systemd.services.lidarr.serviceConfig = {
        # THE hardlink line, and the consumer half of the property
        # microvms/wg-qbittorrent.nix's slskd block provides.  slskd writes
        # 0664; Lidarr links and then writes its own artwork and .nfo files
        # next to the media, and at 0022 those would land writable by exactly
        # one uid on a tree whose whole point is that `media` can manage it.
        #
        # NO mkForce, unlike sonarr and radarr: upstream sets no UMask here at
        # all, so this is a new definition rather than a competing one.
        UMask = "0002";

        # The hardening upstream omits.  Same set as sonarr's and radarr's,
        # restated in full rather than referenced, because there is nothing
        # here to inherit from.
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

        # AF_INET/AF_INET6 for indexers and MusicBrainz, AF_UNIX for logging.
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];

        # NOT ProtectHome = true.  sonarr and radarr carry it and can, because
        # their dataDir is /var/lib/<name>; Lidarr's home IS its state
        # directory and ProtectHome would make /var/lib/lidarr invisible to it.
        # ProtectSystem=strict plus an explicit ReadWritePaths is what does the
        # work instead.
        ProtectSystem  = "strict";
        ReadWritePaths = [ "/srv/media" "/var/lib/lidarr" ];

        # NOT PrivateUsers.  sonarr and radarr carry it — which is why `media`
        # has to be their PRIMARY group — and it is upstream's choice there,
        # not this file's.  Adding it here would buy nothing (Lidarr's access
        # to /srv/media is entirely its group membership, and that group is
        # already primary) and would cost the same footgun for the next person
        # who adds a supplementary group.
        #
        # NOT MemoryDenyWriteExecute: Lidarr is .NET and the JIT maps
        # writable-then-executable pages.  Same rejection as sonarr/radarr and
        # containers/jellyfin.nix, for the same runtime.
      };

      ##########################################################################
      # M14 (b) — SOULARR.  A TIMER, NOT A SERVICE.
      #
      # It reads Lidarr's "wanted" list, searches Soulseek through slskd's REST
      # API, grabs the best match into slskd's download tree, and tells Lidarr
      # to import it.  Lidarr then hardlinks out of that tree, which is the
      # chain M14's proof is about.
      #
      # ── WHY A TIMER ──────────────────────────────────────────────────────
      #
      # soularr.py runs one pass and EXITS.  Upstream's Docker image fakes a
      # daemon with a `SCRIPT_INTERVAL` sleep loop and its README's non-Docker
      # instruction is a cron entry.  A `Restart=always` service would restart-
      # loop by design and log every SUCCESSFUL pass as a service exit.
      #
      # 15 minutes, not upstream's 5.  Every firing is a full pass over Lidarr's
      # wanted list plus live Soulseek searches, each search bounded by
      # `search_timeout`; five minutes is tuned for someone watching a fresh
      # setup fill up, not for steady state.  The lock file makes an overlong
      # pass safe either way — see below.
      #
      # ── THE CONFIG IS RENDERED AT RUN TIME, NOT INTO THE STORE ───────────
      #
      # config.ini carries TWO API keys: Lidarr's (out of Lidarr's own
      # config.xml, via the existing arr-api-keys stager) and slskd's (from the
      # clan var).  Neither may sit in /nix/store, so the file is written into
      # a tmpfs on every firing — the same shape as janitorr's application.yml.
      #
      # ── THE LOCK FILE IS AN INTERLOCK, NOT A LEFTOVER ────────────────────
      #
      # soularr.py writes `.soularr.lock` into --var-dir and refuses to start
      # while it exists, which is what stops a slow pass from being overrun by
      # the next timer firing.  --var-dir therefore points at the PERSISTENT
      # state bind mount, not at the tmpfs holding the config: a lock on a
      # tmpfs would be erased by a reboot mid-pass, and — worse — would not be
      # seen by the next firing at all if the tmpfs were per-invocation.
      #
      # It also means a CRASHED pass leaves the lock behind and Soularr stays
      # stopped until someone removes it.  That is upstream's design and it is
      # the right failure direction here (a stuck downloader is visible; a
      # doubled one corrupts its own import queue), but it is the first thing
      # to check when Soularr "stops working":
      #
      #     rm /srv/state/soularr/.soularr.lock
      ##########################################################################
      systemd.services.soularr = {
        description = "Soularr — fill Lidarr's wanted list from Soulseek via slskd";

        # Wants, not requires: if Lidarr is down this pass should fail and be
        # retried at the next firing, not block the timer forever.
        after    = [ "lidarr.service" "arr-api-keys.service" ];
        wants    = [ "lidarr.service" ];
        # requires, not wants: without the staged keys this pass can only
        # write a config.ini with an empty API key, which Lidarr answers with
        # a 401 that says nothing about why.
        requires = [ "arr-api-keys.service" ];

        serviceConfig = {
          Type  = "oneshot";
          User  = "soularr";
          Group = "media";

          # Bound the pass.  Without this a hung one runs forever.
          #
          # A Type=oneshot unit is "activating" for as long as its ExecStart
          # runs, and TimeoutStartSec defaults to infinity for oneshots — so a
          # pass that wedges on an unresponsive slskd or a transfer that never
          # completes never ends.  While it sits there the timer cannot fire
          # again (the unit is already active), so Soularr stops running
          # permanently, and the unit shows `activating` rather than `failed`
          # so nothing looks wrong.  Silent, indefinite, and self-concealing:
          # the worst of the three.
          #
          # TimeoutStartSec and NOT RuntimeMaxSec.  systemd.service(5) is
          # explicit that RuntimeMaxSec "does not have any effect on
          # Type=oneshot services ... use TimeoutStartSec= to limit their
          # activation".  Setting the other one looks right and does nothing.
          #
          # Two hours.  A legitimate pass is bounded by the config rendered
          # below: each search by `search_timeout`, and a transfer this pass is
          # waiting on by `stalled_timeout`, which is 3600.  So one stalled
          # download can legitimately hold a pass for an hour; two hours clears
          # that with room and still turns "forever" into a bounded failure.
          #
          # On expiry the unit goes to `failed` with Result=timeout — and note
          # that the lock file described above is then LEFT BEHIND, which is
          # the documented, deliberate failure direction: Soularr stays stopped
          # until someone runs the `rm`.  That is a better resting place than
          # the current one only because `failed` is a state something can
          # eventually alert on; `activating` is not.  Nothing watches units
          # inside this container yet, which is what makes that caveat matter.
          TimeoutStartSec = 7200;

          # See the render script: these are read by PID 1 as root and handed
          # to the unit as 0400 copies under $CREDENTIALS_DIRECTORY.  Both are
          # root-owned and unreadable by this unit's user at their real paths.
          LoadCredential = [
            "lidarr-api-key:${arrSecretsDir}/lidarr-api-key"
            # The STAGED copy, not slskdCredsGen's own path: that one is on the
            # host and invisible in here.  See soularrSecretsDir.
            "slskd-api-key:${soularrSecretsDir}/slskd-api-key"
          ];

          # Renders config.ini into a private tmpfs directory immediately
          # before the run.  RuntimeDirectory gives it 0700 ownership by the
          # service user and — importantly — REMOVES IT WHEN THE UNIT STOPS,
          # so the API keys exist only while a pass is running.
          RuntimeDirectory     = "soularr";
          RuntimeDirectoryMode = "0700";

          ExecStartPre = [
            "${pkgs.writeShellScript "soularr-render-config" ''
              set -euo pipefail

              # Read into variables FIRST and check them.  A command
              # substitution that fails inside a sed argument does not trip
              # `set -e`, which is how containers/jellyfin.nix's sibling bug
              # shipped an EMPTY password once.  A plain assignment does trip
              # it, and the explicit test covers "file present but empty".
              # $CREDENTIALS_DIRECTORY, NOT the staging directory.
              #
              # The staged keys are 0600 root:root inside a 0700 root directory
              # — deliberately, see the arr-api-keys block — so User=soularr
              # cannot open them and `cat` fails with "Permission denied".
              # That is exactly what shipped: every timer firing failed for a
              # day before anyone looked, because a failed oneshot on a timer
              # is silent unless you go and read its journal.
              #
              # LoadCredential below is what bridges it: PID 1 reads the files
              # as root BEFORE dropping to this unit's user, and places 0400
              # copies here that the service can read.  Scraparr solves the
              # same problem the same way and this file's header already said
              # so.
              lidarr_key=$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/lidarr-api-key")
              slskd_key=$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/slskd-api-key")

              if [ -z "$lidarr_key" ] || [ -z "$slskd_key" ]; then
                echo "soularr: an API key is empty — has arr-api-keys run, and has 'clan vars generate ernst' been run for slskd-credentials?" >&2
                exit 1
              fi

              ${pkgs.coreutils}/bin/install -m 0600 /dev/null ${soularrConfigDir}/config.ini
              ${pkgs.coreutils}/bin/cat > ${soularrConfigDir}/config.ini <<EOF
              [Lidarr]
              api_key = $lidarr_key
              host_url = http://localhost:${toString lidarrPort}
              download_dir = ${soulseekDownloadDir}
              disable_sync = False

              [Slskd]
              api_key = $slskd_key
              host_url = http://${slskdAddr}:${toString slskdPort}
              url_base = /
              download_dir = ${soulseekDownloadDir}
              delete_searches = False
              stalled_timeout = 3600
              remote_queue_timeout = 300

              [Release Settings]
              use_selected_lidarr_release = False
              use_most_common_tracknum = True
              allow_multi_disc = True
              accepted_countries = Europe,Japan,United Kingdom,United States,[Worldwide],Australia,Canada
              skip_region_check = False
              accepted_formats = CD,Digital Media,Vinyl

              [Search Settings]
              search_timeout = 5000
              maximum_peer_queue = 50
              minimum_peer_upload_speed = 0
              minimum_filename_match_ratio = 0.8
              minimum_search_interval = 5
              allowed_filetypes = flac 24/192,flac 16/44.1,flac,mp3 320,mp3
              album_prepend_artist = False
              search_type = incrementing_page
              number_of_albums_to_grab = 10
              search_source = missing
              failed_import_denylist = True

              [Download Settings]
              allow_uploads = False

              [Logging]
              level = INFO
              format = [%%(levelname)s|%%(module)s|L%%(lineno)d] %%(asctime)s: %%(message)s
              datefmt = %%Y-%%m-%%dT%%H:%%M:%%S%%z
              EOF
            ''}"
          ];

          # --config-dir and --var-dir are BOTH passed explicitly.  Upstream
          # defaults both to os.getcwd(), which for a systemd unit is `/`, and
          # a downloader that silently reads its configuration out of the root
          # directory is worse than one that fails.
          ExecStart = "${lib.getExe soularr} --config-dir ${soularrConfigDir} --var-dir /var/lib/soularr";

          # Group-writable output — it moves rejected downloads aside inside
          # slskd's tree, which is 2770 root:media.  Same argument as
          # sonarr/radarr/cleanuparr.
          UMask = "0002";

          # Static uid with persistent state — the prowlarr shape, so every
          # directive DynamicUser would have implied is restated explicitly.
          NoNewPrivileges  = true;
          PrivateTmp       = true;
          ProtectSystem    = "strict";
          ProtectHome      = true;
          RemoveIPC        = true;
          RestrictSUIDSGID = true;

          # It reads ID3 tags out of the download tree and moves rejects; it
          # never touches the library, which Lidarr owns.
          ReadWritePaths = [ soulseekRoot "/var/lib/soularr" ];

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
        };
      };

      systemd.timers.soularr = {
        description = "Run Soularr every 15 minutes";
        wantedBy    = [ "timers.target" ];
        timerConfig = {
          OnBootSec      = "10m";
          OnUnitActiveSec = "15m";
          # A missed firing (host down, container restarting) runs once on the
          # next start rather than not at all.  Harmless for an idempotent
          # pass over a wanted list.
          Persistent     = true;
          # Without this every firing lands on the same second across reboots,
          # which for a job that hammers a P2P network is a needless pattern.
          RandomizedDelaySec = "2m";
        };
      };

      ##########################################################################
      # M14 (c) — KAPOWARR.  Comics acquisition.
      #
      # Komga and CWA already serve the READING side in this household; this is
      # the acquisition half only.  ./pkgs/kapowarr.nix records why it was
      # chosen over Mylar3 (short version: Mylar3 is Usenet-first and this fleet
      # has measurably no Usenet).
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
        #         client and docs/roadmap.md use.
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
      # M17 — BINDERY.  Ebooks: the last media class with no acquisition
      # automation.  Readarr is archived (its metadata backend died);
      # Bindery is the successor picked on FIT — see ./pkgs/bindery.nix for
      # the survey correction (upstream's own repo description was the stale
      # artifact) and docs/roadmap.md's M17 for the full comparison.
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
      # ── WHAT IS DELIBERATELY NOT CONFIGURED ──────────────────────────────
      #
      #   BINDERY_AUDIOBOOK_DIR.  Unset, so audiobooks Bindery might acquire
      #   route to the ebook library dir — and audiobook acquisition is NOT
      #   set up in its UI.  The audiobook pipeline in this house is
      #   Audiobookshelf + Storyteller on /srv/audiobooks; a second writer
      #   into that tree from another product's quality logic is the
      #   two-systems-one-library failure M4/M12 exist to avoid.  If that
      #   changes, set the variable AND argue the ownership here.
      #
      #   BINDERY_TRUSTED_PROXY / BINDERY_URL_BASE.  Distinct hostname, no
      #   subpath, and nothing consumes client IPs from it — same as every
      #   other *arr here.
      ##########################################################################
      systemd.services.bindery = {
        description = "Bindery — ebook acquisition and library manager";
        wantedBy    = [ "multi-user.target" ];
        after       = [ "network.target" ];

        environment = {
          BINDERY_PORT         = toString binderyPort;
          BINDERY_DATA_DIR     = "/var/lib/bindery";
          # Does NOT follow DATA_DIR — measured, see ./pkgs/bindery.nix.
          # Unset, the compiled-in default is /config/bindery.db and the
          # service dies on mkdir at first start.
          BINDERY_DB_PATH      = "/var/lib/bindery/bindery.db";
          BINDERY_LIBRARY_DIR  = "/srv/media/library/books";
          BINDERY_DOWNLOAD_DIR = "/srv/media/torrents/books";
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

          ReadWritePaths = [ "/srv/media" "/var/lib/bindery" ];

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

      services.recyclarr = {
        enable = true;

        # Daily, with the module's 5-minute jitter.  Nothing here is urgent —
        # TRaSH guide changes are edits to a git repo, not events.
        schedule = "daily";

        # localhost, because all of this shares one netns.  Same payoff as the
        # Prowlarr→Sonarr/Radarr wiring: no port opened, nothing to firewall.
        #
        # ── The config is INLINED, not `include`d, and that is forced ────────
        #
        # The obvious form is `include: [ { template = "remux-web-2160p"; } ]`,
        # naming one of the ids in the official config-templates repo.  It does
        # not work on v8 and fails with "Unable to find include template with
        # name".  Those templates are STARTER CONFIGS, meant to be copied once
        # via `recyclarr config create` and then edited; the repo ships no
        # include-able fragments at all (its `includes/` directory is for
        # user-authored ones and is empty).  So the template body is
        # transcribed here instead — which is the better shape for this repo
        # anyway: the profile and every custom-format group is an explicit,
        # reviewable value rather than a remote id whose contents can change
        # under a `git fetch`.
        #
        # Transcribed from config-templates @ 9faf65f:
        #   radarr/templates/remux-web-2160p.yml
        #   sonarr/templates/remux-web-2160p.yml
        # and validated with `recyclarr sync --preview` against the live
        # instances before being committed.
        #
        # ── INSTANCE NAMES MUST BE UNIQUE ACROSS SERVICES ────────────────────
        #
        # AND SO MUST base_url — M12 found the second half the hard way, and it
        # is written out where the block itself lives, below.  Unique names are
        # necessary and NOT sufficient: recyclarr groups instances by base_url
        # and treats two names on one server as duplicates, with the identical
        # silent outcome described here.  ONE INSTANCE PER SERVER, ALWAYS;
        # extra profiles go in `quality_profiles`.
        #
        # `movies` and `series`, not `main` and `main`.  Recyclarr treats the
        # instance-name namespace as global, not per-service, and it enforces
        # that in the worst possible way: with both named `main` it logs
        # "Duplicate instances: [main]" at DEBUG, syncs NOTHING, prints nothing
        # to the console and EXITS 0.  A green timer, forever, doing nothing.
        # Measured 2026-08-21; the first version of this file had exactly that
        # bug and only a --preview run caught it.
        #
        # ── WHAT THIS CHANGES on the live instances ──────────────────────────
        #
        # More than the first draft of this block claimed, so it is spelled out.
        # This applies quality definitions (per-quality file size limits) AND a
        # quality profile AND custom-format scoring.  `[Audio] Audio Formats`
        # syncs by default (it is listed under the templates' `skip:` blocks,
        # commented out), and that group is what scores TrueHD Atmos and DTS-X
        # above everything else.
        #
        # THE TWO SERVICES ARE DELIBERATELY ASYMMETRIC:
        #
        #   radarr → Remux + WEB 2160p   films are what you sit down for, and
        #                                TrueHD Atmos lives on Bluray remuxes;
        #                                WEB releases carry only lossy DD+ Atmos
        #   sonarr → WEB-1080p           series are the bulk of the episode
        #                                count, so this is where restraint
        #                                actually saves the pool
        #
        # WHAT "REMUX" MEANS HERE, because the everyday meaning of the word
        # points the wrong way: in TRaSH/*arr terms a Remux release is the video
        # and audio streams lifted UNTOUCHED off the UHD Blu-ray into an MKV.
        # It is the TOP of the quality ladder and the LARGEST file type —
        # roughly 40–80 GB per film — not a re-package for compatibility.  If
        # anything it is *less* compatible: full TrueHD Atmos and dual-layer
        # Dolby Vision are exactly what weak clients cannot direct-play.
        #
        # MEASURED CONTEXT — RE-MEASURED 2026-08-26, AND THE OLD NUMBERS WERE
        # WRONG IN A WAY THAT MATTERED.
        #
        # This paragraph used to read: "Sonarr held 133 series, all on a
        # hand-made profile 'Ultra-HD' with upgradeAllowed = FALSE."  Both
        # halves are false today, and the second was probably always a
        # conflation of the two services.  Actual census, via each app's
        # /api/v3 endpoints:
        #
        #   SONARR   139 series
        #     id 4  HD-1080p               upgradeAllowed=false    67
        #     id 6  HD - 720p/1080p        upgradeAllowed=false    13
        #     id 7  Remux + WEB 2160p      upgradeAllowed=TRUE     59
        #     id 5  Ultra-HD               upgradeAllowed=false     0  ← empty
        #
        #   RADARR   2432 movies
        #     id 5  Ultra-HD               upgradeAllowed=false  2389
        #     id 7  Remux + WEB 2160p      upgradeAllowed=TRUE     27
        #     id 6  HD - 720p/1080p        upgradeAllowed=false    16
        #
        # So "the big pile sitting on a non-upgrading Ultra-HD profile" is a
        # RADARR fact — 2389 films — and Sonarr's Ultra-HD holds nothing at
        # all.  The bulk-edit hazard is real and is mostly on the film side;
        # the film library is the 13 TB one and the pool has ~47.6 TB free, so
        # a mass promotion there is still capable of consuming most of it
        # through the VPN.
        #
        # The operating rule is unchanged and now rests on correct numbers:
        # promote titles to a new profile INDIVIDUALLY.  The one part that
        # applies fleet-wide regardless is `quality_definition`, which rewrites
        # size limits for every profile including "Ultra-HD".
        #
        # reset_unmatched_scores means custom formats NOT named by these groups
        # are set to 0 on the synced profile.  That is what makes the profile
        # reproducible from this file rather than accumulating whatever the UI
        # has been poked into.
        #
        # To preview before letting the timer run.
        #
        # CORRECTED 2026-08-26 — the previous form in this comment did not work
        # and failed in a way that reads like a permissions problem:
        #
        #   runuser: failed to execute recyclarr: Permission denied
        #
        # `recyclarr` IS NOT ON $PATH inside this container.  The container's
        # environment.systemPackages is deliberately just `curl`; the binary
        # only ever exists as an absolute store path in the unit's ExecStart.
        # So the command has to ask systemd where it is rather than assume a
        # PATH lookup, and the store path changes with every rebuild, so it
        # must not be pasted literally either:
        #
        #   nixos-container run arr -- systemctl start arr-api-keys
        #   BIN=$(nixos-container run arr -- \
        #           systemctl show recyclarr -p ExecStart --value \
        #         | grep -o '/nix/store/[^ ]*/bin/recyclarr' | head -1)
        #   nixos-container run arr -- runuser -u recyclarr -- \
        #     "$BIN" sync --preview --config /var/lib/recyclarr/config.yml
        #
        # ONE TRAP IN READING THE OUTPUT, and it cost a confused minute on the
        # deploy that found this: /var/lib/recyclarr/config.yml IS REGENERATED
        # BY ExecStartPre, not by the deploy.  Straight after a rebuild it is
        # still the PREVIOUS generation's file, so a preview run will faithfully
        # process the OLD instance list and show nothing new.  That is not a
        # config that failed to apply.  The check that the new instances really
        # are deployed is the unit itself —
        #
        #   nixos-container run arr -- systemctl show recyclarr -p ExecStartPre \
        #     --value | xargs cat | grep -o 'quality_profiles.*' | head -c 400
        #
        # — the pre-start script embeds the whole rendered config as a heredoc,
        # so it shows what the NEXT run will use without running anything.
        # (`grep -c LoadCredential` counts `_secret` references, which is two
        # here — one per INSTANCE, not per profile.)  Run the service once, or
        # wait for the timer, and config.yml catches up.
        configuration = {

          ####################################################################
          # M12 (g) — THREE MORE PROFILES, ON THE TWO EXISTING INSTANCES.
          #
          # ── RECYCLARR DEDUPLICATES ON base_url, NOT ON INSTANCE NAME ──────
          #
          # THIS IS THE CORRECTED VERSION.  The first attempt gave each new
          # profile its own INSTANCE (`sonarr.series-german`, and so on) with a
          # distinct name, on the strength of the "instance names must be
          # unique" warning further up this file.  Unique names are necessary
          # and NOT sufficient.  Measured on ernst 2026-08-26:
          #
          #   [DBG] Split instances: [
          #     {"BaseUrl":"http://localhost:7878",
          #      "InstanceNames":["movies","movies-german"]},
          #     {"BaseUrl":"http://localhost:8989",
          #      "InstanceNames":["series","series-german","series-remux-2160p"]}]
          #
          # …and then it synced NOTHING and EXITED 0.  Two instance names
          # pointing at ONE base_url are duplicates as far as recyclarr is
          # concerned, however differently they are named.  This is the SAME
          # fails-by-succeeding bug the header already warns about, on a
          # dimension the warning did not cover — so the rule is now:
          #
          #   ONE INSTANCE PER SERVER.  ALWAYS.  Additional profiles go in
          #   `quality_profiles`; never in a new instance.
          #
          # It is only visible with `--log debug`.  At the default level the
          # command prints two "Initializing provider" lines and stops, which
          # looks like success.  The check is the ABSENCE of "Processing" and
          # "Completed at" lines, exactly as the note below `systemd.services.
          # recyclarr` says.
          #
          # ── SO HOW ARE THE GROUPS KEPT APART? assign_scores_to ────────────
          #
          # The cross-contamination worry that motivated separate instances is
          # real: `custom_format_groups` is declared per INSTANCE, and a group
          # with no `assign_scores_to` applies to ALL guide-backed profiles in
          # that instance.  Left implicit, the German unwanted-formats set
          # would land on the English profile and vice versa — a config that
          # syncs cleanly and scores nonsense.
          #
          # `assign_scores_to` is the mechanism that solves it properly, and it
          # takes a profile REFERENCE — `trash_id` or `name`.  trash_id is used
          # throughout below: it is what `quality_profiles` already keys on, and
          # a name can be changed in the *arr UI by anyone, silently detaching
          # the scores from the profile.
          #
          # EVERY GROUP HERE CARRIES AN EXPLICIT assign_scores_to, including
          # the ones that go to only one profile.  Relying on the "applies to
          # all" default would mean the correctness of this block changed the
          # next time a profile was added — which is precisely how it broke.
          #
          # The pairings below are NOT invented: each is the group list its own
          # TRaSH template ships with, transcribed whole, from config-templates
          # @ 9faf65f.  Scores and CF combinations are tested together to
          # prevent download loops; a half-transcribed group is not a smaller
          # version of the same thing.
          #
          # NOT ADDED, both recorded so they are not "discovered" later:
          #
          #   AN ANIME PROFILE.  M12 (g) says to ask rather than assume, because
          #   it is a substantial custom-format set for content nobody has said
          #   they watch.  Asked on 2026-08-26; the answer was no.  Reopen it by
          #   adding sonarr/templates/anime-remux-1080p.yml's profile to the
          #   `sonarr.series` quality_profiles list below — NOT as a new
          #   instance, for the reason at the top of this comment.
          #
          #   PROFILARR.  Same job as this block, but it keeps state in ITS OWN
          #   DATABASE.  A Nix attrset is a reviewable diff with recorded
          #   provenance and is strictly better here — the argument the
          #   recyclarr header makes about why this config is inlined rather
          #   than `include`d applies to Profilarr with more force, not less.
          #   REJECTED, deliberately.
          ####################################################################

          radarr.movies = {
            base_url        = "http://localhost:${toString radarrPort}";
            api_key._secret = "${arrSecretsDir}/radarr-api-key";

            quality_definition.type = "movie";

            quality_profiles = [
              {
                trash_id = "fd161a61e3ab826d3a22d53f935696dd";   # Remux + WEB 2160p
                reset_unmatched_scores.enabled = true;
              }
              # M12: the German companion, pitched to MATCH the English profile
              # rather than sit below it.  Films are what you sit down for, and
              # a German profile a step down would make "upgrade to German when
              # one appears" a downgrade in everything except language.
              #
              # THE BEHAVIOUR THIS BUYS, which is the actual request in M12 (g):
              # grab the best English release first, then upgrade to German /
              # German-DL when one appears, upgrading until "Upgrade Until
              # Custom Format Score".  That is a property of the TRaSH German
              # profile itself — its German-audio CFs carry positive scores and
              # its cutoff sits above what an English-only release can reach —
              # not something configured here.  It only takes effect for titles
              # ASSIGNED to it; see the promotion rule on the Sonarr side.
              {
                trash_id = "79faa9943cef2f510b997b1f2a9f3ea6";   # [German] Remux + WEB 2160p
                reset_unmatched_scores.enabled = true;
              }
            ];

            # Groups these templates add on top of the three synced by default
            # ([Audio] Audio Formats, [HDR Formats] HDR, [Streaming Services]
            # General).  Those three are not listed anywhere — they are on
            # unless explicitly skipped.
            custom_format_groups.add = [
              # Both templates ship Golden Rule UHD, so it goes to both.
              {
                trash_id = "ff204bbcecdd487d1cefcefdbf0c278d";    # [Optional] Golden Rule UHD
                assign_scores_to = [
                  { trash_id = "fd161a61e3ab826d3a22d53f935696dd"; }
                  { trash_id = "79faa9943cef2f510b997b1f2a9f3ea6"; }
                ];
              }
              # English unwanted formats — ENGLISH PROFILE ONLY.
              {
                trash_id = "a3ac6af01d78e4f21fcb75f601ac96df";    # [Unwanted] Unwanted Formats
                assign_scores_to = [ { trash_id = "fd161a61e3ab826d3a22d53f935696dd"; } ];
              }
              # GERMAN unwanted formats — GERMAN PROFILE ONLY.  A different
              # trash_id with different contents, not a translation: it adds
              # German LQ, German LQ (release title) and German Microsized,
              # which are the formats that make a German library unwatchable
              # and which the English group knows nothing about.
              {
                trash_id = "0ca61b4b233178d07113082a7acff72d";    # [Unwanted] Unwanted Formats German
                assign_scores_to = [ { trash_id = "79faa9943cef2f510b997b1f2a9f3ea6"; } ];
              }
            ];
          };

          sonarr.series = {
            base_url        = "http://localhost:${toString sonarrPort}";
            api_key._secret = "${arrSecretsDir}/sonarr-api-key";

            quality_definition.type = "series";

            # 1080p for series, deliberately — see the asymmetry note above.
            # Transcribed from sonarr/templates/web-1080p.yml, NOT from the
            # 2160p one: the group list differs by more than the profile id.
            quality_profiles = [
              {
                trash_id = "72dae194fc92bf828f32cde7744e51a1";   # WEB-1080p
                reset_unmatched_scores.enabled = true;
              }
              # M12: German series at HD, matching the English profile's
              # restraint for the reason this file already gives — series are
              # the bulk of the episode count, so this is where restraint
              # actually saves the pool.
              {
                trash_id = "dca7e5e9e99c703bcbdaaa471dd40e98";   # [German] HD Bluray + WEB
                reset_unmatched_scores.enabled = true;
              }
              # M12: Sonarr Remux + WEB 2160p.
              #
              # ── THIS ONE ADOPTS AN EXISTING PROFILE.  IT IS NOT NEW ──────
              #
              # M12 asked for this to be "created ALONGSIDE" the others.  It
              # cannot be, and the deploy is what revealed why: Sonarr ALREADY
              # HAS a profile named exactly `Remux + WEB 2160p` (id 7), with
              # upgradeAllowed = TRUE and 59 OF THE 139 SERIES ON IT.  Syncing
              # the guide's profile under its guide name therefore does not
              # create anything — recyclarr takes the existing profile over and
              # rewrites it, and `reset_unmatched_scores` below zeroes every
              # custom format these groups do not name.
              #
              # ADOPTING IT IS A DELIBERATE CHOICE, made by lgo on 2026-08-26
              # with the consequence stated: those 59 series ride an
              # upgrade-enabled profile, so re-scoring can put their current
              # files below cutoff and queue 2160p upgrade searches.  The
              # alternative — giving the guide-backed profile an explicit
              # `name` so recyclarr builds a separate one and leaves id 7
              # alone — was considered and rejected: bringing the profile
              # actually in use into line with TRaSH is the point, and a
              # second nearly-identical 2160p profile is a thing nobody would
              # keep straight.
              #
              # WATCH THE ACTIVITY QUEUE AFTER THE FIRST REAL SYNC.  If it
              # fills with upgrade grabs for those 59 series, the lever is
              # Sonarr's own "Upgrade Until Custom Format Score" on this
              # profile, not this file.
              #
              # ── THE RULE IS STILL INDIVIDUAL PROMOTION.  DO NOT BULK-EDIT ─
              #
              # Someone will eventually "tidy up" by selecting everything and
              # reassigning the profile in one action.  Re-measured 2026-08-26,
              # and the hazard is mostly on the RADARR side: 2389 of 2432 films
              # sit on a hand-made "Ultra-HD" profile with upgradeAllowed =
              # false, and every TRaSH profile ships upgradeAllowed = true.
              # Mass-promoting those would queue a re-download of most of a
              # 13 TB film library against ~47.6 TB of free space, through the
              # VPN.  (The older form of this note put 133 series on Sonarr's
              # Ultra-HD; Sonarr's Ultra-HD is empty and always was the wrong
              # service to cite — see the census above.)
              #
              # Recyclarr never reassigns a title, so nothing moves on its own.
              # The danger is entirely a human with a multi-select box.
              {
                trash_id = "76a5053bdb2d1e4a8f16a69a37d46c12";   # Remux + WEB 2160p
                reset_unmatched_scores.enabled = true;
              }
            ];

            custom_format_groups.add = [
              # Golden Rule *HD* for the two HD profiles.  It is a different
              # group from the UHD one below — different trash_ids, tuned to
              # different resolutions — and carrying the UHD one onto a 1080p
              # profile would score x265/HDR rules that do not belong there.
              {
                trash_id = "158188097a58d7687dee647e04af0da3";    # [Optional] Golden Rule HD
                assign_scores_to = [
                  { trash_id = "72dae194fc92bf828f32cde7744e51a1"; }
                  { trash_id = "dca7e5e9e99c703bcbdaaa471dd40e98"; }
                ];
              }
              # Golden Rule UHD, and note this is SONARR's id — Sonarr and
              # Radarr have different groups with different trash_ids under the
              # same name.  2160p profile only.
              {
                trash_id = "e3f37512790f00d0e89e54fe5e790d1c";    # [Optional] Golden Rule UHD
                assign_scores_to = [ { trash_id = "76a5053bdb2d1e4a8f16a69a37d46c12"; } ];
              }
              # The three the two ENGLISH templates share.  Deliberately NOT on
              # the German profile: its own template ships neither Language
              # Profiles nor the streaming boost, and adding them would be
              # exactly the "mixing groups that were tested together" the TRaSH
              # guidance warns about.
              {
                trash_id = "74aff4168620ed49dcc67e92b2c2a5b4";    # [Optional] Language Profiles
                assign_scores_to = [
                  { trash_id = "72dae194fc92bf828f32cde7744e51a1"; }
                  { trash_id = "76a5053bdb2d1e4a8f16a69a37d46c12"; }
                ];
              }
              {
                trash_id = "85fae4a2294965b75710ef2989c850eb";    # [Streaming Services] HD/UHD boost
                assign_scores_to = [
                  { trash_id = "72dae194fc92bf828f32cde7744e51a1"; }
                  { trash_id = "76a5053bdb2d1e4a8f16a69a37d46c12"; }
                ];
              }
              {
                trash_id = "59c3af66780d08332fdc64e68297098f";    # [Unwanted] Unwanted Formats
                assign_scores_to = [
                  { trash_id = "72dae194fc92bf828f32cde7744e51a1"; }
                  { trash_id = "76a5053bdb2d1e4a8f16a69a37d46c12"; }
                ];
              }
              # GERMAN unwanted formats — German profile only, same argument as
              # on the Radarr side.
              {
                trash_id = "6f0872eebfc95b1f93474b7ac866ced0";    # [Unwanted] Unwanted Formats German
                assign_scores_to = [ { trash_id = "dca7e5e9e99c703bcbdaaa471dd40e98"; } ];
              }
            ];
          };
        };
      };

      # Do not fire while the things being configured are still coming up.
      # `wants`, not `requires`: recyclarr failing is not a reason to consider
      # sonarr degraded, and a sync that runs a minute early simply fails and
      # retries tomorrow.
      systemd.services.recyclarr = {
        after = [ "sonarr.service" "radarr.service" ];
        wants = [ "sonarr.service" "radarr.service" ];

        # DO NOT ADD `path = [ pkgs.git ]` HERE.  It was added once, on the
        # strength of an inference, and reverted after measurement.
        #
        # Recyclarr does shell out to a `git` binary to clone and fetch the
        # TRaSH-Guides and config-templates repos, and `command -v git` inside
        # this container correctly reports nothing — which makes "git is
        # missing" a very convincing explanation for a sync that does nothing.
        # It is wrong.  nixpkgs wraps the recyclarr binary with git already on
        # its PATH (`nix-store -q --references` on the package lists
        # git-2.54.0), so it finds one regardless of the unit's environment.
        # Verified on ernst 2026-08-21: with git explicitly filtered OUT of the
        # PATH passed to it, recyclarr still fetched 74 MB of guides and its
        # debug log shows the `git fetch` and `git reset --hard` succeeding.
        #
        # WHAT ACTUALLY CAUSED the silent run that prompted this: the config
        # file was not where recyclarr was told to look.  This container's /tmp
        # is a tmpfs, so a file written to the HOST's
        # /var/lib/nixos-containers/arr/tmp/ is invisible inside — and recyclarr
        # given a --config path that does not exist prints nothing and EXITS 0.
        #
        # Which is the part worth keeping, because it is not specific to that
        # mistake: this service fails by succeeding.  A missing config, a
        # duplicate instance name (see above), a bad template id — all of them
        # exit 0.  A green `systemctl list-timers` therefore proves nothing
        # about whether a sync happened.  The real check is the journal:
        #
        #   journalctl -u recyclarr | grep -E "Processing|Completed at"
        #
        # Their ABSENCE is the failure signal, not a non-zero status.
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
      # in docs/roadmap.md, where DynamicUser plus persistent state left a
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
      systemd.services.prowlarr.serviceConfig = {
        DynamicUser = lib.mkForce false;
        User        = "prowlarr";
        Group       = "prowlarr";

        # See the note on sonarr's StateDirectoryMode below — same tug-of-war,
        # same fix.  0755 from systemd on every start against 0700 from
        # tmpfiles on every deploy.
        StateDirectoryMode = "0700";

        # Restoring what DynamicUser=true had been implying.
        NoNewPrivileges  = true;
        PrivateTmp       = true;
        ProtectSystem    = "strict";
        ProtectHome      = true;
        RemoveIPC        = true;
        RestrictSUIDSGID = true;

        # The rest of the servarr set, which upstream applies to sonarr and
        # radarr but not to prowlarr.
        CapabilityBoundingSet   = "";
        PrivateDevices          = true;
        PrivateUsers            = true;
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
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@debug"
          "~@mount"
          "@chown"
        ];
      };

      # SONARR / RADARR — upstream is already thorough (CapabilityBoundingSet="",
      # NoNewPrivileges, ProtectHome/Clock/Hostname/Proc, ProtectKernel*,
      # PrivateTmp, PrivateDevices, PrivateUsers, RestrictAddressFamilies,
      # RestrictNamespaces, RestrictRealtime, LockPersonality,
      # SystemCallArchitectures, SystemCallFilter, RemoveIPC, RestrictSUIDSGID).
      # Two things are changed, and only two.
      #
      # 1. ProtectSystem = "strict".  Upstream sets nothing at all, so the whole
      #    filesystem is writable to the extent the uid allows.  strict makes
      #    everything read-only except the listed paths, /dev, /proc and /sys.
      #
      #    The enumeration: /srv/media (the library and the download tree) and
      #    the service's own state directory.  Sonarr's state dir is covered
      #    implicitly by StateDirectory=sonarr and Radarr has no StateDirectory
      #    at all, but both are listed explicitly — belt and braces costs
      #    nothing and makes the set readable without cross-referencing the
      #    upstream module.  $HOME is inside the state dir (the module sets
      #    home = dataDir) and PrivateTmp covers /tmp and /var/tmp.
      #
      #    IF THIS FAILS TO START with "Read-only file system" after the first
      #    deploy, the fix is to add the path it names to ReadWritePaths, or to
      #    drop to ProtectSystem = "full" (which only protects /usr, /boot and
      #    /etc and needs no enumeration).  It is called out because this could
      #    not be tested before deploying — Claude does not deploy — and a loud,
      #    pre-diagnosed failure is worth more than an untightened unit.
      #
      # 2. UMask = "0002", down from upstream's 0022.
      #
      #    Be precise about what this does and does not do, because M3's header
      #    makes a stronger claim for the same setting and the reason is
      #    different there.  A HARDLINKED import does not depend on it at all:
      #    the link shares qBittorrent's inode and therefore its 0664 mode, and
      #    the write bit that fs.protected_hardlinks demands is on the SOURCE
      #    file, which qBittorrent already sets correctly.  What 0002 changes is
      #    everything the *arr creates fresh — series and season directories,
      #    .nfo files, artwork, and any import that copies rather than links
      #    (a different filesystem, a torrent still seeding under a lock).  At
      #    0022 those land 0755/0644 owned by sonarr, i.e. writable by exactly
      #    one uid, and the next member of `media` that needs to move or replace
      #    one — Radarr reorganising a mixed folder, qBittorrent cleaning up,
      #    whatever M9 turns out to be — fails with EACCES on a tree that looks
      #    fine.  0002 keeps the group able to manage what the group can see,
      #    which is the property the setgid bit on those directories exists to
      #    provide and which 0022 quietly cancels.
      #
      # REJECTED, with reasons, so nobody re-tries them blindly:
      #
      #   MemoryDenyWriteExecute = true
      #     All three are .NET.  The JIT maps writable-then-executable pages;
      #     the service starts and then dies on the first request.  The same
      #     rejection is recorded in containers/jellyfin.nix for the same
      #     runtime.
      #   IPAddressAllow/IPAddressDeny
      #     Prowlarr must reach arbitrary indexers and Sonarr/Radarr must reach
      #     TheTVDB/TMDB, so the allow-list would be "the internet".  The
      #     inbound half is the container firewall's job and the cross-VLAN half
      #     is the UDM-Pro's.
      #   ProtectSystem = "strict" on prowlarr WITH DynamicUser left on
      #     Not a rejection of strict — see the prowlarr block above, where it
      #     is enabled.  What is rejected is keeping DynamicUser to get it for
      #     free, which is what put the state directory under /var/lib/private
      #     in the first place.
      #   ReadOnlyPaths = [ "/srv/media/torrents" ]
      #     Tempting — the *arr should only ever read from the download tree —
      #     and wrong: "Completed Download Handling" removes the torrent's copy
      #     after a successful import, and the *arr also writes its own
      #     .nfo/metadata next to files it links.  Read-only here turns a
      #     working import into a disk that fills up.
      # mkForce on UMask only: both modules set it to "0022" as a plain
      # definition, so a second plain definition is a merge conflict rather than
      # an override.  ProtectSystem and ReadWritePaths are unset upstream and
      # need no priority bump.
      systemd.services.sonarr.serviceConfig = {
        ProtectSystem  = "strict";
        ReadWritePaths = [ "/srv/media" "/var/lib/sonarr" ];
        UMask          = lib.mkForce "0002";

        # Stops a mode tug-of-war, which is the M3 lesson in a new place.
        #
        # sonarr and prowlarr carry StateDirectory=, whose StateDirectoryMode
        # defaults to 0755 and is RE-APPLIED on every service start.  The host
        # tmpfiles rule above declares 0700 and is re-applied on every
        # `clan machines update`.  So the two took turns: 0700 after a deploy,
        # 0755 after the next restart, neither wrong enough to notice.  First
        # observed on ernst 2026-08-21 — sonarr and prowlarr on disk as 0755
        # while this file said 0700, and radarr (no StateDirectory) correctly
        # at 0700.
        #
        # Pinning it here makes systemd agree with tmpfiles rather than
        # alternate with it.  Radarr needs no equivalent: it has no
        # StateDirectory, so nothing competes.
        StateDirectoryMode = "0700";
      };
      systemd.services.radarr.serviceConfig = {
        ProtectSystem  = "strict";
        ReadWritePaths = [ "/srv/media" "/var/lib/radarr" ];
        UMask          = lib.mkForce "0002";
      };

      # BAZARR — the M12 equivalent of the Prowlarr row, and worse to start
      # with.
      #
      # Upstream's module (nixos/modules/services/misc/bazarr.nix) sets Type,
      # User, Group, SyslogIdentifier, ExecStart, Restart, KillSignal and
      # SuccessExitStatus.  That is the complete list.  There is NO hardening
      # of any kind — not a reduced set like prowlarr's, not a partial one:
      # none.  So everything below is ours, and unlike prowlarr there is no
      # "restoring what DynamicUser had been implying" to do, because upstream
      # never had DynamicUser either.
      #
      # The set is deliberately the same one sonarr and radarr get, because
      # Bazarr is the same kind of thing: a Python/.NET-adjacent web service
      # that reads and writes the library as group `media` and talks to
      # subtitle providers over HTTPS.
      #
      # ReadWritePaths is /srv/media AND its state directory, and /srv/media
      # is not narrowable to the library: Bazarr also reads from the download
      # tree when it grabs subtitles for something mid-import, and the "sync
      # subtitles" feature rewrites files in place.
      #
      # NOT PrivateUsers, for the reason cleanuparr's block gives: it would
      # squash a supplementary group, and here `media` is primary anyway — but
      # adding it would buy nothing and would make the primary-group choice
      # load-bearing in a second place.
      #
      # NOT MemoryDenyWriteExecute — Bazarr is Python and its native
      # extensions map writable-then-executable pages, the same rejection this
      # file already records for the three .NET services.
      systemd.services.bazarr.serviceConfig = {
        NoNewPrivileges  = true;
        PrivateTmp       = true;
        ProtectSystem    = "strict";
        ProtectHome      = true;
        RemoveIPC        = true;
        RestrictSUIDSGID = true;

        ReadWritePaths = [ "/srv/media" "/var/lib/bazarr" ];

        # Group-writable sidecars.  A .srt that only bazarr can replace is a
        # .srt nothing else can clean up, on a tree whose whole point is that
        # `media` can manage it.  Same argument as sonarr/radarr, and here it
        # applies to the PRIMARY artefact rather than to incidental metadata.
        UMask = "0002";

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
      };

      # `curl` is the test plan's instrument: it is what proves this container
      # can reach the download client's API at 10.0.90.11:8080 over br0 without
      # the UDM-Pro being involved, and what checks each web UI answers on
      # localhost before any firewall is in the picture.  Nothing else is added.
      environment.systemPackages = with pkgs; [ curl ];
      documentation.enable       = false;
      documentation.nixos.enable = false;
    };
  };
}
