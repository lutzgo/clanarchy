# machines/ernst/containers/cwa.nix
#
# Calibre-Web-Automated — the ebook library, its OPDS catalogue, its Kobo sync
# endpoint and its KOReader progress-sync server.
#
# ── IT DID NOT EXIST BEFORE THIS FILE, WHATEVER THE OTHER COMMENTS SAY ──────
#
#   containers/arr.nix says "Komga and CWA already serve the READING side in
#   this household" and docs/roadmap.md repeats it in four places.  It was not
#   true: there was no CWA in this repo, no container on ernst, no podman
#   workload, and no Technitium record.  The sentence described an intention
#   that was never built, and it was load-bearing in the wrong direction —
#   Kapowarr's placement argument leans on it.
#
#   So this is GREENFIELD.  There is no deployed version to report, no pin to
#   bump, and no 3.x→4.x migration to perform, because there is no 3.x here to
#   migrate from.  It starts at 4.0.6 with an empty library.
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
#   ALONGSIDE.  networking.nix's table already warns that a reservation for a
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
#   web UI may block on metadata.db while it runs.  On an EMPTY library — which
#   is what this deploys with — the backfill is trivial, which is a good reason
#   to turn it on now rather than after the library fills.
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
#     /srv/media/library/calibre  CWA owns entirely.  New, empty.
#     /srv/media/ingest/cwa       CWA's watch folder.  Files are DELETED after
#                                 processing — that is upstream's documented
#                                 behaviour, so nothing that matters may be the
#                                 only copy in here.
#
#   WIRING BINDERY'S OUTPUT INTO CWA'S INGEST IS DELIBERATELY NOT DONE.  It is
#   a one-line change to Bindery's destination and it is somebody's decision,
#   not a detail: it would move ebook acquisition from "Komga reads a plain
#   tree" to "CWA owns the tree and Komga reads CWA's output", which is a
#   different topology for the household's reading. Left as an explicit
#   non-decision rather than a default.
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
  vethNs    = "eth0";
  mac       = "02:00:00:90:00:0d";   # reused from M16's cloudflared — see header
  vlanId    = 90;

  # Continuing the 3000-range family.  Next free was 3031 before this round;
  # containers/arr.nix took 3031 (komga) and 3032 (navidrome) in the same
  # change, so this is 3033.  The table in machines/ernst/networking.nix is
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
  # 4.0.6 with an empty library means none of those migration paths is ever
  # exercised here — which is the one genuine advantage of having had no
  # earlier deployment.
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
  # The network namespace, its veth, and its firewall.
  ##############################################################################

  # Bridge=, NOT KeepMaster — pattern A in networking.nix.  The oneshot below
  # only CREATES the pair; networkd owns the enslavement and so applies
  # [BridgeVLAN] in the same step.  (The nspawn containers need KeepMaster
  # because nspawn enslaves the link itself and networkd must not fight it.)
  systemd.network.networks."60-${vethHost}" = {
    matchConfig.Name = vethHost;
    networkConfig = {
      Bridge              = "br0";
      LinkLocalAddressing = "no";
      IPv6AcceptRA        = false;
    };
    bridgeVLANs = [ { VLAN = vlanId; PVID = vlanId; EgressUntagged = vlanId; } ];
    linkConfig.RequiredForOnline = "enslaved";
  };

  systemd.services.cwa-netns = {
    description = "Network namespace and veth for the CWA container";
    wantedBy = [ "multi-user.target" ];
    before   = [ "podman-cwa.service" ];
    after    = [ "systemd-networkd.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.iproute2 pkgs.iptables ];
    # Idempotent throughout: it must survive a `clan machines update` that
    # restarts it while the container is running.
    script = ''
      set -eu

      if ! ip netns list | grep -qw '${netns}'; then
        ip netns add '${netns}'
      fi
      ip -n '${netns}' link set lo up

      if ! ip link show '${vethHost}' >/dev/null 2>&1; then
        ip link add '${vethHost}' type veth peer name '${vethNs}' netns '${netns}'
      fi

      # MAC pinned on the CONTAINER side — the address the UDM-Pro sees and the
      # one the DHCP reservation keys on, never the host-side veth.  Set before
      # the link comes up so it is stable from the first DHCP DISCOVER.
      ip -n '${netns}' link set '${vethNs}' address '${mac}'
      ip -n '${netns}' link set '${vethNs}' up
      ip link set '${vethHost}' up

      # Namespace firewall.  A bare netns handed to podman has NO rules, and
      # podman adds none when it is given a namespace rather than asked to
      # build one.  Rebuilt from scratch each run so it cannot accumulate
      # duplicates.
      ip netns exec '${netns}' iptables -F INPUT
      ip netns exec '${netns}' iptables -P INPUT DROP
      ip netns exec '${netns}' iptables -A INPUT -i lo -j ACCEPT
      ip netns exec '${netns}' iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

      # The web UI and every app protocol, from Traefik and nothing else.
      #
      # THIS ONE RULE IS THE WHOLE BACKEND-BYPASS DEFENCE FOR AN
      # INTERNET-FACING SERVICE.  cwa.goclan.org is in `wanExposed`, so
      # requests reaching this port may have originated on the public internet
      # — but they arrive FROM TRAEFIK, which is what makes a source
      # restriction meaningful here at all.  Without this rule the container
      # would be reachable directly from every host on VLAN 90, including the
      # qBittorrent guest one layer-2 hop away, bypassing the rate limits,
      # CrowdSec and the login limiter in one step.
      ip netns exec '${netns}' iptables -A INPUT -p tcp -s ${traefikAddr}/32 --dport ${toString webPort} -j ACCEPT

      # DHCP replies from the UDM-Pro (the client below runs in here).
      ip netns exec '${netns}' iptables -A INPUT -p udp --sport 67 --dport 68 -j ACCEPT
      # ICMP, so the thing is diagnosable at all.
      ip netns exec '${netns}' iptables -A INPUT -p icmp -j ACCEPT
    '';
    preStop = ''
      ${pkgs.iproute2}/bin/ip netns del '${netns}' 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip link del '${vethHost}' 2>/dev/null || true
    '';
  };

  # DHCP inside the namespace — a bare netns has no networkd in it.
  #
  # `--nohook resolv.conf` is load-bearing: the MOUNT namespace is shared with
  # the host, so without it dhcpcd would rewrite the HOST's /etc/resolv.conf
  # from a lease meant for a container.  M9 documents this at length.  The
  # resolver is declared on the podman side instead.
  systemd.services.cwa-dhcp = {
    description = "DHCP client inside the CWA network namespace";
    wantedBy = [ "multi-user.target" ];
    after    = [ "cwa-netns.service" ];
    requires = [ "cwa-netns.service" ];
    before   = [ "podman-cwa.service" ];
    serviceConfig = {
      NetworkNamespacePath = "/run/netns/${netns}";
      ExecStart  = "${pkgs.dhcpcd}/bin/dhcpcd --nobackground --nohook resolv.conf --ipv4only ${vethNs}";
      Restart    = "on-failure";
      RestartSec = "5s";
    };
  };

  ##############################################################################
  # Storage.
  ##############################################################################

  # Ordered AFTER the datasets are mounted, and REQUIRING them — a tmpfiles
  # rule alone races the mount, which containers/jellyfin.nix documents at
  # length and every podman-tier sibling follows.
  #
  # The requirement is HARD rather than advisory: if zdata is not up, CWA
  # starting anyway would create an empty Calibre library on the rolled-back
  # root and then initialise a metadata.db in it.  The next boot would mount
  # the real dataset over the top and the library would appear to have lost
  # every book — recoverable, but only by someone who works out what happened.
  systemd.services.cwa-dirs = {
    description = "Create CWA's library, ingest and state directories";
    wantedBy = [ "multi-user.target" ];
    before   = [ "podman-cwa.service" ];
    after    = [ "srv-media.mount" "srv-state.mount" ];
    requires = [ "srv-media.mount" "srv-state.mount" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      install=${pkgs.coreutils}/bin/install

      # 0750 cwa:cwa throughout, NOT 2770 root:media.
      #
      # No setgid and no shared group, because unlike RomM's tree there is no
      # second principal here: CWA is the only writer to all three of these.
      # Syncthing does not replicate them and no *arr files into them.  A
      # shared-group tree with one member is a grant waiting to be inherited by
      # something that should not have it.
      $install -d -o ${toString cwaUid} -g ${toString cwaGid} -m 0750 ${stateDir}
      $install -d -o ${toString cwaUid} -g ${toString cwaGid} -m 0750 ${stateDir}/config
      $install -d -o ${toString cwaUid} -g ${toString cwaGid} -m 0750 ${libraryDir}
      $install -d -o ${toString cwaUid} -g ${toString cwaGid} -m 0750 ${ingestDir}
    '';
  };

  ##############################################################################
  # The container.
  ##############################################################################
  virtualisation.oci-containers.containers.cwa = {
    image = "ghcr.io/crocodilestick/calibre-web-automated@${cwaDigest}";

    environment = {
      TZ = "Europe/Berlin";

      # The image drops to this uid/gid internally via its s6 init.  It must
      # match the ownership cwa-dirs sets, or CWA cannot write its own library.
      PUID = toString cwaUid;
      PGID = toString cwaGid;

      # The image's default is 8083; set explicitly so the Traefik service, the
      # firewall rule and the listener cannot drift apart.  `CWA_PORT_OVERRIDE`
      # is the variable the image actually reads — confirmed by grepping the
      # v4.0.6 source for environment reads, which is also how the absence of
      # an OAuth/KOReader override was established.
      CWA_PORT_OVERRIDE = toString webPort;
    };

    volumes = [
      # CWA's own state: app.db (users, settings, OAuth client config, the
      # KOReader toggle) and logs.  The one directory here that is NOT
      # re-derivable.
      "${stateDir}/config:/config"

      # The Calibre library CWA owns outright.  See the header for why this is
      # not /srv/media/library/books.
      "${libraryDir}:/calibre-library"

      # The ingest watch folder.  FILES ARE DELETED FROM HERE AFTER
      # PROCESSING — upstream's documented behaviour, restated at the mount
      # because it is the surprising half: this is a hand-off point, never a
      # place to keep the only copy of anything.
      "${ingestDir}:/cwa-book-ingest"
    ];

    # Meaningless with `--network=ns:` and actively misleading — the port is
    # published by the namespace's own firewall rule above, not by podman.
    ports = [ ];

    extraOptions = [
      "--network=ns:/run/netns/${netns}"
      "--dns=10.0.5.3"
      "--dns-search=skynet.lan"
    ];
  };

  systemd.services.podman-cwa = {
    after    = [ "cwa-netns.service" "cwa-dhcp.service" "cwa-dirs.service" ];
    requires = [ "cwa-netns.service" "cwa-dirs.service" ];

    serviceConfig = {
      # Ingest conversion is the expensive path: CWA shells out to Calibre's
      # ebook-convert, which is single-threaded but CPU-hungry, and a bulk
      # import runs it once per book.  Add the KOReader checksum backfill on
      # top — which reads every file in the library — and this competes with
      # Jellyfin transcodes, the HTPC session and an interactive Ollama
      # session on the same box.
      #
      # Same two mechanisms as Storyteller's and RomM's:
      #   Nice = 10        lowers priority against everything on the box.
      #   CPUWeight = 40   biases the cgroup's share only under contention.
      # Not CPUQuota: nobody is waiting on an import, so it should be free to
      # use an otherwise idle box at full speed.
      Nice      = 10;
      CPUWeight = 40;
    };
  };
}
