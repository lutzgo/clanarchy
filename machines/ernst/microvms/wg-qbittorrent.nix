# machines/ernst/microvms/wg-qbittorrent.nix
#
# qBittorrent behind a commercial WireGuard VPN, in a microvm with a real
# killswitch.  M3 in docs/roadmap.md.
#
# Why a microvm and not an nspawn container:
#   Architecture invariant #1 puts a workload in a VM — its own kernel — when it
#   talks to the open internet on its own behalf.  This is the only such
#   workload on ernst: it accepts connections from arbitrary BitTorrent peers
#   and runs a protocol stack against them.  Jellyfin and the arr suite are
#   trusted and storage-heavy, so they stay in nspawn on the shared kernel; a
#   kernel-level escape from libtorrent must not land on the host that owns
#   zdata.
#
# ── The killswitch is nftables, not the routing table ─────────────────────────
#
#   Both halves exist and they do different jobs:
#
#     ROUTING (wg-quick's automatic policy routing) decides where packets try
#     to go.  It is a correctness mechanism and it fails open — delete wg0 and
#     the default route reverts to the LAN.
#
#     NFTABLES decides what is allowed to leave.  Output policy is `drop` on
#     the LAN interface with exactly three exceptions: the encrypted tunnel to
#     the provider's endpoint, DHCPv4, and replies to management-network
#     connections.  Everything else — trackers, peers, DNS — is only reachable
#     via `oifname "wg0"`.  When wg0 disappears, so does the only path out.
#
#   That ordering matters: the firewall is loaded by nftables.service, which is
#   `before network-pre.target`, so the guest is fail-closed from before it has
#   an address, not from whenever the tunnel first comes up.
#
#   DNS RESOLVES IN-TUNNEL ONLY.  The guest runs no resolver of its own,
#   networkd is told `UseDNS=false`, and /etc/resolv.conf is written by
#   wg-quick from the DNS= line in the (secret) tunnel config.  A killswitch
#   that blocks packets but leaks names to the LAN resolver is not a
#   killswitch.
#
#   THE ENDPOINT MUST BE AN IP LITERAL, and the vars generator enforces it.
#   wg-quick resolves a hostname endpoint using the guest's resolver — which is
#   in-tunnel, which does not exist until the handshake completes, which needs
#   the endpoint.  A hostname there does not fail loudly; it fails at every
#   boot, forever.
#
# ── Exposure: the WebUI is a deliberate, permanent Traefik bypass ─────────────
#
#   Architecture invariant #4 names this one explicitly.  The WebUI is reachable
#   from the management networks only (LAN 10.0.10.0/24 and Servers
#   10.0.50.0/24), enforced twice: guest-side nftables here, and a ZBF rule on
#   the UDM-Pro.  It gets NO Traefik route, ever — not in M5, not in M7.  A
#   torrent client's admin surface does not belong on a name that resolves for
#   the household, and forward-auth in front of its API would break the arr
#   integration M4 builds.  Do not "fix" this.
#
#   M4 ADDED A THIRD SOURCE, and it is enforced in exactly one place.  The arr
#   container (10.0.90.13, machines/ernst/containers/arr.nix) drives this
#   client's API, and it sits on VLAN 90 — the same VLAN, on the same bridge, as
#   this guest's own tap.  Those frames are switched by br0 and never reach the
#   UDM-Pro, so the "enforced twice" above is NOT true of that source: the
#   nftables `api_clients` set below is the only thing standing between the arr
#   and the WebUI.  It gets the API port and nothing else — no SSH, no ping —
#   which is why the sets are a pair rather than one widened list.
#
# ── uid/gid: the decision the whole media stack rests on ──────────────────────
#
#   virtiofsd runs WITHOUT id translation (no --translate-uid/--translate-gid),
#   so numeric ids pass through the share unchanged in both directions: guest
#   uid 3001 IS host uid 3001.  Everything below follows from that.
#
#     uid 3001  qbittorrent     allocated here (see the id table in
#                               machines/ernst/networking.nix's MAC block for
#                               the sibling convention)
#     uid 3024  slskd           M14.  Same rule, same reason — see the M14
#                               section below
#     gid 3000  media           fixed on the host in containers/jellyfin.nix;
#                               restated in the guest, and it MUST match
#                               numerically or every file the guest writes
#                               lands in a group the host cannot name
#
#   media is qbittorrent's PRIMARY group, not a supplementary one.  Upstream's
#   unit sets PrivateUsers=true, which maps only User= and Group= into the
#   service's user namespace; a supplementary membership would be squashed to
#   nogroup inside it and every write would land root-less.
#
#   UMask=0002 is load-bearing, and this is the failure M4 exists to catch.
#   The download directories are setgid (2770 root:media) so new files inherit
#   gid media whatever the process's umask — but the systemd default umask 0022
#   would still make them mode 0644, i.e. group-READ only.  fs.protected_hardlinks
#   is 1 (kernel default) and refuses `link()` on a file you do not own unless
#   you have read AND WRITE on it.  The M4 arr stack runs host-side as a
#   different uid in group media, so with 0644 every import would fail to
#   hardlink and silently fall back to copying — which is exactly the failure
#   that fills a 6-wide raidz1 twice over.  0002 gives 0664 and the link
#   succeeds.  The PR test plan proves this with `stat` rather than assuming it.
#
# ── M14: slskd, AND WHY IT IS THE SECOND OCCUPANT OF THIS GUEST ─────────────
#
#   Soulseek is peer-to-peer on the open internet on ernst's behalf, which is
#   the exact test invariant #1 applies: a workload that talks to the internet
#   on its own behalf goes one tier up, into the microvm that already carries
#   the killswitch and the exit.  So slskd lands HERE and not in the arr
#   container, while Soularr — which only drives slskd's REST API and never
#   speaks Soulseek — stays in the container.
#
#   THE PLACEMENT WAS MEASURED BEFORE IT WAS COMMITTED, as M14 requires.  The
#   recorded counter-argument is that Soulseek connectivity through a shared
#   commercial VPN exit can be poor, and that this exit is Leaseweb NL — which
#   M4 measured as legally blocked by at least one indexer (HTTP 451).  From
#   inside this guest on 2026-08-28:
#
#     curl https://api.ipify.org        →  95.211.172.88   (Leaseweb NL)
#     TCP connect vps.slsknet.org:2271  →  OPEN
#
#   So the transport is not blocked and the placement stands.  What that does
#   NOT prove is PEER connectivity — whether enough peers accept connections
#   from this exit to make searches useful — and that cannot be measured
#   without the service running.  It is the go/no-go in the PR test plan, and
#   the documented fallback if it fails is the arr container WITH THE TRADEOFF
#   WRITTEN DOWN: a deliberate tier violation with a stated reason, never a
#   silent move.
#
#   UMask=0002 APPLIES TO slskd TOO, AND UPSTREAM DOES NOT SET IT.  This is the
#   single most important line in M14 and it is worth being blunt: the nixpkgs
#   slskd module's unit sets LockPersonality, NoNewPrivileges, PrivateUsers,
#   ProtectSystem=strict and a dozen more — and NO UMask at all.  It therefore
#   inherits systemd's 0022, writes 0644 files, and every Lidarr import would
#   fail to hardlink and silently fall back to copying.
#
#   That is not a prediction.  Measured on ernst 2026-08-28, in a 2770
#   root:media directory on zdata/media, with fs.protected_hardlinks = 1:
#
#     file written as uid 3024 with umask 0002  →  0664, links=1
#     linked as uid 3017 (lidarr) in group media →  LINK OK, one inode, links=2
#     same file chmod 0644, linked again        →  EPERM
#
#   The third step is the negative control and it is what makes the first two
#   mean anything: without it the test cannot tell a working chain from root
#   bypassing the check.  M3's own first draft made exactly that mistake, and
#   it is the same failure class as M11's grader bug (roadmap standing note
#   SN3) — a broken instrument is indistinguishable from a good result.
#
#   The override is applied in the slskd block below, and M14 owes its own
#   proof rather than inheriting M3's because this is a SECOND WRITE PATH into
#   /srv/media by a different service with a different umask.
#
# ── virtiofs, not 9p ─────────────────────────────────────────────────────────
#
#   Decided on hardlink and ownership fidelity, as M3 instructed — not on
#   throughput, though virtiofs wins there too.
#
#     9p's security models are disqualifying, not merely slow.  `mapped` and
#     `mapped-file` store ownership in xattrs or a side file, so a file the
#     guest writes appears on the host as the virtfs process's uid.  That
#     breaks the identity mapping above at the root, and with it every
#     host-side hardlink.  `passthrough` preserves ids but is documented as
#     unreliable for exactly the metadata operations that matter here.
#
#     virtiofsd passes uid/gid through unmodified and implements link(),
#     rename() and the rest with full POSIX semantics, which is what qBittorrent
#     needs for its own incomplete → complete moves and what M4 needs for the
#     import.
#
#   ZFS CAVEAT — posixAcl = false on every share.  microvm.nix passes
#   `--posix-acl --xattr` by default, and its own documentation notes that a
#   ZFS-backed share then requires `xattr=sa` + `acltype=posixacl` on the
#   dataset.  Neither zroot nor zdata/{media,state} sets either (see
#   machines/ernst/disko.nix — only zdata/{unsorted,gardens} carry acltype).
#   Nothing here wants POSIX ACLs, so the flag is switched off rather than the
#   pool properties changed.
#
# ── Where the download tree lives ────────────────────────────────────────────
#
#   M3's prompt said /srv/media/downloads.  The deployed tree says
#   /srv/media/torrents: containers/jellyfin.nix already creates
#   torrents/{movies,tv} root:media 2770 beside library/{movies,tvshows}.
#   Inventing a fourth top-level directory would have split the download area
#   in two.  This file adds only the two directories the client itself needs:
#
#     /srv/media/torrents/incomplete   in-progress writes (Session\TempPath)
#     /srv/media/torrents/complete     default save path for uncategorised
#
#   CORRECTION, measured 2026-08-21 during M4: the sentence that used to sit
#   here — "torrents/{movies,tv} … are the directories M4's arr will import
#   FROM" — is WRONG, and it was an inference, not an observation.  qBittorrent
#   derives a per-category save path automatically, `<DefaultSavePath>/<category>`,
#   whenever a category's own save path is left blank.  Sonarr and Radarr create
#   their categories over the API without one, so the real tree is:
#
#     /srv/media/torrents/complete/tv        Sonarr's category
#     /srv/media/torrents/complete/radarr    Radarr's category
#     /srv/media/torrents/incomplete/<cat>   in-progress
#
#   torrents/{movies,tv} are empty and vestigial.  They are left declared
#   because deleting a tmpfiles rule does not delete the directory and the
#   churn buys nothing — but do not write anything expecting to find files
#   there.  Setting explicit category save paths to "fix" this is a trap while
#   torrents are in flight: qBittorrent's default reaction to a changed
#   category save path is to switch affected torrents to Manual Mode, pinning
#   the existing ones where they are and sending only new ones to the new path,
#   i.e. splitting the tree the change was meant to tidy.
#
#   None of it matters for hardlinks, which is the point worth keeping: the
#   domain is the DATASET (invariant #2), not the directory layout, so the
#   M4 import linked across complete/tv → library/tvshows with links=2 exactly
#   as designed.
#
#   Both inside /srv/media, which is ONE hardlink domain — plain subdirectories,
#   never sub-datasets (invariant #2).
#
# ── State, and what survives a rollback ──────────────────────────────────────
#
#   The guest is STATELESS.  Root is a tmpfs, /nix/store is a read-only share of
#   the host's, and there is no volume: everything that must survive is a share
#   of a zdata path.
#
#     /srv/state/qbittorrent  → /var/lib/qBittorrent   (profile, torrent state)
#     /srv/media/torrents     → same path in the guest  (the data)
#
#   /var/lib/microvms is deliberately NOT persisted, and that is not an
#   oversight.  For a fully-declarative VM, install-microvm-wg-qbittorrent.service
#   is wantedBy microvms.target (→ multi-user.target) and rewrites the state
#   directory's symlinks from the store on every boot, so the zroot rollback
#   has nothing to lose.  Persisting it would freeze a stale `current` symlink
#   across a redeploy — the opposite of what it looks like it does.
#
# ── Side effects of importing microvm.nixosModules.host, checked ─────────────
#
#   1. boot.kernelModules gains "tap" and "vhost_net" host-wide.  Wanted.
#   2. hardware.ksm.enable is mkDefault true.  Turned off below: with one small
#      guest there is nothing for ksmd to merge against on a 256 GB host.
#   3. environment.etc."qemu/bridge.conf" is set to `allow all` — with
#      lib.mkDefault, and modules/virtualisation.nix already enables libvirtd,
#      whose own module sets that file from allowedBridges (default virbr0) as a
#      plain definition.  libvirtd wins; the setuid qemu-bridge-helper is NOT
#      widened to br0.  Checked, because "allow all" in front of a
#      VLAN-filtering bridge would have been a real hole.
#   4. A `microvm` system user (group kvm) with memlock unlimited.  Required —
#      microvm@ runs unprivileged as that user.
#
#   The host module is imported from flake.nix, beside this file, and NOT with
#   an `imports = [ inputs.microvm.nixosModules.host ]` here.  `inputs` reaches
#   a machine module through _module.args, and reading _module.args from
#   `imports` is an infinite recursion — the module system has to know the
#   import list before it can compute the arguments.
{ config, lib, pkgs, ... }:
let
  vmName  = "wg-qbittorrent";

  # Host-side tap.  The name matters twice: machines/ernst/networking.nix
  # already lists "interface-name:tap-*" as NetworkManager-unmanaged, and the
  # networkd unit below matches it.
  tapName = "tap-vpn";

  # Guest-side MAC — 02:00:00:<vlan>:00:<seq>, allocated in the table in
  # machines/ernst/networking.nix.  This is the address the UDM-Pro sees and
  # the one the DHCP reservation keys on; never the host-side tap.
  guestMac = "02:00:00:90:00:03";
  vlanId   = 90;

  qbtUid   = 3001;
  mediaGid = 3000;

  webuiPort   = 8080;
  torrentPort = 6881;

  # ── M14: slskd ────────────────────────────────────────────────────────────
  #
  # uid 3024, reserved for this service in machines/ernst/networking.nix and
  # reserved THERE rather than here for the reason that file gives: the number
  # is a number on zdata, so it is allocated centrally and not by whichever
  # module happens to create the user first.
  slskdUid = 3024;

  # Upstream defaults, restated because three things have to agree: the
  # module's own settings, this guest's nftables ruleset, and Soularr's
  # config.ini over in containers/arr.nix.
  #
  #   5030   the web UI and the REST API.  Reached from the management VLANs
  #          (a human) and from the arr container (Soularr).
  #   50300  the Soulseek LISTEN port — incoming peer connections.  It belongs
  #          on wg0 ONLY, exactly like qBittorrent's torrentPort, and for the
  #          same reason: an incoming peer connection arriving on eth0 would be
  #          a peer that found this host at its real address.
  slskdWebPort    = 5030;
  slskdListenPort = 50300;

  # slskd's download tree, and it is a SIBLING of downloadRoot rather than a
  # subdirectory of it.
  #
  # Both are inside /srv/media, which is what matters for hardlinks — the
  # domain is the DATASET (invariant #2), not the directory layout.  They are
  # kept apart because Cleanuparr and the *arr recycle-bin logic both treat
  # everything under torrents/ as qBittorrent's, and because "which client
  # wrote this" is a question someone will ask of a stuck file at 0200.
  soulseekRoot = "/srv/media/soulseek";

  # State, on zdata beside qBittorrent's (invariant #7).  Mounted at the
  # module's own StateDirectory path so the packaged unit needs no override.
  slskdStateSource = "/srv/state/slskd";

  # M13.  prometheus-qbittorrent-exporter's own default port, and the
  # monitoring container's address on VLAN 90 (M6, 02:00:00:90:00:06).
  #
  # The exporter lives INSIDE this guest rather than beside Prometheus, and
  # that placement is the interesting part: it reads qBittorrent's WebUI API,
  # which is exactly the interface this file spends 200 lines restricting.
  # Running it here means the API conversation never leaves the guest — the
  # exporter talks to 127.0.0.1 — and only the aggregate metrics cross the
  # wire.  An exporter in the monitoring container would have needed the WebUI
  # API opened to a third client and the plaintext password staged there too.
  #
  # It is also inside the killswitch, which is the right side of it: the
  # exporter has no reason to reach the internet, and the output chain below
  # gives it no way to.
  exporterPort   = 8000;
  monitoringAddr = "10.0.90.14";

  downloadRoot = "/srv/media/torrents";
  stateSource  = "/srv/state/qbittorrent";

  # Management networks allowed to reach the WebUI and SSH.  LAN (1) is where
  # lgo's machines live; Servers (50) is ernst itself, so a port-forward from
  # the host works without a second hop.
  #
  # These are the OFF-LINK sources, and that is what earns them a route.  Both
  # are on the far side of the UDM-Pro, so a reply to one has to be steered out
  # of eth0 explicitly or wg-quick's `suppress_prefixlength 0` sends it into the
  # tunnel — the failure written up at length at the routes = ... below.
  mgmtNets = [ "10.0.10.0/24" "10.0.50.0/24" ];

  # M4: the arr container, on the guest's OWN link (VLAN 90).  Sonarr and Radarr
  # drive qBittorrent through its WebUI API, so this address needs the two
  # firewall entries mgmtNets gets — the input accept, and the established-reply
  # accept in the output chain that keeps the answer off the tunnel.
  #
  # IT MUST NOT GET A ROUTE, which is why this is a second list rather than two
  # more elements in the first.  10.0.90.0/24 is directly connected on eth0, so
  # main already holds a /24 for it; that route is prefix length 24 and
  # therefore survives wg-quick's suppress_prefixlength 0 untouched.  Adding
  # `10.0.90.13/32 via <dhcp gateway>` on top would take traffic that belongs on
  # the wire and hand it to the UDM-Pro to bounce back — a hairpin, for a
  # neighbour two ports away on the same bridge.
  #
  # It is also why M4 needs no UDM-Pro rule for this path at all: vb-arr and
  # tap-vpn are both VLAN-90 ports on br0, so the frames are switched locally
  # and the gateway never sees them.
  #
  # A /32, not the /24.  The Services VLAN also holds Jellyfin and will hold
  # Traefik; neither has any business reaching a torrent client's API.
  #
  # M14 hoisted the bare address out of the list: slskd's CIDR-scoped API key
  # needs the same address in a different syntax, and two literals for one host
  # is how they drift apart.
  arrAddr   = "10.0.90.13";
  arrClient = [ "${arrAddr}/32" ];

  # The union, and it has exactly TWO consumers: the input chain's WebUI accept
  # and the output chain's established-reply accept.  That coupling is the point
  # — the set of sources whose traffic may come IN is exactly the set whose
  # replies must be allowed back OUT rather than into the tunnel, so one list
  # feeding both cannot drift.  M3 stated this as "one list, three consumers";
  # the third was the routing carve-out, which now belongs to mgmtNets alone for
  # the reason given just above.
  #
  # The UDM-Pro rule is the consumer that cannot be derived from here.  It
  # covers mgmtNets only — the arr's half never reaches the gateway — and has to
  # be kept in step by hand.
  allowedClients = mgmtNets ++ arrClient;

  # Secrets are staged out of sops into a host tmpfs directory and shared into
  # the guest read-only.  NOT a share of /run/secrets itself: that path is a
  # symlink to a per-generation directory which is replaced on every deploy, so
  # a running virtiofsd would keep serving a deleted generation.  A directory
  # we own has a stable identity and is rewritten in place.
  hostSecretsDir  = "/run/microvm-${vmName}-secrets";
  guestSecretsDir = "/run/wg-secrets";

  gen = config.clan.core.vars.generators.wg-qbittorrent;

  # M13.  The WebUI password lives in its own generator so that adding the
  # plaintext did not mark `wg-qbittorrent` missing and re-prompt every
  # WireGuard value — see the generator's own header for the full argument.
  webuiGen = config.clan.core.vars.generators.qbittorrent-webui;

  # M14.  slskd's credentials, in a THIRD generator for exactly the reason M13
  # split out the second one: adding files to an existing generator marks it
  # incomplete and re-prompts every value it already holds, and nobody wants to
  # re-enter a WireGuard private key to add a Soulseek password.
  #
  # Guarded rather than referenced directly, the same way containers/arr.nix
  # guards janitorr-jellyfin: naming a generator that does not exist yet is an
  # EVALUATION error, and an evaluation error names an attribute rather than
  # the thing a human forgot to run.  With the guard, a machine whose
  # `clan vars generate ernst` has not been run yet still evaluates and the
  # failure moves to the staging unit, where the message can say what to do.
  #
  # UNLIKE janitorr's, though, this one IS fatal to the guest: the staging unit
  # is requiredBy microvm@, so a missing var means no VM rather than a VM with
  # a broken service.  That is deliberate and matches the WireGuard secrets
  # beside it — slskd with no Soulseek credentials cannot connect at all, and a
  # guest that starts anyway would just be a quieter failure.
  slskdGen =
    if config.clan.core.vars.generators ? slskd-credentials
    then config.clan.core.vars.generators.slskd-credentials
    else { files."slskd.env".path = "/no-such-path"; };

  # qBittorrent.conf, with the WebUI password hash left as a placeholder that
  # the guest substitutes at start.  The ExecStartPre that renders it carries
  # the reasoning: why the whole file is declarative, and what that costs.
  #
  # ── DO NOT AUTHENTICATE THE *ARR WITH qBITTORRENT'S API KEY ──────────────────
  #
  #   qBittorrent's WebUI has an "API Key" field (Options → WebUI →
  #   Authentication) and recent Sonarr/Radarr offer it as an alternative to
  #   username+password.  Using it here is a trap, and it cost a session:
  #
  #     The generated key is stored in qBittorrent.conf.  This file is
  #     REINSTALLED FROM THE STORE ON EVERY START.  So the key survives exactly
  #     until the next restart — a deploy, or in the case that found this, a
  #     power cut — and then it is gone.  The *arr keeps sending a key
  #     qBittorrent no longer knows.
  #
  #   The failure is silent in the worst way: the request is rejected BEFORE the
  #   login path, so qBittorrent's own log records nothing at all — no failure
  #   line, no IP, no username.  Sonarr says only "Failed to authenticate with
  #   qBittorrent"; the API test is the thing that names it, reporting
  #   `propertyName: ApiKey`.  Observed on ernst 2026-08-21: after the outage
  #   both Sonarr and Radarr failed, while the arr container could still reach
  #   the WebUI (HTTP 403 in 0.5 ms) and qBittorrent's log held only browser
  #   logins from lgo's workstation.
  #
  #   USE USERNAME + PASSWORD.  `admin` plus the WebUI password is rendered from
  #   the clan var into the two lines below on every start, so it is the only
  #   credential here that is guaranteed to still be valid after a restart.
  #
  #   If API-key auth is ever actually wanted, the key has to become a clan var
  #   and be substituted into this template exactly as the password hash is —
  #   anything else is storing a secret in a file this unit overwrites.
  qbtConfTemplate = pkgs.writeText "qBittorrent.conf" ''
    [LegalNotice]
    Accepted=true

    [BitTorrent]
    Session\DefaultSavePath=${downloadRoot}/complete
    Session\TempPath=${downloadRoot}/incomplete
    Session\TempPathEnabled=true
    Session\Interface=wg0
    Session\InterfaceName=wg0
    Session\Preallocation=true
    Session\QueueingSystemEnabled=false

    [Preferences]
    General\Locale=en
    WebUI\Address=*
    WebUI\Username=admin
    WebUI\Password_PBKDF2=@WEBUI_PASSWORD_PBKDF2@
    WebUI\LocalHostAuth=true
    WebUI\CSRFProtection=true
    WebUI\ClickjackingProtection=true
    WebUI\HostHeaderValidation=true
  '';
in
{
  ##############################################################################
  # Host side.
  ##############################################################################

  # See side-effect note 2 in the file header.
  hardware.ksm.enable = false;

  # Bind sources.  The two new directories are the client's own; the category
  # directories (torrents/movies, torrents/tv) already exist and are chowned
  # root:media 2770 by containers/jellyfin.nix, which owns those rules.
  #
  # 2770 = setgid + rwxrws---: new files inherit gid media, group members read
  # AND write (the arr must be able to hardlink and move), root owns.
  #
  # NOTE ON A DUPLICATE: microvm.nixosModules.host emits its own tmpfiles line
  # for every share source, in 10-microvm.conf.  systemd.tmpfiles.rules lands in
  # 00-nixos.conf, which sorts first and therefore wins; the microvm copy is
  # logged as a duplicate and ignored.  That ordering is why the modes here are
  # the ones that take effect and not microvm's :0775 microvm:kvm — do not
  # rename this into a higher-numbered settings file without rechecking.
  systemd.tmpfiles.rules = [
    "d ${downloadRoot}/incomplete 2770 root media -"
    "d ${downloadRoot}/complete   2770 root media -"
    "d ${stateSource}             0700 ${toString qbtUid} ${toString mediaGid} -"

    # ── M14: slskd ──────────────────────────────────────────────────────────
    #
    # Same 2770 root:media as qBittorrent's tree, and for the identical reason:
    # setgid so everything created inside inherits gid media, group-writable so
    # Lidarr (a different uid in group media) can hardlink out of it and remove
    # the source after a successful import.
    #
    # The modes here and slskd's UMask=0002 are the TWO halves of one property
    # and neither works alone — setgid fixes the group, the umask fixes the
    # group's write bit, and fs.protected_hardlinks needs both.  See the M14
    # section of the header for the measurement.
    "d ${soulseekRoot}            2770 root media -"
    "d ${soulseekRoot}/incomplete 2770 root media -"
    "d ${soulseekRoot}/complete   2770 root media -"

    "d ${slskdStateSource}        0700 ${toString slskdUid} ${toString mediaGid} -"
  ];

  ##############################################################################
  # Secrets: sops → a tmpfs directory → virtiofs → the guest.
  #
  # The guest cannot run sops-nix: it has no persistent state and no age key of
  # its own, and giving it one would put a fleet secret inside the machine whose
  # entire job is to face the internet.  So the host decrypts, and hands over
  # five files.
  #
  # `install -d` on the directory is not redundant.  microvm.nixosModules.host
  # emits a tmpfiles line for every share source, so this path would otherwise
  # be created 0775 microvm:kvm — and unlike the /srv paths above, there is no
  # 00-nixos.conf rule of ours to win the duplicate.  install -d applies mode
  # and ownership to an existing directory too, and it runs immediately before
  # virtiofsd, so the correction always lands.
  #
  # Modes are the interesting part:
  #   0400 root:root   wg0.conf, ssh_host_ed25519_key, endpoint-{ip,port}
  #                    — read by the guest's root (wg-quick, sshd, the nft
  #                    endpoint oneshot) and by nothing else.
  #   0440 root:media  webui-password-pbkdf2 — qBittorrent's own ExecStartPre
  #                    runs as qbittorrent:media and substitutes it into the
  #                    profile.  Group-readable so that step does NOT need a
  #                    `+`-prefixed root escape out of the unit's sandbox.
  #
  # GENERATE BEFORE YOU DEPLOY, and the reason is not politeness.  clan-core
  # cannot know a sops secret's path until the secret exists: until then
  # `files.<n>.path` evaluates to the literal "/no-such-path"
  # (clan-core nixosModules/clanCore/vars/secret/sops/default.nix), and that
  # string is what gets baked into the script below.  So a deploy that runs
  # before `clan vars generate ernst` produces a system whose staging unit can
  # never succeed, no matter how many times it is restarted — it has to be
  # rebuilt.  The failure is at least loud and fail-closed: this unit fails,
  # and microvm@ never starts.  No tunnel config means no VM, not a VM with no
  # tunnel.
  ##############################################################################
  systemd.services."microvm-secrets-${vmName}" = {
    description = "Stage clan-vars secrets for MicroVM '${vmName}'";
    after       = [ "local-fs.target" ];
    before      = [ "microvm-virtiofsd@${vmName}.service" "microvm@${vmName}.service" ];
    requiredBy  = [ "microvm@${vmName}.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # 0750 root:media, NOT 0700 root:root.  The WebUI hash below is
      # group-readable so qBittorrent's own ExecStartPre can read it without a
      # `+`-prefixed escape from the unit's sandbox — but a group-readable file
      # inside a group-untraversable directory is unreadable, which is exactly
      # the bug this deployed with: the render step silently substituted an
      # EMPTY password and the WebUI rejected every login with nothing in any
      # log to say why.  Group needs x on the directory, not just r on the file.
      ${pkgs.coreutils}/bin/install -d -m 0750 -o root -g media ${hostSecretsDir}
      ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
        ${gen.files."wg0.conf".path}             ${hostSecretsDir}/wg0.conf
      ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
        ${gen.files."endpoint-ip".path}          ${hostSecretsDir}/endpoint-ip
      ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
        ${gen.files."endpoint-port".path}        ${hostSecretsDir}/endpoint-port
      ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
        ${gen.files."ssh-host-key".path}         ${hostSecretsDir}/ssh_host_ed25519_key
      # Both WebUI password artefacts come from the `qbittorrent-webui`
      # generator, NOT from `gen` — see that generator for why it is separate.
      # The staged FILENAMES are unchanged, so nothing in the guest moved.
      ${pkgs.coreutils}/bin/install -m 0440 -o root -g media \
        ${webuiGen.files."password-pbkdf2".path} ${hostSecretsDir}/webui-password-pbkdf2

      # M13.  0400 root:root, NOT 0440 root:media like the hash above it.
      #
      # The distinction is the whole reason this is safe to add: the HASH is
      # group-readable because qBittorrent's own unprivileged ExecStartPre has
      # to substitute it into a config file.  The PLAINTEXT has no unprivileged
      # reader at all — the exporter receives it through LoadCredential=, which
      # PID 1 reads before dropping privileges.  If this ever needs to be 0440,
      # something has gone wrong with that design rather than with this mode.
      ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
        ${webuiGen.files."password".path}        ${hostSecretsDir}/webui-password

      # M14.  slskd's EnvironmentFile: Soulseek account, web UI login, and the
      # primary API key Soularr authenticates with.
      #
      # 0400 root:root, like the plaintext above it and unlike the pbkdf2 hash.
      # systemd's EnvironmentFile= is read by PID 1 BEFORE it drops to the
      # slskd uid, so no unprivileged process ever opens this file — the same
      # argument the qbit-exp LoadCredential note makes two lines up.  If this
      # ever needs to be group-readable, something has gone wrong with that
      # design rather than with this mode.
      ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
        ${slskdGen.files."slskd.env".path}        ${hostSecretsDir}/slskd.env
    '';
  };

  ##############################################################################
  # The tap: a VLAN-90 port on br0.
  #
  # THERE IS NO NETDEV HERE, and the worked example this replaces in
  # machines/ernst/networking.nix has been corrected to match.  microvm.nix
  # creates the tap itself, from the VM's own bin/tap-up
  # (`ip tuntap add … user microvm`), deleting and recreating it on every start.
  # A netdev unit would race that for ownership of the same name.
  #
  # Bridge=, not KeepMaster=.  This is the OPPOSITE of containers/jellyfin.nix
  # and the difference is real: nspawn enslaves its veth itself, out of band,
  # so networkd must be told to keep its hands off the master while still
  # applying [BridgeVLAN].  Nothing enslaves a microvm tap, so networkd does
  # both — which also means the VLAN race that file documents CANNOT occur
  # here, and no ExecStartPost backstop is needed.  Verify anyway with
  # `bridge vlan show dev tap-vpn`; the failure with DefaultPVID="none" is
  # fail-closed (no VLAN at all), not fail-open onto VLAN 50.
  ##############################################################################
  systemd.network.networks."60-${tapName}" = {
    matchConfig.Name = tapName;
    networkConfig = {
      Bridge              = "br0";
      LinkLocalAddressing = "no";
      IPv6AcceptRA        = false;
    };
    bridgeVLANs = [ { VLAN = vlanId; PVID = vlanId; EgressUntagged = vlanId; } ];
    linkConfig.RequiredForOnline = "enslaved";
  };

  ##############################################################################
  # Vars generator.
  #
  # Everything the tunnel needs is prompted, and the generator assembles a
  # complete wg-quick config rather than exporting the pieces for Nix to
  # reassemble.  Two reasons: the provider's peer material, address and
  # in-tunnel resolver are all credentials, so none of them may be committed;
  # and a single file keeps the provider's own downloaded config recognisable
  # when it is pasted in.
  #
  # endpoint-ip / endpoint-port are emitted separately because the killswitch
  # needs them at runtime, on the guest, before the tunnel exists — parsing a
  # secret at boot to find out what to allow is worse than being handed it.
  #
  # The SSH host key is generated here, not in the guest.  The guest's root is a
  # tmpfs: a self-generated host key would change on every boot and train
  # everyone to click through the warning that is supposed to mean something.
  ##############################################################################
  clan.core.vars.generators.wg-qbittorrent = {
    files."wg0.conf".secret              = true;
    files."endpoint-ip".secret           = true;
    files."endpoint-port".secret         = true;
    files."ssh-host-key".secret          = true;
    files."ssh-host-key.pub".secret      = false;

    prompts."private-key" = {
      description = "WireGuard PRIVATE key for this peer (from the VPN provider's config)";
      type        = "hidden";
    };
    prompts."peer-public-key" = {
      description = "WireGuard PUBLIC key of the provider's server";
      type        = "line";
    };
    prompts."endpoint" = {
      description = "Provider endpoint as IP:PORT — an IP LITERAL, not a hostname (e.g. 193.32.127.70:51820)";
      type        = "line";
    };
    prompts."address" = {
      description = "Tunnel address assigned by the provider, with prefix (e.g. 10.68.4.21/32)";
      type        = "line";
    };
    prompts."dns" = {
      description = "In-tunnel DNS server supplied by the provider (IVPN standard: 172.16.0.1)";
      type        = "line";
    };
    prompts."mtu" = {
      # Optional, and the only prompt that accepts an empty answer.
      #
      # wg-quick derives an MTU when the config does not set one: the egress
      # link's MTU minus 80, i.e. 1420 on ethernet.  Several providers ship a
      # LOWER value — IVPN's own guides say 1412 — and the difference does not
      # fail cleanly.  The handshake completes, `wg show` looks healthy, small
      # requests work, and transfers stall on the first full-size packet.  For
      # a torrent client that is the entire workload.
      #
      # Empty answer → no MTU line at all → wg-quick's derivation, which is the
      # right default for a provider that does not specify one.
      description = "MTU from the provider's config, or EMPTY for wg-quick's default (IVPN: 1412)";
      type        = "line";
    };
    # THE WebUI PASSWORD IS NOT PROMPTED HERE ANY MORE — see the
    # `qbittorrent-webui` generator below for where it went and why moving it
    # was not optional.

    runtimeInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.python3 pkgs.openssh ];

    script = ''
      set -euo pipefail

      priv=$(tr -d '[:space:]' < "$prompts/private-key")
      peer=$(tr -d '[:space:]' < "$prompts/peer-public-key")
      endpoint=$(tr -d '[:space:]' < "$prompts/endpoint")
      address=$(tr -d '[:space:]' < "$prompts/address")
      dns=$(tr -d '[:space:]' < "$prompts/dns")
      mtu=$(tr -d '[:space:]' < "$prompts/mtu")

      ##########################################################################
      # Validate EVERYTHING before doing any work, and report every problem in
      # one pass.
      #
      # clan collects all seven prompts and only then runs this script, so an
      # `exit 1` on the first bad value costs the operator every other answer
      # too.  The first version did exactly that and charged six correct
      # answers for one mistyped separator.  Accumulating the errors means one
      # re-run fixes everything, however many things are wrong.
      #
      # Validating here at all is the point of the exercise: every one of these
      # values fails LATE and QUIETLY otherwise — a bad key is "the handshake
      # never completes", a v6 address is "wg-quick aborts at every boot", a
      # hostname endpoint is "unresolvable, because the resolver is inside the
      # tunnel it is needed to build".  A human is watching exactly once.
      ##########################################################################
      fail=0
      err() { echo "  ✗ $*" >&2; fail=1; }

      # 32 bytes of base64 — every WireGuard key is 43 chars plus one '='.
      # Catches the truncated paste, which otherwise presents as a tunnel that
      # comes up and never handshakes.
      wgkey='^[A-Za-z0-9+/]{43}=$'

      valid_ipv4() {
        local ip="$1" octet
        printf '%s' "$ip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || return 1
        for octet in ''${ip//./ }; do
          [ "$octet" -le 255 ] || return 1
        done
      }

      # ── endpoint ────────────────────────────────────────────────────────────
      case "$endpoint" in
        *:*)
          ep_ip="''${endpoint%:*}"
          ep_port="''${endpoint##*:}"
          valid_ipv4 "$ep_ip" || err \
            "endpoint host '$ep_ip' is not an IPv4 literal. Resolve the provider's hostname yourself (dig +short <host>) and paste an address — the guest's only resolver is inside the tunnel this endpoint builds."
          printf '%s' "$ep_port" | grep -Eq '^[0-9]{1,5}$' || err \
            "endpoint port '$ep_port' is not a number."
          ;;
        *)
          ep_ip=""; ep_port=""
          err "endpoint '$endpoint' has no ':' before the port."
          err "  A dot instead of a colon is the usual slip: 1.2.3.4.51820 should be 1.2.3.4:51820."
          ;;
      esac

      # ── address ─────────────────────────────────────────────────────────────
      # IPv4 only, prefix optional (ip(8) assumes /32 for a bare IPv4).  A v6
      # component is rejected rather than carried: the guest sets
      # net.ipv6.conf.all.disable_ipv6, so wg-quick's `ip -6 address add` would
      # fail, and wg-quick runs under `set -e` — the tunnel would never come up,
      # at every boot, for a reason nothing states out loud.
      case "$address" in
        *,*|*:*)
          err "address '$address' looks dual-stack. Paste ONLY the IPv4 part: the guest has IPv6 disabled, and wg-quick aborts when 'ip -6 address add' fails."
          ;;
        */*)
          valid_ipv4 "''${address%/*}" || err "address '$address' is not an IPv4 address with a prefix."
          printf '%s' "''${address##*/}" | grep -Eq '^[0-9]{1,2}$' || err "address '$address' has a malformed prefix."
          ;;
        *)
          valid_ipv4 "$address" || err "address '$address' is not an IPv4 address."
          ;;
      esac

      # ── the rest ────────────────────────────────────────────────────────────
      valid_ipv4 "$dns" || err \
        "dns '$dns' is not an IPv4 address. IVPN: 172.16.0.1 plain, or one of the 10.0.254.x AntiTracker resolvers."
      printf '%s' "$peer" | grep -Eq "$wgkey" || err \
        "peer-public-key is not a 44-character WireGuard key — check for a truncated paste."
      printf '%s' "$priv" | grep -Eq "$wgkey" || err \
        "private-key is not a 44-character WireGuard key — check for a truncated paste."
      [ -z "$mtu" ] || printf '%s' "$mtu" | grep -Eq '^[0-9]{3,4}$' || err \
        "mtu '$mtu' is not a number (and may be left empty)."

      if [ "$fail" -ne 0 ]; then
        echo "" >&2
        echo "Nothing was written. Fix the above and re-run: clan vars generate ernst" >&2
        exit 1
      fi

      # No Table= line, deliberately: wg-quick's automatic policy routing
      # (fwmark + `suppress_prefixlength 0`) is what puts every non-tunnel
      # destination on wg0.  Setting Table= disables it.
      cat > "$out/wg0.conf" <<EOF
      [Interface]
      PrivateKey = $priv
      Address = $address
      DNS = $dns
      EOF

      # Omitted entirely when the prompt was left empty — an "MTU = " line is
      # not the same thing as no MTU line.
      if [ -n "$mtu" ]; then
        printf 'MTU = %s\n' "$mtu" >> "$out/wg0.conf"
      fi

      cat >> "$out/wg0.conf" <<EOF

      [Peer]
      PublicKey = $peer
      Endpoint = $endpoint
      AllowedIPs = 0.0.0.0/0
      PersistentKeepalive = 25
      EOF

      printf '%s' "$ep_ip"   > "$out/endpoint-ip"
      printf '%s' "$ep_port" > "$out/endpoint-port"

      ssh-keygen -t ed25519 -N "" -C "root@wg-qbittorrent" -f "$out/ssh-host-key" >/dev/null
    '';
  };

  ##############################################################################
  # M13 — the qBittorrent WebUI password, in a generator of its OWN.
  #
  # ── WHY IT IS NOT PART OF wg-qbittorrent ABOVE, WHERE IT LIVED ────────────
  #
  #   M13 needs a SECOND form of this password.  The exporter authenticates to
  #   the WebUI API as an ordinary client, so it has to PRESENT the password;
  #   a PBKDF2 verifier cannot be replayed as a credential.  The obvious change
  #   was to add one more `files."webui-password"` to the generator above.
  #
  #   THAT WOULD HAVE BEEN EXPENSIVE, AND SILENTLY SO.  clan decides whether to
  #   run a generator per GENERATOR, not per file — clan_lib/vars/graph.py:
  #   "A generator is missing if at least one of its files is missing."  So one
  #   new file in the generator above marks the WHOLE generator missing, and
  #   re-running it would have:
  #
  #     - re-prompted all SEVEN WireGuard values, i.e. required the IVPN
  #       private key, peer public key, endpoint, address, DNS and MTU to be
  #       typed in again from the provider's config;
  #     - regenerated wg0.conf from those answers;
  #     - MINTED A NEW SSH HOST KEY for the guest, because ssh-keygen runs
  #       fresh every time — so every known_hosts entry for it would break.
  #
  #   None of that is a price worth paying to store a copy of a password the
  #   operator already knows.  Splitting it out keeps every file the generator
  #   above declares present on disk, so that generator is NOT missing and is
  #   NOT re-run.
  #
  #   Checked rather than assumed: `validationHash` — the other thing that can
  #   force a regeneration — comes from an explicit `validation` attribute that
  #   neither generator sets, so EDITING A SCRIPT does not invalidate anything.
  #   Only the file list matters here.
  #
  # ── ONE PROMPT, BOTH FORMS.  NOT TWO GENERATORS ───────────────────────────
  #
  #   The password is prompted ONCE and both artefacts are derived from that
  #   single answer.  A second generator holding the plaintext alongside the
  #   old hash would be two copies of one secret that can silently diverge —
  #   and the divergence presents as an exporter that cannot log in while the
  #   WebUI works fine, which is a genuinely annoying thing to debug.
  #
  # ── WHAT THIS OVERTURNS, STATED PLAINLY ───────────────────────────────────
  #
  #   The generator above used to say the hash "is what ever reaches the
  #   guest".  That was true and free until M13, and it is no longer free.
  #   Two alternatives were considered and are worse:
  #
  #     1. qBittorrent's WebUI "API Key" field.  ALREADY REJECTED WITH A
  #        MEASUREMENT in this file's header: HTTP 403 in 0.5 ms, nothing in
  #        qBittorrent's log.  Re-run that before reaching for it again.
  #     2. WebUI\AuthSubnetWhitelist for 127.0.0.1, letting the exporter skip
  #        authentication.  Worse than it looks: `WebUI\LocalHostAuth=true` is
  #        deliberate, and turning it off lets EVERY process in this guest
  #        drive the torrent client unauthenticated.
  #
  #   The exposure added is bounded: one 0400 root:root file in the guest's
  #   secrets share, read by PID 1 through LoadCredential= before the exporter
  #   drops privileges, so the exporter's own user never opens it either.
  #
  # ── ONE ORPHAN TO SWEEP ───────────────────────────────────────────────────
  #
  #   vars/per-machine/ernst/wg-qbittorrent/webui-password-pbkdf2/ is no longer
  #   declared by any generator and can be deleted after this lands.  Leaving
  #   it does no harm — nothing reads it — but it is a stale copy of a secret.
  clan.core.vars.generators.qbittorrent-webui = {
    files."password".secret        = true;
    files."password-pbkdf2".secret = true;

    prompts."password" = {
      description = "qBittorrent WebUI password for user 'admin' (the EXISTING one, unless you mean to change it)";
      type        = "hidden";
    };

    runtimeInputs = [ pkgs.coreutils pkgs.python3 ];

    script = ''
      set -euo pipefail

      cp "$prompts/password" "$out/password"

      # qBittorrent's password format: @ByteArray(<b64 salt>:<b64 hash>), where
      # the hash is PBKDF2-HMAC-SHA512, 100000 iterations, 64-byte key over a
      # 16-byte salt.
      #
      # The salt is fresh on every run, so re-running this produces a DIFFERENT
      # hash for the same password.  That is correct and harmless: qBittorrent
      # verifies against whatever salt is in the file, and the config is
      # re-rendered on every start anyway.
      python3 - "$prompts/password" > "$out/password-pbkdf2" <<'PY'
      import base64, hashlib, os, sys
      password = open(sys.argv[1], "rb").read().rstrip(b"\n")
      salt = os.urandom(16)
      digest = hashlib.pbkdf2_hmac("sha512", password, salt, 100000, 64)
      sys.stdout.write("@ByteArray(%s:%s)" % (
          base64.b64encode(salt).decode(),
          base64.b64encode(digest).decode(),
      ))
      PY
    '';
  };

  ##############################################################################
  # M14 — slskd's credentials.  ONE generator, TWO consumers, and that is the
  # point of its shape.
  #
  # ── WHAT IS PROMPTED AND WHAT IS GENERATED ─────────────────────────────────
  #
  #   PROMPTED, because they are accounts a human owns and this repo cannot
  #   invent:
  #     slsk-username / slsk-password   the Soulseek NETWORK account, registered
  #                                     at soulseek.org.  slskd cannot connect
  #                                     without it and there is no anonymous
  #                                     mode.
  #     web-password                    the slskd web UI login.  The username is
  #                                     fixed to `slskd` below — it is a
  #                                     single-operator UI behind Authelia, so a
  #                                     prompt for it would be a prompt whose
  #                                     answer is always the same.
  #
  #   GENERATED, because nothing outside this machine ever needs to know it and
  #   a human-chosen value would only be weaker:
  #     api-key                         32 hex characters, used by Soularr.
  #
  # ── TWO OUTPUT FILES, AND THE SPLIT IS DELIBERATE ─────────────────────────
  #
  #   slskd.env   the guest's EnvironmentFile.  Everything slskd needs.
  #   api-key     the bare key, nothing else — consumed by containers/arr.nix,
  #               which renders it into Soularr's config.ini at run time.
  #
  #   The alternative was a second prompted secret in the arr container, which
  #   would be a SECOND COPY of the same key with no link to the first: rotate
  #   one and the other silently keeps the old value until someone notices
  #   Soularr getting 401s.  One generator makes rotation a single edit.  It is
  #   the same argument M4 made for reading the *arr API keys out of their own
  #   config.xml instead of prompting for them.
  #
  # ── THE KEY IS CIDR-SCOPED TO THE arr CONTAINER ───────────────────────────
  #
  #   slskd's "primary" API key accepts a role and a CIDR list as a
  #   semicolon-separated tuple, which is the only way to constrain it from an
  #   environment variable:
  #
  #     SLSKD_API_KEY=cidr=<list>;<key>
  #
  #   The list is 10.0.90.13/32 — Soularr's container and nothing else.  Its
  #   ROLE is left at the primary key's default (Administrator) and that is a
  #   deliberate non-choice rather than an oversight: Soularr ENQUEUES
  #   downloads, so ReadOnly cannot work, and slskd's documented roles do not
  #   include a middle option that covers "search and download but not
  #   reconfigure".  The CIDR is therefore the constraint that is actually
  #   doing the work, which is why it is not omitted.
  #
  #   Upstream's own caution applies and is worth restating: CIDR filtering
  #   breaks behind a reverse proxy, because the remote address becomes the
  #   proxy's.  It works HERE precisely because Soularr does NOT go through
  #   Traefik — it reaches slskd directly across VLAN 90 at layer 2, which is
  #   the same departure-2 argument M4 recorded for the *arrs and qBittorrent.
  #   If a later milestone ever routes Soularr through the proxy, this CIDR
  #   silently stops constraining anything.
  ##############################################################################
  clan.core.vars.generators.slskd-credentials = {
    files."slskd.env".secret = true;
    files."api-key".secret   = true;

    prompts."slsk-username" = {
      description = "Soulseek NETWORK account username (registered at soulseek.org)";
      type        = "line";
    };
    prompts."slsk-password" = {
      description = "Soulseek NETWORK account password";
      type        = "hidden";
    };
    prompts."web-password" = {
      description = "slskd web UI password for user 'slskd'";
      type        = "hidden";
    };

    runtimeInputs = [ pkgs.coreutils pkgs.openssl ];

    script = ''
      set -euo pipefail

      openssl rand -hex 16 > "$out/api-key"

      # Values are NOT quoted.  systemd's EnvironmentFile parser treats quotes
      # as part of the value unless the WHOLE value is quoted, and a Soulseek
      # password that silently gains a pair of quotes fails authentication with
      # a message that says nothing about quoting — the same trap
      # containers/arr.nix's janitorr-jellyfin generator documents.
      {
        printf 'SLSKD_SLSK_USERNAME=%s\n' "$(cat "$prompts/slsk-username")"
        printf 'SLSKD_SLSK_PASSWORD=%s\n' "$(cat "$prompts/slsk-password")"
        printf 'SLSKD_USERNAME=slskd\n'
        printf 'SLSKD_PASSWORD=%s\n'      "$(cat "$prompts/web-password")"
        printf 'SLSKD_API_KEY=cidr=%s;%s\n' \
          '${arrAddr}/32' "$(cat "$out/api-key")"
      } > "$out/slskd.env"
    '';
  };

  ##############################################################################
  # The guest.
  ##############################################################################
  microvm.vms.${vmName} = {
    autostart = true;

    config = { config, lib, pkgs, ... }: {
      system.stateVersion = "26.05";

      microvm = {
        # qemu, and the choice has a consequence worth knowing: the qemu runner
        # does not implement a notify socket, so microvm.nixosModules.host gives
        # microvm@wg-qbittorrent Type=simple.  A guest that fails to finish
        # booting therefore leaves a RUNNING service and a diagnosable console
        # log, instead of the host killing it at TimeoutSec and
        # Restart=always looping it out of reach — the trap
        # containers/jellyfin.nix caps wait-online to 20 s to avoid.
        hypervisor = "qemu";
        vcpu = 2;
        # NOT 2048.  microvm.nix emits an eval warning for exactly that value:
        # qemu hangs when the guest has precisely 2 GB
        # (microvm-nix/microvm.nix#171).  4096 also leaves headroom for
        # libtorrent's piece cache once the session is large; ernst has 256 GB.
        mem  = 4096;

        interfaces = [ {
          type = "tap";
          id   = tapName;
          mac  = guestMac;
        } ];

        # posixAcl = false on every share — see the ZFS caveat in the header.
        shares = [
          {
            # The host's store, read-only.  Without this the guest's closure
            # would be built into a disk image on every change.
            tag = "ro-store";
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
            proto = "virtiofs";
            readOnly = true;
            posixAcl = false;
          }
          {
            # IDENTICAL PATH on both sides.  Not cosmetic: it is what lets a
            # torrent's path be handed to the arr stack verbatim in M4, with no
            # remote-path mapping to get wrong.
            tag = "downloads";
            source = downloadRoot;
            mountPoint = downloadRoot;
            proto = "virtiofs";
            posixAcl = false;
          }
          {
            # Profile + torrent state, on zdata (invariant #7).  Mounted at
            # upstream's default profileDir so the packaged unit needs no
            # overrides — the same trick containers/jellyfin.nix uses for
            # /var/lib/jellyfin.
            tag = "qbt-state";
            source = stateSource;
            mountPoint = "/var/lib/qBittorrent";
            proto = "virtiofs";
            posixAcl = false;
          }
          {
            tag = "secrets";
            source = hostSecretsDir;
            mountPoint = guestSecretsDir;
            proto = "virtiofs";
            readOnly = true;
            posixAcl = false;
          }

          # ── M14: slskd ────────────────────────────────────────────────────
          #
          # A SEPARATE share for the Soulseek tree rather than widening the
          # `downloads` one to all of /srv/media.  The guest gets exactly the
          # two subtrees its two clients write and nothing else — the media
          # LIBRARY is not shared into the machine that faces the internet, and
          # that is the whole reason to keep the shares narrow.
          #
          # IDENTICAL PATH on both sides, like `downloads` above, and for the
          # same reason: Soularr hands Lidarr the path slskd reports, so the
          # two must agree verbatim or every import needs a remote-path mapping
          # to get wrong.
          #
          # Hardlinks still work across it because they are not this share's
          # problem: Lidarr links from /srv/media/soulseek to
          # /srv/media/library inside the ARR CONTAINER, which binds the whole
          # dataset in one mount.  The domain is the dataset (invariant #2).
          {
            tag = "soulseek";
            source = soulseekRoot;
            mountPoint = soulseekRoot;
            proto = "virtiofs";
            posixAcl = false;
          }
          {
            # slskd's state, at the module's own StateDirectory path so the
            # packaged unit needs no override — the same trick `qbt-state` uses
            # for /var/lib/qBittorrent.
            tag = "slskd-state";
            source = slskdStateSource;
            mountPoint = "/var/lib/slskd";
            proto = "virtiofs";
            posixAcl = false;
          }
        ];
      };

      ########################################################################
      # Networking.
      ########################################################################

      # No IPv6 anywhere.  The provider's tunnel is v4-only as configured, and
      # a v6 default route the killswitch does not model is precisely how these
      # setups leak.  `table inet` below covers both families regardless.
      networking.enableIPv6 = false;

      # The interface is named eth0, and that is asserted rather than assumed.
      #
      # The nftables ruleset below matches `iifname "eth0"` / `oifname "eth0"`,
      # so the name is part of the killswitch, not a cosmetic detail — a NIC
      # that came up as enp0s7 would leave every LAN-side rule matching nothing
      # and the output chain's `policy drop` would take the guest off the
      # network entirely.  qemu's `microvm` machine type puts the virtio-net on
      # the MMIO bus, where udev has no PCI path to build a predictable name
      # from and would fall back to eth0 anyway — but "would fall back to" is
      # not a guarantee across systemd versions.  net.ifnames=0 makes it one.
      # There is exactly one NIC, so nothing is lost.
      networking.usePredictableInterfaceNames = false;

      networking.useNetworkd = true;
      # No local resolver.  resolvconf (openresolv, on by default) is left
      # enabled because wg-quick uses it to install the provider's DNS from the
      # DNS= line; nothing else writes /etc/resolv.conf, so before the tunnel is
      # up the guest cannot resolve at all.  That is the intended state.
      services.resolved.enable = false;

      # Nothing may talk to an NTP server outside the tunnel, and time-syncing
      # through it buys nothing here: kvm-clock keeps the guest in step with
      # ernst, which does sync.
      services.timesyncd.enable = false;

      systemd.network.networks."10-eth0" = {
        matchConfig.Name = "eth0";
        networkConfig = {
          DHCP         = "ipv4";
          IPv6AcceptRA = false;
        };
        dhcpV4Config = {
          # The lease supplies an address and a gateway and nothing else.  A
          # resolver from DHCP would be a LAN resolver, i.e. a name leak.
          UseDNS     = false;
          UseDomains = false;
          UseNTP     = false;
        };

        # The carve-out that keeps replies to management clients out of the
        # tunnel.  ROUTES, not routing policy rules — and the difference is the
        # whole point.
        #
        # With AllowedIPs = 0.0.0.0/0, wg-quick installs two rules:
        #
        #   from all lookup main suppress_prefixlength 0
        #   not from all fwmark 0xca6c lookup <wg table>
        #
        # Main is consulted first, but its DEFAULT route is suppressed, so a
        # reply to a client on 10.0.10.0/24 — a different subnet from the
        # guest's own — matches nothing in main, falls to the second rule, and
        # is routed into the tunnel.  The WebUI and SSH appear dead from exactly
        # the networks that are allowed to reach them.
        #
        # THE OBVIOUS FIX DOES NOT WORK, and it was tried first: a
        # [RoutingPolicyRule] per management network at priority 100.  wg-quick
        # runs AFTER networkd and adds its rules without an explicit priority,
        # and the kernel's fib_default_rule_pref() assigns "one less than the
        # second rule in the list" — so it landed at 99 and 98, ahead of ours,
        # *because* ours were at 100.  Measured on the running guest:
        #
        #   98:  from all lookup main suppress_prefixlength 0
        #   99:  not from all fwmark 0xca6c lookup 51820
        #   100: from all to 10.0.10.0/24 lookup main      ← never consulted
        #
        # Picking a lower number cannot win: wg-quick would take one lower
        # still.  Anything that competes on rule priority loses to a program
        # that chooses its priority at run time relative to whatever it finds.
        #
        # So compete on route specificity instead.  `suppress_prefixlength 0`
        # rejects only prefix length 0 — the default route — so an explicit
        # /24 in main is found by wg-quick's OWN first rule and wins there,
        # whatever the priorities end up being.  Nothing is widened: the
        # nftables output chain still drops everything to these networks except
        # replies on established flows.
        #
        # Gateway = _dhcp4 rather than a literal 10.0.90.1: the UDM-Pro owns
        # this subnet's gateway and a second copy here would be a fact that can
        # silently diverge — the same call M2b made about the address itself.
        #
        # Per network, never a supernet.  A provider's in-tunnel resolver can
        # live inside 10.0.0.0/16 — IVPN's AntiTracker DNS is 10.0.254.2/.3,
        # and the one actually in use here is 10.0.254.4 — and a /16 carve-out
        # would route every DNS query at eth0, where the killswitch correctly
        # drops it.  Tunnel up, `wg show` perfect, not one name resolving.
        routes = map (net: {
          Destination = net;
          Gateway     = "_dhcp4";
        }) mgmtNets;

        linkConfig.RequiredForOnline = "routable";
      };

      # 20 s: long enough for a DHCP lease, short enough that a missing
      # reservation leaves one obviously failed unit rather than a two-minute
      # stall in the middle of boot.  Same reasoning, at length, in
      # machines/ernst/containers/jellyfin.nix.
      systemd.network.wait-online.timeout = 20;

      ########################################################################
      # The killswitch.
      ########################################################################
      networking.firewall.enable = false;
      networking.nftables = {
        enable = true;
        ruleset = ''
          table inet killswitch {
            # Management networks: the humans.  SSH and ping, and the WebUI by
            # way of api_clients below.  Mirrored on the UDM-Pro; both must
            # agree.
            set mgmt_nets {
              type ipv4_addr
              flags interval
              elements = { ${lib.concatStringsSep ", " mgmtNets} }
            }

            # Everything allowed to reach the WebUI API: the management
            # networks, plus M4's arr container on this guest's own VLAN.
            #
            # A SUPERSET of mgmt_nets, not a replacement for it, because the
            # arr gets the API and nothing else — no SSH, no ping.  The
            # UDM-Pro never sees the arr's traffic (same VLAN, same bridge,
            # switched locally), so for that source this set is the ONLY thing
            # enforcing anything.
            set api_clients {
              type ipv4_addr
              flags interval
              elements = { ${lib.concatStringsSep ", " allowedClients} }
            }

            # The VPN endpoint, as address . port.  Deliberately EMPTY at load
            # time and filled in at boot by vpn-killswitch-endpoint.service from
            # the staged secret: the endpoint is a credential and does not
            # belong in a world-readable /etc/nftables ruleset.  An empty set
            # means the handshake itself is blocked — fail-closed, and the
            # symptom is a tunnel that never comes up rather than traffic that
            # quietly takes the wrong door.
            set vpn_endpoint {
              type ipv4_addr . inet_service
            }

            chain input {
              type filter hook input priority filter; policy drop;

              iif lo accept
              ct state established,related accept
              ct state invalid drop

              iifname "eth0" ip saddr @api_clients tcp dport ${toString webuiPort} accept

              # M14.  slskd's web UI and REST API.
              #
              # THE SET GROWS A SECOND PORT, NOT A SECOND CLIENT — which is
              # what docs/roadmap.md's M14 requires, and it is exactly right
              # here: the set already means "the humans, plus the arr
              # container", and both of those want slskd for the same reasons
              # they want qBittorrent.  A separate set would be a second list
              # holding the same three entries, free to drift.
              #
              # Contrast the exporter rule below, which really does need its
              # own line because its client is neither of those.
              iifname "eth0" ip saddr @api_clients tcp dport ${toString slskdWebPort} accept

              iifname "eth0" ip saddr @mgmt_nets   tcp dport 22 accept

              # M13.  The Prometheus exporter, and it gets its OWN rule rather
              # than a seat in @api_clients — deliberately, in both directions:
              #
              #   the monitoring container may reach the EXPORTER and not the
              #   WebUI API, so a scrape cannot become a torrent command;
              #   and the arr container may reach the WebUI API and not the
              #   exporter, which it has no use for.
              #
              # A literal address rather than a set, because a set of one is a
              # set that invites a second element without an argument for it.
              iifname "eth0" ip saddr ${monitoringAddr} tcp dport ${toString exporterPort} accept
              iifname "eth0" ip saddr @mgmt_nets   icmp type echo-request accept

              # DHCPv4 offers/acks.  networkd's initial exchange uses a raw
              # packet socket and bypasses this hook entirely; the rule is here
              # for the unicast renewal, which does not.
              iifname "eth0" udp sport 67 udp dport 68 accept

              # Incoming peer connections, in-tunnel only.  Useful solely if
              # the provider forwards a port; harmless when it does not.
              iifname "wg0" tcp dport ${toString torrentPort} accept
              iifname "wg0" udp dport ${toString torrentPort} accept

              # M14.  slskd's Soulseek listen port, and it is `wg0` ONLY —
              # deliberately, and it is the line that would be easiest to get
              # wrong by copying the WebUI rule above.
              #
              # An incoming Soulseek peer connection arriving on eth0 would be
              # a peer that had found this host at its REAL address, which is
              # the one thing this guest exists to prevent.  On wg0 it is a
              # peer that found the exit, which is the intended shape.
              #
              # TCP only: the Soulseek protocol's peer connections are TCP.
              iifname "wg0" tcp dport ${toString slskdListenPort} accept
            }

            chain forward {
              type filter hook forward priority filter; policy drop;
            }

            chain output {
              type filter hook output priority filter; policy drop;

              oif lo accept

              # THE killswitch.  Three exceptions on the LAN side, and no
              # blanket `ct state established` — an established entry is not
              # bound to an interface, so a global accept here would let a flow
              # that was built through the tunnel continue out of eth0 the
              # moment wg0 disappeared.  Scoping the established rule to the
              # allowed clients keeps the WebUI, the API and SSH answering
              # without opening that door.
              #
              # api_clients rather than mgmt_nets: it is the superset, so this
              # one rule covers the replies to every source the input chain
              # accepts.  Splitting it per set would let the two drift, and a
              # drifted output chain presents as "the service is down" from one
              # client and fine from another.
              oifname "eth0" ip daddr @api_clients ct state established,related accept

              # M13.  The scrape's reply, and it needs its own line for exactly
              # the reason the comment above gives about not drifting: the
              # monitoring container is deliberately NOT in @api_clients, so
              # the rule above does not cover it, and without this the exporter
              # would answer into the tunnel and Prometheus would see a
              # timeout — the same failure the mgmtNets routing note describes.
              oifname "eth0" ip daddr ${monitoringAddr} ct state established,related accept

              oifname "eth0" ip daddr . udp dport @vpn_endpoint accept
              oifname "eth0" udp sport 68 udp dport 67 accept

              # Everything else — trackers, peers, DNS, the lot.
              oifname "wg0" accept
            }
          }
        '';
      };

      # Fill the endpoint set from the staged secret.
      #
      # partOf nftables.service so that reloading the ruleset — which flushes
      # every set — re-runs this instead of silently leaving the tunnel with no
      # way out.  Ordered before wg-quick for the obvious reason.
      systemd.services.vpn-killswitch-endpoint = {
        description = "Populate the killswitch's VPN endpoint set";
        after       = [ "nftables.service" ];
        partOf      = [ "nftables.service" ];
        before      = [ "wg-quick-wg0.service" ];
        requiredBy  = [ "wg-quick-wg0.service" ];
        serviceConfig = {
          Type            = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ip=$(${pkgs.coreutils}/bin/cat ${guestSecretsDir}/endpoint-ip)
          port=$(${pkgs.coreutils}/bin/cat ${guestSecretsDir}/endpoint-port)
          ${pkgs.nftables}/bin/nft add element inet killswitch vpn_endpoint \
            "{ $ip . $port }"
        '';
      };

      ########################################################################
      # The tunnel.
      ########################################################################
      networking.wg-quick.interfaces.wg0.configFile = "${guestSecretsDir}/wg0.conf";

      ########################################################################
      # SSH — management networks only, and the reason it exists at all.
      #
      # M3's test plan requires running commands INSIDE the guest (the exit-IP
      # check through wg0).  The qemu runner wires the serial console to the
      # service's stdout, i.e. to ernst's journal: excellent for reading a boot,
      # useless for typing into.  Without sshd the milestone cannot be verified
      # and M4 has no way to look at the client it integrates with.
      #
      # Key-only, root-only, and reachable from mgmt_nets alone.  The key is the
      # YubiKey ed25519 that is already authorised across the fleet
      # (modules/users/admin.nix uses the same file), so this adds a host to
      # reach, not a credential to manage.
      ########################################################################
      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin        = "prohibit-password";
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
        };
        # Host key from the vars generator: root is a tmpfs, so a
        # self-generated key would be new on every boot.
        hostKeys = [ ];
        extraConfig = ''
          HostKey ${guestSecretsDir}/ssh_host_ed25519_key
        '';
      };
      users.users.root.openssh.authorizedKeys.keyFiles = [
        ../../miralda/yubikey_ed25519.pub
      ];

      ########################################################################
      # qBittorrent.
      ########################################################################

      # uid/gid pinned to match the host — see the file header.  media is the
      # PRIMARY group; PrivateUsers=true in the upstream unit would squash a
      # supplementary one.
      users.users.qbittorrent = {
        isSystemUser = true;
        uid          = qbtUid;
        group        = "media";
      };
      users.groups.media = { gid = mediaGid; };

      services.qbittorrent = {
        enable         = true;
        user           = "qbittorrent";
        group          = "media";
        webuiPort      = webuiPort;
        torrentingPort = torrentPort;

        # Reachability is the firewall's job, above; upstream's openFirewall
        # would also open torrentingPort on the LAN side, which is the one
        # thing this guest exists to prevent.
        openFirewall = false;

        # serverConfig is deliberately EMPTY, and the config is rendered by the
        # ExecStartPre below instead.  Upstream's serverConfig path installs a
        # store-built qBittorrent.conf on every start — which is the behaviour
        # we want — but it has no way to interpolate a secret, and the WebUI
        # password hash must not be in the store.  Setting both would mean two
        # ExecStartPre definitions of the same option, which is a merge
        # conflict, not an append.
        serverConfig = { };

        # --confirm-legal-notice as well as [LegalNotice] Accepted=true: the
        # conf covers the normal path, the flag covers the first start, when
        # the file is written after the check.
        extraArgs = [ "--confirm-legal-notice" ];
      };

      ##########################################################################
      # M13 — the Prometheus exporter.
      #
      # ── IT IS `qbit-exp`, NOT THE ONE THE NAME SUGGESTS ───────────────────
      #
      # `pkgs.prometheus-qbittorrent-exporter` (2.0.1) is martabal/qbit-exp, a
      # RUST binary called `qbit-exp` — not esanchezm's Python exporter of the
      # same descriptive name.  Checked by looking in the built store path
      # rather than inferring from the attribute, because the two take
      # completely different environment variables and the Python one's
      # (QBITTORRENT_HOST / QBITTORRENT_PORT) would be silently ignored here.
      #
      # The names below were read out of the binary itself.
      #
      # ── QBITTORRENT_PASSWORD_FILE IS WHY THIS IS CLEAN ────────────────────
      #
      # qbit-exp reads the password from a FILE if told to, so the plaintext
      # never enters the environment and never appears in /proc/<pid>/environ.
      # Combined with LoadCredential — which PID 1 reads before dropping to the
      # exporter's DynamicUser — the staged 0400 root:root file is never opened
      # by an unprivileged process at all.
      #
      # THE API-KEY ROUTE IS DELIBERATELY NOT USED, even though this binary
      # supports QBITTORRENT_API_KEY.  The header of this file records a
      # measurement: qBittorrent's WebUI API Key produced HTTP 403 in 0.5 ms
      # with nothing in its log.  Re-run that before reaching for it again.
      systemd.services.qbittorrent-exporter = {
        description = "Prometheus exporter for qBittorrent";
        wantedBy    = [ "multi-user.target" ];
        after       = [ "qbittorrent.service" ];
        wants       = [ "qbittorrent.service" ];

        environment = {
          # 127.0.0.1: the exporter and qBittorrent share this guest's netns,
          # so the WebUI API conversation never touches the wire.  That is the
          # whole reason the exporter lives in here rather than beside
          # Prometheus — see the exporterPort note at the top of this file.
          QBITTORRENT_BASE_URL       = "http://127.0.0.1:${toString webuiPort}";
          QBITTORRENT_USERNAME       = "admin";
          QBITTORRENT_PASSWORD_FILE  = "%d/webui-password";

          # ── THE COOKIE NAME.  WITHOUT THIS THE EXPORTER NEVER SERVES ──────
          #
          # qBittorrent renamed its session cookie in 5.2.0: `SID` became
          # `QBT_SID_<webui port>`.  qbit-exp still DEFAULTS to `SID`, and its
          # own startup line says so:
          #
          #   WARN SID for qBittorrent < 5.2.0; QBT_SID_<qBittorrent_port>
          #        for > 5.2.0 (SID)
          #
          # — the trailing "(SID)" is the value actually in use.  This guest
          # runs v5.2.2, so the default is wrong here.
          #
          # THE FAILURE IS A LOOP, NOT AN ERROR, which is why it took a manual
          # run to find.  Login SUCCEEDS and the cookie is stored; every
          # subsequent request then carries the wrong cookie NAME, qBittorrent
          # treats it as unauthenticated, and the exporter concludes the cookie
          # "changed" and logs back in — forever:
          #
          #   INFO New cookie for auth stored
          #   WARN Cookie changed, trying to reconnect ...
          #
          # Metrics never populate, so /metrics answers 503 with an EMPTY body
          # and the unit stays `active` the whole time.  Nothing fails, nothing
          # restarts, and the only external symptom is up=0 in Prometheus.
          #
          # Measured on ernst 2026-08-26 by running the binary by hand in the
          # guest: with the default, 503; with this set, HTTP 200 and 4296
          # qbittorrent_* series.
          #
          # Derived from webuiPort rather than written as a literal, because
          # the port is in the name — changing the WebUI port and not this
          # would resurrect the loop.
          QBITTORRENT_COOKIE_NAME    = "QBT_SID_${toString webuiPort}";

          # 0.0.0.0, restricted by the nftables rule above to the monitoring
          # container's address alone.  Stated rather than left to the
          # binary's default so the number the firewall reasons about and the
          # number the process binds are the same number in one file.
          EXPORTER_HOST = "0.0.0.0";
          EXPORTER_PORT = toString exporterPort;
        };

        serviceConfig = {
          Type      = "simple";
          ExecStart = "${pkgs.prometheus-qbittorrent-exporter}/bin/qbit-exp";
          Restart   = "on-failure";
          RestartSec = "30s";

          LoadCredential = [ "webui-password:${guestSecretsDir}/webui-password" ];

          # DynamicUser, and KEPT — this is the flaresolverr shape, not the
          # prowlarr one.  The exporter holds no state, writes nothing, and
          # needs no id that means anything on the pool, so there is nothing to
          # gain by pinning a uid and six hardening directives to lose by it.
          DynamicUser = true;

          CapabilityBoundingSet   = "";
          PrivateDevices          = true;
          ProtectClock            = true;
          ProtectHostname         = true;
          ProtectKernelLogs       = true;
          ProtectKernelModules    = true;
          ProtectKernelTunables   = true;
          ProtectProc             = "invisible";
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
          RestrictNamespaces      = true;
          RestrictRealtime        = true;
          LockPersonality         = true;
          SystemCallArchitectures = "native";
          SystemCallFilter        = [ "@system-service" "~@privileged" "~@debug" "~@mount" ];
          UMask                   = "0077";
        };
      };

      systemd.services.qbittorrent = {
        # Start after the tunnel, but do not depend on it: `wants`, not
        # `requires`.  If wg0 fails, qBittorrent should still come up so the
        # WebUI can say so — it is bound to wg0 at the application level and
        # will not move a byte regardless.
        wants = [ "wg-quick-wg0.service" ];
        after = [ "wg-quick-wg0.service" ];

        serviceConfig = {
          # THE line that makes M4's hardlinks possible.  0002 → files 0664,
          # so a host-side arr in group media has the write bit
          # fs.protected_hardlinks demands before it will link a file it does
          # not own.  With the systemd default 0022 the import silently copies.
          # The header explains this at length; do not "tidy" it away.
          UMask = "0002";

          # Renders the profile config, substituting the WebUI password hash.
          # Runs as qbittorrent:media inside the unit's own sandbox — no `+`
          # escape needed, because the staged hash is group-readable by media.
          #
          # THE TRADE, stated plainly: this file is authoritative on every
          # start, so anything changed in the WebUI that lives in
          # qBittorrent.conf is discarded at the next restart (i.e. at the next
          # deploy).  That is deliberate — same call as forceEncodingConfig in
          # containers/jellyfin.nix, and for the same reason: this is the
          # machine where the repo wins.  Torrent state, categories
          # (categories.json) and the resume data are separate files and are
          # NOT touched.
          ExecStartPre = [
            "${pkgs.writeShellScript "qbittorrent-render-config" ''
              set -euo pipefail
              conf=/var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf

              # Read into a variable FIRST, and check it.  `sed "s|x|$(cat f)|"`
              # looks equivalent and is not: a command substitution that fails
              # inside an argument does not trip `set -e`, so an unreadable
              # secret becomes an EMPTY password rather than a failed unit.
              # That shipped once — the WebUI then rejected every login and
              # nothing anywhere said why.  A plain assignment DOES trip
              # `set -e`, and the explicit test covers the file being present
              # but empty.
              hash=$(${pkgs.coreutils}/bin/cat ${guestSecretsDir}/webui-password-pbkdf2)
              if [ -z "$hash" ]; then
                echo "webui-password-pbkdf2 is empty — refusing to start with no password" >&2
                exit 1
              fi

              ${pkgs.coreutils}/bin/install -Dm600 ${qbtConfTemplate} "$conf"
              ${pkgs.gnused}/bin/sed -i "s|@WEBUI_PASSWORD_PBKDF2@|$hash|" "$conf"
            ''}"
          ];
        };
      };

      ########################################################################
      # M14 — slskd.
      #
      # See the M14 section of the file header for the placement argument and
      # for the hardlink measurement that dictates UMask below.
      ########################################################################

      # uid/gid pinned to match the host, and `media` as the PRIMARY group —
      # the qbittorrent shape, for the identical reason.  Upstream's unit sets
      # PrivateUsers=true (verified by reading the module, not assumed), which
      # maps only User= and Group= into the service's user namespace; a
      # SUPPLEMENTARY media membership would be squashed to nogroup inside it
      # and every downloaded file would land in a group the host cannot name.
      #
      # The module creates users.users.slskd itself, but only when `user` is
      # left at its default — and it assigns NO uid, leaving the allocation to
      # NixOS.  So setting one here is a new definition of an unset option and
      # needs no mkForce, exactly like bazarr in containers/arr.nix.  It also
      # declares the `slskd` GROUP only when group == "slskd"; it is "media"
      # below, so no stray group is created.
      users.users.slskd = {
        isSystemUser = true;
        uid          = slskdUid;
        group        = "media";
      };

      services.slskd = {
        enable = true;
        user   = "slskd";
        group  = "media";

        # Reachability is the killswitch's job, above.  Upstream's openFirewall
        # opens soulseek.listen_port via networking.firewall — which is
        # DISABLED in this guest (`networking.firewall.enable = false`, the
        # nftables ruleset replaces it entirely), so this option would be inert
        # rather than wrong.  It is set false anyway so that nobody reads its
        # absence as "the port is open somewhere else".
        openFirewall = false;

        # The credentials — Soulseek account, web UI login, and the CIDR-scoped
        # primary API key — arrive through the environment, never the store.
        # See the slskd-credentials generator.
        #
        # A NOTE ON PRECEDENCE, because it is counter-intuitive and it decides
        # whether this works: slskd loads configuration in the order
        # `defaults < environment variables < YAML < command line`.  The YAML
        # BEATS the environment.  The module renders that YAML into the store
        # from `settings`, so anything named in `settings` below would silently
        # override the matching environment variable.  That is precisely why
        # `soulseek.username`, `soulseek.password` and everything under
        # `web.authentication` are absent from `settings` — they must be left
        # unset for the EnvironmentFile to win.
        environmentFile = "${guestSecretsDir}/slskd.env";

        settings = {
          directories = {
            downloads  = "${soulseekRoot}/complete";
            incomplete = "${soulseekRoot}/incomplete";
          };

          soulseek.listen_port = slskdListenPort;

          web = {
            port = slskdWebPort;
            # Bind every interface INSIDE this guest: the API has to be
            # reachable from the arr container across VLAN 90, and the guest
            # has exactly one non-loopback interface, on which the killswitch
            # above admits precisely @api_clients.  The firewall is the
            # boundary here, the bind address is not.
            https.disabled = true;
          };

          # NOTHING IS SHARED.  slskd defaults to sharing no directories, and
          # this states it rather than relying on that default.
          #
          # It is worth an explicit note because Soulseek is a RECIPROCAL
          # network and sharing is the socially expected behaviour — so the
          # absence of a shares list will look like an oversight to anyone who
          # knows the protocol.  It is not: pointing a share at /srv/media
          # would publish this household's library to the open internet from
          # the one machine that has an unfiltered path to it, which is a
          # different decision entirely from "download music".  If sharing is
          # ever wanted it needs its own directory, its own argument, and a
          # read-only share into this guest — not a line added here.
          shares.directories = [ ];
        };
      };

      systemd.services.slskd = {
        # Start after the tunnel but do not require it — the qbittorrent shape
        # again, and for the same reason: slskd binds the Soulseek connection
        # at the application level, so if wg0 is down it should come up and say
        # so rather than vanish.  The module's own `after = [ "network.target" ]`
        # is merged with this, not replaced by it.
        wants = [ "wg-quick-wg0.service" ];
        after = [ "wg-quick-wg0.service" ];

        serviceConfig = {
          # THE line that makes M14's hardlinks possible, and upstream does NOT
          # set it — the module's unit carries fifteen hardening directives and
          # no UMask, so it inherits systemd's 0022 and writes 0644 files.
          #
          # 0002 → 0664, which is what fs.protected_hardlinks requires before
          # Lidarr (a different uid in group media) may link a file it does not
          # own.  Measured both ways on ernst 2026-08-28 — see the header.
          # With 0022 every music import silently degrades to a copy.
          #
          # Do not "tidy" this away, and do not assume M3's proof covers it:
          # this is a SECOND write path into /srv/media by a different service
          # with a different umask, which is the whole reason M14 owes its own
          # proof.
          UMask = "0002";

          # ── THE REST OF THE HARDENING UPSTREAM LEAVES OFF ────────────────
          #
          # The module's unit is genuinely well hardened as far as it goes —
          # fifteen Protect*/Restrict* directives — but it stops short of the
          # three that carry the most weight, and the measurement says so.
          # `systemd-analyze security --offline=true` on the generated unit:
          #
          #   upstream as shipped      5.1 MEDIUM
          #   with the block below     see the PR table
          #
          # Almost all of that 5.1 is ONE missing directive:
          # CapabilityBoundingSet is unset, so every capability line scores
          # against it — CAP_SYS_ADMIN, CAP_SYS_PTRACE, CAP_SETUID and twenty
          # more, none of which slskd has any use for.
          #
          # EMPTY IS SAFE HERE, and the thing that would make it unsafe is
          # worth naming: a service binding a port below 1024 needs
          # CAP_NET_BIND_SERVICE.  slskd binds 5030 and 50300, both well above
          # it, so there is nothing to keep.
          CapabilityBoundingSet = "";

          # AF_INET/AF_INET6 for the Soulseek network and the API, AF_UNIX for
          # logging.  slskd speaks no other address family.
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];

          LockPersonality         = true;
          RestrictRealtime        = true;
          SystemCallArchitectures = "native";

          # `@chown` is added back after `~@privileged` removes it, and the
          # trailing position matters — later entries win.
          #
          # MEASURED ELSEWHERE, APPLIED HERE PRE-EMPTIVELY.  On 2026-08-28 the
          # identical filter killed Audiobookshelf in the arr container the
          # first time it touched file ownership:
          #
          #   status=31/SYS   (SIGSYS — a seccomp kill, not an app error)
          #   syscall=93      (fchown on x86_64)
          #
          # slskd is the other M14 service that WRITES INTO /srv/media, as a
          # uid whose files Lidarr must then be able to hardlink, so it is in
          # exactly the same position — and a SIGSYS mid-download is a far
          # worse failure than the EPERM it would otherwise get.
          #
          # It costs essentially nothing: CapabilityBoundingSet is "" above, so
          # there is no CAP_CHOWN and the kernel only permits chown to this
          # process's own uid/gid.  nixpkgs' own sonarr and radarr units permit
          # chown for the same class of workload.
          SystemCallFilter        = [ "@system-service" "~@privileged" "~@debug" "~@mount" "@chown" ];

          # NOT MemoryDenyWriteExecute.  slskd is .NET and the JIT maps
          # writable-then-executable pages, so it would start and then die on
          # the first request.  Same rejection containers/arr.nix and
          # containers/jellyfin.nix record for the same runtime — and the same
          # one qBittorrent's block above does not need to make, because
          # nothing there is managed.
        };
      };

      # No host keys to generate — the one host key comes from the vars
      # generator, because the guest's root is a tmpfs and a self-generated key
      # would be new on every boot.  Without this, sshd-keygen.service is
      # emitted with an empty ExecStart and systemd refuses it noisily on the
      # console at every boot: "Service has no ExecStart=. Refusing."  Harmless,
      # but it is the only red line in an otherwise clean boot log, and a boot
      # log people learn to ignore is worse than no boot log.
      systemd.services.sshd-keygen.enable = false;

      # Minimal guest.  curl and wireguard-tools are the test plan's
      # instruments (exit-IP check through wg0, `wg show` for the handshake);
      # everything else stays out.
      environment.systemPackages = with pkgs; [ curl wireguard-tools ];
      documentation.enable = false;
      documentation.nixos.enable = false;
    };
  };
}
