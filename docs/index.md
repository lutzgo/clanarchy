# Clanarchy

**Clanarchy** is a NixOS declarative configuration built on [clan-core](https://git.clan.lol/clan/clan-core), managing five machines under one clan.

## Stack

| Layer | Technology |
|-------|------------|
| Compositors | Niri (miralda, jens), labwc + Noctalia (biene), KDE Plasma 6 (birte), headless (ernst) |
| Session manager | UWSM |
| Greeter | ReGreet (Niri/labwc), SDDM (KDE via Jovian) |
| Shell | Noctalia / Quickshell |
| Secrets | clan vars + sops-nix |
| Disk layout | ZFS + systemd-boot |
| Root persistence | Impermanence (ZFS rollback on boot) |
| Hardware auth | YubiKey PIV (age encryption) + GnuPG (SSH) — miralda + jens |

## Machines

| Machine | Hardware | Role | Desktop |
|---------|----------|------|---------|
| `miralda` | Framework 13 AMD | Daily driver (lgo) | Niri + Noctalia |
| `jens` | Framework 12 Intel (convertible) | Portable daily driver (lgo) | Niri + Noctalia |
| `biene` | Lenovo laptop | Sabine's machine | labwc + Noctalia |
| `birte` | Steam Deck OLED (Galileo) | Handheld gaming | Steam Gaming Mode (Jovian) / KDE Plasma 6 |
| `ernst` | AM5 / X870E homelab | Headless server (NAS + VM host + GPU compute) | — |

## Navigation

- **Invariants / Standing notes / Ledger** — what a change must design around, the hazards that live in files you will edit for another reason, and the temporary network shims
- **History** — one row per milestone: what it was, whether it landed, which PRs to read
- **Architecture** — the machines, the modules, and the decisions whose reason is not visible from the code
- **Guides** — how to do a thing: deploy, install a machine, add a module, the YubiKey, each service
- **Reference** — generated tables of all `clanarchy.*` NixOS options

## Developing

```bash
# Enter devShell (direnv or manual)
nix develop

# Deploy — the clan CLI, no wrapper
clan machines update miralda
clan machines update biene --target-host root@biene.skynet.lan
clan machines list

# Regenerate option reference docs
gendocs

# Build docs locally
docs serve
```
