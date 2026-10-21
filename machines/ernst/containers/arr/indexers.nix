# machines/ernst/containers/arr/indexers.nix
#
# What finds releases: Prowlarr, FlareSolverr, UmlautAdaptarr and the two
# MediathekArr halves — plus Prowlarr's hardening override, which is the one
# upstream unit in this container that scored EXPOSED before it.
#
# ── THIS FILE CO-DEFINES containers.arr ─────────────────────────────────────
#
# It creates no container; `containers.<name>.config` is a module option and
# every file in this directory merges into the one ./common.nix declares. See
# ./video.nix for the longer note on why the split is by media domain.
#
# TWO PORTS EACH FOR TWO OF THESE, and the pair matters: Prowlarr talks to the
# SECOND port in both cases (MediathekArr's Newznab, UmlautAdaptarr's proxy),
# so swapping them gives an indexer that tests green and returns nothing.
{
  config,
  lib,
  pkgs,
  ...
}: let
  ids = import ./ids.nix;

  # The old flat names, so the definitions below are unchanged from the file
  # they came out of — see ./video.nix.
  arrSyscallFilter = ids.syscallFilter;
  arrSecretsDir = ids.secretsDirs.arrApiKeys;
  prowlarrPort = ids.ports.prowlarr;
  flaresolverrPort = ids.ports.flaresolverr;
in {
  # ── Inside the container ──────────────────────────────────────────────────
  containers.arr.config = {
    config,
    pkgs,
    lib,
    ...
  }: let
    # Both are packaged in this repo: ../pkgs/<name>.nix. Each domain file
    # calls the ones its own units need, so a reader of this file sees every
    # derivation it depends on without opening another.
    umlautadaptarr = pkgs.callPackage ../pkgs/umlautadaptarr.nix {};
    mediathekarr = pkgs.callPackage ../pkgs/mediathekarr.nix {};
  in {
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
      user = "radarr";
      group = "media";
      mode = "0700";
    };

    # Prowlarr.  dataDir left at the default: the module only wires its
    # bind-mount/tmpfiles machinery when dataDir differs from
    # /var/lib/prowlarr, and the packaged ExecStart hardcodes
    # `-data=/var/lib/prowlarr` regardless.  Our nspawn bind mount already
    # puts zdata there, so the custom-dataDir path would be a second
    # mechanism doing the same job.
    services.prowlarr = {
      enable = true;
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
      port = flaresolverrPort;

      # 127.0.0.1 only.  Upstream's openFirewall would open 8191 in this
      # container's netns, which would expose a remote-URL-fetching service
      # to the whole Services VLAN — an SSRF primitive with a web API in
      # front of it.  Prowlarr is in this same netns and needs no port open
      # at all.
      openFirewall = false;
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
    # ── IT DOES NOTHING FOR THIS FLEET'S INDEXERS.  MEASURED 2026-08-26 ──
    #
    # READ THIS BEFORE TRYING TO "FINISH WIRING IT UP".  M12 called this the
    # highest-value item in the milestone.  That judgement assumed an
    # indexer set this deployment does not have, and the service as deployed
    # is INERT — not misconfigured, not half-wired: architecturally unable to
    # help.  The evidence, in the order it was found:
    #
    # 1. ALL SIX PROWLARR INDEXERS ARE `Cardigann`.  EZTV, LimeTorrents,
    #    Nyaa.si, The Pirate Bay, TorrentDownload, YTS — every one of them a
    #    definition-driven HTML SCRAPER, all torrent protocol.  Cardigann's
    #    Site Link is a select populated from the bundled YAML definition, so
    #    the https → http edit the upstream README requires CANNOT BE MADE.
    #    That is the symptom people notice first.  It is not the cause.
    #
    # 2. BOTH INTEGRATION MODES CONVERGE ON THE SAME REQUIREMENT, and this
    #    is the cause.  Reading the source rather than the README:
    #
    #      HttpProxyService (port 5006) rewrites an intercepted request to
    #        http://localhost:5005/{apiKey}/{uri.Host}{uri.PathAndQuery}
    #      SearchController's routes are constrained on the NEWZNAB `t=`
    #        parameter — caps | movie | tvsearch | music | book | search
    #      UrlUtilities.BuildUrl then does
    #        new UriBuilder("https", domain)
    #
    #    So whichever mode is used, UmlautAdaptarr ends up fetching the
    #    indexer's own NEWZNAB/TORZNAB API over https and rewriting the XML
    #    it gets back.  THE TARGET MUST SPEAK NEWZNAB/TORZNAB AT ITS OWN
    #    DOMAIN.  A Cardigann tracker speaks HTML, and Prowlarr is what turns
    #    that into Torznab — inside Prowlarr, after the proxy hop.
    #
    # 3. SO THE INSTRUCTION WOULD HAVE BROKEN SEARCHES, NOT ENABLED THEM.  A
    #    Cardigann request carries no `t=` parameter, so no route matches and
    #    UmlautAdaptarr answers 404.  Tagging these indexers with the proxy
    #    would take six working indexers offline.  The Site Link dropdown
    #    being read-only is the only reason that did not happen.
    #
    # 4. THE NON-PROXY MODE IS NOT AN ESCAPE EITHER.  `IsValidDomain` demands
    #    a dotted host and the scheme is hardcoded to https, so
    #    `http://localhost:5005/_/localhost:9696/1/api` — pointing it at
    #    Prowlarr, whose Torznab really is XML over plain http — is rejected
    #    twice over.
    #
    # WHY IT IS STILL HERE.  It runs clean (NRestarts=0), and it does real
    # work that costs nothing: it syncs Sonarr's 139 series and resolves
    # German titles for 130 of them against the maintainer's API.  The day an
    # indexer that speaks Newznab or Torznab is added — a usenet provider, or
    # any tracker with a real API — it becomes useful with a UI change and no
    # deploy.  Removing it would mean re-deriving all of the above later.
    #
    # THE TRIGGER TO REVISIT IS AN INDEXER WITH AN API, not a Prowlarr
    # update.  This is the same shape as the Unpackerr finding one screen
    # down, and it has the same root: this stack is 100% torrent, 100%
    # Cardigann, with no usenet path at all.
    #
    # ── THE TRAP, IF THAT DAY COMES ──────────────────────────────────────
    #
    # For an indexer that DOES have an API, the README's rule applies and is
    # a genuine fails-by-succeeding: the indexer URL must change https → http
    # so this can intercept locally (the outbound leg stays https).  AN
    # INDEXER LEFT ON https WORKS FINE AND SILENTLY BYPASSES THIS ENTIRELY.
    # Configure it in PROWLARR, not per-arr — per-arr costs a speed penalty
    # on multi-indexer search.
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
    # docs/history.md reserves uid 3010 for this service, "own group, no
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
      wantedBy = ["multi-user.target"];

      # HARD startup dependency, and it is not advisory.  Measured
      # 2026-08-26: with no *arr reachable, UmlautAdaptarr logs
      #   The URL "http://.../api?apikey=[REDACTED]" is not reachable.
      #   Next attempt in 15 seconds...
      # and NEVER BINDS ITS PORTS.  It blocks in its own constructor until
      # an *arr answers.  That is good behaviour — it fails closed — but it
      # means ordering matters and that a restart policy is required rather
      # than optional.
      after = ["sonarr.service" "radarr.service" "arr-api-keys.service"];
      wants = ["sonarr.service" "radarr.service"];

      serviceConfig = {
        Type = "simple";

        # The two API keys, as environment variables, staged by
        # arr-api-keys.service below.  EnvironmentFile is read by PID 1
        # before privileges are dropped, so a 0600 root-owned file under
        # /run is exactly right and the DynamicUser never sees it.
        EnvironmentFile = "${arrSecretsDir}/umlautadaptarr.env";

        ExecStart = "${lib.getExe umlautadaptarr}";

        Restart = "on-failure";
        RestartSec = "30s";

        # See the long note above.  Upstream ships no unit at all, so every
        # directive here is ours.  DynamicUser buys the six implied ones;
        # the rest is the servarr set this file already applies to prowlarr.
        DynamicUser = true;
        RuntimeDirectory = "umlautadaptarr";

        CapabilityBoundingSet = "";
        PrivateDevices = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";

        # NOT MemoryDenyWriteExecute — .NET, same JIT rejection this file
        # already records for sonarr/radarr/prowlarr and jellyfin.nix
        # records for Jellyfin.
        SystemCallFilter = arrSyscallFilter;
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
    #   mediathekarr-downloader  5007   SABnzbd shim + the setup WIZARD +
    #                                   a full Newznab endpoint.  THIS IS THE
    #                                   ONE EVERYTHING IS POINTED AT.
    #   mediathekarr-indexer     5008   Newznab shim, plus the ruleset
    #                                   background fetcher.  Nothing points
    #                                   at it.  See below.
    #
    # CORRECTED AFTER THE DEPLOY, 2026-08-26.  This block used to say the
    # indexer on 5008 "is what Prowlarr is pointed at".  It is not.  The
    # setup wizard — which runs inside the DOWNLOADER — registers the
    # Prowlarr indexer against `http://localhost:5007`, and that works,
    # because 5007 serves the Newznab API as well.  Verified by asking both
    # ports the same question:
    #
    #   curl 'http://localhost:5007/api?t=tvsearch&q=Tatort'
    #   curl 'http://localhost:5008/api?t=tvsearch&q=Tatort'
    #
    # Both returned `total="3012"` and byte-identical, correctly-formatted
    # release titles.  So the downloader is self-sufficient and 5008 is NOT
    # in the request path of anything.
    #
    # BOTH ARE KEPT ANYWAY, deliberately.  Upstream's docker_start.sh runs
    # both, and the two are not identical: only the INDEXER registers
    # RulesetBackgroundService, which refreshes the per-show naming rules
    # from mediathekarr.pcjones.de on a timer.  The downloader's journal
    # shows no ruleset activity at all.  One matching search result is not
    # evidence that ruleset upkeep is irrelevant — and inferring that from a
    # single query is exactly the species of mistake this milestone has
    # already made four times.  It costs ~90 MB.
    #
    # TO REVISIT: if the naming ever drifts, or if the container needs the
    # memory, the question to answer FIRST is whether 5007 gets its rulesets
    # some other way.  Until then, run what upstream runs.
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
    # exist at all.  See the M8 amendment in docs/history.md.
    systemd.services.mediathekarr-indexer = {
      description = "MediathekArr indexer — ARD/ZDF Mediathek as Newznab";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];

      serviceConfig = {
        Type = "simple";
        User = "mediathekarr";
        Group = "media";
        ExecStart = "${lib.getExe mediathekarr.indexer}";
        Restart = "on-failure";
        RestartSec = "30s";

        # The indexer half NEVER TOUCHES A FILE.  It is in group media only
        # because it shares a uid with the downloader half, and it is given
        # no writable path at all — ProtectSystem=strict with no
        # ReadWritePaths means the entire filesystem is read-only to it.
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RemoveIPC = true;
        RestrictSUIDSGID = true;

        CapabilityBoundingSet = "";
        PrivateDevices = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = arrSyscallFilter;
      };
    };

    systemd.services.mediathekarr-downloader = {
      description = "MediathekArr downloader — SABnzbd shim and setup wizard";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target"];
      wants = ["network-online.target"];

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
        DOWNLOAD_COMPLETE_PATH = "/srv/media/torrents/mediathek/complete";

        # The SABnzbd categories the *arrs will see.  tv and movies match
        # the two libraries this stack actually has.
        CATEGORIES = "tv,movies";
      };

      serviceConfig = {
        Type = "simple";
        User = "mediathekarr";
        Group = "media";
        ExecStart = "${lib.getExe mediathekarr.downloader}";
        Restart = "on-failure";
        RestartSec = "30s";

        # Group-writable, same argument as sonarr/radarr/cleanuparr: what
        # this writes is imported, moved and eventually deleted by other
        # members of `media`.
        UMask = "0002";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        RemoveIPC = true;
        RestrictSUIDSGID = true;

        ReadWritePaths = [
          "/srv/media/torrents/mediathek"
          "/var/lib/mediathekarr"
        ];

        CapabilityBoundingSet = "";
        PrivateDevices = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";

        # ffmpeg and mkvmerge are FORKED, so the filter has to permit it —
        # @system-service already does.  What it must NOT gain is @privileged
        # or @mount, and it does not.
        SystemCallFilter = arrSyscallFilter;
      };
    };
    systemd.services.prowlarr.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "prowlarr";
      Group = "prowlarr";

      # See the note on sonarr's StateDirectoryMode below — same tug-of-war,
      # same fix.  0755 from systemd on every start against 0700 from
      # tmpfiles on every deploy.
      StateDirectoryMode = "0700";

      # Restoring what DynamicUser=true had been implying.
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      RemoveIPC = true;
      RestrictSUIDSGID = true;

      # The rest of the servarr set, which upstream applies to sonarr and
      # radarr but not to prowlarr.
      CapabilityBoundingSet = "";
      PrivateDevices = true;
      PrivateUsers = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectProc = "invisible";
      RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      LockPersonality = true;
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
  };
}
