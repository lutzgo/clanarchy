# machines/ernst/containers/homepage.nix
#
# gethomepage — the fleet's SERVICE INDEX, at home.goclan.org.  M26.
#
# ── WHAT THIS IS, AND WHAT IT IS NOT ────────────────────────────────────────
#
#   ernst routes twenty-eight hostnames across four hosting tiers.  Until this
#   file, the authoritative list of them was three Nix arrays in
#   containers/ingress-policy.nix plus `wanExposed` in containers/traefik.nix
#   — readable by whoever has this repo checked out, and by nobody else in the
#   household.  This is that list, rendered, with live status.
#
#   IT IS NOT GRAFANA AND MUST NOT GROW INTO IT.  The roadmap has used the
#   word "dashboard" for M6's Grafana since it shipped, and the division of
#   labour is worth stating once so a later milestone does not blur it:
#
#     Grafana (M6)        OPS TRUTH.  Time series, alert rules, retention,
#                         ZFS and SMART.  Answers "is this healthy, and was it
#                         healthy an hour ago".
#     this file           THE INDEX.  Answers "what exists, where is it, is it
#                         up, what is it doing right now".  No history, no
#                         alerting, no retention.
#     Uptime Kuma         (backlog, not built) THE OUTSIDE-IN PATH, from a VPS.
#                         Answers "can a stranger on the internet reach it".
#
#   The concrete rule that keeps them apart: NOTHING HERE MAY BE THE ONLY
#   PLACE A FACT IS SHOWN.  Every number on this page is fetched live from the
#   service that owns it, and if this container is down the answer is "go look
#   at Grafana", not "we lost the data".  Nothing is stored here at all.
#
# ── THIS FILE CO-DEFINES containers.arr.  THAT IS THE WHOLE DESIGN ──────────
#
#   It does not create a container.  It merges a service, a bind mount and one
#   firewall rule into the one machines/ernst/containers/arr.nix declares, and
#   adds the host-side secret staging.  `containers.<name>.config` merges
#   multiple definitions like any other NixOS option, so the two files compose
#   — exactly as containers/crowdsec.nix composes with containers/traefik.nix,
#   and for a reason of the same kind: the thing it needs exists in that
#   namespace and nowhere else.
#
#   WHY NOT ITS OWN CONTAINER, WHICH IS THIS REPO'S DEFAULT ANSWER AND WAS THE
#   FIRST PLAN.  Two reasons, and the first is decisive.
#
#   (1) THE *ARR API KEYS ARE NOT OURS TO CHOOSE, AND THEY LIVE HERE.
#
#       `arr-api-keys.service` (containers/arr.nix) EXTRACTS six keys at
#       runtime from each service's own configuration — Sonarr, Radarr,
#       Lidarr and Prowlarr from the servarr `<ApiKey>` element, Bazarr from
#       the `auth:` block of its YAML, Jellyseerr from `.main.apiKey` in
#       settings.json — into /run/arr-api-keys, a 0700 root RuntimeDirectory
#       INSIDE THIS CONTAINER'S NAMESPACE.
#
#       Those keys are DERIVED, NOT CHOSEN.  A human rotates one with a button
#       in a web UI and the stager picks the new value up on the next start.
#       A homepage in a second namespace could not read them; it would need a
#       clan-vars prompt per key, which is a SECOND SOURCE OF TRUTH for a
#       value the first source regenerates behind its back.  The failure mode
#       is a dashboard showing "API Error" on six tiles some weeks after
#       somebody clicked a button, with nothing anywhere connecting the two
#       events.  Running where the stager already runs makes that impossible
#       rather than unlikely.
#
#       This is the same argument containers/arr.nix makes for having ONE
#       stager with three consumers instead of three copies of it, applied one
#       consumer further out.  This file is the fourth consumer.
#
#   (2) FOURTEEN OF THE ROUTED SERVICES ARE ALREADY ON THIS ADDRESS.
#
#       Their status and widget traffic is a connection to 127.0.0.1 — no
#       firewall rule, no VLAN hop, no `-s` accept for a future reader to
#       audit.  Every other container on VLAN 90 admits 10.0.90.12 and nothing
#       else, so a homepage anywhere else would be REFUSED AT EVERY SINGLE
#       BACKEND until each one was widened.  Placing it here reduces the set
#       of widenings this milestone makes from nineteen to four.
#
#   WHAT THE PLACEMENT COSTS, stated rather than discovered:  homepage
#   restarts when container@arr restarts, and a `nixos-container` operation on
#   `arr` now takes the index down with the *arr.  Acceptable — the index is
#   the least load-bearing thing on this host by construction.
#
#   WHAT IT DOES NOT COST, because the numbers are the kind that get assumed:
#   M26 CONSUMES NO MAC, NO ADDRESS AND NO UID.  The three NEXT FREE markers
#   in machines/ernst/networking.nix are unchanged, and that file says so.
#   The nixpkgs module runs under DynamicUser with its configuration in
#   /etc and its cache in a CacheDirectory, so nothing here touches zdata and
#   invariant #7 has nothing to check.
#
#   THE TIER QUESTION (invariant #1) never arises.  `services.homepage-
#   dashboard` is a first-class nixpkgs module at this pin (homepage-dashboard
#   1.12.3), so the podman tier — which exists for things upstream ships only
#   as an image — is not in play.
#
# ── TWO SECRET MECHANISMS, AND WHY IT IS NOT ONE ────────────────────────────
#
#   Homepage substitutes placeholders in its YAML from the environment:
#   `{{HOMEPAGE_FILE_X}}` is replaced by the CONTENTS of the path in
#   $HOMEPAGE_FILE_X, and `{{HOMEPAGE_VAR_X}}` by the VALUE of $HOMEPAGE_VAR_X.
#   This file uses both, because the two credential sources here are genuinely
#   different and collapsing them would mean copying one into the other:
#
#     HOMEPAGE_FILE_*   the six *arr keys, reached through LoadCredential from
#                       /run/arr-api-keys.  Derived at runtime; never in sops.
#     HOMEPAGE_VAR_*    the four tokens for services in OTHER namespaces,
#                       which nothing extracts and which are therefore clan
#                       vars like any other credential.
#
#   LoadCredential rather than widening /run/arr-api-keys, and this is the
#   third time this container answers that question the same way (scraparr and
#   soularr are the other two, and containers/arr.nix explains it at length at
#   the soularr render script): PID 1 reads the file as root BEFORE the drop to
#   the unit's user and places a 0400 copy in $CREDENTIALS_DIRECTORY.  The
#   staging directory stays 0700 root.  Widening it for a fourth consumer
#   would widen it for recyclarr, umlautadaptarr and scraparr too.
#
#   It matters more here than for the other three: this unit is DynamicUser,
#   so there is no fixed uid a directory mode could be written against even if
#   widening were acceptable.
#
# ── WHAT IS DELIBERATELY ABSENT ─────────────────────────────────────────────
#
#   THE `resources` WIDGET.  It reads /proc, and /proc in here is the arr
#   container's view — so "disk" would be this namespace's root filesystem and
#   not zroot or zdata.  A dashboard displaying a plausible WRONG number about
#   pool capacity is worse than one displaying none; the household would read
#   it and believe it.  ZFS truth is Grafana's and stays there.  (Keeping it
#   out also keeps the module's `ProcSubset = "all"` branch off, which is a
#   real hardening difference and not a side benefit worth inverting for.)
#
#   THE DOCKER AND KUBERNETES PROVIDERS.  Homepage can enumerate containers
#   from a runtime socket and label tiles automatically.  That would mean
#   handing the index a socket with control of the container runtime in order
#   to save typing a list.  The list below is hand-written, and the fact that
#   adding a service to ernst means adding a line here is a FEATURE — it is
#   the same "a peer names its peers, and drift fails loudly" property that
#   containers/traefik.nix's hard-coded backend addresses are for.
#
#   qBITTORRENT.  It is in the microvm guest behind WireGuard, reachable only
#   from the management VLAN by permanent bypass (invariant #4).  A widget
#   would mean opening a path into it from VLAN 90 for decoration.  It is not
#   listed at all — a tile linking somewhere this browser cannot reach is
#   worse than its absence.
#
#   SEARXNG.  No hostname, no Traefik route, reachable only from 10.0.90.23.
#   There is nothing to link to.
#
#   ping: AND siteMonitor: ON THE FLEET TILES.  node_exporter on miralda,
#   jens, biene and birte binds IPv6 over ZeroTier, and this container is on
#   VLAN 90 with no route to any of it.  A status dot that is structurally
#   always red is worse than no dot, so those four tiles are links into
#   Grafana filtered by instance and carry no status at all.
#
# ── THE AUTH POSTURE ────────────────────────────────────────────────────────
#
#   `home.goclan.org` is in `protectedHosts` (containers/ingress-policy.nix)
#   and in `wanExposed` (containers/traefik.nix): forward-auth on BOTH
#   entrypoints, admins only, two_factor.  It passes ingress-policy's test
#   without argument — the only client is a browser, so there is no native
#   client a 302 could break and no carve-out to justify.
#
#   That is the `chat` posture (ledger row L10) and NOT the appApiHosts one
#   (L13/L14/L15).  Worth saying plainly, because this name goes on the
#   internet and the list of names that do is now mostly unauthenticated ones:
#   the public path here is wan-ratelimit → wan-inflight → Authelia → 2FA
#   before a single byte reaches this process.
#
#   WHAT IT MEANS THAT THE INDEX IS BEHIND ONE DOOR.  Everything on this page
#   is a link or a read-only statistic, and the tokens that fetch those
#   statistics never leave this container — the browser gets rendered numbers,
#   not credentials, because homepage proxies every widget call server-side.
#   So an Authelia compromise reaches a MAP of the house's services, which is
#   information it largely already had from public DNS, and not a key to any
#   of them.  The four tokens below are still the most concentrated set of
#   read credentials on this host; they are scoped read-only where the service
#   allows it, and that scoping is the operator's job, not this file's.
{ config, lib, pkgs, ... }:

let
  baseDomain = "goclan.org";

  ############################################################################
  # Peers.
  #
  # PEER addresses, hard-coded, which is the deliberate opposite of the rule
  # each container follows for its OWN address — see the same block in
  # containers/traefik.nix.  A service that has moved fails loudly on the tile
  # that names it rather than silently resolving to something else.
  ############################################################################
  traefikAddr = "10.0.90.12";

  # This container's own address, restated for the firewall rule and for the
  # `allowedHosts` entry that makes a direct curl from the host work.  Not
  # used to reach anything: co-resident services are reached on 127.0.0.1.
  arrAddr = "10.0.90.13";

  # The four backends in OTHER namespaces that carry a widget.  Each one costs
  # exactly one accept rule in its own container file, added in this milestone
  # and commented there with this file's name.
  jellyfinAddr  = "10.0.90.10";
  jellyfinPort  = 8096;
  rommAddr      = "10.0.90.22";
  rommPort      = 8080;
  immichAddr    = "10.0.90.25";
  immichPort    = 2283;
  nextcloudAddr = "10.0.90.26";
  nextcloudPort = 80;
  hassAddr      = "10.0.90.27";
  hassPort      = 8123;

  ############################################################################
  # Co-resident ports, on 127.0.0.1.
  #
  # Restated from containers/arr.nix rather than imported, for the reason that
  # file gives for restating them from upstream: the alternative is a shared
  # attrset whose consumers stop being greppable.  These are loopback targets,
  # so a stale number here is a dead tile on one row and nothing else.
  ############################################################################
  sonarrPort         = 8989;
  radarrPort         = 7878;
  prowlarrPort       = 9696;
  bazarrPort         = 6767;
  lidarrPort         = 8686;
  jellyseerrPort     = 5055;
  audiobookshelfPort = 13378;
  komgaPort          = 25600;
  navidromePort      = 4533;
  cleanuparrPort     = 11011;
  mediathekarrPort   = 5007;
  kapowarrPort       = 5656;
  questarrPort       = 5000;
  binderyPort        = 8787;

  ############################################################################
  # Homepage itself.
  #
  # 8082 is the module's default and is free in this netns.  It collides with
  # Traefik's metrics entryPoint by number only — that listener is in a
  # different container's namespace and the two never meet.
  ############################################################################
  homepagePort = 8082;

  # Where the four clan-var tokens are staged for the container to see.
  #
  # A directory WE own, bound in at the identical path, and NOT a bind of
  # /run/secrets — which is a symlink to a per-generation directory that is
  # REPLACED on every deploy, so an nspawn bind established at container start
  # would keep exposing a deleted generation until the container restarted.
  # Same shape and same reasoning as janitorr-secrets and soularr-secrets in
  # containers/arr.nix, and as traefik-secrets before both.
  homepageSecretsDir = "/run/homepage-secrets";

  # Where arr-api-keys.service puts the six it extracts.  Restated from
  # containers/arr.nix; the LoadCredential lines below are the only reader.
  arrSecretsDir = "/run/arr-api-keys";

  tokensGen = config.clan.core.vars.generators.homepage-tokens;

  # Local helper: a co-resident service, reached on loopback.
  local = port: "http://127.0.0.1:${toString port}";

  # Local helper: the public URL a human clicks.  Always the Traefik name and
  # never the backend address — the tile is for a browser, which has to go
  # through the proxy for TLS and for Authelia.
  pub = name: "https://${name}.${baseDomain}";
in
{
  ##############################################################################
  # The four tokens that are not derivable.
  #
  # ONE generator and ONE file rather than four generators, because the
  # consumer is a single EnvironmentFile and four files would mean four
  # staging branches for no gain.  janitorr-jellyfin is the model.
  #
  # ── THE BLANK-PROMPT TRAP, WHICH THIS GENERATOR IS SHAPED AROUND ───────────
  #
  #   A blank clan-vars prompt does NOT mean "optional credential".  It stores
  #   nothing; `files.<n>.path` then evaluates to the literal "/no-such-path";
  #   a consumer that reads it under `set -eu` dies; and every later deploy
  #   re-prompts, which is fatal without a TTY.  That sequence took RomM down
  #   on 2026-09-07 and is worth one comment per generator for as long as
  #   anyone is still writing them.
  #
  #   The shape that avoids it: this script writes EVERY LINE
  #   UNCONDITIONALLY.  A prompt left empty yields `HOMEPAGE_VAR_X=` — a
  #   variable that exists and is empty — so the file is always complete, the
  #   staging unit always succeeds, and the cost of a skipped token is ONE
  #   widget tile reporting an API error next to a link that still works.
  #   That is the correct blast radius for a dashboard credential.
  #
  #   VALUES ARE NOT QUOTED, for the reason janitorr-jellyfin gives: systemd's
  #   EnvironmentFile parser treats quotes as part of the value unless the
  #   whole value is quoted, and a token that silently gains a pair of quotes
  #   fails authentication with a message that says nothing about quoting.
  ##############################################################################
  clan.core.vars.generators.homepage-tokens = {
    files."tokens.env" = {
      secret = true;
    };

    prompts."jellyfin-key" = {
      description = "Jellyfin API key for the dashboard (Dashboard → API Keys → +). Read-only is not offered; a key is a key.";
      type = "hidden";
    };
    prompts."immich-key" = {
      description = "Immich API key for the dashboard (Account Settings → API Keys). Grant server.statistics ONLY.";
      type = "hidden";
    };
    prompts."homeassistant-token" = {
      description = "Home Assistant long-lived access token for the dashboard (Profile → Security → Long-lived access tokens)";
      type = "hidden";
    };
    prompts."nextcloud-token" = {
      description = "Nextcloud serverinfo NC-Token (Administration settings → System → 'Copy token'). NOT a user password.";
      type = "hidden";
    };

    script = ''
      {
        printf 'HOMEPAGE_VAR_JELLYFIN_KEY=%s\n'  "$(cat "$prompts/jellyfin-key")"
        printf 'HOMEPAGE_VAR_IMMICH_KEY=%s\n'    "$(cat "$prompts/immich-key")"
        printf 'HOMEPAGE_VAR_HASS_TOKEN=%s\n'    "$(cat "$prompts/homeassistant-token")"
        printf 'HOMEPAGE_VAR_NEXTCLOUD_KEY=%s\n' "$(cat "$prompts/nextcloud-token")"
      } > "$out/tokens.env"
    '';
    runtimeInputs = [ pkgs.coreutils ];
  };

  ##############################################################################
  # Stage them where the container can see them.
  #
  # Stage an EMPTY file rather than failing when the var is absent, which is
  # soularr-secrets' shape and is here for the matching reason: EnvironmentFile
  # is read by PID 1, so a missing source file kills homepage at step
  # CREDENTIALS with "No such file or directory" — an error naming neither the
  # generator nor the command that would produce it.  An empty file lets the
  # service start and report four broken tiles, which says what is wrong.
  #
  # NOT `requiredBy` container@arr: a homepage that cannot fetch statistics
  # must never be able to keep the *arr from starting.
  #
  # ROTATING A TOKEN needs a restart and not just a deploy — if this unit's
  # text is unchanged, systemd will not re-run it when the underlying sops file
  # changes.  After `clan vars generate ernst`:
  #     systemctl restart homepage-secrets container@arr
  ##############################################################################
  systemd.services.homepage-secrets = {
    description = "Stage the dashboard's service tokens for container@arr";
    after       = [ "local-fs.target" ];
    before      = [ "container@arr.service" ];
    wantedBy    = [ "container@arr.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root ${homepageSecretsDir}
      if [ -r ${tokensGen.files."tokens.env".path} ]; then
        ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
          ${tokensGen.files."tokens.env".path} \
          ${homepageSecretsDir}/tokens.env
      else
        echo "homepage-secrets: no tokens at ${tokensGen.files."tokens.env".path} — run 'clan vars generate ernst'. Staging an empty file so the dashboard starts and reports the missing widgets by name." >&2
        ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
          /dev/null ${homepageSecretsDir}/tokens.env
      fi
    '';
  };

  ##############################################################################
  # The container half.  See the header: this MERGES into containers.arr.
  ##############################################################################
  containers.arr = {
    # READ-ONLY, at the identical path.  The third bind mount in this container
    # that carries a secret.
    bindMounts."${homepageSecretsDir}" = {
      hostPath   = homepageSecretsDir;
      isReadOnly = true;
    };

    config = { ... }: {
      ##########################################################################
      # One more port through Traefik, and through nothing else.
      #
      # This merges with the accept list in containers/arr.nix — both are
      # definitions of `networking.firewall.extraCommands`, which is
      # types.lines and concatenates.  Written out here rather than added to
      # that file's list so the whole of M26's network surface is in one file.
      #
      # LOAD-BEARING, not belt-and-braces, and for the sharpest version of the
      # reason questarr's comment in arr.nix gives: homepage binds 0.0.0.0 (the
      # module sets PORT and nothing else), so inside this netns it is on the
      # veth, on VLAN 90.  This rule and the nixos-fw-log-refuse at the end of
      # the chain are the only things keeping an authenticated-by-Authelia page
      # off that VLAN generally.
      ##########################################################################
      networking.firewall.extraCommands = ''
        iptables -A nixos-fw -p tcp -s ${traefikAddr}/32 --dport ${toString homepagePort} -j nixos-fw-accept
      '';

      services.homepage-dashboard = {
        enable     = true;
        listenPort = homepagePort;

        # REQUIRED since homepage 1.0, and a wrong value here presents as a
        # blank page with a console error rather than as a 403 — so it is the
        # first thing to check if the proxy path works and the browser shows
        # nothing.  Traefik forwards the original Host (there is no
        # passHostHeader = false anywhere in this fleet), so the name the
        # browser typed is the name that must be listed.  The address form is
        # for curling it directly from the host during the test plan.
        allowedHosts = "home.${baseDomain},${arrAddr}:${toString homepagePort}";

        settings = {
          title = "clanarchy";

          # Fixed dark.  This page is read on a television across a living room
          # as often as on a laptop, and the theme switcher offers a light mode
          # that is unreadable at that distance.  Unrelated to the fleet's
          # Stylix polarity, which governs desktops and not a served web page.
          theme = "dark";
          color = "slate";

          headerStyle = "boxed";
          hideVersion = true;

          # Dots rather than ping times: the question this page answers is "is
          # it up", and a millisecond count on a layer-2 hop inside one host is
          # noise that looks like information.
          statusStyle = "dot";

          layout = {
            "Media automation" = { style = "row"; columns = 3; };
            "Libraries"        = { style = "row"; columns = 4; };
            "Household"        = { style = "row"; columns = 3; };
            "Infrastructure"   = { style = "row"; columns = 4; };
            "Fleet"            = { style = "row"; columns = 4; };
          };
        };

        # The top bar.  `search` renders a form the BROWSER submits, so it
        # needs no reachability from this container; DuckDuckGo rather than the
        # house SearXNG because SearXNG has no hostname and no route, and a
        # search box that 404s is worse than one that leaves the house.
        #
        # No `resources` entry — see the header.
        widgets = [
          { search = { provider = "duckduckgo"; target = "_blank"; }; }
          { datetime = { text_size = "l"; format = { dateStyle = "long"; timeStyle = "short"; hourCycle = "h23"; }; }; }
        ];

        bookmarks = [
          {
            "clanarchy" = [
              { "Repository" = [ { abbr = "GH"; href = "https://github.com/lutzgo/clanarchy"; } ]; }
              { "Docs"       = [ { abbr = "DC"; href = "https://lutzgo.github.io/clanarchy"; } ]; }
            ];
          }
          {
            "Network" = [
              { "UDM-Pro"    = [ { abbr = "UI"; href = "https://10.0.1.1/"; } ]; }
              { "Technitium" = [ { abbr = "DNS"; href = "http://10.0.5.3:5380/"; } ]; }
              { "Cloudflare" = [ { abbr = "CF"; href = "https://dash.cloudflare.com/"; } ]; }
            ];
          }
        ];

        services = [
          ####################################################################
          # Group 1 — the six with keys arr-api-keys already stages.
          #
          # Every `url` here is 127.0.0.1: these services are in THIS
          # namespace.  `{{HOMEPAGE_FILE_*}}` is substituted with the CONTENTS
          # of the credential systemd placed in $CREDENTIALS_DIRECTORY — see
          # the LoadCredential block below.
          #
          # No `fields` on any widget in this file, deliberately: the defaults
          # are upstream's choice of what matters per service, and pinning a
          # field list here is a second thing to keep in step with a package
          # this repo does not control.
          ####################################################################
          {
            "Media automation" = [
              {
                "Sonarr" = {
                  icon        = "sonarr.png";
                  href        = pub "sonarr";
                  description = "Television";
                  siteMonitor = local sonarrPort;
                  widget = {
                    type = "sonarr";
                    url  = local sonarrPort;
                    key  = "{{HOMEPAGE_FILE_SONARR_KEY}}";
                  };
                };
              }
              {
                "Radarr" = {
                  icon        = "radarr.png";
                  href        = pub "radarr";
                  description = "Film";
                  siteMonitor = local radarrPort;
                  widget = {
                    type = "radarr";
                    url  = local radarrPort;
                    key  = "{{HOMEPAGE_FILE_RADARR_KEY}}";
                  };
                };
              }
              {
                "Lidarr" = {
                  icon        = "lidarr.png";
                  href        = pub "lidarr";
                  description = "Music";
                  siteMonitor = local lidarrPort;
                  widget = {
                    type = "lidarr";
                    url  = local lidarrPort;
                    key  = "{{HOMEPAGE_FILE_LIDARR_KEY}}";
                  };
                };
              }
              {
                "Prowlarr" = {
                  icon        = "prowlarr.png";
                  href        = pub "prowlarr";
                  description = "Indexers";
                  siteMonitor = local prowlarrPort;
                  widget = {
                    type = "prowlarr";
                    url  = local prowlarrPort;
                    key  = "{{HOMEPAGE_FILE_PROWLARR_KEY}}";
                  };
                };
              }
              {
                "Bazarr" = {
                  icon        = "bazarr.png";
                  href        = pub "bazarr";
                  description = "Subtitles";
                  siteMonitor = local bazarrPort;
                  widget = {
                    type = "bazarr";
                    url  = local bazarrPort;
                    key  = "{{HOMEPAGE_FILE_BAZARR_KEY}}";
                  };
                };
              }
              {
                "Jellyseerr" = {
                  icon        = "jellyseerr.png";
                  href        = pub "jellyseerr";
                  description = "Requests — the household's front door";
                  siteMonitor = local jellyseerrPort;
                  widget = {
                    type = "jellyseerr";
                    url  = local jellyseerrPort;
                    key  = "{{HOMEPAGE_FILE_JELLYSEERR_KEY}}";
                  };
                };
              }
              {
                "Cleanuparr" = {
                  icon        = "cleanuparr.png";
                  href        = pub "cleanuparr";
                  description = "Stalled-download reaper";
                  siteMonitor = local cleanuparrPort;
                };
              }
              {
                "MediathekArr" = {
                  icon        = "mdi-television-classic";
                  href        = pub "mediathekarr";
                  description = "Öffentlich-rechtliche Mediatheken";
                  siteMonitor = local mediathekarrPort;
                };
              }
              {
                "Kapowarr" = {
                  icon        = "kapowarr.png";
                  href        = pub "kapowarr";
                  description = "Comics";
                  siteMonitor = local kapowarrPort;
                };
              }
              {
                "Questarr" = {
                  icon        = "mdi-gamepad-variant";
                  href        = pub "questarr";
                  description = "Games";
                  siteMonitor = local questarrPort;
                };
              }
              {
                "Bindery" = {
                  icon        = "mdi-book-cog";
                  href        = pub "bindery";
                  description = "Ebooks";
                  siteMonitor = local binderyPort;
                };
              }
            ];
          }

          ####################################################################
          # Group 2 — the read-only libraries, all co-resident.
          #
          # Link + loopback status only.  Komga, Navidrome and Audiobookshelf
          # all have homepage widgets that would want a credential; they are
          # three of the five appApiHosts names on the public internet, and
          # minting a fourth long-lived token apiece to render a count is not
          # a trade this milestone makes.  Revisit only if somebody asks for
          # the numbers.
          ####################################################################
          {
            "Libraries" = [
              {
                "Audiobookshelf" = {
                  icon        = "audiobookshelf.png";
                  href        = pub "audiobookshelf";
                  description = "Audiobooks and podcasts";
                  siteMonitor = local audiobookshelfPort;
                };
              }
              {
                "Komga" = {
                  icon        = "komga.png";
                  href        = pub "komga";
                  description = "Comics and manga";
                  siteMonitor = local komgaPort;
                };
              }
              {
                "Navidrome" = {
                  icon        = "navidrome.png";
                  href        = pub "navidrome";
                  description = "Music, over Subsonic";
                  siteMonitor = local navidromePort;
                };
              }
              {
                "Calibre-Web" = {
                  icon        = "calibre-web.png";
                  href        = pub "cwa";
                  description = "Ebooks, OPDS, Kobo and KOReader sync";
                };
              }
            ];
          }

          ####################################################################
          # Group 3 — the five in other namespaces that carry a widget.
          #
          # Each `url` is a peer address on VLAN 90.  FOUR of the five cost one
          # accept rule apiece in that container's own file, added in this
          # milestone and commented there with `dashboardAddr` — grep that name
          # across machines/ernst to find the whole of M26's widening of the
          # fleet's internal reachability, which is those four rules and
          # nothing else.
          #
          # JELLYFIN COST NOTHING, and that is worth a line rather than a
          # silent omission: containers/jellyfin.nix has admitted this
          # container's address on 8096 since M13, for Jellyseerr and Janitorr.
          # The dashboard is the third consumer of a path that already existed,
          # so there is no new rule to find there and no new exposure to argue.
          ####################################################################
          {
            "Household" = [
              {
                "Jellyfin" = {
                  icon        = "jellyfin.png";
                  href        = pub "jellyfin";
                  description = "Film, television and live TV";
                  siteMonitor = "http://${jellyfinAddr}:${toString jellyfinPort}/health";
                  widget = {
                    type             = "jellyfin";
                    url              = "http://${jellyfinAddr}:${toString jellyfinPort}";
                    key              = "{{HOMEPAGE_VAR_JELLYFIN_KEY}}";
                    enableNowPlaying = true;
                  };
                };
              }
              {
                "Immich" = {
                  icon        = "immich.png";
                  href        = pub "photos";
                  description = "The household photo library";
                  widget = {
                    type    = "immich";
                    url     = "http://${immichAddr}:${toString immichPort}";
                    key     = "{{HOMEPAGE_VAR_IMMICH_KEY}}";
                    # Required for Immich >= v1.118; without it the widget
                    # calls a removed endpoint and reports an API error while
                    # the service itself is perfectly healthy.
                    version = 2;
                  };
                };
              }
              {
                "Nextcloud" = {
                  icon        = "nextcloud.png";
                  href        = pub "cloud";
                  description = "Files, calendars and contacts";
                  widget = {
                    type = "nextcloud";
                    url  = "http://${nextcloudAddr}:${toString nextcloudPort}";
                    # The serverinfo NC-Token, not a user password.  Both are
                    # accepted by the widget and only one of them is a
                    # credential that can log in.
                    key  = "{{HOMEPAGE_VAR_NEXTCLOUD_KEY}}";
                  };
                };
              }
              {
                "Home Assistant" = {
                  icon        = "home-assistant.png";
                  href        = pub "ha";
                  description = "Home automation";
                  widget = {
                    type = "homeassistant";
                    url  = "http://${hassAddr}:${toString hassPort}";
                    key  = "{{HOMEPAGE_VAR_HASS_TOKEN}}";
                  };
                };
              }
              {
                "RomM" = {
                  icon        = "romm.png";
                  href        = pub "romm";
                  description = "ROM library — mastered here, synced to birte";
                  widget = {
                    type = "romm";
                    url  = "http://${rommAddr}:${toString rommPort}";
                  };
                };
              }
            ];
          }

          ####################################################################
          # Group 4 — infrastructure.  Links only.
          #
          # No widgets and no siteMonitor: three of these five are the things
          # that would have to be working for this page to be reachable at all
          # (Traefik, Authelia) or are the thing that watches everything
          # including this (Grafana).  A green dot drawn by the service being
          # watched is not evidence, and putting one here would invite reading
          # it as if it were.
          ####################################################################
          {
            "Infrastructure" = [
              {
                "Grafana" = {
                  icon        = "grafana.png";
                  href        = pub "grafana";
                  description = "Metrics, alerts and ZFS — the ops truth";
                };
              }
              {
                "Authelia" = {
                  icon        = "authelia.png";
                  href        = pub "auth";
                  description = "Identity — you came through here";
                };
              }
              {
                "Open WebUI" = {
                  icon        = "open-webui.png";
                  href        = pub "chat";
                  description = "The local model";
                };
              }
              {
                "Tvheadend" = {
                  icon        = "tvheadend.png";
                  href        = pub "tvheadend";
                  description = "DVB-C tuners and the EPG";
                };
              }
              {
                "TubeSync" = {
                  icon        = "tubesync.png";
                  href        = pub "tubesync";
                  description = "YouTube subscriptions";
                };
              }
              {
                "Storyteller" = {
                  icon        = "mdi-book-music";
                  href        = pub "storyteller";
                  description = "Ebook/audiobook alignment";
                };
              }
              {
                "slskd" = {
                  icon        = "slskd.png";
                  href        = pub "slskd";
                  description = "Soulseek, in the microvm";
                };
              }
            ];
          }

          ####################################################################
          # Group 5 — the rest of the fleet.
          #
          # Deep links into M6's `clanarchy-fleet` dashboard, filtered by the
          # `instance` label — which service-modules/monitoring.nix sets to the
          # MACHINE NAME rather than letting Prometheus derive it from the
          # target address, so these values are stable and these links do not
          # depend on a scrape address.
          #
          # NO STATUS ON ANY OF THEM — see the header.  These four machines are
          # scraped over ZeroTier IPv6 from the monitoring container, and this
          # container has no route to any of that.
          ####################################################################
          {
            "Fleet" = [
              {
                "miralda" = {
                  icon        = "mdi-laptop";
                  href        = "${pub "grafana"}/d/clanarchy-fleet?var-instance=miralda";
                  description = "Framework 13 AMD — lgo";
                };
              }
              {
                "jens" = {
                  icon        = "mdi-tablet";
                  href        = "${pub "grafana"}/d/clanarchy-fleet?var-instance=jens";
                  description = "Framework 12 Intel — lgo";
                };
              }
              {
                "biene" = {
                  icon        = "mdi-laptop";
                  href        = "${pub "grafana"}/d/clanarchy-fleet?var-instance=biene";
                  description = "Lenovo — Sabine";
                };
              }
              {
                "birte" = {
                  icon        = "mdi-gamepad";
                  href        = "${pub "grafana"}/d/clanarchy-fleet?var-instance=birte";
                  description = "Steam Deck OLED";
                };
              }
              {
                "ernst" = {
                  icon        = "mdi-server";
                  href        = "${pub "grafana"}/d/clanarchy-fleet?var-instance=ernst";
                  description = "This machine";
                };
              }
            ];
          }
        ];

        # The four clan-var tokens.  Read by PID 1 as root before the drop to
        # the dynamic user, which is what lets the staged file stay 0400 root.
        environmentFiles = [ "${homepageSecretsDir}/tokens.env" ];
      };

      ##########################################################################
      # The six derived keys.
      #
      # `requires` + `after`, which is scraparr's and soularr's shape in this
      # same container.  arr-api-keys is a oneshot with RemainAfterExit = false
      # and RuntimeDirectoryPreserve = "yes", so requiring it means it re-runs
      # on every start of this unit and the keys are re-read from each
      # service's config.xml — which is the whole point: a key rotated in a web
      # UI is picked up by restarting the consumer, with nothing to edit here.
      #
      # `%d` is systemd's specifier for $CREDENTIALS_DIRECTORY and expands in
      # Environment= as it does in ExecStart=.  Homepage reads the path out of
      # the environment and substitutes the FILE'S CONTENTS into the YAML, so
      # the key itself is never an environment variable and never appears in
      # `systemctl show`.
      #
      # This is an ADDITIVE merge onto the unit the nixpkgs module defines.
      # Both `environment` and `serviceConfig.LoadCredential` merge cleanly —
      # attrset and list respectively — and nothing here overrides a directive
      # the module already sets.  (Were that ever needed, note that an
      # ExecStart-style additive directive would need the list form with an
      # empty first element; nothing in this block is one.)
      ##########################################################################
      systemd.services.homepage-dashboard = {
        after    = [ "arr-api-keys.service" ];
        requires = [ "arr-api-keys.service" ];

        environment = {
          HOMEPAGE_FILE_SONARR_KEY     = "%d/sonarr-api-key";
          HOMEPAGE_FILE_RADARR_KEY     = "%d/radarr-api-key";
          HOMEPAGE_FILE_LIDARR_KEY     = "%d/lidarr-api-key";
          HOMEPAGE_FILE_PROWLARR_KEY   = "%d/prowlarr-api-key";
          HOMEPAGE_FILE_BAZARR_KEY     = "%d/bazarr-api-key";
          HOMEPAGE_FILE_JELLYSEERR_KEY = "%d/jellyseerr-api-key";
        };

        serviceConfig.LoadCredential = [
          "sonarr-api-key:${arrSecretsDir}/sonarr-api-key"
          "radarr-api-key:${arrSecretsDir}/radarr-api-key"
          "lidarr-api-key:${arrSecretsDir}/lidarr-api-key"
          "prowlarr-api-key:${arrSecretsDir}/prowlarr-api-key"
          "bazarr-api-key:${arrSecretsDir}/bazarr-api-key"
          "jellyseerr-api-key:${arrSecretsDir}/jellyseerr-api-key"
        ];
      };
    };
  };
}
