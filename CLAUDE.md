# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Clanarchy** is a NixOS declarative configuration using **clan-core** to manage five machines:

- `miralda` — Framework 13 AMD, NixOS 26.05. Niri + UWSM + regreet Wayland desktop, ZFS + impermanence, YubiKey PIV for age encryption, clan vars for secrets. Daily driver for `lgo`.
- `jens` — Framework 12 Intel (convertible 2-in-1), NixOS 26.05. Deliberately the same machine as `miralda` from the user's side: same Niri desktop, same Selenized Black theme and wallpapers, same ZFS + impermanence, same `lgo` toolchain. Differences are hardware only — Intel instead of AMD (`clanarchy.hardware.cpu`), a 1920×1200 panel, and `clanarchy.hardware.convertible.enable` for the accelerometer / auto-rotation / on-screen keyboard. No local Ollama: miralda's local-ai role is ROCm, which does not apply to an Intel iGPU. OpenCode is still there, reaching ernst's `qwen3-coder:30b` over a restricted SSH port-forward (`roles.opencode.…tunnel.enable`) rather than over an exposed ollama port.
- `biene` — Lenovo laptop, NixOS 26.05. labwc + UWSM + regreet Wayland desktop with Noctalia shell (Sabine's machine), ZFS + impermanence, clan vars for secrets.
- `birte` — Steam Deck OLED (Galileo). Jovian-NixOS Steam Gaming Mode by default; "Switch to Desktop" drops into KDE Plasma 6 via SDDM. Built entirely against `nixpkgs-unstable` (Jovian only supports unstable). Lives on branch `feat/birte-steamdeck` until merged.
- `ernst` — AM5 / X870E homelab server. NAS + VM host + GPU compute; encrypted mirrored `zroot` + encrypted `zdata` raidz1. Carries **two** machine-type roles: `server` (headless baseline) plus `htpc` — a living-room Steam Big Picture / KDE Plasma session on the TV, switchable at runtime. Stable channel throughout (the gamescope session is stock nixpkgs, not Jovian).

## Development Environment

Enter the devShell via direnv (`.envrc` uses `use flake`) or manually with `nix develop`.

**Deployment is the clan CLI — do not add a wrapper for it.**

```bash
clan machines update <machine>          # miralda | jens | biene | birte | ernst
clan machines update <m> --target-host root@host   # override the configured address
clan vars generate <machine>            # (re)generate secrets, then update
```

The devShell used to carry `deploy`, `deploy-<machine>`, `test-pr` and
`test-vm`. They are gone, deliberately: they drove `nixos-rebuild` directly and
so skipped clan's inventory evaluation, which meant they could not apply
secrets or vars — a second deploy path that quietly did less. Do not reintroduce
them, in any form, including as a thin alias. See [docs/guides/deploy.md](docs/guides/deploy.md).

Note there is no stage-for-next-boot mode: `clan machines update` runs
`switch-to-configuration boot` *and* `switch`.

The devShell provides these shell functions:

```bash
push [remote] [branch]        # git push via gh credential helper (read-only ~/.config/git under impermanence)
gendocs                       # regenerate docs/reference/*.md from live NixOS config
docs serve                    # local mkdocs preview
```

Key packages in devShell: `clan-cli`, `git`, `openssh`, `nixos-rebuild`, `age-plugin-yubikey`, `sops`, `python3` + `python3Packages.mkdocs-material` (for `gendocs` and `docs serve` — note the local preview runs mkdocs; CI publishes with properdocs).

**When pinentry is broken** (e.g. after a miralda rebuild that changes `modules/hardware/yubikey.nix`): use a local rebuild to avoid the SSH chicken-and-egg problem:
```bash
sudo nixos-rebuild switch --flake .#miralda --no-reexec -j auto
gpgconf --kill gpg-agent && gpg --card-status
```

**Important**: Always use `--no-reexec` (not `--fast`) with nixos-rebuild. Never use `--build-host localhost`.

## Git Workflow

**Never commit directly to `main`.** All changes — even single-file docs edits — go on a named, prefix-tagged branch and land on `main` via a pull request.

Branch naming: `<type>/<short-kebab-slug>`. Use one of these prefixes:

| Prefix | For |
|--------|-----|
| `feat/`  | New user-visible feature or module |
| `fix/`   | Bug fix |
| `docs/`  | Docs, CLAUDE.md, README, guides |
| `chore/` | Tooling, deps, flake bumps, refactors with no behaviour change |
| `vars/`  | Clan-vars regeneration only |
| `wip/`   | Exploratory work not yet ready for review |

Examples: `feat/ernst-machine`, `fix/greetd-restart-loop`, `docs/git-branch-workflow`, `chore/flake-bump-2026-07`.

Workflow for any change:

1. Start from an up-to-date `main`: `git fetch origin && git switch main && git merge --ff-only origin/main`.
2. Create the branch: `git switch -c <type>/<slug>`.
3. Commit only the files this change touches — never `git add -A` when unrelated work is in the working tree.
4. Push: `push origin <branch>` (the devShell function) or `git push -u origin <branch>`.
5. Open a PR with `gh pr create`. Title: imperative, ≤70 chars, no prefix. Body: summary + test plan.
6. Never force-push to `main`. Never merge locally into `main`; merging happens via the PR (see [docs/guides/accepting-pull-requests.md](docs/guides/accepting-pull-requests.md)).

If Claude is asked to make a change while `HEAD` is on `main`, Claude must create a branch first and tell the user which prefix it chose.

## Installing a Machine from Scratch

The full walkthrough — `clan flash write` + `clan machines install <name>` — lives in [docs/guides/first-time-install.md](docs/guides/first-time-install.md). Points that always bite:

- **SSH key**: use the YubiKey ed25519 pubkey at `machines/miralda/yubikey_ed25519.pub`. It's authorised on every clan machine, so `miralda` can SSH into the installer without extra setup.
- **clan-core rev**: `clan flash write --flake` must match the rev this project's `clan` CLI was built from. Read it from `flake.lock` via `nix flake metadata --json . | jq -r '.locks.nodes["clan-core"].locked.rev'` — mismatch causes `attribute 'vars' missing`.
- **`clan flash` wipes the USB stick entirely.** Confirm the device path with `lsblk` first.

**Post-install: Noctalia profile for Sabine (`biene`)** — see [docs/guides/noctalia-profiles.md](docs/guides/noctalia-profiles.md). Short version: Sabine saves her layout once as a Shell Profile named `Sabine`; the HM activation hook in `modules/users/sabine.nix` restores it on every subsequent `clan machines update biene`. To pin the profile so it survives future fresh installs, `scp` the settings.json out of biene into `modules/users/sabine-noctalia-settings.json` and wire it via `xdg.configFile`.

## Architecture

### Flake Structure

- `flake.nix` — inputs, devShell, and `clan.machines.*` composition. Each machine block uses helpers from `lib/mk-machine.nix` to avoid repeating boilerplate.
- `lib/mk-machine.nix` — `mkModuleArgs`, `stylixKmsconFix`, `commonBase`, `commonHeadful`. See "Machine Composition Helpers" under Key Design Decisions. Per-machine nixpkgs channel selection is in `modules/channel.nix` (option `clanarchy.channel = "stable" | "unstable"`).
- `clan.nix` — clan-core metadata (`name = "clanarchy"`, `domain = "goclan.org"`), the stable `pkgsForSystem` instance, clan-service inventory instances (see Service Modules below).
- `lib/overlays.nix` — the nixpkgs overlays (niri sandbox fix, ungoogled-chromium privacy flags), applied to **both** pkgs instances: the stable one in `clan.nix` and the unstable one in `lib/mk-machine.nix`. A machine on `clanarchy.channel = "unstable"` takes its whole `pkgs` from the latter, so an overlay listed in only one place silently doesn't apply there.
- `machines/<name>/` — machine-specific NixOS configs (see per-machine tables).
- `modules/` — shared NixOS modules used by multiple machines (see below).
- `service-modules/` — custom clan-service modules registered in `clan.nix` (see below).
- `vars/per-machine/<machine>/` — generated secrets/configs (clan vars).
- `sops/` — sops keys and age identity.

### Machine Module Layout (`machines/miralda/`)

All modules are explicitly imported in `flake.nix` (no auto-discovery):

| File | Purpose |
|------|---------|
| `configuration.nix` | Hostname, timezone, ZFS/systemd-boot, SSH daemon, per-user overrides |
| `disko.nix` | Thin wrapper over `modules/disko/base.nix` — NVMe device path, encryption on |
| `home-modules/browsers.nix` | HM: Chromium/LibreWolf per-user config |
| `home-modules/console-desktop.nix` | HM: TTY / console-only fallback session for `lgo` |
| `yubikey_ed25519.pub`, `yubikey_rsa.pub`, `clanarchy_admin.pub` | Committed SSH pubkeys used across the clan |
| `facter.json` | nixos-facter hardware fingerprint |

miralda's theme and wallpapers used to live here as `stylix.nix` / `wallpapers.nix`. They are now `modules/themes/selenized-black.nix` and `modules/wallpapers/nix-anarchy.nix`, shared with `jens` — neither file ever contained anything machine-specific, and keeping two copies in step by hand was not going to work. `machines/biene/` and `machines/birte/` still carry their own `stylix.nix`, because they run a different palette.

### Machine Module Layout (`machines/jens/`)

| File | Purpose |
|------|---------|
| `configuration.nix` | Hostname, timezone, Intel CPU/GPU, convertible + ZSA hardware, apps, syncthing user |
| `disko.nix` | Thin wrapper over `modules/disko/base.nix` — NVMe device path, encryption on, no swap |
| `facter.json` | nixos-facter hardware fingerprint |

No `stylix.nix` or `wallpapers.nix`: `flake.nix` imports the shared `modules/themes/selenized-black.nix` + `modules/wallpapers/nix-anarchy.nix` for this machine, same as miralda.

### Machine Module Layout (`machines/biene/`)

| File | Purpose |
|------|---------|
| `configuration.nix` | Hostname, timezone, ZFS/systemd-boot, SSH daemon, Syncthing user override |
| `disko.nix` | Thin wrapper over `modules/disko/base.nix` — unencrypted pool, 8G plain swap for hybrid-sleep |
| `stylix.nix` | Catppuccin Mocha theme; imports `modules/stylix-base.nix` |
| `wallpapers.nix` | Nix-Anarchy SVG (logo-blue) rendered at native 1366×768; seeds `~/Pictures/Wallpapers/clanarchy.png` + pins `~/.cache/noctalia/wallpapers.json` |
| `facter.json` | nixos-facter hardware fingerprint |

### Machine Module Layout (`machines/birte/`)

| File | Purpose |
|------|---------|
| `configuration.nix` | Hostname, timezone, btrfs/systemd-boot, SSH daemon; `clanarchy.rootfs = "btrfs"`; Steam Deck power/hardware tweaks |
| `disko.nix` | Thin wrapper over `modules/disko/btrfs.nix` — btrfs (not ZFS), unencrypted, 16G plain swap for hybrid-sleep, `@games` subvol at `/games` (symlinked into deck's home) |
| `jovian.nix` | Jovian-NixOS wiring: Steam Gaming Mode enablement, gamescope-session, `deck` user provisioning |
| `deck.nix` | Deck-specific user config + HM stylix enablement |
| `stylix.nix` | Catppuccin Mocha theme, SVG-recolored wallpaper at native 1280×800; imports `modules/stylix-base.nix` (no regreet target — SDDM is Jovian-provisioned) |

### Machine Module Layout (`machines/ernst/`)

| File | Purpose |
|------|---------|
| `configuration.nix` | Hostname, timezone, ZFS/systemd-boot, SSH daemon |
| `disko.nix` | Multi-disk hand-written disko: mirrored encrypted `zroot` (2× 960 GB SAS SSD) + raidz1 encrypted `zdata` (6× 15.36 TB SAS SSD). Does NOT use `modules/disko/base.nix` |
| `hardware-configuration.nix` | Bootloader + kernel modules for the AM5 / X870E board |
| `htpc.nix` | `go` user (couch account, deliberately not in `wheel`) + password vars generator; Steam library symlinked onto `zdata/games` |

### Shared Module Layout (`modules/`)

Shared modules imported by `commonBase` / `commonHeadful` (see `lib/mk-machine.nix`) or by individual machines / service modules:

| File | Purpose |
|------|---------|
| `base.nix` | Universal defaults: EFI boot, Plymouth, flakes, openssh baseline, zsh |
| `rootfs.nix` | `clanarchy.rootfs` option (`zfs` | `btrfs`) + impermanence bits shared by both backends (persist paths, stage-1 mounts) |
| `zfs-impermanence.nix` | ZFS backend: rollback-on-boot of root + home (stage 1). Active when `clanarchy.rootfs = "zfs"` (default) |
| `btrfs-impermanence.nix` | btrfs backend: rollback-on-boot of `@root` **and** `@home`, seeded automatically on first boot. Active when `clanarchy.rootfs = "btrfs"` (birte) |
| `vm-variant.nix` | QEMU-friendly overrides for `nixos-rebuild build-vm` (no devShell helper wraps this) |
| `locale.nix` | `clanarchy.locale` option: language + keyboard layout/variant/options |
| `networking/mdns.nix` | Avahi / mDNS — `<hostname>.local` across LAN + ZeroTier |
| `networking/resolved.nix` | systemd-resolved fleet defaults: public FallbackDNS (1.1.1.1 9.9.9.9); no global DNS/search (per-link only, avoids off-LAN breakage on roaming machines) |
| `networking/skynet-dns-nm.nix` | NM machines only: extends the clan-core-created "home" wifi profile with `dns-search = "~. skynet.lan"` + `dns-priority = -100` so Technitium (10.0.5.3 via DHCP) is the sole resolver whenever the home LAN is active |
| `networking/initrd-ssh.nix` | Opt-in stage-1 SSH server for remote pool/passphrase unlock. `clanarchy.initrdSsh.{enable,port,hostKey,authorizedKeyFiles,interface,address,gateway,kernelModules}`. Requires `boot.initrd.systemd.enable = true`. See `docs/guides/remote-unlock.md` |
| `virtualisation.nix` | libvirt / qemu / podman shared setup |
| `wifi.nix` | NetworkManager wifi profile from clan var (imported by biene + birte) |
| `caldav-sync.nix` | CalDAV sync helpers for shared calendar access |
| `icon-theme.nix` | `clanarchy.iconTheme` option: Stylix-recolored Papirus-Dark |
| `stylix-base.nix` | Shared stylix baseline for headful machines: fonts (Monaspace), cursor (Adwaita), `targets.plymouth`, polarity |
| `disko/base.nix` | Single-disk disko helper: 1G ESP + optional swap + ZFS `zroot`. Parameters: `device`, `enableSwap`, `swapSize`, `encryptSwap`, `enableEncryption` |
| `disko/btrfs.nix` | Single-disk btrfs sibling of `base.nix`: 1G ESP + optional swap + `@root`/`@nix`/`@home`/`@persist`/`@games` subvols. No LUKS. Parameters: `device`, `enableSwap`, `swapSize`, `encryptSwap`, `gamesMountpoint` |
| `hardware/cpu.nix` | Intel/AMD microcode selection |
| `hardware/gpu.nix` | GPU driver selection (AMD/Intel/NVIDIA) |
| `hardware/display.nix` | `clanarchy.display.scale` option: console font/mode scaling for boot/TTY |
| `hardware/printing.nix` | CUPS + hplip + SANE |
| `hardware/yubikey.nix` | pcscd + GnuPG agent (pinentry-qt wrapper) + polkit rule |
| `hardware/convertible.nix` | `clanarchy.hardware.convertible` option: iio-sensor-proxy, a `niri msg`-driven auto-rotate user service, and wvkbd. Imported fleet-wide, inert on clamshells. Consumer: jens |
| `themes/selenized-black.nix` | Shared Stylix theme (scheme + generated wallpaper + font sizes + regreet target) for miralda and jens |
| `wallpapers/nix-anarchy.nix` | Shared per-workspace nix-anarchy SVG wallpapers, recolored to the active Stylix palette. Consumers: miralda, jens |
| `desktop/desktop-common.nix` | Shared NixOS bits for all Noctalia-based Wayland compositors: regreet, pipewire, fonts, NetworkManager, Mullvad, Noctalia plugin runtime deps |
| `desktop/noctalia-hm.nix` | Shared HM: Noctalia settings, starship, swayidle, packages, activation hooks |
| `desktop/foot-hm.nix` | Shared HM: foot terminal config (Stylix-themed) |
| `desktop/niri.nix` | Niri compositor: UWSM session, XDG portal (gtk), fprintd, V4L2 loopback |
| `desktop/niri-hm.nix` | Niri HM: full KDL config (outputs, layout, keybinds, rules) |
| `desktop/labwc.nix` | labwc compositor: UWSM session, XDG portal (wlr+gtk), Valent, PAM service |
| `desktop/labwc-hm.nix` | labwc HM: rc.xml keybinds, themerc-override (Stylix colors), kanshi display service |
| `desktop/kde.nix` | KDE Plasma 6 desktop: SDDM, Plasma packages (used by birte's "Switch to Desktop" session) |
| `roles/laptop.nix` | Laptop role: fwupd (all laptops), thermald (Intel only), power-profiles-daemon, weekly Nix GC (14-day retention) |
| `roles/server.nix` | Server role (headless): no GUI packages, no laptop-only services |
| `roles/htpc.nix` | HTPC role: stock-nixpkgs gamescope Steam session + KDE Plasma behind one wrapper session, switched at runtime via `clanarchy-session-select` (and a `steamos-session-select` shim so Steam's own button works). Installs a couch media client (Jellyfin Media Player by default) — Plasma Bigscreen is not packaged in 26.05. Options: `user`, `defaultSession`, `autologin.enable`, `mediaClient.{enable,package}` |
| `roles/vm.nix` | VM guest role: SPICE agent, QEMU guest tools |
| `roles/rpi.nix` | Raspberry Pi role (unused; kept for future clan expansion) |
| `users/admin.nix` | admin user: SSH keys, password, impermanence, HM stub |
| `users/lgo.nix` | lgo power user: SSH config, browsers, devtools, Noctalia; `clanarchy.users.lgo.editor` option (govim \| helix, default govim) |
| `users/sabine.nix` | sabine user: impermanence, HM config, Noctalia plugins declaration |
| `users/sgo.nix` | sgo alt user (miralda only) |
| `users/sabine-noctalia/` | Sabine's pinned Noctalia plugin assets (e.g. `simple_mouse`) |
| `apps/default.nix` | Aggregator; imports each `apps/*.nix` |
| `apps/communication.nix` | `clanarchy.apps.communication`: messaging apps (Valent, etc.) |
| `apps/containers.nix` | `clanarchy.apps.containers`: Podman / container tooling |
| `apps/desktop-tools.nix` | `clanarchy.apps.desktopTools`: desktop utilities bundle |
| `apps/flatpak.nix` | `clanarchy.apps.flatpak`: Flatpak + Flathub remote |
| `apps/gnome-core.nix` | `clanarchy.apps.gnomeCoreApps`: a few standalone GTK apps (text editor, calculator, software centre). Consumer: biene. Not the GNOME desktop — that was removed |
| `apps/graphics.nix` | `clanarchy.apps.graphics`: graphics/creative apps (GIMP, Inkscape, etc.) |
| `apps/media.nix` | `clanarchy.apps.media`: media playback apps |

### Service Modules (`service-modules/`)

Custom clan-service modules registered in `clan.nix` under `modules."@clanarchy/<name>"`. Referenced by `module.name = "@clanarchy/<name>"` in `inventory.instances`, which assigns per-machine roles/settings:

| Module | Purpose | Used by (in `clan.nix`) |
|--------|---------|-------------------------|
| `@clanarchy/machine-type` | Hardware/role archetype dispatch: `laptop` / `server` / `htpc` (imports the matching `modules/roles/*.nix`). Roles compose — a machine may hold more than one | miralda/jens/biene/birte (laptop), ernst (server + htpc) |
| `@clanarchy/desktop` | Desktop dispatch: `niri` / `labwc` / `kde` (imports the matching `modules/desktop/*.nix`) | miralda + jens (niri), biene (labwc), birte (kde) |
| `@clanarchy/users` | User dispatch: `lgo` / `sabine` (imports the matching `modules/users/*.nix`) | miralda + jens (lgo), biene (sabine) |
| `@clanarchy/yubikey` | Imports `modules/hardware/yubikey.nix` on target machines | miralda, jens |
| `@clanarchy/printing` | Imports `modules/hardware/printing.nix` on target machines | miralda, jens |
| `@clanarchy/software` | Per-user browser + email software dispatch (librewolf, firefox, chromium, chrome, edge, thunderbird) | miralda + jens (lgo), biene (sabine), birte (deck — chromium + chrome, for Desktop Mode) |
| `@clanarchy/local-ai` | Ollama + OpenCode (self-hosted LLM stack). `opencode` can reach a remote ollama over a restricted SSH port-forward rather than needing one locally | ollama: miralda, ernst; opencode: miralda (local), jens (tunnelled to ernst) |
| `@clanarchy/monitoring` | `client`: node_exporter (+ optional zfs / smartctl / systemd) on every machine. `server`: Prometheus + Alertmanager + Grafana in one nspawn container. **Scrape targets are derived from `roles.client` membership**, so adding a machine to the role is the only step needed to monitor it | client: all five; server: ernst |

Plus stock clan services used verbatim: `sshd`, `zerotier`, `syncthing`, `wifi`.

### Clan Vars

Secrets are generated via `clan.core.vars.generators.<name>` modules (either inside `service-modules/` or, for clan-stock services, inside clan-core itself). Each generator specifies:
- `files.<name>` — output file (with `secret` flag, `neededFor` timing)
- `prompts.<name>` — user input at generation time
- `script` + `runtimeInputs` — generation logic

Generated outputs land in `vars/per-machine/<machine>/`. Run generators with `clan vars generate <machine>`.

### Key Design Decisions

**Machine Composition Helpers (`lib/mk-machine.nix`)**: Every clan machine needs the same `_module.args` injection (`pkgs-unstable` + `inputs`), the same stylix kmscon workaround, and the same list of shared modules. Instead of repeating that boilerplate in each `clan.machines.<name>` block, `lib/mk-machine.nix` exports `mkModuleArgs`, `stylixKmsconFix` (bundled into `commonHeadful`), plus two shared imports lists: `commonBase` (universal — impermanence, HM, `modules/base.nix`, `modules/channel.nix`, `rootfs.nix`, `zfs-impermanence.nix`, `btrfs-impermanence.nix`, `vm-variant.nix`, `locale.nix`, `networking/mdns.nix`, `networking/resolved.nix`, `networking/initrd-ssh.nix`, `hardware/cpu.nix`, `hardware/gpu.nix`, `hardware/zsa.nix`, `hardware/convertible.nix`, `virtualisation.nix`, `nix-remote-builder.nix`, `users/admin.nix`, `observability/zfs-ntfy.nix`) and `commonHeadful` (`commonBase` + stylix + `hardware/display.nix` + `networking/skynet-dns-nm.nix` + `modules/apps`). `ernst` uses `commonBase`; the others use `commonHeadful`.

**Per-machine nixpkgs channel (`modules/channel.nix`)**: `clanarchy.channel = "stable"` (default) keeps the clan-core pin; `clanarchy.channel = "unstable"` swaps the machine's `nixpkgs.pkgs` to `nixpkgs-unstable`. Used by birte for Jovian compatibility. The override uses `mkOverride 25` to win against clan-core's `overridePkgs.nix` `mkForce`.

**Impermanence**: Two backends, selected per machine by `clanarchy.rootfs` (declared in `modules/rootfs.nix`, which also holds the shared persist paths). Both backends are imported unconditionally by `commonBase` and each guards its own body on the option — the same pattern as `modules/channel.nix`.

- `clanarchy.rootfs = "zfs"` (default; miralda, jens, biene, ernst) — root **and home** roll back to `@blank` ZFS snapshots on boot. The snapshots are **not** created automatically; a machine missing them silently isn't impermanent at all, which is exactly what happened to ernst for a month. `clanarchy-impermanence-check.service` now fails loudly when they're absent — if a deploy reports it, that machine is accumulating state outside `/persist`. See [docs/runbooks/ernst-enable-impermanence.md](docs/runbooks/ernst-enable-impermanence.md).
- `clanarchy.rootfs = "btrfs"` (birte) — `@root` and `@home` both roll back, to `@root-blank` / `@home-blank` subvolume snapshots, seeded automatically on first boot. Behaviourally equivalent to the ZFS backend.

The shared system-level persist set lives in `modules/rootfs.nix`: `/var/lib/nixos`, `/var/lib/sops-nix`, `/var/log`, `/var/lib/systemd`, plus `/etc/machine-id`. Modules add their own as needed — e.g. `/var/lib/libvirt` (virtualisation), `/var/lib/private/ollama` (local-ai), `/var/lib/clanarchy-session` (htpc role). Per-user paths (`.gnupg`, `.config`, `.local/share`, …) are declared in `modules/users/*.nix` and the machine's user modules.

`/var/lib/zerotier-one` is deliberately **not** persisted, despite what earlier revisions of this file claimed. clan-core sources each node's ZeroTier identity from a clan var (`zerotier-identity-<machine>.files.identity-secret`), so it is redeployed from sops on every boot and survives rollback without `/var/lib` state. Persisting the directory would add a second, competing source of truth for the node ID.

**Why birte is btrfs**: out-of-tree OpenZFS gates the kernel. birte tracks `nixpkgs-unstable` and a Valve kernel via Jovian (`clanarchy.channel = "unstable"`), so it can't afford that coupling; btrfs is in-tree and follows whatever kernel Jovian ships.

**Game libraries** (birte's `@games` subvol, ernst's `zdata/games` dataset) sit **outside** both the rollback path and the impermanence bind-mounts, and are symlinked into the gaming user's home by a tmpfiles `L+` rule that re-forces the link after every rollback. Two reasons they are not mounted straight at `~/.local/share/Steam`: that path is restored as an impermanence bind-mount, which would shadow anything mounted underneath it; and keeping the library on its own subvol/dataset lets it carry `nodatacow` (CoW badly fragments large, repeatedly-rewritten game files) without imposing that on `@home`. A `d` tmpfiles rule fixes ownership, since a fresh subvolume/dataset is `root:root`.

**greetd/tuigreet**: Must pass `--sessions /run/current-system/sw/share/wayland-sessions`. Never use `--remember-session`, `--remember-user-session`, or any other cache-writing flag — tuigreet 0.9.1 panics with a crossterm `reader source not set` error when the cache is absent or stale after ZFS rollback, causing greetd to hit its restart limit. Never add TTY systemd overrides to the greetd unit.

**YubiKey + pcscd**: SSH sessions lack an "active" logind session, so pcscd requires a polkit rule via `security.polkit.extraConfig` (not `extraRules`). The `age-plugin-yubikey` package must be in the devShell for sops re-encryption with YubiKey recipients.

**scdaemon + pcscd**: `~/.gnupg/scdaemon.conf` must contain `disable-ccid`. Without it, scdaemon defaults to trying the internal CCID/libusb driver first, which races with pcscd and produces "No such device" even when the YubiKey is present. `disable-ccid` forces scdaemon to route all card access through pcscd (socket-activated on demand). This is managed declaratively via `home.file.".gnupg/scdaemon.conf"` in `modules/users/lgo.nix`. If the card is suddenly missing: `gpgconf --kill gpg-agent && gpg --card-status`.

**YubiKey pinentry**: Use `pinentry-qt`, not `pinentry-gnome3`. `pinentry-gnome3` calls `gcr_system_password_finish` via D-Bus (`org.gnome.keyring.SystemPrompter`), which requires `gnome-keyring-daemon` — absent on Niri. Without it every PIN prompt fails silently and gpg-agent returns "agent refused operation" on all card-backed SSH signing. `pinentry-qt` draws its own Qt dialog on Wayland with no GNOME dependency. The wrapper in `modules/hardware/yubikey.nix` injects `WAYLAND_DISPLAY` and `QT_QPA_PLATFORM=wayland` so Qt picks the right backend when called from the gpg-agent context.

**Niri overlay**: `clan.nix` overrides niri with `checkPhase = ":"` to bypass an EMFILE sandbox test failure in nixpkgs 25.11.

**pkgs-unstable**: `nixpkgs-unstable` intentionally does NOT follow clan-core's nixpkgs — it's needed for Noctalia/Quickshell. Injected as a module arg via `_module.args` (see `mkModuleArgs` in `lib/mk-machine.nix`).

**push function**: Reads gh token at runtime to construct HTTPS remote URL, enabling pushes from a machine where `~/.config/git` is a read-only impermanence bind mount.

**icon-theme.nix**: Declares `clanarchy.iconTheme.{name,package}` and installs the package via `environment.systemPackages`. Niri and labwc wire `gtk.iconTheme` in their respective `-hm.nix` modules via `osConfig`. Do **not** set `gtk.iconTheme` in `home-manager.sharedModules` — it conflicts with Stylix's GTK HM target and breaks the entire HM activation for affected users.

**labwc window decorations**: `labwc-hm.nix` generates `~/.config/labwc/themerc-override` from `config.lib.stylix.colors` at build time. This patches the active openbox theme's title bar, border, and button colors to follow the Stylix palette — active border uses `base0D` (accent), active title uses `base01`, inactive recedes to `base00`.

**lgo editor option** (`clanarchy.users.lgo.editor`): Selects between `"govim"` (default) and `"helix"`. govim is a flake input (`github:lutzgo/govim`) built on nvf; it's wired via `programs.nvf.settings` (nvf's HM module namespace) with `imports = [common.nix, variants/default.nix]`. Stylix theming uses `vim.theme.enable = false` + `pkgs.vimPlugins.base16-nvim` + `vim.luaConfigRC.stylixTheme` (DAG entry via `inputs.nvf.lib.nvim.dag`). The nvf HM option namespace must be declared at the NixOS level via `home-manager.sharedModules`; per-user imports cannot bootstrap their own option types. `inputs.nvf` is pinned as `nvf.follows = "govim/nvf"` in `flake.nix`. `EDITOR`/`VISUAL`, Zellij `Alt+e`, and Yazi `e` all key off the same `editorBin` variable.
