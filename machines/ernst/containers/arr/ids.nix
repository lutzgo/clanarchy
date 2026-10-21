# The numbers, addresses and paths the `arr` container's six files share.
#
# ── WHY THIS IS A PLAIN FILE AND NOT A MODULE ───────────────────────────────
#
# It is data. `import ./ids.nix` gives every sibling the same attrset with no
# option plumbing, no `config` read, and therefore no way to introduce the
# recursion that an option default reading `config` would. The same shape
# machines/ernst/allocations.nix already uses, and the same reason.
#
# ── THE uids ARE NOT HERE, DELIBERATELY ─────────────────────────────────────
#
# They are rows in machines/ernst/allocations.nix, which is the host's
# registry and already carried all twenty-two of them while this file's
# predecessor restated every one. Restating them here would recreate exactly
# the drift the registry exists to prevent, so the uids are READ:
#
#     ids.uids.sonarr   -> allocations.ids.sonarr.uid
#
# ── THE PORTS ARE HERE, AND THAT IS NOT YET FINISHED ────────────────────────
#
# containers/traefik.nix, containers/homepage.nix and
# service-modules/monitoring.nix each restate these same port numbers, which
# is the dedup this file sets up but does NOT do: moving them into
# allocations.nix while three other files still hold their own copies would
# create a second source of truth with nothing asserting the two agree, which
# is worse than either end state. That consolidation wants its own change,
# where all four consumers move together and a check holds them equal.
let
  alloc = import ../../allocations.nix;

  # Every arr service's uid, read from the registry rather than restated.
  # A service with no row here has no id of its own on purpose — recyclarr is
  # the one, and its own file says why.
  uidOf = name: alloc.ids.${name}.uid;
  gidOf = name: alloc.ids.${name}.gid;
in rec {
  # ── Numeric ids ───────────────────────────────────────────────────────────
  #
  # nspawn passes ids through UNMAPPED, so each of these is a number on
  # zdata as well as inside the container. That is the whole reason they are
  # pinned rather than left to the container's own useradd.
  uids = {
    sonarr = uidOf "sonarr";
    radarr = uidOf "radarr";
    prowlarr = uidOf "prowlarr";
    bazarr = uidOf "bazarr";
    cleanuparr = uidOf "cleanuparr";
    mediathekarr = uidOf "mediathekarr";
    jellyseerr = uidOf "jellyseerr";
    janitorr = uidOf "janitorr";
    scraparr = uidOf "scraparr";
    lidarr = uidOf "lidarr";
    soularr = uidOf "soularr";
    kapowarr = uidOf "kapowarr";
    questarr = uidOf "questarr";
    audiobookshelf = uidOf "audiobookshelf";
    bindery = uidOf "bindery";
    komga = uidOf "komga";
    navidrome = uidOf "navidrome";
  };

  # Only the services that own a group of their own. The rest are in `media`,
  # which is what makes the *arr hardlink domain work at all.
  gids = {
    media = gidOf "media";
    prowlarr = gidOf "prowlarr";
    jellyseerr = gidOf "jellyseerr";
    scraparr = gidOf "scraparr";
    questarr = gidOf "questarr";
  };

  # ── Ports, all on the container's own netns ───────────────────────────────
  ports = {
    prowlarr = 9696;
    sonarr = 8989;
    radarr = 7878;
    flaresolverr = 8191;
    bazarr = 6767;
    cleanuparr = 11011;
    jellyseerr = 5055;
    scraparr = 7100;
    janitorr = 8978;
    lidarr = 8686;
    kapowarr = 5656;
    questarr = 5000;
    audiobookshelf = 13378;
    bindery = 8787;
    komga = 25600;
    navidrome = 4533;

    # Two ports each, and the pair matters: Prowlarr talks to the SECOND one
    # in both cases, so swapping them produces an indexer that tests green
    # and returns nothing.
    mediathekarrDownloader = 5007; # SABnzbd shim, and the setup wizard
    mediathekarrIndexer = 5008; # Newznab; what Prowlarr reaches
    umlautadaptarr = 5005; # its own HTTP API
    umlautadaptarrProxy = 5006; # the proxy Prowlarr's indexers point at
  };

  # ── Peers outside this container ──────────────────────────────────────────
  peers = {
    traefik = "10.0.90.12";
    monitoring = "10.0.90.14";
    jellyfin = {
      addr = "10.0.90.10";
      port = 8096;
    };
    slskd = {
      addr = "10.0.90.11";
      port = 5030;
    };
    mass = "10.0.90.30";
  };

  # ── Host-side paths ───────────────────────────────────────────────────────
  stateRoot = "/srv/state";
  audiobooksRoot = "/srv/audiobooks";
  soulseekRoot = "/srv/media/soulseek";

  paths = {
    soulseekDownloads = "${soulseekRoot}/complete";
    beetsStaging = "/srv/media/staging/music";
    beetsState = "${stateRoot}/beets";
  };

  # Staging directories, one per consumer. All under /run: nothing here
  # survives a reboot, and nothing here should.
  secretsDirs = {
    arrApiKeys = "/run/arr-api-keys";
    soularr = "/run/soularr-secrets";
    janitorr = "/run/janitorr-secrets";
    navidrome = "/run/navidrome-secrets";
  };

  soularrConfigDir = "/run/soularr";
  navidromeEnvFile = "${secretsDirs.navidrome}/navidrome.env";

  # ── Policy shared by every unit in the container ──────────────────────────
  #
  # Applied per-file to that file's own units. It is NOT mapped over
  # `config.systemd.services` from common.nix: the attrset being read would be
  # the one being defined, which is infinite recursion.
  syscallFilter = ["@system-service" "~@privileged" "~@debug" "~@mount" "@chown"];

  # Janitorr deletes media. It stays in dry-run until a human has read a
  # cycle's log and agreed with what it proposed.
  janitorrDryRun = true;
}
