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

The devShell exposes these shell functions:

```bash
deploy [boot|switch]        # default: switch — build locally, push, activate on miralda
deploy-biene [boot|switch]  # same, targets biene (override host with BIENE_HOST=...)
push [remote] [branch]      # default: origin main — push via gh auth token
```

### Pushing with `gh`

Impermanence makes `~/.config/git` a read-only bind mount, so `git push` with a credential helper doesn't work. The `push` shell function works around this by reading `gh auth token` at runtime and injecting it into the HTTPS remote URL.

**First-time setup** (run once per machine, persisted by impermanence):
```bash
gh auth login            # authenticate with GitHub (browser or token)
```

**Day-to-day pushing:**
```bash
push                     # pushes main to origin
push origin my-branch    # pushes a specific branch
```

If you need `gh` for other tasks (PRs, issues, releases), use it directly — authentication is handled via the keyring.

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
# 1. Edit config files
# 2. Deploy (switch = immediate activation):
deploy

# Or stage a boot entry without switching (safe for risky changes):
deploy boot

# 3. Commit and push:
git add -A && git commit
push
```

**Secrets / clan vars:** If you change a `secrets/` generator, re-run:
```bash
clan vars generate miralda
```
Then redeploy. Use `clan machines update miralda` if the full inventory evaluation is needed (e.g. after sops key changes).

---

## YubiKey usage

The YubiKey serves two roles: **SSH authentication** (via GnuPG agent) and **age decryption** (PIV-backed identity for sops/clan vars).

For full setup instructions and troubleshooting, see [docs/guides/yubikey.md](docs/guides/yubikey.md).

### When to plug in the YubiKey

| Task | YubiKey needed? |
|------|-----------------|
| `deploy` (local to miralda) | **Yes** — SSH to `root@miralda.goclan.org` uses the GPG auth subkey |
| `clan vars generate` | **Yes** — decrypts/re-encrypts secrets with age-plugin-yubikey |
| `clan machines update` | **Yes** — both SSH and secret decryption |
| Editing config, `nix eval`, building | No |
| `push` / `gh` operations | No — uses GitHub token, not SSH |
| `git commit` | No |

### Troubleshooting

If `deploy` fails with `Permission denied (publickey)`:

```bash
# 1. Check the YubiKey is visible:
gpg --card-status

# 2. Check GPG agent is serving SSH keys:
ssh-add -L

# 3. If ssh-add shows nothing, restart the agent:
gpgconf --kill gpg-agent
gpg --card-status        # re-triggers agent + card detection
ssh-add -L               # should now show the key
```

If `gpg --card-status` fails, the YubiKey isn't plugged in or `pcscd` isn't running:
```bash
sudo systemctl status pcscd
```

---

## Architecture

```
flake.nix                       — devShell, machine composition, module injection
clan.nix                        — clan metadata, overlays, inventory instances
modules/
  base.nix                      — universal NixOS defaults (EFI boot, Plymouth, flakes, openssh, zsh)
  zfs-impermanence.nix          — ZFS rollback on boot, boot flags, common persist paths
  hardware/yubikey.nix          — pcscd, GnuPG agent (pinentry-qt Wayland wrapper), polkit
  hardware/printing.nix         — CUPS + hplip, SANE scanning
  desktop/niri.nix              — Niri compositor, UWSM, ReGreet, Pipewire, fonts, Noctalia PAM
  desktop/gnome.nix             — GNOME/GDM, extensions, shared dconf
  roles/laptop.nix              — GPU drivers, power management, Framework hw (fprintd, fwupd)
  users/lgo.nix                 — lgo power user: shell, devtools, HM config
  users/admin.nix               — admin user: SSH keys, impermanence
  locale.nix, networking.nix    — shared locale/keyboard and ZeroTier/mDNS options
service-modules/
  machine-type.nix              — @clanarchy/machine-type (laptop, server, vm, rpi)
  desktop.nix                   — @clanarchy/desktop (niri, gnome, kde)
  users.nix                     — @clanarchy/users (lgo, sabine)
  yubikey.nix                   — @clanarchy/yubikey (pcscd, GnuPG, polkit)
  printing.nix                  — @clanarchy/printing (CUPS, SANE, hplip)
  software.nix                  — @clanarchy/software (browsers, email)
machines/miralda/
  configuration.nix             — identity (hostname, locale, cpu), tablet hw, stateVersion
  disko.nix                     — NVMe partitioning (GPT: 1G ESP + ZFS AES-256-GCM)
  stylix.nix                    — Selenized Black theme, generated wallpaper, cursor
  apps.nix                      — GUI/CLI apps, unfree allowlist, Flatpak, Podman, OBS
  wallpapers.nix                — Per-workspace nix-anarchy SVG wallpapers
  home/                         — Home Manager per-user configs
  home-modules/                 — HM modules: browsers, console tools
  secrets/                      — Clan vars generators (passwords, WiFi, age identity)
machines/biene/
  configuration.nix             — identity (hostname, locale, cpu), Fritz!Box wifi, stateVersion
  disko.nix                     — NVMe partitioning (GPT: 1G ESP + ZFS)
  stylix.nix                    — Catppuccin Mocha theme
vars/per-machine/               — Generated secrets (gitignored sensitive values)
sops/                           — sops age keys
```

---

## Adding a machine to syncthing

Syncthing keeps `~/Public` in sync across all clan machines. When a new machine joins, add it as a peer in `clan.nix`:

```nix
inventory.instances.syncthing.roles.peer.machines.new-machine = {
  settings.folders.public.path = "/home/lgo/Public";
};
```

Then generate its syncthing vars and redeploy both machines:

```bash
clan vars generate new-machine
deploy switch   # on each machine
```

Machines discover each other automatically via their zerotier IPs stored in clan vars — no manual device ID exchange needed.

---

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
