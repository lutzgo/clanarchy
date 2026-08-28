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
#   convenience, and docs/roadmap.md is explicit that a convenience argument
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
#   Storyteller takes its input through its own web UI and writes its output
#   inside its /data volume.  Pointing Audiobookshelf at the result is a UI
#   step in the PR body, not something this file implements.
#
# ── TIER: PODMAN, AND THE ROADMAP'S OWN ESCAPE HATCH IS WHAT PUTS IT HERE ──
#
#   docs/roadmap.md instructs: "VERIFY the deploy story against the upstream
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
#   musical intros and messy EPUB formatting.  docs/roadmap.md requires ONE
#   known-good pair to be bound and its sync checked by hand BEFORE any batch,
#   and that is in the PR test plan rather than here because nothing in Nix can
#   enforce it.
{ config, pkgs, lib, ... }:

let
  # uid 3022, reserved for this service in machines/ernst/networking.nix.
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
  # Next free sequence in the allocation table in machines/ernst/networking.nix:
  # 08 and 09 are RESERVED (M15 tdarr, M16 jellyseerr), 0a went to M8's
  # tvheadend and 0b to M9's tubesync.  So 0c, and the last octet follows that
  # table's 8 + <seq> convention: 10.0.90.20.
  netns    = "storyteller";
  vethHost = "vb-storyteller";
  vethNs   = "eth0";
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

  # See the header.  web-v2.9.3, the newest STABLE tag — NOT `latest`, which is
  # currently a 3.0.0 beta.
  imageTag    = "web-v2.9.3";
  imageDigest = "sha256:9f7fac6ba3217e131cf3eaefe0b5107b8b6c431ace91e73c06cb530cd43ff4b8";
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
  # THE FIREWALL IS PART OF THIS UNIT, and it has to be: a bare netns handed to
  # podman has NO rules at all, and podman adds none when it is given a
  # namespace rather than asked to build one.  Without these lines 8001 would
  # be reachable from everything on VLAN 90 — including the microvm that faces
  # the open internet, one layer-2 hop away.
  #
  # Idempotent throughout: it must survive a `clan machines update` that
  # restarts it while the container is running.
  systemd.services.storyteller-netns = {
    description = "Network namespace and veth for the Storyteller container";
    wantedBy = [ "multi-user.target" ];
    before   = [ "podman-storyteller.service" ];
    after    = [ "systemd-networkd.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.iproute2 pkgs.iptables ];
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

  # DHCP inside the namespace — a bare netns has no networkd in it.
  #
  # `--nohook resolv.conf` is load-bearing: the MOUNT namespace is shared with
  # the host, so without it dhcpcd would rewrite the HOST's /etc/resolv.conf
  # from a lease meant for a container.  The resolver is declared on the podman
  # side instead.  M9 documents this at length.
  systemd.services.storyteller-dhcp = {
    description = "DHCP client inside the Storyteller network namespace";
    wantedBy = [ "multi-user.target" ];
    after    = [ "storyteller-netns.service" ];
    requires = [ "storyteller-netns.service" ];
    before   = [ "podman-storyteller.service" ];
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

  # /data, ordered AFTER the audiobooks dataset is mounted.
  #
  # A tmpfiles rule alone races the mount — containers/jellyfin.nix documents
  # that at length and containers/tubesync.nix follows it; read either before
  # changing this.
  #
  # 0750 storyteller:media, not 2770 root:media like the library directories
  # beside it.  The distinction is real: this is one application's private data
  # directory (its SQLite database lives here), so the service owns it outright
  # — but `media` keeps GROUP READ so Audiobookshelf, which is in that group,
  # can be pointed at the produced EPUB3s without a copy or a chown.  Group
  # WRITE is deliberately absent: nothing else should be modifying another
  # application's database directory.
  systemd.services.storyteller-data-dir = {
    description = "Create ${dataDir} as storyteller:media 0750";
    wantedBy = [ "multi-user.target" ];
    before   = [ "podman-storyteller.service" ];
    after    = [ "srv-audiobooks.mount" ];
    requires = [ "srv-audiobooks.mount" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.coreutils}/bin/install -d \
        -o ${toString storytellerUid} -g ${toString mediaGid} -m 0750 ${dataDir}
    '';
  };

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
  virtualisation.oci-containers.containers.storyteller = {
    image = "registry.gitlab.com/storyteller-platform/storyteller@${imageDigest}";

    environment = {
      # Drives timestamps in the UI.  Matches the host.
      TZ = "Europe/Berlin";
      # See the secrets block: a FILE, not the key itself.
      STORYTELLER_SECRET_KEY_FILE = "/run/secrets/secret-key";
    };

    volumes = [
      "${dataDir}:/data"
      # Read-only, and mounted at the path the variable above names.
      "${secretsDir}/secret-key:/run/secrets/secret-key:ro"
    ];

    # NO `ports` ENTRY, deliberately.  Publishing a port is meaningless with
    # `--network=ns:` — there is no podman-managed network to publish from, and
    # the service is reached at its own address on VLAN 90 like every other
    # backend in this fleet.
    ports = [ ];

    extraOptions = [
      # The namespace built above.  This is the whole networking decision.
      "--network=ns:/run/netns/${netns}"
      # Resolver declared rather than inherited, so Technitium's blocklists and
      # logging cover this container too.
      "--dns=10.0.5.3"
      "--dns-search=skynet.lan"
      # Run as the reserved uid and the shared media gid.  ROOTFUL AND
      # UNMAPPED, so these are literal on zdata — see the header.
      "--user=${toString storytellerUid}:${toString mediaGid}"
    ];
  };

  # Ordering and the CPU budget.
  #
  # oci-containers generates podman-storyteller.service; everything it depends
  # on is declared here rather than inside the generated unit.
  systemd.services.podman-storyteller = {
    after    = [ "storyteller-netns.service" "storyteller-dhcp.service" "storyteller-data-dir.service" ];
    requires = [ "storyteller-netns.service" "storyteller-data-dir.service" ];

    serviceConfig = {
      # THE CPU BUDGET, and docs/roadmap.md requires it explicitly.
      #
      # Forced alignment will happily saturate every core it is given.  It
      # competes with a Jellyfin transcode, an HTPC session on the TV, and —
      # since M11 — an interactive Ollama session, which is the claimant whose
      # degradation is hardest to attribute.
      #
      # TWO MECHANISMS, because they do different things and neither is
      # sufficient:
      #
      #   Nice = 15         lowers scheduling priority against everything on
      #                     the box, including processes outside this cgroup.
      #   CPUWeight = 20    biases the cgroup's share when there IS contention
      #                     (default 100).  Under no contention it still gets
      #                     the whole machine, which is the point — a batch job
      #                     should use idle cores, just never at the expense of
      #                     something a human is waiting on.
      #
      # NOT CPUQuota.  A hard cap would make alignment slower even on an
      # otherwise idle box, which trades away the only thing this workload has
      # going for it (nobody is waiting on it) for no benefit.
      Nice      = 15;
      CPUWeight = 20;
    };
  };
}
