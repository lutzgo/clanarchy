# Technitium on the UDM Pro after a UniFi OS update

Technitium is the household resolver: `10.0.5.3` on VLAN 5, handed out by DHCP
on every network and used by ernst for **every** lookup
(`machines/ernst/networking.nix`). It runs as the systemd-nspawn container
`debian-custom` **on the UDM Pro**, outside this repository.

A UniFi OS update replaces everything on the UDM except `/data`. The container's
root filesystem survives in `/data/custom/machines/debian-custom`; the host-side
pieces that start it do not, and the scripts in `/data/on_boot.d/` exist to put
them back.

## Symptom

- Phones and laptops: "connected, no internet".
- ernst: `getent hosts example.com` returns nothing. Traefik, the *arr apps,
  mail, Nextcloud → Paperless and the TV's Immich proxy all fail at the first
  name they look up.
- From a laptop, routing works and DNS doesn't:

  ```bash
  ping -c2 1.1.1.1                    # answers
  dig +short example.com @10.0.5.3    # ";; no servers could be reached"
  ```

`ernst` itself no longer resolves either. Reach it as `ssh root@ernst-zt`.

## Fix

```bash
ssh root@10.0.10.1        # always `root`; password: UniFi → Settings → Control Plane → Console → SSH
```

Check what survived:

```bash
ls /data/custom/machines/; ls /data/on_boot.d/; which machinectl; ls -la /var/lib/machines; ls /etc/systemd/nspawn/
```

The usual finding is that **only `machinectl` is missing**: `20-nspawn-persistence.sh`
has already recreated the link and the `.nspawn` file, but could not start the
container without it. Then:

```bash
apt-get -y install systemd-container
machinectl enable debian-custom && machinectl start debian-custom
sleep 8 && machinectl list && ping -c2 10.0.5.3
```

Verify from a laptop that the split horizon is back, i.e. that internal names answer with
internal addresses:

```bash
dig +short photos.goclan.org @10.0.5.3   # 10.0.90.12
dig +short ernst.skynet.lan  @10.0.5.3   # 10.0.50.10
```

Then check ernst for units that failed while nothing resolved
(`systemctl --failed`, and `systemctl -M <container> --failed` per container).
On 2026-11-08 the only one was `recyclarr` in `arr`: its git fetch fails without
DNS, and the next timer run fixes it.

If DHCP DNS was switched to "Auto" in UniFi as a stopgap, set it back to
`10.0.5.3`. Otherwise internal names hang for those clients: Technitium is
the only place they're defined.

## The boot scripts

| Script | Does |
|---|---|
| `05-install-systemd-container.sh` | Reinstalls `systemd-container`: **apt first** (with retries), the cache in `/data/custom/dpkg` as fallback. Refreshes that cache whenever it does not match the installed version |
| `06-cron-refresh-dpkg.sh` | Restores a quarterly cron job for `/data/custom/refresh-dpkg-cache.sh` |
| `10-setup-network.sh` | VLAN 5 bridge `br5` for the container's MACVLAN |
| `15-add-root-ssh-keys.sh` | Root SSH keys |
| `20-nspawn-persistence.sh` | Recreates `/var/lib/machines/debian-custom`, `debian-custom.nspawn` and the enable link, then starts the container if it isn't running |

**Why the cache must match the running firmware, not the last one:** at boot,
apt needs DNS, and the UDM's own lookups may depend on the very container that
is not up yet. So the offline cache is the path that actually runs after an
update, and a cache of the previous release's packages cannot install.

## 2026-11-08

UniFi OS moved from **Debian 11 to 13** (systemd 247 → 257) overnight. The cache
held only `…247.3-7+deb11u8` packages, last refreshed 1 October by the quarterly
cron. The old `05` tried only the cache, failed, and `20` logged
`failed to start debian-custom` with no `machinectl` to call. Wi-Fi had no DNS
until morning.

Fixed by hand as above, then:

- `05` rewritten: apt first, and a cache refresh whenever the installed version
  differs from what is cached.
- `20` now starts the container whenever it isn't running, not only when it had
  to recreate something.
