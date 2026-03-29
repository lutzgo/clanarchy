# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Clanarchy** is a NixOS declarative configuration using **clan-core** to manage the `miralda` machine (Framework 13 AMD, NixOS 26.05). It uses Niri/UWSM/greetd for the Wayland desktop, ZFS + impermanence for rollback-on-boot, YubiKey PIV for age encryption, and clan vars for secrets generation.

## Development Environment

Enter the devShell via direnv (`.envrc` uses `use flake`) or manually with `nix develop`.

The devShell provides these shell functions:

```bash
deploy [boot|switch]          # default: switch
# nixos-rebuild --flake .#miralda with --no-reexec, targets root@miralda.goclan.org

push [remote] [branch]        # defaults: origin main
# git push via gh auth token (works with read-only ~/.config/git under impermanence)
```

Key packages in devShell: `clan-cli`, `git`, `openssh`, `nixos-rebuild`, `age-plugin-yubikey`.

**Important**: Always use `--no-reexec` (not `--fast`) with nixos-rebuild. Never use `--build-host localhost`.

## Architecture

### Flake Structure

- `flake.nix` — top-level, defines devShell, machine composition for `miralda`, injects `pkgs-unstable` and `inputs` as module args
- `clan.nix` — clan-core metadata (`name = "clanarchy"`, `domain = "goclan.org"`), nixpkgs overlay (niri sandbox fix), clan instances (sshd, zerotier)
- `machines/miralda/` — all machine-specific NixOS + Home Manager modules
- `vars/per-machine/miralda/` — generated secrets/configs (clan vars)
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
| `yubikey.nix` | pcscd, GnuPG agent, polkit rule for SSH sessions |
| `wifi.nix` | NetworkManager profile from `wifi-home` clan var |
| `users/admin.nix` + `users/lgo.nix` | System users |
| `home/admin.nix` + `home/lgo.nix` | Home Manager configurations |
| `home-modules/desktop.nix` | Shared HM module: Niri settings, Noctalia, touchpad, packages |
| `secrets/admin.nix` + `secrets/lgo.nix` + `secrets/wifi.nix` | Clan vars generators |

### Clan Vars

Secrets are generated via `clan.core.vars.generators.<name>` modules in `secrets/`. Each generator specifies:
- `files.<name>` — output file (with `secret` flag, `neededFor` timing)
- `prompts.<name>` — user input at generation time
- `script` + `runtimeInputs` — generation logic

Generated outputs land in `vars/per-machine/miralda/`. Run generators with `clan vars generate`.

### Key Design Decisions

**Impermanence**: Root and home roll back to `@blank` ZFS snapshots on boot. Persisted paths include: `/var/lib/sops-nix`, `/var/lib/systemd`, `/var/lib/zerotier-one`, user `.gnupg`, `.config`, `.local/share`.

**greetd/tuigreet**: Must pass `--sessions /run/current-system/sw/share/wayland-sessions`. Never use `--remember-session` (impermanence wipes the cache on boot). Never add TTY systemd overrides to the greetd unit.

**YubiKey + pcscd**: SSH sessions lack an "active" logind session, so pcscd requires a polkit rule via `security.polkit.extraConfig` (not `extraRules`). The `age-plugin-yubikey` package must be in the devShell for sops re-encryption with YubiKey recipients.

**Niri overlay**: `clan.nix` overrides niri with `checkPhase = ":"` to bypass an EMFILE sandbox test failure in nixpkgs 25.11.

**pkgs-unstable**: `nixpkgs-unstable` intentionally does NOT follow clan-core's nixpkgs — it's needed for Noctalia/Quickshell. Injected as a module arg via `_module.args`.

**push function**: Reads gh token at runtime to construct HTTPS remote URL, enabling pushes from a machine where `~/.config/git` is a read-only impermanence bind mount.
