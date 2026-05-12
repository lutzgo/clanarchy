# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Clanarchy** is a NixOS declarative configuration using **clan-core** to manage two machines:
- `miralda` — Framework 13 AMD, NixOS 26.05. Niri/UWSM/greetd Wayland desktop, ZFS + impermanence, YubiKey PIV for age encryption, clan vars for secrets.
- `biene` — Lenovo laptop, NixOS 26.05. GNOME/GDM desktop (Sabine's machine), ZFS + impermanence, clan vars for secrets.

## Development Environment

Enter the devShell via direnv (`.envrc` uses `use flake`) or manually with `nix develop`.

The devShell provides these shell functions:

```bash
deploy [boot|switch]          # default: switch
# nixos-rebuild --flake .#miralda with --no-reexec, targets root@miralda.goclan.org

deploy-biene [boot|switch]    # default: switch
# nixos-rebuild --flake .#biene with --no-reexec, targets root@biene.local
# Override host: BIENE_HOST=biene.skynet.lan deploy-biene

push [remote] [branch]        # defaults: origin main
# git push via gh auth token (works with read-only ~/.config/git under impermanence)
```

Key packages in devShell: `clan-cli`, `git`, `openssh`, `nixos-rebuild`, `age-plugin-yubikey`.

**When pinentry is broken** (e.g. after a miralda rebuild that changes `yubikey.nix`): use a local rebuild to avoid the SSH chicken-and-egg problem:
```bash
sudo nixos-rebuild switch --flake .#miralda --no-reexec -j auto
gpgconf --kill gpg-agent && gpg --card-status
```

**Important**: Always use `--no-reexec` (not `--fast`) with nixos-rebuild. Never use `--build-host localhost`.

## Architecture

### Flake Structure

- `flake.nix` — top-level, defines devShell, machine composition for both machines, injects `pkgs-unstable` and `inputs` as module args
- `clan.nix` — clan-core metadata (`name = "clanarchy"`, `domain = "goclan.org"`), nixpkgs overlay (niri sandbox fix), clan instances (sshd, zerotier)
- `machines/miralda/` — miralda-specific NixOS + Home Manager modules
- `machines/biene/` — biene-specific NixOS modules
- `modules/` — shared NixOS modules used by both machines (see below)
- `vars/per-machine/<machine>/` — generated secrets/configs (clan vars)
- `sops/` — sops keys and age identity

### Machine Module Layout (`machines/miralda/`)

All modules are explicitly imported in `flake.nix` (no auto-discovery):

| File | Purpose |
|------|---------|
| `configuration.nix` | Hostname, timezone, ZFS/systemd-boot, SSH daemon |
| `disko.nix` | NVMe → GPT (1G ESP + ZFS pool, AES-256-GCM) |
| `impermanence.nix` | ZFS rollback-on-boot (stage 1); persist paths |
| `desktop.nix` | Niri + UWSM + greetd, Framework hw (fprintd, fwupd), pipewire, NetworkManager |
| `stylix.nix` | Gruvbox Dark Medium theme + generated wallpaper |
| `yubikey.nix` | pcscd, GnuPG agent (pinentry-qt), polkit rule for SSH sessions |
| `wifi.nix` | NetworkManager profile from `wifi-home` clan var |
| `users/admin.nix` + `users/lgo.nix` | System users |
| `home/admin.nix` + `home/lgo.nix` | Home Manager configurations |
| `home-modules/desktop.nix` | Shared HM module: Niri settings, Noctalia, touchpad, packages |
| `secrets/admin.nix` + `secrets/lgo.nix` + `secrets/wifi.nix` | Clan vars generators |

### Machine Module Layout (`machines/biene/`)

| File | Purpose |
|------|---------|
| `configuration.nix` | Hostname, timezone, ZFS/systemd-boot, SSH daemon, module activation |
| `disko.nix` | NVMe → GPT (1G ESP + ZFS pool) |
| `impermanence.nix` | ZFS rollback-on-boot (stage 1); persist paths |
| `stylix.nix` | Catppuccin Mocha theme + generated anarchy wallpaper |
| `syncthing.nix` | Syncthing file sync |

### Shared Module Layout (`modules/`)

Shared modules are imported by machines via their desktop/role modules:

| File | Purpose |
|------|---------|
| `desktop/gnome.nix` | GNOME desktop: GDM, extensions, shared dconf, Sabine's dconf |
| `desktop/niri.nix` | Niri compositor: UWSM, regreet, pipewire, fonts |
| `desktop/niri-hm.nix` | Shared HM module for Niri users: Niri config, Noctalia, keybinds |
| `icon-theme.nix` | `clanarchy.iconTheme` option: Stylix-recolored Papirus-Dark; imported by both desktop modules |
| `locale.nix` | `clanarchy.locale` option: language + keyboard layout/variant/options |
| `users/admin.nix` | admin user: SSH keys, password, impermanence, HM stub |
| `users/lgo.nix` | lgo power user: SSH config, browsers, devtools, Noctalia; `clanarchy.users.lgo.editor` option (govim \| helix, default govim) |
| `users/sabine.nix` | sabine user: impermanence, HM config |
| `wifi.nix` | NetworkManager profile generator (clan var) |
| `hardware/cpu.nix` | Intel/AMD microcode selection |
| `networking.nix` | ZeroTier + DNS options |
| `roles/laptop.nix` | Laptop role: fwupd, power-profiles-daemon, tlp |

### Clan Vars

Secrets are generated via `clan.core.vars.generators.<name>` modules in `secrets/`. Each generator specifies:
- `files.<name>` — output file (with `secret` flag, `neededFor` timing)
- `prompts.<name>` — user input at generation time
- `script` + `runtimeInputs` — generation logic

Generated outputs land in `vars/per-machine/miralda/`. Run generators with `clan vars generate`.

### Key Design Decisions

**Impermanence**: Root and home roll back to `@blank` ZFS snapshots on boot. Persisted paths include: `/var/lib/sops-nix`, `/var/lib/systemd`, `/var/lib/zerotier-one`, user `.gnupg`, `.config`, `.local/share`.

**greetd/tuigreet**: Must pass `--sessions /run/current-system/sw/share/wayland-sessions`. Never use `--remember-session`, `--remember-user-session`, or any other cache-writing flag — tuigreet 0.9.1 panics with a crossterm `reader source not set` error when the cache is absent or stale after ZFS rollback, causing greetd to hit its restart limit. Never add TTY systemd overrides to the greetd unit.

**YubiKey + pcscd**: SSH sessions lack an "active" logind session, so pcscd requires a polkit rule via `security.polkit.extraConfig` (not `extraRules`). The `age-plugin-yubikey` package must be in the devShell for sops re-encryption with YubiKey recipients.

**YubiKey pinentry**: Use `pinentry-qt`, not `pinentry-gnome3`. `pinentry-gnome3` calls `gcr_system_password_finish` via D-Bus (`org.gnome.keyring.SystemPrompter`), which requires `gnome-keyring-daemon` — absent on Niri. Without it every PIN prompt fails silently and gpg-agent returns "agent refused operation" on all card-backed SSH signing. `pinentry-qt` draws its own Qt dialog on Wayland with no GNOME dependency. The wrapper in `yubikey.nix` injects `WAYLAND_DISPLAY` and `QT_QPA_PLATFORM=wayland` so Qt picks the right backend when called from the gpg-agent context.

**Niri overlay**: `clan.nix` overrides niri with `checkPhase = ":"` to bypass an EMFILE sandbox test failure in nixpkgs 25.11.

**pkgs-unstable**: `nixpkgs-unstable` intentionally does NOT follow clan-core's nixpkgs — it's needed for Noctalia/Quickshell. Injected as a module arg via `_module.args`.

**push function**: Reads gh token at runtime to construct HTTPS remote URL, enabling pushes from a machine where `~/.config/git` is a read-only impermanence bind mount.

**icon-theme.nix**: Declares `clanarchy.iconTheme.{name,package}` and installs the package via `environment.systemPackages`. GNOME wires the theme name via dconf in `gnome.nix`. Niri wires `gtk.iconTheme` in `niri-hm.nix` via `osConfig`. Do **not** set `gtk.iconTheme` in `home-manager.sharedModules` — it conflicts with Stylix's GTK HM target and breaks the entire HM activation for affected users.

**lgo editor option** (`clanarchy.users.lgo.editor`): Selects between `"govim"` (default) and `"helix"`. govim is a flake input (`github:lutzgo/govim`) built on nvf; it's wired via `programs.nvf.settings` (nvf's HM module namespace) with `imports = [common.nix, variants/default.nix]`. Stylix theming uses `vim.theme.enable = false` + `pkgs.vimPlugins.base16-nvim` + `vim.luaConfigRC.stylixTheme` (DAG entry via `inputs.nvf.lib.nvim.dag`). The nvf HM option namespace must be declared at the NixOS level via `home-manager.sharedModules`; per-user imports cannot bootstrap their own option types. `inputs.nvf` is pinned as `nvf.follows = "govim/nvf"` in `flake.nix`. `EDITOR`/`VISUAL`, Zellij `Alt+e`, and Yazi `e` all key off the same `editorBin` variable.
