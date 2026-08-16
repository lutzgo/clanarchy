# clanarchy

NixOS declarative configuration built on [clan-core](https://git.clan.lol/clan/clan-core), managing four machines:

| Machine | Hardware | Role |
|---------|----------|------|
| `miralda` | Framework 13 AMD | daily-driver laptop (Niri, YubiKey, lgo) |
| `biene` | Lenovo laptop | Sabine's machine (labwc + Noctalia) |
| `birte` | Steam Deck OLED (Galileo) | Steam Gaming Mode via Jovian-NixOS; KDE Plasma 6 fallback |
| `ernst` | AM5/X870E homelab | headless server (NAS + VM host + GPU compute) |

**Stack:** ZFS + impermanence · Wayland compositors (Niri, labwc, KDE) · Noctalia shell · YubiKey PIV (age) + GnuPG (SSH) · clan vars for secrets.

Full docs: **[lutzgo.github.io/clanarchy](https://lutzgo.github.io/clanarchy)** (or `docs serve` locally).

---

## Prerequisites

- Nix with flakes enabled
- [clan-cli](https://clan.lol/docs/getting-started/) (provided by the devShell)
- A configured YubiKey with a PIV age identity (needed for secret decryption on `miralda`)

---

## Development shell

```bash
nix develop           # or: direnv allow, if you use direnv
```

The devShell exposes:

```bash
deploy [boot|switch]         # miralda   (root@miralda.goclan.org)
deploy-biene [boot|switch]   # biene     (root@biene.local; BIENE_HOST= to override)
deploy-birte [boot|switch]   # birte     (root@birte.local; BIRTE_HOST= to override)
deploy-ernst [boot|switch]   # ernst     (root@ernst.skynet.lan; ERNST_HOST= to override)

test-pr <PR#> [machine]      # gh pr checkout + build-vm + run-vm  (machine defaults to biene)
test-vm [machine]            # build-vm + run-vm on the current tree

push [remote] [branch]       # push via gh auth token (works with impermanent ~/.config/git)
gendocs                      # regenerate docs/reference/*.md from live NixOS config
```

See [docs/guides/deploy.md](docs/guides/deploy.md) for the full breakdown, including when to use `deploy-X` vs. `clan machines update X` (the latter re-evaluates vars/secrets).

### Pushing with `gh`

Impermanence makes `~/.config/git` a read-only bind mount, so `git push` with a credential helper doesn't work. The `push` function reads `gh auth token` at runtime and injects it into the HTTPS remote URL.

First-time setup (once per machine):
```bash
gh auth login
```

---

## Bootstrap (first-time machine install)

New machines are installed by booting the Clan installer USB, then running `clan machines install <name>` from an existing clan machine. The installer uses the YubiKey pubkey embedded in `machines/miralda/yubikey_ed25519.pub` so no manual SSH-key setup is needed.

Full walkthrough: **[docs/guides/first-time-install.md](docs/guides/first-time-install.md)**.

---

## Day-to-day workflow

```bash
# 1. Edit config files
# 2. Deploy (switch = immediate activation, boot = staged for next boot):
deploy
deploy boot

# 3. Commit and push:
git add <files> && git commit
push
```

If a `secrets/` generator or `sops` config changes, run `clan vars generate <machine>` then redeploy. `clan machines update <machine>` also re-evaluates vars — use it when a stripped-down `deploy` isn't enough.

---

## YubiKey usage

The YubiKey serves two roles on `miralda`: **SSH authentication** (via GnuPG agent) and **age decryption** (PIV-backed identity for sops/clan vars). Full setup + troubleshooting in [docs/guides/yubikey.md](docs/guides/yubikey.md).

### When to plug in the YubiKey

| Task | YubiKey needed? |
|------|-----------------|
| `deploy` (SSH to `root@miralda.goclan.org`) | **Yes** — GPG auth subkey |
| `clan vars generate` | **Yes** — decrypts/re-encrypts secrets |
| `clan machines update` | **Yes** — SSH + secret decryption |
| Editing config, `nix eval`, building | No |
| `push` / `gh` operations | No — uses GitHub token |
| `git commit` | No |

`deploy-biene`, `deploy-birte`, and `deploy-ernst` also need SSH access to their targets, but those use the `clanarchy_admin` ed25519 key, not the YubiKey.

### Troubleshooting `Permission denied (publickey)`

```bash
gpg --card-status        # confirms the YubiKey is visible to pcscd
ssh-add -L               # should list the GPG auth subkey
# If ssh-add is empty:
gpgconf --kill gpg-agent
gpg --card-status        # re-triggers agent + card detection
```

---

## Architecture

Authoritative source: **[docs/index.md](docs/index.md)** for the overview and **[docs/reference/](docs/reference/)** for the auto-generated `clanarchy.*` option tables.

At a glance:

- `flake.nix` — inputs, devShell, and clan machine composition (uses `lib/mk-machine.nix` helpers).
- `clan.nix` — clan-core metadata (`name = clanarchy`, `domain = goclan.org`), nixpkgs overlays, and clan-service inventory instances.
- `lib/mk-machine.nix` — `mkModuleArgs`, `commonBase`, `commonHeadful` — reusable pieces that keep the per-machine blocks small. Per-machine nixpkgs channel selection is in `modules/channel.nix` (`clanarchy.channel = "stable" | "unstable"`).
- `modules/` — reusable NixOS modules (hardware, roles, apps, desktop, users, disko/stylix bases).
- `service-modules/` — custom clan-service definitions (`@clanarchy/machine-type`, `@clanarchy/desktop`, `@clanarchy/users`, `@clanarchy/yubikey`, `@clanarchy/printing`, `@clanarchy/software`, `@clanarchy/local-ai`).
- `machines/{miralda,biene,birte,ernst}/` — machine-specific `configuration.nix`, `disko.nix`, `stylix.nix`, plus per-machine extras (wallpapers, Jovian wiring, etc.).
- `vars/per-machine/` — generated clan vars (secrets committed encrypted, plaintext gitignored).
- `sops/` — sops age keys.

---

## Adding a machine to syncthing

Syncthing keeps `~/Public` in sync across clan machines. When a new machine joins, add it as a peer in `clan.nix`:

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

Machines discover each other via their zerotier IPs — no manual device ID exchange.

---

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
