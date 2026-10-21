# machines/ernst/containers/arr/common.nix
#
# The `arr` container itself: its veth, its storage, its firewall, its users,
# and `arr-api-keys` — the unit that extracts every service's API key at
# start so the rest of the stack can be configured declaratively.
#
# ── ONE CONTAINER, SIX FILES ────────────────────────────────────────────────
#
# This file DECLARES containers.arr. The five beside it add to it:
#
#     ./video.nix      sonarr, radarr, bazarr, seerr, recyclarr
#     ./indexers.nix   prowlarr, flaresolverr, umlautadaptarr, mediathekarr
#     ./music.nix      lidarr, soularr, navidrome, the beets staging tool
#     ./books.nix      audiobookshelf, komga, kapowarr, questarr, bindery
#     ./lifecycle.nix  janitorr, cleanuparr, scraparr
#     ./ids.nix        the numbers, addresses and paths they share (data)
#
# `containers.<name>.config` is a module option, so those five merge into the
# one declared here — the same mechanism containers/crowdsec.nix uses to put
# CrowdSec inside Traefik's namespace, and the one containers/homepage.nix
# already used to add a service to THIS container before the split.
#
# ── WHY IT WAS SPLIT ────────────────────────────────────────────────────────
#
# It was one 6,218-line file, which is about 87k tokens: two and a half times
# the context window of the model this repo is meant to be workable with, and
# past the point where a human finds anything either. The split is by MEDIA
# DOMAIN rather than by mechanism because that is how these services were
# added and how they are changed — a film-pipeline change touches Sonarr,
# Radarr and Bazarr together and nothing else.
#
# The service definitions themselves were MOVED, not rewritten. Each file
# re-exposes the handful of shared names its own blocks use (`ids.ports.sonarr`
# aliased back to `sonarrPort`), so the bodies are identical to what they were
# and the whole split is verifiable as a no-op: ernst's derivation hash is
# unchanged by it.
#
# ── THE SYSCALL FILTER IS APPLIED PER FILE, AND THAT IS DELIBERATE ──────────
#
# `ids.syscallFilter` is applied by each file to its own units. common.nix
# must NOT map it over `config.systemd.services` to catch them all: the
# attrset being read would be the one being defined, which is infinite
# recursion at eval. If a global application is ever wanted it needs an
# explicit list of unit names, not a fold over the service set.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  ids = import ./ids.nix;

  # The old flat names, so every block below is unchanged from the file it
  # came out of. See the header.
  inherit (ids) stateRoot audiobooksRoot;
  arrSyscallFilter = ids.syscallFilter;
  arrSecretsDir = ids.secretsDirs.arrApiKeys;
  arrMac = "02:00:00:90:00:05";
  vlanId = 90;
  vethName = "vb-arr";
  mediaGid = ids.gids.media;
  sonarrUid = ids.uids.sonarr;
  radarrUid = ids.uids.radarr;
  prowlarrUid = ids.uids.prowlarr;
  bazarrUid = ids.uids.bazarr;
  cleanuparrUid = ids.uids.cleanuparr;
  mediathekarrUid = ids.uids.mediathekarr;
  jellyseerrUid = ids.uids.jellyseerr;
  janitorrUid = ids.uids.janitorr;
  scraparrUid = ids.uids.scraparr;
  lidarrUid = ids.uids.lidarr;
  soularrUid = ids.uids.soularr;
  kapowarrUid = ids.uids.kapowarr;
  questarrUid = ids.uids.questarr;
  audiobookshelfUid = ids.uids.audiobookshelf;
  binderyUid = ids.uids.bindery;
  komgaUid = ids.uids.komga;
  navidromeUid = ids.uids.navidrome;
  prowlarrGid = ids.gids.prowlarr;
  jellyseerrGid = ids.gids.jellyseerr;
  scraparrGid = ids.gids.scraparr;
  questarrGid = ids.gids.questarr;
  sonarrPort = ids.ports.sonarr;
  radarrPort = ids.ports.radarr;
  prowlarrPort = ids.ports.prowlarr;
  flaresolverrPort = ids.ports.flaresolverr;
  bazarrPort = ids.ports.bazarr;
  cleanuparrPort = ids.ports.cleanuparr;
  jellyseerrPort = ids.ports.jellyseerr;
  scraparrPort = ids.ports.scraparr;
  janitorrPort = ids.ports.janitorr;
  lidarrPort = ids.ports.lidarr;
  kapowarrPort = ids.ports.kapowarr;
  questarrPort = ids.ports.questarr;
  audiobookshelfPort = ids.ports.audiobookshelf;
  binderyPort = ids.ports.bindery;
  komgaPort = ids.ports.komga;
  navidromePort = ids.ports.navidrome;
  mediathekarrDownloaderPort = ids.ports.mediathekarrDownloader;
  umlautadaptarrPort = ids.ports.umlautadaptarr;
  umlautadaptarrProxyPort = ids.ports.umlautadaptarrProxy;
  traefikAddr = ids.peers.traefik;
  monitoringAddr = ids.peers.monitoring;
  massAddr = ids.peers.mass;
  beetsStagingRoot = ids.paths.beetsStaging;
  beetsStateDir = ids.paths.beetsState;
  janitorrSecretsDir = ids.secretsDirs.janitorr;
  navidromeSecretsDir = ids.secretsDirs.navidrome;
  soularrSecretsDir = ids.secretsDirs.soularr;
in {
  ##############################################################################
  # Host-side wiring.
  ##############################################################################

  # Host side of the container's veth — a VLAN-90 port on br0.
  #
  # There is deliberately NO `networking.firewall.allowedTCPPorts` here.  The
  # three web UIs are opened inside the container's own netns (below); on the
  # host they are not ports at all.  Reachability from the management VLANs is
  # the UDM-Pro's job — ledger row L4 in docs/ledger.md.
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
  # ── The container ──────────────────────────────────────────────────────────
  #
  # modules/containers/nspawn.nix generates the dirs unit (with mount guards),
  # the host-side veth network, the VLAN backstop, the container preamble and
  # the in-container networking. ./storage.nix supplies the directories.
  #
  # THE FIREWALL IS THIS FILE'S OWN, and that is why `manageFirewall = false`.
  # `allowFrom` is a list of (peer, port) pairs; this container's rules are
  # three source lists over twenty-odd ports, built with `concatMapStrings`
  # and carrying the argument for each exclusion inline. Flattening that into
  # twenty-odd `allowFrom` entries would lose the grouping that makes "what
  # can Traefik reach?" answerable by reading one list — which is the property
  # the block below was written for. Same opt-out traefik.nix takes, for a
  # related reason.
  clanarchy.containers.arr = {
    enable = true;
    mac = arrMac;

    # NO uid/gid PIN: ./users.nix declares all twenty-two in full.

    # Pinned, and load-bearing for the services whose state directories were
    # created under it.
    stateVersion = "26.05";

    manageFirewall = false;

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
        hostPath = "/srv/media";
        isReadOnly = false;
      };

      # Per-service state, remapped to each package's upstream default path so
      # the packaged units need no dataDir override.
      "/var/lib/sonarr" = {
        hostPath = "${stateRoot}/sonarr";
        isReadOnly = false;
      };
      "/var/lib/radarr" = {
        hostPath = "${stateRoot}/radarr";
        isReadOnly = false;
      };
      "/var/lib/prowlarr" = {
        hostPath = "${stateRoot}/prowlarr";
        isReadOnly = false;
      };

      # ── beets' CATALOGUE, AND IT IS NOT OPTIONAL STATE ─────────────────────
      #
      # Shipped missing in #269 and found on 2026-10-04.  `beetsStateDir` is a
      # HOST path, and only `/srv/media` was mounted in — so
      # `nixos-container run arr -- music-stage` wrote library.db to the
      # container's PRIVATE /srv/state/beets, on zroot, which rolls back.
      #
      # THE SYMPTOM IS NOT AN EMPTY CATALOGUE, IT IS DUPLICATE AUDIO.  With no
      # record of what it already staged, beets cannot apply
      # `duplicate_action: skip`; it copies the file again and disambiguates
      # the name, so a second run of the same CSVs produced
      # `Elephant Gun.flac` AND `Elephant Gun.1.flac`.  At ten thousand tracks
      # over weeks of re-runs that is the whole library, several times over.
      #
      # The path is the same inside and out, unlike the `/var/lib/<svc>`
      # entries above, because `music-stage`'s config is generated from
      # `beetsStateDir` and the two must agree.
      "${beetsStateDir}" = {
        hostPath = beetsStateDir;
        isReadOnly = false;
      };

      # M12.  Same pattern: each service's UPSTREAM DEFAULT state path, so
      # nothing needs a dataDir override.
      #
      # UmlautAdaptarr has no entry, and that is not an omission — it has no
      # persistent state at all.  See its block below.
      "/var/lib/bazarr" = {
        hostPath = "${stateRoot}/bazarr";
        isReadOnly = false;
      };
      "/var/lib/cleanuparr" = {
        hostPath = "${stateRoot}/cleanuparr";
        isReadOnly = false;
      };
      "/var/lib/mediathekarr" = {
        hostPath = "${stateRoot}/mediathekarr";
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
        hostPath = "${stateRoot}/jellyseerr";
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
        hostPath = "${stateRoot}/janitorr";
        isReadOnly = false;
      };

      # Scraparr has no bind mount, and that is not an omission — it has no
      # persistent state at all.  Same situation as UmlautAdaptarr above.

      # Janitorr's Jellyfin credentials, READ-ONLY, at the same path as on the
      # host.  One of the two bind mounts in this file that carry a secret.
      "${janitorrSecretsDir}" = {
        hostPath = janitorrSecretsDir;
        isReadOnly = true;
      };

      # The other one: slskd's API key, for Soularr.  Same shape, same reason —
      # a clan var's own /run/secrets path does not exist inside the container.
      "${soularrSecretsDir}" = {
        hostPath = soularrSecretsDir;
        isReadOnly = true;
      };

      # The THIRD: Navidrome's Prometheus password.  Same shape and the same
      # reason as the two above — see navidromeSecretsDir in the let block.
      "${navidromeSecretsDir}" = {
        hostPath = navidromeSecretsDir;
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
        hostPath = "${stateRoot}/lidarr";
        isReadOnly = false;
      };
      "/var/lib/soularr" = {
        hostPath = "${stateRoot}/soularr";
        isReadOnly = false;
      };
      "/var/lib/kapowarr" = {
        hostPath = "${stateRoot}/kapowarr";
        isReadOnly = false;
      };
      "/var/lib/questarr" = {
        hostPath = "${stateRoot}/questarr";
        isReadOnly = false;
      };
      "/var/lib/audiobookshelf" = {
        hostPath = "${stateRoot}/audiobookshelf";
        isReadOnly = false;
      };

      # 2026-09-08.  Komga's and Navidrome's state, remapped onto each
      # module's own default path so neither needs a directory override —
      # the same trick lidarr's bind above uses, and jellyfin.nix for
      # /var/lib/jellyfin.
      #
      #   komga      services.komga.stateDir defaults to /var/lib/komga
      #              (verified by evaluating the option).
      #   navidrome  the module hard-codes WorkingDirectory=/var/lib/navidrome
      #              and StateDirectory=navidrome, and DataFolder defaults to
      #              the WorkingDirectory.  So this bind is what puts the
      #              database on zdata, and DataFolder is deliberately LEFT
      #              UNSET below rather than pointed somewhere else.
      "/var/lib/komga" = {
        hostPath = "${stateRoot}/komga";
        isReadOnly = false;
      };
      "/var/lib/navidrome" = {
        hostPath = "${stateRoot}/navidrome";
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
        hostPath = "${stateRoot}/bindery";
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
        hostPath = audiobooksRoot;
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
        hostPath = "/srv/games/questarr";
        isReadOnly = false;
      };
    };

    ############################################################################
    # NixOS config for the container's own root filesystem.
    ############################################################################
    config = {
      config,
      pkgs,
      lib,
      ...
    }: {
      time.timeZone = "Europe/Berlin";

      ##########################################################################
      # Networking.  The container owns its netns, so it owns all of this.
      ##########################################################################

      # services.resolved asserts !networking.useHostResolvConf, and with a
      # private netns the host's resolv.conf is a stale snapshot of someone
      # else's resolver anyway.  virtualisation/container-config.nix sets it
      # `mkDefault true`, so a plain `false` wins without mkForce.
      networking.firewall.allowedTCPPorts = [];
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

          # ── EVERY SERVICE BELOW BINDS 0.0.0.0, AND THIS RULE IS WHAT KEEPS
          #    IT OFF THE VLAN ─────────────────────────────────────────────
          #
          # Measured for questarr (v1.4.2 config dump says `"host":
          # "0.0.0.0"`), bindery (`ss` shows *:8787), kapowarr and
          # audiobookshelf (given 0.0.0.0 explicitly below), komga and
          # navidrome (0.0.0.0 by configuration). Inside this netns that means
          # they are on the veth and therefore on VLAN 90; the ONLY thing
          # keeping them off it generally is that each rule names one source
          # and the chain ends in `nixos-fw-log-refuse`. Load-bearing, not
          # belt-and-braces.
          #
          # Loopback instead would make them unreachable from Traefik in
          # another netns while adding nothing this rule does not give.
          #
          # SOULARR IS ABSENT AND STAYS ABSENT: it listens on nothing — its
          # bundled Flask UI is not packaged. See ../pkgs/soularr.nix.
          #
          # KOMGA AND NAVIDROME ARE DIFFERENT IN ONE WAY THAT MATTERS. They
          # are in `wanExposed` (containers/traefik.nix), so a request here
          # can have come from the public internet by way of the UDM-Pro DNAT.
          # The rule is unchanged and still correct — the source is Traefik's
          # address either way, since the proxy is what connects. What differs
          # is what stands behind it: for these two the application's own user
          # database is the boundary, not Authelia. See ingress-policy.nix.
          lidarrPort
          kapowarrPort
          questarrPort
          audiobookshelfPort
          binderyPort
          komgaPort
          navidromePort
        ]
        + lib.concatMapStrings (port: ''
          iptables -A nixos-fw -p tcp -s ${monitoringAddr}/32 --dport ${toString port} -j nixos-fw-accept
        '') [
          scraparrPort

          # Navidrome's /metrics rides its ORDINARY port rather than getting a
          # listener of its own, so this opens the whole application to the
          # monitoring container — the same trade containers/jellyfin.nix
          # states plainly for its own metrics.  It is acceptable here for the
          # same reason: the far end is a container on this host that already
          # scrapes every other service, and the endpoint itself demands HTTP
          # Basic (measured: 401 without, 200 with — see the block below).
          navidromePort
        ]
        # ── M30: NAVIDROME'S THIRD SOURCE, AND ITS FIRST APPLICATION CLIENT ──
        #
        # A third source list rather than a merged list of (source, port) pairs,
        # for the reason stated above the first one: "what can Traefik reach?"
        # has to stay answerable by reading one list, and so does this.
        #
        # ONE PORT, ONE SOURCE.  Music Assistant reads the library over the
        # Subsonic API at /rest/** and touches nothing else in this container —
        # not Lidarr, not the *arr APIs, not Komga.  The acquisition pipeline and
        # the playback controller share exactly one surface, and it is this.
        #
        # `/metrics` RIDES THIS PORT TOO, which is the trade the monitoring rule
        # above already states plainly: source-restricting to one address is what
        # keeps that acceptable, and the endpoint demands HTTP Basic regardless.
        + lib.concatMapStrings (port: ''
          iptables -A nixos-fw -p tcp -s ${massAddr}/32 --dport ${toString port} -j nixos-fw-accept
        '') [
          navidromePort
        ];

      ##########################################################################
      # `arr-api-keys` — extract Sonarr's and Radarr's API keys at start.
      #
      # IT LIVES IN THIS FILE BECAUSE IT HAS TWO CONSUMERS IN TWO DOMAINS:
      # recyclarr (./video.nix) reads the two key files through `_secret`, and
      # UmlautAdaptarr (./indexers.nix) reads an environment file written from
      # the same two keys. A copy in each would be two sources of truth for a
      # value that can be rotated with one button in a web UI.
      #
      # M12 renamed it from `recyclarr-api-keys` for that reason.
      systemd.services.arr-api-keys = {
        description = "Stage Sonarr/Radarr API keys for recyclarr and UmlautAdaptarr";
        before = ["recyclarr.service" "umlautadaptarr.service"];
        requiredBy = ["recyclarr.service" "umlautadaptarr.service"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = false;
          RuntimeDirectory = "arr-api-keys";
          RuntimeDirectoryMode = "0700";
          RuntimeDirectoryPreserve = "yes";
          UMask = "0077";

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
          PrivateNetwork = true;
          IPAddressDeny = "any";
          CapabilityBoundingSet = ["CAP_DAC_READ_SEARCH"];
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectProc = "invisible";
          RestrictAddressFamilies = ["AF_UNIX"];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          RemoveIPC = true;
          LockPersonality = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = arrSyscallFilter;

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
      # in docs/history.md, where DynamicUser plus persistent state left a
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
      documentation.enable = false;
      documentation.nixos.enable = false;
    };
  };
}
