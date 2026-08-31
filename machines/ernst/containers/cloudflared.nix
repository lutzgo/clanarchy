# machines/ernst/containers/cloudflared.nix
#
# Cloudflare Tunnel (cloudflared), in a declarative systemd-nspawn NixOS
# container.  M16: the first — and only — WAN ingress path in this fleet.
#
# THE TUNNEL DECLARES WHICH HOSTNAMES IT SERVES, AND THAT IS WHY IT EXISTS.
# The alternative was a UDM-Pro port forward, WAN :443 → 10.0.90.12:443 —
# simpler on paper (the connection is a static full IP stack, so there is no
# DDNS and no rotating address to manage), and rejected on one property: a
# port forward makes EVERY Traefik router internet-reachable, gated on nothing
# but middleware correctness, and a middleware one edit from wrong fails OPEN.
# The tunnel's ingress list below names exactly two hostnames; sonarr, radarr,
# prowlarr, grafana, jellyfin and the rest DO NOT RESOLVE OR ROUTE from
# outside — not "are refused", ARE NOT THERE.  Adding a service to the
# internet becomes an explicit act (a hostname here, a CNAME at Cloudflare)
# rather than the default consequence of creating a Traefik route.  That is
# fail-closed-by-construction — the same property this repo chose with
# DefaultPVID = "none" (M2b), default_policy = "deny" (M7), and mkOverride
# over silent merges.  It also sidesteps standing note SN2 entirely: the
# tunnel is outbound-only, so the UDM-Pro's IPv6 ruleset stays un-audited and
# un-relied-upon, exactly as before this milestone.
#
# ── THE COSTS, STATED PLAINLY (docs/roadmap.md M16 requires them here) ───────
#
#   - CLOUDFLARE TERMINATES TLS AND CAN SEE PLAINTEXT.  Every external
#     request to Jellyseerr — including the Jellyfin credentials its login
#     form carries — is decrypted at Cloudflare's edge, re-encrypted over the
#     tunnel, and decrypted again by Traefik.  That is a real disclosure to a
#     third party, accepted deliberately for the fail-closed property above.
#   - A THIRD PARTY IS IN THE AVAILABILITY PATH.  Cloudflare down means
#     Jellyseerr externally down.  Internal access is unaffected: Technitium
#     keeps resolving jellyseerr.goclan.org to 10.0.90.12, so household
#     traffic never leaves the house.  That split horizon is the mitigation.
#   - THE TUNNEL MUST NEVER GROW A jellyfin.goclan.org HOSTNAME.  Cloudflare's
#     terms have historically restricted proxying large media streams;
#     Jellyseerr is a low-bandwidth request UI so this does not bite, but a
#     video stream is exactly what it is written against.  "Just add one more
#     hostname" is the single most predictable future edit to this file, and
#     it is the one this paragraph exists to stop.
#
# ── WHY auth.goclan.org IS THE SECOND HOSTNAME — A CORRECTED PREMISE ─────────
#
#   docs/roadmap.md's M16 test plan listed auth.goclan.org among the names
#   that must be UNREACHABLE from outside.  That premise did not survive
#   implementation, and could not have: forward-auth is a REDIRECT protocol.
#   An unauthenticated request to jellyseerr.goclan.org answers with a 302 to
#   https://auth.goclan.org/?rd=…, and if that name does not resolve
#   externally, no external login can ever complete — the milestone's positive
#   test ("reaches Authelia, and Jellyseerr only after auth") requires the
#   portal on the external path BY CONSTRUCTION.  This is also what the same
#   milestone text demands: "the unauthenticated attack surface must be
#   AUTHELIA, not Jellyseerr's Node application."  So the portal rides the
#   tunnel, and what the internet meets there is Authelia's login form backed
#   by per-user regulation (3 failures / 5 min → 15 min ban) and mandatory
#   2FA — which was the design intent all along.  The corrected negative set
#   is every OTHER name; the ledger row records both hostnames.
#
# ── TIER: nspawn, OWN container — argued, not defaulted (invariant #1) ───────
#
#   "Talks to the internet on its own behalf" is the phrase that put
#   qBittorrent in a microvm, and cloudflared matches it literally, so the
#   microvm tier was argued rather than skipped.  It loses on what the tiers
#   are FOR.  qBittorrent's own kernel exists because it processes
#   attacker-supplied torrent data and must sit behind a killswitch whose
#   failure mode is "emit nothing".  cloudflared parses HTTP/2 and QUIC from
#   Cloudflare's edge and forwards it — the same class of untrusted-input
#   parsing Traefik does from every consumer VLAN, and Traefik is nspawn.
#   What matters here is not the kernel boundary but the BLAST RADIUS of a
#   compromised proxy, and that is bounded by the netns instead:
#
#     - its OWN container, not a unit inside Traefik's: code execution in
#       Traefik's netns inherits the one source address every backend
#       firewall in this fleet admits.  Here it inherits an address nothing
#       admits (no backend names 10.0.90.21 in an allow rule);
#     - an EGRESS firewall (below) that drops everything RFC1918 except
#       Traefik's :443 and Technitium's :53 — so a compromised cloudflared
#       can reach, on the LAN, exactly what the internet can already reach
#       through it, and nothing else.  No pivot to the arr APIs, the
#       monitoring stack, or the UDM-Pro's management plane;
#     - nothing listens: the INPUT policy admits no port from any source.
#
# ── WHY NOT services.cloudflared (the nixpkgs module — it exists) ────────────
#
#   The module keys its configuration on the tunnel's UUID
#   (`tunnels.<id>.…`), and the UUID lives inside the credentials JSON that
#   `cloudflared tunnel create` emits — clan-vars material that does not
#   exist at eval time on a fresh checkout.  Deriving Nix attribute NAMES
#   from a var is exactly the two-sources-of-truth trap this repo keeps
#   refusing, so instead the staging oneshot below reads the UUID out of the
#   credentials file with jq at ACTIVATION time and renders the whole
#   config.yml next to it.  The unit is hand-written — which M14 turned from
#   a chore into policy: read the unit, do not infer it from a module.
#
# ── Networking: veth on br0, Services VLAN 90 ────────────────────────────────
#
#   The jellyfin.nix "Networking — v2" pattern, verbatim, like every container
#   since M2b: KeepMaster rather than Bridge=, the ExecStartPost that settles
#   the VLAN race, the 20 s wait-online cap.  MAC 02:00:00:90:00:0d from the
#   allocation table in machines/ernst/networking.nix, DHCP reservation
#   10.0.90.21 — INSIDE the pool (10.0.90.6–.254); UniFi accepts a .2–.5
#   address and then silently hands out an ordinary lease (M2b, M5, M6).
#
#   NO Technitium record and no UDM-Pro ZBF rule: nothing on any VLAN ever
#   initiates a connection TO this container.  Its DNS names live at
#   Cloudflare (two proxied CNAMEs onto <tunnel-id>.cfargotunnel.com), which
#   is the one deliberate exception to "names resolve to Traefik" — the
#   invariant-#4 bypass row in docs/roadmap.md's ledger records it.
{ config, pkgs, lib, ... }:

let
  baseDomain = "goclan.org";

  # The COMPLETE list of externally served names.  Growing this list is
  # growing the internet-facing surface of the house: it needs a matching
  # proxied CNAME at Cloudflare, a deliberate decision recorded in the ledger
  # row, and — for anything that is not Jellyseerr or the portal — a very
  # good answer to the "never jellyfin" paragraph in the header.
  externalHosts = [
    "jellyseerr.${baseDomain}"
    "auth.${baseDomain}"
  ];

  # Traefik, the sole origin.  Requests leave the tunnel as HTTPS to .12 with
  # the ORIGINAL hostname as SNI and Host header, so the existing routers
  # match unchanged and Traefik serves its ordinary wildcard certificate,
  # which cloudflared verifies against the system CA bundle (LE is real).
  traefikAddr = "10.0.90.12";

  # Technitium — declared, not DHCP-inherited, same call as every container.
  # cloudflared resolves Cloudflare's edge through it; the goclan.org names
  # it carries internally are irrelevant to this container, which never
  # dials them by name.
  dnsAddr = "10.0.5.3";

  cloudflaredUid = 3029;   # allocated in machines/ernst/networking.nix
  cloudflaredGid = 3029;

  cfMac    = "02:00:00:90:00:0d";
  vlanId   = 90;
  vethName = "vb-cloudflared";

  # Staged at runtime by cloudflared-secrets on the host, bind-mounted
  # read-only at the identical path — the authelia.nix pattern.
  secretsDir = "/run/cloudflared-secrets";
  credsFile  = "${secretsDir}/tunnel.json";
  configFile = "${secretsDir}/config.yml";

  tunnelGen = config.clan.core.vars.generators.cloudflared-jellyseerr;
in
{
  ##############################################################################
  # Host-side wiring.
  ##############################################################################

  # No tmpfiles rule and no /srv/state directory: cloudflared is STATELESS.
  # Its identity is the credentials var, its configuration is rendered below,
  # and nothing it writes at runtime is worth keeping.  A service with no
  # state gets no dataset (invariant #7 cuts both ways).

  # Stage the tunnel credentials and render config.yml where the container
  # can see them.  Rendered HERE rather than written in Nix because the
  # `tunnel:` line needs the UUID out of the credentials JSON — see the
  # header.  Rotating the var needs a restart, not just a deploy; the
  # generator's restartUnits carry that.
  systemd.services.cloudflared-secrets = {
    description = "Stage the Cloudflare Tunnel credentials and config for container@cloudflared";
    after       = [ "local-fs.target" ];
    before      = [ "container@cloudflared.service" ];
    requiredBy  = [ "container@cloudflared.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils pkgs.jq ];
    script = ''
      set -euo pipefail

      # 0711 for the same reason authelia-secrets gives: the files inside are
      # read by uid ${toString cloudflaredUid}, unprivileged, so the walk in
      # must be possible while the listing is not.
      install -d -m 0711 -o root -g root ${secretsDir}

      src=${tunnelGen.files."tunnel.json".path}

      # Fail the deploy, not the tunnel, on malformed credentials: jq -e
      # exits non-zero when TunnelID is missing, and a oneshot that dies here
      # stops container@cloudflared from starting with a config that names
      # no tunnel (Requires= via requiredBy).
      tunnel_id=$(jq -re .TunnelID "$src")

      install -m 0400 -o ${toString cloudflaredUid} -g ${toString cloudflaredGid} \
        "$src" ${credsFile}

      umask 077
      {
        echo "tunnel: $tunnel_id"
        echo "credentials-file: ${credsFile}"
        echo "no-autoupdate: true"
        echo "ingress:"
        ${lib.concatMapStrings (host: ''
          echo "  - hostname: ${host}"
          echo "    service: https://${traefikAddr}:443"
          echo "    originRequest:"
          echo "      originServerName: ${host}"
        '') externalHosts}
        # The terminal rule.  Anything Cloudflare sends for a hostname not
        # declared above — which can only happen if a CNAME is created
        # without editing this file — answers 404 HERE, before any request
        # reaches Traefik.  Fail closed, in the tunnel's own vocabulary.
        echo "  - service: http_status:404"
      } > ${configFile}.new
      chown ${toString cloudflaredUid}:${toString cloudflaredGid} ${configFile}.new
      chmod 0400 ${configFile}.new
      mv -f ${configFile}.new ${configFile}
    '';
  };

  # Host side of the container's veth — a VLAN-90 port on br0.  Identical to
  # vb-authelia's block; see that file for the KeepMaster and
  # RequiredForOnline reasoning.
  systemd.network.networks."60-${vethName}" = {
    matchConfig.Name = vethName;
    networkConfig = {
      KeepMaster          = true;
      LinkLocalAddressing = "no";
      IPv6AcceptRA        = false;
    };
    bridgeVLANs = [ { VLAN = vlanId; PVID = vlanId; EgressUntagged = vlanId; } ];
    linkConfig.RequiredForOnline = "enslaved";
  };

  # Re-assert the VLAN membership after nspawn creates the veth — the same
  # real race every vb-* in this fleet settles this way.
  systemd.services."container@cloudflared".serviceConfig.ExecStartPost = [
    "-${pkgs.iproute2}/bin/bridge vlan add dev ${vethName} vid ${toString vlanId} pvid untagged"
  ];

  ##############################################################################
  # Vars generator.
  ##############################################################################
  #
  # The credentials JSON is MINTED OUTSIDE THIS REPO, by
  # `cloudflared tunnel create jellyseerr` run wherever `cloudflared tunnel
  # login` has left a cert.pem (lgo's laptop).  That is deliberate: the
  # origin certificate that can CREATE tunnels and REWRITE zone DNS never
  # touches ernst; the machine holds only this one tunnel's own secret,
  # which can run the tunnel and nothing else.  Cloudflare revokes it from
  # the dashboard if it leaks, without touching the account credential.
  clan.core.vars.generators.cloudflared-jellyseerr = {
    files."tunnel.json".secret       = true;
    files."tunnel.json".restartUnits = [
      "cloudflared-secrets.service"
      "container@cloudflared.service"
    ];

    prompts."credentials-json" = {
      description = ''
        The single-line credentials JSON written by `cloudflared tunnel create
        jellyseerr` (…/.cloudflared/<tunnel-id>.json). It must contain
        AccountTag, TunnelSecret and TunnelID.
      '';
      type = "hidden";
    };

    runtimeInputs = [ pkgs.jq pkgs.coreutils ];

    script = ''
      set -euo pipefail
      umask 077

      # Validate at GENERATE time, on the operator's own terminal, where the
      # error is readable — not at 03:00 on ernst where it is a dead oneshot.
      jq -e 'has("AccountTag") and has("TunnelSecret") and has("TunnelID")' \
        "$prompts/credentials-json" > /dev/null || {
          echo "  ✗ not a cloudflared tunnel credentials JSON (needs AccountTag," >&2
          echo "    TunnelSecret, TunnelID — the file tunnel create writes)" >&2
          exit 1
        }
      jq -c . "$prompts/credentials-json" > "$out/tunnel.json"
    '';
  };

  ##############################################################################
  # The container itself.
  ##############################################################################
  containers.cloudflared = {
    autoStart = true;
    ephemeral = true;            # stateless — see the tmpfiles note above

    privateNetwork  = true;
    hostBridge      = "br0";
    localMacAddress = cfMac;

    bindMounts = {
      # The staged credentials and rendered config, read-only, identical path.
      "${secretsDir}" = {
        hostPath   = secretsDir;
        isReadOnly = true;
      };
    };

    config = { config, pkgs, lib, ... }: {
      system.stateVersion = "26.05";
      time.timeZone = "Europe/Berlin";

      ##########################################################################
      # Networking — the container owns its netns.
      ##########################################################################
      networking.useHostResolvConf = false;
      networking.useNetworkd       = true;
      services.resolved.enable     = true;

      systemd.network.networks."10-eth0" = {
        matchConfig.Name = "eth0";
        networkConfig = {
          DHCP         = "ipv4";
          DNS          = dnsAddr;
          Domains      = "~.";
          IPv6AcceptRA = false;
        };
        dhcpV4Config = {
          UseDNS     = false;
          UseDomains = false;
        };
        linkConfig.RequiredForOnline = "routable";
      };
      systemd.network.wait-online.timeout = 20;

      ##########################################################################
      # Firewall — BOTH directions, and the egress half is the security
      # argument for this container's tier (see the header).
      #
      # INBOUND: nothing.  No port is open to any source; the empty
      # allowedTCPPorts list plus the chain's terminal refuse is the whole
      # policy.  cloudflared originates its edge connections outbound and
      # never listens for anything this fleet should reach.
      #
      # OUTBOUND: a compromised cloudflared may reach, on RFC1918 space,
      # exactly what the tunnel already grants the internet — Traefik's :443
      # — plus the resolver, and NOTHING else.  Its own chain rather than
      # bare -A OUTPUT lines because extraCommands runs on every firewall
      # start AND reload: nixos-fw is flushed each time but OUTPUT is not,
      # so un-chained appends would accumulate.  The delete/flush prologue
      # makes the block idempotent.
      ##########################################################################
      networking.firewall.allowedTCPPorts = [ ];
      networking.firewall.extraCommands = ''
        iptables -D OUTPUT -j cf-egress 2>/dev/null || true
        iptables -F cf-egress 2>/dev/null || true
        iptables -X cf-egress 2>/dev/null || true
        iptables -N cf-egress
        iptables -A cf-egress -o lo -j RETURN
        iptables -A cf-egress -m state --state ESTABLISHED,RELATED -j RETURN
        # Traefik: the tunnel's one and only origin.
        iptables -A cf-egress -d ${traefikAddr}/32 -p tcp --dport 443 -j RETURN
        # Technitium: cloudflared resolves Cloudflare's edge addresses.
        iptables -A cf-egress -d ${dnsAddr}/32 -p udp --dport 53 -j RETURN
        iptables -A cf-egress -d ${dnsAddr}/32 -p tcp --dport 53 -j RETURN
        # DHCP renewal unicasts to the UDM-Pro.  (Initial acquisition uses
        # AF_PACKET, which iptables never sees.)
        iptables -A cf-egress -p udp --dport 67 -j RETURN
        # THE POINT: no pivot from here into the house.
        iptables -A cf-egress -d 10.0.0.0/8     -j REJECT
        iptables -A cf-egress -d 172.16.0.0/12  -j REJECT
        iptables -A cf-egress -d 192.168.0.0/16 -j REJECT
        iptables -A cf-egress -d 169.254.0.0/16 -j REJECT
        # Everything non-RFC1918 — Cloudflare's edge on 443/7844 (QUIC with
        # http2 fallback), NTP — is the container's job.
        iptables -A cf-egress -j RETURN
        iptables -A OUTPUT -j cf-egress
      '';
      networking.firewall.extraStopCommands = ''
        iptables -D OUTPUT -j cf-egress 2>/dev/null || true
        iptables -F cf-egress 2>/dev/null || true
        iptables -X cf-egress 2>/dev/null || true
      '';

      ##########################################################################
      # User.  Numeric ids are the interface across the nspawn boundary —
      # allocation table in machines/ernst/networking.nix.  OWN group, no
      # media: this service has no business being able to name a file in any
      # library, and nothing else needs to read what it never writes.
      ##########################################################################
      users.users.cloudflared = {
        isSystemUser = true;
        uid          = cloudflaredUid;
        group        = "cloudflared";
      };
      users.groups.cloudflared = { gid = cloudflaredGid; };

      ##########################################################################
      # The unit.  Hand-written — see WHY NOT services.cloudflared above —
      # and hardened from the start, because M14 measured what upstream units
      # ship with when nobody looks (9.0 UNSAFE, twice).
      ##########################################################################
      systemd.services.cloudflared = {
        description = "Cloudflare Tunnel — jellyseerr + auth external ingress";
        wantedBy    = [ "multi-user.target" ];
        after       = [ "network-online.target" ];
        wants       = [ "network-online.target" ];

        serviceConfig = {
          Type  = "simple";
          User  = "cloudflared";
          Group = "cloudflared";

          ExecStart = lib.concatStringsSep " " [
            (lib.getExe pkgs.cloudflared)
            "--no-autoupdate"
            "tunnel"
            "--config ${configFile}"
            "run"
          ];

          # The edge connection drops whenever Cloudflare re-balances; the
          # daemon reconnects itself.  Restart covers the process dying, and
          # 30 s matches the fleet's setting for services whose failure mode
          # can be a dead upstream rather than a local bug.
          Restart    = "on-failure";
          RestartSec = "30s";

          NoNewPrivileges  = true;
          PrivateTmp       = true;
          ProtectSystem    = "strict";
          ProtectHome      = true;
          RemoveIPC        = true;
          RestrictSUIDSGID = true;

          # No ReadWritePaths at all: the config and credentials are read-only
          # and there is no state.  ProtectSystem=strict with an empty RW set
          # is the honest expression of "stateless".

          CapabilityBoundingSet   = "";
          PrivateDevices          = true;
          ProtectClock            = true;
          ProtectControlGroups    = true;
          ProtectHostname         = true;
          ProtectKernelLogs       = true;
          ProtectKernelModules    = true;
          ProtectKernelTunables   = true;
          ProtectProc             = "invisible";
          # AF_NETLINK: the Go net stack enumerates interfaces over netlink
          # when it picks source addresses for the edge connections.
          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" ];
          RestrictNamespaces      = true;
          RestrictRealtime        = true;
          LockPersonality         = true;
          SystemCallArchitectures = "native";
          SystemCallFilter        = [ "@system-service" "~@privileged" "~@debug" "~@mount" ];

          # Unlike every V8/.NET service in the arr container, Go does not
          # JIT: this one gets MemoryDenyWriteExecute, and it is the first
          # unit in the fleet where the directive costs nothing.
          MemoryDenyWriteExecute = true;
        };
      };

      # curl is the in-netns instrument for the egress rules: it must FAIL to
      # 10.0.90.13:8989 (REJECT) and succeed to https://10.0.90.12 with the
      # right SNI — both halves of the blast-radius claim, testable in place.
      environment.systemPackages = with pkgs; [ curl ];
      documentation.enable       = false;
      documentation.nixos.enable = false;
    };
  };
}
