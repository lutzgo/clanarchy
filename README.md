# clanarchy

NixOS configuration for `miralda` (Framework 13 AMD), managed with [clan-core](https://clan.lol).

**Stack:** Niri + UWSM + ReGreet · Noctalia shell · ZFS + impermanence · YubiKey PIV age · clan vars

---

## Prerequisites

- Nix with flakes enabled
- [clan-cli](https://clan.lol/docs/getting-started/) (available in the devShell)
- A configured YubiKey with a PIV age identity (for secret decryption)
- SSH access to `root@miralda.goclan.org`

---

## Development shell

```bash
# Enter devShell (direnv picks this up automatically if you use it)
nix develop

# Or with direnv:
direnv allow
```

The devShell exposes two shell functions:

```bash
deploy [boot|switch]      # default: switch — build locally, push, activate on miralda
push [remote] [branch]    # default: origin main — push via gh auth token
```

---

## Bootstrap (first-time machine setup)

1. **Boot NixOS installer**, partition and format with disko:
   ```bash
   nix run github:nix-community/disko -- --mode disko machines/miralda/disko.nix
   ```

2. **Install NixOS:**
   ```bash
   nixos-install --flake .#miralda --no-root-password
   ```

3. **Create ZFS blank snapshots** (impermanence rollback targets):
   ```bash
   zfs snapshot zroot/root@blank
   zfs snapshot zroot/home@blank
   ```

4. **Generate clan vars** (WiFi credentials, admin/lgo passwords, age identity):
   ```bash
   clan vars generate miralda
   ```
   Each generator prompts for the required inputs (passphrases, YubiKey slot, etc.).

5. **Set up YubiKey age identity** on miralda after first login:
   ```bash
   age-plugin-yubikey --generate --slot 1 > ~/.age/yubikey-identity.txt
   ```
   The recipient stored in `vars/per-machine/miralda/` is used by sops for secret encryption.

---

## Day-to-day workflow

```bash
# Edit config, then deploy (switch = immediate activation):
deploy

# Stage a boot entry without switching (safe for risky changes):
deploy boot

# After deploy, push to remote:
push
```

**Secrets / clan vars:** If you change a `secrets/` generator, re-run:
```bash
clan vars generate miralda
```
Then redeploy. Use `clan machines update miralda` if the full inventory evaluation is needed (e.g. after sops key changes).

---

## Architecture

```
flake.nix                  — devShell, machine composition, module injection
clan.nix                   — clan metadata, nixpkgs overlay (niri sandbox fix)
machines/miralda/
  configuration.nix        — hostname, timezone, boot loader, ZFS, Plymouth
  disko.nix                — NVMe partitioning (GPT: 1G ESP + ZFS AES-256-GCM)
  impermanence.nix         — ZFS rollback on boot; persisted paths
  desktop.nix              — Niri, UWSM, ReGreet, Framework hw, Pipewire, fonts
  stylix.nix               — Gruvbox Dark theme, generated wallpaper, cursor
  noctalia.nix             — PAM service for Noctalia lockscreen
  yubikey.nix              — pcscd, GnuPG agent, polkit rule
  wifi.nix                 — NetworkManager profile from clan vars
  apps.nix                 — GUI apps, Podman, Flatpak
  users/                   — System user declarations
  home/                    — Home Manager per-user configs
  home-modules/desktop.nix — Shared HM module: Niri settings, Noctalia, packages
  secrets/                 — Clan vars generators (passwords, WiFi, age identity)
vars/per-machine/miralda/  — Generated secrets (gitignored sensitive values)
sops/                      — sops age keys
```

---

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
