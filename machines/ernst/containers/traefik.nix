# machines/ernst/containers/traefik.nix
#
# Traefik v3 in an nspawn container: one reverse proxy on its own L2 identity,
# so every consumer VLAN collapses to a single permanent firewall rule pointing
# at THIS address instead of one rule per backend.
#
# nspawn per invariant #1: Traefik terminates TLS for in-house services and
# never fetches attacker-supplied URLs, so it is trusted tier.  (The workload
# that DOES render hostile pages is FlareSolverr — see containers/arr/.)
#
# History: docs/history.md M2b (the veth), M16 (the Cloudflare Tunnel, now
# deleted), M18 (the WAN forward that replaced it), M7 (Authelia).
#
# ── WHERE THINGS LIVE.  THIS FILE IS THE SHELL ──────────────────────────────
#
#   ./traefik/peers.nix     PURE DATA — the MAC, uid/gid, baseDomain,
#                           acmeEmail, and every backend's address and port.
#                           Fifty-eight bindings, inherited below so that
#                           every reference elsewhere reads unchanged.
#   ./traefik/wan.nix       the `wan` entrypoint's name and port,
#                           `wanExposed`, `wanLoginPaths`, and `withWan` —
#                           the guard that THROWS at evaluation.  One
#                           mechanism, so one file.
#   ./traefik/static.nix    staticConfigOptions: entrypoints, the ACME
#                           resolver, the metrics listener.  Restart, not
#                           reload.
#   ./traefik/dynamic.nix   dynamicConfigOptions: every router, service and
#                           middleware.  The half that changes when a service
#                           is added.
#   ./ingress-policy.nix    which hostnames may carry forward-auth.  Shared
#                           with containers/authelia.nix; NOT in ./traefik/
#                           because it is not this file's to own.
#
#   This file keeps the container declaration, the firewall, the secrets
#   staging unit and the vars generator.  It was 2,972 lines — 45k tokens,
#   more than the local coding model's whole window — and the sections above
#   had no reason to share a file beyond having been written in one.  Every
#   step of the split was gated on all five machine drvs staying
#   byte-identical.
#
# ── Networking: veth on br0, Services VLAN 90 ────────────────────────────────
#
#   The skeleton is modules/containers/nspawn.nix; its header owns the
#   rationale (KeepMaster over Bridge=, the VLAN-race backstop, the 20 s
#   wait-online cap).
#
#   MAC 02:00:00:90:00:04 ↔ DHCP reservation 10.0.90.12, in
#   machines/ernst/allocations.nix.  The reservation lives on the UDM-Pro, not
#   here, because the UDM-Pro owns the pool and a second copy diverges
#   silently.  It must be INSIDE the pool (10.0.90.6–.254): UniFi accepts an
#   address from the reserved .2–.5 range and then hands out a pool lease
#   anyway.
#
#   10.0.90.12 is the point of the milestone — the single address any client
#   VLAN may reach.  Jellyfin's .10 and arr's .13 are reachable from nowhere
#   else; see BACKEND BYPASS.
#
#   The RESOLVER is declared here (Technitium 10.0.5.3) because a
#   DHCP-supplied resolver that quietly changes does not fail loudly.  The ACME
#   resolvers are deliberately NOT Technitium — see SPLIT HORIZON.
#
# ── TWO ENTRYPOINTS, AND WHY THAT IS THE WHOLE SECURITY ARGUMENT ─────────────
#
#     websecure  :443 on 10.0.90.12   LAN only.  Every pre-M18 router names
#                                     this and only this.
#     wan        :8443 on 10.0.90.12  the UDM-Pro's DNAT target, and nothing
#                                     else.
#
#   A router is internet-reachable if and only if it names `wan`.  So creating
#   a route does NOT expose it: exposure is one greppable entry in `wanExposed`
#   below.  This reproduces the tunnel's fail-closed-by-construction property,
#   which a plain WAN :443 → `websecure` forward would have destroyed — every
#   router would become reachable, gated on middleware correctness alone, and a
#   middleware one edit from wrong fails OPEN.
#
#   MEASURED, scratch Traefik 3.7.10, 2026-09-03 — the milestone rests on this
#   entirely, so it was tested before the config was written:
#
#     - a `websecure`-only router requested on `wan` is UNMATCHED: 404, no
#       backend contact.  Control: the same request for a router that DOES name
#       `wan` returned 502 from the absent backend, which proves routing
#       happens at all and the 404 is a real miss;
#     - unknown SNI and no-SNI on `wan` also 404;
#     - the TLS handshake COMPLETES first, with `CN=TRAEFIK DEFAULT CERT`.  So
#       a scanner of the public IP learns a Traefik is here: an existence
#       disclosure, not an exposure.  This is the one place this is weaker than
#       the tunnel;
#     - the certificate store is GLOBAL and entrypoint-independent — a cert
#       attached to no entrypoint was served on both, selected by SNI alone.
#       That is why `wan` below carries NO certResolver: a second resolver
#       request for the same main+sans risks duplicate issuance against Let's
#       Encrypt's 5-per-week limit, and the failure mode of omitting it is loud
#       and free (a browser warning naming TRAEFIK DEFAULT CERT).
#
#   THE FAIL-OPEN PATH, DEFENDED IN CODE.  A router omitting `entryPoints` is
#   instantiated on EVERY entrypoint — measured on the same instance, one
#   appeared as both `websecure-forgot-entrypoints@file` and
#   `wan-forgot-entrypoints@file` and proxied on `wan`.  The split alone is
#   therefore not fail-closed; `withWan` below THROWS AT EVALUATION if a router
#   omits `entryPoints`, or if the set naming `wan` is anything but what
#   `wanExposed` generates.  Forgetting is a build error.
#
#   DNS IS THE SECOND, INDEPENDENT GATE.  Every other name exists only inside
#   Technitium, so from outside they NXDOMAIN.  Neither gate is sufficient
#   alone: DNS does not gate a request to the bare public IP.
#
#   `wanExposed` is authoritative and the registrar must agree with it by hand
#   — nothing makes them agree automatically, which is the point of two
#   independent gates.  A NAME IN `wanExposed` WITH NO PUBLIC A RECORD IS
#   INERT: that is how audiobookshelf stayed unreachable for a day after a
#   correct deploy.  If an exposed service is unreachable from outside,
#   `dig +short <name>.goclan.org @1.1.1.1` is the FIRST command.
#
#   "DNS-only" IS LOAD-BEARING: these records must not be Cloudflare-proxied.
#   A proxied record makes every request arrive from a Cloudflare address, and
#   CrowdSec — which reads Traefik's access log and bans at the packet layer —
#   would see one source for the whole internet.  Its bans would be useless at
#   best and self-inflicted outages at worst.
#
#   NO AAAA RECORDS, EVER, while SN2 holds.
#
# ── IPv4-ONLY BY CONSTRUCTION (standing note SN2) ────────────────────────────
#
#   The hazard: if the UDM-Pro ever permits inbound v6 and this container ever
#   acquires a global address, a v6 listener bypasses the DNAT and therefore
#   the `wan` entrypoint — and the firewall bouncer sets
#   `nftables.ipv6.enabled = false`, so there is no `ip6 crowdsec` table.  Over
#   v6 the routers would be reachable AND unbannable at once.
#
#   THE BIND IS NOT THE DEFENCE.  Every entryPoint is written `0.0.0.0:`
#   rather than `:` and it makes no difference: Go treats `0.0.0.0` as
#   unspecified and opens AF_INET6 with IPV6_V6ONLY=0 for any wildcard listen.
#   Measured on the deployed config 2026-09-07 — all four entryPoints plus
#   CrowdSec's metrics port were accepting v6 on link-local.  `disable_ipv6`
#   does not help either: the socket family is available whenever the module is
#   loaded, regardless of addressing.
#
#   What actually holds the line, in the order it is relied on:
#
#     1. NO IPv6 ADDRESS EXISTS IN THIS NETNS — `LinkLocalAddressing = "no"`.
#        The sockets stay dual-stack; they have nothing to be reached on.
#        THE PROOF IS `ip -6 addr show dev eth0` RETURNING NOTHING — not
#        `ss -f inet6`, and not a bare `ip -6 addr show`, because `lo` keeps
#        `::1/128 scope host` and is supposed to.
#     2. No v6 forward on the UDM-Pro.  Outside Nix, an explicit "do not" in
#        M18's manual steps, NOT audited.
#     3. No GUA anywhere on VLAN 90.  Measured 2026-08-25 and 2026-09-03:
#        link-local only, no v6 default route, `accept_ra = 0` on br0.
#
#   (3) is a state, not a defence, which is why M6 alerts on it
#   (`UnexpectedIPv6GlobalAddress`) — that alert is the tripwire for (1) and
#   (2) being all that is left.
#
# ── TLS: ACME DNS-01, wildcard, split horizon ────────────────────────────────
#
#   One wildcard for *.goclan.org over DNS-01, specifically so that no inbound
#   port is needed to prove domain control.  HTTP-01 never runs.
#
#   THEREFORE :80 IS NOT FORWARDED FROM THE WAN, and "open 80 for Let's
#   Encrypt" is the single most likely wrong edit to the UDM-Pro.  The `web`
#   entryPoint exists only to 308 a bare hostname typed on the LAN.
#
#   SPLIT HORIZON.  The CERTIFICATE is public — every name in it hits the
#   Certificate Transparency logs at issuance, so `*.goclan.org` is
#   world-readable forever.  The SERVICES are not: jellyfin.goclan.org and the
#   arr names exist only in Technitium, and Cloudflare's zone holds nothing for
#   them but the transient _acme-challenge TXT.  CT discloses that a wildcard
#   exists — not one service name, and not an address.
#
#   THE ACME RESOLVERS ARE PUBLIC ONES, AND THAT IS LOAD-BEARING.  lego
#   verifies its own TXT propagated before asking Let's Encrypt to validate.
#   Through this container's normal resolver that check asks Technitium, which
#   is authoritative for goclan.org inside the LAN and knows nothing about
#   _acme-challenge — an authoritative NXDOMAIN, forever.  The failure is a
#   renewal that hangs at "waiting for DNS record propagation", i.e. a
#   certificate that expires with the proxy still running.  1.1.1.1 and 9.9.9.9
#   ask the PUBLIC view, which is the view Let's Encrypt uses.
#
#   THE STORE IS ON zdata — /srv/state/traefik, because zroot rolls back
#   (invariant #7) and acme.json cannot be regenerated cheaply against a
#   5-per-week duplicate limit.  Traefik creates it 0600; the directory is 0700
#   uid 3005.  The Cloudflare token is a prompted clan var — see the generator
#   at the bottom and the staging oneshot.
#
# ── BACKEND BYPASS HARDENING: backend-side source restriction ────────────────
#
#   ONE mechanism, (a): each backend's own firewall, in its own netns, accepts
#   its web port ONLY from 10.0.90.12.  Those rules live beside the ports they
#   restrict, in containers/jellyfin.nix and containers/arr/.
#
#   WHY NOT (b), a UDM-Pro intra-zone ZBF rule — not a preference, (b) CANNOT
#   do the job: .10, .11, .12 and .13 are ports on the same VLAN on the same
#   bridge, so traffic between them is switched at layer 2 and the frames never
#   reach the UDM-Pro.  containers/arr/ relies on that property in the other
#   direction.  A gateway cannot filter traffic it never sees.
#   DO NOT ADD (b) AS WELL: two sources of truth for one property is how you
#   get a rule nobody dares delete because nobody can prove what it does.
#
#   The adjacency is real, not theoretical.  10.0.90.11 is the qBittorrent
#   microvm — the one workload on ernst that talks to the open internet on its
#   own behalf — one L2 hop from Sonarr's, Radarr's and Prowlarr's web UIs.
#   Source-restricting those ports is the largest thing this buys beyond TLS.
#
#   WHAT (a) DOES NOT COVER:
#
#     - code execution IN THIS CONTAINER.  Traefik is inside the allow-list by
#       construction.  This is the cost of collapsing every rule to one address;
#     - the backends' OUTBOUND reach — that is invariant #1's tiering;
#     - spoofed sources.  br0 does no source validation, so a VLAN 90 host can
#       forge .12.  It gets no replies, so this blocks exploitation-by-response
#       but not a blind one-shot write to an unauthenticated API;
#     - the host itself, which is on VLAN 50 and reaches VLAN 90 through the
#       UDM-Pro — the one path (b) would have covered.
#
#   DEBUGGING CONSEQUENCE: `curl http://10.0.90.10:8096` from a laptop or from
#   ernst FAILS, and that is correct.  Reach a backend with
#   `nixos-container run jellyfin -- curl -sS localhost:8096/health` instead —
#   `lo` is always trusted.
#
# ── JELLYFIN KEEPS NATIVE AUTH, FOREVER ──────────────────────────────────────
#
#   NEVER put Authelia, or any forward-auth middleware, in front of the
#   Jellyfin route.  TV apps, the mobile clients, Chromecast senders and every
#   DLNA-ish device authenticate with Jellyfin's own token API and cannot
#   perform an interactive OIDC redirect; forward-auth turns the first request
#   into a 302 to a page the client has no browser to render, so the app fails
#   with an opaque network error.
#
#   The arr routes are the opposite case and are what forward-auth exists for.
#   The distinction is NOT "admin versus household" — it is "can the client
#   render a login page and follow a 302".
#
# ── Storage, and the second occupant ─────────────────────────────────────────
#
#   /srv/state/traefik (zdata/state) → /var/lib/traefik.  Nothing else
#   persists; both configs are generated into the store on every deploy.
#
#   containers/crowdsec.nix puts the CrowdSec agent, its local API and the
#   firewall bouncer in THIS netns — the only place that sees the pre-DNAT
#   source of a WAN request — with its decisions database bound separately from
#   /srv/state/crowdsec.  That file CO-DEFINES `containers.traefik.config`:
#   read its header before assuming this file is the whole of what runs here.
{
  config,
  lib,
  pkgs,
  ...
}: let
  ############################################################################
  # Identity, peers and ports — ./traefik/peers.nix
  #
  # Fifty-eight pure-data bindings (MAC, uid/gid, baseDomain, acmeEmail, and
  # every backend's address and port) used to sit here, and they were a third
  # of this file's `let`.  They are data, so they moved to a plain imported
  # attrset; the names are inherited rather than reached through a prefix so
  # that every reference in ./traefik/{static,dynamic}.nix and in the body
  # below stays exactly as it was.
  ############################################################################
  peers = import ./traefik/peers.nix;
  inherit
    (peers)
    traefikMac
    traefikUid
    traefikGid
    baseDomain
    acmeEmail
    jellyfinAddr
    arrAddr
    monitoringAddr
    autheliaAddr
    jellyfinPort
    prowlarrPort
    sonarrPort
    radarrPort
    grafanaPort
    autheliaPort
    bazarrPort
    cleanuparrPort
    mediathekarrPort
    jellyseerrPort
    homepagePort
    tvheadendAddr
    tvheadendPort
    tubesyncAddr
    tubesyncPort
    lidarrPort
    kapowarrPort
    questarrPort
    audiobookshelfPort
    binderyPort
    komgaPort
    navidromePort
    storytellerAddr
    storytellerPort
    rommAddr
    rommPort
    openWebuiAddr
    openWebuiPort
    immichAddr
    immichPort
    nextcloudAddr
    nextcloudPort
    homeassistantAddr
    homeassistantPort
    minifluxAddr
    minifluxPort
    mailAddr
    mtaStsPort
    karakeepAddr
    karakeepPort
    massAddr
    massPort
    paperlessAddr
    paperlessPort
    cwaAddr
    cwaPort
    slskdAddr
    slskdPort
    metricsPort
    ;
  ############################################################################
  # ── THE INGRESS POLICY, AND THE GUARD THAT ENFORCES IT ────────────────────
  #
  # `appApiHosts`, `protectedHosts`, `householdHosts` and `portalHost` are
  # defined ONCE in ./ingress-policy.nix and consumed by both this file and
  # containers/authelia.nix.  Read that file before changing a middleware on
  # any router below — it carries the whole argument for which names may be
  # answered by the application instead of by Authelia.
  ############################################################################
  ingressPolicy = import ./ingress-policy.nix {inherit baseDomain;};

  ############################################################################
  # ── THE `wan` ENTRYPOINT AND ITS GUARD — ./traefik/wan.nix ────────────────
  #
  # `wanEntryPoint`, `wanPort`, `wanExposed`, `wanLoginPaths`, `hostOfRule` and
  # `withWan` were seven hundred lines of this file's `let`.  They moved
  # together because they are one mechanism: the list, the paths it needs, and
  # the evaluation-time guard that makes forgetting an `entryPoints` line a
  # build error rather than a silent exposure.
  ############################################################################
  wan = import ./traefik/wan.nix {inherit lib ingressPolicy baseDomain;};
  inherit (wan) wanEntryPoint wanPort wanExposed wanLoginPaths withWan;
  ############################################################################
  # Secrets staging.
  ############################################################################

  # The Cloudflare token, staged out of sops into a host tmpfs directory and
  # bound read-only into the container at the SAME path.
  #
  # NOT a bind of /run/secrets itself: that path is a symlink to a
  # per-generation directory which is REPLACED on every deploy, so an nspawn
  # bind established at container start would keep exposing a deleted
  # generation until the container is restarted.  microvms/wg-qbittorrent.nix
  # hit this first and its header explains it at length.  A directory we own
  # has a stable identity and is rewritten in place.
  secretsDir = "/run/traefik-secrets";
  envFile = "${secretsDir}/cloudflare.env";

  gen = config.clan.core.vars.generators.traefik-acme;

  # The module's default dataDir.  Named here because the ACME storage path in
  # the static config has to agree with the bind mount, and one binding is
  # cheaper to keep in step than two string literals.
  dataDir = "/var/lib/traefik";
in {
  ##############################################################################
  # Host-side wiring.
  ##############################################################################

  # Stage the Cloudflare token where the container can see it.
  #
  # 0400 root:root.  systemd reads EnvironmentFile= as PID 1, before it drops
  # to User=traefik, so the traefik uid never needs to read this file and must
  # not be able to.  That is the whole difference from the wg-qbittorrent
  # staging unit, whose WebUI hash HAD to be group-readable because the process
  # that consumes it runs unprivileged — and which shipped broken once because
  # the directory was not group-traversable.  No such trap here: nothing but
  # PID 1 opens it.
  #
  # GENERATE BEFORE YOU DEPLOY.  clan-core cannot know a sops secret's path
  # until the secret exists; until then `files.<n>.path` evaluates to the
  # literal "/no-such-path" and THAT is what gets baked into the script below.
  # A deploy that runs before `clan vars generate ernst` produces a system
  # whose staging unit can never succeed however often it is restarted — it has
  # to be rebuilt.  The failure is at least loud and fail-closed: this unit
  # fails, `container@traefik` never starts, and there is no proxy rather than
  # a proxy with no certificate.
  #
  # ROTATING THE TOKEN needs a restart, not just a deploy.  If this unit's text
  # is unchanged, systemd will not re-run it when the underlying sops file
  # changes, so the staged copy stays stale.  After `clan vars generate ernst`:
  #     systemctl restart traefik-secrets container@traefik
  systemd.services.traefik-secrets = {
    description = "Stage the Cloudflare ACME token for container@traefik";
    after = ["local-fs.target"];
    before = ["container@traefik.service"];
    requiredBy = ["container@traefik.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root ${secretsDir}
      ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
        ${gen.files."cloudflare.env".path} ${envFile}
    '';
  };

  # There is deliberately NO `networking.firewall.allowedTCPPorts` on the HOST.
  # 443 is opened inside the container's own netns; on the host it is not a
  # port at all.  Reachability from the consumer VLANs is the UDM-Pro's job —
  # and after this milestone it is ONE rule per zone, pointing at 10.0.90.12,
  # which is the entire reduction M5 exists to deliver.
  #
  # The host-side veth network and the VLAN-race backstop are generated by
  # modules/containers/nspawn.nix, whose header owns both arguments.
  # `bridge vlan show dev vb-traefik` remains the check — do not trust silence
  # from either mechanism.

  ##############################################################################
  # Vars generator: the Cloudflare DNS-01 credential.
  #
  # A SCOPED API TOKEN, not the Global API Key.  Both work with lego's
  # cloudflare provider, and the difference is the blast radius of this
  # container being compromised:
  #
  #   Global API Key  → full control of every zone and every setting on the
  #                     Cloudflare ACCOUNT, and it cannot be rotated without
  #                     breaking everything else that uses it.
  #   Scoped token    → Zone:DNS:Edit on goclan.org and nothing else, revocable
  #                     on its own.
  #
  # The token needs exactly two permissions, both on the goclan.org zone:
  #     Zone / DNS  / Edit
  #     Zone / Zone / Read
  # Zone:Read is not optional — lego looks the zone id up by name before it can
  # write the challenge record, and a token with only DNS:Edit fails at that
  # lookup with an error that names neither permission.
  #
  # The file is emitted in KEY=value form rather than as a bare token because
  # services.traefik consumes it through systemd's EnvironmentFile=.
  ##############################################################################
  clan.core.vars.generators.traefik-acme = {
    files."cloudflare.env".secret = true;

    prompts."cloudflare-dns-api-token" = {
      description = "Cloudflare API token, scoped Zone:DNS:Edit + Zone:Zone:Read on ${baseDomain}";
      type = "hidden";
    };

    runtimeInputs = [pkgs.coreutils pkgs.gnugrep];

    script = ''
      set -euo pipefail

      token=$(tr -d '[:space:]' < "$prompts/cloudflare-dns-api-token")

      # Validate before writing.  Every one of these fails LATE otherwise — the
      # container starts, the routes serve, and the only symptom is that no
      # certificate ever appears and the browser shows Traefik's self-signed
      # default.  A human is watching exactly once, at prompt time.
      fail=0
      err() { echo "  ✗ $*" >&2; fail=1; }

      if [ -z "$token" ]; then
        err "empty token"
      fi

      # A Global API Key is 37 lowercase hex characters.  A scoped token is 40
      # characters of [A-Za-z0-9_-].  Catching the former is worth a rule of its
      # own: it AUTHENTICATES FINE, so the mistake is invisible at every point
      # where it could be caught later — the certificate issues, everything
      # works, and the account is one container compromise from being lost.
      if printf '%s' "$token" | grep -qE '^[0-9a-f]{37}$'; then
        err "that is a Global API Key (37 hex chars), not a scoped token."
        err "  Create one at: Cloudflare → My Profile → API Tokens → Create Token"
        err "  Permissions:   Zone/DNS/Edit + Zone/Zone/Read, on ${baseDomain}"
      elif ! printf '%s' "$token" | grep -qE '^[A-Za-z0-9_-]{30,}$'; then
        err "does not look like a Cloudflare API token (expected 40 chars of [A-Za-z0-9_-])"
      fi

      [ "$fail" -eq 0 ] || exit 1

      # The consumer is systemd's EnvironmentFile=, which wants KEY=value.
      # No quoting: systemd would keep the quotes as part of the value.
      printf 'CF_DNS_API_TOKEN=%s\n' "$token" > "$out/cloudflare.env"
    '';
  };

  ##############################################################################
  # The container itself.
  ##############################################################################

  ##############################################################################
  # The container.
  ##############################################################################
  #
  # modules/containers/nspawn.nix generates the dirs unit, the host-side veth
  # network, the VLAN backstop, the container preamble and the in-container
  # networking. It does NOT generate this container's firewall — see
  # `manageFirewall` below.
  #
  # `traefik-secrets` STAYS HAND-WRITTEN: it installs the Cloudflare token as
  # a whole file rather than composing an env file out of keys.
  #
  # containers/crowdsec.nix CO-DEFINES this container, adding its own daemon
  # inside Traefik's netns — the only place that sees the pre-DNAT source of a
  # WAN request. `containers.<n>.config` merges like any other option, and
  # `clanarchy.containers.<n>.config` is passed through to it unchanged, so
  # that arrangement is unaffected by this move.
  clanarchy.containers.traefik = {
    enable = true;
    mac = traefikMac;

    # NO uid/gid PIN: the module allocates traefik dynamically and the
    # in-container block handles it — see its own note.

    stateVersion = "26.05";

    # ── THE FIREWALL IS THIS CONTAINER'S OWN, AND THAT IS NOT A SHORTCUT ─────
    #
    # Two reasons, either of which is sufficient. First, "which peers" is the
    # wrong question for the ingress: 80, 443 and the WAN port answer the
    # whole internet, which is the entire point of the machine. Second, this
    # is the one container here running `networking.nftables`, where the
    # `extraCommands` the module emits is declared but never consumed — no
    # rule, no warning, no firewall. Its rules use `extraInputRules`, below.
    manageFirewall = false;

    # AN ORDERED UNIT RATHER THAN A tmpfiles RULE: bound into the container,
    # so a tmpfiles rule for it races the container's own start. The guard
    # matters more here than anywhere — acme.json on a filesystem that rolls
    # back means re-issuing every certificate on every boot, and Let's
    # Encrypt rate-limits that.
    #
    # NUMERIC ids on purpose: `traefik` is a container user and the host has
    # no matching passwd entry.
    stateDirs = [
      {
        path = "/srv/state/traefik";
        owner = traefikUid;
        group = traefikGid;
      }
    ];

    bindMounts = {
      # The certificate store, at the module's own default dataDir so
      # services.traefik needs no path override.
      "${dataDir}" = {
        hostPath = "/srv/state/traefik";
        isReadOnly = false;
      };
      # The staged Cloudflare token, read-only, at the identical path.
      "${secretsDir}" = {
        hostPath = secretsDir;
        isReadOnly = true;
      };
    };

    config = {
      config,
      pkgs,
      lib,
      ...
    }: {
      # Matches the host.  Certificate expiry, renewal attempts and every
      # access-log line are rendered in local time, and a container that
      # silently defaults to UTC makes "when did the cert actually renew" a
      # two-hour question.  Same call as containers/arr/.
      time.timeZone = "Europe/Berlin";

      ##########################################################################
      # Networking.  The container owns its netns, so it owns all of this.
      ##########################################################################

      # services.resolved asserts !networking.useHostResolvConf, and with a
      # private netns the host's resolv.conf is a stale snapshot of someone
      # else's resolver anyway.  virtualisation/container-config.nix sets it
      # `mkDefault true`, so a plain `false` wins without mkForce.

      ##########################################################################
      # THE FIREWALL IS nftables HERE, AND M18 IS WHY — argue before reverting.
      #
      # Every other container in this fleet uses the iptables firewall with
      # `extraCommands`.  This one moved, for one reason: the CrowdSec firewall
      # bouncer (machines/ernst/containers/crowdsec.nix) has to enforce bans in
      # THIS netns, and the two backends give materially different guarantees.
      #
      #   iptables mode.  The bouncer inserts `-I INPUT … -j DROP` above the
      #     `-j nixos-fw` jump.  A firewall RELOAD re-inserts nixos-fw at the
      #     top — and `PartOf=` does not propagate reload, only restart — so
      #     after a reload nixos-fw ACCEPTs :443 before the drop is ever
      #     reached, and every ban is silently inert.  A ban that is not
      #     observed in the ruleset is not a ban (SN3), and this is the version
      #     of that failure that leaves no trace at all.
      #   nftables mode.  The drop lives in its OWN base chain in its OWN
      #     table.  Both chains are traversed at the input hook and only `drop`
      #     is terminal, so nixos-fw accepting :443 does not prevent the drop.
      #     Ordering stops being a property anyone has to get right.
      #
      # It also makes the drop rule DECLARATIVE: with the bouncer in nftables
      # mode the NixOS module emits `networking.nftables.tables.crowdsec` — the
      # set and the `ip saddr @crowdsec-blacklists drop` chain are in the Nix
      # config, greppable, and re-created by nftables.service, while the
      # bouncer only manages set membership.  Measured in a throwaway VM on
      # 2026-09-03 before any of this was written; the transcript and the four
      # upstream defects it found are in crowdsec.nix's header.
      #
      # THE COST, stated: `networking.firewall.extraCommands` is REJECTED under
      # nftables, so the M6 metrics rule below had to move to
      # `extraInputRules`.  The comment that used to sit there said
      # extraInputRules "would produce no rule and no warning" — true then,
      # false now, and this is the edit that makes it false.
      ##########################################################################
      networking.nftables.enable = true;

      # 443 is the service.  80 exists ONLY to redirect to it (see the
      # entryPoint below) and is opened for that reason alone — a household
      # that types a bare hostname gets a redirect instead of a connection
      # refused, and nothing is ever served over it.  If you want to remove the
      # redirect, remove BOTH this port and the entryPoint; leaving the port
      # open with no listener is worse than either.
      #
      # 8443 IS THE WAN ENTRYPOINT and is the only listener the internet can
      # reach — see TWO ENTRYPOINTS in the file header.  It is open to the
      # whole Services VLAN here rather than to the gateway alone, deliberately
      # and with the reason written down: the UDM-Pro DNATs to this address
      # from the WAN, so the source it arrives from is whatever external client
      # sent it and there is no stable inside source to filter on.  What gates
      # this port is the ROUTER SET, not an address list.
      #
      # 80 IS NOT FORWARDED FROM THE WAN.  ACME is DNS-01, so HTTP-01 never
      # runs — see the TLS block in the header, which exists so nobody opens it
      # "for Let's Encrypt".
      #
      # No 8080: the Traefik dashboard/API is not enabled.  See the static
      # config below.
      #
      # 8082 (metrics) is NOT in this list on purpose — it is opened below for
      # one source address only.  Everything on VLAN 90 could otherwise read
      # every route name, backend address and TLS setting in the house off an
      # unauthenticated endpoint, which is most of what the dashboard was
      # switched off to avoid.
      networking.firewall.allowedTCPPorts = [80 443 wanPort];

      # M6: the metrics endpoint, source-restricted to the monitoring
      # container.  Same mechanism and the same reasoning as the backend
      # hardening this file imposes on jellyfin and the arr — see BACKEND
      # BYPASS HARDENING above — just pointing the other way: there, this
      # container is the permitted source; here, it is the protected one.
      #
      # `extraInputRules` now that the firewall is nftables — see the block
      # above.  It lands in nixos-fw's input chain ahead of the terminal
      # refuse, which is the same placement the old iptables append had.
      networking.firewall.extraInputRules = ''
        ip saddr ${monitoringAddr} tcp dport ${toString metricsPort} accept
      '';

      # SN2's enforcement is NOT here.  It is `LinkLocalAddressing = "no"` on
      # the 10-eth0 network unit below — see the comment there.
      #
      # THERE WAS A `boot.kernel.sysctl` disable_ipv6 BLOCK IN THIS SPOT AND IT
      # IS DELIBERATELY GONE: two attempts, both deployed, both measured, both
      # dead (`all` alone, then `all`+`default`+`eth0` — eth0 kept
      # fe80::ff:fe90:4/64 either way).  Two independent reasons, each fatal
      # alone: systemd-sysctl runs before eth0 exists in this netns, so the
      # per-interface key is silently skipped; and networkd writes
      # `disable_ipv6 = 0` on every link it configures.  networkd owns the link.
      #
      # THE SOCKETS ARE DUAL-STACK AND STAY DUAL-STACK whatever is done here —
      # Go returns AF_INET6 with IPV6_V6ONLY=0 for any wildcard listen, so the
      # address written in an entryPoint makes no difference.  The mechanism is
      # that NO IPv6 ADDRESS EXISTS IN THIS NETNS: the sockets have nothing to
      # be reached on, and no delegated prefix can be accepted.
      #
      # THE PROOF, EXACTLY, because two different wrong commands have already
      # been written down as one:
      #
      #   ip -6 addr show dev eth0   ->  nothing        <- THIS is the check
      #   ip -6 route show           ->  nothing        <- and this
      #   ip -6 addr show            ->  ::1/128 on lo  <- EXPECTED, not a failure
      #   ss -ltnH -f inet6          ->  five listeners <- EXPECTED, not a failure
      #
      # The bare `ip -6 addr show` form was accurate only while the deleted
      # sysctls existed, because `all = 1` covered `lo` and took `::1` with it.
      # Loopback is unreachable from outside this netns; `::1` coming back is
      # correct.

      ##########################################################################
      # Users.  Numeric ids are the interface across the nspawn boundary.
      ##########################################################################

      # The upstream module declares users.users.traefik without a uid (it lets
      # NixOS allocate one dynamically from the system range) and
      # users.groups.traefik without a gid.  Both are plain definitions with no
      # uid/gid attribute, so adding one here is a MERGE and needs no mkForce —
      # unlike containers/arr/, where the servarr modules DO set uid from
      # config.ids.uids.* and the override has to fight them.
      #
      # isSystemUser is already true upstream and stays true; it is restated
      # because NixOS infers "effectively a system user" from uid < 1000, and
      # 3005 is not, so the inference stops working the moment the uid is
      # pinned.  containers/arr/ hit exactly this and the error names
      # neither the uid nor the cause.
      users.users.traefik = {
        isSystemUser = true;
        uid = traefikUid;
      };
      users.groups.traefik = {gid = traefikGid;};

      ##########################################################################
      # Traefik.
      ##########################################################################
      services.traefik = {
        enable = true;

        # dataDir left at its default — /var/lib/traefik is the bind mount.
        environmentFiles = [envFile];

        ########################################################################
        # STATIC configuration — entryPoints, the ACME resolver, logging.
        # Changing anything here needs a Traefik restart; the dynamic half
        # below is re-read live.
        #
        # NOTE ON envsubst: because environmentFiles is non-empty, the module
        # renders this file through envsubst at ExecStartPre, into
        # /run/traefik/config.toml.  Nothing below may contain a literal `$` —
        # it would be substituted (probably to the empty string) with no error.
        ########################################################################
        ########################################################################
        # STATIC configuration — entrypoints, the ACME resolver, metrics.
        # ./traefik/static.nix
        ########################################################################
        staticConfigOptions = import ./traefik/static.nix {
          inherit baseDomain acmeEmail metricsPort wanEntryPoint wanPort dataDir;
        };

        ########################################################################
        # DYNAMIC configuration — routers, services, middlewares.
        # ./traefik/dynamic.nix
        #
        # Called with the whole `peers` data set plus `withWan`; that file's
        # argument list names the fifty-two it actually reads, so its
        # dependencies are visible without opening it.
        ########################################################################
        dynamicConfigOptions = import ./traefik/dynamic.nix ({inherit withWan;} // peers);
      };

      # Additional hardening on top of the upstream module.
      #
      # Upstream already sets NoNewPrivileges, CapabilityBoundingSet =
      # cap_net_bind_service (the one capability a proxy binding :443 as an
      # unprivileged user actually needs), PrivateTmp, PrivateDevices,
      # ProtectHome, ProtectSystem = "full" and ReadWritePaths = [ dataDir ].
      # What is added here is the set it omits and that is SAFE INSIDE NSPAWN.
      #
      # THE OMISSIONS ARE THE INTERESTING PART, and they are not oversights.
      # containers/jellyfin.nix records that upstream deliberately disables
      # ProtectKernelTunables / ProtectKernelModules / ProtectControlGroups /
      # RestrictNamespaces / PrivateTmp under `!config.boot.isContainer`,
      # because they conflict with nspawn's own mount-namespace setup and
      # either error at activation or silently no-op.  The traefik module has
      # no such conditional — it is not container-aware — so setting them here
      # would be doing by hand exactly what the jellyfin module refuses to do
      # by machine.  They are left out for that reason, not because they were
      # not considered.
      #
      # PrivateUsers is omitted for a different reason: a user namespace and
      # AmbientCapabilities = cap_net_bind_service interact badly, and the
      # failure is a proxy that cannot bind 443 at all.
      #
      # REJECTED, with reasons:
      #   MemoryDenyWriteExecute = true
      #     Go's runtime does not need W|X pages, so this one would probably
      #     hold — but "probably" on the single service every other service is
      #     now behind, in a milestone that cannot be tested before deploying,
      #     is not a trade worth making.  Revisit with a measurement.
      #   IPAddressAllow / IPAddressDeny
      #     The allow-list would have to include Let's Encrypt, Cloudflare's
      #     API, two public resolvers and every client VLAN — i.e. most of the
      #     internet plus the LAN.  Inbound restriction is the container
      #     firewall's and the UDM-Pro's job.
      systemd.services.traefik.serviceConfig = {
        ProtectClock = true;
        ProtectHostname = true;
        ProtectProc = "invisible";
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = ["@system-service" "~@privileged" "~@debug" "~@mount"];
        UMask = "0077";
      };

      # `curl` and `dig` are the test plan's instruments: curl proves each
      # backend is reachable from HERE (and, from anywhere else, that it is
      # not), and dig is what checks the split-horizon answer differs from the
      # public one.  `openssl` reads the SANs off the issued certificate.
      environment.systemPackages = with pkgs; [curl dnsutils openssl];
      documentation.enable = false;
      documentation.nixos.enable = false;
    };
  };
}
