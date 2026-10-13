# clanarchy

NixOS declarative configuration built on [clan-core](https://git.clan.lol/clan/clan-core), managing five machines:

| Machine | Hardware | Role |
|---------|----------|------|
| `miralda` | Framework 13 AMD | daily-driver laptop (Niri, YubiKey, lgo) |
| `jens` | Framework 12 Intel, convertible | second laptop, same desktop as miralda |
| `biene` | Lenovo laptop | Sabine's machine (labwc + Noctalia) |
| `birte` | Steam Deck OLED (Galileo) | Steam Gaming Mode via Jovian-NixOS; KDE Plasma 6 fallback |
| `ernst` | AM5/X870E homelab | headless server — NAS, VM host, GPU compute, ~20 containerised services |

**Stack:** ZFS or btrfs + impermanence · Wayland compositors (Niri, labwc, KDE) · Noctalia shell · YubiKey PIV (age) + GnuPG (SSH) · clan vars for secrets.

Full docs: **[lutzgo.github.io/clanarchy](https://lutzgo.github.io/clanarchy)** (or `docs serve` locally).

---

## Working on this repo

Read **[AGENTS.md](AGENTS.md)** first — it is the short version of every
convention here, and it is what both Claude Code and OpenCode read.

```bash
direnv allow          # or: nix develop
check                 # evaluate every machine — the one gate before a deploy
```

Changes go through a PR; nothing lands on `main` directly. The repo is driven
with [jj](docs/guides/jj-workflow.md), not git:

```bash
jj git fetch
jj new main -m "<message>"
# …edit. Editing again *is* amending; there is no add and no commit.
jj st                                     # read this before the next line
jj bookmark set <type>/<slug> -r @        # feat/ fix/ docs/ chore/ vars/ wip/
jj git push --bookmark <type>/<slug>
gh pr create --head <type>/<slug>
```

Prerequisites: Nix with flakes, and — for anything touching secrets on
`miralda` — a YubiKey with a PIV age identity. `clan-cli` comes from the
devShell.

## Deploying

The clan CLI, with no wrapper around it:

```bash
clan machines update <machine>       # miralda | jens | biene | birte | ernst
clan vars generate <machine>         # (re)generate secrets, then update
```

It needs a real terminal. See [deploy](docs/guides/deploy.md) for the flags, the
roaming overrides, and why the old `deploy-<machine>` helpers were removed.

## What else the devShell adds

```bash
check [machine…]             # evaluate machines; same script CI runs
push [remote] [branch]       # git push via gh credential helper (read-only ~/.config/git)
gendocs                      # regenerate docs/reference/*.md from live config
docs serve                   # local mkdocs preview
```

### Pushing with `gh`

Impermanence makes `~/.config/git` a read-only bind mount, so `gh auth setup-git` cannot write the global config it wants. The `push` function passes gh's git credential helper with `-c` instead, so the token is never spliced into a URL or into `argv`.

`jj git push` needs none of that: jj performs remote operations by spawning a real `git` subprocess, so it picks up the same credential helper that `programs.gh` already declares in `~/.config/git/config`. `push` is retained as the git-side escape hatch.

First-time setup (once per machine):
```bash
gh auth login
```

---

## Bootstrap (first-time machine install)

New machines are installed by booting the Clan installer USB, then running `clan machines install <name>` from an existing clan machine. The installer uses the YubiKey pubkey embedded in `machines/miralda/yubikey_ed25519.pub` so no manual SSH-key setup is needed.

Full walkthrough: **[docs/guides/first-time-install.md](docs/guides/first-time-install.md)**.
---

## YubiKey usage

The YubiKey serves two roles on `miralda`: **SSH authentication** (via GnuPG agent) and **age decryption** (PIV-backed identity for sops/clan vars). Full setup + troubleshooting in [docs/guides/yubikey.md](docs/guides/yubikey.md).

### When to plug in the YubiKey

| Task | YubiKey needed? |
|------|-----------------|
| `clan machines update miralda` (SSH to `root@miralda.goclan.org`) | **Yes** — GPG auth subkey |
| `clan vars generate` | **Yes** — decrypts/re-encrypts secrets |
| `clan machines update` | **Yes** — SSH + secret decryption |
| Editing config, `nix eval`, building | No |
| `jj git push` / `push` / `gh` operations | No — uses GitHub token |
| `jj describe` / `git commit` | No |

Updating `biene`, `birte` and `ernst` also needs SSH access to those targets, but they authenticate with the `clanarchy_admin` ed25519 key rather than the YubiKey.

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

Authoritative: **[docs/architecture/](docs/architecture/machines.md)** — the
machines, the modules and clan services, and the decisions whose reason is not
visible from the code. `docs/reference/` carries the generated `clanarchy.*`
option tables.

At a glance:

- `flake.nix` — inputs, devShell, flake `checks`, and clan machine composition (via `lib/mk-machine.nix`).
- `clan.nix` — clan-core metadata, nixpkgs overlays, and the clan-service inventory instances.
- `lib/mk-machine.nix` — `mkModuleArgs`, `commonBase`, `commonHeadful`.
- `modules/` — shared NixOS modules (hardware, roles, apps, desktop, users, disko and stylix bases).
- `service-modules/` — the `@clanarchy/*` clan services.
- `machines/<name>/` — per-machine configuration, disko, and extras.
- `vars/` — generated clan vars (encrypted in git; plaintext gitignored).
- `sops/` — sops age keys.

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
clan machines update <machine>   # on each machine
```

Machines discover each other via their zerotier IPs — no manual device ID exchange.

---

## Secrets & threat model

This repository is **public**, and sops/clan-vars ciphertexts are committed to it. That is the intended design — the secrets are encrypted to age recipients (machine keys plus a YubiKey PIV identity), and only holders of those keys can decrypt them. Nothing here relies on the repo being hard to find.

What it does mean is that **git history retains every ciphertext forever**. Rewriting history does not help: the repo is public, so any old revision may already have been cloned, forked, or archived. So if a machine's age key is ever compromised, re-encrypting to a new set of recipients is **not sufficient** — an attacker holding the old key can decrypt every historical ciphertext it was ever a recipient of, including versions you have since "removed". Recovery requires rotating the *underlying* secrets themselves: wifi PSKs, user password hashes, syncthing keys, the ntfy topic URLs, and anything else under `vars/`. Treat deleting a secret from the working tree as tidying up, not as revocation.

---

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
