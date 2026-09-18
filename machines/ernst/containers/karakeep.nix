# machines/ernst/containers/karakeep.nix
#
# Karakeep — bookmarks, full-page archives and search over both.  The KEEP half
# of M27's reading stack (see docs/roadmap.md); containers/miniflux.nix is the
# intake half.  An nspawn container on VLAN 90 serving `karakeep.goclan.org`
# through Traefik on BOTH entrypoints, with Authelia as its sole identity
# provider and ernst's own inference server doing the tagging.
#
# ── WHAT THIS REPLACES: A SERVER THAT NEVER EXISTED ─────────────────────────
#
#   machines/miralda/home-modules/browsers.nix has carried a Linkwarden
#   extension ID marked "⚠ spec-provided, unverified" since the browser stack
#   was written, next to a Vimium keybinding whose target is the literal string
#   YOUR_LINKWARDEN_INSTANCE, next to a comment doubting whether the Firefox
#   add-on it names exists.  There has never been a Linkwarden anywhere in this
#   fleet.  M27 resolves that by deleting those lines rather than by finally
#   standing up the server they point at — Karakeep takes the role, and this is
#   the instance the extensions are configured against.
#
# ── IT IS ALSO THE FLOCCUS BACKEND, WHICH IS WHY THE STACK IS ONE MILESTONE ─
#
#   Floccus (the browser bookmark-sync add-on, installed declaratively on
#   miralda and jens — see service-modules/software.nix and browsers.nix) gained
#   a native Karakeep adapter in 5.10.  So the browsers' own bookmark trees and
#   the archived copies land in ONE database with one search over them, instead
#   of in a bookmark sync server and an archive that know nothing about each
#   other.  Nextcloud Bookmarks and a WebDAV XBEL blob were the alternatives;
#   both would have added a second store for the same nouns.
#
# ── WHY THE nspawn TIER ─────────────────────────────────────────────────────
#
#   `services.karakeep` is a first-class NixOS module at this pin, and it is
#   not a thin wrapper: it builds four units (init, workers, web, browser) and
#   pulls in Meilisearch.  The podman tier on this host exists for upstreams
#   that ship only an OCI image — Karakeep publishes one, but nixpkgs packages
#   the application itself, and an available module beats an available image.
#   containers/nextcloud.nix argues the tier question at length.
#
# ── NO forward-auth ON THIS HOSTNAME ────────────────────────────────────────
#
#   `karakeep.goclan.org` is in `appApiHosts` (containers/ingress-policy.nix),
#   and unusually for that list the clients that fail the 302 test are ones
#   THIS REPO INSTALLS:
#
#     * the Karakeep browser extension on all four of lgo's browsers, which
#       posts to /api/v1/bookmarks with a bearer token;
#     * the Floccus adapter, same token, no cookie jar and no UI;
#     * the mobile apps, same again.
#
#   So the vhost is answered by Karakeep, not by Authelia, and the BROWSER path
#   gets its second factor from Authelia's OIDC provider instead — Nextcloud's
#   and CWA's arrangement (OIDC INSTEAD OF the middleware), not Grafana's
#   (OIDC AS WELL AS it).
#
# ── IT IS ON THE INTERNET, AND MINIFLUX IS NOT ──────────────────────────────
#
#   `wanExposed` in containers/traefik.nix names this router and not the feed
#   reader's, which is a deliberate asymmetry rather than an oversight.
#   Bookmark sync is the half of this stack that has to work from somewhere
#   that is not the house: miralda and jens are laptops, and a Floccus that
#   only syncs on the home LAN silently diverges the moment either one leaves.
#   Reading feeds can wait for the LAN.  Ledger row L17 in docs/roadmap.md
#   records the exposure.
#
#   The compensating controls `appApiHosts` demands, in order: Karakeep's own
#   accounts with password auth DISABLED entirely (see below), `wan-ratelimit`
#   + `wan-inflight`, `wan-login-ratelimit` on the credential path, and
#   CrowdSec reading Traefik's access log.
#
# ── NO LOCAL PASSWORD AT ALL ────────────────────────────────────────────────
#
#   `DISABLE_PASSWORD_AUTH` plus `DISABLE_SIGNUPS` below means Authelia is the
#   only way in, which is the same call containers/miniflux.nix makes and the
#   opposite of containers/home-assistant.nix's.  The reason is the one that
#   file gives: nothing in the house depends on this service, so "fix Authelia"
#   is an acceptable recovery path, and it is a much better answer than a
#   second credential store reachable from the internet.
#
# ── THE SECOND LEG, AND WHY IT COSTS NO VRAM ────────────────────────────────
#
#   Karakeep auto-tags and summarises every saved page.  It does that against
#   ernst's OWN inference server over a point-to-point /128 veth (`ai0`,
#   fdca:fe92::), exactly the mechanism service-modules/local-ai.nix built for
#   the monitoring container and Open WebUI — a socket on the host end, ONE
#   firewall accept for the container end, and no VLAN exposure whatsoever.
#
#   NOTE THE MODEL CHOICE.  `INFERENCE_TEXT_MODEL` is `qwen3-coder-30b`, the
#   model llama-swap ALREADY has resident for lgo's coding agent — declared in
#   clan.nix's `roles.models`.  llama-swap runs its LLMs in an exclusive group,
#   so naming any other text model here would EVICT the coder model on every
#   bookmark and stall the agent on the next keystroke.  Reusing the resident
#   one costs nothing: no eviction, no second set of weights, no VRAM.
#
#   THE IMAGE MODEL IS THE EXCEPTION AND IT IS PRICED HERE RATHER THAN
#   DISCOVERED.  `qwen2.5-vl-7b` is a different model in that same exclusive
#   group, so saving an IMAGE bookmark does evict the coder model and the next
#   agent request pays a reload.  That is acceptable because image bookmarks
#   are rare and the alternative — leaving the karakeep default of
#   `gpt-4o-mini`, a model that does not exist here — is a request that fails
#   with a name nothing on this host has ever served.  M19's restart-loop
#   lesson, in miniature.
#
# ── uid 3038, AND IT IS LOAD-BEARING ────────────────────────────────────────
#
#   The nixpkgs module creates `karakeep` with `isSystemUser = true` and no
#   uid, and nspawn passes ids through UNMAPPED — so whatever the container's
#   useradd happens to pick is the number that ends up on every archived page
#   on zdata.  Adding an unrelated user to this container could otherwise
#   change the owner of the whole archive.  Its OWN group, not `media`: this
#   service hardlinks nothing and never touches /srv/media.
#
# ── NO NEW DATASET, AND MEILISEARCH IS DELIBERATELY NOT ON ZDATA ────────────
#
#   DATA_DIR (the SQLite database and the archived assets) is bound to
#   /srv/state/karakeep — `zdata/state`, 128K, `com.sun:auto-snapshot=true`.
#   The snapshot property is the part that matters, for the reason
#   machines/ernst/disko.nix gives about Nextcloud: IT IS DELETED FROM BY
#   PEOPLE, and a crawled copy of a page that has since gone dark is not
#   re-acquirable from anywhere.
#
#   MEILISEARCH'S INDEX STAYS ON THE CONTAINER ROOTFS, and that is a decision
#   rather than an omission.  The nixpkgs meilisearch module runs under
#   `DynamicUser` with `StateDirectory = meilisearch`, so binding it out would
#   put a systemd-allocated uid — a number nobody chose and nothing records —
#   on zdata, which is precisely what the uid table in
#   machines/ernst/networking.nix exists to prevent.  The index is DERIVED
#   data: it is rebuilt from the SQLite database by Karakeep's own reindex
#   action (Settings → Search → "Reindex all bookmarks", or
#   `karakeep-cli` against the API).  Losing it costs a rebuild, not data.
#   The rootfs under /var/lib/nixos-containers IS persisted by
#   machines/ernst/configuration.nix, so this survives an ordinary reboot too.
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

  # From the allocation table in machines/ernst/networking.nix.  See the header
  # for why pinning it is load-bearing rather than hygiene.
  karakeepUid = 3038;
  karakeepGid = 3038;

  ##############################################################################
  # Peers, ports and paths.
  ##############################################################################

  # The one VLAN-90 peer allowed to reach the web surface.  Every client — a
  # browser, the extensions, Floccus, the phone apps — arrives through it.
  # M5's backend-bypass hardening, mechanism (a).
  traefikAddr = "10.0.90.12";

  # The service index (M26), which fetches the bookmark counts with an API key.
  # Tagged with this name in every container that carries a widget so one grep
  # finds them all.
  dashboardAddr = "10.0.90.13";

  karakeepAddr = "10.0.90.29";
  karakeepPort = 3000;

  baseDomain = "goclan.org";
  hostName   = "karakeep.${baseDomain}";

  # ── The inference leg ─────────────────────────────────────────────────────
  #
  # Declared as a peer in clan.nix's `@clanarchy/local-ai` instance
  # (`roles.ollama.…exposeOn`), which is what puts a socket on the host end and
  # one accept rule in ernst's own firewall.  ALL THREE PARTS ARE REQUIRED and
  # each fails silently on its own — see the long note on that option in
  # service-modules/local-ai.nix.  This file supplies the third: the consumer
  # pointed at the address rather than at localhost.
  aiVeth = "ai0";
  aiHost = "fdca:fe92::1";
  aiCont = "fdca:fe92::2";
  swapUrl = "http://[${aiHost}]:11434";

  # Authelia's portal, as the OIDC issuer.
  #
  # NOTE THE SUFFIX, WHICH containers/miniflux.nix DELIBERATELY OMITS.
  # Karakeep's `OAUTH_WELLKNOWN_URL` is the FULL discovery document URL;
  # Miniflux's `OAUTH2_OIDC_DISCOVERY_ENDPOINT` is the issuer with the
  # well-known path stripped, because its library appends that itself.  Two
  # adjacent files, two conventions, each read out of the application that
  # consumes it rather than copied from its neighbour.  That is M23's lesson
  # stated as a habit.
  autheliaWellKnown = "https://auth.${baseDomain}/.well-known/openid-configuration";

  dataRoot = "/srv/state/karakeep";

  ##############################################################################
  # Secrets staging.
  #
  # NOT a bind of /run/secrets itself: that path is a symlink to a
  # per-generation directory which is REPLACED on every deploy, so an nspawn
  # bind established at container start would keep exposing a deleted
  # generation.  containers/traefik.nix carries the long form of this.
  ##############################################################################
  secretsDir  = "/run/karakeep-secrets";
  oidcEnvFile = "${secretsDir}/oidc.env";

  # Declared in containers/authelia.nix, beside the other relying parties —
  # ONE GENERATOR PER RELYING PARTY is that file's rule.  Authelia takes the
  # DIGEST; this container takes the PLAINTEXT half of the same pair.
  oidcGen = config.clan.core.vars.generators.authelia-oidc-karakeep;
in
{
  ##############################################################################
  # Host side — the directories, the secrets and the veth.
  ##############################################################################

  # ── NO tmpfiles RULES IN THIS FILE, AND containers/immich.nix IS WHY ───────
  #
  # That file records the measured failure: host-side directories shipped as
  # `systemd.tmpfiles.rules` and the container died five times into its start
  # limit with `Failed to clone …: No such file or directory`, because
  # activating a new configuration does not re-run systemd-tmpfiles-setup in
  # time for a container the same activation starts.
  systemd.services.karakeep-dirs = {
    description = "Verify /srv/state is mounted and create Karakeep's data directory";
    wantedBy   = [ "multi-user.target" ];
    after      = [ "srv-state.mount" ];
    requires   = [ "srv-state.mount" ];
    before     = [ "container@karakeep.service" ];
    requiredBy = [ "container@karakeep.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.util-linux pkgs.coreutils ];

    # BLOCKING (`requires` + `requiredBy`), not advisory, for the reason
    # containers/nextcloud.nix gives: a Karakeep that starts without its data
    # directory is not a degraded Karakeep, it is a NEW EMPTY one on zroot that
    # will accept bookmarks, crawl and archive them, report success to the
    # extension, and lose the lot at the next boot.  It FAILS rather than
    # repairing itself — a unit that silently fixes storage layout hides the
    # fact that the layout was wrong.
    script = ''
      set -eu

      # THE TARGET IS THE PARENT, NOT ${dataRoot}.  `findmnt --target` on a
      # path that does not exist yet returns nothing — it does not walk up to
      # the nearest existing ancestor — so checking the leaf would fail on
      # every first run.  immich-dirs refused its own first deploy that way on
      # 2026-09-11.
      ssrc=$(findmnt --noheadings --output SOURCE --target /srv/state || true)
      if [ "$ssrc" != "zdata/state" ]; then
        echo "karakeep-dirs: /srv/state is not zdata/state (found '$ssrc')." >&2
        echo "  Refusing to create Karakeep's data directory, because it would" >&2
        echo "  land on zroot and be rolled back on the next boot — taking the" >&2
        echo "  archived copies with it." >&2
        echo "  See docs/guides/ernst-zdata-datasets.md." >&2
        exit 1
      fi

      # NUMERIC ids on purpose: `karakeep` is a CONTAINER user and the host has
      # no matching passwd entry.  Same shape traefik.nix uses for uid 3005.
      #
      # 0700 is asked for; systemd's own StateDirectory handling inside the
      # container may settle it at 0750, the way the nixpkgs Nextcloud module's
      # tmpfiles rules do there.  That is not forced back here for the same two
      # reasons nextcloud.nix gives — a competing rule for one path is the M3
      # defect, and `getent group 3038` on the HOST returns nothing, so the
      # group bit grants nobody anything.
      install -d -o ${toString karakeepUid} -g ${toString karakeepGid} -m 0700 ${dataRoot}
    '';
  };

  # ── Stage the OIDC client credentials where the container can see them ────
  #
  # AS AN ENVIRONMENT FILE, NOT AS `extraEnvironment` ENTRIES.  That attrset is
  # rendered into the unit's `Environment=` lines and therefore into the Nix
  # store, which is world-readable on this host.  A client secret has no
  # business there.  Everything that is NOT a secret does go in
  # `extraEnvironment`, where it is legible in `systemctl cat`.
  #
  # ROTATING THE SECRET needs a restart, not just a deploy: this unit's script
  # embeds the sops PATH and not the contents, so systemd sees an unchanged
  # unit and does not re-run it.  The generator therefore carries
  # `restartUnits`.  By hand it is:
  #     systemctl restart karakeep-secrets container@karakeep
  systemd.services.karakeep-secrets = {
    description = "Stage Karakeep's OIDC client credentials for container@karakeep";
    after       = [ "local-fs.target" ];
    before      = [ "container@karakeep.service" ];
    requiredBy  = [ "container@karakeep.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils ];
    script = ''
      set -euo pipefail

      # 0711: traversable by anyone, listable by nobody.
      install -d -m 0711 -o root -g root ${secretsDir}

      # 0400 root:root: an `EnvironmentFile=` is opened by PID 1 while it builds
      # the execution context, BEFORE the unit drops to the karakeep uid, so
      # root ownership is right here.  Contrast containers/nextcloud.nix, where
      # the file is read by an unprivileged setup script and is chowned to the
      # service uid — different reader, different answer.
      umask 077
      {
        printf 'OAUTH_CLIENT_ID=karakeep\n'
        printf 'OAUTH_CLIENT_SECRET=%s\n' "$(cat ${oidcGen.files."karakeep-client-secret".path})"
      } > ${oidcEnvFile}.tmp
      chmod 0400 ${oidcEnvFile}.tmp
      mv -f ${oidcEnvFile}.tmp ${oidcEnvFile}
    '';
  };

  # Host side of the container's VLAN-90 veth — a bridge port on br0.  The
  # SECOND leg (ai0) is not here: nixos-containers creates that pair itself
  # from `extraVeths` and adds the matching host route on both sides, because
  # it is a point-to-point /128 link and not a bridge port.
  systemd.network.networks."60-vb-karakeep" = {
    matchConfig.Name = "vb-karakeep";
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
  # `bridge vlan show dev vb-karakeep` is the check.
  systemd.services."container@karakeep".serviceConfig.ExecStartPost = [
    "-${pkgs.iproute2}/bin/bridge vlan add dev vb-karakeep vid 90 pvid untagged"
  ];

  ##############################################################################
  # The container.
  ##############################################################################
  containers.karakeep = {
    autoStart = true;
    ephemeral = false;

    # MAC from the allocation table in machines/ernst/networking.nix; the DHCP
    # reservation 10.0.90.29 on the UDM-Pro keys on it (manual step).  Sequence
    # 15, and the last octet is 8 + seq as everywhere else on this bridge.
    privateNetwork  = true;
    hostBridge      = "br0";
    localMacAddress = "02:00:00:90:00:15";

    # Leg 2 — the point-to-point link to the host, carrying exactly one thing:
    # inference requests to llama-swap.  /128 on each end, so nixos-containers
    # adds the matching host route on both sides and there is no on-link
    # assumption to get wrong.  Copied in shape from Open WebUI's leg in
    # service-modules/local-ai.nix.
    extraVeths.${aiVeth} = {
      hostAddress6  = aiHost;
      localAddress6 = aiCont;
    };

    bindMounts = {
      # DATA_DIR, bound at the module's OWN default so that `DATA_DIR`, the
      # units' `StateDirectory` and karakeep-init's migration all agree with
      # nothing overridden.  Upstream's own documentation says changing
      # DATA_DIR is "possible but not supported", which settles it.
      "/var/lib/karakeep" = {
        hostPath   = dataRoot;
        isReadOnly = false;
      };

      "${secretsDir}" = {
        hostPath   = secretsDir;
        isReadOnly = true;
      };
    };

    config = { config, pkgs, lib, ... }: {
      system.stateVersion = "26.05";

      ##########################################################################
      # ── THE ONE INSECURE PACKAGE THIS FLEET PERMITS ON THE STABLE SIDE ─────
      #
      # `pkgs.karakeep` builds its JavaScript with `pnpm_9`, which nixpkgs
      # 26.05 marks insecure.  Without this line the build refuses at
      # evaluation and the error names pnpm rather than Karakeep.
      #
      # IT IS DECLARED HERE, INSIDE THE CONTAINER, AND NOT IN clan.nix.  That
      # was the first attempt and it does nothing: a `containers.<n>.config` is
      # its own NixOS evaluation with its own nixpkgs instance, so the
      # `pkgsForSystem` config clan-core force-sets on the HOST never reaches
      # it.  Measured — the grant was added there, the build failed with the
      # identical message, and the stack trace named
      # `containers.karakeep.systemd.services.karakeep-init.script`.  Keeping
      # it here also makes the grant as narrow as the mechanism allows: it
      # applies to one container and nothing else on this machine.
      #
      # lib/mk-machine.nix carries the SAME line for the unstable pkgs
      # instance, where birte pulls pnpm through Jovian's KDE tooling.  Two
      # grants, two reasons, neither reachable from the other.
      #
      # THIS IS NOT KARAKEEP CHOOSING A STALE TOOLCHAIN, which is the first
      # thing worth checking before permitting anything: EVERY pnpm variant in
      # this pin carries the identical seven CVEs, 10.29.2 included
      # (pkgs/development/tools/pnpm/default.nix).  There is no newer pnpm to
      # move to.
      #
      # AND IT IS BUILD-TIME ONLY.  pnpm runs inside a sandboxed derivation
      # over a lockfile whose hashes `fetchPnpmDeps` has already pinned; it is
      # in no runtime closure and nothing in this container executes it.
      # Revisit when a patched pnpm lands — this line should come out on its
      # own rather than be renewed by habit.
      ##########################################################################
      nixpkgs.config.permittedInsecurePackages = [ "pnpm-9.15.9" ];

      ##########################################################################
      # Networking — TWO legs.
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
          # SN2: v4 only on the VLAN leg.  M18 measured that IPv6AcceptRA alone
          # blocks an RA but NOT link-local assignment; this is the line that
          # actually makes `ip -6 addr show dev eth0` empty.  The ai0 leg below
          # is v6 and is the deliberate exception — a ULA /128 on a
          # point-to-point link that is on no VLAN at all.
          LinkLocalAddressing = "no";
        };
        dhcpV4Config = {
          UseDNS     = false;
          UseDomains = false;
        };
        linkConfig.RequiredForOnline = "routable";
      };

      systemd.network.networks."20-${aiVeth}" = {
        matchConfig.Name = aiVeth;
        address = [ "${aiCont}/128" ];
        routes  = [ { Destination = "${aiHost}/128"; Scope = "link"; } ];
        networkConfig.IPv6AcceptRA = false;
        # "no", for the reason service-modules/monitoring.nix measured and wrote
        # down: a veth pair has no carrier until BOTH ends are up, and the host
        # end is brought up by container@…'s postStart, which runs only after
        # the container has finished booting.  Requiring any state here waits
        # for an event its own completion is a precondition for.
        linkConfig.RequiredForOnline = "no";
      };

      # Same 20 s cap as every sibling: a DHCP failure must leave a RUNNING
      # container with one failed unit, not a host-side restart loop.
      systemd.network.wait-online.timeout = 20;

      # ── The container firewall ────────────────────────────────────────────
      #
      #   3000/tcp from Traefik     — every human, every extension, Floccus.
      #   3000/tcp from the index   — M26's widget.
      #
      # NOTHING is opened on ai0: that leg only ever carries OUTBOUND requests
      # to the host, and replies arrive on an established connection.
      #
      # extraCommands, not extraInputRules: the latter is declared
      # unconditionally but consumed only under networking.nftables, so here it
      # would produce no rule and no warning.
      #
      # ── THE NEGATIVE CONTROL THIS IMPLIES ────────────────────────────────
      #
      #   `curl http://10.0.90.29:3000/` RUN ON ernst IS REFUSED, BY DESIGN.
      #   ernst is 10.0.50.10 and matches neither rule.  M24's test plan asked
      #   for a 200 there that could never happen and sent its reader hunting a
      #   fault that was the firewall working.
      networking.firewall.allowedTCPPorts = [ ];
      networking.firewall.extraCommands = ''
        iptables -A nixos-fw -p tcp -s ${traefikAddr}/32   --dport ${toString karakeepPort} -j nixos-fw-accept
        iptables -A nixos-fw -p tcp -s ${dashboardAddr}/32 --dport ${toString karakeepPort} -j nixos-fw-accept
      '';

      ##########################################################################
      # The service.
      ##########################################################################
      services.karakeep = {
        enable = true;

        # Meilisearch, on the container's own loopback.  The module wires
        # MEILI_ADDR from `services.meilisearch.listenPort` itself.  Its index
        # is deliberately NOT on zdata — see the header.
        meilisearch.enable = true;

        # The headless-chromium worker that takes full-page screenshots.
        #
        # THIS IS THE LEAST PROVEN THING IN THIS FILE.  It runs chromium
        # `--no-sandbox` under `DynamicUser` with `PrivateUsers = true`, i.e. a
        # nested user namespace inside an nspawn container, which nothing else
        # on this host does.  If it refuses to start, the fallback is
        # `browser.enable = false`: bookmarks, crawling, text extraction,
        # search and tagging all keep working and only the screenshots go.
        # Do that rather than loosening the sandbox.
        browser.enable = true;

        # The OIDC client id and secret, out of the staged file rather than out
        # of the world-readable store.  The module appends this to its own
        # `/var/lib/karakeep/settings.env`, so both are read.
        environmentFile = oidcEnvFile;

        extraEnvironment = {
          # Karakeep builds every absolute URL from this — the OIDC redirect
          # above all.  Getting it wrong fails closed at Authelia with
          # `invalid_redirect_uri`, which reads as an Authelia fault.
          NEXTAUTH_URL = "https://${hostName}";

          # ── Authentication.  SEE THE HEADER — no local password exists ────
          DISABLE_SIGNUPS       = "true";
          DISABLE_PASSWORD_AUTH = "true";
          OAUTH_PROVIDER_NAME   = "Authelia";
          OAUTH_WELLKNOWN_URL   = autheliaWellKnown;

          # The FIRST login has to be able to create the account, since there
          # is no other way for one to exist here and signups are off.  Karakeep
          # links an OAuth identity to an existing local account only with this
          # set; with no local accounts at all it is what admits the first user.
          # Narrow because the issuer is ours and the email claim comes from
          # Authelia's own user database.
          OAUTH_ALLOW_DANGEROUS_EMAIL_ACCOUNT_LINKING = "true";

          # Nothing on this host updates itself; the answer is never actionable
          # and it is an outbound request on every start.
          DISABLE_NEW_RELEASE_CHECK = "true";

          # ── Inference.  See the header for the model choice and its cost ──
          OPENAI_BASE_URL = "${swapUrl}/v1";

          # llama-swap takes no credential; the OpenAI client library requires
          # the variable to exist before it will use the endpoint at all.  The
          # same literal Open WebUI uses in service-modules/local-ai.nix, so a
          # grep for it finds both consumers.
          OPENAI_API_KEY = "sk-no-key-required";

          # Both names must match KEYS in ernst's `roles.models` in clan.nix.
          # `qwen3-coder-30b` is the resident one; `qwen2.5-vl-7b` evicts it.
          INFERENCE_TEXT_MODEL  = "qwen3-coder-30b";
          INFERENCE_IMAGE_MODEL = "qwen2.5-vl-7b";

          INFERENCE_ENABLE_AUTO_TAGGING       = "true";
          INFERENCE_ENABLE_AUTO_SUMMARIZATION = "true";
          INFERENCE_LANG                      = "english";

          # 8192, not the 2048 default and not the 32768 the model serves.  The
          # default truncates most long-form articles before the tagger sees
          # the argument; the full window would make every bookmark a 32k-token
          # prompt against a model a human is waiting on for something else.
          INFERENCE_CONTEXT_LENGTH = "8192";

          # 300s, not the 30s default.  llama-swap may have to LOAD a 21 GiB
          # model before the first token, and a 30-second ceiling would turn
          # every cold request into a failure that looks like a broken endpoint.
          INFERENCE_JOB_TIMEOUT_SEC = "300";

          # One at a time.  The card is shared with lgo's coding agent and with
          # Open WebUI; parallel tagging jobs would queue behind each other in
          # llama-swap anyway, and a single worker makes that visible in the
          # journal instead of as latency.
          INFERENCE_NUM_WORKERS = "1";
        };
      };

      # ── Pin the ids ───────────────────────────────────────────────────────
      #
      # See the header: unmapped nspawn ids mean a container-chosen number is a
      # number on the pool.
      users.users.karakeep.uid  = karakeepUid;
      users.groups.karakeep.gid = karakeepGid;
    };
  };
}
