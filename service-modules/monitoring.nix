# service-modules/monitoring.nix
#
# @clanarchy/monitoring — Prometheus + Alertmanager + Grafana on ernst, and a
# node_exporter on every machine in the clan.
#
# ── Why this lives in service-modules/ and not machines/ernst/containers/ ────
#
#   Every other container on ernst (jellyfin, arr, traefik) lives in
#   machines/ernst/containers/, and M2b's "the units live with the service, not
#   with the topology" note says to keep it that way.  This one does not, for a
#   reason that is specific to it:
#
#     THE SCRAPE TARGETS ARE DERIVED FROM CLAN ROLE MEMBERSHIP.  M6's whole
#     point is that adding a machine to `roles.client` is the ONLY step needed
#     to monitor it — no hand-maintained target list anywhere.  The role
#     membership is visible only inside a clan.service module's `perInstance`
#     (as the `roles` argument), so the thing that generates the scrape config
#     has to live here.  Splitting the container away from the config it is
#     built from would mean plumbing a derived list through a NixOS option and
#     hoping the two halves stay in step.
#
#   Everything ernst-specific about the container — bridge, VLAN, MAC, state
#   path, domain — is a ROLE SETTING with its value in clan.nix's inventory,
#   which is where per-machine facts belong in this repo.  The file itself
#   names no machine.
#
# ── Two roles ───────────────────────────────────────────────────────────────
#
#   roles.client  every machine.  node_exporter, listening on IPv6, reachable
#                 ONLY from the monitoring stack (see FIREWALL below).
#                 Optionally the zfs and smartctl exporters and node_exporter's
#                 systemd collector — ernst takes all three, the laptops take
#                 none of them.
#   roles.server  ernst.  ONE systemd-nspawn container holding Prometheus,
#                 Alertmanager, alertmanager-ntfy and Grafana.  nspawn because
#                 architecture invariant #1 puts trusted, storage-heavy
#                 workloads there: this one talks to the internet on nobody's
#                 behalf and its TSDB is the only thing here that grows.
#
# ── HOW THE CONTAINER REACHES ANYTHING: two legs, and both are load-bearing ──
#
#   This container is the first on ernst that must reach things which are NOT
#   on VLAN 90, and that is the one genuinely new piece of engineering in M6.
#
#   LEG 1 — eth0: veth on br0, Services VLAN 90, exactly like jellyfin/arr/
#   traefik.  DHCP against a UDM-Pro reservation keyed on the pinned MAC.  This
#   is how TRAEFIK REACHES GRAFANA, and it is the only leg any consumer VLAN
#   ever sees.  Nothing else uses it.
#
#   LEG 2 — mon0: a point-to-point veth to the HOST, on a link-local ULA that
#   never leaves ernst.  It exists because the two things Prometheus must
#   scrape are both unreachable from VLAN 90:
#
#     (a) ernst's OWN exporters.  The host is on VLAN 50 and br0 is a member of
#         VLAN 50 only, so a packet from .14 to 10.0.50.10 hairpins out to the
#         UDM-Pro and back and is subject to the Services→Servers zone pair.
#         M5 lost a round to exactly this shape (its `curl` from ernst timed out
#         after 136 s while a LAN browser worked).  mon0 makes the host one hop
#         away with no gateway, no ZBF rule, and no UniFi round.
#
#     (b) THE REST OF THE FLEET.  miralda, biene and birte are laptops.  They
#         are not on any VLAN ernst can reach; they are on ZeroTier, whose
#         rfc4193 addresses live on the HOST's zt* interface, inside the host's
#         netns.  A container on VLAN 90 has no path to them at all.
#
#         So the host forwards for it: a /128 route per client via mon0, IPv6
#         forwarding on, and SNAT out zt+ (networking.nat, below).  The routes
#         are PER TARGET rather than a prefix — they are derived from the same
#         clan vars the targets are, so the container can reach exactly the
#         machines it is supposed to scrape and nothing else on the mesh.
#
#         The SNAT has a second effect that is not incidental: scrapes arrive at
#         a laptop FROM ERNST'S OWN ZEROTIER ADDRESS, which is precisely the
#         source the client role's firewall rule allows.  One address to
#         permit, fleet-wide, and it is the address clan itself deploys from.
#
#   WHY NOT host networking (privateNetwork = false).  It would make both of
#   these free, and it is what Jellyfin did before M2b.  It would also re-open
#   three host ports on ernst — Grafana, Prometheus, Alertmanager — four PRs
#   after #82 deleted the last one (ledger row L3), and it would put Grafana on
#   VLAN 50 where Traefik cannot reach it without a ZBF rule.  Trading two
#   in-repo routing lines for a UniFi rule and a re-opened host port is the
#   wrong direction.
#
# ── FIREWALL: who may scrape ────────────────────────────────────────────────
#
#   Exporters listen on [::] and are then source-restricted in the client's own
#   firewall to exactly two addresses:
#
#     the server machine's ZeroTier address   (laptops: the SNAT'd source)
#     the monitoring container's mon0 address (ernst: the direct source)
#
#   Both are permitted on every client, uniformly.  The mon0 address is
#   unroutable off ernst, so the rule permitting it on a laptop can never
#   match — it is there so the rule set reads the same everywhere rather than
#   branching on which machine holds the server role.
#
#   ip6tables and NOT the exporters' own `openFirewall`.  That option renders
#   its filter through `ip46tables`, i.e. through the IPv4 binary too, and an
#   IPv6 source address in an iptables rule fails.  extraCommands with an
#   explicit ip6tables is the same escape hatch containers/arr.nix uses, for
#   the same reason: it fails loudly if a rule will not insert.
#
# ── ALERTING: ZED AND PROMETHEUS BOTH, WITH A HARD BOUNDARY ─────────────────
#
#   M6's prompt required a choice: (a) absorb ZFS alerting into Prometheus and
#   retire modules/observability/zfs-ntfy.nix's zedlet, or (b) keep both — and
#   whichever is chosen, two systems must NOT alert on the same pool event.
#
#   THIS IS (b), and the boundary is drawn so the overlap is empty:
#
#     ZED owns POOL AND VDEV STATE.  It is edge-triggered by the kernel, it
#     fires in the same second the transition happens, it runs on every machine
#     in the fleet (commonBase imports it), and — the part that decides this —
#     IT KEEPS WORKING WHEN THE MONITORING CONTAINER IS DOWN.  Prometheus
#     cannot alert on ernst's pool while the thing that would alert is on
#     ernst's pool.
#
#     PROMETHEUS OWNS EVERYTHING ZED CANNOT SEE: capacity, SMART predictions,
#     unreachable hosts, failed units, certificate expiry.  There is
#     DELIBERATELY NO zfs_pool_health ALERT RULE.  The metric is scraped and
#     shown on the dashboard — that is a panel, not a notification.
#
#     THE TWO INTERLOCK, which is what makes (b) better than (a) rather than
#     merely more:  the one thing ZED cannot report is its own death, and
#     `ZedNotRunning` below is a Prometheus rule that fires when zfs-zed is not
#     active.  Prometheus watches the watcher; ZED covers the window in which
#     Prometheus is what has failed.
#
#   BOTH PATHS END AT THE SAME ntfy TOPIC — the clan var
#   `zfs-ntfy.files.url`, generated per machine and already deployed on ernst.
#   No second topic, no second secret, no second thing to mute on a phone.  The
#   staging unit below splits that URL into the baseurl/topic pair
#   alertmanager-ntfy wants; see it for why the URL is not simply passed on.
#
# ── WHAT IS DELIBERATELY NOT HERE ───────────────────────────────────────────
#
#   - No Prometheus web UI route.  Its listener is bound inside the container
#     and never opened; `nixos-container run monitoring -- curl -s
#     localhost:9090/api/v1/...` is the debugging path.  An unauthenticated
#     read of every metric in the house is not a management-network problem,
#     and the same argument containers/traefik.nix makes for the Traefik
#     dashboard applies unchanged.
#   - No blackbox exporter, no per-service dashboards, no rule library.  Six
#     alerts and one dashboard; M6's prompt asks for restraint and the restraint
#     is the feature.
#   - No Loki.  Logs are a different milestone and a much larger disk question.
{
  config,
  lib,
  clanLib,
  directory,
  ...
}:
let
  ############################################################################
  # Ports.  Upstream defaults throughout — restated once so the firewall
  # rules, the scrape config and the Traefik backend in
  # machines/ernst/containers/traefik.nix can all be read against one list.
  ############################################################################
  ports = {
    node        = 9100;   # prometheus-node-exporter
    zfs         = 9134;   # prometheus-zfs-exporter
    smartctl    = 9633;   # prometheus-smartctl-exporter
    traefik     = 8082;   # Traefik's metrics entryPoint (M5, added by M6)
    prometheus  = 9090;
    alertmanager = 9093;
    ntfyBridge  = 8000;   # alertmanager-ntfy, loopback only
    grafana     = 3000;
  };

  ############################################################################
  # The host↔container point-to-point link (leg 2 in the header).
  #
  # A locally-chosen ULA out of fd00::/8.  It is NOT routed, NOT advertised and
  # NOT reachable from anywhere but ernst: the only two addresses on it are the
  # two ends of one veth pair.  /128s on both sides, which is what
  # containers.<n>.extraVeths produces — nixos-containers adds a host route to
  # the far side on each end, so there is no on-link prefix to get wrong.
  #
  # The name mon0 is the veth's name on BOTH sides (nspawn's
  # --network-veth-extra=NAME with a single name), so it appears as mon0 on the
  # host and as mon0 in the container.
  ############################################################################
  monVeth          = "mon0";
  monHostAddr      = "fdca:fe90::1";   # ernst
  monContainerAddr = "fdca:fe90::2";   # the monitoring container

  ############################################################################
  # Reading a peer machine's ZeroTier address out of clan vars.
  #
  # clan-core's zerotier service generates `zerotier-ip-<machine>-<instance>`
  # as a SHARED, NON-SECRET var, so the value is a plain file in the repo at
  # vars/shared/... and any machine's evaluation can read any other machine's.
  # That is what makes "targets are generated, not listed" possible at all:
  # the address is a fact clan already owns, not one this module invents.
  #
  # `default = null` rather than the throw getPublicValue defaults to.  A
  # machine added to roles.client before `clan vars generate` has run for it
  # would otherwise fail EVERY machine's evaluation, including CI's, with an
  # error about a file nobody has heard of.  Null is filtered out below and
  # reported as a warning instead.
  ############################################################################
  ztIpOf = instance: machineName: clanLib.getPublicValue {
    generator = "zerotier-ip-${machineName}-${instance}";
    file      = "ip";
    flake     = directory;
    default   = null;
  };
in
{
  _class = "clan.service";
  manifest.name        = "@clanarchy/monitoring";
  manifest.description = "Prometheus, Alertmanager and Grafana on one machine; node_exporter on all of them.";
  manifest.readme      = builtins.readFile ./monitoring.md;

  ##############################################################################
  # roles.client — every machine in the clan.
  ##############################################################################
  roles.client = {
    description = "Exports host metrics for the monitoring server to scrape.";

    interface.options = {
      alwaysOn = lib.mkOption {
        type        = lib.types.bool;
        default     = false;
        description = ''
          Whether this machine is expected to be reachable at all times.

          ONLY alwaysOn machines get the `InstanceDown` alert.  This is not a
          nicety: miralda, biene and birte are a laptop, a laptop and a
          handheld.  They are asleep, shut, or out of the house for most of any
          given week, so `up == 0` is their NORMAL state and an alert on it
          would fire several times a day, teach everyone to ignore the topic,
          and take the real alerts down with it.

          Their metrics are still collected and still graphed, and every rule
          whose data they produce still applies whenever they ARE up — which,
          with the optional exporters off, means `FilesystemFillingUp`.  What
          this setting drops is exactly one rule, and only for them.
        '';
      };

      exporters = {
        zfs = lib.mkOption {
          type        = lib.types.bool;
          default     = false;
          description = ''
            Run prometheus-zfs-exporter (pool health, capacity, fragmentation).

            Off by default even though miralda and biene are ZFS machines: on a
            laptop the pool is one mirror-less vdev on the disk the machine
            cannot boot without, so "the pool is degraded" and "the laptop is
            dead" are the same event and ZED already reports it.  The exporter
            earns its place on a machine with redundancy to lose.

            This is NOT node_exporter's built-in `zfs` collector, which reports
            ARC statistics from /proc/spl/kstat/zfs and knows nothing about
            pool state.  Different data, different exporter, both useful.
          '';
        };

        smartctl = lib.mkOption {
          type        = lib.types.bool;
          default     = false;
          description = ''
            Run prometheus-smartctl-exporter (per-device SMART, including the
            self-assessment that backs the `SmartFailurePredicted` alert).

            It needs CAP_SYS_RAWIO and CAP_SYS_ADMIN and it re-queries every
            device on a timer, which is a real cost on a battery.  Machines
            with disks worth pre-emptively replacing want it; laptops do not.

            node_exporter has no equivalent collector — its `smartmon` support
            is a textfile-collector shell script, not a built-in — so this is
            the only way to get the data without a cron job writing .prom files.
          '';
        };

        arc = lib.mkOption {
          type        = lib.types.bool;
          default     = false;
          description = ''
            Enable node_exporter's `zfs` collector, which reports ARC
            statistics (hit ratio, size, evictions) from
            /proc/spl/kstat/zfs.

            NOT the same thing as `exporters.zfs` above, despite the names —
            and that is the trap this option exists to make visible.  The
            dedicated zfs_exporter reports POOL state: health, capacity,
            fragmentation.  This collector reports CACHE behaviour.  Neither
            substitutes for the other, and an earlier revision of this module
            said one superseded the other; see the disabledCollectors block.

            Worth having on a storage host, where ARC hit ratio is what
            explains a slow library on a pool that is healthy and disks that
            are not busy.  Not worth having on a laptop, where the answer is
            usually "the lid was shut".
          '';
        };

        systemd = lib.mkOption {
          type        = lib.types.bool;
          default     = false;
          description = ''
            Enable node_exporter's `systemd` collector, which exports
            `node_systemd_unit_state` per unit and backs both the
            `SystemdUnitFailed` and `ZedNotRunning` alerts.

            node_exporter's own collector rather than the standalone
            prometheus-systemd-exporter: it is one process instead of two, one
            port instead of two, and it is enough for the two rules that use
            it.  The standalone exporter's extra per-unit CPU/memory/IO
            accounting is not something anything here alerts on.

            Off by default because it is the one collector with a real idle
            cost — it talks to systemd over D-Bus and enumerates every unit on
            every scrape — and because the series count scales with the unit
            count, which is where a small fleet's cardinality actually goes.
          '';
        };

        containers = lib.mkOption {
          type        = lib.types.bool;
          default     = false;
          description = ''
            Export failed systemd units from inside this machine's
            systemd-nspawn containers, via node_exporter's textfile collector.
            Backs the `ContainerSystemdUnitFailed` alert.

            THE `systemd` COLLECTOR ABOVE DOES NOT COVER THEM. It reads the
            host's own systemd, and every container runs its own init with its
            own unit namespace — so `SystemdUnitFailed` is blind to all of it.
            Which is not theoretical: `soularr.service` in ernst's `arr`
            container failed 1412 times over nine days without ever completing
            a pass, and nothing alerted. It was found by hand, while chasing an
            unrelated host alert.

            Cheap, unlike the `systemd` collector: this exports ONLY failed
            units, so the steady state is zero series. It is a timer on the
            host writing a .prom file, not work done per scrape.
          '';
        };
      };
    };

    perInstance = { settings, roles, ... }: {
      nixosModule = { config, lib, pkgs, ... }:
        let
          # Every address permitted to scrape this machine.  See FIREWALL in
          # the file header for why both entries are present on every machine.
          #
          # The zerotier instance name is read per SERVER MACHINE rather than
          # off `roles.server.settings`: clan-core deprecated role-level
          # settings access in perInstance (it warns at eval and says the
          # attribute goes away next release), and the per-machine path is
          # both supported and more correct — nothing stops two servers being
          # on two different meshes.
          serverMachines = roles.server.machines or { };
          serverZtIps = lib.filter (v: v != null) (lib.mapAttrsToList
            (name: m: ztIpOf m.settings.zerotierInstance name)
            serverMachines);
          scrapeSources = serverZtIps ++ [ monContainerAddr ];

          # Where the container-unit collector drops its .prom file.
          #
          # Under /var/lib and not /run: node_exporter reads whatever is in
          # here at scrape time, and a tmpfs would mean every reboot has a
          # window in which the file is absent and the metric silently missing
          # rather than zero.
          textfileDir = "/var/lib/prometheus-node-exporter-textfile";

          # Failed units inside the nspawn containers, as Prometheus metrics.
          #
          # `systemctl -M <name>` talks to the container's init through
          # machined — no exporter inside each container, no extra port, no
          # per-container firewall rule. Measured at 2 ms per container on
          # ernst, against seven of them.
          #
          # ONLY FAILED UNITS ARE EMITTED. The steady state is an empty file,
          # so this costs nothing in cardinality, and an alert on
          # `== 1` needs no `state=` matcher.
          containerUnitsCollector = pkgs.writeShellApplication {
            name = "clanarchy-container-units-collector";
            runtimeInputs = [ pkgs.systemd pkgs.jq pkgs.gawk pkgs.coreutils ];
            text = ''
              out=${textfileDir}/container-units.prom
              # Written aside and renamed. node_exporter reads this file
              # whenever a scrape lands, and rename(2) is what stops it from
              # ever seeing a half-written one.
              tmp=$(mktemp "$out.XXXXXX")
              trap 'rm -f "$tmp"' EXIT

              {
                echo "# HELP clanarchy_container_systemd_unit_failed A systemd unit inside an nspawn container is in the failed state."
                echo "# TYPE clanarchy_container_systemd_unit_failed gauge"
              } > "$tmp"

              ok=1
              for c in $(machinectl list --no-legend | awk '{print $1}'); do
                # A container that is starting, stopping or wedged answers
                # nothing. Do not treat that as "no failures" — that is the
                # exact shape of a monitoring blind spot — mark the run bad and
                # let the collector-health metric below carry it.
                if units=$(systemctl -M "$c" list-units --state=failed \
                             --no-legend --plain --no-pager -o json 2>/dev/null); then
                  jq -r --arg c "$c" \
                    '.[] | "clanarchy_container_systemd_unit_failed{container=\"\($c)\",name=\"\(.unit)\"} 1"' \
                    <<< "$units" >> "$tmp"
                else
                  ok=0
                fi
              done

              # Who watches the watcher. Same argument as the ZedNotRunning
              # rule: the one thing a collector cannot report is its own
              # failure, so it reports its own success and the absence of that
              # is what alerts.
              {
                echo "# HELP clanarchy_container_units_collector_success Whether the last container-unit collection queried every container successfully."
                echo "# TYPE clanarchy_container_units_collector_success gauge"
                echo "clanarchy_container_units_collector_success $ok"
              } >> "$tmp"

              chmod 0644 "$tmp"
              mv -f "$tmp" "$out"
              trap - EXIT
            '';
          };

          # Ports this machine actually exposes.
          exposedPorts =
            [ ports.node ]
            ++ lib.optional settings.exporters.zfs      ports.zfs
            ++ lib.optional settings.exporters.smartctl ports.smartctl;
        in
        {
          ####################################################################
          # node_exporter.
          #
          # LISTENING ON [::] AND NOT 0.0.0.0, which is the module default.
          # Every scrape of a laptop arrives over ZeroTier, and clan's ZeroTier
          # is rfc4193 IPv6 ONLY — there is no v4 address on that mesh to bind.
          # Linux's default bindv6only=0 means the [::] socket still accepts
          # v4-mapped connections, so ernst's own loopback-ish scrape over mon0
          # and any future v4 path both keep working.
          ####################################################################
          services.prometheus.exporters.node = {
            enable        = true;
            listenAddress = "[::]";
            port          = ports.node;

            # Restriction is done below with an explicit ip6tables rule; see
            # FIREWALL in the file header for why openFirewall cannot be used.
            openFirewall = false;

            enabledCollectors = lib.optional settings.exporters.systemd "systemd";

            # TRIMMED DEFAULTS.  node_exporter is idle between scrapes — it does
            # no background work — so the cost of running it is the cost of one
            # scrape per interval, and these are the default collectors whose
            # per-scrape cost is real and whose output nothing here reads:
            #
            #   arp, btrfs, dmi, edac, entropy, fibrechannel, infiniband,
            #   ipvs, mdadm, nfs, nfsd, nvme, powersupplyclass, rapl,
            #   selinux, softnet, tapestats, thermal_zone, xfs, zfs
            #
            # `hwmon` and `thermal_zone` walk sysfs trees that are large on a
            # laptop; `nvme` and `mdadm` and `fibrechannel` are hardware nobody
            # in this fleet has in the shape those collectors expect; `zfs` is
            # ARC statistics, which the dedicated exporter's pool metrics
            # supersede for every question asked here.
            #
            # `netdev`, `filesystem`, `cpu`, `meminfo`, `loadavg`, `diskstats`,
            # `stat`, `time`, `uname`, `os` are all KEPT — they are what the
            # dashboard and every alert are built from.
            #
            # ── M13 CORRECTS THE `zfs` LINE ABOVE ───────────────────────────
            #
            # It said the dedicated exporter's pool metrics "supersede" this
            # collector for every question asked here.  That was true of the
            # questions M6 asked and is NOT true in general: the two answer
            # different things and neither can stand in for the other.
            #
            #   zfs_exporter          POOL — health, capacity, fragmentation.
            #   node_exporter `zfs`   ARC — hit ratio, size, evictions, read
            #                         from /proc/spl/kstat/zfs.
            #
            # M13 asks for ARC specifically, and on ernst it is worth having:
            # it is the machine with 47 TB behind it, and ARC hit ratio is what
            # explains "why did the library get slow" when the pool is healthy
            # and the disks are not busy.
            #
            # It stays OFF everywhere else.  On a laptop ARC behaviour is
            # decided by whether the lid was shut, which is not a series
            # anybody reads.
            disabledCollectors = [
              "arp" "btrfs" "dmi" "edac" "entropy" "fibrechannel" "infiniband"
              "ipvs" "mdadm" "nfs" "nfsd" "nvme" "powersupplyclass" "rapl"
              "selinux" "softnet" "tapestats" "thermal_zone" "xfs"
            ] ++ lib.optional (!settings.exporters.arc) "zfs";

            # The textfile collector is on by default in node_exporter, but it
            # reads nothing until it is told where to look.
            extraFlags = lib.optional settings.exporters.containers
              "--collector.textfile.directory=${textfileDir}";
          };

          ####################################################################
          # Failed units inside the nspawn containers.
          #
          # A HOST timer, not an exporter per container. The alternative —
          # node_exporter inside each of ernst's seven containers — is seven
          # processes, seven ports and seven firewall rules to answer one
          # question, and each one would then need its own scrape config that
          # nobody would remember to add for container number eight.
          #
          # Every minute rather than on demand, because the textfile collector
          # is a file read: node_exporter has no way to trigger this, so the
          # file has to already be current when a scrape lands. A minute is
          # well inside the 15m `for` on the alert.
          ####################################################################
          systemd.tmpfiles.rules = lib.optional settings.exporters.containers
            "d ${textfileDir} 0755 root root -";

          systemd.services.clanarchy-container-units =
            lib.mkIf settings.exporters.containers {
              description = "Collect failed systemd units from nspawn containers";
              serviceConfig = {
                Type = "oneshot";
                ExecStart = lib.getExe containerUnitsCollector;
                # Talks to machined and to each container's init over D-Bus,
                # and writes one file. It needs no network and no devices.
                PrivateNetwork = true;
                PrivateDevices = true;
                ProtectHome = true;
                ProtectSystem = "strict";
                ReadWritePaths = [ textfileDir ];
                NoNewPrivileges = true;
              };
            };

          systemd.timers.clanarchy-container-units =
            lib.mkIf settings.exporters.containers {
              description = "Collect failed nspawn container units every minute";
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnBootSec = "2m";
                OnUnitActiveSec = "1m";
                # No Persistent: a missed run is worthless, the next one in
                # sixty seconds supersedes it entirely.
              };
            };

          ####################################################################
          # zfs_exporter — pool health, capacity, fragmentation.
          ####################################################################
          services.prometheus.exporters.zfs = lib.mkIf settings.exporters.zfs {
            enable        = true;
            listenAddress = "[::]";
            port          = ports.zfs;
            openFirewall  = false;
          };

          ####################################################################
          # smartctl_exporter — per-device SMART.
          #
          # `devices` left empty so it autodiscovers.  ernst's disks sit behind
          # an HBA and their /dev/sd* names are not stable across a reboot (see
          # docs/incidents/ernst-slot12-drop-2026-08-11.md); a hand-listed
          # device path would monitor whatever landed on that letter this boot,
          # which is worse than useless because it would look like it worked.
          ####################################################################
          services.prometheus.exporters.smartctl = lib.mkIf settings.exporters.smartctl {
            enable        = true;
            listenAddress = "[::]";
            port          = ports.smartctl;
            openFirewall  = false;
          };

          ####################################################################
          # The scrape ACL.
          #
          # One accept per (source, port) pair, appended to nixos-fw.  The
          # firewall's start script emits allowedTCPPorts first, then
          # extraCommands, then the catch-all -j nixos-fw-log-refuse — so these
          # land before the refuse and after everything else, and nothing needs
          # to go in extraStopCommands because the chain is flushed and rebuilt
          # on every start and reload.  Same placement argument as
          # machines/ernst/containers/arr.nix.
          #
          # If `up` is 0 for a machine that is demonstrably awake, this is the
          # first thing to check:
          #   ip6tables -L nixos-fw -n --line-numbers | grep 9100
          ####################################################################
          networking.firewall.extraCommands = lib.concatMapStrings (src:
            lib.concatMapStrings (port: ''
              ip6tables -A nixos-fw -p tcp -s ${src}/128 --dport ${toString port} -j nixos-fw-accept
            '') exposedPorts
          ) scrapeSources;

          warnings = lib.optional (serverZtIps == [ ] && serverMachines != { }) ''
            @clanarchy/monitoring: no ZeroTier address is known for the machine
            holding roles.server, so nothing is permitted to scrape this host.
            Run `clan vars generate <server machine>` and re-deploy.
          '';
        };
    };
  };

  ##############################################################################
  # roles.server — the machine that runs the stack.
  ##############################################################################
  roles.server = {
    description = "Runs Prometheus, Alertmanager and Grafana in one nspawn container.";

    interface.options = {
      bridge = lib.mkOption {
        type        = lib.types.str;
        default     = "br0";
        description = "VLAN-filtering bridge the container's eth0 is a port on.";
      };

      vlan = lib.mkOption {
        type        = lib.types.int;
        default     = 90;
        description = "VLAN id for the container's eth0 (the Services VLAN on ernst).";
      };

      mac = lib.mkOption {
        type        = lib.types.str;
        example     = "02:00:00:90:00:06";
        description = ''
          Guest-side MAC for the container's eth0, and the address the DHCP
          reservation keys on.  Never the host-side vb-* veth.

          Allocated in the table in machines/ernst/networking.nix.
        '';
      };

      resolver = lib.mkOption {
        type        = lib.types.str;
        default     = "10.0.5.3";
        description = "Resolver for the container.  Declared, not inherited from DHCP.";
      };

      searchDomain = lib.mkOption {
        type        = lib.types.str;
        default     = "skynet.lan";
        description = "Bare-hostname search suffix inside the container.";
      };

      stateDir = lib.mkOption {
        type        = lib.types.path;
        default     = "/srv/state/monitoring";
        description = ''
          Host path holding the Prometheus TSDB and Grafana's database.  Must
          be on a filesystem that does NOT roll back (invariant #7).
        '';
      };

      domain = lib.mkOption {
        type        = lib.types.str;
        default     = "goclan.org";
        description = "Public zone; Grafana is served at grafana.<domain> through Traefik.";
      };

      proxyAddress = lib.mkOption {
        type        = lib.types.str;
        example     = "10.0.90.12";
        description = ''
          The reverse proxy's address on the Services VLAN.  The ONLY source
          permitted to reach Grafana's port, and the address Traefik's metrics
          endpoint is scraped at.  Backend bypass hardening, mechanism (a) —
          the argument is in machines/ernst/containers/traefik.nix.
        '';
      };

      # ── M13: the media-stack targets ──────────────────────────────────────
      #
      # FOUR MORE SCRAPE TARGETS, and they share one shape deliberately: an
      # `address` that defaults to "" and disables the job when left empty.
      # That is the authelia option's pattern below, and it is what keeps this
      # a clan-service module that HAPPENS to be pointed at a media stack on
      # ernst rather than one that requires one — the laptops hold this role's
      # `client` side and must never need to know these exist.
      #
      # Each of them is a plain HTTP endpoint on a VLAN-90 address reached by a
      # single layer-2 hop inside br0 on this host, exactly like the traefik
      # and authelia jobs.  None of them gets an alert rule, for the reason
      # those two do not either: `InstanceDown` keys on always_on="true", which
      # is a label only the MACHINE targets carry.  What these buy is the
      # dashboard and the history.
      mediaStack = {
        arrAddress = lib.mkOption {
          type        = lib.types.str;
          default     = "";
          example     = "10.0.90.13";
          description = ''
            Address of the *arr container on the Services VLAN.  Empty disables
            the `scraparr` job.

            Scraparr is ONE exporter covering Sonarr, Radarr, Prowlarr, Bazarr
            and Jellyseerr — see the rejection of Exportarr recorded in
            machines/ernst/containers/arr.nix.  Its port must additionally be
            source-restricted to THIS container's address on the far end;
            adding the target here alone produces a job that times out.
          '';
        };

        scraparrPort = lib.mkOption {
          type        = lib.types.port;
          default     = 7100;
          description = "Scraparr's listener (its own upstream default).";
        };

        jellyfinAddress = lib.mkOption {
          type        = lib.types.str;
          default     = "";
          example     = "10.0.90.10";
          description = ''
            Address of the Jellyfin container on the Services VLAN.  Empty
            disables the `jellyfin` job.

            NO EXPORTER.  Jellyfin serves Prometheus metrics natively — 10.11.x
            ships prometheus-net — so this scrapes the application directly.
            Do not add an exporter for it.

            The endpoint is gated on `EnableMetrics` in Jellyfin's own
            system.xml, which is a dashboard setting and therefore a manual
            step; until it is on, this job reports up=0.  See the note beside
            services.jellyfin in machines/ernst/containers/jellyfin.nix.
          '';
        };

        jellyfinPort = lib.mkOption {
          type        = lib.types.port;
          default     = 8096;
          description = ''
            Jellyfin's HTTP port.  Metrics share it with the media API rather
            than getting a listener of their own, which is why permitting this
            scrape necessarily permits more than a scrape — stated plainly in
            the firewall block of containers/jellyfin.nix.
          '';
        };

        qbittorrentAddress = lib.mkOption {
          type        = lib.types.str;
          default     = "";
          example     = "10.0.90.11";
          description = ''
            Address of the qBittorrent guest on the Services VLAN.  Empty
            disables the `qbittorrent` job.

            NOTE WHERE THIS ONE LIVES: it is inside M3's VPN microvm — a guest
            with its own kernel, not a container — so the exporter runs behind
            the same killswitch as the client it reads.  The scrape path is
            nonetheless the same VLAN-90 layer-2 hop the *arr use.
          '';
        };

        qbittorrentExporterPort = lib.mkOption {
          type        = lib.types.port;
          default     = 8000;
          description = "prometheus-qbittorrent-exporter's listener (its own default).";
        };

        # ── THERE IS NO OLLAMA OPTION HERE, AND IT IS NOT AN OVERSIGHT ──────
        #
        # M13's brief says "ADD AN OLLAMA TARGET", so that it appears `up` and
        # reports VRAM before M15's GPU arbitration needs the history.  The
        # premise does not hold, and it was checked on the running machine
        # rather than reasoned about:
        #
        #   ernst, 2026-08-26, ollama 0.32.3
        #     GET http://127.0.0.1:11434/metrics    404
        #     GET http://127.0.0.1:11434/api/tags   200
        #
        # OLLAMA SERVES NO PROMETHEUS ENDPOINT.  A scrape job pointed at it
        # would report up=0 forever, which is worse than no job: it is an
        # alert-shaped object that can never go green, on a dashboard that is
        # supposed to make red mean something.
        #
        # TWO FURTHER REASONS NOT TO PAPER OVER IT WITH AN EXPORTER HERE:
        #
        #   1. THE WANTED SERIES IS THE GPU'S, NOT OLLAMA'S.  M15 has to
        #      arbitrate between Ollama, the gamescope HTPC session and Tdarr
        #      over ONE 24 GiB card.  Ollama's own view of its allocation
        #      cannot see the other two, so even a working Ollama exporter
        #      would answer a narrower question than the one being asked.
        #   2. NOTHING IS PACKAGED.  ernst's pin has
        #      prometheus-nvidia-gpu-exporter and no AMD equivalent — no
        #      amd-smi-exporter, no rocm-smi-exporter — and the card is a
        #      Navi 31.  So this is a hand-rolled derivation, i.e. a third one
        #      in a milestone that already has two.
        #
        # HANDED TO M15 WITH THE MEASUREMENT ATTACHED, rather than dropped.
        # M11's numbers are what make the history worth having at all: 22482
        # MiB at 64k with q8_0 against a 24560 MiB card, i.e. 2078 MiB of
        # headroom.  M15 should start by packaging an AMD SMI exporter and
        # scraping the CARD, and it will then cover all three claimants at
        # once.
      };

      # ── M7: the identity provider ─────────────────────────────────────────
      #
      # Two INDEPENDENT things behind one attribute, because they are one box:
      # a scrape target, and Grafana's OIDC issuer.  Either can be left off.
      #
      # The module knows nothing about Authelia beyond these values — no
      # generator name is hard-wired, no address is assumed — so this stays a
      # clan service module that happens to be pointed at one on ernst rather
      # than one that requires it.
      authelia = {
        address = lib.mkOption {
          type        = lib.types.str;
          default     = "";
          example     = "10.0.90.15";
          description = ''
            Address of the Authelia container on the Services VLAN.  Empty
            disables the scrape job entirely.

            Worth scraping specifically because of what M7 did: an Authelia
            that is down is every admin UI in the house being down, and an
            identity provider nobody watches is the thing that fails silently.
          '';
        };

        metricsPort = lib.mkOption {
          type        = lib.types.port;
          default     = 9959;
          description = "Authelia's telemetry listener (its own upstream default).";
        };

        oidc = {
          enable = lib.mkOption {
            type        = lib.types.bool;
            default     = false;
            description = ''
              Point Grafana's generic_oauth provider at an OIDC issuer.

              Grafana's LOCAL admin account stays enabled either way — see the
              break-glass note beside services.grafana below.  This adds a
              second way in; it does not remove the first.
            '';
          };

          issuerUrl = lib.mkOption {
            type        = lib.types.str;
            default     = "";
            example     = "https://auth.goclan.org";
            description = "Issuer base URL, no trailing slash.  Required when oidc.enable is set.";
          };

          clientId = lib.mkOption {
            type        = lib.types.str;
            default     = "grafana";
            description = "OIDC client id.  Must match the client block on the issuer.";
          };

          secretGenerator = lib.mkOption {
            type        = lib.types.str;
            default     = "authelia-oidc";
            description = ''
              Name of the clan vars generator holding the client secret, and
              the file inside it, as `secretFile`.

              Named rather than imported: the generator is owned by whichever
              module declares the identity provider (on ernst that is
              machines/ernst/containers/authelia.nix), and it emits the
              PLAINTEXT half here and the hashed half there in one run, so the
              two cannot drift.
            '';
          };

          secretFile = lib.mkOption {
            type    = lib.types.str;
            default = "grafana-client-secret";
            description = "File name inside secretGenerator holding the plaintext client secret.";
          };

          adminGroup = lib.mkOption {
            type        = lib.types.str;
            default     = "admins";
            description = ''
              Group in the `groups` claim that maps to Grafana's Admin role.
              Everyone else who gets through forward-auth lands on Viewer.
            '';
          };
        };
      };

      zerotierInstance = lib.mkOption {
        type        = lib.types.str;
        default     = "zerotier";
        description = ''
          Name of the clan zerotier inventory instance.  It is part of the
          generator name the client addresses are read from
          (`zerotier-ip-<machine>-<instance>`), so a renamed instance silently
          produces an empty target list without it.
        '';
      };

      retentionTime = lib.mkOption {
        type        = lib.types.str;
        default     = "400d";
        description = ''
          Prometheus TSDB retention.  See the disk-math comment in the module
          for how this number was arrived at — briefly: disk is not the binding
          constraint by four orders of magnitude, so it is chosen from
          usefulness (13 months, so a year-over-year comparison always has last
          year's same month in window) and backstopped by a size cap.
        '';
      };

      retentionSize = lib.mkOption {
        type        = lib.types.str;
        default     = "64GB";
        description = ''
          Hard cap on TSDB size, ~8x the estimate.  This is not a capacity
          plan; it is the thing that stops a cardinality explosion from filling
          the dataset that also holds every *arr database.
        '';
      };

      scrapeInterval = lib.mkOption {
        type        = lib.types.str;
        default     = "60s";
        description = ''
          Global scrape interval.  60s and not the 15s Prometheus defaults to:
          three of the four machines are battery-powered, sample volume and
          therefore retention scale linearly with it, and nothing alerted on
          here resolves faster than minutes.
        '';
      };
    };

    perInstance = { settings, roles, machine, ... }: {
      nixosModule = { config, lib, pkgs, ... }:
        let
          ##################################################################
          # Identity on the Services VLAN.
          ##################################################################
          vethName = "vb-monitoring";

          # Numeric ids, continuing the 3000-range family established by
          # containers/arr.nix (3002–3004) and containers/traefik.nix (3005).
          # nspawn passes uids and gids through unmapped, so an id chosen in
          # here is an id on zdata — and stateDir is on zdata.  Add a row to
          # the table in machines/ernst/networking.nix for any new one.
          #
          # NOT in group media, either of them.  Neither service has any
          # business holding a handle to the library.
          prometheusUid = 3006;
          prometheusGid = 3006;
          grafanaUid    = 3007;
          grafanaGid    = 3007;

          ##################################################################
          # Targets, generated from clan role membership.
          ##################################################################
          clientRole   = roles.client or { machines = { }; };
          clientNames  = lib.attrNames clientRole.machines;

          # The machine holding this role scrapes ITSELF over mon0, and every
          # other client over ZeroTier.  Two different addresses, one rule:
          # "how do I get to that machine from inside this container".
          addrOf = name:
            if name == machine.name then monHostAddr
            else ztIpOf settings.zerotierInstance name;

          # Machines whose address could not be resolved are dropped rather
          # than throwing — see ztIpOf.  They are reported in `warnings`.
          resolvable   = lib.filter (n: addrOf n != null) clientNames;
          unresolvable = lib.filter (n: addrOf n == null) clientNames;

          settingsOf = name: clientRole.machines.${name}.settings;

          # An IPv6 literal has to be bracketed in a Prometheus target.
          targetFor = name: port:
            let a = addrOf name; in "[${a}]:${toString port}";

          # One static_config per machine so each carries its own labels.
          # `instance` is set explicitly: Prometheus would otherwise derive it
          # from __address__, and a dashboard legend full of
          # [fdda:106a:...:711f]:9100 is unreadable and changes if a machine's
          # ZeroTier identity is ever regenerated.
          staticFor = name: port: {
            targets = [ (targetFor name port) ];
            labels = {
              instance  = name;
              always_on = if (settingsOf name).alwaysOn then "true" else "false";
            };
          };

          # Machines that run a given optional exporter.
          withExporter = which: lib.filter (n: (settingsOf n).exporters.${which}) resolvable;

          ##################################################################
          # Secrets staging (host side).
          #
          # Same shape and the same reasoning as containers/traefik.nix: a
          # directory WE own, rewritten in place, rather than a bind of
          # /run/secrets — which is a symlink to a per-generation directory
          # that is REPLACED on every deploy, so an nspawn bind established at
          # container start would keep exposing a deleted generation.
          #
          # The directory is 0711 root:root: traversable by anyone, listable by
          # nobody.  It holds two files with DIFFERENT consumers and therefore
          # different owners, which is the thing to get right here:
          #
          #   ntfy.yml              0400 root:root  — read by PID 1 as a
          #                         systemd credential, before it drops to the
          #                         alertmanager-ntfy dynamic user.
          #   grafana-password      0400 uid 3007   — read by GRAFANA ITSELF,
          #                         unprivileged, via $__file{}.
          #
          # PR #84 shipped the second shape broken once: a file the
          # unprivileged consumer could read, inside a directory it could not
          # traverse.  0711 on the directory is what prevents the repeat.
          ##################################################################
          secretsDir     = "/run/monitoring-secrets";
          ntfyConfFile   = "${secretsDir}/ntfy.yml";
          grafanaPwFile  = "${secretsDir}/grafana-admin-password";
          grafanaKeyFile = "${secretsDir}/grafana-secret-key";

          # Guarded rather than selected directly.  Without the guard, a
          # machine holding this role with `clanarchy.zfs.ntfy.enable = false`
          # fails evaluation on a missing attribute, and the error names a
          # generator rather than the option that was never turned on — so the
          # assertion below would never get the chance to say the useful thing.
          ntfyUrlFile =
            if config.clan.core.vars.generators ? zfs-ntfy
            then config.clan.core.vars.generators.zfs-ntfy.files."url".path
            else "/no-such-path";

          grafanaGen = config.clan.core.vars.generators.monitoring-grafana;

          # ── M7: Grafana's OIDC client secret ────────────────────────────
          #
          # Guarded the same way ntfyUrlFile is, and for the same reason: a
          # machine that has not enabled OIDC must not fail evaluation on a
          # generator that legitimately does not exist there.  The `enable`
          # flag is the thing that decides, not the presence of an attribute.
          oidc            = settings.authelia.oidc;
          grafanaOidcFile = "${secretsDir}/grafana-oidc-client-secret";
          oidcSecretPath  =
            if oidc.enable
            then config.clan.core.vars.generators.${oidc.secretGenerator}.files.${oidc.secretFile}.path
            else "/no-such-path";

          # Optional ntfy bearer token, from the same module and the same
          # opt-in that gates the zedlet's — one switch, both publishers, so
          # they cannot end up disagreeing about whether the topic is
          # authenticated.
          ntfyAuth      = config.clanarchy.zfs.ntfy.auth.enable;
          ntfyTokenFile =
            if ntfyAuth
            then config.clan.core.vars.generators.zfs-ntfy-token.files."token".path
            else "/no-such-path";

          ##################################################################
          # The single dashboard, as code.
          #
          # Grafana's file provider wants a DIRECTORY, so the one JSON file is
          # wrapped in one.  Adding a second dashboard means adding a second
          # cp — which is deliberately slightly annoying, because "exactly one
          # dashboard" is a decision and not an accident.
          ##################################################################
          dashboardDir = pkgs.runCommand "clanarchy-grafana-dashboards" { } ''
            mkdir -p $out
            cp ${./monitoring-dashboard.json} $out/clanarchy-fleet.json
          '';
        in
        lib.mkMerge [
        {
          ####################################################################
          # It is an error to hold this role without the ntfy var.
          #
          # Without it the staging unit below evaluates
          # `files."url".path` to the literal "/no-such-path" and the failure
          # surfaces at deploy time as a container that will not start, with
          # nothing in the message about zfs-ntfy.  Say it at eval time
          # instead.
          ####################################################################
          assertions = [
            {
              assertion = config.clanarchy.zfs.ntfy.enable;
              message = ''
                @clanarchy/monitoring's server role reuses the ntfy topic from
                modules/observability/zfs-ntfy.nix — one alerting path, not two.
                Set `clanarchy.zfs.ntfy.enable = true` on this machine and run
                `clan vars generate <machine>`.
              '';
            }
          ];

          warnings = lib.optional (unresolvable != [ ]) ''
            @clanarchy/monitoring: no ZeroTier address on record for
            ${lib.concatStringsSep ", " unresolvable} — they hold roles.client
            but are NOT being scraped.  Run `clan vars generate <machine>` for
            each, commit vars/shared/, and re-deploy this machine.
          '';

          ####################################################################
          # State on zdata.  0700 and owned by the service, exactly like
          # /srv/state/{jellyfin,sonarr,traefik}.
          #
          # NUMERIC ids on purpose: prometheus and grafana are CONTAINER users
          # and the host has no matching passwd entry.  Same shape
          # containers/arr.nix uses for uid 3002.
          ####################################################################
          systemd.tmpfiles.rules = [
            "d ${settings.stateDir}            0755 root root -"
            "d ${settings.stateDir}/prometheus 0700 ${toString prometheusUid} ${toString prometheusGid} -"
            "d ${settings.stateDir}/grafana    0700 ${toString grafanaUid}    ${toString grafanaGid}    -"
          ];

          ####################################################################
          # Stage both secrets.
          #
          # GENERATE BEFORE YOU DEPLOY, for the reason containers/traefik.nix
          # spells out: clan-core cannot know a sops secret's path until the
          # secret exists, so a deploy that runs before `clan vars generate`
          # bakes "/no-such-path" into this script and produces a system whose
          # staging unit can never succeed however often it is restarted.  The
          # failure is at least fail-closed — this unit fails, the container
          # never starts, and there is no monitoring rather than monitoring
          # that silently never alerts.
          #
          # ROTATING EITHER SECRET needs a restart, not just a deploy: if this
          # unit's text is unchanged systemd will not re-run it when the
          # underlying sops file changes.  After `clan vars generate`:
          #     systemctl restart monitoring-secrets container@monitoring
          ####################################################################
          systemd.services.monitoring-secrets = {
            description = "Stage the ntfy topic and Grafana admin password for container@monitoring";
            after       = [ "local-fs.target" ];
            before      = [ "container@monitoring.service" ];
            requiredBy  = [ "container@monitoring.service" ];
            serviceConfig = {
              Type            = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              set -euo pipefail

              install -d -m 0711 -o root -g root ${secretsDir}

              # ── ntfy ────────────────────────────────────────────────────
              #
              # zfs-ntfy stores ONE value, and it is EITHER a full topic URL
              # OR a bare topic — the prompt asks for a URL and in the same
              # sentence suggests `openssl rand -hex 12`, which is a topic.
              # ernst's is a bare topic.
              #
              # alertmanager-ntfy needs the two halves separately (baseurl for
              # the instance, topic for the channel), so they are split with
              # THE ZEDLET'S OWN SPLITTER — not a second copy of the logic
              # here.  Two publishers that disagree about how to read one
              # value is exactly how "one alerting path" quietly becomes two,
              # and this milestone's ZED/Prometheus split is built on them
              # landing on the same topic.
              #
              # A second clan var was the obvious alternative and is worse: it
              # would be a second thing to keep in step, with nothing checking
              # that it agrees.
              #
              # This FAILS THE UNIT on a value it cannot read, which stops the
              # container — deliberate.  alertmanager-ntfy with an empty topic
              # starts fine and posts into the void, and a monitoring stack
              # that silently cannot notify is worse than one that is
              # obviously down.  It is also how the bare-topic shape was found
              # at all: the zedlet had been failing on it in silence.
              if ! split=$(${config.clanarchy.zfs.ntfy.splitScript} ${ntfyUrlFile}); then
                echo "cannot read a base URL and topic out of the zfs-ntfy var" >&2
                exit 1
              fi
              base=''${split%% *}
              topic=''${split##* }

              # Built line by line rather than with a heredoc, because the
              # optional token has to come out of a FILE and never out of a
              # shell variable: this unit runs as root and its environment is
              # inherited by everything it forks.  `tr` writes the value
              # straight into the redirect.
              umask 077
              {
                echo "ntfy:"
                echo "  baseurl: $base"
                ${lib.optionalString ntfyAuth ''
                echo "  auth:"
                printf '    token: '
                tr -d '[:space:]' < ${ntfyTokenFile}
                echo
                ''}
                echo "  notification:"
                echo "    topic: $topic"
              } > ${ntfyConfFile}.new
              chown root:root ${ntfyConfFile}.new
              chmod 0400 ${ntfyConfFile}.new
              mv -f ${ntfyConfFile}.new ${ntfyConfFile}

              # ── Grafana admin password ──────────────────────────────────
              #
              # Owned by the GRAFANA uid, unlike everything else here: grafana
              # reads it itself, unprivileged, through the $__file{} provider
              # in its own config.  0400 with the right owner, inside a 0711
              # directory — see the secretsDir comment.
              install -m 0400 -o ${toString grafanaUid} -g ${toString grafanaGid} \
                ${grafanaGen.files."admin-password".path} ${grafanaPwFile}

              # ── Grafana secret_key ──────────────────────────────────────
              #
              # Same ownership, and it matters more than the password does:
              # this key encrypts the datasource credentials and any API
              # tokens in grafana.db.  Change it and every stored secret
              # becomes undecryptable — which is why it is generated ONCE and
              # never rotated by a deploy.  See the generator.
              install -m 0400 -o ${toString grafanaUid} -g ${toString grafanaGid} \
                ${grafanaGen.files."secret-key".path} ${grafanaKeyFile}

              ${lib.optionalString oidc.enable ''
              # ── M7: the OIDC client secret ──────────────────────────────
              #
              # Same ownership as the two above — Grafana reads it itself
              # through $__file{}, unprivileged.  Its counterpart, the hashed
              # form the issuer stores, is staged on the other side of this
              # machine by machines/ernst/containers/authelia.nix out of the
              # SAME generator run.
              install -m 0400 -o ${toString grafanaUid} -g ${toString grafanaGid} \
                ${oidcSecretPath} ${grafanaOidcFile}
              ''}
            '';
          };

          ####################################################################
          # Host side of the Services-VLAN veth — leg 1.
          #
          # Copied from containers/traefik.nix, which copied it from
          # containers/jellyfin.nix ("Networking — v2"), the working version of
          # this pattern.  KeepMaster rather than Bridge= because nspawn
          # creates AND enslaves this link itself; no L3 of its own because a
          # bridge port carries none; "enslaved" rather than "routable" because
          # a bridge port never reaches routable and waiting for it hangs boot.
          #
          # There is deliberately NO networking.firewall.allowedTCPPorts here.
          # Grafana's port is opened inside the container's own netns; on the
          # host it is not a port at all.
          ####################################################################
          systemd.network.networks."60-${vethName}" = {
            matchConfig.Name = vethName;
            networkConfig = {
              KeepMaster          = true;
              LinkLocalAddressing = "no";
              IPv6AcceptRA        = false;
            };
            bridgeVLANs = [ {
              VLAN           = settings.vlan;
              PVID           = settings.vlan;
              EgressUntagged = settings.vlan;
            } ];
            linkConfig.RequiredForOnline = "enslaved";
          };

          # Re-assert the VLAN after nspawn has created the veth.  Same real
          # race as vb-jellyfin / vb-arr / vb-traefik: networkd applies
          # [BridgeVLAN] only once it observes the link's master, and nspawn
          # sets that master out of band.  Idempotent, and "-" prefixed so a
          # backstop cannot become a new failure mode.
          #
          # `bridge vlan show dev vb-monitoring` remains the check.
          systemd.services."container@monitoring".serviceConfig.ExecStartPost = [
            "-${pkgs.iproute2}/bin/bridge vlan add dev ${vethName} vid ${toString settings.vlan} pvid untagged"
          ];

          ####################################################################
          # Leg 2's host half: forward and SNAT the container onto ZeroTier.
          #
          # WHAT THIS DOES:  a packet from ${monContainerAddr} to a client's
          # ZeroTier address arrives on mon0, is forwarded (hence the sysctl
          # networking.nat sets), leaves on zt*, and has its source rewritten
          # to ernst's own ZeroTier address.  Without the rewrite the reply
          # would be addressed to a ULA the laptop has never heard of and would
          # be routed out of its default interface into nothing.
          #
          # externalInterface = "zt+", a WILDCARD, because ZeroTier names its
          # interface after the network id (ztXXXXXXXX) and that name is not
          # known here.  iptables accepts the "+" suffix; nothing else on this
          # host is named zt*.
          #
          # SCOPE:  internalIPv6s is a single /128 and there are no
          # internalInterfaces, so this NATs exactly one address and nothing
          # else.  IPv4 NAT is inert — no internalIPs, no forwardPorts.
          #
          # SIDE EFFECT WORTH KNOWING: net.ipv6.conf.all.forwarding = 1 makes
          # the kernel stop accepting router advertisements by default.  That
          # is a no-op on ernst, which already sets IPv6AcceptRA = false on br0
          # and on the trunk (machines/ernst/networking.nix) and holds no
          # RA-derived address anywhere.  It would NOT be a no-op on a machine
          # that gets its IPv6 from RA — do not copy this block to one.
          ####################################################################
          networking.nat = {
            enable            = true;
            enableIPv6        = true;
            externalInterface = "zt+";
            internalIPv6s     = [ "${monContainerAddr}/128" ];
          };

          # KEEP NetworkManager OFF mon0, and this one is easy to miss.
          #
          # nixpkgs ships a udev rule marking `v[eb]-*` as NM_UNMANAGED
          # whenever NetworkManager is enabled, which is why no container veth
          # in this repo has ever needed listing (see the note in
          # machines/ernst/networking.nix).  `mon0` does NOT match that glob.
          #
          # On a host running BOTH networkd and NetworkManager — which ernst
          # does, via the htpc role pulling in kde.nix — an unlisted,
          # unmatched link is exactly what NM auto-connects to: it would create
          # a profile, start DHCP on a point-to-point ULA link with no server
          # on it, and can strip the address the container's start script put
          # there.  The symptom would be every scrape failing at once, some
          # minutes after boot, with the config unchanged.
          #
          # This appends to the list in machines/ernst/networking.nix rather
          # than replacing it.
          networking.networkmanager.unmanaged = [ "interface-name:${monVeth}" ];

          ####################################################################
          # Vars generator: Grafana's admin password.
          #
          # PROMPTED, like go-password and traefik-acme, rather than generated:
          # a human types this into a login form, so a value nobody chose and
          # nobody can remember has to be looked up out of sops every time.
          #
          # It stays relevant after M7.  Authelia will front the ROUTE, but
          # Grafana's local admin is the account that still works when the
          # identity provider is the thing that is broken — which is exactly
          # when someone needs to look at a dashboard.
          ####################################################################
          # ── Make a rotated ntfy secret re-stage itself ──────────────────
          #
          # The 2026-08-24 rotation needed a manual
          # `systemctl restart monitoring-secrets container@monitoring`,
          # and the reason it is easy to forget is that nothing looks wrong
          # without it: the staging unit's SCRIPT is unchanged (it embeds the
          # sops PATH, not the contents), so systemd sees an unchanged unit,
          # does not re-run it, and the previous topic stays staged in /run
          # while the deploy reports success.  Alerts then keep going to the
          # topic that was just rotated away from.
          #
          # BOTH units are listed and both are needed.  Restarting
          # container@monitoring alone would not re-run the staging oneshot
          # (RemainAfterExit=true, already active); restarting the staging
          # oneshot alone would rewrite /run while alertmanager-ntfy keeps the
          # copy it loaded as a systemd credential at start.  systemd orders
          # them correctly on its own through the existing Before=.
          #
          # Declared HERE and not in modules/observability/zfs-ntfy.nix
          # because monitoring-secrets exists only on the machine holding this
          # role — naming it fleet-wide would point sops-nix at a unit that is
          # absent on three machines out of four.
          #
          # NOTE THE SHAPE of the token half: `mkIf` wraps a CONFIG BLOCK, not
          # a value.  Written the obvious way —
          #
          #   generators.zfs-ntfy-token.files."token".restartUnits =
          #     lib.mkIf ntfyAuth [ … ];
          #
          # — the *value* is conditional but the *attribute path* is not, so
          # the module system materialises `generators.zfs-ntfy-token` with its
          # defaults even when auth is off.  That is enough to make clan
          # believe the generator exists, and `clan vars check` then reports
          #
          #   Secret var 'token' for service 'zfs-ntfy-token' … is missing
          #
          # on a machine that has deliberately not enabled auth.  Measured
          # 2026-08-24.  Guard the definition, not the value.
          clan.core.vars.generators.zfs-ntfy.files."url".restartUnits = [
            "monitoring-secrets.service"
            "container@monitoring.service"
          ];

          # ── AND Grafana's secret_key, which is NOT prompted ─────────────
          #
          # nixpkgs 26.05 removed the compiled-in default for
          # `security.secret_key` and asserts on a config that does not set
          # one, which is the right call: it is the key grafana.db's stored
          # datasource credentials and API tokens are encrypted with.
          #
          # GENERATED, not prompted, because nobody ever types it — and
          # GENERATED ONCE, because changing it makes every secret already in
          # the database undecryptable.  There is no supported rotation; the
          # upstream assertion message points at a third-party re-encryption
          # tool.  clan vars only runs a generator when its output is missing,
          # so this is stable for the life of the machine unless someone
          # deletes it deliberately.
          clan.core.vars.generators.monitoring-grafana = {
            files."admin-password".secret = true;
            files."secret-key".secret     = true;

            prompts."admin-password" = {
              description = "Grafana admin password (user: admin) at grafana.${settings.domain}";
              type        = "hidden";
            };

            runtimeInputs = [ pkgs.coreutils ];

            script = ''
              set -euo pipefail

              pw=$(tr -d '\n' < "$prompts/admin-password")
              if [ "''${#pw}" -lt 12 ]; then
                echo "  ✗ too short — Grafana's admin account is reachable from every management VLAN" >&2
                exit 1
              fi
              printf '%s' "$pw" > "$out/admin-password"

              # base64 of 32 random bytes, newline stripped: Grafana reads the
              # file verbatim and a trailing newline becomes part of the key.
              head -c 32 /dev/urandom | base64 | tr -d '\n' > "$out/secret-key"
            '';
          };

          ####################################################################
          # The container.
          ####################################################################
          containers.monitoring = {
            autoStart = true;
            ephemeral = false;

            # Leg 1 — own netns, own L2 identity on the Services VLAN.
            privateNetwork  = true;
            hostBridge      = settings.bridge;
            localMacAddress = settings.mac;

            # Leg 2 — the point-to-point link to the host.  /128 on each end;
            # nixos-containers adds the matching host route on both sides, so
            # there is no prefix and no on-link assumption to get wrong.
            extraVeths.${monVeth} = {
              hostAddress6  = monHostAddr;
              localAddress6 = monContainerAddr;
            };

            bindMounts = {
              "/var/lib/prometheus2" = {
                hostPath   = "${settings.stateDir}/prometheus";
                isReadOnly = false;
              };
              "/var/lib/grafana" = {
                hostPath   = "${settings.stateDir}/grafana";
                isReadOnly = false;
              };
              "${secretsDir}" = {
                hostPath   = secretsDir;
                isReadOnly = true;
              };
            };

            ##################################################################
            # NixOS config for the container's own root filesystem.
            ##################################################################
            config = { config, pkgs, lib, ... }: {
              system.stateVersion = "26.05";

              # Matches the host.  Every alert timestamp, every "when did this
              # start firing", and every dashboard axis is rendered in local
              # time; a container that silently defaults to UTC makes all of
              # them a two-hour question.  Same call as containers/arr.nix.
              time.timeZone = "Europe/Berlin";

              ################################################################
              # Networking.
              ################################################################
              networking.useHostResolvConf = false;
              networking.useNetworkd       = true;
              services.resolved.enable     = true;

              # eth0 — the Services VLAN.  DHCP against the UDM-Pro
              # reservation; resolver DECLARED, not inherited, so a future
              # change to the Services network's DHCP options cannot silently
              # move this container off Technitium.
              systemd.network.networks."10-eth0" = {
                matchConfig.Name = "eth0";
                networkConfig = {
                  DHCP         = "ipv4";
                  DNS          = settings.resolver;
                  Domains      = "~. ${settings.searchDomain}";
                  IPv6AcceptRA = false;
                };
                dhcpV4Config = {
                  UseDNS     = false;
                  UseDomains = false;
                };
                linkConfig.RequiredForOnline = "routable";
              };

              # mon0 — the host link, and every scrape route.
              #
              # EVERYTHING IS DECLARED HERE even though container-init already
              # assigned the address and the host route: networkd removes
              # addresses and routes it does not know about once it takes a
              # link over.  Restating them is what stops the link being
              # configured and then quietly stripped a second later.
              #
              # The /128 host route needs Scope = "link" — with /128s on both
              # ends there is no on-link prefix, so the neighbour is not
              # implicitly reachable.
              #
              # ONE /128 ROUTE PER SCRAPE TARGET, rather than the ZeroTier /88.
              # The addresses come from the same clan vars the targets do, so
              # this costs nothing to maintain and buys least privilege: the
              # container can reach the machines it scrapes and no other node
              # on the mesh.
              systemd.network.networks."20-${monVeth}" = {
                matchConfig.Name = monVeth;
                address = [ "${monContainerAddr}/128" ];
                routes = [
                  { Destination = "${monHostAddr}/128"; Scope = "link"; }
                ] ++ map (name: {
                  Destination = "${addrOf name}/128";
                  Gateway     = monHostAddr;
                }) (lib.filter (n: n != machine.name) resolvable);
                networkConfig.IPv6AcceptRA = false;

                # "no", and this is a MEASURED correction rather than a
                # preference.  It was "degraded" on the first deploy, on the
                # guess that a /128 p2p link never reaches "routable".  That
                # guess was wrong twice: it does reach routable (it has a
                # global address), and requiring ANY state here fails.
                #
                # The journal from the first successful start, 2026-08-24:
                #
                #   12:14:58  mon0: Link UP
                #   12:14:58  Starting Wait for Network to be Online...
                #   12:15:18  Timeout occurred while waiting for network
                #   12:15:18  systemd-networkd-wait-online: FAILED
                #   12:15:18  mon0: Gained carrier          ← same second
                #
                # A veth pair has NO CARRIER until BOTH ends are up, and the
                # host end of mon0 is brought up by container@monitoring's
                # postStart — which nixos-containers runs only after nspawn
                # reports the container started, i.e. after the container's own
                # boot has finished.  So mon0 cannot possibly be online while
                # the container is booting: wait-online was waiting for an
                # event that its own completion is a precondition for.
                #
                # It resolved itself only because of the 20 s cap below — the
                # unit failed, boot finished, READY fired, postStart ran, and
                # carrier appeared in that same second.  That is the cap doing
                # exactly what containers/jellyfin.nix designed it for, and it
                # left one permanently failed unit on every boot as the price.
                #
                # Nothing in the container needs mon0 at boot: Prometheus
                # retries a failed scrape forever and the first one is
                # seconds away.  eth0 still carries RequiredForOnline =
                # "routable", so a missing DHCP reservation is still caught.
                linkConfig.RequiredForOnline = "no";
              };

              # 20 s, for the reason containers/jellyfin.nix explains at
              # length: container@monitoring is Type=notify with
              # TimeoutStartSec=1min, so a wait-online that blocks for the
              # stock 120 s turns a missing DHCP reservation into a container
              # the host kills and restart-loops, with no reachable state to
              # debug.  At 20 s the container always finishes booting and
              # leaves one obviously failed unit instead.
              systemd.network.wait-online.timeout = 20;

              # The container's own firewall.
              #
              # NOTHING is unconditionally open.  Grafana's 3000 is reachable
              # only from the reverse proxy — backend bypass hardening,
              # mechanism (a), the same rule containers/arr.nix applies to the
              # three *arr UIs and for the same reason: .11 is the qBittorrent
              # microvm and it is one layer-2 hop away on this bridge.
              #
              # Prometheus (9090), Alertmanager (9093) and the ntfy bridge
              # (8000) are absent on purpose and must stay absent.  Grafana
              # reaches Prometheus on 127.0.0.1; Prometheus reaches
              # Alertmanager on 127.0.0.1; Alertmanager reaches the bridge on
              # 127.0.0.1.  There was never a second inbound client.
              #
              # extraCommands and not extraInputRules: the latter is declared
              # unconditionally but consumed only under networking.nftables,
              # which is off here, so it would produce no rule and no warning.
              #
              # ── M7 ADDS A SECOND SOURCE, AND IT IS THE BREAK-GLASS PATH ──
              #
              # After M7 the Grafana route is behind Authelia forward-auth, so
              # "keep the local admin as break-glass" is only true if there is
              # a way to REACH the login form when the identity provider is
              # the thing that is down — and through Traefik there is not.
              #
              # mon0's host end is that way.  It is host-only (a
              # point-to-point ULA veth that never leaves ernst), it needs
              # root on ernst to use, and it costs one rule:
              #
              #   ssh -N -L 3000:[${monContainerAddr}]:3000 root@ernst
              #   then http://localhost:3000  →  local admin login
              #
              # ip6tables and not iptables: mon0 is IPv6-only by construction.
              networking.firewall.allowedTCPPorts = [ ];
              networking.firewall.extraCommands = ''
                iptables  -A nixos-fw -p tcp -s ${settings.proxyAddress}/32 --dport ${toString ports.grafana} -j nixos-fw-accept
                ip6tables -A nixos-fw -p tcp -s ${monHostAddr}/128          --dport ${toString ports.grafana} -j nixos-fw-accept
              '';

              ################################################################
              # Users.  Numeric ids are the interface across the nspawn
              # boundary — see the allocation table in
              # machines/ernst/networking.nix.
              #
              # Both upstream modules set uid AND gid from config.ids.*, as
              # plain definitions, so both need mkForce — unlike
              # containers/traefik.nix, where the module allocates
              # dynamically and a plain merge sufficed.
              #
              # isSystemUser must be restated with the uid: NixOS infers
              # "effectively a system user" from uid < 1000, and 3006 is not,
              # so the inference stops working the moment the uid is pinned.
              # containers/arr.nix hit exactly this and the error names
              # neither the uid nor the cause.
              ################################################################
              users.users.prometheus = {
                isSystemUser = true;
                uid          = lib.mkForce prometheusUid;
              };
              users.groups.prometheus.gid = lib.mkForce prometheusGid;

              users.users.grafana = {
                isSystemUser = true;
                uid          = lib.mkForce grafanaUid;
              };
              users.groups.grafana.gid = lib.mkForce grafanaGid;

              ################################################################
              # Prometheus.
              #
              # ── RETENTION, WITH THE ARITHMETIC ─────────────────────────────
              #
              # series, estimated per scrape target:
              #   node_exporter, laptop  (trimmed collectors)          ~700
              #   node_exporter, ernst   (+systemd, ~250 units)       ~2500
              #   zfs_exporter    (2 pools, ~12 datasets)               ~90
              #   smartctl_exporter (8 SAS/NVMe devices)               ~280
              #   prometheus self                                     ~1100
              #   alertmanager                                         ~400
              #   grafana                                              ~400
              #   traefik (M5, metrics entryPoint)                     ~200
              #                                                      -------
              #   3 laptops + ernst + the four local jobs             ~7100
              #                                            round up:  8000
              #
              #   samples/second = 8000 / 60s scrape interval        =  133
              #   bytes/sample, after Prometheus' delta-of-delta +
              #     XOR compression (upstream quotes 1–2)            =  1.8
              #
              #   per day  = 133 x 86400 x 1.8                       = 21 MB
              #   per year =                                          7.6 GB
              #
              # zdata has ~47 TB free.  DISK IS NOT THE BINDING CONSTRAINT — it
              # is off by four orders of magnitude, and a retention chosen to
              # "fit the disk" here would be a decade, which is not a decision,
              # it is an absence of one.
              #
              # So retention is chosen from USEFULNESS: 400 days, i.e. thirteen
              # months, so that a year-over-year comparison always has last
              # year's same month still in the window.  ~8.3 GB.
              #
              # And it is backstopped by a SIZE CAP at 64 GB, ~8x the estimate.
              # That cap is not capacity planning; it is what stops a
              # cardinality explosion — a new exporter with a per-request label,
              # the classic — from filling the dataset that also holds every
              # *arr database.  Prometheus enforces whichever limit is hit
              # first.
              #
              # CHECK THE ESTIMATE ONCE IT IS RUNNING, because the series count
              # is the only guessed number above:
              #   nixos-container run monitoring -- curl -s \
              #     'localhost:9090/api/v1/query?query=prometheus_tsdb_head_series'
              ################################################################
              services.prometheus = {
                enable        = true;
                listenAddress = "127.0.0.1";
                port          = ports.prometheus;
                retentionTime = settings.retentionTime;
                extraFlags    = [ "--storage.tsdb.retention.size=${settings.retentionSize}" ];

                globalConfig = {
                  scrape_interval     = settings.scrapeInterval;
                  evaluation_interval = settings.scrapeInterval;
                  external_labels.clan = "clanarchy";
                };

                ##############################################################
                # SCRAPE TARGETS — GENERATED, NEVER LISTED.
                #
                # Every entry below is derived from `roles.client.machines`.
                # Adding a machine to that role in clan.nix is the only step
                # needed to monitor it: its address comes from the ZeroTier
                # var clan already generated for it, and its labels come from
                # its own role settings.  There is no list in this file to
                # forget to update, which is the specific bug M6's prompt
                # forbids.
                ##############################################################
                scrapeConfigs = [
                  {
                    job_name = "node";
                    static_configs = map (n: staticFor n ports.node) resolvable;
                  }
                  {
                    job_name = "zfs";
                    static_configs = map (n: staticFor n ports.zfs) (withExporter "zfs");
                  }
                  {
                    job_name = "smartctl";
                    static_configs = map (n: staticFor n ports.smartctl) (withExporter "smartctl");
                  }
                  # Traefik's metrics entryPoint (M5).  Same VLAN, same
                  # bridge, so this is a layer-2 hop that never reaches the
                  # UDM-Pro.  It is the ONLY source of certificate expiry
                  # data — it is the process that owns acme.json.
                  {
                    job_name = "traefik";
                    static_configs = [ {
                      targets = [ "${settings.proxyAddress}:${toString ports.traefik}" ];
                      labels.instance = "traefik";
                    } ];
                  }
                  # Authelia's telemetry listener (M7).  Same VLAN, same
                  # bridge, same layer-2 hop as Traefik's — and the same
                  # source restriction on the other end, keyed on this
                  # container's address.
                  #
                  # Conditional on an address being configured, because the
                  # module must stay usable on a fleet that has no identity
                  # provider.  There is no alert on it: `InstanceDown` keys on
                  # always_on="true", which is a label only the machine
                  # targets carry, and the same is true of the traefik job
                  # above.  What this buys is the dashboard and the history —
                  # authentication_attempts, request latency, and the `up`
                  # series to look at after an outage.
                ] ++ lib.optional (settings.authelia.address != "") {
                  job_name = "authelia";
                  static_configs = [ {
                    targets = [ "${settings.authelia.address}:${toString settings.authelia.metricsPort}" ];
                    labels.instance = "authelia";
                  } ];
                }
                # ── M13's media-stack targets ──────────────────────────────
                #
                # Each conditional on its own address, so a fleet without a
                # media stack — or an ernst part-way through M13 — evaluates
                # and runs with whichever subset is configured.
                #
                # NO TDARR JOB.  That arrives with M15, which owns it: queue
                # depth is only a meaningful series once there is a queue.
                ++ lib.optional (settings.mediaStack.arrAddress != "") {
                  job_name = "scraparr";
                  static_configs = [ {
                    targets = [ "${settings.mediaStack.arrAddress}:${toString settings.mediaStack.scraparrPort}" ];
                    labels.instance = "scraparr";
                  } ];
                }
                ++ lib.optional (settings.mediaStack.jellyfinAddress != "") {
                  job_name = "jellyfin";
                  static_configs = [ {
                    targets = [ "${settings.mediaStack.jellyfinAddress}:${toString settings.mediaStack.jellyfinPort}" ];
                    labels.instance = "jellyfin";
                  } ];
                }
                ++ lib.optional (settings.mediaStack.qbittorrentAddress != "") {
                  job_name = "qbittorrent";
                  static_configs = [ {
                    targets = [ "${settings.mediaStack.qbittorrentAddress}:${toString settings.mediaStack.qbittorrentExporterPort}" ];
                    labels.instance = "qbittorrent";
                  } ];
                }
                # NO OLLAMA JOB.  Ollama 0.32.3 serves no /metrics — measured
                # on ernst, see the note in the mediaStack options above.
                ++ [
                  # The stack watching itself.  All on loopback inside this
                  # netns, so none of these needs a port opened.
                  {
                    job_name = "prometheus";
                    static_configs = [ {
                      targets = [ "127.0.0.1:${toString ports.prometheus}" ];
                      labels.instance = "prometheus";
                    } ];
                  }
                  {
                    job_name = "alertmanager";
                    static_configs = [ {
                      targets = [ "127.0.0.1:${toString ports.alertmanager}" ];
                      labels.instance = "alertmanager";
                    } ];
                  }
                  {
                    job_name = "grafana";
                    static_configs = [ {
                      targets = [ "127.0.0.1:${toString ports.grafana}" ];
                      labels.instance = "grafana";
                    } ];
                  }
                ];

                alertmanagers = [
                  { static_configs = [ { targets = [ "127.0.0.1:${toString ports.alertmanager}" ]; } ]; }
                ];

                ##############################################################
                # RULES.  Six, plus the interlock.  Written as JSON because
                # YAML is a superset of it — which removes indentation from
                # the list of things that can be wrong in a file nothing
                # validates until Prometheus refuses to start.
                #
                # There is deliberately NO rule on zfs_pool_health.  ZED owns
                # pool state; see ALERTING in the file header.
                ##############################################################
                rules = [
                  (builtins.toJSON {
                    groups = [ {
                      name = "clanarchy";
                      rules = [
                        # ── host down ────────────────────────────────────
                        #
                        # always_on only.  A laptop with the lid shut is not
                        # an incident; see the alwaysOn option's description.
                        # 10m so a reboot or a `clan machines update` does not
                        # page anyone.
                        {
                          alert = "InstanceDown";
                          expr  = ''up{always_on="true"} == 0'';
                          "for" = "10m";
                          labels.severity = "critical";
                          annotations = {
                            summary     = "{{ $labels.instance }} is not answering scrapes";
                            description = "job {{ $labels.job }} on {{ $labels.instance }} has been down for 10 minutes.";
                          };
                        }

                        # ── SMART failure predicted ──────────────────────
                        #
                        # smartctl_device_smart_status is the drive's own
                        # self-assessment: 1 = passed, 0 = FAILING.  A drive
                        # that says this about itself is a drive to replace,
                        # not one to investigate.
                        {
                          alert = "SmartFailurePredicted";
                          expr  = "smartctl_device_smart_status == 0";
                          "for" = "15m";
                          labels.severity = "critical";
                          annotations = {
                            summary     = "SMART self-assessment FAILED on {{ $labels.instance }}";
                            description = "device {{ $labels.device }} ({{ $labels.model_name }}) reports its own health check as failing. Replace it.";
                          };
                        }

                        # ── filesystem filling up ────────────────────────
                        #
                        # The pseudo-filesystem exclusion list is the whole
                        # difficulty here: without it this fires permanently
                        # on /nix/store (a read-only bind at 100%), on every
                        # tmpfs, and on the impermanence overlays.
                        #
                        # 1h, because filling a filesystem is a slope and not
                        # an event — and because an *arr import can push a
                        # dataset past a threshold for minutes and then hard-
                        # link the file away again.
                        {
                          alert = "FilesystemFillingUp";
                          expr = ''
                            100 - (
                              node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs|overlay|squashfs|autofs|nsfs|devtmpfs|efivarfs"}
                              / node_filesystem_size_bytes{fstype!~"tmpfs|ramfs|overlay|squashfs|autofs|nsfs|devtmpfs|efivarfs"}
                              * 100
                            ) > 85
                          '';
                          "for" = "1h";
                          labels.severity = "warning";
                          annotations = {
                            summary     = "{{ $labels.mountpoint }} on {{ $labels.instance }} is over 85% full";
                            description = "{{ $labels.mountpoint }} ({{ $labels.fstype }}) has been above 85% for an hour.";
                          };
                        }

                        # ── any failed systemd unit ──────────────────────
                        #
                        # Only fires where the systemd collector is enabled,
                        # which today is ernst alone.  That is where it earns
                        # its keep: clanarchy-impermanence-check, the
                        # container units, the secret-staging oneshots and the
                        # zdata import all fail loudly and then sit there
                        # failed with nobody looking.
                        {
                          alert = "SystemdUnitFailed";
                          expr  = ''node_systemd_unit_state{state="failed"} == 1'';
                          "for" = "15m";
                          labels.severity = "warning";
                          annotations = {
                            summary     = "{{ $labels.name }} has failed on {{ $labels.instance }}";
                            description = "systemd unit {{ $labels.name }} has been in the failed state for 15 minutes.";
                          };
                        }

                        # ── any failed unit INSIDE an nspawn container ───
                        #
                        # SystemdUnitFailed above cannot see these. It is fed
                        # by node_exporter's systemd collector, which reads
                        # the HOST's systemd; every container runs its own
                        # init with its own unit namespace.
                        #
                        # The gap was not hypothetical. soularr.service in
                        # ernst's `arr` container failed 1412 times across
                        # nine days, never once completing a pass, and
                        # nothing alerted — a failed oneshot on a timer is
                        # invisible unless something is watching for exactly
                        # this.
                        {
                          alert = "ContainerSystemdUnitFailed";
                          expr  = ''clanarchy_container_systemd_unit_failed == 1'';
                          "for" = "15m";
                          labels.severity = "warning";
                          annotations = {
                            summary     = "{{ $labels.name }} has failed in container {{ $labels.container }} on {{ $labels.instance }}";
                            description = "systemd unit {{ $labels.name }} inside nspawn container {{ $labels.container }} has been in the failed state for 15 minutes. Inspect with: systemctl -M {{ $labels.container }} status {{ $labels.name }}";
                          };
                        }

                        # ── the container collector itself is broken ─────
                        #
                        # Its whole value is answering "is anything failing in
                        # there", so a collector that silently answers "no"
                        # because it could not reach machined is worse than
                        # not having it. It publishes its own success and this
                        # is what reads it — the same interlock argument as
                        # ZedNotRunning immediately below.
                        {
                          alert = "ContainerUnitCollectorFailing";
                          expr  = ''clanarchy_container_units_collector_success == 0'';
                          "for" = "15m";
                          labels.severity = "warning";
                          annotations = {
                            summary     = "Container unit collector could not query every container on {{ $labels.instance }}";
                            description = "At least one nspawn container did not answer systemctl -M for 15 minutes, so ContainerSystemdUnitFailed is blind to it. Check `machinectl list` and journalctl -u clanarchy-container-units.";
                          };
                        }

                        # ── THE INTERLOCK: ZED is not running ────────────
                        #
                        # This is the rule that makes "keep both alerting
                        # systems" a design rather than an omission.  ZED is
                        # the only thing that reports a pool going degraded,
                        # and the only thing it cannot report is its own
                        # death.  A unit that is stopped rather than failed
                        # does not trip SystemdUnitFailed above, so this asks
                        # the opposite question.
                        {
                          alert = "ZedNotRunning";
                          expr  = ''node_systemd_unit_state{name="zfs-zed.service",state="active"} == 0'';
                          "for" = "15m";
                          labels.severity = "critical";
                          annotations = {
                            summary     = "ZFS event daemon is not running on {{ $labels.instance }}";
                            description = "zfs-zed is the ONLY path that alerts on a pool going degraded (modules/observability/zfs-ntfy.nix). While it is down, pool state changes are unmonitored.";
                          };
                        }

                        # ── TLS certificate expiring ─────────────────────
                        #
                        # traefik_tls_certs_not_after is a unix timestamp, so
                        # the expression is "days remaining".  M5's wildcard
                        # renews at 30 days left; 14 means two renewal
                        # attempts have already failed silently, which is
                        # exactly the failure that file's header says has no
                        # monitoring "until M6".
                        {
                          alert = "CertificateExpiringSoon";
                          expr  = "(traefik_tls_certs_not_after - time()) / 86400 < 14";
                          "for" = "1h";
                          labels.severity = "critical";
                          annotations = {
                            summary     = "TLS certificate expires in under 14 days";
                            description = "{{ $labels.cn }}{{ $labels.sans }} has {{ $value | printf \"%.0f\" }} days left. Renewal has already failed at least twice — check `journalctl -u traefik` in the traefik container.";
                          };
                        }
                      ];
                    } ];
                  })
                ];
              };

              ################################################################
              # Alertmanager.
              #
              # ONE receiver, because there is one destination.  Everything is
              # grouped by alertname and instance so a machine that comes back
              # with four failed units produces one notification, not four.
              #
              # repeat_interval is 24h and not the 4h default: these are phone
              # notifications for a household, and a still-degraded pool does
              # not become more actionable by being announced six times a day.
              ################################################################
              services.prometheus.alertmanager = {
                enable        = true;
                listenAddress = "127.0.0.1";
                port          = ports.alertmanager;
                configuration = {
                  route = {
                    receiver        = "ntfy";
                    group_by        = [ "alertname" "instance" ];
                    group_wait      = "30s";
                    group_interval  = "5m";
                    repeat_interval = "24h";
                  };
                  receivers = [ {
                    name = "ntfy";
                    webhook_configs = [ {
                      url           = "http://127.0.0.1:${toString ports.ntfyBridge}/hook";
                      send_resolved = true;
                    } ];
                  } ];
                };
              };

              ################################################################
              # alertmanager-ntfy — the bridge to the SAME topic the ZFS
              # zedlet already publishes to.
              #
              # Alertmanager's own webhook receiver cannot do this on its own:
              # it POSTs a fixed JSON envelope, and ntfy renders the request
              # BODY as the message, so a direct webhook to the topic URL
              # produces a phone notification containing raw Alertmanager JSON.
              # ntfy's title/priority/tags live in HTTP HEADERS, which
              # Alertmanager cannot template.  This bridge exists to do exactly
              # that translation and nothing else.
              #
              # The topic is a PASSWORD on a public ntfy instance — anyone who
              # knows it can both read and publish — so it never appears in the
              # Nix store.  `settings` here carries only the shape; the two
              # values that matter arrive through extraConfigFiles as a
              # systemd credential, and the module merges the files in order
              # with later ones winning.
              ################################################################
              services.prometheus.alertmanager-ntfy = {
                enable = true;
                settings = {
                  http.addr = "127.0.0.1:${toString ports.ntfyBridge}";
                  ntfy = {
                    # Both overridden by the staged credential below.  The
                    # placeholders are here because the options are required
                    # and because a config that failed to merge should look
                    # obviously wrong on the phone rather than subtly right.
                    baseurl = "https://ntfy.invalid";
                    notification = {
                      topic    = "";
                      priority = ''status == "firing" ? "high" : "default"'';
                      # The module's own defaults, restated so the two
                      # conditions are visible next to the priority they pair
                      # with.  Nothing cleverer: the tag conditions are gval
                      # expressions evaluated at notification time, and a
                      # typo in one is a crash in the bridge rather than a
                      # missing emoji — which would take the whole alerting
                      # path down to make a notification prettier.
                      tags = [
                        { tag = "red_circle";   condition = ''status == "firing"''; }
                        { tag = "green_circle"; condition = ''status == "resolved"''; }
                      ];
                    };
                  };
                };
                extraConfigFiles = [ ntfyConfFile ];
              };

              ################################################################
              # Grafana.
              #
              # Behind Traefik, and since M7 behind Authelia forward-auth —
              # ledger row L5's ipAllowList is gone, not stacked underneath.
              # Its own login stays either way; see the break-glass block
              # below and the vars generator above.
              ################################################################
              services.grafana = {
                enable = true;

                settings = {
                  server = {
                    http_addr = "0.0.0.0";
                    http_port = ports.grafana;
                    # domain / root_url are what make Grafana emit correct
                    # absolute URLs behind a proxy.  Without them every
                    # redirect and every OAuth callback points at
                    # http://10.0.90.14:3000/, which nothing on a client VLAN
                    # can reach — the classic reverse-proxy failure where the
                    # login page loads and the login itself does not.
                    domain    = "grafana.${settings.domain}";
                    root_url  = "https://grafana.${settings.domain}/";
                    enforce_domain = false;
                  };

                  security = {
                    admin_user     = "admin";
                    admin_password = "$__file{${grafanaPwFile}}";
                    # Encrypts stored datasource credentials and API tokens.
                    # See the generator: created once, never rotated.
                    secret_key     = "$__file{${grafanaKeyFile}}";
                    # Nothing renders this in a frame, and saying so removes a
                    # clickjacking surface for free.
                    disable_gravatar = true;
                    cookie_secure    = true;
                  };

                  # A household dashboard, not a SaaS.  Local sign-up off,
                  # anonymous off.
                  #
                  # `users.allow_sign_up` governs the LOCAL form and stays
                  # false; `auth.generic_oauth.allow_sign_up` below is a
                  # different switch and has to be true, or an OIDC login
                  # succeeds at the issuer and then fails at Grafana with
                  # "signup is not allowed".  They look like the same setting
                  # and are not.
                  users.allow_sign_up = false;
                  "auth.anonymous".enabled = false;

                  ############################################################
                  # M7 — BREAK-GLASS.  Read this before "tidying" it away.
                  #
                  # `disable_login_form` is NOT set, so the local admin form
                  # stays.  That is deliberate and it is the entire reason the
                  # monitoring-grafana generator still prompts for a password.
                  #
                  # The account that matters is the one that works when the
                  # identity provider is broken — which is exactly when
                  # somebody wants a dashboard.  After M7 the Grafana ROUTE is
                  # behind Authelia forward-auth, so reaching that form when
                  # Authelia is down means going around Traefik entirely:
                  #
                  #   ssh -N -L 3000:[${monContainerAddr}]:3000 root@ernst
                  #   open http://localhost:3000, log in as `admin`
                  #
                  # The ip6tables rule that makes that work is in the firewall
                  # block above; it is host-only and needs root on ernst.
                  #
                  # `signout_redirect_url` is deliberately NOT set either: a
                  # Grafana logout should end the Grafana session and leave
                  # the Authelia one alone, so that signing out of a dashboard
                  # is not also signing out of the *arr.
                  ############################################################
                  "auth".disable_login_form = false;

                  "auth.generic_oauth" = lib.mkIf oidc.enable {
                    enabled = true;
                    name    = "Authelia";
                    icon    = "signin";

                    # See the note on users.allow_sign_up above — this is the
                    # OAuth-side switch and it must be on for a first login to
                    # create the Grafana account.
                    allow_sign_up = true;
                    # NOT auto_login: it would send anyone hitting /login
                    # straight to the issuer, including the person trying to
                    # reach the break-glass form on localhost.
                    auto_login    = false;

                    client_id     = oidc.clientId;
                    client_secret = "$__file{${grafanaOidcFile}}";

                    # `groups` is not a standard OIDC scope; Authelia serves it
                    # and it is what role_attribute_path reads below.  Without
                    # it every OIDC user silently lands on Viewer.
                    scopes = "openid profile email groups";

                    auth_url  = "${oidc.issuerUrl}/api/oidc/authorization";
                    token_url = "${oidc.issuerUrl}/api/oidc/token";
                    api_url   = "${oidc.issuerUrl}/api/oidc/userinfo";

                    # PKCE is REQUIRED by the client block on the issuer side,
                    # so this is not optional hardening — without it the
                    # authorization request is rejected before a password is
                    # ever typed.
                    use_pkce = true;

                    login_attribute_path  = "preferred_username";
                    name_attribute_path   = "name";
                    groups_attribute_path = "groups";

                    # JMESPath over the claims.  Membership of the admin group
                    # is the only distinction drawn; everyone else who gets
                    # this far is a Viewer.  `role_attribute_strict = false`
                    # so a claim shape that does not match leaves the user on
                    # the fallback rather than refusing the login outright —
                    # a locked-out admin is worse here than a demoted one.
                    role_attribute_path   = "contains(groups[*], '${oidc.adminGroup}') && 'Admin' || 'Viewer'";
                    role_attribute_strict = false;
                  };

                  analytics = {
                    reporting_enabled = false;
                    check_for_updates = false;
                  };
                };

                ##############################################################
                # Provisioning — datasource and dashboard as code.
                #
                # `uid` is pinned on the datasource because the dashboard JSON
                # references it by uid.  Left to Grafana it would be random,
                # and the dashboard would provision successfully with every
                # panel reporting "datasource not found" — which looks like a
                # Prometheus problem and is not.
                ##############################################################
                provision = {
                  enable = true;

                  datasources.settings = {
                    apiVersion = 1;
                    datasources = [ {
                      name      = "Prometheus";
                      uid       = "clanarchy-prometheus";
                      type      = "prometheus";
                      access    = "proxy";
                      url       = "http://127.0.0.1:${toString ports.prometheus}";
                      isDefault = true;
                    } ];
                  };

                  dashboards.settings = {
                    apiVersion = 1;
                    providers = [ {
                      name    = "clanarchy";
                      type    = "file";
                      # The dashboard is code; editing it in the UI and not
                      # here would be lost on the next deploy, so say so
                      # rather than letting someone find out.
                      allowUiUpdates = false;
                      options.path   = dashboardDir;
                    } ];
                  };
                };
              };

              ################################################################
              # `curl` is the test plan's instrument — it is what proves each
              # target is reachable from HERE and, run anywhere else, that the
              # backends are not.  `dig` checks the container resolves through
              # Technitium.  Nothing else is added.
              ################################################################
              environment.systemPackages = with pkgs; [ curl dnsutils ];
              documentation.enable       = false;
              documentation.nixos.enable = false;
            };
          };
        }

        # The token's restart wiring, added ONLY when auth is on.
        #
        # `mkMerge` + `mkIf` on a WHOLE CONFIG BLOCK, and both halves of that
        # are load-bearing:
        #
        #   - `mkIf` on the VALUE (`restartUnits = mkIf ntfyAuth [ … ]`) leaves
        #     the attribute PATH defined, which materialises the
        #     `zfs-ntfy-token` generator on machines that never enabled auth.
        #     `clan vars check` then reports its token as missing. Measured
        #     2026-08-24.
        #   - `//  lib.optionalAttrs ntfyAuth { … }` fixes that and introduces
        #     INFINITE RECURSION: it forces `config.clanarchy.zfs.ntfy.auth`
        #     while the module's own attribute structure is still being
        #     determined. Also measured, immediately after.
        #
        # `mkIf` defers the condition until after the structure is known,
        # which is exactly the property needed here.
        (lib.mkIf ntfyAuth {
          clan.core.vars.generators.zfs-ntfy-token.files."token".restartUnits = [
            "monitoring-secrets.service"
            "container@monitoring.service"
          ];
        })

        # M7's OIDC wiring, added ONLY when it is switched on.
        #
        # Same `mkIf`-on-a-CONFIG-BLOCK shape as the token above, and for the
        # identical reason: `restartUnits = mkIf oidc.enable [ … ]` would leave
        # the attribute PATH defined, materialising a generator this module
        # does not own on every machine that holds the server role without an
        # identity provider — and `clan vars check` would then report its
        # secret as missing.  Guard the definition, not the value.
        #
        # The generator is named by settings, so this is where the two halves
        # of the client secret are tied to the units that consume the plaintext
        # one.  The hashed half's restartUnits are declared beside the issuer,
        # in machines/ernst/containers/authelia.nix, because those units exist
        # only there.
        (lib.mkIf oidc.enable {
          assertions = [
            {
              assertion = oidc.issuerUrl != "";
              message = ''
                @clanarchy/monitoring: authelia.oidc.enable is set but
                authelia.oidc.issuerUrl is empty.  Grafana would be configured
                with auth_url = "/api/oidc/authorization", which is a relative
                URL Grafana accepts and then cannot redirect to.  Set it to the
                issuer's base URL (e.g. "https://auth.goclan.org") in clan.nix.
              '';
            }
          ];

          clan.core.vars.generators.${oidc.secretGenerator}.files.${oidc.secretFile}.restartUnits = [
            "monitoring-secrets.service"
            "container@monitoring.service"
          ];
        })
        ];
    };
  };
}
