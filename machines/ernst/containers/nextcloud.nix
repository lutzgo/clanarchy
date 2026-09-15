# machines/ernst/containers/nextcloud.nix
#
# Nextcloud — the household file-sync, calendar and contacts server (M23 in
# docs/roadmap.md).  An nspawn container on VLAN 90, serving
# `cloud.goclan.org` through Traefik on BOTH entrypoints, with its own
# accounts, no forward-auth, and Authelia as an OIDC provider for the browser.
#
# ── WHAT THIS REPLACES ──────────────────────────────────────────────────────
#
#   The hosted instance at citizengo.io.  M22b already pulled its PHOTO corpus
#   into Immich (see containers/immich.nix, the `nextcloud` import sets); what
#   is left over there is the file tree the desktop sync clients point at, and
#   the CalDAV endpoint modules/caldav-sync.nix pushes lgo's org VTODOs to.
#   This container is what lets that instance be turned off.
#
#   IT STANDS UP EMPTY.  Nothing here downloads anything from citizengo.io —
#   migrating the remaining file corpus is its own milestone, exactly as M22b
#   was for the photographs, and for the same reason: choosing what comes
#   across is a triage decision and not a script.
#
# ── WHY THE nspawn TIER ─────────────────────────────────────────────────────
#
#   `services.nextcloud` is a first-class NixOS module.  The podman tier here
#   exists for upstreams that ship only an OCI image (storyteller, cwa, romm,
#   tubesync) and Nextcloud is not one of them.  An internet-facing service
#   does not move up a tier for being internet-facing; it moves up for needing
#   its own kernel.  containers/immich.nix argues this at length and this file
#   takes the same side for the same reason.
#
# ── NO forward-auth ON THIS HOSTNAME, AND IT IS NOT A CONVENIENCE ───────────
#
#   `cloud.goclan.org` is in `appApiHosts` (containers/ingress-policy.nix).
#   The test that file states is whether EVERY client of the hostname can
#   render a login page and follow a 302, and here three cannot:
#
#     * the Nextcloud desktop sync client on miralda, jens and biene
#       (modules/desktop/noctalia-hm.nix already installs it), which
#       authenticates with an app password over /remote.php/dav/**;
#     * DAVx5 on the phones, same protocol, no browser at all;
#     * vdirsyncer, run headless from a user timer on miralda.
#
#   So the vhost is answered by Nextcloud, not by Authelia — and the BROWSER
#   path gets its second factor from Authelia's OIDC provider instead.  That is
#   Calibre-Web-Automated's arrangement (containers/cwa.nix), NOT Grafana's or
#   Open WebUI's: those two are behind forward-auth AND take OIDC, because the
#   middleware decides whether the request arrives and OIDC decides whose it
#   is.  Here OIDC is INSTEAD OF the middleware.  Do not merge the two
#   reasonings; containers/authelia.nix says so at the client block.
#
#   The compensating controls `appApiHosts` demands are, in order: Nextcloud's
#   own accounts, `wan-ratelimit` + `wan-inflight`, CrowdSec reading Traefik's
#   access log, and Nextcloud's OWN brute-force throttle — which is real, on by
#   default, and depends entirely on `trusted_proxies` below being right.  See
#   the note there; it is the one line in this file that turns a control into
#   a decoration if it is wrong.
#
# ── WHAT IS DELIBERATELY NOT HERE ───────────────────────────────────────────
#
#   `services.nextcloud.notify_push` — the push daemon that lets desktop
#   clients stop polling.  It is genuinely wanted and it does not work behind
#   this proxy as configured: `notify_push.nextcloudUrl` defaults to
#   `https://${hostName}`, and its `bendDomainToLocalhost` escape points that
#   name at 127.0.0.1 — where nothing listens on 443, because the container's
#   nginx terminates plain HTTP on 80 and TLS is Traefik's job.  Enabling it
#   would need a second local listener whose only purpose is to satisfy a
#   self-test.  Recorded as a decision rather than an oversight; it is a
#   follow-on, not a defect.
#
#   A Prometheus scrape target.  Nextcloud's serverinfo endpoint is
#   token-authenticated JSON, not an OpenMetrics exposition, so a job pointed
#   at it could only ever be `up == 0` — which is M13's Ollama lesson, and
#   service-modules/monitoring.nix is disciplined about not adding targets that
#   cannot work.  What this container DOES get for free, because it is nspawn
#   and `machinectl` can see it, is `ContainerSystemdUnitFailed`: any failed
#   unit inside it is a host-side metric within a minute.  That is the alerting
#   story here, and it is enough for a first deploy.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  ##############################################################################
  # Identity.
  ##############################################################################

  # From the allocation table in machines/ernst/networking.nix.  OWN group, not
  # `media` — `media` is a SECONDARY membership below, for the external storage
  # mount, and making it primary would put the media gid on every file the
  # service writes into its own store.
  #
  # PINNING IT IS LOAD-BEARING, not hygiene, for exactly the reason Immich's
  # row in that table gives: the nixpkgs module creates `nextcloud` with
  # `isSystemUser = true` and no uid, and nspawn passes ids through UNMAPPED,
  # so whatever the container's useradd happens to pick is the number that ends
  # up on every file in /srv/nextcloud.  Adding an unrelated user to this
  # container could otherwise change the owner of the household's file store.
  nextcloudUid = 3037;
  nextcloudGid = 3037;

  # Not ours to choose: a well-known NixOS static id (`ids.uids.postgres`).  It
  # lands on zdata unmapped like every other container uid here.  The
  # 3000-block convention does not apply to it and it must not be renumbered
  # into the block.
  postgresUid = 71;
  postgresGid = 71;

  # The host-side media group from containers/jellyfin.nix, restated here
  # because a container config is its own NixOS evaluation and cannot read the
  # host's option tree.  This is the "group-add, not a chown" that jellyfin.nix
  # anticipated when it created the group.
  mediaGid = 3000;

  ##############################################################################
  # Peers, ports and paths.
  ##############################################################################

  # The one VLAN-90 peer allowed to reach this service.  Every client — the
  # laptops' sync agents, the phones, a browser, vdirsyncer — arrives through
  # it.  This is M5's backend-bypass hardening, mechanism (a).
  traefikAddr = "10.0.90.12";

  # Plain HTTP on 80, terminated by the container's own nginx.  TLS is
  # Traefik's, once, at the edge, with the *.goclan.org wildcard it already
  # holds — nothing here requests a certificate.
  nextcloudPort = 80;

  baseDomain = "goclan.org";
  hostName   = "cloud.${baseDomain}";

  # Authelia's portal, as the OIDC issuer.  Restated rather than shared for the
  # same reason baseDomain is restated in traefik.nix and authelia.nix.
  autheliaIssuer = "https://auth.${baseDomain}";

  # THE TWO DATASETS, SPLIT FOR THE REASON IMMICH SPLIT ITS OWN: a 1M
  # recordsize is right for a bulk file store and wrong for PostgreSQL.
  #
  # zdata/nextcloud holds config/, data/ and store-apps/ — the module's whole
  # `home`.  recordsize is a MAXIMUM, not a quantum, so the small files in
  # config/ cost nothing there; what it buys is that a 4 GB upload is not
  # 32,768 records.  Nextcloud writes user files whole over WebDAV and never
  # does an in-place partial rewrite of a large one, which is the access
  # pattern that would make 1M the wrong answer.
  dataRoot  = "/srv/nextcloud";
  stateRoot = "/srv/state/nextcloud";

  # The media library, bound in READ-ONLY as external storage.  Read-only at
  # the NSPAWN level rather than as a files_external option, because a mount
  # flag is enforced by the kernel and an app setting is enforced by whatever
  # the app believes about itself.
  mediaRoot = "/srv/media";

  ##############################################################################
  # Secrets staging.
  #
  # NOT a bind of /run/secrets itself: that path is a symlink to a
  # per-generation directory which is REPLACED on every deploy, so an nspawn
  # bind established at container start would keep exposing a deleted
  # generation.  A directory we own has a stable identity and is rewritten in
  # place.  containers/traefik.nix carries the long form of this.
  ##############################################################################
  secretsDir     = "/run/nextcloud-secrets";
  adminPassFile  = "${secretsDir}/admin-pass";
  oidcSecretFile = "${secretsDir}/oidc-client-secret";

  adminGen = config.clan.core.vars.generators.nextcloud-admin;

  # Declared in containers/authelia.nix, beside the other relying parties —
  # ONE GENERATOR PER RELYING PARTY is that file's rule, and it is why this
  # reaches across rather than declaring its own.  Authelia takes the DIGEST;
  # this container takes the PLAINTEXT half of the same pair.
  oidcGen = config.clan.core.vars.generators.authelia-oidc-nextcloud;
in
{
  ##############################################################################
  # Host side — the datasets, the directories, the secrets and the veth.
  ##############################################################################

  # ── NO tmpfiles RULES IN THIS FILE, AND containers/immich.nix IS WHY ───────
  #
  # That file records the measured failure: three of its four host-side
  # directories shipped as `systemd.tmpfiles.rules` and the container died
  # five times into its start limit with
  #
  #     systemd-nspawn: Failed to clone /srv/state/immich/ml-cache:
  #                     No such file or directory
  #
  # because activating a new configuration does not re-run
  # systemd-tmpfiles-setup.service in time for a container the same activation
  # starts.  Every host-side directory this container binds therefore belongs
  # to the ordered unit below, and NONE of them is also a tmpfiles rule — two
  # declarations for one path is the M3 defect, where two rules that disagree
  # about mode take turns winning, one per deploy.
  systemd.services.nextcloud-dirs = {
    description = "Verify Nextcloud's datasets are mounted and create its directories";
    wantedBy   = [ "multi-user.target" ];
    after      = [ "srv-nextcloud.mount" "srv-state.mount" ];
    requires   = [ "srv-nextcloud.mount" "srv-state.mount" ];
    before     = [ "container@nextcloud.service" ];
    requiredBy = [ "container@nextcloud.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.util-linux pkgs.coreutils ];

    # BLOCKING (`requires` + `requiredBy`), not advisory.  containers/arr.nix
    # uses `before` only for /srv/audiobooks, on the argument that Sonarr must
    # not go down because an unrelated library is missing.  That argument does
    # not transfer: /srv/nextcloud is not one library among several inside a
    # shared container, it is this container's entire reason to exist AND the
    # module's `home`.  A Nextcloud that starts without it is not a degraded
    # Nextcloud — it is a NEW, EMPTY one on zroot, which will accept a laptop's
    # whole sync, report success to the client, and lose the lot at the next
    # boot.  That is storyteller.nix's case, so it gets storyteller's treatment.
    #
    # It FAILS rather than repairing itself: a unit that silently fixes storage
    # layout hides the fact that the layout was wrong.
    script = ''
      set -eu

      # findmnt, not `mountpoint`: this has to check WHAT is mounted, not just
      # that something is.  /srv/nextcloud carries `nofail`
      # (machines/ernst/disko.nix), so the mount unit can fail while
      # /srv/nextcloud still exists as an ordinary directory on zroot —
      # precisely the case a bare mountpoint test passes.
      src=$(findmnt --noheadings --output SOURCE --target ${dataRoot} || true)
      fstype=$(findmnt --noheadings --output FSTYPE --target ${dataRoot} || true)

      if [ "$src" != "zdata/nextcloud" ] || [ "$fstype" != "zfs" ]; then
        echo "nextcloud-dirs: ${dataRoot} is NOT zdata/nextcloud." >&2
        echo "  found: source='$src' fstype='$fstype'" >&2
        echo "" >&2
        echo "  Refusing to create it, because doing so would put the" >&2
        echo "  household's file store on zroot, which rolls back on every" >&2
        echo "  boot — and every sync client would report success meanwhile." >&2
        echo "" >&2
        echo "  The dataset must exist AND carry mountpoint=legacy — a ZFS" >&2
        echo "  dataset without it cannot be mounted by mount(8) at all:" >&2
        echo "" >&2
        echo "    zfs create -o mountpoint=legacy -o recordsize=1M \\" >&2
        echo "      -o exec=off -o setuid=off -o devices=off -o atime=off \\" >&2
        echo "      -o com.sun:auto-snapshot=true zdata/nextcloud" >&2
        echo "" >&2
        echo "  If it exists already:  zfs set mountpoint=legacy zdata/nextcloud" >&2
        echo "  Then:                  systemctl start srv-nextcloud.mount" >&2
        echo "  See docs/guides/ernst-zdata-datasets.md." >&2
        exit 1
      fi

      # THE TARGET IS THE PARENT, NOT ${stateRoot}, and that is not tidiness.
      # `findmnt --target` on a path that DOES NOT EXIST YET returns nothing —
      # it does not walk up to the nearest existing ancestor — so checking
      # ${stateRoot} here would fail on every first run, before this unit has
      # had a chance to create it.  immich-dirs refused its own first deploy
      # that way on 2026-09-11.
      ssrc=$(findmnt --noheadings --output SOURCE --target /srv/state || true)
      if [ "$ssrc" != "zdata/state" ]; then
        echo "nextcloud-dirs: /srv/state is not zdata/state (found '$ssrc')." >&2
        echo "  Refusing to create Nextcloud's database directory, because it" >&2
        echo "  would land on zroot and be rolled back on the next boot." >&2
        exit 1
      fi

      # NUMERIC ids on purpose: `nextcloud` and `postgres` are CONTAINER users
      # and the host has no matching passwd entries.  Same shape traefik.nix
      # uses for uid 3005.
      #
      # ── 0700 IS ASKED FOR HERE AND 0750 IS WHAT LANDS.  MEASURED. ────────
      #
      # On the first deploy (2026-09-15) the store came out `drwxr-x---` on
      # the host despite this line.  The nixpkgs module ships its own tmpfiles
      # rules INSIDE the container —
      #
      #     d /var/lib/nextcloud            0750 nextcloud nextcloud
      #     d /var/lib/nextcloud/config     0750 nextcloud nextcloud
      #     d /var/lib/nextcloud/data       0750 nextcloud nextcloud
      #     d /var/lib/nextcloud/store-apps 0750 nextcloud nextcloud
      #
      # — and those run on every container start, against the same inodes this
      # line created, through the bind mount.  It is the Immich
      # `StateDirectoryMode` finding in a different costume: upstream re-asserts
      # a mode after we have set ours, and upstream wins.
      #
      # IT IS NOT FORCED BACK, and the two reasons are worth keeping apart.
      #
      #   The cheap one: fixing it would mean declaring a competing tmpfiles
      #   rule for a path the module already declares, and two rules for one
      #   path that disagree about mode take turns winning, one per deploy.
      #   That is the M3 defect, which this file warns about twenty lines up.
      #
      #   The real one: 0750 IS NOT AN EXPOSURE HERE, and the check is
      #   specific rather than reassuring.  The group is gid 3037, and
      #   `getent group 3037` ON THE HOST RETURNS NOTHING — no host user is in
      #   it.  `go`, the couch account that autologins on the television
      #   without a password, is `uid=1001 gid=100(users)` plus audio, video
      #   and input, and is not.  So the group bit grants nobody anything.
      #
      #   THAT IS EXACTLY WHERE THIS DIFFERS FROM IMMICH, and why that file
      #   spends two lines forcing its mode and this one does not: /srv/photos
      #   came out 0755, and the o+r bit is what `go` could have used.  0750
      #   has no o+r bit.  If a host-side group 3037 is ever created, or a user
      #   is ever added to it, this paragraph stops being true — re-read it
      #   then rather than trusting it.
      install -d -o ${toString nextcloudUid} -g ${toString nextcloudGid} -m 0700 ${dataRoot}

      # The same applies to PostgreSQL's directory, which also settles at 0750.
      # That one is fine by upstream's own rules: PostgreSQL refuses to start
      # on a world-readable data directory, but has accepted group-readable
      # (0750) since version 11.  It is running, which is the proof.
      install -d -o ${toString nextcloudUid} -g ${toString nextcloudGid} -m 0700 ${stateRoot}
      install -d -o ${toString postgresUid}  -g ${toString postgresGid}  -m 0700 ${stateRoot}/postgresql
    '';
  };

  # ── Stage the secrets where the container can see them ────────────────────
  #
  # ROTATING EITHER OF THEM needs a restart, not just a deploy: this unit's
  # script embeds the sops PATH and not the contents, so systemd sees an
  # unchanged unit and does not re-run it.  Both generators therefore carry
  # `restartUnits`, which is what makes `clan vars generate ernst` +
  # `clan machines update ernst` sufficient.  By hand it is:
  #     systemctl restart nextcloud-secrets container@nextcloud
  systemd.services.nextcloud-secrets = {
    description = "Stage Nextcloud's admin password and OIDC secret for container@nextcloud";
    after       = [ "local-fs.target" ];
    before      = [ "container@nextcloud.service" ];
    requiredBy  = [ "container@nextcloud.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils ];
    script = ''
      set -euo pipefail

      # 0711: traversable by anyone, listable by nobody.  The files inside are
      # read by the NEXTCLOUD uid, unprivileged — nextcloud-setup.service runs
      # as `nextcloud`, not as PID 1 — so it must be able to walk in, and
      # 0700 root:root here would produce EACCES on every one of them with a
      # message that names the file rather than the directory.  See PR #84,
      # which shipped that inversion once.
      install -d -m 0711 -o root -g root ${secretsDir}

      install -m 0400 -o ${toString nextcloudUid} -g ${toString nextcloudGid} \
        ${adminGen.files."admin-pass".path} ${adminPassFile}

      install -m 0400 -o ${toString nextcloudUid} -g ${toString nextcloudGid} \
        ${oidcGen.files."nextcloud-client-secret".path} ${oidcSecretFile}
    '';
  };

  # ── The admin password ────────────────────────────────────────────────────
  #
  # GENERATED, NOT PROMPTED, and read out of sops when it is needed:
  #
  #     clan vars get ernst nextcloud-admin/admin-pass
  #
  # A prompt here would be a password a human chose for an account that is the
  # RECOVERY PATH — the local login that still works when Authelia, the OIDC
  # client registration, or Traefik is what is broken.  It should be long and
  # it should not be memorable.
  #
  # `tr -d '=+/'` because this string is typed into a login form and pasted
  # into shell one-liners; the base64 punctuation buys nothing here and costs
  # quoting mistakes.  32 bytes of entropy survive it comfortably.
  clan.core.vars.generators.nextcloud-admin = {
    files."admin-pass".secret = true;
    files."admin-pass".restartUnits = [
      "nextcloud-secrets.service"
      "container@nextcloud.service"
    ];
    runtimeInputs = [ pkgs.coreutils pkgs.openssl ];
    script = ''
      openssl rand -base64 48 | tr -d '\n=+/' | cut -c1-48 > "$out/admin-pass"
    '';
  };

  # Host side of the container's veth — a VLAN-90 port on br0.  Identical
  # rationale to vb-immich / vb-jellyfin / vb-arr; see containers/traefik.nix
  # for the long form of KeepMaster-not-Bridge and why a bridge port carries no
  # address of its own.
  systemd.network.networks."60-vb-nextcloud" = {
    matchConfig.Name = "vb-nextcloud";
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
  # `bridge vlan show dev vb-nextcloud` is the check.
  systemd.services."container@nextcloud".serviceConfig.ExecStartPost = [
    "-${pkgs.iproute2}/bin/bridge vlan add dev vb-nextcloud vid 90 pvid untagged"
  ];

  ##############################################################################
  # The container.
  ##############################################################################
  containers.nextcloud = {
    autoStart = true;
    ephemeral = false;

    # MAC from the allocation table in machines/ernst/networking.nix; the DHCP
    # reservation 10.0.90.26 on the UDM-Pro keys on it (manual step).  Sequence
    # 12, and the last octet is 8 + seq as everywhere else on this bridge.
    privateNetwork  = true;
    hostBridge      = "br0";
    localMacAddress = "02:00:00:90:00:12";

    bindMounts = {
      # The store, bound at the module's OWN default (`services.nextcloud.home`)
      # so that `home`, `datadir` and the module's tmpfiles rules all agree with
      # nothing overridden.  Same trick as Immich's /var/lib/immich.
      "/var/lib/nextcloud" = {
        hostPath   = dataRoot;
        isReadOnly = false;
      };

      # The database.  The PARENT is bound, not the version subdirectory, so a
      # future PostgreSQL major bump lands beside the old one on zdata instead
      # of on the container's rootfs.
      "/var/lib/postgresql" = {
        hostPath   = "${stateRoot}/postgresql";
        isReadOnly = false;
      };

      # The media library as external storage.  READ-ONLY at the mount, which
      # is the actual boundary; the files_external entry below is only what
      # makes it visible in the UI.
      "${mediaRoot}" = {
        hostPath   = mediaRoot;
        isReadOnly = true;
      };

      "${secretsDir}" = {
        hostPath   = secretsDir;
        isReadOnly = true;
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
          # but NOT link-local assignment; this is the line that actually makes
          # `ip -6 addr show dev eth0` empty.
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
      #   80/tcp  ONLY from Traefik.  Every client of this service arrives
      #           through the proxy.
      #
      # extraCommands, not extraInputRules: the latter is declared
      # unconditionally but consumed only under networking.nftables, so here it
      # would produce no rule and no warning.  containers/traefik.nix is the
      # only nftables container on this machine.
      networking.firewall.allowedTCPPorts = [ ];
      networking.firewall.extraCommands = ''
        iptables -A nixos-fw -p tcp -s ${traefikAddr}/32 --dport ${toString nextcloudPort} -j nixos-fw-accept
      '';

      ##########################################################################
      # The service.
      ##########################################################################
      services.nextcloud = {
        enable = true;

        # PINNED EXPLICITLY, AND TO THE stateVersion DEFAULT.  nixpkgs carries
        # 31 through 34 at this pin, and the module derives a default from
        # `system.stateVersion` — 33 for 26.05.
        #
        # An earlier draft took 32, on the reasoning that the oldest supported
        # major makes the first in-place upgrade a deliberate act rather than a
        # side effect of the initial deploy.  THAT ARGUMENT IS FOR AN EXISTING
        # INSTANCE AND THIS ONE STARTS EMPTY: there is nothing to upgrade, so
        # all it bought was the module's legacy-install warning on every single
        # evaluation.  A deploy that always prints a warning is a deploy nobody
        # reads — that is a standing item in docs/roadmap.md's backlog.
        #
        # It is still written out rather than left to the default, because the
        # default moves with `system.stateVersion`, and a Nextcloud major must
        # never move as a side effect of editing an unrelated line.  Bumping it
        # is an edit here, with a `zfs snapshot zdata/nextcloud` first.
        package = pkgs.nextcloud33;

        inherit hostName;

        # Tells the module to emit `fastcgi_param HTTPS on` and the HSTS
        # header.  It does NOT make nginx listen on 443 and does not request a
        # certificate: TLS is terminated once, at Traefik, with the wildcard it
        # already holds.
        https = true;

        # Local PostgreSQL over the unix socket at /run/postgresql.
        #
        # THIS FILE THEREFORE DECLARES NO DATABASE PASSWORD AND NO DATABASE
        # STAGING UNIT, and that is the same argument containers/immich.nix
        # makes: `dbhost` defaults to the socket, socket connections use peer
        # authentication, and a credential that is never checked is a
        # credential that should not exist.  A `nextcloud-db-password`
        # generator would be a generator nothing reads.
        database.createLocally = true;
        config.dbtype = "pgsql";

        # The local account, and the RECOVERY PATH.  It remains a Nextcloud
        # password login after OIDC is registered below, which is the point:
        # when the portal, the client registration or Traefik is what is
        # broken, this is the way back in.  `root` is the module's default and
        # is a confusing name for a Nextcloud user.
        config.adminuser = "ncadmin";
        config.adminpassFile = adminPassFile;

        # Redis for the distributed cache and the file-locking backend, over
        # its unix socket.  APCu stays the local cache (`caching.apcu`, on by
        # default).  Redis lives on the container's own rootfs under
        # /var/lib/nixos-containers/nextcloud, which machines/ernst/configuration.nix
        # persists — it is a cache and has no business on zdata.
        configureRedis = true;

        # Raised from the module's 512M default.  This is a file-sync server;
        # the ceiling people actually hit is a video, and the corresponding
        # ceiling at the proxy is already high enough — traefik.nix sets
        # websecure's readTimeout to 3600s and wan's to 1800s, after a 1.1 GB
        # Immich upload died at exactly 60.000 s on 2026-09-14.
        maxUploadSize = "16G";

        settings = {
          # ── THE LINE THAT MAKES THE BRUTE-FORCE CONTROL REAL ──────────────
          #
          # Without it every request appears to come from 10.0.90.12 and two
          # separate things break in the same direction: Nextcloud's own
          # brute-force throttle keys on the client address, so ONE attacker
          # would lock out the whole household; and the logs an operator reads
          # during an incident would name the proxy instead of the client.
          #
          # `appApiHosts` in containers/ingress-policy.nix names the service's
          # own controls as compensation number 5 for having no forward-auth.
          # This is what turns that from a claim into a fact.
          trusted_proxies = [ traefikAddr ];

          # Traefik forwards the original Host, so `trusted_domains` (which the
          # module sets to hostName) is enough on its own — but the protocol is
          # NOT forwarded in a form PHP sees, and without this Nextcloud
          # generates http:// URLs for share links, DAV discovery and the OIDC
          # redirect.  The last of those fails closed at Authelia with
          # `invalid_redirect_uri`, which reads as an Authelia fault.
          overwriteprotocol = "https";

          # Silences the admin-panel warning and, more usefully, pins WHEN the
          # heavy background jobs run.  1 = 01:00 UTC.
          maintenance_window_start = 1;

          # Required for the Contacts app's phone-number handling; without it
          # every admin page carries a warning about it.
          default_phone_region = "DE";
        };

        # ── The apps, from nixpkgs' curated set ───────────────────────────
        #
        # NOT the in-app appstore, which is left at its default (off when
        # `extraApps` is set): an app store that can install code into
        # /var/lib/nextcloud at runtime is a second, unreviewed source of truth
        # for what this container runs, and this repository's whole argument is
        # against those.  Adding an app is a pull request.
        #
        # `files_external` is NOT listed and does not need to be — it ships
        # inside the Nextcloud tarball and is enabled by occ below.
        extraApps = {
          inherit (pkgs.nextcloud33Packages.apps)
            calendar      # CalDAV, replacing citizengo.io's
            contacts      # CardDAV
            tasks         # the VTODO surface modules/caldav-sync.nix pushes to
            notes
            user_oidc     # the Authelia login button
            ;
        };
        extraAppsEnable = true;
      };

      # ── Pin the ids ───────────────────────────────────────────────────────
      #
      # See the let block: unmapped nspawn ids mean a container-chosen number
      # is a number on the pool.  `media` is SECONDARY, for the read-only
      # external storage mount only.
      users.users.nextcloud.uid  = nextcloudUid;
      users.groups.nextcloud.gid = nextcloudGid;
      users.users.nextcloud.extraGroups = [ "media" ];
      users.groups.media.gid = mediaGid;

      ##########################################################################
      # ── Provisioning that only occ can express ──────────────────────────────
      #
      # Two things Nextcloud keeps in its DATABASE rather than in config.php,
      # so neither is reachable from `settings` above: the OIDC provider
      # registration and the external storage mount.
      #
      # `nextcloud-occ user_oidc:provider <name> …` is an UPSERT — it creates
      # on first run and updates on every subsequent one — so this unit is
      # idempotent across deploys by construction rather than by a stamp file.
      # A stamp file would be worse than nothing here: it would claim the
      # provider exists after somebody deleted it in the admin UI.
      ##########################################################################
      systemd.services.nextcloud-provision = {
        description = "Register the Authelia OIDC provider and the media external storage";
        wantedBy = [ "multi-user.target" ];
        after    = [ "nextcloud-setup.service" "phpfpm-nextcloud.service" "network-online.target" ];
        wants    = [ "network-online.target" ];
        requires = [ "nextcloud-setup.service" ];

        # ── IT RETRIES, AND THE REASON IS NOT GENERAL ROBUSTNESS ─────────────
        #
        # `user_oidc:provider --discoveryuri` FETCHES that URL when it runs, so
        # this unit depends on `auth.goclan.org` resolving through Technitium
        # AND on container@authelia being up behind Traefik — neither of which
        # this container can order against, because they are in a different
        # namespace and on the other side of the host's unit graph.  On a cold
        # boot of ernst, or on the very first deploy, losing that race is the
        # expected case rather than the exceptional one.
        #
        # It gives up after ten tries over ten minutes and STAYS FAILED, which
        # is deliberate: `ContainerSystemdUnitFailed` sees failed units inside
        # nspawn containers within a minute, so a genuine misconfiguration
        # alerts instead of being retried forever in silence.
        #
        # The visible symptom of this unit never succeeding is a Nextcloud
        # login page with only the local password form on it.
        startLimitIntervalSec = 600;
        startLimitBurst = 10;

        serviceConfig = {
          Type            = "oneshot";
          RemainAfterExit = true;
          Restart         = "on-failure";
          RestartSec      = "60s";
          # As `nextcloud`, like nextcloud-setup.service.  The occ wrapper does
          # NOT drop privileges, so running this as root would leave root-owned
          # files inside a store the service then cannot write.
          User  = "nextcloud";
          Group = "nextcloud";
        };
        path = [ config.services.nextcloud.occ pkgs.coreutils pkgs.gnugrep ];
        script = ''
          set -euo pipefail

          # ── Authelia as an OIDC provider ─────────────────────────────────
          #
          # THE SECRET PASSES THROUGH ARGV, and there is no alternative: the
          # command takes `--clientsecret=<value>` and has no stdin or file
          # form.  The exposure is /proc/<pid>/cmdline, for the life of one occ
          # invocation, inside a container whose only other unprivileged users
          # are nginx and postgres.  Stated rather than smoothed — if upstream
          # grows a file form, this should take it.
          #
          # `--unique-uid=0` maps accounts by the preferred_username claim
          # rather than by Authelia's opaque subject hash, so an OIDC login
          # lands on the SAME Nextcloud account a pre-existing local user
          # already has.  With it set to 1 the first Authelia login would
          # silently create a second, empty account beside the real one.
          nextcloud-occ user_oidc:provider Authelia \
            --clientid="nextcloud" \
            --clientsecret="$(cat ${oidcSecretFile})" \
            --discoveryuri="${autheliaIssuer}/.well-known/openid-configuration" \
            --scope="openid profile email groups" \
            --unique-uid=0 \
            --mapping-uid=preferred_username \
            --mapping-display-name=name \
            --mapping-email=email

          # Keep the local password form on the login page.  This is what makes
          # `ncadmin` above an actual recovery path rather than a decoration.
          nextcloud-occ config:app:set user_oidc allow_multiple_user_backends --value=1

          # ── /srv/media as read-only external storage ─────────────────────
          #
          # files_external ships in the tarball, so this enables rather than
          # installs.
          nextcloud-occ app:enable files_external

          # Idempotency without a stamp file: ask what is already mounted.  PHP
          # escapes forward slashes in JSON output (\/srv\/media), hence the
          # `tr -d`, which is cheaper and less brittle than a JSON parser for a
          # substring test.
          #
          # THE TEST IS DELIBERATELY LOOSE — a bare substring rather than the
          # exact `"datadir":"…"` pair — because the two ways it can be wrong
          # are not symmetric.  Too loose means the mount is never created,
          # which is visible in the UI on the first look.  Too strict means a
          # DUPLICATE MOUNT IS CREATED ON EVERY DEPLOY, silently, forever.
          #
          # NO --user AND NO --group, so this is a SYSTEM mount applicable to
          # every Nextcloud account.  That is the intent — it is the household
          # media library and the bind is read-only — and it is stated here
          # because "applicable to everyone" is a default rather than a flag,
          # and defaults are what nobody re-reads.  Narrow it in Settings →
          # External storage if that stops being true.
          if ! nextcloud-occ files_external:list --output=json | tr -d '\\' | grep -q '${mediaRoot}'; then
            nextcloud-occ files_external:create Media local null::null -c datadir=${mediaRoot}
          fi
        '';
      };

      # `curl` is the test plan's instrument for proving this backend is
      # reachable from Traefik and from nowhere else.
      environment.systemPackages = with pkgs; [ curl ];
      documentation.enable       = false;
      documentation.nixos.enable = false;
    };
  };
}
