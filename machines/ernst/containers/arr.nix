# machines/ernst/containers/arr.nix
#
# Prowlarr + Sonarr + Radarr, in one declarative systemd-nspawn NixOS container.
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

  # Host state sources.  Bound to the upstream default paths inside.
  stateRoot = "/srv/state";
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
  ];

  # The media tree itself is NOT declared here.  containers/jellyfin.nix owns
  # those tmpfiles rules (library/{movies,tvshows}, torrents/{movies,tv}) and
  # microvms/wg-qbittorrent.nix owns torrents/{incomplete,complete}.  A second
  # set of rules for the same paths is precisely the failure M3 spent a round
  # on: tmpfiles enforces mode and ownership on EVERY run, so two declarations
  # that disagree take turns winning, silently, one per deploy.

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
      networking.firewall.allowedTCPPorts = [ prowlarrPort sonarrPort radarrPort ];

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
      # Hardening.
      #
      # MEASURED, not asserted.  `systemd-analyze security --offline=true
      # --root=<container toplevel>/etc/systemd/system` scores the units this
      # file actually generates, which is how these can be checked before a
      # deploy rather than after one:
      #
      #   service       upstream directives   this file
      #   prowlarr      8.2 EXPOSED           1.3 OK
      #   sonarr        1.5 OK                1.3 OK
      #   radarr        1.5 OK                1.3 OK
      #   flaresolverr  3.0 OK                3.0 OK  (upstream, untouched)
      #
      # FlareSolverr is left exactly as upstream ships it, and its 3.0 is the
      # honest price of what it does: RestrictNamespaces has to permit `user`
      # so Chromium can build its own sandbox, and tightening that would
      # replace a browser sandbox with a systemd one — a worse trade. Its
      # confinement comes from DynamicUser and from NOT being in group media,
      # not from these directives.
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
