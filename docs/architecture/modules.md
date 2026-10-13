# Modules and clan services

Where the shared code lives. Adding something new:
[adding a module](../guides/adding-a-module.md).

## Composition

- `flake.nix` — inputs, devShell, flake `checks`, and the `clan.machines.*`
  blocks. Each uses helpers from `lib/mk-machine.nix`.
- `lib/mk-machine.nix` — `mkModuleArgs`, `stylixKmsconFix`, and the two shared
  import lists: **`commonBase`** (every machine) and **`commonHeadful`**
  (`commonBase` + stylix + display + NM DNS routing + apps + immich-upload).
  `ernst` takes `commonBase`; the others take `commonHeadful`.
- `lib/overlays.nix` — the nixpkgs overlays, applied to **both** pkgs instances:
  the stable one in `clan.nix` and the unstable one in `lib/mk-machine.nix`. A
  machine on `clanarchy.channel = "unstable"` takes its whole `pkgs` from the
  latter, so an overlay listed in only one place silently does not apply there.
- `clan.nix` — clan-core metadata, the stable `pkgsForSystem`, and the
  `inventory.instances` that assign roles per machine.
- `vars/` — generated secrets and configs (clan vars).

## `modules/` — shared NixOS modules

### Base and filesystem

| File | Purpose |
|------|---------|
| `base.nix` | Universal defaults: EFI boot, Plymouth, flakes, openssh baseline, zsh |
| `channel.nix` | `clanarchy.channel` = `stable` \| `unstable`. Unstable swaps `nixpkgs.pkgs`, using `mkOverride 25` to win against clan-core's `mkForce` |
| `rootfs.nix` | `clanarchy.rootfs` = `zfs` \| `btrfs`, plus the persist paths both backends share. **Derived, not set**: `stable` → `zfs`, `unstable` → `btrfs`, because OpenZFS is out-of-tree and gates the kernel — which is the only reason a machine is on unstable in the first place. The option is `readOnly`, so a machine that tries to set it gets an error rather than an unstable kernel paired with an out-of-tree filesystem |
| `zfs-impermanence.nix` | ZFS backend: root **and** home roll back to `@blank` on boot (stage 1) |
| `btrfs-impermanence.nix` | btrfs backend: `@root` and `@home` roll back to `@root-blank` / `@home-blank`, seeded on first boot |
| `disko/base.nix` | Single-disk ZFS helper: 1G ESP + optional swap + `zroot`. Parameters: `device`, `enableSwap`, `swapSize`, `encryptSwap`, `enableEncryption` |
| `disko/btrfs.nix` | Single-disk btrfs sibling: 1G ESP + optional swap + `@root`/`@nix`/`@home`/`@persist`/`@games` |
| `vm-variant.nix` | QEMU-friendly overrides for `nixos-rebuild build-vm` |

Both impermanence backends are imported unconditionally and each guards its own
body on `clanarchy.rootfs`, the same pattern as `channel.nix`.

### Hardware and locale

| File | Purpose |
|------|---------|
| `locale.nix` | `clanarchy.locale`: language + keyboard layout/variant/options |
| `hardware/cpu.nix` | Intel/AMD microcode selection |
| `hardware/gpu.nix` | GPU driver selection (AMD/Intel/NVIDIA) |
| `hardware/display.nix` | `clanarchy.display.scale`: console font/mode scaling for boot and TTY |
| `hardware/printing.nix` | CUPS + hplip + SANE |
| `hardware/yubikey.nix` | pcscd + GnuPG agent (pinentry-qt wrapper) + polkit rule |
| `hardware/zsa.nix` | ZSA keyboards (Voyager et al). Inert until enabled |
| `hardware/convertible.nix` | `clanarchy.hardware.convertible`: iio-sensor-proxy, a `niri msg`-driven auto-rotate service, wvkbd. Fleet-wide but inert on clamshells, because the shared `niri-hm.nix` reads the option |
| `icon-theme.nix` | `clanarchy.iconTheme`: Stylix-recoloured Papirus; source variant follows `stylix.polarity` |

### Networking

| File | Purpose |
|------|---------|
| `networking/mdns.nix` | Avahi / mDNS — `<hostname>.local` across LAN + ZeroTier |
| `networking/resolved.nix` | systemd-resolved defaults: public FallbackDNS, no global DNS/search (per-link only, so roaming does not break) |
| `networking/skynet-dns-nm.nix` | NM machines: extends the clan-created "home" wifi profile so Technitium is the sole resolver whenever the home LAN is active |
| `networking/initrd-ssh.nix` | Opt-in stage-1 SSH for remote pool/passphrase unlock. Requires `boot.initrd.systemd.enable` |
| `networking/clan-known-hosts.nix` | Pins every clan machine's host key on every address it answers on. Fleet-wide, because any machine may be the one deploying and the address clan picks depends on which path answers first |
| `nix-remote-builder.nix` | Distributed Nix builds; both roles off by default |

### Desktop

| File | Purpose |
|------|---------|
| `stylix-base.nix` | Shared stylix baseline: fonts (Monaspace), cursor, `targets.plymouth`, polarity |
| `themes/palettes.nix` | The theme registry — one data entry per known-good theme |
| `themes/default.nix` | Declares `clanarchy.theme` as an enum over those keys and applies it |
| `wallpapers/nix-anarchy.nix` | Per-workspace nix-anarchy SVG wallpapers, recoloured to the active palette |
| `desktop/desktop-common.nix` | Shared NixOS bits for Noctalia-based compositors: regreet, pipewire, fonts, NetworkManager, Mullvad |
| `desktop/noctalia-hm.nix` | Shared HM: Noctalia settings, starship, swayidle, packages, activation hooks |
| `desktop/foot-hm.nix` | Shared HM: foot terminal (Stylix-themed) |
| `desktop/niri.nix` | Niri: UWSM session, portal, fprintd, V4L2 loopback. Also declares the per-machine appearance options `niri-hm.nix` consumes |
| `desktop/niri-hm.nix` | Niri HM: the full KDL config |
| `desktop/labwc.nix` / `labwc-hm.nix` | labwc session, portal, Valent, PAM; HM rc.xml + themerc-override generated from the Stylix palette |
| `desktop/kde.nix` | KDE Plasma 6 + SDDM (birte's "Switch to Desktop") |
| `desktop/bigscreen.nix` | Plasma Bigscreen in an nspawn container (ernst). Parked |

### Roles

| File | Purpose |
|------|---------|
| `roles/laptop.nix` | fwupd, thermald (Intel), power-profiles-daemon, weekly GC, lid-switch handling. `hybridSleep` defaults on only for a btrfs root and asserts its three preconditions, so hibernation cannot be half-configured |
| `roles/server.nix` | Headless baseline: no GUI packages, `execWheelOnly`, store optimisation |
| `roles/htpc.nix` | A gamescope Steam session and KDE Plasma behind one wrapper session, switched at runtime. Also arbitrates the TV's claim on a GPU shared with ROCm compute, and demotes a crash-looping session instead of letting the display manager relogin it forever |
| `roles/vm.nix`, `roles/rpi.nix` | VM guest tools; Raspberry Pi firmware (unused) |

### Users and apps

| File | Purpose |
|------|---------|
| `users/admin.nix` | admin user: SSH keys, password, impermanence, HM stub |
| `users/lgo.nix` | lgo: SSH config, browsers, devtools, Noctalia; `clanarchy.users.lgo.editor` = `govim` \| `helix` |
| `users/sabine.nix` + `users/sabine-noctalia/` | sabine: impermanence, HM, pinned Noctalia plugin assets |
| `users/sgo.nix` | sgo alt user (miralda only) |
| `mail-accounts.nix` | `clanarchy.mail.accounts`: the **shared** mailbox password generator. Not fleet-wide — imported by exactly the three machines that need it, because a clan var reaches only machines whose configuration declares its generator, and two generators would prompt separately for the same password |
| `apps/default.nix` + `apps/*.nix` | `clanarchy.apps.*` bundles: communication, containers, desktop-tools, emulation, flatpak, gnome-core, graphics, media |

### Other

| File | Purpose |
|------|---------|
| `virtualisation.nix` | libvirt / qemu / podman shared setup |
| `caldav-sync.nix` | CalDAV sync helpers |
| `immich-upload.nix` | A watched darktable export folder pushed to Immich. Inert until enabled |
| `gaming-shortcuts.nix` | `clanarchy.gaming.shortcuts`: declarative non-Steam entries merged into Steam's binary `shortcuts.vdf`, matching on name and leaving hand-added entries alone |
| `observability/zfs-ntfy.nix` | ZFS event notifications to ntfy |

## `service-modules/` — clan services

Registered in `clan.nix` under `modules."@clanarchy/<name>"` and referenced by
`module.name` in `inventory.instances`, which assigns roles and settings per
machine. Each has a `.md` readme beside it.

| Module | Purpose | Used by |
|---|---|---|
| `@clanarchy/machine-type` | Hardware/role archetype: `laptop` / `server` / `htpc` / `vm` / `rpi`. Roles compose — a machine may hold more than one | laptops (laptop), ernst (server + htpc) |
| `@clanarchy/desktop` | Desktop dispatch: `niri` / `labwc` / `kde` | miralda + jens, biene, birte |
| `@clanarchy/users` | User dispatch: `lgo` / `sabine` | miralda + jens, biene |
| `@clanarchy/yubikey` | Imports `modules/hardware/yubikey.nix` | miralda, jens |
| `@clanarchy/printing` | Imports `modules/hardware/printing.nix` | miralda, jens |
| `@clanarchy/software` | Per-user browser + mail app dispatch. The `librewolf` role installs extensions as an `ExtensionSettings` policy merged into the wrapped package — see `software.md` for why neither `/etc` policies nor `nixExtensions` work | all headful machines |
| `@clanarchy/local-ai` | The self-hosted LLM stack and OpenCode. Roles: `inference` (llama-swap + llama-server on ROCm), `models` (one attrset feeding both the fetcher and the preset INI), `speech`, `agent` (mneme, the household agent), `voice`, `imagegen`, `search` (SearXNG), `webui` (Open WebUI), `ollama` (miralda only), `opencode`. In-container consumers reach loopback-bound llama-swap through per-consumer point-to-point ULA legs. Full detail: `service-modules/local-ai.md` | ernst (most), miralda (ollama + opencode), jens (opencode) |
| `@clanarchy/monitoring` | `client`: node_exporter everywhere. `server`: Prometheus + Alertmanager + Grafana in one container. **Scrape targets are derived from `roles.client` membership**, so adding a machine to the role is the only step needed. Also four textfile collectors for properties no exporter reports | client: all five; server: ernst |

Plus stock clan services used verbatim: `sshd`, `zerotier`, `syncthing`, `wifi`.

## Clan vars

Secrets come from `clan.core.vars.generators.<name>`: `files.<name>` (with
`secret` and `neededFor`), optional `prompts.<name>`, and a `script` with
`runtimeInputs`. Outputs land in `vars/per-machine/<machine>/` or
`vars/shared/`. See [adding a module](../guides/adding-a-module.md) for the
three ways this has gone wrong.
