# @clanarchy/monitoring

Fleet metrics: Prometheus, Alertmanager and Grafana in one nspawn container on
the server machine; `node_exporter` on every machine.

## Overview

| Component | Where | Reachable from |
|-----------|-------|----------------|
| `node_exporter` | every `client` machine | the monitoring stack only (ip6tables source restriction) |
| `zfs_exporter` | opt-in per client (ernst) | same |
| `smartctl_exporter` | opt-in per client (ernst) | same |
| Prometheus | container, `127.0.0.1:9090` | nothing — `nixos-container run monitoring -- curl localhost:9090` |
| Alertmanager | container, `127.0.0.1:9093` | nothing |
| `alertmanager-ntfy` | container, `127.0.0.1:8000` | nothing |
| Grafana | container, `:3000` | Traefik only (`grafana.<domain>`, mgmt VLANs until M7) |

Everything is stock nixpkgs. No new flake input.

## Roles

| Role | What it does |
|------|--------------|
| `client` | Runs `node_exporter` (trimmed collector set), optionally the ZFS and SMART exporters and node_exporter's `systemd` collector, and permits exactly the monitoring stack to scrape it |
| `server` | Runs the container, generates every scrape target from `roles.client`, alerts to the ntfy topic `modules/observability/zfs-ntfy.nix` already owns |

### `client` settings

| Setting | Default | Meaning |
|---------|---------|---------|
| `alwaysOn` | `false` | Machine is expected up 24/7. **Only these get the `InstanceDown` alert** — a laptop with the lid shut is not an incident |
| `exporters.zfs` | `false` | Pool health / capacity / fragmentation (`zfs_exporter`, not node_exporter's ARC collector) |
| `exporters.smartctl` | `false` | Per-device SMART, including the self-assessment behind `SmartFailurePredicted` |
| `exporters.systemd` | `false` | node_exporter's `systemd` collector — backs `SystemdUnitFailed` and `ZedNotRunning` |

### `server` settings

| Setting | Default | Meaning |
|---------|---------|---------|
| `bridge` / `vlan` / `mac` | `br0` / `90` / — | The container's L2 identity; MAC is allocated in `machines/ernst/networking.nix` |
| `proxyAddress` | — | Reverse proxy's address: the only source allowed to reach Grafana, and Traefik's own scrape target |
| `stateDir` | `/srv/state/monitoring` | TSDB + Grafana database. Must not be on a rolling-back filesystem |
| `domain` | `goclan.org` | Grafana is served at `grafana.<domain>` |
| `retentionTime` / `retentionSize` | `400d` / `64GB` | See the disk arithmetic in `monitoring.nix` |
| `scrapeInterval` | `60s` | Global |
| `resolver` / `searchDomain` | `10.0.5.3` / `skynet.lan` | Declared inside the container, not inherited from DHCP |
| `zerotierInstance` | `zerotier` | Name of the clan zerotier instance; part of the var name client addresses are read from |

## Scrape targets are generated

There is no target list. `roles.server` reads `roles.client.machines` and, for
each machine, takes the address out of the clan var
`zerotier-ip-<machine>-<instance>` that clan-core's zerotier service already
generates. **Adding a machine to `roles.client` is the only step needed to
monitor it.**

The one exception is the machine holding `roles.server` itself, which is
scraped over the host link instead (see below) because it is on the host's own
VLAN, not the container's.

## Two network legs

```
                       br0 / VLAN 90                    ZeroTier mesh
  Traefik ──────────────► eth0                       miralda  biene  birte
                          │                              ▲      ▲      ▲
                   [ monitoring container ]              └──────┴──────┘
                          │                                     │ SNAT to
                          mon0 ◄──── point-to-point ULA ────► ernst (host)
                                                          forwards + NATs
```

* **eth0** — veth on the bridge, Services VLAN, DHCP against a UDM-Pro
  reservation keyed on the pinned MAC. This is how Traefik reaches Grafana and
  the only leg any client VLAN sees.
* **mon0** — a `/128`-to-`/128` veth to the host on a ULA that never leaves the
  machine. It carries scrapes of the host's own exporters, and — via one host
  route per target plus `networking.nat` — scrapes of every other machine on
  ZeroTier. The SNAT rewrites the source to the host's own ZeroTier address,
  which is exactly the source each client's firewall permits.

## Alerting

Six rules and one interlock. **ZED and Prometheus both alert, to the same ntfy
topic, with no overlap:**

* **ZED** (`modules/observability/zfs-ntfy.nix`) owns pool and vdev state. It is
  edge-triggered, fleet-wide, and keeps working when the monitoring container
  is down.
* **Prometheus** owns everything ZED cannot see. There is deliberately **no
  alert on `zfs_pool_health`** — it is a dashboard panel only.
* **`ZedNotRunning`** is the interlock: the one thing ZED cannot report is its
  own death, so Prometheus reports it.

| Alert | Fires when | For |
|-------|------------|-----|
| `InstanceDown` | `up == 0` on an `alwaysOn` machine | 10m |
| `SmartFailurePredicted` | a drive fails its own SMART self-assessment | 15m |
| `FilesystemFillingUp` | a real filesystem is over 85% | 1h |
| `SystemdUnitFailed` | any unit in `failed` | 15m |
| `ZedNotRunning` | `zfs-zed.service` not active | 15m |
| `CertificateExpiringSoon` | Traefik's cert has under 14 days left | 1h |

## Usage

### Inventory (`clan.nix`)

```nix
monitoring = {
  module.input = "self";
  module.name  = "@clanarchy/monitoring";

  roles.server.machines.ernst.settings = {
    mac          = "02:00:00:90:00:06";
    proxyAddress = "10.0.90.12";
  };

  roles.client.machines.ernst.settings = {
    alwaysOn           = true;
    exporters.zfs      = true;
    exporters.smartctl = true;
    exporters.systemd  = true;
  };
  roles.client.machines.miralda = { };
  roles.client.machines.biene   = { };
  roles.client.machines.birte   = { };
};
```

### First deploy

```bash
clan vars generate ernst          # prompts for the Grafana admin password
clan machines update ernst
clan machines update miralda      # then the rest, in any order
```

The container will not start before `clan vars generate` has run — deliberately
fail-closed, the same shape `containers/traefik.nix` uses.

### Checking it

```bash
# On ernst.
bridge vlan show dev vb-monitoring            # expect: 90 PVID Egress Untagged
ip -6 route get fdda:...                      # a client's ZT address, via mon0's peer
nixos-container run monitoring -- curl -s localhost:9090/api/v1/targets \
  | jq -r '.data.activeTargets[] | "\(.labels.instance)\t\(.health)"'

# How big is it really? (the one estimated number in the retention math)
nixos-container run monitoring -- curl -s \
  'localhost:9090/api/v1/query?query=prometheus_tsdb_head_series'
```

### Troubleshooting

**A machine shows `up == 0` but is awake.** The scrape ACL is the first
suspect:

```bash
# On the client.
ip6tables -L nixos-fw -n --line-numbers | grep 9100
# From the container: does the route exist at all?
nixos-container run monitoring -- ip -6 route
```

**No notifications, but alerts are firing.** The bridge is the only thing
between Alertmanager and the phone:

```bash
nixos-container run monitoring -- systemctl status alertmanager-ntfy
nixos-container run monitoring -- journalctl -u alertmanager-ntfy -n 50
systemctl status monitoring-secrets        # on the host — did the topic stage?
```

**Grafana shows "datasource not found" on every panel.** The dashboard
references the datasource by the pinned uid `clanarchy-prometheus`; if
provisioning of the datasource failed, the dashboard still provisions fine.
Check `journalctl -u grafana | grep -i provision` inside the container.

**Rotating the ntfy topic or the Grafana password.** A deploy is not enough —
the staging unit's text is unchanged, so systemd will not re-run it:

```bash
clan vars generate ernst
systemctl restart monitoring-secrets container@monitoring
```
