# @clanarchy/haos

Home Assistant OS (the official appliance image, with Supervisor and the add-on
store) as a KVM guest. It runs as a plain systemd unit, `haos-<name>.service`.
One role, `host`. Every machine-specific property is a setting in the inventory:
cpus, memory, the disk, the NICs, the USB devices and the metrics token.

## Why a VM and not the nspawn container it replaced

Home Assistant ran on ernst as `services.home-assistant` in the nspawn container
`hass` (M24). That is Home Assistant **Core** built by nixpkgs:

- no Supervisor, so no add-ons;
- `--skip-pip`, so an integration downloaded through HACS never gets its
  Python requirements. Home Assistant doesn't even check them, so the first
  sign was an `ImportError` from deep inside someone else's code. The repo
  carried a dependency checker, a hand-kept `extraPackages` list, an
  eval-time filter over every component and a stack of per-package test
  overrides to live with that.

HAOS removes all of it. The price is that **the repo stops describing Home
Assistant itself.** Its configuration, integrations, HACS and add-ons now live
inside the guest's disk. They are covered by ZFS snapshots of the zvol and by
HA's own backups, not by a file in this repository.

## What the repo owns, and what it doesn't

| Owned here (declarative) | Owned by HAOS (state in the guest) |
|---|---|
| vCPUs, RAM, hugepages, CPU affinity | `configuration.yaml`, `.storage`, the recorder DB |
| the zvol, its size and properties | integrations, HACS and what it installs |
| UEFI firmware, the OVMF variable store | add-ons and their config |
| every NIC: tap name, MAC, bridge/VLAN, p2p addresses | interface IP configuration (set in the HAOS UI) |
| the bridge filter in front of each bridged NIC | HA's own `ip_ban`, MFA, trusted proxies |
| which USB devices the guest gets | ZHA / Thread / Bluetooth configuration |
| the metrics token (clan var) | HAOS and Core versions (OTA from the UI) |

The pinned `image.version` only says what a **new** disk is seeded from. Once
the zvol exists, the image is never read again.

## Settings

```nix
roles.host.machines.<machine>.settings = {
  name = "hass";                 # unit haos-hass, user haos-hass, /run/haos-hass
  vcpus = 4; memoryMiB = 8192; hugepages = true; cpuAffinity = null;
  disk = { zvol = "zdata/vm/hass"; sizeGiB = 64; };
  stateDir = "/srv/state/haos-hass";   # OVMF variable store; guarded to be on zdata/state
  nics = [
    { tap = "hass0"; kind = "bridged"; vlan = 90; mac = "02:00:00:90:00:13";
      allowFrom = [ { peer = "10.0.90.12"; port = 8123; } ]; }
    { tap = "ai3"; kind = "p2p"; mac = "…";
      hostAddress6 = "fdca:fe93::1"; guestAddress6 = "fdca:fe93::2"; }
  ];
  usb = [ { name = "zigbee"; vendorId = "303a"; productId = "831a"; serial = "…"; } ];
  metrics.enable = false;
};
```

- **`nics` are in PCI order**, each at a fixed slot from `0x10` up. HAOS names
  interfaces by slot (`enp0s16`, `enp0s17`, …) and keys its saved network
  settings on that name. Append new NICs; don't insert them.
- **`bridged`** NICs are untagged members of `vlan` on `bridge`. On a DHCP
  segment the address is the reservation for `mac`.
- **`p2p`** NICs carry a `/128` on the host end and a route to the guest end:
  the shape `service-modules/local-ai/bridges.nix` sockets expect. The guest
  end is set once in HAOS (Settings → System → Network, static IPv6, e.g.
  `fdca:fe93::2/64`, no gateway). Turn mDNS off on a p2p leg too
  (`ha network update <if> --mdns off`): ernst's Avahi never reflects a tap,
  but the guest has nothing to announce there.
- **The leg with the default route is the one the add-ons use.** The
  Supervisor calls it "primary", and the Matter Server and OpenThread Border
  Router apps bind to it. Put the default route on the segment where the
  devices are, give every other leg a static address with no gateway, and
  allow `icmpv6` there when the guest speaks IPv6 on it.
- **`usb`** entries are matched in `/sys/bus/usb/devices` by vendor, product
  and `serial` and/or `port` (the kernel name, e.g. `3-2.1`). If an entry
  doesn't match exactly one device, the VM doesn't start. Two devices with the
  same vendor:product must each name a serial or a port; that is asserted.

## The firewall is in the bridge

HAOS has no user-configurable firewall, and the Supervisor and every add-on
open ports of their own. Traffic between the guest and a container on the same
VLAN is switched inside `br0` and never reaches the gateway. So each instance
loads one nftables table in the **`bridge`** family. It filters every frame
forwarded *towards* each bridged tap, in this order:

1. accept established/related;
2. accept ARP and DHCP replies;
3. accept each `allowFrom` entry;
4. drop everything else.

Outbound traffic from the guest is not filtered, which matches the container
it replaced.

The table is `haos_<name>`. On an iptables host it is loaded by
`haos-<name>-filter.service`; on an nftables host it goes into
`networking.nftables.tables`. The VM unit `Requires=` the filter: no filter,
no VM.

**Each add-on port you want reachable is an `allowFrom` edit and a deploy.**
That is the point.

## Operating it

```bash
systemctl status haos-hass                       # the VM
journalctl -u haos-hass                          # prestart: seed, USB resolution
socat -,raw,echo=0 UNIX-CONNECT:/run/haos-hass/serial.sock   # HAOS console (`ha` CLI); ctrl-] style exit: ctrl-c
echo '{"execute":"qmp_capabilities"}{"execute":"query-status"}' \
  | socat -t1 - UNIX-CONNECT:/run/haos-hass/qmp.sock
nft list table bridge haos_hass                  # the filter, with drop counters
zfs get clanarchy:seeded,clanarchy:seeded-from zdata/vm/hass
```

- **Deploys don't restart the guest** (`restartIfChanged = false`). A changed
  command line, such as a new NIC, a USB device or more RAM, takes effect at
  the next `systemctl restart haos-hass`. Restarting it is your call; it takes
  the house's automations down for about a minute.
- **Stop is a clean shutdown.** `ExecStop` presses the ACPI power button over
  QMP and waits up to 110 s. Only then does systemd SIGTERM qemu, which would
  otherwise cut the guest's power.
- **Growing the disk:** `zfs set volsize=96G zdata/vm/hass`, then restart.
  HAOS grows its data partition on boot.
- **A new disk from scratch:** stop the unit, `zfs destroy zdata/vm/hass`,
  start it. The prestart downloads the pinned image, checks its sha256, and
  writes it. `clanarchy:seeded` stays `no` until the write has finished, so an
  interrupted seed is redone instead of booted.

## Metrics

`metrics.enable` declares the `haos-<name>-metrics` generator, which **prompts**
for a long-lived access token. A pending prompt blocks every deploy, so only
enable it once the token exists. The rest:

1. in the guest: `prometheus:` in `configuration.yaml`, and create the token;
2. `metrics.enable = true` here, then `clan vars generate <machine>`;
3. in `@clanarchy/monitoring`: `mediaStack.homeAssistantAddress`;
4. the monitoring container's address in the VLAN NIC's `allowFrom`, on 8123.

**Core is on 8123, always.** The Supervisor pins it there and ignores
`http.server_port`. On a brand-new disk, *before* Core is installed, HAOS
serves an onboarding page on port 80 and redirects 8123 to it. That is the
first-boot state only, not something to point a backend at.

The job is `up == 0` until all four are done.

## On ernst

The instance is `hass`. It took over everything the container had:

- **Network:** the same MAC on VLAN 90, so `10.0.90.27` and Traefik's,
  homepage's and Music Assistant's backends are unchanged. The same MAC on
  `iot0` (VLAN 20), which is the PRIMARY leg: the default route, IPv6, mDNS,
  Matter and Thread border routing all sit there, because that is where the
  devices are and where phones join (`skynet-iot`) to pair. `ai3` for the
  conversation agent, STT and TTS, and `kodi0` for Kodi.
- **USB:** both Nabu Casa ZBT-2 radios (Zigbee, and Thread for the OpenThread
  Border Router app) and the older of the host's two Bluetooth
  dongles. The host keeps the other.
- **mneme's pictures** used to be written into the hub's `www/`. They now land
  in `/srv/state/mneme-images` and are served by the Traefik container at the
  same URL, `ha.goclan.org/local/mneme/`.

The cutover runbook (backup → deploy → on-disk state migration; a UI restore
does not survive the Nix store symlinks) is in
`docs/runbooks/ernst-hass-to-haos.md`.
