# Clanarchy

**Clanarchy** is a NixOS declarative configuration built on [clan-core](https://git.clan.lol/clan/clan-core), currently managing `miralda` — a Framework 13 AMD laptop running NixOS 26.05.

## Stack

| Layer | Technology |
|-------|------------|
| Compositor | Niri (Wayland, tiled scrolling) |
| Session manager | UWSM |
| Greeter | ReGreet via greetd |
| Shell | Noctalia / Quickshell |
| Secrets | clan vars + sops-nix |
| Disk layout | ZFS + systemd-boot |
| Root persistence | Impermanence (ZFS rollback on boot) |
| Hardware auth | YubiKey PIV (age encryption) + GnuPG (SSH) |

## Machines

| Machine | Role | Status |
|---------|------|--------|
| `miralda` | Framework 13 AMD laptop, daily driver | active |
| `homeserver` | Headless server | planned |

## Navigation

- **Guides** — step-by-step explanations for cross-cutting concerns (YubiKey setup, impermanence workflow, …)
- **Reference** — auto-generated tables of all `clanarchy.*` NixOS options defined in `modules/`

## Developing

```bash
# Enter devShell (direnv or manual)
nix develop

# Deploy to miralda
deploy           # nixos-rebuild switch
deploy boot      # stage for next boot only

# Regenerate option reference docs
gendocs

# Build docs locally
mkdocs serve
```
