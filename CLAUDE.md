# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Clanarchy** is a NixOS declarative configuration using **clan-core** to manage two machines:
- `miralda` — Framework 13 AMD, NixOS 26.05. Niri/UWSM/greetd Wayland desktop, ZFS + impermanence, YubiKey PIV for age encryption, clan vars for secrets.
- `biene` — Lenovo laptop, NixOS 26.05. labwc/UWSM/regreet Wayland desktop (Sabine's machine), ZFS + impermanence, clan vars for secrets.

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

## Installing a Machine from Scratch

Use this when disko must re-run (new disk layout, new machine). Requires booting the target from a Clan installer USB.

### Step 1 — Create the installer USB

**SSH key**: use the YubiKey ed25519 key already stored at `machines/miralda/yubikey_ed25519.pub`. This is the same key authorised on both machines, so you can SSH into the installer from miralda without extra setup.

From the devShell, with the USB stick identified (e.g. `/dev/sda` — confirm with `lsblk` first):

```bash
# Get the exact clan-core rev pinned in this flake:
CLAN_CORE_REV=$(nix flake metadata --json . | jq -r '.locks.nodes["clan-core"].locked.rev')

clan flash write \
  --flake "github:clan-lol/clan-core/$CLAN_CORE_REV" \
  --ssh-pubkey machines/miralda/yubikey_ed25519.pub \
  --keymap us --language en_US.UTF-8 \
  --disk main /dev/sda \
  flash-installer
```

> `clan flash write` writes a generic NixOS installer with the YubiKey pubkey embedded as the root authorized key. `--ssh-pubkey` takes a **file path**, not key content. The `--flake` must point to the **same clan-core rev** that this project's `clan` CLI was built from — mismatched versions cause `attribute 'vars' missing` errors. Using the rev from `flake.lock` (via `nix flake metadata`) guarantees they match. Machine-specific config is applied later by `clan machines install`.

**Warning**: `clan flash` wipes the target USB stick entirely. Double-check the device path.

### Step 2 — Boot the target machine

Insert the USB into biene, boot from it (F12 or BIOS boot menu). The installer brings up a minimal NixOS with SSH on port 22.

Find biene's IP (check your router/Fritz!Box, or use `arp-scan -l` from miralda):

```bash
ssh root@<biene-installer-ip>   # authenticates via YubiKey
```

### Step 3 — Install

From the devShell on miralda:

```bash
clan machines install biene --target-host root@<biene-installer-ip>
```

This runs disko (partitions and formats the disk) then installs NixOS with all clan vars applied. After the machine reboots into the new system, use the normal deploy workflow:

```bash
deploy-biene   # or: BIENE_HOST=<ip> deploy-biene
```

### Post-install: Noctalia profile for Sabine

After first login on biene:
1. Noctalia starts with the default declarative settings from `labwc-hm.nix`.
2. Plugins listed in `plugins.json` are declared — Noctalia re-downloads their source files from the plugin store on first run.
3. Sabine configures her preferred layout via the Noctalia UI.
4. She saves it: **Settings → Shell Profiles → Save Profile** → name it **"Sabine"**.
5. Every subsequent `deploy-biene` rebuild auto-restores her profile via the HM activation hook in `modules/users/sabine.nix`.

To pin the profile so it survives future fresh installs:
```bash
scp root@biene.local:/home/sabine/.config/noctalia/plugins/shell-profiles/assets/profiles/Sabine/settings.json \
    modules/users/sabine-noctalia-settings.json
```
Then add to `modules/users/sabine.nix` (inside `home-manager.users.sabine`):
```nix
xdg.configFile."noctalia/plugins/shell-profiles/assets/profiles/Sabine/settings.json".source =
  ./sabine-noctalia-settings.json;
```

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
| `configuration.nix` | Hostname, timezone, ZFS/systemd-boot, SSH daemon; Syncthing user override |
| `disko.nix` | NVMe → GPT (1G ESP + ZFS pool) |
| `stylix.nix` | Catppuccin Mocha theme; `targets.regreet.enable` for greeter theming |

### Shared Module Layout (`modules/`)

Shared modules are imported by machines via their desktop/role modules:

| File | Purpose |
|------|---------|
| `desktop/gnome.nix` | GNOME desktop: GDM, extensions, shared dconf, Sabine's dconf |
| `desktop/desktop-common.nix` | Shared NixOS config for all Noctalia-based Wayland compositors: regreet, pipewire, fonts, NetworkManager, Mullvad, Noctalia plugin runtime deps |
| `desktop/noctalia-hm.nix` | Shared HM module for all desktop users: Noctalia settings, starship, swayidle, packages, activation hooks |
| `desktop/niri.nix` | Niri compositor: UWSM session, XDG portal (gtk), fprintd, V4L2 loopback |
| `desktop/niri-hm.nix` | Niri-specific HM: full KDL config (outputs, layout, keybinds, rules) |
| `desktop/labwc.nix` | labwc compositor: UWSM session, XDG portal (wlr+gtk), Valent, PAM service |
| `desktop/labwc-hm.nix` | labwc-specific HM: rc.xml keybinds, themerc-override (Stylix colors), kanshi display service |
| `icon-theme.nix` | `clanarchy.iconTheme` option: Stylix-recolored Papirus-Dark; imported by niri, labwc, and gnome desktop modules |
| `locale.nix` | `clanarchy.locale` option: language + keyboard layout/variant/options |
| `users/admin.nix` | admin user: SSH keys, password, impermanence, HM stub |
| `users/lgo.nix` | lgo power user: SSH config, browsers, devtools, Noctalia; `clanarchy.users.lgo.editor` option (govim \| helix, default govim) |
| `users/sabine.nix` | sabine user: impermanence, HM config |
| `wifi.nix` | NetworkManager profile generator (clan var) |
| `hardware/cpu.nix` | Intel/AMD microcode selection |
| `hardware/display.nix` | `clanarchy.display.scale` option: console font/mode scaling for pre-compositor contexts (boot, TTY) |
| `networking.nix` | ZeroTier + DNS options |
| `roles/laptop.nix` | Laptop role: fwupd (all laptops), thermald (Intel only), power-profiles-daemon, weekly Nix GC (14-day retention) |
| `apps/communication.nix` | `clanarchy.apps.communication`: messaging apps (Valent, etc.) |
| `apps/containers.nix` | `clanarchy.apps.containers`: Podman / container tooling |
| `apps/desktop-tools.nix` | `clanarchy.apps.desktopTools`: desktop utilities bundle |
| `apps/flatpak.nix` | `clanarchy.apps.flatpak`: Flatpak + Flathub remote |
| `apps/gnome-core.nix` | `clanarchy.apps.gnomeCoreApps`: core GNOME app set |
| `apps/graphics.nix` | `clanarchy.apps.graphics`: graphics/creative apps (GIMP, Inkscape, etc.) |
| `apps/media.nix` | `clanarchy.apps.media`: media playback apps |

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

**scdaemon + pcscd**: `~/.gnupg/scdaemon.conf` must contain `disable-ccid`. Without it, scdaemon defaults to trying the internal CCID/libusb driver first, which races with pcscd and produces "No such device" even when the YubiKey is present. `disable-ccid` forces scdaemon to route all card access through pcscd (socket-activated on demand). This is managed declaratively via `home.file.".gnupg/scdaemon.conf"` in `modules/users/lgo.nix`. If the card is suddenly missing: `gpgconf --kill gpg-agent && gpg --card-status`.

**YubiKey pinentry**: Use `pinentry-qt`, not `pinentry-gnome3`. `pinentry-gnome3` calls `gcr_system_password_finish` via D-Bus (`org.gnome.keyring.SystemPrompter`), which requires `gnome-keyring-daemon` — absent on Niri. Without it every PIN prompt fails silently and gpg-agent returns "agent refused operation" on all card-backed SSH signing. `pinentry-qt` draws its own Qt dialog on Wayland with no GNOME dependency. The wrapper in `yubikey.nix` injects `WAYLAND_DISPLAY` and `QT_QPA_PLATFORM=wayland` so Qt picks the right backend when called from the gpg-agent context.

**Niri overlay**: `clan.nix` overrides niri with `checkPhase = ":"` to bypass an EMFILE sandbox test failure in nixpkgs 25.11.

**pkgs-unstable**: `nixpkgs-unstable` intentionally does NOT follow clan-core's nixpkgs — it's needed for Noctalia/Quickshell. Injected as a module arg via `_module.args`.

**push function**: Reads gh token at runtime to construct HTTPS remote URL, enabling pushes from a machine where `~/.config/git` is a read-only impermanence bind mount.

**icon-theme.nix**: Declares `clanarchy.iconTheme.{name,package}` and installs the package via `environment.systemPackages`. GNOME wires the theme name via dconf in `gnome.nix`. Niri and labwc wire `gtk.iconTheme` in their respective `-hm.nix` modules via `osConfig`. Do **not** set `gtk.iconTheme` in `home-manager.sharedModules` — it conflicts with Stylix's GTK HM target and breaks the entire HM activation for affected users.

**labwc window decorations**: `labwc-hm.nix` generates `~/.config/labwc/themerc-override` from `config.lib.stylix.colors` at build time. This patches the active openbox theme's title bar, border, and button colors to follow the Stylix palette — active border uses `base0D` (accent), active title uses `base01`, inactive recedes to `base00`.

**lgo editor option** (`clanarchy.users.lgo.editor`): Selects between `"govim"` (default) and `"helix"`. govim is a flake input (`github:lutzgo/govim`) built on nvf; it's wired via `programs.nvf.settings` (nvf's HM module namespace) with `imports = [common.nix, variants/default.nix]`. Stylix theming uses `vim.theme.enable = false` + `pkgs.vimPlugins.base16-nvim` + `vim.luaConfigRC.stylixTheme` (DAG entry via `inputs.nvf.lib.nvim.dag`). The nvf HM option namespace must be declared at the NixOS level via `home-manager.sharedModules`; per-user imports cannot bootstrap their own option types. `inputs.nvf` is pinned as `nvf.follows = "govim/nvf"` in `flake.nix`. `EDITOR`/`VISUAL`, Zellij `Alt+e`, and Yazi `e` all key off the same `editorBin` variable.
