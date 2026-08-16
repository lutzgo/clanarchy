# Clanarchy

**Clanarchy** is a NixOS declarative configuration built on [clan-core](https://git.clan.lol/clan/clan-core), managing four machines under one clan.

## Stack

| Layer | Technology |
|-------|------------|
| Compositors | Niri (miralda), labwc + Noctalia (biene), KDE Plasma 6 (birte), headless (ernst) |
| Session manager | UWSM |
| Greeter | ReGreet (Niri/labwc), SDDM (KDE via Jovian) |
| Shell | Noctalia / Quickshell |
| Secrets | clan vars + sops-nix |
| Disk layout | ZFS + systemd-boot |
| Root persistence | Impermanence (ZFS rollback on boot) |
| Hardware auth | YubiKey PIV (age encryption) + GnuPG (SSH) — miralda only |

## Machines

| Machine | Hardware | Role | Desktop |
|---------|----------|------|---------|
| `miralda` | Framework 13 AMD | Daily driver (lgo) | Niri + Noctalia |
| `biene` | Lenovo laptop | Sabine's machine | labwc + Noctalia |
| `birte` | Steam Deck OLED (Galileo) | Handheld gaming | Steam Gaming Mode (Jovian) / KDE Plasma 6 |
| `ernst` | AM5 / X870E homelab | Headless server (NAS + VM host + GPU compute) | — |

## Navigation

- **Guides** — step-by-step explanations for cross-cutting concerns (deploy helpers, first-time install, YubiKey setup, Noctalia profiles, …)
- **Reference** — auto-generated tables of all `clanarchy.*` NixOS options defined in `modules/`

## Developing

```bash
# Enter devShell (direnv or manual)
nix develop

# Deploy — one function per machine, all support boot|switch
deploy              # miralda
deploy boot         # miralda — stage for next boot only
deploy-biene        # biene    (BIENE_HOST= to override target)
deploy-birte        # birte    (BIRTE_HOST= to override target)
deploy-ernst        # ernst    (ERNST_HOST= to override target)

# Test a PR in a QEMU VM (defaults to biene)
test-pr <PR#> [machine]
test-vm [machine]

# Regenerate option reference docs
gendocs

# Build docs locally
docs serve
```
