# Machines

Five machines. Each `clan.machines.<name>` block in `flake.nix` reads as a
per-machine feature list: module args, the shared imports from
`lib/mk-machine.nix`, then the machine's own files.

| Machine | Hardware | Channel | Root | Desktop | Notes |
|---|---|---|---|---|---|
| `miralda` | Framework 13 AMD | stable | ZFS + impermanence, encrypted | Niri + UWSM + regreet | lgo's daily driver. YubiKey PIV for age. Gruvbox Light Hard — the only light palette in the fleet. |
| `jens` | Framework 12 Intel, convertible | stable | ZFS + impermanence, encrypted | Niri + UWSM + regreet | Deliberately the same machine as miralda from the user's side. Differences are hardware (Intel, 1920×1200, `clanarchy.hardware.convertible.enable`) and the palette (Selenized Black). No local model — Intel iGPU, so ROCm does not apply. |
| `biene` | Lenovo laptop | stable | ZFS + impermanence, unencrypted | labwc + UWSM + regreet + Noctalia | Sabine's machine. Lid close → power off, by preference. |
| `birte` | Steam Deck OLED (Galileo) | **unstable** | **btrfs** + impermanence | Jovian Steam Gaming Mode; KDE Plasma 6 via SDDM | Unstable because Jovian only supports it; **btrfs follows from that** — `clanarchy.rootfs` is derived from `clanarchy.channel`, because out-of-tree OpenZFS gates the kernel and birte tracks a Valve kernel. The only machine in the fleet that hibernates, for the same reason. |
| `ernst` | AM5 / X870E homelab | stable | ZFS + impermanence; mirrored encrypted `zroot` + raidz1 encrypted `zdata` | headless, plus an HTPC session on the TV | NAS + VM host + GPU compute. Two machine-type roles: `server` and `htpc`. ~20 containerised services. |

---

## `machines/miralda/`

| File | Purpose |
|------|---------|
| `configuration.nix` | Hostname, timezone, ZFS/systemd-boot, SSH daemon, per-user overrides |
| `disko.nix` | Thin wrapper over `modules/disko/base.nix` — NVMe device path, encryption on |
| `home-modules/browsers.nix` | HM: the four-browser stack. **Shared despite the path** — `modules/users/lgo.nix` imports it, so jens gets it too. Its header carries the table of which extension mechanism each browser admits, and why each is the only one that works |
| `home-modules/console-desktop.nix` | HM: TTY / console-only fallback session for `lgo` |
| `yubikey_ed25519.pub`, `yubikey_rsa.pub`, `clanarchy_admin.pub` | Committed SSH pubkeys used across the clan |
| `facter.json` | nixos-facter hardware fingerprint |

Theme and wallpapers are shared with jens (`modules/themes/`,
`modules/wallpapers/nix-anarchy.nix`); the palette itself is one word in
`configuration.nix` (`clanarchy.theme`).

## `machines/jens/`

| File | Purpose |
|------|---------|
| `configuration.nix` | Hostname, timezone, Intel CPU/GPU, convertible + ZSA hardware, apps, syncthing user |
| `disko.nix` | `modules/disko/base.nix` — NVMe path, encryption on, no swap |
| `facter.json` | nixos-facter hardware fingerprint |

## `machines/biene/`

| File | Purpose |
|------|---------|
| `configuration.nix` | Hostname, timezone, ZFS/systemd-boot, SSH daemon, Syncthing user override |
| `disko.nix` | `modules/disko/base.nix` — unencrypted pool, 8G plain swap (memory pressure only) |
| `stylix.nix` | Catppuccin Mocha; imports `modules/stylix-base.nix` |
| `wallpapers.nix` | Nix-Anarchy SVG rendered at native 1366×768; seeds `~/Pictures/Wallpapers/` and pins Noctalia's `wallpapers.json` |
| `facter.json` | nixos-facter hardware fingerprint |

biene and birte keep their own `stylix.nix` because they generate their
wallpaper at a machine-native resolution (and birte has no regreet target), not
because of the palette.

## `machines/birte/`

| File | Purpose |
|------|---------|
| `configuration.nix` | Hostname, timezone, btrfs/systemd-boot, SSH daemon, `clanarchy.channel = "unstable"` (which is what makes it btrfs), Steam Deck power/hardware tweaks |
| `disko.nix` | `modules/disko/btrfs.nix` — btrfs, unencrypted, 16G plain swap for hybrid-sleep, `@games` subvol at `/games` |
| `jovian.nix` | Jovian-NixOS wiring: Steam Gaming Mode, gamescope-session, `deck` user |
| `deck.nix` | Deck user config + HM stylix; persist set (incl. `.var/app` for Flatpak) and the `/games` tmpfiles rules |
| `stylix.nix` | Catppuccin Mocha, SVG-recoloured wallpaper at 1280×800 |
| `romm-esde-bridge.nix` | Publishes RomM's ES-DE export into the layout ES-DE actually reads |

## `machines/ernst/`

| File | Purpose |
|------|---------|
| `configuration.nix` | Hostname, timezone, ZFS/systemd-boot, SSH daemon |
| `disko.nix` | Hand-written multi-disk: mirrored encrypted `zroot` (2× 960 GB SAS SSD) + raidz1 encrypted `zdata` (6× 15.36 TB). Does **not** use `modules/disko/base.nix` |
| `hardware-configuration.nix` | Bootloader + kernel modules for the AM5 / X870E board |
| `networking.nix` | VLAN-filtering `br0`, the trunk, the VLAN map, and the two attachment patterns six container files cite as "pattern A". Carries the assertions that check `allocations.nix` against the live configuration |
| `allocations.nix` | The MAC / address / veth / uid registry — **data, checked by those assertions**, not a comment table. `nextFree` is computed |
| `htpc.nix` | The `go` couch user (deliberately **not** in `wheel`) + its password generator, and the one set of HDMI/audio facts the HTPC role needs |
| `courses.nix` | The Courses Jellyfin library + `course-import`. A separate library because Jellyfin's metadata providers are a **per-library** setting, and a sibling of `tvshows/` so Sonarr's root scan does not list every course as unmapped |
| `courses/*.json` | One manifest per course. `slug` is **the download filename stem and nothing else** — it is not reliably the URL slug |
| `course-import.sh`, `rom-import.sh` | Bodies of `course-import` / `rom-import`. Not standalone: the Nix file prepends the uid/gid/path constants, so the tool cannot drift from the deployment |
| `microvms/wg-qbittorrent.nix` | The microvm tier's only occupant: qBittorrent + slskd behind a commercial WireGuard VPN with an nftables killswitch |
| `containers/*.nix` | One file per service — see below |
| `containers/pkgs/*.nix` | Hand-rolled derivations for things absent from nixpkgs |

### Service tiers on ernst

Chosen by trust and workload, and a service does not move down a tier for
convenience:

- **microvm** (own kernel) — internet-facing, killswitch-carrying. One occupant.
- **systemd-nspawn** (shared kernel, real NixOS view) — trusted, storage-heavy.
  The default: used wherever a first-class NixOS module exists.
- **podman** — escape hatch for upstreams that ship only an OCI image.

### `machines/ernst/containers/`

Each file's own header carries its full reasoning — tier, exposure, uid, and
what was rejected. One line each here:

| File | Tier | Service |
|---|---|---|
| `traefik.nix` | nspawn | Reverse proxy on its own L2 identity, so every consumer VLAN collapses to one permanent firewall rule. Owns the router set and the `withWan` guards |
| `crowdsec.nix` | — | Log-driven detection + nftables remediation **inside Traefik's netns** — the only place that sees the pre-DNAT source of a WAN request. Co-defines `containers.traefik` |
| `authelia.nix` | nspawn | Identity provider: forward-auth, plus OIDC for the apps that can use it |
| `ingress-policy.nix` | data | Not a module — a plain function imported by both `traefik.nix` and `authelia.nix`, classifying every hostname. `withWan` throws at eval if a router disagrees with it |
| `arr.nix` | nspawn | ~18 services in one namespace: sonarr, radarr, prowlarr, bazarr, lidarr, jellyseerr, audiobookshelf, komga, navidrome, recyclarr and the helper daemons |
| `homepage.nix` | — | The service index. Co-defines `containers.arr` |
| `jellyfin.nix` | nspawn | Media server, on its own veth since M2b |
| `tvheadend.nix` | nspawn | SAT>IP client against the FRITZ!Box's DVB-C tuners; publishes M3U + XMLTV |
| `immich.nix` | nspawn | Photo library. Owns `zdata/photos`; declares `photo-import` |
| `nextcloud.nix` | nspawn | File sync / CalDAV / CardDAV. Owns `zdata/nextcloud` |
| `home-assistant.nix` | nspawn | The automation hub. The only container with **two legs on `br0`** (VLAN 90 + VLAN 20, because mDNS and SSDP are link-local) and the first to pass USB devices through |
| `music-assistant.nix` | nspawn | Player controller over Navidrome's library, via the Subsonic API. Second container with a VLAN 20 leg (`iot1`) — the one speaker is mDNS-discovery-only |
| `miniflux.nix` | nspawn | Feed reader. Public behind forward-auth **and** OIDC, so no native RSS client can ever reach the name again |
| `karakeep.nix` | nspawn | Bookmarks, page archives, search; the Floccus backend for both laptops. Auto-tags against the model already resident on ernst |
| `paperless.nix` | nspawn | Household document archive. Owns `zdata/docs`. Two ingest doors (the phone app's API, and a writable Nextcloud folder that *is* the consumption directory) |
| `mail.nix` | nspawn | SMTP + IMAP for `@goclan.org`. **The only service that does not ride Traefik** — `:25` has no SNI — so it gets UDM-Pro DNATs, is not in `ingress-policy.nix`, and is the one container that does not pin Technitium |
| `tubesync.nix` | podman | YouTube archiving. The tier's first occupant, so it is where podman itself is enabled |
| `storyteller.nix` | podman | Ebook/audiobook alignment |
| `cwa.nix` | podman | Calibre-Web-Automated: OPDS, the Kobo endpoint, KOReader sync. `pkgs.calibre-web` is a *different* codebase without any of those |
| `romm.nix` | podman | ROM library manager; masters `zdata/roms`, which Syncthing replicates to birte. Two images in one netns, so MariaDB on loopback is structurally unreachable |

Containers are also declared from clan services: `monitoring` (in
`service-modules/monitoring.nix`), `openwebui` and `searxng` (in
`service-modules/local-ai.nix`).

### Allocation

New services claim a sequence number, a MAC, an address and possibly a uid from
the registry in `machines/ernst/allocations.nix`. Three things that bite:

- **Container names cap at 12 characters** — `vb-<name>` hits IFNAMSIZ and fails
  at container *start*, not at eval. Hence `mail`, `mass`, `hass`.
- **Check nixpkgs' `ids.nix` before taking a number from the 3000 block.**
  `paperless`=315, `hass`=286, `postgres`=71 are static upstream; pinning a
  3000-block number on top is an eval conflict, and NEXT FREE must *not* advance.
- **A veth name is a host-global allocation.** M19 and M27 both picked `ai0` and
  Open WebUI silently lost its leg for five days. There is now an assertion.
