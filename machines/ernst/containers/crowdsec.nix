# machines/ernst/containers/crowdsec.nix
#
# CrowdSec — log-driven detection plus an nftables remediation, INSIDE THE
# TRAEFIK CONTAINER'S NETWORK NAMESPACE.  M18: the thing that watches the WAN
# ingress the same milestone opened.
#
# ── THIS FILE CO-DEFINES containers.traefik.  THAT IS THE WHOLE DESIGN ───────
#
#   It does not create a container.  It merges units into the one
#   machines/ernst/containers/traefik.nix declares, and adds the host-side
#   state directory.  `containers.<name>.config` merges multiple definitions
#   like any other NixOS option, so the two files compose; traefik.nix's header
#   says so in its storage section, because a file that adds a daemon to
#   somebody else's container must not be discoverable only by accident.
#
#   WHY NOT ITS OWN CONTAINER, WHICH IS THIS REPO'S DEFAULT ANSWER.  Because a
#   bouncer in another netns cannot enforce anything here, and that was
#   MEASURED rather than assumed.  The path a WAN request takes is:
#
#       internet → UDM-Pro (DNAT to 10.0.90.12:8443) → trunk → br0 → veth
#                → the traefik container's netns
#
#   br0 forwards those frames at layer 2.  On ernst, 2026-09-03:
#
#       lsmod | grep br_netfilter                 → not loaded
#       sysctl net.bridge.bridge-nf-call-iptables → no such file
#
#   So the HOST'S netfilter never sees the packet at all.  A bouncer on ernst
#   could write every rule it liked and drop nothing.  The only place with both
#   the pre-DNAT source address and a hook the packet actually traverses is
#   this netns — which is also where the access log is.  Agent, local API and
#   bouncer therefore all live here, and the question "which machine's firewall
#   sees the pre-DNAT source" has exactly one answer: the traefik container's.
#
#   THE TIER QUESTION (invariant #1) resolves the same way it did for Traefik
#   itself: this is a log parser and a netlink client. It fetches from
#   hub.crowdsec.net and nothing else, it renders no attacker-supplied content,
#   and it is in the same trust position as the proxy whose log it reads.  It
#   does not get a kernel; it gets the proxy's namespace, deliberately, because
#   separating them would break the only capability it has.
#
#   PLACEMENT IN machines/ernst/ AND NOT service-modules/: service-modules/ is
#   for clan-service modules with roles a fleet subscribes to (monitoring,
#   local-ai).  This is one machine's container, wired to one other file in the
#   same directory, and it could not be given a role without reaching into
#   traefik.nix from outside.  It follows the convention M2b set — the units
#   live with the service.
#
# ── FOUR UPSTREAM DEFECTS, MEASURED IN A THROWAWAY VM BEFORE DEPLOYING ───────
#
#   nixpkgs' services.crowdsec and services.crowdsec-firewall-bouncer were
#   booted in a QEMU VM built from THIS flake's nixpkgs on 2026-09-03, in the
#   shape below, six times.  M14's four deploy-day defects are why: a milestone
#   that cannot be tested before deploying should be tested somewhere else.
#   Every override in this file names the thing it fixes.
#
#   (1) THE AGENT CRASH-LOOPS FOREVER ON A FIRST BOOT.  This is the big one,
#       and it is silent in the sense that matters — the unit is `activating`,
#       not `failed`, so `systemctl list-units --failed` is EMPTY while
#       CrowdSec has never once run.  Measured, restart counter 28:
#
#         Error: cscli machines add: write api credentials in
#           '/var/lib/crowdsec/local_api_credentials.yaml' failed:
#           open …: permission denied
#         …and on every start after that:
#         Error: cscli machines add: unable to create machine:
#           user 'csprobe': user already exist
#
#       The module's tmpfiles list creates /var/lib/crowdsec/state but NOT
#       /var/lib/crowdsec, so the parent is created implicitly root:root 0755.
#       The unprivileged agent's ExecStartPre then registers the machine in the
#       database and CANNOT write the credentials file beside it.  The setup
#       script's guard is `if the credentials file is absent, add the machine`
#       — so from then on it retries an add that can only fail, forever.
#
#       TWO FIXES, because one of them is luck.  The bind mount below already
#       gives /var/lib/crowdsec the right owner, so as deployed this cannot
#       fire; that is an accident of the state layout, not a defence, so the
#       in-container tmpfiles rule states it, and `crowdsec-unstick` clears the
#       stale row if it ever happens anyway.
#
#   (2) THE BOUNCER REGISTRATION CAN NEVER SUCCEED.  Measured:
#
#         crowdsec-firewall-bouncer-register.service:
#           Error: while reading yaml file: open /etc/crowdsec/config.yaml:
#           no such file or directory
#
#       The NixOS module renders the config into the STORE and passes it with
#       `-c`, and it never creates /etc/crowdsec/config.yaml — but the register
#       unit shells out to the RAW cscli with no `-c`, so it looks for the
#       default path.  Without it the API key is never minted, the bouncer dies
#       at LoadCredential, and there is no remediation at all.  Fixed by
#       `environment.etc` below, generated from the SAME option the module
#       renders, so the two cannot drift.
#
#   (3) BOTH REMEDIATION UNITS SHIP `Restart=no`.  Measured on a first boot:
#       the bouncer starts before the local API is listening, dies with
#       "dial tcp 127.0.0.1:8080: connect: connection refused", and STAYS dead.
#       This is the hazard M18's brief predicted in a different place — it
#       expected a missing `After=`/`PartOf=`, and those are present and
#       correct in this channel (measured: `PartOf=nftables.service`,
#       `After=… nftables.service crowdsec.service`).  The bug is one step
#       further on: the ordering is right and the retry is missing, so a
#       transient LAPI-not-ready leaves the WAN entrypoint open and unwatched
#       until a human notices.  SN4's shape exactly.  Both get Restart.
#
#   (4) DynamicUser + StateDirectory MIGRATES THE STATE DIRECTORY.  Measured:
#
#         Found pre-existing public StateDirectory= directory /var/lib/crowdsec,
#         migrating to /var/lib/private/crowdsec.
#
#       /var/lib/crowdsec is a BIND MOUNT here.  systemd renaming a mount point
#       is not a thing that ends well, and this is the same trap
#       service-modules/local-ai.nix hit with ollama and turned DynamicUser off
#       for.  Same call, same reason.
#
# ── WHAT IS NOT DONE, AND WHY ────────────────────────────────────────────────
#
#   NO TRAEFIK PLUGIN.  CrowdSec's usual Traefik integration is a Yaegi plugin
#   that Traefik FETCHES FROM plugins.traefik.io AT STARTUP — unpinned network
#   access during service start, in a repo whose whole premise is hashed
#   inputs, on the one service every other service is behind.  The remediation
#   here is the nftables bouncer instead, which is strictly better anyway: it
#   drops the packet before Traefik parses it, so a banned scanner costs no TLS
#   handshake.  If a plugin is ever genuinely needed it must be vendored via
#   localPlugins with a fixed-output derivation, and the argument goes here.
#
#   NO CENTRAL API, NO CONSOLE.  `settings.capi.credentialsFile` and
#   `console.tokenFile` are left null, so this instance neither pulls the
#   community blocklist nor pushes its alerts anywhere.  That is the same
#   decision M18 made about Cloudflare, applied consistently: the milestone
#   exists to take a third party OUT of the data path, and enrolling in CAPI
#   would put a different one into the signal path a week later.  The cost is
#   real and is stated — no community blocklist, so this detects only what it
#   sees itself.  The trigger to revisit is wanting the blocklist badly enough
#   to argue for the telemetry, not tidiness.
#
#   NO AUTO-UPDATE TIMER.  `autoUpdateService` stays off: the agent's own
#   ExecStartPre already runs `cscli hub update` on every start, so the timer
#   would add a second updater whose failure is a silent oneshot (SN4).
#
# ── `cscli explain` IS THE WRONG INSTRUMENT HERE.  MEASURED ──────────────────
#
#   The obvious way to check "is my line being parsed" is to copy a line out of
#   the journal into a file and run `cscli explain -f line.txt --type syslog`.
#   In the probe VM that reported, on a line the LIVE pipeline parsed perfectly:
#
#       ├ s00-raw
#       |  ├ 🔴 crowdsecurity/syslog-logs
#       |  └ 🔴 crowdsecurity/non-syslog
#       └-------- parser failure 🔴
#
#   It is not a parser failure.  `explain` feeds the file's raw bytes — bare
#   JSON — while the journalctl datasource supplies the syslog envelope that
#   s00-raw needs, so the two are not reading the same thing.  Believing that
#   red would mean rebuilding a pipeline that works, which is SN3 pointing the
#   other way: a broken instrument producing a damning result.
#
#   THE INSTRUMENT IS `cscli metrics show acquisition`.  Lines read must equal
#   lines parsed.  In the probe VM, on the same line: read 1, parsed 1, poured
#   to bucket 2, and `crowdsecurity/{syslog-logs,traefik-logs,http-logs}` each
#   1/1.  That is what "the detector can see" looks like.
#
# ── THE ONE UNPINNED FETCH, STATED PLAINLY ───────────────────────────────────
#
#   `cscli hub update` runs at EVERY agent start, from ExecStartPre, under
#   `set -euo pipefail`, and the nixpkgs module offers no way to turn it off.
#   So this is network access during service start, against content nothing in
#   this repo hashes — the exact objection that rules out the Traefik plugin
#   above, and it is only fair to say that it applies here too.
#
#   It is accepted, for two reasons.  The hub IS the product: CrowdSec's value
#   is a community-maintained scenario set, and pinning it to a commit would
#   leave the detector reading last year's attack patterns.  And the failure
#   mode is bounded and visible: a hub that is unreachable fails the
#   ExecStartPre, which fails the unit, which Restart retries — and M18 adds a
#   monitoring alert for exactly "the wan entrypoint is up and CrowdSec is
#   not".  A ledger row carries this with a trigger.
#
# ── ENFORCEMENT IS OFF UNTIL Q2 IS ANSWERED.  READ THIS BEFORE FLIPPING IT ───
#
#   `enforce = false` below puts CrowdSec in SIMULATION: it parses, it fires
#   scenarios, it records decisions — and marks them simulated, so the bouncer
#   never receives them and nothing is dropped.
#
#   THE REASON IS Q2, AND IT IS NOT A FORMALITY.  Everything downstream of the
#   access log keys on the source address the log records.  If the UDM-Pro
#   SNATs the port forward instead of preserving the source, every external
#   request appears to come from 10.0.90.1, and the first scanner would get the
#   DEFAULT GATEWAY banned — which takes the whole house off Jellyseerr, and
#   possibly off more than that.  A remediation that can do that must not be
#   armed on a guess.
#
#   TO ARM IT: make one request from a known external address, then
#
#       nixos-container run traefik -- journalctl -u traefik -n 5 -o cat \
#         | jq -r .ClientHost
#
#   If that prints the external address, Q2 is CONFIRMED — flip `enforce` to
#   true and deploy.  If it prints 10.0.90.1, or the bridge, or the gateway,
#   STOP: the milestone needs proxyProtocol on the wan entryPoint or a
#   different forward mode on the UDM-Pro, and arming this would be actively
#   harmful.  docs/roadmap.md M18 carries the answer as CONFIRMED / FALSE /
#   UNRESOLVED; do not leave it as prose.
#
# ── Storage layout on this host (see machines/ernst/disko.nix) ───────────────
#
#   /srv/state/crowdsec   zdata/state   RW into the container at
#                                       /var/lib/crowdsec
#     state/crowdsec.db                 decisions, alerts, machine + bouncer
#                                       credentials, the acquisition cursor
#     local_api_credentials.yaml        the agent's own LAPI login
#
#   INVARIANT #7, and it is not a formality here either.  zroot rolls back, so
#   on zroot every ban would evaporate at the next boot — and worse, so would
#   the machine and bouncer credentials, putting defect (1) above in the path
#   of every single reboot.  It is on zdata.
{ config, lib, pkgs, ... }:
let
  ############################################################################
  # THE ENFORCEMENT SWITCH.  See the block above — this is Q2's gate.
  ############################################################################
  enforce = false;

  ############################################################################
  # Identity.
  #
  # uid/gid 3030, allocated in the table in machines/ernst/networking.nix.
  # nspawn passes ids through unmapped, so this is a number on zdata — and
  # /srv/state/crowdsec is on zdata.
  #
  # NOT in group media, and not in any group but its own.  A log parser has no
  # business holding a handle to anything.
  ############################################################################
  crowdsecUid = 3030;
  crowdsecGid = 3030;

  stateDirHost = "/srv/state/crowdsec";

  # The module's own rootDir.  Named here because the bind mount and the
  # credentials path both have to agree with it, and one binding is cheaper to
  # keep in step than three string literals.
  rootDir  = "/var/lib/crowdsec";
  credFile = "${rootDir}/local_api_credentials.yaml";

  # The local API, on loopback inside this netns.  Not a port on eth0: the only
  # clients are the agent and the bouncer, both of which are in here, and an
  # unauthenticated-by-network-position API that hands out ban decisions has no
  # business being reachable from VLAN 90.  `lo` is always trusted by the
  # container firewall, so no rule is needed and none is written.
  lapiAddr = "127.0.0.1:8080";

  # M6 scrapes this.  Its own listener on the container's address rather than a
  # Traefik route, for the same reason Traefik's own metrics endpoint is a
  # separate entryPoint: a listener is restricted once, in the firewall, and
  # cannot be re-exposed by adding a router.  Source-restricted to the
  # monitoring container below.
  metricsPort    = 6060;
  monitoringAddr = "10.0.90.14";
in
{
  ##############################################################################
  # Host-side wiring.
  ##############################################################################

  # State on zdata.  0750 and owned by the service, exactly like
  # /srv/state/{traefik,authelia,monitoring}.
  #
  # NUMERIC ids on purpose — `crowdsec` is a container user and the host has no
  # matching passwd entry.  Same shape containers/traefik.nix uses for 3005.
  #
  # THIS RULE IS ALSO WHAT KEEPS UPSTREAM DEFECT (1) FROM FIRING: the bind
  # mount arrives already owned by the crowdsec uid, so the first
  # `cscli machines add` can write its credentials beside the database.
  systemd.tmpfiles.rules = [
    "d ${stateDirHost} 0750 ${toString crowdsecUid} ${toString crowdsecGid} -"
  ];

  ##############################################################################
  # Into the Traefik container.  See the header for why this is not its own.
  ##############################################################################
  containers.traefik = {
    bindMounts."${rootDir}" = {
      hostPath   = stateDirHost;
      isReadOnly = false;
    };

    config = { config, lib, pkgs, ... }:
      let
        # Regenerated from the module's own option — the fix for defect (2).
        etcConfig =
          (pkgs.formats.yaml { }).generate "crowdsec.yaml"
            config.services.crowdsec.settings.general;
      in
      {
        ########################################################################
        # The user.  Numeric ids are the interface across the nspawn boundary.
        #
        # The module declares users.users.crowdsec without a uid, as a plain
        # definition, so adding one here is a MERGE and needs no mkForce — the
        # same shape containers/traefik.nix found for 3005.
        #
        # isSystemUser must be restated with the uid: NixOS infers "effectively
        # a system user" from uid < 1000, and 3030 is not, so the inference
        # stops working the moment the uid is pinned.  containers/arr.nix hit
        # exactly this and the error names neither the uid nor the cause.
        ########################################################################
        users.users.crowdsec = {
          isSystemUser = true;
          uid          = crowdsecUid;
          group        = "crowdsec";
          # The journal is the acquisition source; see `localConfig` below.
          extraGroups  = [ "systemd-journal" ];
        };
        users.groups.crowdsec = { gid = crowdsecGid; };

        # Belt and braces for upstream defect (1).  The bind mount already
        # arrives owned correctly, so this changes nothing today — it is here
        # so that a future change to the state layout cannot silently
        # reintroduce a permanently crash-looping agent.
        systemd.tmpfiles.rules = [
          "d ${rootDir} 0750 crowdsec crowdsec -"
        ];

        ########################################################################
        # The agent + the local API.
        ########################################################################
        services.crowdsec = {
          enable = true;

          # `crowdsecurity/traefik` pulls in exactly what is needed and nothing
          # more: the parser `crowdsecurity/traefik-logs`, and through
          # `base-http-scenarios` the parser `crowdsecurity/http-logs` plus the
          # generic HTTP scenarios — http-probing, http-crawl-non_statics,
          # http-generic-bf, http-bad-user-agent and the CVE probes.  Verified
          # loaded in the probe VM: 5 parser nodes across 3 stages, 47
          # scenarios.
          #
          # `crowdsecurity/syslog-logs` is SEPARATE AND REQUIRED, and its
          # absence is a silent failure rather than an error.  The traefik
          # parser's filter is `evt.Parsed.program startsWith 'traefik'`, and
          # `program` is set by the s00-raw syslog parser from the journal
          # entry's SYSLOG_IDENTIFIER.  Without it every line is unparsed and
          # CrowdSec looks perfectly healthy while detecting nothing — which is
          # SN3 in its purest form.  `cscli metrics show acquisition` is the
          # instrument: lines read must equal lines parsed.
          hub.collections = [ "crowdsecurity/traefik" ];
          hub.parsers     = [ "crowdsecurity/syslog-logs" ];

          # See the header: the hub already updates at every start, so a daily
          # timer would be a second updater failing silently.
          autoUpdateService = false;

          # ── The local API ────────────────────────────────────────────────
          #
          # Loopback only.  `credentialsFile` must live under rootDir: it is
          # written at first start and read on every start, and on zroot it
          # would be regenerated after each reboot — putting defect (1) in the
          # path of every boot rather than only the first.
          settings.general.api.server.enable     = true;
          settings.general.api.server.listen_uri = lapiAddr;
          settings.lapi.credentialsFile          = credFile;

          # NO CENTRAL API and NO CONSOLE — see the header.  Left null, which
          # is what disables the online client.
          settings.capi.credentialsFile = null;
          settings.console.tokenFile    = null;

          # M6.  Bound to the container's address, restricted to the monitoring
          # container by the firewall rule below.
          settings.general.prometheus = {
            enabled     = true;
            level       = "full";
            listen_addr = "0.0.0.0";
            listen_port = metricsPort;
          };

          # ── SIMULATION UNTIL Q2 IS CONFIRMED.  Read the header ────────────
          #
          # true = detect and record, do not enforce.  The single edit that
          # arms this milestone's remediation is `enforce` at the top of this
          # file, and it must not be made before the access log has been seen
          # to carry a real external address.
          settings.simulation.simulation = !enforce;

          ##################################################################
          # Acquisition: the journal, not a file.
          #
          # Traefik's access log goes to stdout and therefore to this
          # container's journal, which is where it already went before M18 —
          # so this milestone changes the log's FORMAT and not its
          # destination.  That is deliberately the smaller change to an
          # existing operational surface: a file would have needed a path, an
          # owner, a rotation unit, and a mode that this uid can read, and
          # every one of those is a way for the detector to read nothing
          # while looking healthy.
          #
          # `labels.type = "syslog"` is what routes the line into
          # crowdsecurity/syslog-logs at stage s00-raw, which sets
          # `evt.Parsed.program` from SYSLOG_IDENTIFIER — and that is the
          # field crowdsecurity/traefik-logs filters on.  The three pieces
          # only work together; see the hub comment above.
          ##################################################################
          localConfig.acquisitions = [
            {
              source            = "journalctl";
              journalctl_filter = [ "_SYSTEMD_UNIT=traefik.service" ];
              labels.type       = "syslog";
            }
          ];

          ##################################################################
          # THE WHITELIST, AND IT IS LOAD-BEARING.
          #
          # One router serves each external name on `wan` and its twin serves
          # the LAN on `websecure`, but they share one access log — so every
          # internal request in the house is parsed by the same scenarios as
          # every external one.  Without this, a household member mistyping a
          # password six times, or Jellyfin's own clients walking a few dozen
          # 404s, would put an INSIDE address in the ban set, and the drop
          # chain would then cut that person off from the proxy every other
          # service in the house is behind.
          #
          # Written locally rather than installed from the hub
          # (crowdsecurity/whitelists) on purpose: this is the one rule whose
          # content must not change under us on a `cscli hub update`, and it
          # is four lines.
          #
          # The v6 ranges are absent because there is no v6 anywhere on this
          # path — see IPv4-ONLY BY CONSTRUCTION in traefik.nix's header.  If
          # that ever changes, this list changes with it.
          ##################################################################
          localConfig.parsers.s02Enrich = [
            {
              name        = "clanarchy/inside-whitelist";
              description = "Never ban an address inside the house";
              whitelist = {
                reason = "RFC1918 and loopback are the household, not the internet";
                cidr = [
                  "10.0.0.0/8"
                  "172.16.0.0/12"
                  "192.168.0.0/16"
                  "127.0.0.0/8"
                ];
              };
            }
          ];
        };

        ######################################################################
        # UPSTREAM FIX (2): the register unit runs the raw cscli with no -c,
        # and the module never writes /etc/crowdsec/config.yaml.  Generated
        # from the module's OWN option, so it is the same content by
        # construction.  This also makes a hand-run `cscli` work for an
        # operator, which it otherwise would not.
        ######################################################################
        environment.etc."crowdsec/config.yaml".source = etcConfig;

        ######################################################################
        # UPSTREAM FIX: journalctl must be on the agent's PATH.
        #
        # The module sets `path = lib.mkForce [ ]`, and the journalctl
        # acquisition datasource SHELLS OUT to journalctl.  Without this the
        # agent starts, reports healthy, and reads zero lines — the failure
        # SN3 is about.  mkForce again, to win against the module's own.
        ######################################################################
        systemd.services.crowdsec.path = lib.mkForce [ pkgs.systemd ];

        ######################################################################
        # UPSTREAM FIX (4): DynamicUser + a bind-mounted state directory.
        #
        # Measured: "Found pre-existing public StateDirectory= directory
        # /var/lib/crowdsec, migrating to /var/lib/private/crowdsec."  That
        # directory is a mount point here.  The uid is static and allocated,
        # so DynamicUser buys nothing and costs that.
        ######################################################################
        systemd.services.crowdsec.serviceConfig.DynamicUser = lib.mkForce false;
        systemd.services.crowdsec-firewall-bouncer-register.serviceConfig.DynamicUser =
          lib.mkForce false;

        ######################################################################
        # UPSTREAM FIX (3): both remediation units ship Restart=no.
        #
        # Measured on a first boot: the bouncer starts before the local API is
        # listening, dies on "connection refused", and stays dead — leaving
        # the wan entrypoint open and unwatched with nothing in
        # `list-units --failed` after the next attempt clears it.
        #
        # NOT a substitute for the ordering, which is already correct in this
        # channel and is left alone: PartOf=nftables.service and
        # After=nftables.service crowdsec.service are both present upstream
        # (measured).  Restating them here would be a second source of truth
        # for an ordering that is right.
        ######################################################################
        systemd.services.crowdsec-firewall-bouncer.serviceConfig = {
          Restart    = "on-failure";
          RestartSec = "15s";
        };
        systemd.services.crowdsec-firewall-bouncer-register.serviceConfig = {
          Restart    = "on-failure";
          RestartSec = "15s";
        };

        ######################################################################
        # UPSTREAM FIX (1), the recovery half.
        #
        # If the credentials file is missing while the machine row exists, the
        # module's setup script retries an add that can only answer "user
        # already exist", and the agent crash-loops forever in the
        # `activating` state — which `systemctl list-units --failed` does not
        # show.  The bind mount's ownership means this should never arise;
        # this clears it if it does, and does nothing at all otherwise.
        #
        # mkBefore so it runs ahead of the module's own ExecStartPre.  The
        # leading "" is what RESETS an additive directive rather than
        # appending to it — the trap this repo has written down before.
        ######################################################################
        systemd.services.crowdsec.serviceConfig.ExecStartPre = lib.mkBefore [
          (pkgs.writeShellScript "crowdsec-unstick" ''
            set -eu
            if [ ! -s ${credFile} ]; then
              ${lib.getExe' config.services.crowdsec.package "cscli"} -c ${etcConfig} \
                machines delete ${lib.escapeShellArg config.services.crowdsec.name} \
                >/dev/null 2>&1 || true
            fi
          '')
        ];

        ######################################################################
        # The remediation.
        #
        # nftables mode, which is the default because traefik.nix turns
        # `networking.nftables.enable` on — and that switch was made FOR this,
        # for the reason written beside it there: in iptables mode a firewall
        # reload silently orders nixos-fw's ACCEPT ahead of the drop and every
        # ban becomes inert.
        #
        # `createRulesets` is left at its default of true, so the SET and the
        # `ip saddr @crowdsec-blacklists drop` chain are emitted into
        # `networking.nftables.tables.crowdsec` — declarative, greppable, and
        # re-created by nftables.service — while the bouncer manages only set
        # membership.  Verified in the probe VM:
        #
        #     table ip crowdsec {
        #       set crowdsec-blacklists { type ipv4_addr; flags timeout }
        #       chain crowdsec-chain {
        #         type filter hook input priority filter; policy accept;
        #         ip saddr @crowdsec-blacklists drop
        #       }
        #     }
        #
        # IPv6 IS OFF, and that is standing note SN2 made mechanical rather
        # than promised: the wan entrypoint binds v4 only, the UDM-Pro forward
        # is v4 only, and there is no v6 on this path to remediate.  A
        # crowdsec6 table would be a chain nothing can ever match, which is
        # the kind of rule that later reads as enforcement.  Verified absent
        # in the probe VM.
        ######################################################################
        services.crowdsec-firewall-bouncer = {
          enable = true;
          settings.nftables.ipv6.enabled = false;
        };

        ######################################################################
        # M6: the metrics endpoint, source-restricted to the monitoring
        # container.  Same mechanism and the same reasoning as Traefik's own
        # in this container — see BACKEND BYPASS HARDENING in traefik.nix.
        #
        # `extraInputRules` and not `extraCommands`, because the firewall in
        # here is nftables now.
        ######################################################################
        networking.firewall.extraInputRules = ''
          ip saddr ${monitoringAddr} tcp dport ${toString metricsPort} accept
        '';

        # `cscli` (the module's wrapper) is already in systemPackages.  `nft`
        # is the test plan's instrument and is NOT otherwise installed: a ban
        # that cannot be observed in the ruleset is not a ban (SN3), and
        # `nft list set ip crowdsec crowdsec-blacklists` is how it is
        # observed.  `jq` reads ClientHost out of the JSON access log, which
        # is Q2's proof.
        environment.systemPackages = with pkgs; [ nftables jq ];
      };
  };
}
