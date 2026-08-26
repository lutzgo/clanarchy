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
  ];

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
      networking.firewall.allowedTCPPorts = [ ];
      networking.firewall.extraCommands = lib.concatMapStrings (port: ''
        iptables -A nixos-fw -p tcp -s ${traefikAddr}/32 --dport ${toString port} -j nixos-fw-accept
      '') [
        prowlarrPort
        sonarrPort
        radarrPort
        bazarrPort
        cleanuparrPort
        mediathekarrDownloaderPort
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
      # ── THE TRAP THAT MATTERS, restated where it will be read ────────────
      #
      # EVERY INDEXER URL IN PROWLARR MUST CHANGE https → http so that this can
      # intercept locally; the outbound leg to the real indexer stays https.
      # AN INDEXER LEFT ON https WORKS FINE AND SILENTLY BYPASSES THIS ENTIRELY
      # — nothing breaks, nothing logs, and the umlaut handling this service
      # exists for simply does not happen for that indexer.  It is the third
      # documented fails-by-succeeding in this repo, alongside recyclarr's
      # duplicate-instance bug and M11's silent context truncation.  The PR
      # body lists every indexer explicitly for that reason.
      #
      # Configure it in PROWLARR, not per-arr: per-arr configuration costs a
      # speed penalty on multi-indexer search.
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
          SystemCallFilter = [ "@system-service" "~@privileged" "~@debug" "~@mount" ];
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
          SystemCallFilter        = [ "@system-service" "~@privileged" "~@debug" "~@mount" ];

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
      #   mediathekarr-indexer     5008   Newznab shim, parses MediathekViewWeb.
      #                                   This is what PROWLARR is pointed at.
      #   mediathekarr-downloader  5007   SABnzbd shim + the setup WIZARD.
      #                                   This is what SONARR and RADARR add as
      #                                   a download client.
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
          SystemCallFilter        = [ "@system-service" "~@privileged" "~@debug" "~@mount" ];
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
          SystemCallFilter        = [ "@system-service" "~@privileged" "~@debug" "~@mount" ];
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
          SystemCallFilter        = [ "@system-service" "~@privileged" "~@debug" "~@mount" ];

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
              echo "Radarr__0__Enabled=true"
              echo "Radarr__0__Name=Radarr"
              echo "Radarr__0__Host=http://localhost:${toString radarrPort}"
              echo "Radarr__0__ApiKey=$(${pkgs.coreutils}/bin/cat ${arrSecretsDir}/radarr-api-key)"
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
        SystemCallFilter        = [ "@system-service" "~@privileged" "~@debug" "~@mount" ];
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
