# Networking

This guide covers how machines resolve each other, what ZeroTier provides, and how to verify connectivity — especially when you're on a different network than the target machine.

---

## Name resolution layers

| Name | Resolves via | Works across networks |
|------|--------------|-----------------------|
| `miralda.goclan.org` | Public DNS | Yes (used by `deploy`) |
| `biene.skynet.lan` | Local split-horizon DNS | LAN only |
| `miralda.local` / `biene.local` | mDNS (Avahi) | Yes — via ZeroTier reflector |
| ZeroTier IPv6 directly | ZeroTier network | Yes |

`modules/networking.nix` enables the Avahi mDNS reflector on all clan machines.
It bridges mDNS multicast between every interface Avahi sees, including the ZeroTier interface (`zt…`), so `<hostname>.local` resolves and routes correctly even when machines are on different LANs.

---

## ZeroTier

All clan machines are peers on a private ZeroTier network.
`miralda` is the controller; `biene` and `homeserver` are peers.
Each machine gets a ZeroTier IPv6 address in the clan-managed subnet.
Network ID and per-machine IPs are stored in clan vars (encrypted).

```
clan.nix inventory:
  zerotier:
    roles.controller.machines.miralda
    roles.peer.tags.all            ← all machines join as peers
```

The system service is `zerotierone` (not `zerotier-one`).
The firewall is opened automatically by the clan zerotier instance.

---

## Testing connectivity from a different network

Run these steps in order until something fails — that pinpoints where the problem is.

### 1. Confirm the ZeroTier service is running

```bash
systemctl is-active zerotierone
# Expected: active
```

If it's not active:

```bash
sudo systemctl start zerotierone
```

### 2. Confirm the ZeroTier interface is up

```bash
ip addr show altname zerotier
```

Expected output includes a `zt…` interface with an `inet6` address in the clan subnet (`fdda:…`).
If the interface is missing, ZeroTier hasn't joined the network yet — check `journalctl -u zerotierone -n 50`.

### 3. Ping the target machine via mDNS

```bash
ping biene.local      # from miralda
ping miralda.local    # from biene
```

`ping` resolves `*.local` via Avahi, which reflects mDNS across the ZeroTier interface.
The reply will come from the machine's ZeroTier IPv6 address — this confirms end-to-end connectivity.

If mDNS fails but you know the ZeroTier IPv6, ping it directly:

```bash
# Read from the clan var on the target machine, or check `ip addr show altname zerotier` there
ping fdda:106a:123a:d561:1099:93da:xxxx:xxxx
```

### 4. SSH test

```bash
ssh lgo@miralda.goclan.org    # via public DNS (always works if ZT is up)
ssh lgo@miralda.local         # via mDNS over ZeroTier
```

!!! note "YubiKey required for SSH"
    SSH auth uses the YubiKey OpenPGP auth subkey via `gpg-agent`.
    The key must be inserted and the PIN must not be blocked.
    See [Updating machines — YubiKey SSH signing](updating-machines.md#yubikey-ssh-signing) if auth fails.

### 5. Deploy connectivity

`deploy` targets `root@miralda.goclan.org`.
If DNS resolves and SSH works (step 4), `deploy` will work.
To verify before deploying:

```bash
ssh root@miralda.goclan.org hostname
```

---

## Troubleshooting

### `*.local` not resolving

1. Confirm Avahi is running: `systemctl is-active avahi-daemon`
2. Confirm the ZeroTier interface is up: `ip link show altname zerotier`
3. If the `zt…` interface came up after Avahi started, Avahi may not have picked it up:
   ```bash
   sudo systemctl restart avahi-daemon
   ```

### ZeroTier interface is up but no cross-network path

ZeroTier peer discovery is asynchronous — wait 30–60 s after the service starts.
If it stays unreachable, check whether UDP is blocked on your current network
(ZeroTier uses UDP; it falls back to TCP relay automatically, but this takes longer).

### `biene` not reachable from a different network

`biene.skynet.lan` only resolves on the home LAN.
Use `biene.local` (mDNS via ZeroTier) instead:

```bash
ssh sabine@biene.local
```

`deploy-biene` hardcodes `root@biene.skynet.lan`.
From outside the home network, use the ZeroTier IPv6 directly:

```bash
nixos-rebuild switch \
  --flake .#biene \
  --target-host root@fdda:106a:123a:d561:1099:93da:ef5d:598c \
  --no-reexec -j auto
```
