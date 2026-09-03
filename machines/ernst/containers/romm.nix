# machines/ernst/containers/romm.nix
#
# RomM — a self-hosted ROM library manager.  It scans a directory tree of game
# files, enriches it with metadata and artwork, and serves the result as a web
# UI.  Here it is the AUTHORITATIVE ROM LIBRARY for the fleet; birte's
# RetroDECK reads a Syncthing replica of the same tree.
#
# ── WHY IT IS HERE AND NOT ON THE DECK ─────────────────────────────────────
#
#   The library has to live somewhere that is backed up, has room, and is not
#   rolled back on every boot.  birte is none of those things: it is a handheld
#   whose @home is blanked at boot, whose only large writable area is a single
#   btrfs subvolume, and which is frequently off.  ernst is all three.
#
#   THE DECK STILL GETS A FULL LOCAL COPY, and that is the whole point of the
#   topology chosen in this change.  A network mount would have been simpler —
#   no duplication, saves naturally shared — and it was rejected because a
#   Steam Deck's defining property is that it LEAVES THE HOUSE.  A library
#   reachable only on the home LAN turns the device into a console.  So: ernst
#   masters, Syncthing replicates, birte plays offline.  The cost is a second
#   full copy of the library on birte's NVMe, accepted deliberately.
#
#   The Syncthing wiring is NOT in this file — it is a clan service, declared
#   in clan.nix.  See the note there about `devices`, which is load-bearing.
#
# ── THE TREE IS SHARED WITH RetroDECK BY CONSTRUCTION ──────────────────────
#
#   RomM's recommended layout ("structure A") and RetroDECK's are the same
#   shape — `roms/<platform>/` under one root — which is why birte's
#   /games/retrodeck can be replicated here without translation:
#
#     ernst   /srv/roms/roms/<platform>/      ← this file
#     birte   /games/retrodeck/roms/<system>/ ← machines/birte/deck.nix
#
#   They agree on the common platform names (nes, snes, gba, psx) and diverge
#   on others; RomM absorbs that with a `system.platforms` mapping in its own
#   config.yml rather than anything being renamed on disk.  docs/guides/
#   birte-emulation.md is the single description of the layout.
#
# ── TIER: PODMAN, and this is the tier's THIRD occupant ────────────────────
#
#   Upstream ships a Docker Compose file and a container image and nothing
#   else; there is no non-Docker path at all.  That is the same test M9's
#   TubeSync and M14's Storyteller applied, with the same answer, so this takes
#   the podman tier beside them.
#
#   `virtualisation.oci-containers` INSIDE AN NSPAWN CONTAINER IS REJECTED,
#   restated here as every service on this tier is required to restate it: the
#   value of containers/arr.nix is that upstream units and their
#   `systemd-analyze` scores stay legible, and an opaque image inside it is
#   opaque to all three.  The escape hatch is this tier, not that hybrid.
#
#   THE COST, accepted explicitly: two opaque images, a package tree we do not
#   build, and a `systemd-analyze security` score for `podman-romm.service`
#   that measures podman rather than RomM.
#
# ── TWO CONTAINERS, ONE NAMESPACE, AND THE DATABASE IS NOT ON THE VLAN ─────
#
#   RomM requires an external database; upstream's compose runs MariaDB beside
#   it and the docs are explicit that PostgreSQL support is experimental, so
#   MariaDB it is.
#
#   Both containers join the SAME network namespace.  That is not a shortcut —
#   it is what keeps the database off VLAN 90 entirely.  RomM reaches it at
#   127.0.0.1:3306, which is `lo` inside the namespace and therefore matched by
#   the one ACCEPT rule that exists for `lo`; nothing outside the namespace can
#   address it at all, and no firewall rule has to be written to say so.
#
#   The alternative — a podman network between them — would have put the
#   database on an addressable interface and made its exposure a matter of
#   getting rules right.  This way it is structural.
{ config, pkgs, lib, ... }:

let
  # uid/gid 3029, reserved in machines/ernst/networking.nix.
  #
  # LITERAL ON zdata, because this container is ROOTFUL AND UNMAPPED — the
  # decision containers/tubesync.nix and containers/storyteller.nix both record
  # at length.  Rootless podman remaps uids through a subuid range, so a number
  # chosen inside the container would not be that number on the pool.
  #
  # ITS OWN GROUP, deliberately NOT `media` (gid 3000).  `media` is the arr
  # suite's shared hardlink domain — one group so that a download, an import
  # and a library file can be the same inode.  A ROM library takes part in none
  # of that: nothing hardlinks into it, no arr writes to it, and Jellyfin does
  # not read it.  Putting ROMs in `media` would widen that group's reach for no
  # benefit.  The one principal that genuinely needs access is Syncthing, and
  # it is added to THIS group rather than the library being moved into that one.
  rommUid = 3029;
  rommGid = 3029;

  # ── L2 / L3 ───────────────────────────────────────────────────────────────
  #
  # Next free sequence in the allocation table in machines/ernst/networking.nix
  # was 0e (0c went to M14's storyteller, 0d to M16's cloudflared), and the last
  # octet follows that table's 8 + <seq> convention: 10.0.90.22.
  netns    = "romm";
  vethHost = "vb-romm";

  # `rm0` — NOT `eth0`, and NOT `st0` either.
  #
  # containers/storyteller.nix diagnosed this the expensive way and left an
  # explicit instruction for the next service on this tier: EVERY podman-tier
  # namespace must use a UNIQUE interface name, because dhcpcd keys its pidfile
  # and control socket on the INTERFACE NAME rather than the network namespace
  # (/run/dhcpcd/<iface>-4.sock), and these units share a mount namespace with
  # the host.  A duplicate name makes the second dhcpcd hand its arguments to
  # the first as a client and exit 0, applying the lease in the wrong namespace
  # — a container that is simply unreachable while every unit reports success.
  #
  # This is that instruction being followed.  A fourth service must not reuse
  # `rm0` either.
  vethNs   = "rm0";
  mac      = "02:00:00:90:00:0e";
  vlanId   = 90;

  # ROMM_PORT's default.  Named rather than left implicit because the firewall
  # rule and traefik.nix both have to agree with it.
  webPort = 8080;

  # Traefik's veth address — the ONLY source permitted to reach the web UI.
  # Same one-hop-on-br0 caveat as every sibling: these frames never reach the
  # UDM-Pro, so the netns firewall below is the only enforcement point.  The
  # adjacency that makes it matter is real — 10.0.90.11 is the qBittorrent and
  # slskd microvm, one layer-2 hop away.
  traefikAddr = "10.0.90.12";

  # ── Storage: the library and the state are deliberately separate ──────────
  #
  # The LIBRARY is content: large, replaceable only by re-dumping, and the one
  # thing that has to be byte-identical with birte's copy.  It gets its own
  # dataset — see the note on the exec property below.
  #
  # The STATE is RomM's own — its database, its fetched artwork, its config and
  # its redis spool.  It goes on zdata/state.  Keeping them apart is what lets
  # Syncthing be pointed at exactly the library and nothing else: replicating a
  # live MariaDB directory to a Steam Deck would be both useless and unsafe.
  # NOT /srv/games, and containers/arr.nix is the reason.  That dataset carries
  # exec ON — deliberately, because Steam and Questarr's PC games are binaries
  # that must run, and arr.nix calls giving anything else a foothold there "the
  # worst place in the fleet to do it".  A ROM is data: it is read by an
  # emulator and never executed.  Putting the library on the one dataset in the
  # pool where files are allowed to run would hand that property to thousands
  # of files downloaded from the internet for no reason at all.
  #
  # So zdata/roms, its own dataset, exec=off/setuid=off/devices=off.  See
  # machines/ernst/disko.nix and the runbook in
  # docs/guides/ernst-zdata-datasets.md.
  #
  # The doubled name below (/srv/roms/roms) is RomM's layout, not an accident:
  # the DATASET is the library root, and "structure A" puts the games in a
  # `roms/` directory inside it beside `bios/`.
  libraryDir = "/srv/roms";
  stateDir   = "/srv/state/romm";
  secretsDir = "/run/romm-secrets";

  # Images pinned by DIGEST, never by tag.
  #
  # Upstream's own compose file uses `:latest` for both, which is exactly the
  # trap containers/storyteller.nix documents: `latest` moved under it to a
  # major-version beta.  A ROM manager holding the only index of the library is
  # not something to let float.
  #
  # TO BUMP: pick the new tag, then
  #   skopeo inspect --format '{{.Digest}}' docker://<image>:<tag>
  # and update BOTH lines of the pair.  Never point this at a tag.
  #
  # Measured 2026-09-01 with skopeo:
  #   rommapp/romm:5.2.0   sha256:3512f2ca…  created 2026-08-20
  #   rommapp/romm:latest  sha256:3512f2ca…  ← the SAME image, today
  #
  # That second line is why the pin is worth stating rather than assuming.
  # `latest` and the newest stable happen to coincide right now, so following
  # upstream's compose would work — and would keep working right up until it
  # silently didn't, which is exactly how containers/storyteller.nix found a
  # major-version beta in a household service.
  rommTag     = "5.2.0";
  rommDigest  = "sha256:3512f2ca455782f90247271bed23116e6bc675bc74e379be2c41696e607ab11e";

  # MariaDB 11.4, the current LTS series.  Pinned to the `11.4` tag's digest
  # rather than to `lts`: the two resolve to DIFFERENT images (measured the
  # same day), and a floating alias that moves across major versions under a
  # database is the last place to accept that.
  dbTag       = "11.4";
  dbDigest    = "sha256:611a2fcc5fa7c6ceb8644c6f74b25ede004ff6c3a6b38c8f8c23d3bbf6c26430";
in
{
  ##############################################################################
  # Podman is already enabled by containers/tubesync.nix (M9), the tier's first
  # occupant.  It is NOT re-enabled here — one owner, one place, so that two
  # differing `dockerCompat` definitions can never become a merge conflict that
  # only surfaces when someone edits one of them.
  ##############################################################################

  ##############################################################################
  # The group, and the one other principal that gets into it.
  ##############################################################################

  users.groups.romm = {
    gid = rommGid;

    # Membership declared from the GROUP side rather than as
    # `users.users.syncthing.extraGroups`, and that is deliberate.
    #
    # Writing `users.users.syncthing.extraGroups` is a DEFINITION of that
    # user: it instantiates the submodule, so on a machine where the syncthing
    # module has not defined the rest of the account the build fails with
    # assertions about `isSystemUser` and an unset `group` that mention
    # neither RomM nor Syncthing.  Wrapping it in `lib.mkIf` does NOT help —
    # naming the attribute path is enough to instantiate it.  Both were
    # measured, in that order, by removing ernst from the syncthing instance.
    #
    # `members` names a user without defining one, so it is inert when the
    # account does not exist and correct when it does.
    members = [ "syncthing" ];
  };

  # Syncthing replicates the library to birte, so it needs to read and write
  # inside it.  It is added to `romm` rather than the library being handed to
  # a group Syncthing already had — the narrower of the two changes.
  #
  # The clan syncthing service runs as user/group `syncthing` (see
  # clanServices/syncthing in clan-core); this only adds a supplementary group
  # to that account and does not otherwise touch it.
  #
  # (The membership itself is declared on the group above — see the note there
  # for why it is not `users.users.syncthing.extraGroups`.)

  ##############################################################################
  # The network namespace, its veth, and its firewall.
  ##############################################################################

  # Host side of the veth — an ordinary VLAN-90 port on br0.
  #
  # Bridge=, NOT KeepMaster: the nspawn containers need KeepMaster because
  # nspawn enslaves the link itself and networkd must not fight it.  Here the
  # oneshot below only CREATES the pair; networkd owns the enslavement, so it
  # applies [BridgeVLAN] in the same step.  Pattern A in networking.nix.
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

  systemd.services.romm-netns = {
    description = "Network namespace and veth for the RomM containers";
    wantedBy = [ "multi-user.target" ];
    before   = [ "podman-romm.service" "podman-romm-db.service" ];
    after    = [ "systemd-networkd.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.iproute2 pkgs.iptables ];
    # Idempotent throughout: it must survive a `clan machines update` that
    # restarts it while the containers are running.
    script = ''
      set -eu

      if ! ip netns list | grep -qw '${netns}'; then
        ip netns add '${netns}'
      fi
      # `lo` up is not cosmetic here — it is the database's only transport.
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
      # This rule is what keeps MariaDB off the network: the database listens
      # on 127.0.0.1 only, and `lo` is reachable from inside the namespace and
      # from nowhere else.
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
  systemd.services.romm-dhcp = {
    description = "DHCP client inside the RomM network namespace";
    wantedBy = [ "multi-user.target" ];
    after    = [ "romm-netns.service" ];
    requires = [ "romm-netns.service" ];
    before   = [ "podman-romm.service" ];
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

  # Ordered AFTER the datasets are mounted, and REQUIRING them.
  #
  # A tmpfiles rule alone races the mount — containers/jellyfin.nix documents
  # that at length and every podman-tier sibling follows it.  The requirement is
  # hard rather than advisory for the same reason Storyteller's is: RomM's
  # database lives under stateDir, so a RomM that starts without it is not a
  # degraded RomM, it is a NEW EMPTY ONE whose index would then have to be
  # reconciled with the real library by hand.
  systemd.services.romm-dirs = {
    description = "Create RomM's library and state directories";
    wantedBy = [ "multi-user.target" ];
    before   = [ "podman-romm.service" "podman-romm-db.service" ];
    after    = [ "srv-roms.mount" "srv-state.mount" ];
    requires = [ "srv-roms.mount" "srv-state.mount" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -eu
      install=${pkgs.coreutils}/bin/install

      # The library: 2770 root:romm.
      #
      # SETGID (the leading 2) is the load-bearing digit.  Two different
      # principals write in here — RomM itself (uploads through the web UI) and
      # Syncthing (replication from birte) — and a file written by one has to
      # remain writable by the other.  Without setgid the group of a new file
      # would follow whichever process created it and the two would slowly
      # fence each other out of the tree.
      $install -d -o root -g ${toString rommGid} -m 2770 ${libraryDir}
      $install -d -o root -g ${toString rommGid} -m 2770 ${libraryDir}/roms
      $install -d -o root -g ${toString rommGid} -m 2770 ${libraryDir}/bios

      # RomM's own state: 0750 romm:romm, no group write and no other access.
      # This is one application's private data, database included.
      $install -d -o ${toString rommUid} -g ${toString rommGid} -m 0750 ${stateDir}
      for d in resources assets config redis mysql; do
        $install -d -o ${toString rommUid} -g ${toString rommGid} -m 0750 ${stateDir}/$d
      done
    '';
  };

  ##############################################################################
  # Secrets.
  ##############################################################################

  # All three are GENERATED, not prompted — nobody types them, nothing outside
  # the repo needs to know them, and a prompt would only invite a weak value.
  # The same call M9's Django key and M14's Storyteller key made.

  # Signs sessions.  Upstream's own instruction is `openssl rand -hex 32`.
  # Losing it logs everyone out; leaking it is worse.
  clan.core.vars.generators.romm-auth-secret = {
    files."secret-key".secret = true;
    runtimeInputs = [ pkgs.coreutils pkgs.openssl ];
    script = ''
      openssl rand -hex 32 | tr -d '\n' > "$out/secret-key"
    '';
  };

  # The application's database password, and MariaDB's root password.
  #
  # Two separate generators rather than one with two files, so that rotating
  # either does not churn the other's sops entry.
  #
  # `tr -d` over a base64 alphabet with the padding stripped: these values are
  # interpolated into an env file that MariaDB's entrypoint parses, and a
  # trailing '=' or a newline in a password has a long history of being read as
  # syntax rather than data.
  clan.core.vars.generators.romm-db-password = {
    files."password".secret = true;
    runtimeInputs = [ pkgs.coreutils pkgs.openssl ];
    script = ''
      openssl rand -base64 32 | tr -d '\n=' > "$out/password"
    '';
  };

  # ── Metadata provider credentials.  PROMPTED, not generated ─────────────
  #
  # The three above are generated because nobody types them.  These are the
  # opposite: they are credentials for accounts that exist outside this clan,
  # so the only source is the operator.
  #
  # THEY ARE NOT A UI SETTING.  RomM reads every metadata provider's
  # credentials from the ENVIRONMENT at startup and its API only reports which
  # sources came out enabled — `/api/heartbeat` on 5.2.0 answers
  #
  #   "STEAMGRIDDB_API_ENABLED": false, "IGDB_API_ENABLED": false,
  #   "HASHEOUS_API_ENABLED": true
  #
  # so there is no field in the web UI that could set them.  That is why this
  # is a clan var and a container env var rather than a note telling someone to
  # click something.
  #
  # OPTIONAL BY CONSTRUCTION.  An empty answer is a valid answer: RomM treats a
  # missing or empty key as "source disabled" and carries on with Hasheous,
  # which needs no account at all.  So this prompt never blocks a deploy on a
  # credential the operator does not have yet — press enter and revisit it with
  # `clan vars generate ernst --generator romm-metadata-keys --regenerate`.
  clan.core.vars.generators.romm-metadata-keys = {
    files."steamgriddb-api-key".secret = true;
    files."igdb-client-id".secret      = true;
    files."igdb-client-secret".secret  = true;

    prompts."steamgriddb-api-key" = {
      description = "SteamGridDB API key for RomM cover art (steamgriddb.com/profile/preferences/api) — blank to leave disabled";
      type        = "hidden";
    };
    # IGDB is RomM's primary metadata source and the one that fills in names,
    # release dates and genres; SteamGridDB only supplies artwork.  Prompted
    # together because they are the same errand, and because the same IGDB
    # application already backs Questarr.
    prompts."igdb-client-id" = {
      description = "IGDB (Twitch) client ID for RomM metadata — blank to leave disabled";
      type        = "hidden";
    };
    prompts."igdb-client-secret" = {
      description = "IGDB (Twitch) client secret for RomM metadata — blank to leave disabled";
      type        = "hidden";
    };

    runtimeInputs = [ pkgs.coreutils ];
    script = ''
      # `tr -d` strips the trailing newline the prompt adds: these end up in an
      # env file, where a newline would terminate the value early and leave the
      # next line looking like a stray assignment.
      for f in steamgriddb-api-key igdb-client-id igdb-client-secret; do
        tr -d '\n' < "$prompts/$f" > "$out/$f"
      done
    '';
  };

  clan.core.vars.generators.romm-db-root-password = {
    files."password".secret = true;
    runtimeInputs = [ pkgs.coreutils pkgs.openssl ];
    script = ''
      openssl rand -base64 32 | tr -d '\n=' > "$out/password"
    '';
  };

  # Stage them as env files the container units can read.
  #
  # A directory WE own, rather than a bind of /run/secrets — which is a symlink
  # to a per-generation directory REPLACED on every deploy, so a mount
  # established at container start would keep exposing a deleted generation.
  # M5, M9, M13 and M14 all record this.
  #
  # ENV FILES rather than mounted secret files, because RomM's image takes its
  # database credentials only as environment variables (`DB_PASSWD`); there is
  # no `_FILE` variant to prefer.  They are read by podman as root before the
  # container drops to ${toString rommUid}, so 0400 root:root is correct and
  # the values never appear in a world-readable /proc/<pid>/environ of ours.
  #
  # requiredBy, NOT wantedBy: neither container starts usefully without these,
  # so a container that started anyway would just be a restart loop in a
  # different unit's journal.
  systemd.services.romm-secrets = {
    description = "Stage RomM's generated secrets as container env files";
    requiredBy = [ "podman-romm.service" "podman-romm-db.service" ];
    before     = [ "podman-romm.service" "podman-romm-db.service" ];
    after      = [ "local-fs.target" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script =
      let
        authKey = config.clan.core.vars.generators.romm-auth-secret.files."secret-key".path;
        dbPw    = config.clan.core.vars.generators.romm-db-password.files."password".path;
        rootPw  = config.clan.core.vars.generators.romm-db-root-password.files."password".path;
        meta    = config.clan.core.vars.generators.romm-metadata-keys.files;
        sgdbKey = meta."steamgriddb-api-key".path;
        igdbId  = meta."igdb-client-id".path;
        igdbSec = meta."igdb-client-secret".path;
      in
      ''
        set -eu
        umask 077
        ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root ${secretsDir}

        auth=$(${pkgs.coreutils}/bin/cat ${authKey})
        dbpw=$(${pkgs.coreutils}/bin/cat ${dbPw})
        rootpw=$(${pkgs.coreutils}/bin/cat ${rootPw})
        sgdb=$(${pkgs.coreutils}/bin/cat ${sgdbKey})
        igdbid=$(${pkgs.coreutils}/bin/cat ${igdbId})
        igdbsec=$(${pkgs.coreutils}/bin/cat ${igdbSec})

        ${pkgs.coreutils}/bin/install -m 0400 -o root -g root /dev/null ${secretsDir}/romm.env
        ${pkgs.coreutils}/bin/cat > ${secretsDir}/romm.env <<EOF
        ROMM_AUTH_SECRET_KEY=$auth
        DB_PASSWD=$dbpw
        STEAMGRIDDB_API_KEY=$sgdb
        IGDB_CLIENT_ID=$igdbid
        IGDB_CLIENT_SECRET=$igdbsec
        EOF

        ${pkgs.coreutils}/bin/install -m 0400 -o root -g root /dev/null ${secretsDir}/romm-db.env
        ${pkgs.coreutils}/bin/cat > ${secretsDir}/romm-db.env <<EOF
        MARIADB_ROOT_PASSWORD=$rootpw
        MARIADB_PASSWORD=$dbpw
        EOF
      '';
  };

  ##############################################################################
  # The containers.
  ##############################################################################

  # MariaDB.  Reachable only over `lo` inside the namespace — see the header.
  virtualisation.oci-containers.containers.romm-db = {
    image = "docker.io/library/mariadb@${dbDigest}";

    environment = {
      TZ                = "Europe/Berlin";
      MARIADB_DATABASE  = "romm";
      MARIADB_USER      = "romm-user";
    };
    environmentFiles = [ "${secretsDir}/romm-db.env" ];

    volumes = [ "${stateDir}/mysql:/var/lib/mysql" ];

    # NO `ports` entry, deliberately — meaningless with `--network=ns:`, and in
    # this case actively undesirable: the database has no business being
    # addressable at all.
    ports = [ ];

    extraOptions = [
      "--network=ns:/run/netns/${netns}"
      "--dns=10.0.5.3"
      "--dns-search=skynet.lan"
      # Same uid as RomM: one service, one identity on the pool.  The datadir
      # is created 0750 with that owner by romm-dirs above, which is what makes
      # running the image unprivileged possible at all.
      "--user=${toString rommUid}:${toString rommGid}"
      # Bind the listener to loopback explicitly rather than relying on the
      # firewall alone.  Defence in depth is cheap here and it documents the
      # intent at the point someone would otherwise wonder.
      "--health-cmd=healthcheck.sh --connect --innodb_initialized"
    ];
    cmd = [ "--bind-address=127.0.0.1" ];
  };

  virtualisation.oci-containers.containers.romm = {
    image = "docker.io/rommapp/romm@${rommDigest}";

    environment = {
      TZ = "Europe/Berlin";

      # 127.0.0.1 — the database is in this same namespace.  Upstream's compose
      # uses the compose service name here; there is no DNS between these two
      # containers because there is no podman network, by design.
      DB_HOST = "127.0.0.1";
      DB_NAME = "romm";
      DB_USER = "romm-user";
      # DB_PASSWD and ROMM_AUTH_SECRET_KEY arrive via environmentFiles.

      ROMM_PORT = toString webPort;

      # Hasheous is the one metadata source that needs NO account and NO API
      # key, so it is enabled unconditionally and makes a scan useful even
      # before anyone has signed up for anything.
      #
      # IGDB and SteamGridDB need credentials tied to a personal account.  They
      # arrive through environmentFiles as the `romm-metadata-keys` prompted
      # generator below — the empty-prompt path leaves them unset, so a machine
      # whose owner has not signed up still deploys and still scans.
      HASHEOUS_API_ENABLED = "true";

      # ── Why these two are set, and what happens when they are not ──────────
      #
      # SCAN_WORKERS is an asyncio.Semaphore around per-ROM scanning
      # (endpoints/sockets/scan.py), and it DEFAULTS TO 1 — the scan is
      # entirely serial, and every ROM is a round trip to IGDB, SteamGridDB and
      # Hasheous.  Measured on the first real scan: ~150 ROMs/hour, degrading
      # from 235 in the first hour to 93 by the fourth.
      #
      # SCAN_TIMEOUT is an rq job timeout, and it DEFAULTS TO 4 HOURS.  When it
      # fires the job dies with rq.timeouts.JobTimeoutException and takes the
      # whole tail of the scan with it.  That is not a cosmetic failure: the
      # gamelist.xml export runs at the END of the job, so a scan that times
      # out silently produces no ES-DE metadata at all — which is exactly how
      # this library sat at "gamelist.xml: 0" while `scan.gamelist.export` was
      # correctly set to true and being read.  ROMs already committed do
      # survive, so a timed-out scan looks like a partial success rather than a
      # crash: 531 of ~5000 files, three platforms out of five.
      #
      # 4 workers, not more, because there is NO rate limiter in
      # handler/metadata/igdb_handler.py and IGDB's documented ceiling is 4
      # requests per second.  Each ROM also costs local hashing and SteamGridDB
      # and Hasheous calls, so 4 concurrent ROMs stays under that ceiling
      # rather than racing it.
      #
      # 24 hours, not 4, because the library is 37k files across 26 platforms.
      # Even at 4× the measured rate a full pass does not fit in an afternoon,
      # and the point of the timeout is to catch a wedged scan — not to cap a
      # legitimately long one.
      SCAN_WORKERS = "4";
      SCAN_TIMEOUT = toString (24 * 60 * 60);
    };
    environmentFiles = [ "${secretsDir}/romm.env" ];

    volumes = [
      # The library.  Read-write: RomM can accept uploads through the web UI,
      # and that is the intended way to add a game from a machine that is not
      # birte.
      "${libraryDir}:/romm/library"
      # Fetched artwork and metadata — large, and re-fetchable, but re-fetching
      # a whole library's covers is slow enough to be worth persisting.
      "${stateDir}/resources:/romm/resources"
      # Saves, states and screenshots RomM manages itself.
      "${stateDir}/assets:/romm/assets"
      # config.yml lives here.  It is where the platform-name mapping and the
      # ES-DE gamelist export get configured; RomM rewrites this file itself,
      # so it is a volume rather than anything generated from Nix.
      "${stateDir}/config:/romm/config"
      # The image runs its own redis for background tasks.
      "${stateDir}/redis:/redis-data"
    ];

    ports = [ ];

    dependsOn = [ "romm-db" ];

    extraOptions = [
      "--network=ns:/run/netns/${netns}"
      "--dns=10.0.5.3"
      "--dns-search=skynet.lan"
      "--user=${toString rommUid}:${toString rommGid}"
    ];
  };

  ##############################################################################
  # Ordering and the resource budget.
  ##############################################################################

  systemd.services.podman-romm-db = {
    after    = [ "romm-netns.service" "romm-dirs.service" ];
    requires = [ "romm-netns.service" "romm-dirs.service" ];
  };

  systemd.services.podman-romm = {
    after    = [ "romm-netns.service" "romm-dhcp.service" "romm-dirs.service" "podman-romm-db.service" ];
    requires = [ "romm-netns.service" "romm-dirs.service" "podman-romm-db.service" ];

    serviceConfig = {
      # A library scan hashes every file it has not seen before.  On a
      # cold first scan of a large library that is hours of sustained IO and a
      # real amount of CPU, competing with a Jellyfin transcode, the HTPC
      # session on the TV, and an interactive Ollama session — the last of
      # which is the claimant whose degradation is hardest to attribute.
      #
      # Same two mechanisms, and the same reasoning, as Storyteller's:
      #   Nice = 10        lowers priority against everything on the box.
      #   CPUWeight = 40   biases the cgroup's share only under contention.
      # Not CPUQuota: nobody is waiting on a scan, so it should be free to use
      # an otherwise idle box at full speed.
      #
      # Less aggressive than Storyteller's 15/20 because a scan is bounded and
      # occasionally a human IS waiting on it (adding one game and wanting to
      # see it), whereas forced alignment is pure batch.
      Nice      = 10;
      CPUWeight = 40;
    };
  };

  ##############################################################################
  # `rom-import` — moving a finished download into the library.
  #
  # This lives here, rather than in a script pasted into the guide, for one
  # reason: the constants below (uid 3029, the `romm` gid, /srv/roms, the
  # roms/bios split) are DEFINED in this file, and a copy of them in a document
  # is a copy that goes stale silently.  The tool is generated from the same
  # `let` bindings the container is, so it cannot disagree with the deployment.
  #
  # WHY A TOOL AND NOT `cp`.  Every import has to get four things right, and
  # each of them has already cost a session:
  #
  #   1. COPY, NEVER MOVE.  qBittorrent goes on seeding what it downloaded;
  #      moving the files out from under it kills the torrent.
  #   2. Collections bundle EMULATORS.  A Switch grab shipped Ryujinx and Yuzu
  #      inside the same archive, and they landed in the library because the
  #      copy was unfiltered.  Hence -e, and the nested-archive warning.
  #   3. Ownership.  A fresh directory is root:root and the setgid bit fixes
  #      only the GROUP of new files, never the owner — so RomM (uid 3029)
  #      cannot write its own resources next to ROMs it cannot chown.
  #   4. Staging must be on the SAME dataset and OUTSIDE roms/ and bios/.
  #      Those two directories are Syncthing folders and RomM's scan targets;
  #      a half-extracted 8 GB pack visible there gets replicated to birte and
  #      indexed mid-flight.  /srv/roms/.staging is on the dataset (so the copy
  #      is rename-speed) but in neither folder.
  #
  # The one thing it does NOT do is decide WHICH platform a file belongs to.
  # That needs a human: the directory name is read literally by ES-DE on birte
  # and cannot be remapped afterwards.  See docs/guides/birte-emulation.md.
  ##############################################################################

  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "rom-import";

      runtimeInputs = with pkgs; [
        coreutils findutils gnugrep gnused gawk
        p7zip          # .7z and .zip
        unar           # .rar — p7zip 17.x dropped the non-free Rar codec, so
                       # `7z l` reports "Can not open the file as archive" on a
                       # perfectly good RAR.  lsar/unar are the free path.
        curl jq        # the qBittorrent WebUI API, for `rom-import list`
        util-linux     # column
      ];

      text = ''
        LIB=${libraryDir}
        ROMM_UID=${toString rommUid}
        ROMM_GID=${toString rommGid}

        # qBittorrent runs in the WireGuard microvm; its WebUI is reachable on
        # the container VLAN.  The password is the SAME clan var the arr stack
        # authenticates with — one generator, and this is a third consumer, so
        # a rotation cannot leave this tool behind holding a stale copy.
        QBT=http://10.0.90.11:8080
        # Quoted deliberately: to shellcheck a bare `admin` reads as a command
        # substitution that lost its $( ) — SC2209, and writeShellApplication
        # fails the build on it.
        QBT_USER="admin"
        QBT_PWFILE=${config.clan.core.vars.generators.qbittorrent-webui.files."password".path}
        CATS=prowlarr,games

        ${builtins.readFile ../rom-import.sh}
      '';
    })
  ];
}
