# ernst — moving Home Assistant from the `hass` container to HAOS

This replaces the nspawn container `hass` (Home Assistant Core from nixpkgs) with
the Home Assistant OS guest `haos-hass` from `@clanarchy/haos`
(`service-modules/haos.md`). The deploy takes
care of the VM shell. This runbook covers what the deploy can't do: carrying
the state across and finishing the setup inside the guest.

**Time:** about an hour. The house has no automations from step 2 until
step 5 is done.

**Rollback at any point before step 7:** revert the PR and deploy `main`. The
container's state in `/srv/state/home-assistant` is never touched by any step
here.

## What you need in front of you

- **The YubiKey**, unlocked in this session, for the deploy and for `ssh root@ernst`.
- A browser on the LAN (VLAN 10). The guest's UI is reachable there before
  Traefik routes to it.
- Somewhere to keep the backup file and its **encryption key**.

## 1. Back up the container

In the current Home Assistant: **Settings → System → Backups → Create backup →
Full**. Download the `.tar`. Copy the backup's **encryption key** (Settings →
System → Backups → ⋮ → Encryption key). You can't restore without it.

Also note:

- Settings → Devices & services → **ZHA** → the radio path (`/dev/zigbee-coordinator`);
- the Ollama / Wyoming / Kodi integration addresses (`fdca:fe93::1`, `fdca:fe96::1`).
  They survive the restore unchanged.

## 2. Deploy

Merge the PR, then:

```bash
clan machines update ernst
./scripts/post-deploy-check.sh ernst
```

During this deploy, `container@hass` stops and disappears. `haos-hass-filter`
loads the bridge table. `haos-hass` creates `zdata/vm/hass`, downloads HAOS,
checks the sha256, writes the image and boots it. The first start takes a few
minutes.

Check:

```bash
ssh root@ernst
systemctl status haos-hass haos-hass-filter
journalctl -u haos-hass -b | grep -E 'seeding|USB|hugepages'   # three USB lines, no "matched 0/2"
zfs get clanarchy:seeded zdata/vm/hass                          # yes
networkctl list | grep -E 'hass0|iot0|ai3|kodi0'                # four taps, all configured
bridge vlan show dev hass0; bridge vlan show dev iot0           # 90 PVID untagged / 20 PVID untagged
```

If a tap shows `failed` because the old veth of the same name was still around
when networkd reloaded, run `networkctl reload`, then `systemctl restart haos-hass`.

## 3. Network settings inside HAOS

On `hass0` the guest gets `10.0.90.27` from the UDM-Pro reservation, because
the MAC is unchanged. Core is on 8123 (the Supervisor pins it; port 80 is only the
first-boot onboarding page). If the bridge
filter blocks your source, use the serial console instead:

```bash
socat -,raw,echo=0 UNIX-CONNECT:/run/haos-hass/serial.sock     # login: root → `ha` CLI
```

Under **Settings → System → Network** (or `ha network update` on the console):

| Interface | IPv4 | IPv6 | mDNS |
|---|---|---|---|
| `enp0s16` (hass0, VLAN 90) | static `10.0.90.27/24`, **no gateway** | disabled | off |
| `enp0s17` (iot0, VLAN 20)  | static `10.0.20.27/24`, gateway `10.0.20.1`, DNS `10.0.5.3` | auto | default |
| `enp0s18` (ai3)            | disabled | static `fdca:fe93::2/64`, no gateway | off |
| `enp0s19` (kodi0)          | disabled | static `fdca:fe96::2/64`, no gateway | off |

```bash
# iot0 first, so that the guest is never without a default route
ha network update enp0s17 --ipv4-method static --ipv4-address 10.0.20.27/24 \
  --ipv4-gateway 10.0.20.1 --ipv4-nameserver 10.0.5.3 --ipv6-method auto --mdns default
ha network update enp0s16 --ipv4-method static --ipv4-address 10.0.90.27/24 \
  --ipv6-method disabled --mdns off
ha network update enp0s18 --mdns off
ha network update enp0s19 --mdns off
ha network info | grep -B1 -A0 'primary: true'     # enp0s17
ha apps restart core_openthread_border_router
ha apps restart core_matter_server
```

**`enp0s17` (VLAN 20) is the primary leg, and that is load-bearing.** The
Supervisor calls the interface with the default route "primary", and both the
Matter Server and the OpenThread Border Router apps take it as their own. The
log lines are `Using 'enp0s17' as primary network interface.` and
`Infra link selected: enp0s17`. Matter is IPv6 on the devices' own link, the
Wi-Fi Matter devices are on VLAN 20, and phones join `skynet-iot` to pair. With
the default route on `enp0s16` both apps sat on VLAN 90, where IPv6 is off and no
device lives. `enp0s16` keeps no gateway, because two default routes leave the
guest picking a leg per packet. Traefik and Music Assistant are on-link on
VLAN 90, so they are unaffected.

VLAN 20 has no IPv6 router of its own, so `auto` yields only a link-local address
until OTBR announces its on-link ULA prefix. That is expected.

**mDNS is off on every leg but `enp0s17`.** The guest announces one hostname on
every NIC that has mDNS on. Any reflector that carries one leg's announcement
onto another (ernst's Avahi before it denied the p2p taps, and the UDM-Pro's
across VLANs 50/90/20) makes the guest see its own name with a foreign
address. It renames, re-announces, and loops. This was measured on 2026-11-05:
about 18 packets a second, and the name at `homeassistant82520.local`.

## 4. Migrate the state — on the disk, NOT through "Restore from backup"

**The UI restore does not work from the Nix container, and that was measured on
2026-11-05.** Nix generated `configuration.yaml` as a symlink into the store
(`/etc/home-assistant/configuration.yaml`), and HACS as a symlink into
`/nix/store/…-hacs-2.0.5`. A backup archives both as symlinks, so a restore
leaves them dangling in HAOS: no `http:` block, which means the proxy gets a
`400`, no includes and no HACS. (The backup from step 1 is still the safety net.)

What worked was copying the state into the guest's data partition with the
guest powered off:

```bash
ssh root@ernst
zfs snapshot zdata/vm/hass@pre-migrate-$(date +%Y%m%d-%H%M)
systemctl stop haos-hass                              # clean ACPI powerdown
M=$(mktemp -d); mount /dev/zvol/zdata/vm/hass-part8 $M  # label hassos-data
C=$M/supervisor/homeassistant; O=/srv/state/home-assistant
mv $C $M/supervisor/homeassistant.fresh && mkdir -m 0755 $C
for f in .storage automations.yaml scenes.yaml scripts.yaml blueprints custom_components \
         themes tts www image .shopping_list.json home-assistant_v2.db zigbee.db .HA_VERSION; do
  [ -e "$O/$f" ] && cp -a "$O/$f" "$C/"
done
rm $C/custom_components/hacs                          # the store symlink
# HACS 2.0.5 (the version the container ran), from its release zip:
curl -fsSLO https://github.com/hacs/integration/releases/download/2.0.5/hacs.zip
mkdir $C/custom_components/hacs && unzip -q hacs.zip -d $C/custom_components/hacs
# configuration.yaml as a REAL file — the YAML Nix generated, minus
# http.server_host (HAOS manages it):
$EDITOR $C/configuration.yaml
# ZHA's radio path: the udev alias does not exist inside the guest.
sed -i 's#"path":"/dev/zigbee-coordinator"#"path":"/dev/serial/by-id/usb-Nabu_Casa_ZBT-2_1CDBD45E613C-if00"#' \
  $C/.storage/core.config_entries
chown -R 0:0 $C; sync; umount $M
systemctl start haos-hass
```

Do NOT add `http.server_port`: the Supervisor pins Core to 8123 and ignores it.

## 5. What is left inside HAOS

- **Bluetooth.** Settings → Devices & services → the discovered adapter
  (the CSR8510) → Configure.
- **HACS** keeps its stored GitHub token (it is in `.storage/hacs*`). If it
  asks for the device flow again, redo it once.
- The integrations HACS installed now install their own Python requirements on
  first start. The `pytoyoda` packaging is gone for that reason.

## 6. mneme's pictures

Nothing to copy on ernst: `/srv/state/home-assistant/www/mneme` was empty at
the cutover. New pictures land in `/srv/state/mneme-images`. A miss returns
nginx's `404` with `cache-control: public`, which proves the route goes to the
Traefik container and not to the hub.

## 7. Verify, then let it soak

- `https://ha.goclan.org` logs in. The companion app reconnects without
  re-pairing (same URL, same tokens).
- A Zigbee device toggles. Assist answers a voice query (the `ai3` leg). The
  Kodi media player is available (the `kodi0` leg). The Music Assistant
  integration is connected.
- The filter works. From the arr container
  (`nixos-container run arr -- curl -m3 http://10.0.90.27:8123/`) the request
  succeeds: `.13` is the service index's address and is allowed. From any other
  VLAN-90 container it times out. `nft list table bridge haos_hass` shows the
  drop counter moving.
- `systemctl restart haos-hass` once. `journalctl -u haos-hass` shows a clean
  powerdown, not a SIGTERM timeout.

After a week without problems, `/srv/state/home-assistant` can go. That's your
call, and it isn't part of any deploy.

## Optional: metrics

When you want Home Assistant in Prometheus:

1. Inside HA, add `prometheus:` to `configuration.yaml` and create a long-lived
   access token (Profile → Security).
2. Set `metrics.enable = true` on the `haos` instance in `clan.nix`. In the
   monitoring instance, set `mediaStack.homeAssistantAddress = "10.0.90.27"`.
   Add `{ peer = "10.0.90.14"; port = 8123; }` to `hass0`'s `allowFrom`.
3. Run `clan vars generate ernst` (it prompts for the token), then deploy.
