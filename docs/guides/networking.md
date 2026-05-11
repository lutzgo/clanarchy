# Networking

This guide covers how machines resolve each other, what ZeroTier provides, and how to verify connectivity — especially when you're on a different network than the target machine.

---

## Name resolution layers

| Name | Resolves via | Works across networks |
|------|--------------|-----------------------|
| `miralda.goclan.org` | Public DNS | Yes (used by `deploy`) |
| `biene.skynet.lan` | Local split-horizon DNS | LAN only |
| `miralda.local` / `biene.local` | mDNS (Avahi) | Yes — via ZeroTier reflector |
| ZeroTier IP directly | ZeroTier network | Yes |

`modules/networking.nix` enables the Avahi mDNS reflector on all clan machines.
It bridges mDNS multicast between every interface Avahi sees, including ZeroTier (`zt…`), so `<hostname>.local` resolves even when machines are on different LANs.

---

## ZeroTier

All clan machines are peers on a private ZeroTier network.
`miralda` is the controller; `biene` and `homeserver` are peers.
Network ID and per-machine ZeroTier IPs are stored in clan vars (encrypted).

```
clan.nix inventory:
  zerotier:
    roles.controller.machines.miralda
    roles.peer.tags.all            ← all machines join as peers
```

ZeroTier runs as a system service (`services.zerotier`).
The firewall is opened automatically by the clan zerotier instance.

---

## Testing connectivity from a different network

Run these steps in order until something fails — that tells you where the problem is.

### 1. ZeroTier status on your local machine

```bash
zerotier-cli status
# Expected: 200 info <node-id> <version> ONLINE
```

If you see `OFFLINE` or `DISCONNECTED`, the local ZeroTier daemon is not running or has lost its network membership.
Restart it:

```bash
sudo systemctl restart zerotier-one
```

### 2. Check peer visibility

```bash
zerotier-cli peers
# Look for miralda's node ID — state should be LEAF, latency should be a number (not -)
```

If miralda doesn't appear, or shows `-` latency, ZeroTier has not yet established a path.
Wait 10–30 s and retry; ZeroTier performs peer discovery asynchronously.

To find miralda's ZeroTier IP:

```bash
# On miralda itself:
zerotier-cli listnetworks
# or read the clan var (requires age decryption):
cat vars/per-machine/miralda/zerotier/zerotier-ip
```

### 3. Ping via mDNS

```bash
ping miralda.local
```

This works if:

- ZeroTier has a path to miralda (step 2 passed), and
- Avahi is running on both machines and its reflector is bridging the ZeroTier interface.

If `miralda.local` doesn't resolve but you know the ZeroTier IP, ping the IP directly:

```bash
ping <miralda-zt-ip>
```

### 4. SSH test

```bash
ssh lgo@miralda.goclan.org      # via public DNS
# or
ssh lgo@miralda.local           # via mDNS + ZeroTier
# or
ssh lgo@<miralda-zt-ip>         # via ZeroTier IP directly
```

!!! note "YubiKey required for SSH"
    SSH auth uses the YubiKey OpenPGP auth subkey via `gpg-agent`.
    The key must be inserted and PIN must not be blocked.
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

### `miralda.local` not resolving

1. Confirm Avahi is running on your local machine: `systemctl status avahi-daemon`
2. Confirm the ZeroTier interface is up: `ip link show | grep zt`
3. Avahi publishes and reflects on all interfaces it sees — if the `zt…` interface came up after Avahi started, a restart may be needed: `sudo systemctl restart avahi-daemon`

### ZeroTier peer present but latency is `-`

ZeroTier has no direct or relayed path yet.
Check whether your network blocks UDP (ZeroTier uses UDP by default; TCP relay is a fallback).
Give it 30–60 s — relayed paths appear before direct ones.

### `biene` not reachable from a different network

`biene.skynet.lan` only resolves on the home LAN.
Use `biene.local` (mDNS via ZeroTier) or the ZeroTier IP directly:

```bash
cat vars/per-machine/biene/zerotier/zerotier-ip
ssh sabine@biene.local
```

`deploy-biene` hardcodes `root@biene.skynet.lan`.
From outside the home network, deploy to biene manually:

```bash
nixos-rebuild switch \
  --flake .#biene \
  --target-host root@<biene-zt-ip> \
  --no-reexec -j auto
```
