# machines/ernst/containers/tubesync.nix
#
# TubeSync on ernst: subscribe to YouTube channels and playlists, download with
# yt-dlp on a schedule, and write straight into the tree Jellyfin already scans
# — no import stage, no second copy (M9 in docs/roadmap.md).
#
# ── TIER: podman, AND THE PREMISE WAS RE-CHECKED RATHER THAN INHERITED ──────
#
#   Invariant #1 gives podman exactly one job: "escape hatch — upstream ships
#   only an image."  M9's brief asserted TubeSync qualifies.  It still does,
#   and this was re-derived rather than assumed, because M8 and M12/M13 have
#   each overturned a packaging premise this year:
#
#     - **Not in nixpkgs** (checked 2026-08-27 against ernst's own pin and
#       nixos-unstable: only `tubekit`).  No module, no package.
#     - **And packaging it is not a milestone task, it is a project.**  This
#       is not a single binary like Janitorr's jar or M12's *arr helpers.
#       Upstream's Dockerfile is a many-stage build over Debian carrying
#       **s6-overlay** for process supervision, **openresty** (an nginx fork)
#       in front, **tailwindcss** and **deno** for asset building, and **uv**
#       for Python.  The app itself is **Django 6.0** plus **django-huey** for
#       background work, gunicorn, whitenoise, django-sass-processor, and
#       yt-dlp.  A Nix package would have to reproduce the asset pipeline and
#       the supervision tree, not just install a program.
#
#   THIS IS THE FIRST OCCUPANT OF THE PODMAN TIER — `virtualisation.oci-
#   containers` appears nowhere else in this repo, and podman was not even
#   installed on ernst before this file.  So it builds the tier as much as it
#   deploys the service.
#
#   THE COST, accepted explicitly: an opaque image, a package tree we do not
#   control, and drift we absorb rather than evaluate.  WHAT WOULD MOVE IT TO
#   nspawn: somebody packaging TubeSync, or upstream shedding the openresty /
#   s6 / asset-build layers so a plain Django-from-source derivation becomes
#   realistic.  Neither is close.
#
# ── ROOTFUL, AND THE REASON IS THE STORAGE MODEL, NOT CONVENIENCE ───────────
#
#   The brief leaned rootless.  This runs ROOTFUL, deliberately, and the
#   deciding argument is the one the brief itself flagged as "the trap":
#
#     nspawn and virtiofs both pass uids/gids through UNMAPPED, which is why
#     the allocation table in machines/ernst/networking.nix can say a number
#     chosen inside a guest IS a number on zdata.  **Rootless podman always
#     has a user namespace**, so the in-container PUID/PGID are NOT what lands
#     on disk — files appear as some sub-uid, or as nobody:nobody.  Recovering
#     from that means `--userns=keep-id` or an idmap, i.e. bolting a second,
#     different id model onto a pool whose entire convention is that ids are
#     literal.  `/srv/media` is a shared hardlink domain with the *arr; it is
#     the last place to introduce a second id model.
#
#   Rootful with no remapping makes podman behave like nspawn here: PUID 3027
#   and PGID 3000 are exactly what appears on zdata.
#
#   THE SECURITY COST, stated rather than buried: the container runtime runs
#   as root on the host.  What limits the blast radius is that TubeSync holds
#   no inbound trust (see AUTHENTICATION), reaches the internet only outbound
#   to YouTube, and its netns can talk to exactly one address.  What would
#   move this to rootless: an idmapped mount story for `/srv/media` that keeps
#   on-disk ids literal — `--userns=keep-id:uid=3027,gid=3000` is the shape to
#   evaluate, and it should be evaluated before the SECOND podman service, not
#   after five of them.
#
# ── NETWORKING: THE OPEN PROBLEM, SOLVED — AND MEASURED FIRST ───────────────
#
#   M9 called this "genuinely unsolved in this repo", and it was: a tap is the
#   microvm primitive, a vb-* veth the nspawn one, and podman is neither.
#   macvlan is REJECTED for this architecture (on br0 it rides br0's own self
#   VLAN 50, and on enp13s0 the trunk's native VLAN, also 50 — M2 established
#   this; do not re-derive it).
#
#   WHAT THIS FILE DOES: build the netns OURSELVES with the repo's ordinary
#   veth-on-br0 pattern, then hand it to podman with `--network=ns:`.  Podman
#   creates no network of its own, so netavark never runs, no CNI plugin is
#   involved, and there is no second IPAM to keep in step.
#
#     br0 ──[vb-tubesync, VLAN 90]── veth ──[eth0]── netns "tubesync"
#                                                       └── podman joins it
#
#   PROVEN ON ernst BEFORE THIS FILE WAS WRITTEN (2026-08-27), on a throwaway
#   bridge so nothing production was touched: a container started with
#   `--network=ns:/var/run/netns/<n>` saw the interface with the MAC we pinned
#   and the address we set, while the host side sat on the bridge as a
#   `90 PVID Egress Untagged` port.  The mechanism is not inferred.
#
#   WHY NOT the host-networking fallback the brief blessed: it is WORSE here
#   than the brief assumed.  br0's own VLAN membership is 50 ONLY (see note 3
#   in machines/ernst/networking.nix), so a service on the host is not on
#   VLAN 90 at all — Traefik at 10.0.90.12 reaching ernst at 10.0.50.10 is a
#   CROSS-VLAN flow that hairpins through the UDM-Pro and needs a Services →
#   Servers rule.  M5 lost a round to exactly that shape and M6 built its mon0
#   veth specifically to avoid it.  The fallback would trade a solved
#   networking problem for a new firewall rule and a known-bad path.
#
#   networkd ENSLAVES the host side (`Bridge=`), rather than the KeepMaster
#   dance the nspawn containers need.  That is pattern A from
#   machines/ernst/networking.nix, and it applies here for the same reason it
#   applies to the microvm tap: nothing else claims this link, so networkd
#   does the enslavement and the [BridgeVLAN] in ONE step and the VLAN race
#   cannot occur.  Verify anyway: `bridge vlan show dev vb-tubesync`.
#
# ── AUTHENTICATION: AUTHELIA, AND HTTP_USER/HTTP_PASS IS A TRAP ─────────────
#
#   Forward-auth via Authelia (M7, done).  The Jellyfin carve-out does not
#   apply: Jellyfin is exempt because TV and mobile clients cannot survive an
#   interactive redirect, and TubeSync's only ingress is a browser.
#
#   Its "media servers" feature is an OUTBOUND call from TubeSync to Jellyfin
#   (a library-rescan trigger).  Forward-auth sits on TubeSync's INGRESS and
#   cannot break an egress call — put that here so a later session does not
#   "fix" it.
#
#   THE BRIEF'S INTERIM — `HTTP_USER`/`HTTP_PASS` — MUST NOT BE USED, and M8
#   is why.  TubeSync's basic auth answers in the `Authorization` header, and
#   **Authelia consumes that header as its own credential**: any request
#   carrying one is rejected 401 by Authelia before it ever reaches the
#   backend.  M8 lost most of a session to precisely this with Tvheadend's
#   digest auth (see the M8 close-out in docs/roadmap.md).  The general rule,
#   now paid for twice: **a backend whose own auth uses the `Authorization`
#   header cannot sit behind a forward-auth middleware.**  Leave both env vars
#   unset; Authelia is the gate.
#
#   `TUBESYNC_HOSTS` is set to the real hostname rather than left at its `*`
#   default — that is Django's ALLOWED_HOSTS, and `*` disables the Host-header
#   check that exists to stop cache-poisoning and password-reset-link forgery.
#
# ── STORAGE ─────────────────────────────────────────────────────────────────
#
#   /srv/state/tubesync → /config     SQLite db, thumbnails, yt-dlp cache.
#                                     A BIND MOUNT, not a named podman volume:
#                                     a named volume puts state in podman's
#                                     graph root and defeats the point of
#                                     /srv/state being the one place state
#                                     lives (invariant #7 — zroot rolls back).
#   /srv/media/youtube  → /downloads  A PLAIN SUBDIRECTORY of the one media
#                                     dataset (invariant #2).  Do NOT add
#                                     zdata/media/youtube: hardlinks cannot
#                                     cross a dataset boundary and the *arr
#                                     import path depends on them.  TubeSync
#                                     does not hardlink, but it must not
#                                     disturb the layout that does.
#
#   `/srv/media` carries `com.sun:auto-snapshot=false`, so DOWNLOADS ARE NOT
#   SNAPSHOTTED.  Acceptable for re-downloadable content — said out loud
#   rather than left implied.
#
#   TUBESYNC_RESET_DOWNLOAD_DIR IS SET TO False, AND THAT IS DELIBERATE.  It
#   defaults to True, which makes TubeSync walk /downloads at startup
#   rewriting ownership and modes.  Pointed at a subdirectory of the shared
#   media dataset that is a bad idea on its own merits, and this repo already
#   has a scar from ownership being rewritten underneath it — see the tmpfiles
#   vs oneshot fight documented in containers/jellyfin.nix, which silently
#   reset the media modes on every deploy for a milestone.  Ownership here is
#   set once, by us, below.
{ config, lib, pkgs, ... }:
let
  # ── Identity ──────────────────────────────────────────────────────────────
  # NO uid WAS EVER RESERVED FOR THIS SERVICE.  The reservation block in
  # machines/ernst/networking.nix jumps from M8's 3026 straight to M14's 3017
  # group, so 3027 is allocated here and added to the table in the same
  # commit.  PGID is the shared media group, fixed at 3000 in
  # containers/jellyfin.nix and deliberately above NixOS's dynamic gid range.
  tubesyncUid = 3027;
  mediaGid    = 3000;

  # ── L2 / L3 ───────────────────────────────────────────────────────────────
  # Next free sequence in the allocation table: 08 and 09 are RESERVED for
  # M15's tdarr and M16's jellyseerr, 0a went to M8's tvheadend.  The last
  # octet follows the table's 8 + <seq> convention.
  netns     = "tubesync";
  vethHost  = "vb-tubesync";
  vethNs    = "eth0";
  mac       = "02:00:00:90:00:0b";
  vlanId    = 90;
  webPort   = 4848;

  # Traefik's veth address — the ONLY source permitted to reach the web UI.
  # Same one-hop-on-br0 caveat as every sibling: these frames never reach the
  # UDM-Pro, so the netns firewall below is the only enforcement point there
  # is.  The adjacency that makes it matter is real — 10.0.90.11 is the
  # qBittorrent microvm, one layer-2 hop away.
  traefikAddr = "10.0.90.12";

  stateDir     = "/srv/state/tubesync";
  downloadsDir = "/srv/media/youtube";
  secretsDir   = "/run/tubesync-secrets";

  # Pinned by DIGEST, not by tag.  A tag is mutable and image drift is the
  # entire cost of this tier, so the digest is what converts "whatever the
  # registry serves today" into something reproducible.
  #
  #   tag    v0.18.3   (released 2026-08-03; amd64/linux)
  #   digest sha256:f41658ebc890fa7aba037e3e1f113b5a2af81581799e23c59534b9faff258092
  #
  # NOTE the brief named v0.18.1 and flagged it as operator-supplied and
  # unverified — correctly: v0.18.2 and v0.18.3 have shipped since.
  #
  # TO BUMP: pick the new tag, then
  #   skopeo inspect --format '{{.Digest}}' docker://ghcr.io/meeb/tubesync:<tag>
  # and update BOTH lines here.  Never point this at a tag.
  imageTag    = "v0.18.3";
  imageDigest = "sha256:f41658ebc890fa7aba037e3e1f113b5a2af81581799e23c59534b9faff258092";
in
{
  ##############################################################################
  # Podman itself.  ernst had no container runtime before this file.
  ##############################################################################
  #
  # `virtualisation.containers.enable` is what provides /etc/containers —
  # policy.json in particular.  Without it podman refuses every image with
  # "no policy.json file found", which is the first thing that happens on a
  # host where podman was installed but never configured (measured on ernst
  # while proving the netns mechanism).
  virtualisation.containers.enable = true;
  virtualisation.podman = {
    enable = true;
    # No docker socket, no docker alias: nothing here speaks the docker API,
    # and modules/apps/containers.nix (lgo's WORKSTATION bundle, which does
    # enable dockerCompat) is not in scope on ernst — ernst uses commonBase,
    # which does not import modules/apps at all.
    dockerCompat = false;
    # The default `podman.service` socket activation is not needed either:
    # oci-containers drives podman by CLI from a systemd unit.
    dockerSocket.enable = false;
  };

  ##############################################################################
  # The network namespace, its veth, and its firewall.
  ##############################################################################

  # Host side of the veth — an ordinary VLAN-90 port on br0.
  #
  # Bridge=, NOT KeepMaster: the nspawn containers need KeepMaster because
  # nspawn enslaves the link itself and networkd must not fight it.  Here the
  # oneshot below only CREATES the pair; networkd owns the enslavement, so it
  # applies [BridgeVLAN] in the same step and the VLAN race the nspawn files
  # work around cannot happen.  Pattern A in machines/ernst/networking.nix.
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

  # Create the namespace and the veth pair, then firewall the namespace.
  #
  # Idempotent throughout: this must survive a `clan machines update` that
  # restarts it while the container is running, and it must not fail the
  # container when the netns already exists.
  #
  # THE FIREWALL IS PART OF THIS UNIT, and it has to be — a bare netns handed
  # to podman has NO rules at all, and podman adds none when it is given a
  # namespace rather than asked to build one.  Without these lines 4848 would
  # be reachable from everything on VLAN 90, including the qBittorrent guest.
  # That is the exact bypass the source-restriction hardening in
  # containers/traefik.nix exists to prevent, so it is reproduced here in the
  # only place that can enforce it.
  systemd.services.tubesync-netns = {
    description = "Network namespace and veth for the TubeSync container";
    wantedBy = [ "multi-user.target" ];
    before   = [ "podman-tubesync.service" ];
    after    = [ "systemd-networkd.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.iproute2 pkgs.iptables ];
    script = ''
      set -eu

      # The namespace.  `ip netns add` fails if it exists, which is the normal
      # case on a re-run, so probe first rather than swallowing every error.
      if ! ip netns list | grep -qw '${netns}'; then
        ip netns add '${netns}'
      fi
      ip -n '${netns}' link set lo up

      # The veth pair.  Existence of the host side is the test: if it is there
      # the pair was made on an earlier run and the container end is already
      # inside the namespace.
      if ! ip link show '${vethHost}' >/dev/null 2>&1; then
        ip link add '${vethHost}' type veth peer name '${vethNs}' netns '${netns}'
      fi

      # MAC is pinned on the CONTAINER side — that is the address the UDM-Pro
      # sees and the one the DHCP reservation keys on, never the host-side
      # veth.  Setting it before the link comes up means it is stable from the
      # first DHCP DISCOVER, which is what a reservation needs.
      ip -n '${netns}' link set '${vethNs}' address '${mac}'
      ip -n '${netns}' link set '${vethNs}' up
      ip link set '${vethHost}' up

      # Namespace firewall.  Rebuilt from scratch on every run so it cannot
      # accumulate duplicates.
      ip netns exec '${netns}' iptables -F INPUT
      ip netns exec '${netns}' iptables -P INPUT DROP
      ip netns exec '${netns}' iptables -A INPUT -i lo -j ACCEPT
      ip netns exec '${netns}' iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
      # The web UI, from Traefik and nothing else.
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

  # DHCP inside the namespace.
  #
  # ADDRESSING IS DHCP WITH A RESERVATION ON THE UDM-Pro, keyed on the pinned
  # MAC — the same rule every sibling container follows, and for the same
  # reason: the UDM-Pro owns the subnet, the pool and every other reservation,
  # and a second copy in this repo diverges silently.
  #
  # It needs its own client because a bare namespace has no networkd in it.
  # `NetworkNamespacePath=` is what puts this unit inside the namespace; the
  # unit is otherwise an ordinary host service.
  #
  # `--nohook resolv.conf` is load-bearing: the MOUNT namespace is shared with
  # the host, so without it dhcpcd would rewrite the HOST's /etc/resolv.conf
  # from a lease meant for a container.  The container's resolver is set
  # declaratively on the podman side (`--dns`) instead, mirroring what the
  # nspawn containers declare in their own networkd config and for the same
  # reason — a DHCP-supplied resolver that quietly changes does not fail
  # loudly, it fails on the next metadata fetch.
  systemd.services.tubesync-dhcp = {
    description = "DHCP client inside the TubeSync network namespace";
    wantedBy = [ "multi-user.target" ];
    after    = [ "tubesync-netns.service" ];
    requires = [ "tubesync-netns.service" ];
    before   = [ "podman-tubesync.service" ];
    serviceConfig = {
      NetworkNamespacePath = "/run/netns/${netns}";
      ExecStart = "${pkgs.dhcpcd}/bin/dhcpcd --nobackground --nohook resolv.conf --ipv4only ${vethNs}";
      Restart    = "on-failure";
      RestartSec = "5s";
    };
  };

  ##############################################################################
  # Storage.
  ##############################################################################

  # State on zdata.  0700 and owned by the container's numeric ids — which are
  # literal here, because this container is rootful and unmapped.
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0700 ${toString tubesyncUid} ${toString mediaGid} -"
  ];

  # The downloads directory, ordered AFTER the media dataset is mounted.
  #
  # A tmpfiles rule alone races the mount, which is why containers/jellyfin.nix
  # pairs its rules with an ordered oneshot — read that file's long comment
  # before changing either.  2770 = setgid + rwxrws---: new files inherit gid
  # media, group members read and write, root owns.  Jellyfin (uid 964, member
  # of media) can then read what TubeSync writes with no second chown.
  systemd.services.tubesync-downloads-dir = {
    description = "Create ${downloadsDir} as root:media 2770";
    wantedBy = [ "multi-user.target" ];
    before   = [ "podman-tubesync.service" ];
    after    = [ "srv-media.mount" ];
    requires = [ "srv-media.mount" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.coreutils}/bin/install -d -o root -g ${toString mediaGid} -m 2770 ${downloadsDir}
    '';
  };

  ##############################################################################
  # Secrets.
  ##############################################################################

  # Django's SECRET_KEY — GENERATED, not prompted: nobody types this and
  # nothing outside the repo knows it, so a prompt would only invite a weak
  # value.  It signs sessions and password-reset tokens; losing it logs
  # everyone out, leaking it is worse.
  clan.core.vars.generators.tubesync-django = {
    files."secret-key".secret = true;
    runtimeInputs = [ pkgs.coreutils pkgs.openssl ];
    script = ''
      openssl rand -base64 48 | tr -d '\n/+=' | head -c 50 > "$out/secret-key"
    '';
  };

  # Jellyfin's URL and API key, for the library-rescan trigger.
  #
  # PROMPTED, and the ordering is the reason: the key is created in JELLYFIN'S
  # OWN UI, so it is an lgo manual step feeding a generator prompt rather than
  # something a session can produce.  Same shape as M13's janitorr-jellyfin
  # generator, which documents the argument at length.
  clan.core.vars.generators.tubesync-jellyfin = {
    files."jellyfin.env".secret = true;
    prompts."api-key" = {
      description = "Jellyfin API key for TubeSync's library-rescan trigger (Dashboard → API Keys → +)";
      type = "hidden";
    };
    runtimeInputs = [ pkgs.coreutils ];
    # Values are NOT quoted: systemd's EnvironmentFile parser treats quotes as
    # part of the value unless the whole value is quoted, and a key that
    # silently gains a pair of quotes fails with a message that says nothing
    # about quoting.  M13 records the same trap.
    script = ''
      printf 'TUBESYNC_JELLYFIN_API_KEY=%s\n' "$(cat "$prompts/api-key")" > "$out/jellyfin.env"
    '';
  };

  # Stage both where the container unit can read them.
  #
  # Same shape and reasoning as M13's janitorr-secrets and M5's
  # traefik-secrets: a directory WE own, rather than a bind of /run/secrets,
  # which is a symlink to a per-generation directory REPLACED on every deploy.
  #
  # wantedBy, deliberately NOT requiredBy: if the Jellyfin key has not been
  # generated yet this unit fails and the container still starts, because
  # everything except the rescan trigger works without it.  That is the same
  # graceful-degradation call M13 made for Janitorr's Jellyfin credentials.
  systemd.services.tubesync-secrets = {
    description = "Stage TubeSync's secrets for the container";
    wantedBy = [ "podman-tubesync.service" ];
    before   = [ "podman-tubesync.service" ];
    after    = [ "local-fs.target" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root ${secretsDir}
      {
        printf 'DJANGO_SECRET_KEY=%s\n' \
          "$(cat ${config.clan.core.vars.generators.tubesync-django.files."secret-key".path})"
        cat ${config.clan.core.vars.generators.tubesync-jellyfin.files."jellyfin.env".path}
      } > ${secretsDir}/env
      ${pkgs.coreutils}/bin/chmod 0400 ${secretsDir}/env
    '';
  };

  ##############################################################################
  # The container.
  ##############################################################################
  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers.tubesync = {
    image = "ghcr.io/meeb/tubesync@${imageDigest}";

    environment = {
      # Literal on disk — rootful, no userns.  See the ROOTFUL section.
      PUID = toString tubesyncUid;
      PGID = toString mediaGid;
      # Drives the download SCHEDULE, so a wrong value silently shifts every
      # window rather than failing.  Matches the host.
      TZ = "Europe/Berlin";
      # Django ALLOWED_HOSTS.  NOT left at the `*` default — see the
      # AUTHENTICATION section.
      TUBESYNC_HOSTS = "tubesync.goclan.org";
      # Do NOT let it rewrite ownership across the media tree.  See STORAGE.
      TUBESYNC_RESET_DOWNLOAD_DIR = "False";
    };

    environmentFiles = [ "${secretsDir}/env" ];

    volumes = [
      "${stateDir}:/config"
      "${downloadsDir}:/downloads"
    ];

    # NO `ports` ENTRY, deliberately.  Publishing a port is meaningless with
    # `--network=ns:` — there is no podman-managed network to publish from,
    # and the service is reached at its own address on VLAN 90 like every
    # other backend in this fleet.
    ports = [ ];

    extraOptions = [
      # The namespace built above.  This is the whole networking decision.
      "--network=ns:/run/netns/${netns}"
      # Resolver declared rather than inherited, for the same reason the nspawn
      # containers declare it: Technitium's blocklists and logging should cover
      # this container, and a DHCP-supplied resolver that changes underneath us
      # fails on the next fetch rather than loudly.
      "--dns=10.0.5.3"
      "--dns-search=skynet.lan"
    ];
  };

  # Ordering.  oci-containers generates podman-tubesync.service; everything it
  # depends on is declared here rather than inside the generated unit.
  systemd.services.podman-tubesync = {
    after    = [ "tubesync-netns.service" "tubesync-dhcp.service" "tubesync-downloads-dir.service" ];
    requires = [ "tubesync-netns.service" "tubesync-downloads-dir.service" ];
  };
}
