# machines/ernst/containers/traefik.nix
#
# Traefik v3, in a declarative systemd-nspawn NixOS container.  One reverse
# proxy on its own L2 identity, so every consumer VLAN collapses to a single
# permanent firewall rule pointing at THIS address instead of one rule per
# backend.  That reduction is the milestone; TLS is how it is made usable.
#
# Why nspawn: architecture invariant #1.  Traefik terminates TLS for trusted
# in-house services and never fetches attacker-supplied URLs on anyone's
# behalf, so it is a trusted-tier workload sharing the host kernel.  (The
# thing that DOES render hostile pages is FlareSolverr, and the argument for
# where it lives is in containers/arr.nix.)
#
# ── Networking: veth on br0, Services VLAN 90 ────────────────────────────────
#
#   Copied from containers/jellyfin.nix ("Networking — v2"), which is the
#   WORKING version of this pattern, and followed again by containers/arr.nix:
#   KeepMaster rather than Bridge=, the ExecStartPost that settles the VLAN
#   race, and the 20 s wait-online cap that stops a DHCP failure from
#   restart-looping the container.  Read jellyfin.nix's header for the full
#   rationale — including why this is a veth and not a macvlan or a tap — it is
#   not repeated here.
#
#   MAC 02:00:00:90:00:04 was RESERVED for this container by M2b, in the
#   allocation table in machines/ernst/networking.nix, against DHCP reservation
#   10.0.90.12.  M4 deliberately skipped to .13 so that .12 stayed free for it.
#
#   10.0.90.12 IS THE POINT OF THE MILESTONE.  It is the single address every
#   consumer-zone ZBF rule now targets, and the only address on VLAN 90 that
#   any client VLAN is permitted to reach.  Jellyfin's .10 and the arr's .13
#   stop being reachable from anywhere but here — see BACKEND BYPASS below.
#
#   Addressing is DHCP with a reservation on the UDM-Pro keyed on the pinned
#   MAC, NOT a static address in this file: the UDM-Pro owns the subnet and the
#   pool, and a second copy here diverges silently.  The reservation must be
#   INSIDE the DHCP pool (10.0.90.6–.254) — UniFi accepts an address from the
#   .2–.5 range the cutover runbook set aside and then hands out an ordinary
#   pool lease instead.  M2b lost a round to exactly that.
#
#   The RESOLVER is the opposite call and IS declared here (Technitium,
#   10.0.5.3), because a DHCP-supplied resolver that quietly changes does not
#   fail loudly.  Note the ACME resolvers below are deliberately NOT Technitium
#   — see SPLIT HORIZON.
#
# ── TLS: ACME DNS-01, wildcard, split horizon ────────────────────────────────
#
#   ONE wildcard certificate for *.goclan.org, issued over the DNS-01
#   challenge.  DNS-01 specifically so that NOTHING here has to be reachable
#   from the internet: the challenge is a TXT record lego writes and deletes at
#   Cloudflare, and no inbound port is ever opened.  There is no HTTP-01, no
#   port forward, and no WAN exposure of any kind.
#
#   SPLIT HORIZON — READ THIS BEFORE ASSUMING ANYTHING IS PUBLIC.
#
#     The CERTIFICATE is public.  Every name in it is published to the
#     Certificate Transparency logs the moment it is issued, so
#     "*.goclan.org" is world-readable and always will be.
#
#     The SERVICES are not.  jellyfin.goclan.org and the arr names exist ONLY
#     as records inside Technitium (10.0.5.3).  There are no public A or AAAA
#     records for them, and Cloudflare's zone holds nothing for these names but
#     the transient _acme-challenge TXT that lego adds and removes.
#
#     A public certificate is what makes people assume the service behind it is
#     reachable.  It is not.  The only thing CT discloses is that a wildcard
#     exists — not a single service name, and not an address.
#
#   THE ACME RESOLVERS ARE PUBLIC ONES, AND THAT IS LOAD-BEARING.  lego
#   verifies its own TXT record has propagated before telling Let's Encrypt to
#   validate.  If that check went through this container's normal resolver it
#   would ask Technitium — which is authoritative for the goclan.org names
#   inside the LAN and knows nothing about _acme-challenge — and the answer
#   would be an authoritative NXDOMAIN, forever.  The failure is a renewal that
#   hangs at "waiting for DNS record propagation" and then times out, i.e. a
#   certificate that expires with the proxy still running.  Pinning 1.1.1.1 and
#   9.9.9.9 makes the check ask the PUBLIC view, which is the view Let's
#   Encrypt will use.
#
#   THE STORE IS ON zdata.  /srv/state/traefik, bound to the module's default
#   dataDir, because zroot rolls back (invariant #7) and acme.json is the one
#   piece of state here that cannot be regenerated cheaply — Let's Encrypt
#   rate-limits duplicate certificates to 5 per week.  Traefik creates
#   acme.json 0600 itself; the directory is 0700 and owned by uid 3005.
#
#   THE CLOUDFLARE TOKEN is a clan var, prompted, never in the store and never
#   in this file.  See the generator at the bottom, and the staging oneshot
#   that is the only reason the container can see it at all.
#
# ── BACKEND BYPASS HARDENING: backend-side source restriction ────────────────
#
#   ONE mechanism, as the milestone requires, and it is (a): each backend's own
#   firewall, in its own netns, accepts its web port ONLY from 10.0.90.12.  The
#   rules live in containers/jellyfin.nix and containers/arr.nix beside the
#   ports they restrict.  The rejected alternative was (b), a UDM-Pro intra-zone
#   ZBF rule.
#
#   WHY (a) AND NOT (b) — this is not a preference, (b) cannot do the job:
#
#     Jellyfin (.10), the arr (.13), qBittorrent's guest (.11) and this
#     container (.12) are all ports on the SAME VLAN on the SAME bridge.
#     Traffic between them is switched at layer 2 by br0 and the frames never
#     reach the UDM-Pro at all.  containers/arr.nix relies on exactly this
#     property in the other direction — it is why the arr needs no ZBF rule to
#     talk to the download client.  A gateway cannot filter traffic it never
#     sees, so an intra-zone rule would be a rule that looks like enforcement
#     and enforces nothing.
#
#     And the adjacency that matters is real, not theoretical.  10.0.90.11 is
#     the qBittorrent microvm: the one workload on ernst that talks to the open
#     internet on its own behalf, which is why invariant #1 gives it its own
#     kernel.  It sits one layer-2 hop from Sonarr's, Radarr's and Prowlarr's
#     web UIs.  Source-restricting those ports to this container is what stops
#     a compromised download client from driving the *arr APIs directly, and it
#     is the single largest thing this milestone buys beyond TLS.
#
#   WHAT (a) DOES NOT COVER, stated plainly:
#
#     - Anything that already has code execution IN THIS CONTAINER.  Traefik is
#       inside the allow-list by construction; source filtering cannot help.
#       This is the cost of collapsing every consumer rule to one address.
#     - The backends' OUTBOUND reach.  Nothing here constrains what Jellyfin or
#       the arr connect out to; that is invariant #1's tiering, not a firewall.
#     - Spoofed sources.  A host on VLAN 90 can forge 10.0.90.12 as its source
#       address; br0 does no source validation.  It would not get replies (they
#       route to the real .12), so this blocks exploitation-by-response but not
#       blind one-shot writes to an unauthenticated API.
#     - Anything on the host itself, which is on VLAN 50 and reaches VLAN 90
#       through the UDM-Pro — a path (b) WOULD have covered.
#
#   WHERE (b) WOULD HAVE BEEN BETTER: it is enforced by a device the containers
#   cannot reconfigure, so a regression in this repo could not silently undo it,
#   and it would cover the host-to-backend path above.  (a) was chosen anyway
#   because covering the intra-VLAN path is worth more than either, and because
#   a rule that lives in the repo deploys atomically with the routes it
#   protects.  DO NOT ADD (b) AS WELL — two sources of truth for one property
#   is how you get a rule nobody dares delete because nobody can prove what it
#   does.
#
#   DEBUGGING CONSEQUENCE, because it will surprise someone: after this
#   deploys, `curl http://10.0.90.10:8096` from your laptop or from ernst FAILS
#   and that is correct.  Reach a backend directly with
#   `nixos-container run jellyfin -- curl -sS localhost:8096/health` instead;
#   `lo` is always trusted by the NixOS firewall.
#
# ── JELLYFIN KEEPS NATIVE AUTH, FOREVER ──────────────────────────────────────
#
#   NEVER put Authelia — or any forward-auth middleware — in front of the
#   Jellyfin route.  This is written here so M7 does not undo it.
#
#   TV apps, the Android/iOS clients, Chromecast senders and every DLNA-ish
#   device authenticate with Jellyfin's own token API and cannot perform an
#   interactive OIDC redirect.  A forward-auth middleware turns the first
#   request into a 302 to a login page the client has no browser to render, so
#   the app fails with an opaque network error rather than a login prompt.
#   Jellyfin's own user database IS the auth boundary for this route, and it is
#   the right one: it is the only one the clients can speak.
#
#   The arr routes are the opposite case — browser-only, admin-facing — and
#   they carry the interim ipAllowList below precisely so M7 has something to
#   replace.
#
# ── Storage layout on this host (see machines/ernst/disko.nix) ───────────────
#
#   /srv/state/traefik    zdata/state   RW into the container at /var/lib/traefik
#     acme.json                         the certificate store, 0600, uid 3005
#
#   Nothing else persists.  Both configs are generated from this file into the
#   Nix store on every deploy, so the container's own root holds no state worth
#   keeping.
{ config, lib, pkgs, ... }:
let
  ############################################################################
  # Identity.
  ############################################################################

  # Guest-side MAC — 02:00:00:<vlan>:00:<seq>, RESERVED for this container by
  # M2b in the allocation table in machines/ernst/networking.nix.  This is the
  # address the UDM-Pro sees and the one the DHCP reservation keys on; never
  # the host-side vb-traefik.
  traefikMac = "02:00:00:90:00:04";
  vlanId     = 90;

  # Host side of the veth pair.  nspawn names it vb-<container> when
  # --network-bridge= is used — "vb-", not "ve-".
  vethName = "vb-traefik";

  # Numeric ids, continuing the 3000-range family that containers/arr.nix and
  # microvms/wg-qbittorrent.nix established.  nspawn passes uids and gids
  # through unmapped, so an id chosen in here is an id on zdata — and
  # /srv/state/traefik is on zdata.  Add a row to the table in
  # machines/ernst/networking.nix for any new one.
  #
  # NOT in group media, and it never should be.  A reverse proxy has no
  # business holding a handle to the library; it moves bytes between two
  # sockets.
  traefikUid = 3005;
  traefikGid = 3005;

  ############################################################################
  # Names and addresses.
  ############################################################################

  # The public zone, rented on Cloudflare.  ONE wildcard covers every service
  # name below, which is why adding a route later needs no certificate work at
  # all — only a Technitium record and a block in the dynamic config.
  baseDomain = "goclan.org";

  # ACME account contact.  Let's Encrypt uses it for expiry warnings, which are
  # the backstop for a renewal that silently stopped working; there is no
  # monitoring on this until M6.  Already public — it is the author address on
  # every commit in this repo.
  acmeEmail = "lutz0go@gmail.com";

  # Backends, by the addresses their DHCP reservations pin.  These are PEER
  # addresses, and hard-coding them here is the deliberate opposite of the rule
  # each container follows for its OWN address.
  #
  # The reason the rule inverts: a container declaring its own address creates
  # a second source of truth that DIVERGES SILENTLY from the UDM-Pro's pool.  A
  # proxy naming a peer cannot diverge quietly — if a reservation moves, every
  # route to it returns 502 immediately and loudly.  Traefik has to learn the
  # address from somewhere, and there is no service discovery here to learn it
  # from.
  jellyfinAddr = "10.0.90.10";
  arrAddr      = "10.0.90.13";

  jellyfinPort = 8096;
  prowlarrPort = 9696;
  sonarrPort   = 8989;
  radarrPort   = 7878;

  # INTERIM ACCESS CONTROL for the arr routes — ledger row L5 in
  # docs/roadmap.md, to be REPLACED by Authelia forward-auth in M7.
  #
  # The management networks are the same two containers/arr.nix and
  # microvms/wg-qbittorrent.nix already use (`mgmtNets`), plus the travel VLAN:
  #   10.0.10.0/24   LAN / "Family"  (VLAN 1)
  #   10.0.50.0/24   Servers         (VLAN 50)
  #   10.0.70.0/24   Travel / wg     (VLAN 70)
  #
  # VLAN 70 is NOT on ernst's trunk and does not need to be — a wg-travel
  # client's traffic is routed to VLAN 90 by the UDM-Pro and arrives here with
  # its 10.0.70.x source intact.  Leaving it out is what would lock lgo out of
  # the arr from the road, which is the specific failure M7's notes warn about.
  #
  # This is an IP allow-list and NOT authentication.  It is here so the admin
  # UIs are not simply open the moment they are proxied, and it is marked
  # interim because it will be wrong for a household the moment anyone wants
  # access from a phone on the IoT VLAN.  DO NOT INVENT AN AUTH SCHEME HERE —
  # basic-auth credentials in a clan var would be a third credential store to
  # rotate and would still have to be torn out for M7.
  mgmtSourceRanges = [ "10.0.10.0/24" "10.0.50.0/24" "10.0.70.0/24" ];

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
  envFile    = "${secretsDir}/cloudflare.env";

  gen = config.clan.core.vars.generators.traefik-acme;

  # The module's default dataDir.  Named here because the ACME storage path in
  # the static config has to agree with the bind mount, and one binding is
  # cheaper to keep in step than two string literals.
  dataDir = "/var/lib/traefik";
in
{
  ##############################################################################
  # Host-side wiring.
  ##############################################################################

  # Certificate store on zdata.  0700 and owned by the service, exactly like
  # /srv/state/{jellyfin,sonarr,radarr,prowlarr}: nothing else has any business
  # reading a private key.
  #
  # NUMERIC ids on purpose — `traefik` is a container user and the host has no
  # matching passwd entry.  Same shape containers/arr.nix uses for uid 3002.
  systemd.tmpfiles.rules = [
    "d /srv/state/traefik 0700 ${toString traefikUid} ${toString traefikGid} -"
  ];

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
    after       = [ "local-fs.target" ];
    before      = [ "container@traefik.service" ];
    requiredBy  = [ "container@traefik.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root ${secretsDir}
      ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
        ${gen.files."cloudflare.env".path} ${envFile}
    '';
  };

  # Host side of the container's veth — a VLAN-90 port on br0.
  #
  # There is deliberately NO `networking.firewall.allowedTCPPorts` here.  443
  # is opened inside the container's own netns (below); on the host it is not a
  # port at all.  Reachability from the consumer VLANs is the UDM-Pro's job —
  # and after this milestone it is ONE rule per zone, pointing at 10.0.90.12,
  # which is the entire reduction M5 exists to deliver.
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
  systemd.network.networks."60-${vethName}" = {
    matchConfig.Name = vethName;
    networkConfig = {
      KeepMaster          = true;
      LinkLocalAddressing = "no";
      IPv6AcceptRA        = false;
    };
    bridgeVLANs = [ { VLAN = vlanId; PVID = vlanId; EgressUntagged = vlanId; } ];
    # A bridge port's terminal operational state is "enslaved"; it never
    # becomes routable, and waiting for that would hang boot.
    linkConfig.RequiredForOnline = "enslaved";
  };

  # Re-assert the VLAN membership after nspawn has created the veth.
  #
  # Same real race as vb-jellyfin and vb-arr: networkd applies [BridgeVLAN]
  # only once it observes the link's master, and nspawn sets that master out of
  # band from container@traefik.service.  With DefaultPVID = "none" on br0 a
  # miss is fail-CLOSED — no connectivity at all — rather than fail-open onto
  # VLAN 50, which is the right failure but still presents as "everything is
  # down" now that everything is behind this one container.
  #
  # `bridge vlan add` is idempotent, so this agrees with networkd rather than
  # competing with it.  The "-" prefix is deliberate: a backstop must not become
  # a new failure mode, so `bridge` exiting non-zero (link already gone during a
  # restart, say) must not fail the container and restart-loop it.
  #
  # `bridge vlan show dev vb-traefik` remains the check — do not trust silence
  # from either mechanism.
  systemd.services."container@traefik".serviceConfig.ExecStartPost = [
    "-${pkgs.iproute2}/bin/bridge vlan add dev ${vethName} vid ${toString vlanId} pvid untagged"
  ];

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
      type        = "hidden";
    };

    runtimeInputs = [ pkgs.coreutils pkgs.gnugrep ];

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
  containers.traefik = {
    autoStart = true;
    ephemeral = false;          # acme.json persists via the bind mount below

    # Own netns, own L2 identity.  See the file header for why this is a veth
    # on br0 and not a macvlan or a tap.
    privateNetwork  = true;
    hostBridge      = "br0";
    localMacAddress = traefikMac;

    bindMounts = {
      # The certificate store, on zdata.  Remapped to the module's upstream
      # default dataDir so services.traefik needs no path override — the same
      # trick containers/jellyfin.nix uses for /var/lib/jellyfin and
      # containers/arr.nix for /var/lib/{sonarr,radarr,prowlarr}.
      "${dataDir}" = {
        hostPath   = "/srv/state/traefik";
        isReadOnly = false;
      };

      # The staged Cloudflare token, read-only, at the identical path.  See the
      # staging unit above for why this is not a bind of /run/secrets.
      "${secretsDir}" = {
        hostPath   = secretsDir;
        isReadOnly = true;
      };
    };

    ############################################################################
    # NixOS config for the container's own root filesystem.
    ############################################################################
    config = { config, pkgs, lib, ... }: {
      system.stateVersion = "26.05";

      # Matches the host.  Certificate expiry, renewal attempts and every
      # access-log line are rendered in local time, and a container that
      # silently defaults to UTC makes "when did the cert actually renew" a
      # two-hour question.  Same call as containers/arr.nix.
      time.timeZone = "Europe/Berlin";

      ##########################################################################
      # Networking.  The container owns its netns, so it owns all of this.
      ##########################################################################

      # services.resolved asserts !networking.useHostResolvConf, and with a
      # private netns the host's resolv.conf is a stale snapshot of someone
      # else's resolver anyway.  virtualisation/container-config.nix sets it
      # `mkDefault true`, so a plain `false` wins without mkForce.
      networking.useHostResolvConf = false;

      networking.useNetworkd   = true;
      services.resolved.enable = true;

      # eth0 — renamed from host0 by container-init before stage 2 runs.
      #
      # ADDRESS: DHCP, reserved on the UDM-Pro against the pinned MAC.
      # RESOLVER: declared, not inherited.  UseDNS/UseDomains = false so a
      # future change to the Services network's DHCP options cannot silently
      # move this container off Technitium.  "~." is a ROUTING domain, so every
      # lookup goes to 10.0.5.3; "skynet.lan" is the bare-hostname suffix.
      #
      # This resolver is what the BACKEND connections and Let's Encrypt's API
      # hostname resolve through.  The ACME propagation check deliberately does
      # NOT use it — see SPLIT HORIZON in the file header.
      #
      # Check on ernst with:  nixos-container run traefik -- resolvectl status eth0
      systemd.network.networks."10-eth0" = {
        matchConfig.Name = "eth0";
        networkConfig = {
          DHCP         = "ipv4";
          DNS          = "10.0.5.3";
          Domains      = "~. skynet.lan";
          IPv6AcceptRA = false;
        };
        dhcpV4Config = {
          UseDNS     = false;
          UseDomains = false;
        };
        linkConfig.RequiredForOnline = "routable";
      };

      # 20 s, for the reason containers/jellyfin.nix explains at length:
      # container@traefik is Type=notify with TimeoutStartSec=1min, so a
      # wait-online that blocks for the stock 120 s turns a missing DHCP
      # reservation into a container the host kills and restart-loops, with no
      # reachable state to debug.  At 20 s the container always finishes booting
      # and leaves one obviously failed unit instead.
      systemd.network.wait-online.timeout = 20;

      # The container's own firewall, in its own netns.
      #
      # 443 is the service.  80 exists ONLY to redirect to it (see the
      # entryPoint below) and is opened for that reason alone — a household
      # that types a bare hostname gets a redirect instead of a connection
      # refused, and nothing is ever served over it.  If you want to remove the
      # redirect, remove BOTH this port and the entryPoint; leaving the port
      # open with no listener is worse than either.
      #
      # No 8080: the Traefik dashboard/API is not enabled.  See the static
      # config below.
      networking.firewall.allowedTCPPorts = [ 80 443 ];

      ##########################################################################
      # Users.  Numeric ids are the interface across the nspawn boundary.
      ##########################################################################

      # The upstream module declares users.users.traefik without a uid (it lets
      # NixOS allocate one dynamically from the system range) and
      # users.groups.traefik without a gid.  Both are plain definitions with no
      # uid/gid attribute, so adding one here is a MERGE and needs no mkForce —
      # unlike containers/arr.nix, where the servarr modules DO set uid from
      # config.ids.uids.* and the override has to fight them.
      #
      # isSystemUser is already true upstream and stays true; it is restated
      # because NixOS infers "effectively a system user" from uid < 1000, and
      # 3005 is not, so the inference stops working the moment the uid is
      # pinned.  containers/arr.nix hit exactly this and the error names
      # neither the uid nor the cause.
      users.users.traefik = {
        isSystemUser = true;
        uid          = traefikUid;
      };
      users.groups.traefik = { gid = traefikGid; };

      ##########################################################################
      # Traefik.
      ##########################################################################
      services.traefik = {
        enable = true;

        # dataDir left at its default — /var/lib/traefik is the bind mount.
        environmentFiles = [ envFile ];

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
        staticConfigOptions = {
          # Neither of these should reach the internet from a box whose whole
          # point is that it does not need to.
          global.checkNewVersion    = false;
          global.sendAnonymousUsage = false;

          # To the journal.  `journalctl -u traefik` inside the container is
          # where the ACME exchange and every routing decision are visible, and
          # it is the instrument the PR test plan uses.
          log.level     = "INFO";
          accessLog.format = "common";

          # THE API AND DASHBOARD ARE OFF, deliberately and by omission: there
          # is no `api` block here at all.  Enabling it would put an
          # unauthenticated read of every route, service and TLS setting behind
          # the one address every VLAN is now allowed to reach.  If it is ever
          # wanted, it belongs behind M7's forward-auth, not behind the
          # ipAllowList — an admin API is not a management-network problem.
          entryPoints = {
            # :80 does nothing but redirect.  `permanent = true` is a 308, so
            # clients and TV apps cache it and stop asking.
            web = {
              address = ":80";
              http.redirections.entryPoint = {
                to        = "websecure";
                scheme    = "https";
                permanent = true;
              };
            };

            websecure = {
              address = ":443";

              # THE WILDCARD IS REQUESTED HERE, ONCE, at the entryPoint — not
              # per router.  This is the difference between one certificate and
              # one certificate per hostname:
              #
              #   Without an explicit `domains` block, Traefik asks the resolver
              #   for a cert covering each router's Host() rule individually.
              #   That still works over DNS-01, but it is four certificates
              #   instead of one, four renewals to fail independently, and four
              #   entries against Let's Encrypt's 50-certs-per-domain-per-week
              #   limit.  It also puts every service NAME into the public CT
              #   logs, which is exactly the disclosure the wildcard avoids.
              #
              # main + sans covers the apex and everything one level below it.
              # A wildcard does NOT match multiple labels: a future
              # foo.bar.goclan.org would need its own entry.
              http.tls = {
                certResolver = "cloudflare";
                domains = [
                  {
                    main = baseDomain;
                    sans = [ "*.${baseDomain}" ];
                  }
                ];
              };
            };
          };

          certificatesResolvers.cloudflare.acme = {
            email   = acmeEmail;
            storage = "${dataDir}/acme.json";

            # STAGING, for when something here changes.  Let's Encrypt's
            # production endpoint allows 5 duplicate certificates per week; a
            # wrong provider config that retries can burn that in an afternoon
            # and leave the household without a working proxy for six days.
            # Uncomment to point at staging (its certs are untrusted — the
            # browser warning is expected and is the signal it worked), verify
            # issuance in the log, then re-comment AND delete acme.json before
            # switching back, because the two CAs share the one store:
            #
            #   caServer = "https://acme-staging-v02.api.letsencrypt.org/directory";

            dnsChallenge = {
              provider = "cloudflare";

              # PUBLIC resolvers, and this line is the difference between a
              # certificate that renews and one that does not.  See SPLIT
              # HORIZON in the file header: the default is the container's own
              # resolver, which is Technitium, which is authoritative for the
              # goclan.org names on this LAN and answers an authoritative
              # NXDOMAIN for _acme-challenge.  lego would then wait for a
              # propagation that, from where it is looking, can never happen.
              resolvers = [ "1.1.1.1:53" "9.9.9.9:53" ];
            };
          };
        };

        ########################################################################
        # DYNAMIC configuration — routers, services, middlewares.
        ########################################################################
        dynamicConfigOptions = {
          http.middlewares = {
            # INTERIM — ledger row L5 in docs/roadmap.md, replaced by Authelia
            # forward-auth in M7.  See mgmtSourceRanges above for what it
            # covers and why it is not authentication.
            #
            # Traefik's ipAllowList matches the TCP peer address by default and
            # IGNORES X-Forwarded-For.  That is the correct behaviour here and
            # it depends on this entryPoint NOT setting
            # forwardedHeaders.trustedIPs — nothing sits in front of this proxy,
            # so any XFF header on an inbound request was written by the client
            # and trusting it would let anyone assert a management source
            # address.  Do not add forwardedHeaders here.
            mgmt-only.ipAllowList.sourceRange = mgmtSourceRanges;
          };

          http.routers = {
            # ── Jellyfin: the household route ──────────────────────────────
            #
            # NO MIDDLEWARE, and never a forward-auth one.  See "JELLYFIN KEEPS
            # NATIVE AUTH, FOREVER" in the file header.
            jellyfin = {
              rule        = "Host(`jellyfin.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              service     = "jellyfin";
            };

            # ── The arr stack: admin routes, interim-restricted ────────────
            #
            # THREE HOSTNAMES, NOT THREE PATH PREFIXES.  containers/arr.nix
            # anticipated this ("M5 can route three paths to one address
            # perfectly well") and subdomains are the better of the two:
            # Sonarr, Radarr and Prowlarr all need a matching `UrlBase` set in
            # their own settings before they will work under a path prefix, and
            # a missing UrlBase presents as a UI that loads a blank page with
            # 404s on every asset.  Distinct hostnames need no UrlBase at all,
            # so there is nothing to keep in step between this file and three
            # web UIs.
            prowlarr = {
              rule        = "Host(`prowlarr.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              middlewares = [ "mgmt-only" ];
              service     = "prowlarr";
            };
            sonarr = {
              rule        = "Host(`sonarr.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              middlewares = [ "mgmt-only" ];
              service     = "sonarr";
            };
            radarr = {
              rule        = "Host(`radarr.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              middlewares = [ "mgmt-only" ];
              service     = "radarr";
            };
          };

          # Backends are plain HTTP over VLAN 90 — the hop from here to them is
          # a single layer-2 forward inside br0 on this host and never touches a
          # wire.  Terminating TLS again at each backend would mean four more
          # certificates for a link that cannot be observed without already
          # being on ernst.
          #
          # There is deliberately no `passHostHeader = false` anywhere: Traefik
          # forwards the original Host by default, which is what lets Jellyfin
          # generate correct absolute URLs.
          http.services = {
            jellyfin.loadBalancer.servers = [ { url = "http://${jellyfinAddr}:${toString jellyfinPort}/"; } ];
            prowlarr.loadBalancer.servers = [ { url = "http://${arrAddr}:${toString prowlarrPort}/"; } ];
            sonarr.loadBalancer.servers   = [ { url = "http://${arrAddr}:${toString sonarrPort}/"; } ];
            radarr.loadBalancer.servers   = [ { url = "http://${arrAddr}:${toString radarrPort}/"; } ];
          };
        };
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
        ProtectClock            = true;
        ProtectHostname         = true;
        ProtectProc             = "invisible";
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictRealtime        = true;
        RestrictSUIDSGID        = true;
        RemoveIPC               = true;
        LockPersonality         = true;
        SystemCallArchitectures = "native";
        SystemCallFilter        = [ "@system-service" "~@privileged" "~@debug" "~@mount" ];
        UMask                   = "0077";
      };

      # `curl` and `dig` are the test plan's instruments: curl proves each
      # backend is reachable from HERE (and, from anywhere else, that it is
      # not), and dig is what checks the split-horizon answer differs from the
      # public one.  `openssl` reads the SANs off the issued certificate.
      environment.systemPackages = with pkgs; [ curl dnsutils openssl ];
      documentation.enable       = false;
      documentation.nixos.enable = false;
    };
  };
}
