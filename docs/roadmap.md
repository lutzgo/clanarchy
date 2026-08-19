# Roadmap

Single source of truth for **ernst / fleet buildout sequencing**.

Two jobs:

1. Record what is already built, compactly, with PR references — so the repo's
   present shape is explainable without archaeology.
2. Carry the **session prompt** for every open milestone, ready to paste into a
   fresh Claude Code session. Each prompt is self-contained: it names the branch,
   the files, the decisions already made, and the constraints.

!!! note "How to start a milestone"

    Copy the fenced prompt from that milestone's section verbatim into a new
    session. Do not summarise it — the decisions embedded in it are the point.
    When the milestone lands, update the status table and the
    [interim-rule ledger](#interim-rule-ledger) in the same PR.

---

## Current state

Verified against the repo on 2026-08-19 (`main` @ `8bdd162`).

| Milestone / work | Status | Refs | Note |
|---|---|---|---|
| zdata datasets + server-role hardening | **done** | [#18](https://github.com/lutzgo/clanarchy/pull/18) | `/srv/media`, `/srv/state`, `/srv/games` declared in `machines/ernst/disko.nix`; `execWheelOnly`, `nix.settings.allowed-users = ["@wheel"]`, `environment.defaultPackages = mkForce []` in `modules/roles/server.nix` |
| `/srv/media` as one hardlink domain | **done** | [#20](https://github.com/lutzgo/clanarchy/pull/20) | The `media/movies` + `media/tvshows` sub-datasets were **collapsed into plain subdirectories** — hardlinks cannot cross a ZFS dataset boundary, and the *arr import path depends on them |
| Datasets for the rescued Arch data | **done** | [#66](https://github.com/lutzgo/clanarchy/pull/66) | `/srv/unsorted` (~485 GB, 26-dir tree awaiting triage) and `/srv/gardens` (SilverBullet KBs, per user). Both `com.sun:auto-snapshot=true`, unlike `/srv/media` |
| `modules/gaming-common.nix` extraction | **done** | [#19](https://github.com/lutzgo/clanarchy/pull/19) | `clanarchy.gaming.{enable,user,persistenceDirectories}`; consumed by birte's `deck.nix` and the HTPC role |
| Jellyfin in an nspawn container | **done** | [#20](https://github.com/lutzgo/clanarchy/pull/20), [#45](https://github.com/lutzgo/clanarchy/pull/45), [#46](https://github.com/lutzgo/clanarchy/pull/46) | Host networking (`privateNetwork = false`), iGPU pinned by PCI path through a colon-free udev alias |
| Jellyfin VAAPI transcoding | **done** | [#49](https://github.com/lutzgo/clanarchy/pull/49), [#50](https://github.com/lutzgo/clanarchy/pull/50), [#51](https://github.com/lutzgo/clanarchy/pull/51) | Fixed by binding **`/dev/dri` as a directory** (mesa re-derives canonical node names from the fd) *and* by `forceEncodingConfig = true` — without #51 the declared settings were inert. Incident: `docs/incidents/ernst-jellyfin-vaapi-drm-display-failure-2026-08-18.md` |
| Container journals persisted | **done** | [#54](https://github.com/lutzgo/clanarchy/pull/54) | `/var/lib/nixos-containers` persisted; the `\|\| true` that hid a missing `@blank` removed, `clanarchy-impermanence-check.service` now fails loudly |
| HTPC role (gamescope + Plasma switching) | **done** | [#39](https://github.com/lutzgo/clanarchy/pull/39), [#53](https://github.com/lutzgo/clanarchy/pull/53), [#57](https://github.com/lutzgo/clanarchy/pull/57) | Stock-nixpkgs `programs.steam.gamescopeSession` behind one wrapper session; `clanarchy-session-select` + `steamos-session-select` shim; couch user `go` (not in `wheel`), autologin on |
| Wireless Xbox controller support | **done** | [#65](https://github.com/lutzgo/clanarchy/pull/65) | Bluetooth + xpadneo, `/var/lib/bluetooth` persisted |
| TV session survives a dark TV | **done** | [#68](https://github.com/lutzgo/clanarchy/pull/68) | The couch session waits for a connected output on `display.gpuPciAddress` before starting a compositor (gamescope segfaults on a card with none), and SDDM gets `Relogin=true` so a session that ends is retried instead of parking on the greeter. Same PR set `bigscreen.enable = false` on ernst, applying #64's decision |
| Headless opt-in gaming | **superseded** | — | Shipped instead as the HTPC role: a real display-manager session on the TV, not a headless opt-in |
| Plasma Bigscreen in a container | **parked** | [#48](https://github.com/lutzgo/clanarchy/pull/48), [#60](https://github.com/lutzgo/clanarchy/pull/60), [#62](https://github.com/lutzgo/clanarchy/pull/62), [#63](https://github.com/lutzgo/clanarchy/pull/63), **revert [#64](https://github.com/lutzgo/clanarchy/pull/64)** | Structural, not a bug: Plasma 6.7 needs logind (user units), KWin needs logind absent or an active *graphical* seat, and a container cannot supply a seat. Machinery kept — either escape route reuses it. Disabled on ernst in [#68](https://github.com/lutzgo/clanarchy/pull/68); the container is no longer built |
| Ollama on ernst | **done** | [#39](https://github.com/lutzgo/clanarchy/pull/39), [#47](https://github.com/lutzgo/clanarchy/pull/47), [#52](https://github.com/lutzgo/clanarchy/pull/52), [#55](https://github.com/lutzgo/clanarchy/pull/55), [#61](https://github.com/lutzgo/clanarchy/pull/61) | Static `ollama` user (DynamicUser + impermanence is a trap), stale `/var/lib/ollama` symlink cleared, `models/` dir created, `qwen3-coder:30b` on the 7900 XTX. Loader backoff raised to `RestartSec=30s` |
| ZFS → ntfy alerting | **done** | [#33](https://github.com/lutzgo/clanarchy/pull/33), [#35](https://github.com/lutzgo/clanarchy/pull/35), [#40](https://github.com/lutzgo/clanarchy/pull/40) | `modules/observability/zfs-ntfy.nix`, imported fleet-wide by `commonBase`, gated on `clanarchy.zfs.ntfy.enable`; topic URL is a clan var. **M6 must reuse this, not duplicate it** |
| `fwupd-refresh` failure tolerance | **done** | — | `modules/roles/laptop.nix` — laptop role only; ernst does not run it |
| Deploy interface = clan CLI | **done** | [#59](https://github.com/lutzgo/clanarchy/pull/59) | `deploy`, `deploy-<machine>`, `test-pr`, `test-vm` removed. Every runbook and milestone prompt below uses `clan machines update` |
| CI eval check on PRs | **done** | — | `.github/workflows/check.yml` evaluates all four toplevel `drvPath`s |
| ernst `@blank` snapshots | **open (operator)** | — | ernst has never been genuinely impermanent — root accumulates. `docs/runbooks/ernst-enable-impermanence.md` is written and unexecuted; step 4 is a one-way door. Not a Claude milestone |
| M1 — Kvantum linkGeneration drift | **closed — did not reproduce** | — | Four consecutive activations in the retained journal all passed `linkGeneration`. The on-disk shape that looked like drift is Stylix's `recursive = true` working as designed. See [M1](#m1-kvantum-linkgeneration-drift-closed) |
| M2 — ernst VLAN bridge | **done — deployed 2026-08-20** | — | `br0` VLAN-filtering bridge, `enp13s0` as tagged trunk; VLAN 80 (Services) created for M2b/M5. The cutover is lgo's — [runbook](runbooks/ernst-vlan-bridge-cutover.md). See [M2](#m2-ernst-vlan-bridge-built-cutover-pending) |
| M2b — Jellyfin on its own veth | **open** | — | [M2b](#m2b-featernst-jellyfin-tap) |
| M3 — VPN microvm + qBittorrent | **open** | — | [M3](#m3-featernst-vpn-microvm) |
| M4 — arr stack | **open** | — | [M4](#m4-featernst-arr-stack) |
| M5 — Traefik | **open** | — | [M5](#m5-featernst-traefik) |
| M6 — monitoring | **open** | — | [M6](#m6-featmonitoring) |
| M7 — Authelia | **open** | — | [M7](#m7-featernst-authelia) |

---

## Architecture invariants

The milestones must respect these. Breaking one is a decision to argue for in a
PR body, not a detail to slide past.

**1 — Three tiers of isolation, chosen by trust and by workload.**

| Tier | For | On ernst |
|---|---|---|
| microvm (own kernel) | internet-facing, killswitch-carrying | the VPN/qBittorrent guest (M3) |
| systemd-nspawn (shared kernel, real NixOS view) | trusted, storage-heavy | Jellyfin, arr, Traefik, Authelia, monitoring |
| podman | escape hatch — upstream ships only an image | nothing yet |

A service does not move down a tier for convenience. It moves up when it starts
talking to the internet on its own behalf.

**2 — `/srv/media` is one hardlink domain.** One dataset, plain subdirectories
inside it. Hardlinks cannot cross a ZFS dataset boundary, so a sub-dataset under
`/srv/media` silently converts every *arr import into a copy. This is why the
`media/movies` and `media/tvshows` sub-datasets were collapsed in #20 — do not
re-introduce them.

**3 — Consumer VLANs get exactly ONE permanent firewall rule: → `traefik:443`.**
Anything else pointing a consumer zone at a service port is *interim* and must
appear in the [ledger](#interim-rule-ledger) with a removal trigger. Management
VLAN access is not covered by this rule and is expected to stay direct.

**4 — Names resolve to Traefik; bypasses are deliberate and listed.** Current
and planned bypasses: the qBittorrent WebUI (mgmt VLAN only, never a Traefik
route — see M3), and Jellyfin's own authentication, which stays native forever
because TV and mobile clients cannot survive forward-auth.

**5 — GPU allocation on ernst is fixed, and passthrough is rejected.**

- `0000:03:00.0` — RX 7900 XTX (Navi 31, `card1`): drives the TV, and is Ollama's
  ROCm card. Shared deliberately — compute goes through the render node, KMS
  through the card node, so a session and ROCm coexist and merely compete for
  VRAM. **Never VFIO-bind it**: exclusive binding is the mutually-exclusive
  outcome `clan.nix` explicitly rejects, and it is why the Bigscreen-in-a-VM
  escape route was not taken.
- `0000:7b:00.0` — Granite Ridge iGPU (`card0`): Jellyfin's VAAPI device, and the
  head the GL.iNet Comet KVM watches. Card numbering here is *inverted*, which is
  why both are pinned by PCI address and never by `renderD*` number.
- The one real mutual exclusion is `display-manager.service` vs the Bigscreen
  container — both want KMS on the same card. That is what the flag file and
  `ConditionPathExists` in `modules/roles/htpc.nix` enforce.

**6 — ernst stays on the stable channel.** `clanarchy.channel = "unstable"` is
birte-only (Jovian). The HTPC gamescope session is stock nixpkgs for exactly this
reason, and `nixpkgs.config` cannot be set on an unstable machine anyway — the
two are mutually exclusive by construction.

**7 — State lives on `zdata`, under `/srv/state/<service>`.** Not on `zroot`,
which rolls back. Container media is read-only where the service does not write.
Anything a service needs across a reboot is either a `/persist` entry or a
`/srv/state` bind — never an accident.

**8 — Secrets come from clan vars generators.** No plaintext in the repo, no
placeholder secrets committed, `neededFor` set where activation depends on it.

**9 — The deploy interface is the clan CLI.** `clan machines update <machine>`.
The `deploy-*` shell helpers were removed in #59 because they bypassed clan's
inventory evaluation and could not apply vars. Do not reintroduce them in any
form, including runbook aliases.

---

## Interim-rule ledger

Temporary firewall / DNS / routing shims. Every row needs a removal trigger.
Rows are retired only by the PR that actually removes the rule.

| # | Shim | Where it lives | Why it exists | Removal trigger | Status |
|---|---|---|---|---|---|
| L1 | `Family` VLAN → `ernst:8096/tcp` | UDM-Pro ZBF (off-repo) | Jellyfin is reached directly; there is no reverse proxy yet | **M5** — repoint clients at `jellyfin.<domain>` and replace with the permanent `Family → traefik:443` rule | open |
| L2 | `IoT (20)` → `10.0.50.10:8096/tcp` | UDM-Pro ZBF policy `Allow Jellyfin from IoT to Servers` | TVs / streaming devices live on the IoT VLAN | **M5** — same as L1 | open — **created 2026-08-19**; earlier revisions of this table asserted it already existed, and it did not (see note below) |
| L2a | IoT name resolution for L2 | — | IoT clients could not resolve `jellyfin.skynet.lan` | **M5** — repoint at Traefik | **not needed** — the TV is pointed at `http://10.0.50.10:8096` by IP, so no IoT→DNS path is required. Revisit only if a name is used |
| L3 | `networking.firewall.allowedTCPPorts = [ 8096 ]` on the host | `machines/ernst/containers/jellyfin.nix` | Jellyfin shares the host network namespace (`privateNetwork = false`), so its port is a host port | **M2b** — the veth on VLAN 80 gives the container its own L2 identity; the host port opening goes away and the ACL moves to the UDM-Pro | open |
| L4 | arr WebUI ports `9696` / `8989` / `7878`, mgmt-VLAN scoped | M4 (host firewall, v1) | arr v1 runs on host networking like Jellyfin did | **M5** for the routes, plus a veth migration mirroring M2b | not yet created |
| L5 | Traefik `ipAllowList` on the arr + Grafana routes (mgmt + wg-travel) | M5 (`traefik` container) | There is no identity provider yet | **M7** — replaced by the Authelia forward-auth middleware | not yet created |

---

## M1 — Kvantum linkGeneration drift (closed)

**Outcome, 2026-08-19: did not reproduce, and the shape that prompted it is
correct behaviour.** Closed without a code change, per the milestone's own
instruction to close on evidence rather than add a hook against a problem that no
longer occurs.

**Evidence 1 — the journal is clean.** `/var/log/journal` is persistent, so the
record spans boots. Every Home Manager activation it retains reached
`linkGeneration`, logged `Creating home file links in /home/lgo`, and ended in
`Finished Home Manager environment for lgo`:

| Activation | linkGeneration | Result |
|---|---|---|
| Jul 21 15:43 | clean | finished |
| Aug 01 18:45 | clean | finished |
| Aug 13 10:57 | clean | finished |
| Aug 19 12:37 | clean | finished |

No `Existing file … would be clobbered`, no non-symlink-in-the-way error, no
failed activation anywhere in the window. `systemctl show home-manager-lgo.service`
confirms the latest run: `Result=success`, `ExecMainStatus=0`, `NRestarts=0`. The
two unrelated failures visible in the same journal — `xdg-desktop-portal-gtk`
(Aug 13) and a `swayidle` restart (Aug 19) — have nothing to do with file linking.

**Evidence 2 — the on-disk shape is by design, not drift.** Home Manager owns
**two overlapping entries** under that path, which is what earlier sessions
misread. From
`nix eval '.#nixosConfigurations.miralda.config.home-manager.users.lgo.home.file'`:

| Entry | `recursive` | source |
|---|---|---|
| `~/.config/Kvantum` | **`true`** | `…-kvantum-themes` |
| `~/.config/Kvantum/kvantum.kvconfig` | `false` | `…-kvantum-config` |

`recursive = true` tells HM to walk the source tree and link each file
*individually* instead of symlinking the directory. Real directories containing
per-file store symlinks are therefore the **intended** result — and they are also
what makes the second entry possible at all, since a file cannot be placed inside
a symlink to a read-only store path. Stylix sets it that way deliberately so its
theme directory and its config file can coexist.

So `~/.config/Kvantum/` and `Base16Kvantum/` being real directories full of
symlinks is not HM's "fallback because something was in the way". It is the only
shape this configuration can produce.

**What would reopen this.** An activation that actually fails at `linkGeneration`
on a Kvantum path, with the journal line pasted. Absent that there is nothing to
fix. Note the retained journal is a finite window: a failure older than it would
not appear above — but a fix cannot be designed against a failure with no
surviving evidence either.

---

## M2 — ernst VLAN bridge (built; cutover pending)

**Code landed. The cutover itself is operator work** — see
[the cutover runbook](runbooks/ernst-vlan-bridge-cutover.md), which is the
deliverable that matters here. `machines/ernst/networking.nix` now declares a
VLAN-filtering bridge `br0` with `enp13s0` as a tagged trunk port; the host keeps
`10.0.50.10/24` untagged on VLAN 50.

**VLAN map** (source of truth: UDM-Pro `skynet-udmpro`). The roadmap's earlier
names map as: "Family" = LAN (1), "skynet-iot" = IoT (20).

| ID | Name | Subnet | On ernst's trunk |
|---|---|---|---|
| 1 | LAN | 10.0.10.0/24 | tagged |
| 5 | DNS-Container | 10.0.5.0/24 | tagged (Technitium 10.0.5.3) |
| 20 | IoT | 10.0.20.0/24 | tagged |
| 30 | HA | 10.0.30.0/24 | not carried |
| 40 | Guest | 10.0.40.0/24 | not carried |
| **50** | **Servers** | **10.0.50.0/24** | **untagged / PVID — ernst itself** |
| 60 | Matter | 10.0.60.0/24 | not carried |
| 70 | Travel (wg) | — | not carried |
| **80** | **Services** | **10.0.80.0/24** | tagged — **new**, created for M2b/M5 |

VLAN 80 did not exist before this milestone. M2b and M5 both assumed a services
zone; there wasn't one, so services would have shared the host's firewall zone
and invariant #3 would have meant nothing. It is tagged on the trunk now, before
anything uses it, so M2b/M3/M5 never need a switch-port change.

Services is **80, not 70** — 70 is already the travel/WireGuard VLAN, the one
M5's interim `ipAllowList` and M7's wg-travel lockout warning refer to.
30/40/60/70 are deliberately off the trunk: a VLAN that is not carried cannot be
reached by a typo in a future container unit, and travel reaches services
through Traefik rather than by riding ernst's trunk.

### Three findings that contradicted this milestone's own prompt

1. **`99-ethernet-default-dhcp` on ernst was a *matchless* wildcard.** Verified
   `matchConfig` → `{}`. nixpkgs gates the real unit on `networking.useDHCP`,
   which is `false` on ernst (NetworkManager, via the htpc role → `kde.nix`,
   sets it false) — but clan-core writes `networkConfig.MulticastDNS` onto that
   attribute unconditionally, so the unit survived with an empty `[Match]` that
   matched **every** link. Harmless while every interface had its own `50-*`
   unit; not harmless on a bridge host that grows taps and `vb-*` veths a
   wildcard `.network` can claim and detach from `br0`. The upstream match is
   restored in `machines/ernst/networking.nix`.
2. **ernst runs NetworkManager as well as networkd** —
   `networking.networkmanager.enable` → `true`, from `modules/roles/htpc.nix`
   importing `modules/desktop/kde.nix`. NM auto-creating a DHCP profile on `br0`
   mid-cutover is a lockout vector, so the hands-off is now explicit rather than
   left to udev's `ID_NET_MANAGED_BY` tagging. Container veths are *not* listed:
   nixpkgs already ships a `v[eb]-*` → `NM_UNMANAGED` udev rule when NM is
   enabled, and duplicating it would be a second source of truth.
3. **The verification command in the old prompt did not work.**
   `nix eval --json '…systemd.network.networks' | jq 'keys'` forces the whole
   attrset and trips the removed `dhcpConfig` alias assertion. Use
   `--apply builtins.attrNames`. Any future milestone listing networkd units
   should copy that form.

### Two attachment patterns, not one

The old prompt said "MAC-pinned tap" for both nspawn containers and microvm
guests. That is only correct for microvms: a tap is a single netdev, and handing
it to an nspawn container moves it out of the host netns and off the bridge.
nspawn's primitive is a veth pair, whose host side is named **`vb-<name>`** (not
`ve-`) when `--network-bridge=` is used. `machines/ernst/networking.nix` carries
both worked examples, commented.

`containers.<n>.macvlans` — sketched in the header of
`machines/ernst/containers/jellyfin.nix` — is **wrong for this architecture** and
M2b must not use it. A macvlan is not a bridge port: on `br0` it rides br0's own
self VLAN (50, the host VLAN), and on `enp13s0` it rides the trunk's native VLAN,
also 50. It cannot be placed on VLAN 80, which is the whole point. Correcting
that file header belongs to M2b, which owns the file.

### Two UDM-Pro findings from the cutover prep

**A ZBF policy with `Connection State: All` silently never matches.** The new
`Allow Jellyfin from IoT to Servers` rule sat at ID `10000` — first in evaluation
order, ahead of `Block IoT to Trusted` — and still logged **zero hits** while the
TV failed to connect. Every field matched the working `Allow Jellyfin from LAN to
Servers` rule except Connection State: the working one used `Custom → New`, the
broken one `All`. Setting it to `Custom → New` fixed it. Note the policy list is
sorted **alphabetically by name**, not by evaluation order — read the ID column
instead, and treat a zero hit count as a *matching* problem rather than an
ordering one.

**VLAN 80 has no gateway, and it is not the trunk's fault.** Tagged frames reach
ernst on VLAN 80, but `10.0.80.1` never answers ARP and no DHCP server responds.
The network is configured correctly (Router `skynet-udmpro`, zone `services`,
`10.0.80.1/24`, DHCP Server on, DNS `10.0.5.3`, Isolate off) and it is *not* a
"VLAN Only" network. **Force Provision is not offered for the UDM-Pro.** This is
an open blocker for **M2b** — see the warning box in the cutover runbook for what
has been ruled out and what to try next.

### Carried forward

- **Pin `br0`'s MAC before M2b.** Not done here: with one port the kernel gives
  `br0` the burned-in MAC of `enp13s0`, so the cutover does not move ernst's L2
  identity — which is what you want on the one deploy that can lock you out. A
  Linux bridge adopts the numerically *lowest* port MAC, so the second port can
  silently move it. §1.4 of the runbook captures the value.
- **Avahi reflection.** `modules/networking/mdns.nix` runs with `reflector = true`
  and no interface pinning. Not a regression here — bridge ports carry no host
  address, so Avahi skips them and `br0` simply replaces `enp13s0` — but it bites
  the first time ernst holds an address on a second VLAN.
- **`ernst-initrd` is DNS-only.** The alias uses `HostName ernst.skynet.lan`,
  so the recovery channel depends on the thing a bad cutover can break. The
  IP-literal fallback is now documented in
  [the remote-unlock guide](guides/remote-unlock.md); pinning the `HostName` is
  a separate `fix/` branch.

---

## M2b — `feat/ernst-jellyfin-tap`

**Goal.** Move the Jellyfin container off the host network namespace onto its own
MAC-pinned veth on `br0` (VLAN 80), giving it a distinct L2 identity the UDM-Pro can
firewall directly. The migration path is already written into the file header of
`machines/ernst/containers/jellyfin.nix`; this milestone executes it and retires
ledger row **L3**.

**Depends on.** M2, proven stable for at least a few days.
**Risk.** Medium — Jellyfin is the one service the household notices immediately.

````text
Read CLAUDE.md fully before doing anything.

Work in the clanarchy repo on miralda. Branch: feat/ernst-jellyfin-tap.
Prerequisite: M2 (feat/ernst-vlan-bridge) is merged, deployed, and has been
stable on ernst for several days.

GOAL. Flip machines/ernst/containers/jellyfin.nix from host networking to a
private network namespace with a MAC-pinned veth on br0, on the Services
VLAN (80).

READ FIRST, and note it is WRONG in two ways: that file's header
("Networking — v1: HOST namespace") sketches the migration as
`containers.jellyfin.macvlans = [ "br-services" ]`. A macvlan is not a
bridge port — on br0 it rides br0's own self VLAN (50, the HOST VLAN) and
on enp13s0 it rides the trunk's native VLAN, also 50 — so it cannot be
placed on VLAN 80 at all. And a *tap* is a microvm primitive, not an
nspawn one. Correct that header in this PR; M2b owns the file.

Scope:
  - containers.jellyfin = { privateNetwork = true; hostBridge = "br0";
    localMacAddress = "…"; }, plus a networkd unit matching the HOST side
    of the veth. That side is named vb-jellyfin — the "vb-" prefix, not
    "ve-", because nspawn uses --network-bridge=. The unit must set
    KeepMaster = true (nspawn owns the enslavement; Bridge= would make
    networkd fight it) and carry the [BridgeVLAN] for VLAN 80. Copy
    worked example B from machines/ernst/networking.nix verbatim.
  - VERIFY with `bridge vlan show` that the VLAN actually landed: networkd
    applies [BridgeVLAN] when it observes the link's master, and nspawn
    sets that master out of band, so the two can race. With
    DefaultPVID = "none" on br0 a missed application is fail-closed (no
    connectivity) rather than fail-open onto VLAN 50 — check for it
    explicitly rather than trusting silence.
  - Give the container its own address. Prefer a DHCP reservation on the
    UDM-Pro over a static address in the container config, so the network's
    source of truth stays in one place — but say which you chose and why.
  - DELETE the host-side firewall opening
    `networking.firewall.allowedTCPPorts = [ 8096 ]`. That is ledger row L3
    in docs/roadmap.md, and it exists only because the container shared the
    host namespace. The ACL moves onto the UDM-Pro.
  - Everything else stays: the iGPU udev alias and the /dev/dri directory
    bind (both load-bearing — see the header and
    docs/incidents/ernst-jellyfin-vaapi-drm-display-failure-2026-08-18.md),
    the /srv/media library binds and their legacy /media/Server001/* paths,
    the /srv/state/jellyfin state bind, the tmpfs transcode cache, the fixed
    uid/gid 964 and media gid 3000.
  - networking.useHostResolvConf is currently mkForce true inside the
    container BECAUSE it shares the host namespace. With a private network
    that has to become real DNS config pointing at Technitium (10.0.5.3)
    with the skynet.lan search domain. Do not leave it dangling.

MANUAL STEPS — list them explicitly in the PR body, they are lgo's:
  - DHCP reservation for the pinned MAC on the Services VLAN (80).
  - Repoint the Technitium `jellyfin` record at the container's new address
    (it moves again to Traefik in M5 — note that).
  - Retarget the interim ZBF rules L1 (Family -> :8096) and L2 (skynet-iot ->
    :8096) from ernst's host address to the container address. They stay
    interim; only their target changes.
  - Update the interim-rule ledger in docs/roadmap.md: L3 retired by this PR,
    L1/L2 retargeted with their trigger unchanged (M5).

TEST PLAN: container starts with its own address (`nixos-container status
jellyfin`, `ip -br addr` inside), VAAPI still works (`nixos-container run
jellyfin -- vainfo --display drm --device /dev/jellyfin-igpu-render` shows
the iGPU, not Navi 31), a transcode runs, DNS resolves inside the container,
and a Family-VLAN client still reaches the web UI.

Constraints:
- Never commit to main. Branch first, PR via `gh pr create` (title
  imperative, <=70 chars, no prefix; body = summary + test plan + manual
  steps).
- No new flake inputs.
- Minimal diffs; commit only the files this change touches.
- Verify by evaluation:
    nix flake check
    nix eval --no-update-lock-file --raw \
      '.#nixosConfigurations.ernst.config.system.build.toplevel.drvPath'
- Claude does not deploy: `clan machines update ernst` is lgo's step.
- Update docs/roadmap.md's status table and interim-rule ledger in the same
  PR.
````

---

## M3 — `feat/ernst-vpn-microvm`

**Goal.** Put qBittorrent behind a VPN in a microvm with a real killswitch —
default-deny egress inside the guest, so a VPN failure means no traffic rather
than leaked traffic. The guest gets its own kernel because it is the one workload
on ernst that talks to the open internet on its own behalf. Downloads land on
`/srv/media` at a path and ownership that let the host-side *arr hardlink them
later.

**Depends on.** M2. **Risk.** Medium-high — new flake input, new isolation tier,
and the uid/gid decision here is the single most common integration failure in
this kind of stack.

````text
Read CLAUDE.md fully before doing anything.

Work in the clanarchy repo on miralda. Branch: feat/ernst-vpn-microvm.
Prerequisite: M2 (br0) merged and deployed.

FLAKE INPUT. Adding microvm.nix is PRE-APPROVED for this milestone (the only
one). Add it to flake.nix with `inputs.nixpkgs.follows = "nixpkgs"` so it
tracks the stable channel the rest of ernst is on, and report the flake.lock
impact in the PR body (what new nodes appear, and whether anything the fleet
already uses gets moved). No other new inputs.

GUEST: "wg-qbittorrent".
  - Minimal NixOS. No X, no docs, no extra packages beyond what qBittorrent
    (nox) and the network stack need.
  - MAC-pinned tap on br0, on the Services VLAN (80). A tap IS the right
    primitive here — this is a microvm, not an nspawn container. Copy
    worked example A from machines/ernst/networking.nix.
  - WireGuard client to the commercial provider, with a REAL killswitch
    implemented as guest-side nftables policy:
      * default-deny on egress from the tap interface;
      * allow ONLY the VPN endpoint IP:port out of the tap;
      * everything else routes via wg0;
      * DNS resolves in-tunnel — no host or LAN resolver, or the killswitch
        leaks names even when it holds packets;
      * INBOUND WebUI on 8080/tcp over the tap is allowed, and
        established/related replies must not be broken by the egress policy.
        The killswitch is an egress policy; a WebUI that cannot answer a
        mgmt-VLAN request is a bug, not extra security.
      * qBittorrent is ADDITIONALLY bound to wg0 at the application level
        (Connection -> Network interface). Belt and braces: nftables is the
        guarantee, the interface binding is the second line.
  - Secrets via clan vars generators (clan.core.vars.generators.*): the
    WireGuard private key, and the provider's endpoint/peer material.
    PROMPT LGO for the provider and credentials at generation time; commit
    NO placeholder secrets and no example keys that look real. Document
    `clan vars generate ernst` in the PR body.

STORAGE — this is the part that decides whether M4 works at all.
  - Share /srv/media/downloads into the guest at the IDENTICAL path. Same
    path on both sides is what makes hardlinks and *arr path mapping sane.
  - Evaluate virtiofs vs 9p and JUSTIFY the choice in a comment: performance,
    whether hardlinks are preserved across the boundary, and how ownership is
    presented. Hardlink preservation is the deciding criterion, not
    throughput.
  - Choose the uid/gid mapping so a HOST-side process (the future arr stack,
    running as its own user in a member of the `media` group, gid 3000 — see
    machines/ernst/containers/jellyfin.nix) can hardlink files the guest
    wrote. Document the mapping in a file-header comment with the reasoning.
    THIS IS THE #1 INTEGRATION FAILURE MODE of the whole stack; treat it as
    a first-class design decision, not a permissions detail.
  - Respect the invariant: /srv/media is ONE hardlink domain, plain
    subdirectories only. Do not add a dataset under it.

EXPOSURE.
  - WebUI reachable from the management VLAN only.
  - NO Traefik route, ever. This is a deliberate, permanent bypass of the
    "everything behind Traefik" rule — record it as such in the PR body and
    in the module header, so a future milestone does not "fix" it.

TEST PLAN in the PR body:
  - VPN exit-IP check from inside the guest (curl an IP-echo service through
    wg0; it must show the provider, never the home WAN address).
  - Killswitch proof: stop wg0 (or blackhole the endpoint) and show with
    tcpdump on the host tap that the guest emits nothing but the allowed
    endpoint traffic — no DNS, no tracker, no peer traffic.
  - Hardlink proof from the HOST side: create a file via the guest, then
    `ln` it host-side across /srv/media and show `stat` link count 2 with
    matching inode. If this fails, M4 cannot work — stop and re-open the
    uid/gid decision.

Constraints:
- Never commit to main. Branch first, PR via `gh pr create` (title
  imperative, <=70 chars, no prefix; body = summary + test plan + manual
  steps).
- No new flake inputs beyond the pre-approved microvm.nix.
- Minimal diffs; commit only the files this change touches.
- Verify by evaluation:
    nix flake check
    nix eval --no-update-lock-file --raw \
      '.#nixosConfigurations.ernst.config.system.build.toplevel.drvPath'
  plus an eval of the microvm guest's own toplevel, and paste the attribute
  path you used.
- Claude does not deploy: `clan machines update ernst` and
  `clan vars generate ernst` are lgo's steps.
- Update docs/roadmap.md's status table in the same PR.
````

---

## M4 — `feat/ernst-arr-stack`

**Goal.** Prowlarr, Sonarr and Radarr in an nspawn container, writing into the
same `/srv/media` hardlink domain qBittorrent writes to, with state on
`/srv/state`. The value of this milestone is the *verified* hardlink chain — a
stack that silently copies instead of linking will fill a 6-wide raidz1 twice
over.

**Depends on.** M3 (for the download client and the uid/gid decision) and
Jellyfin. **Risk.** Medium.

````text
Read CLAUDE.md fully before doing anything.

Work in the clanarchy repo on miralda. Branch: feat/ernst-arr-stack.
Prerequisites: M3 merged and deployed (qBittorrent reachable, hardlink proof
passing), Jellyfin running.

SHAPE. One systemd-nspawn container named "arr" running prowlarr, sonarr and
radarr, in machines/ernst/containers/arr.nix, wired into flake.nix next to
the jellyfin container. If you conclude they should be split into separate
containers, do not just do it — argue it in a file-header comment and keep
the default single-container shape unless the argument is strong.

Networking v1: HOST networking, exactly like Jellyfin's v1, with a
veth-migration note in the file header mirroring the one Jellyfin carried.
Ports 9696 (prowlarr) / 8989 (sonarr) / 7878 (radarr) opened on the host and
scoped to the management VLAN on the UDM-Pro. Add them to the interim-rule
ledger in docs/roadmap.md as row L4 with the M5 trigger.

STORAGE.
  - /srv/media read-write, bound at the IDENTICAL path inside the container.
    Same path on all sides (guest, host, container) is what keeps *arr path
    mapping and hardlinking honest.
  - State under /srv/state/<service> (prowlarr, sonarr, radarr), bound to the
    upstream default state paths inside the container so the packaged units
    need no overrides — the same trick jellyfin.nix uses for
    /var/lib/jellyfin.
  - uid/gid aligned with the decision recorded in M3, and membership of the
    media group (gid 3000, fixed on the host in
    machines/ernst/containers/jellyfin.nix). nspawn does not remap gids here,
    so numeric ids must match exactly on both sides — jellyfin.nix explains
    why in detail; read it.
  - Do NOT add datasets under /srv/media. One hardlink domain, plain
    subdirectories.

VERIFICATION — the point of this milestone. Prove the whole chain, with
`stat` output in the PR body:
    qBittorrent completes a download in the guest
      -> *arr imports it into /srv/media/library/...
      -> `stat` shows link count 2 and the SAME inode for the torrent copy
         and the library copy
      -> the item appears in Jellyfin.
A link count of 1 means a copy happened; treat that as a failed milestone,
not a cosmetic issue, and diagnose the path/uid/gid mismatch behind it.

CONFIGURATION POLICY. Declarative where sane. Where a setting only exists in
the UI (download client registration, root folders, indexer wiring), do NOT
fake it — document the intended in-UI settings in the PR body as a
reproducible checklist, so the state can be rebuilt from the repo plus that
list. recyclarr is explicitly OUT of scope; it is a backlog item to evaluate
after this settles.

HARDENING. Run a `systemd-analyze security` pass on each service inside the
container and record the exposure scores in the PR body, with a note on what
was tightened and what was deliberately left alone. Follow jellyfin.nix's
approach: do not duplicate upstream hardening, and record REJECTED settings
with reasons so nobody re-tries them blindly.

MANUAL STEPS for the PR body (lgo's):
  - Technitium records for the three services.
  - A ZBF rule allowing the arr container to reach the M3 guest's qBittorrent
    API (mgmt-scoped), since the download client lives on a different L2
    identity.

Constraints:
- Never commit to main. Branch first, PR via `gh pr create` (title
  imperative, <=70 chars, no prefix; body = summary + test plan + manual
  steps).
- No new flake inputs.
- Minimal diffs; commit only the files this change touches.
- Verify by evaluation:
    nix flake check
    nix eval --no-update-lock-file --raw \
      '.#nixosConfigurations.ernst.config.system.build.toplevel.drvPath'
- Claude does not deploy: `clan machines update ernst` is lgo's step.
- Update docs/roadmap.md's status table and interim-rule ledger in the same
  PR.
````

---

## M5 — `feat/ernst-traefik`

**Goal.** One reverse proxy, on its own L2 identity, so every consumer VLAN can
be reduced to a single permanent firewall rule pointing at it. Wildcard TLS via
ACME DNS-01 on a real public domain, with records published only inside
Technitium — split-horizon, no public A records. This milestone is what retires
the two interim Jellyfin rules.

**Depends on.** M2; routes for whichever of Jellyfin / arr is live.
**Risk.** Medium — DNS and certificate mistakes are visible to the whole
household.

**Ask first:** the public domain and its DNS provider. `meta.domain` in `clan.nix`
is `goclan.org`, but do not assume that is the one to use for ACME.

````text
Read CLAUDE.md fully before doing anything.

Work in the clanarchy repo on miralda. Branch: feat/ernst-traefik.
Prerequisite: M2 (br0) merged and deployed. Route whatever of Jellyfin (M2b)
and the arr stack (M4) is live at the time.

ASK LGO FIRST, before writing any code:
  - Which public domain to use for certificates (clan.nix's meta.domain is
    goclan.org — do not assume it is the right answer).
  - Which DNS provider holds it, because that decides the ACME DNS-01
    provider config and which credential the vars generator must prompt for.

SHAPE. A systemd-nspawn container "traefik" in
machines/ernst/containers/traefik.nix, with its own MAC-pinned veth on br0
on the Services VLAN (80). NOT a tap — a tap is the microvm primitive; an
nspawn container gets a veth pair whose host side is named vb-traefik.
Copy worked example B from machines/ernst/networking.nix. That veth's
address is the identity every consumer VLAN gets its ONE permanent ZBF
rule for — the whole point of the milestone.

TLS.
  - ACME DNS-01, wildcard certificate. DNS-01 specifically so nothing has to
    be reachable from the internet.
  - SPLIT HORIZON: the names exist only in Technitium. No public A records.
    Say so explicitly in the file header, because the certificate being
    public is what makes people assume the service is.
  - acme.json (or the equivalent store) lives under /srv/state/traefik,
    mode 0600. It is state, so it belongs on zdata, not on the rolled-back
    zroot.
  - Provider credential via a clan vars generator, prompted. No plaintext.

ROUTES.
  - jellyfin — public-ish route for the household.
  - arr services — routes WITH an interim ipAllowList (management VLAN +
    wg-travel). Mark them in a comment as interim and tracked in
    docs/roadmap.md as ledger row L5, to be replaced by Authelia forward-auth
    in M7. Do not invent an auth scheme here.
  - Entrypoint 443 only. If a :80 listener exists at all it does nothing but
    redirect.

BACKEND BYPASS HARDENING. Pick exactly ONE mechanism and justify it in the
file header:
  (a) backend-side firewall source-restriction to Traefik's veth address, or
  (b) a documented UDM-Pro intra-zone ZBF rule.
Both is not "safer" — it is two sources of truth that will disagree. State
which one you chose, what it does not cover, and where the other would have
been better.

JELLYFIN KEEPS NATIVE AUTH, FOREVER. TV and mobile clients cannot deal with
forward-auth. Never put Authelia in front of it; write that into the file
header so M7 does not undo it.

MANUAL STEPS for the PR body (lgo's):
  - Technitium: repoint the jellyfin record from the container (M2b) to
    Traefik; add records for the arr services.
  - UDM-Pro: add the permanent consumer-zone -> traefik:443 rules.
  - EXECUTE THE LEDGER REMOVALS: delete interim rules L1 (Family ->
    ernst:8096) and L2 (skynet-iot -> ernst:8096) from the UDM-Pro, and
    re-check L2a — the IoT DNS plumbing that made name resolution work for
    those clients. Record in docs/roadmap.md which parts of L2a remain
    necessary and promote them out of the interim ledger if they are now
    permanent.
  - Re-point any TV/streaming client bookmarks at the new hostname.

TEST PLAN: certificate issued and renewing (check the ACME log and the
cert's SANs), each route reachable by name from the right VLAN and refused
from the wrong one, backend direct-access blocked by whichever mechanism was
chosen, and Jellyfin playback working from a TV client through the proxy —
including a transcode, since that is where proxies usually break first.

Constraints:
- Never commit to main. Branch first, PR via `gh pr create` (title
  imperative, <=70 chars, no prefix; body = summary + test plan + manual
  steps).
- No new flake inputs.
- Minimal diffs; commit only the files this change touches.
- Verify by evaluation:
    nix flake check
    nix eval --no-update-lock-file --raw \
      '.#nixosConfigurations.ernst.config.system.build.toplevel.drvPath'
- Claude does not deploy: `clan machines update ernst` and
  `clan vars generate ernst` are lgo's steps.
- Update docs/roadmap.md's status table and interim-rule ledger in the same
  PR — this is the milestone that closes L1, L2 and (partly) L2a.
````

---

## M6 — `feat/monitoring`

**Goal.** A fleet-wide clan service module: Prometheus, Alertmanager and Grafana
in an nspawn container on ernst, node_exporter on every machine, scrape targets
generated from the clan role membership rather than hand-listed. Alerting reuses
the ntfy topic that `modules/observability/zfs-ntfy.nix` already owns — one ZFS
alerting path, not two.

**Depends on.** M5 for the Grafana route (mgmt-only until M7). Prometheus itself
does not need it. **Risk.** Low-medium; the fleet-wide half touches laptops.

````text
Read CLAUDE.md fully before doing anything.

Work in the clanarchy repo on miralda. Branch: feat/monitoring.

SHAPE. A clan service module: service-modules/monitoring.nix plus its
readme service-modules/monitoring.md (every module in that directory has
one; manifest.readme = builtins.readFile ./monitoring.md). Register it in
clan.nix under modules."@clanarchy/monitoring" and add an inventory instance.
Model the structure closely on service-modules/local-ai.nix — roles with
interface.options and perInstance nixosModules.

ROLES.
  - roles.server — ernst. Prometheus + Alertmanager + Grafana inside ONE
    systemd-nspawn container (trusted, storage-heavy: the nspawn tier).
    Retention: do the disk math explicitly in a comment — samples/second x
    bytes/sample x retention, against the space actually available — and set
    retention from that number rather than picking a round one.
  - roles.client — every machine (miralda, biene, birte, ernst).
    node_exporter, with the listener restricted so ONLY ernst's address may
    scrape it. On ernst additionally: the zfs, smartmon and systemd
    collectors/exporters, but only those that exist on the STABLE channel —
    check, do not assume, and note anything you had to leave out.

SCRAPE TARGETS ARE GENERATED, NOT LISTED. Derive them from the clan role's
machine list so adding a machine to the role is the only step needed. A
hand-maintained target list in a nix file is a bug waiting for the next
machine; do not write one.

ALERTING — REUSE, DO NOT DUPLICATE. modules/observability/zfs-ntfy.nix
already routes ZED events to an ntfy topic held in a clan var, and is
imported fleet-wide by commonBase (lib/mk-machine.nix). Route Alertmanager
to the SAME topic/wiring. Then decide, and justify in the PR body, between:
  (a) absorbing ZFS alerting into Prometheus rules and retiring the zedlet,
      or
  (b) keeping both deliberately — ZED catches events Prometheus can only
      infer, and it keeps working when the monitoring container is down.
Whichever you choose, the outcome must NOT be two systems alerting on the
same pool event.

STARTER RULES ONLY. Resist a rule library:
  - host down
  - zpool not ONLINE / degraded
  - SMART failure predicted
  - filesystem >85% full
  - any systemd unit in failed state
  - TLS certificate expiring in <14 days (M5's wildcard)

GRAFANA. Behind Traefik (M5), management VLAN only until M7 switches it to
Authelia OIDC. Datasource declared as code, plus exactly ONE dashboard as
code covering node + zfs basics. Not a dashboard collection.

FLEET COST. The client role lands on two laptops and a Steam Deck. Show in
the PR body that idle cost is negligible: which collectors are enabled,
scrape interval, and the resulting wakeups. If node_exporter's defaults are
chatty, trim them and say so — a laptop losing battery to monitoring is a
regression, not a trade-off.

Constraints:
- Never commit to main. Branch first, PR via `gh pr create` (title
  imperative, <=70 chars, no prefix; body = summary + test plan + manual
  steps).
- No new flake inputs.
- Minimal diffs; commit only the files this change touches.
- Verify by evaluation — ALL FOUR machines, since this is fleet-wide:
    nix flake check
    for m in miralda biene birte ernst; do
      nix eval --no-update-lock-file --raw \
        ".#nixosConfigurations.$m.config.system.build.toplevel.drvPath"
    done
  (.github/workflows/check.yml runs the same loop.)
- Claude does not deploy: `clan machines update <machine>` for each machine
  is lgo's step, ernst first.
- Update docs/roadmap.md's status table in the same PR.
````

---

## M7 — `feat/ernst-authelia`

**Goal.** A single sign-on layer in front of the admin UIs: Authelia as a Traefik
forward-auth middleware, replacing the interim `ipAllowList` on the arr and
Grafana routes, with TOTP as the second factor. Authelia over Keycloak — one Go
binary, a forward-auth model that fits Traefik natively, and an OIDC provider for
Grafana; there is no federation requirement that would justify Keycloak's weight.

**Depends on.** M5. **Risk.** Medium — the failure mode is locking yourself out of
your own admin UIs from a remote network.

````text
Read CLAUDE.md fully before doing anything.

Work in the clanarchy repo on miralda. Branch: feat/ernst-authelia.
Prerequisite: M5 (Traefik) merged and deployed.

DECISION ALREADY MADE: Authelia, not Keycloak. Record the rejection in the
PR body — single Go binary versus a JVM stack, native forward-auth fit with
Traefik, built-in OIDC provider, and no federation/SAML requirement here that
would justify Keycloak's operational weight. Do not re-litigate it; do
record it, so the next reader knows it was a choice.

SHAPE. systemd-nspawn container in machines/ernst/containers/authelia.nix.
SQLite storage (single instance, no HA need) under /srv/state/authelia.
Secrets via clan vars generators — jwt secret, session secret, storage
encryption key. GENERATE them (openssl rand in the generator script) rather
than prompting, except where a value genuinely has to come from lgo. No
placeholder secrets committed.

USERS. lgo and sabine — CONFIRM the list with lgo before writing it. File-
based user database, password hashes produced by a generator, TOTP enrolled
per user on first login.

TRAEFIK INTEGRATION.
  - A forwardAuth middleware, applied to the arr routes and the Grafana
    route, REPLACING the interim ipAllowList (ledger row L5 in
    docs/roadmap.md — retire it in this PR).
  - Evaluate whether to stack the allowlist underneath forward-auth as
    defence in depth. The risk is a wg-travel lockout: if the allowlist stays
    and the travel VPN's source address is not in it, valid credentials will
    not help from the road. State the decision and, if stacking, prove the
    wg-travel range is included.
  - Access control: deny by default. two_factor policy for admin UIs. Bypass
    ONLY for the OIDC endpoints and health checks that must be unauthenticated
    for the flow to work — enumerate them, do not use a broad prefix.

GRAFANA. Switch to Authelia OIDC. KEEP the local admin account as
break-glass, with a note in the PR body on how to reach it when Authelia is
down.

JELLYFIN IS EXPLICITLY EXEMPT. Native auth, no forward-auth, ever — TV and
mobile clients cannot handle the redirect flow. M5 wrote this into the
traefik file header; keep it there and repeat it in Authelia's.

TEST PLAN: unauthenticated request to an arr route is redirected to the
Authelia portal; login + TOTP grants access; Grafana OIDC login works and
maps to the right role; the break-glass local admin still works; Jellyfin is
untouched; and — explicitly — a request from the wg-travel network succeeds.

Constraints:
- Never commit to main. Branch first, PR via `gh pr create` (title
  imperative, <=70 chars, no prefix; body = summary + test plan + manual
  steps).
- No new flake inputs.
- Minimal diffs; commit only the files this change touches.
- Verify by evaluation:
    nix flake check
    nix eval --no-update-lock-file --raw \
      '.#nixosConfigurations.ernst.config.system.build.toplevel.drvPath'
- Claude does not deploy: `clan machines update ernst` and
  `clan vars generate ernst` are lgo's steps.
- Update docs/roadmap.md's status table and interim-rule ledger in the same
  PR — this milestone closes L5.
````

---

## Floating / backlog

Not sequenced. Each becomes a milestone when it earns one.

**Xbox pad over Bluetooth on ernst — blocked upstream, not by us.** The board's
MediaTek MT7927 (Filogic 380) Bluetooth half fails at HCI reset: `btmtk` on
6.18.43 has no case for hardware variant `0x6639`, and the firmware blob
`BT_RAM_CODE_MT6639_2_1_hdr.bin` is still in a draft linux-firmware MR pending
MediaTek's redistribution sign-off. The driver fixes are in mainline around
kernel 7.1, but the firmware is the real gate, so this is not a flake bump away.
Wired pads and USB dongles both work today — see
[the controllers guide](guides/htpc-controllers.md), which carries the two
one-line checks to re-run after a future bump.

**Remove NetworkManager from ernst.** It is enabled unintentionally:
`modules/roles/htpc.nix` imports `modules/desktop/kde.nix`, which sets
`networking.networkmanager.enable = true`. Nothing on ernst needs it — clan uses
networkd and ernst is excluded from the wifi service; the couch user `go` is not
in the `networkmanager` group; Steam and gamescope do not use it. The intent was
already recorded in `machines/ernst/htpc.nix`: *"No wheel, no networkmanager
(ernst is networkd + wired)."*

It is not free, either: `nmcli` reports `enp13s0` as `connected (externally)`, so
NM is not hands-off, and it is the reason `machines/ernst/networking.nix` carries
a `networking.networkmanager.unmanaged` list at all.

`networking.networkmanager.enable = lib.mkForce false;` on ernst **evaluates
cleanly** (verified 2026-08-19), but it has one non-obvious consequence: NM is
what sets `networking.useDHCP = false`, so removing it flips `useDHCP` back to
`true` and `99-ethernet-default-dhcp` becomes a **live** unit with `DHCP=yes` on
physical NICs, instead of the inert one M2 hardened. `enp13s0` is unaffected
(`50-*` sorts first) and `br0`/veths/taps are excluded by `Kind = "!*"`, but
`enp12s0` would attempt DHCP if it were ever plugged in.

Deliberately **not** bundled into M2: stacking a NetworkManager removal onto the
one deploy that can cause remote lockout is exactly what the cutover runbook warns
against. Do it as its own small PR after the bridge is proven, and decide there
whether the cleaner shape is an option on the KDE module rather than an
ernst-local `mkForce`.

**Refresh `docs/guides/ernst-zdata-datasets.md`.** Unchanged since #20 apart from
the deploy-helper sweep. It still describes five datasets including
`zdata/media/movies` and `zdata/media/tvshows`, which were deliberately collapsed
into plain subdirectories so *arr hardlinks work — and it predates `/srv/unsorted`
and `/srv/gardens` (#66). A guide that describes a layout the repo rejects is
worse than no guide.

**Execute `docs/runbooks/ernst-enable-impermanence.md`.** ernst has never had
`@blank` snapshots, so its rollback has been a silent no-op since install. The
runbook exists; step 4 is a one-way door. Operator work, not a Claude milestone —
but every milestone above accumulates state on a machine that is not yet
impermanent, which is worth knowing.

**clan-core `Domains=skynet.lan` upstream PR.** A separate session in a separate
repo. Needs a minimal reproduction first — the smallest clan config that shows
the missing search-domain plumbing — before anything is proposed upstream.

**Uptime Kuma on an external VPS.** Off-repo, or a future machine entry. It
watches skynet from *outside*: ernst dying, the WAN dropping, public-domain
certificates expiring — the failures an internal monitor cannot report because it
dies with them.

- Open design question, to settle when it is built: how it reaches internal
  services. Either public-endpoint checks only (simple, limited), or a WireGuard
  peer into the UDM-Pro with its own tightly scoped ZBF zone — `wg-vps →
  traefik:443` and nothing else.
- Shares the ntfy topic with M6 alerting.
- Division of labour: Prometheus (M6) is internal infrastructure truth; the VPS
  Kuma is the outside-in user path. Neither replaces the other.

**recyclarr.** Evaluate after M4 has settled and the quality profiles have been
touched by hand at least once — otherwise there is nothing to codify.

**Expose Ollama via Traefik.** Reopens the native-vs-container decision: Ollama
runs as a host service today because ROCm wants the card directly. Putting it
behind Traefik means deciding whether it stays native with a route pointed at the
host, or moves into a container with GPU access plumbed through.

**Un-parking Bigscreen.** Only if one of the two routes #64 identified becomes
acceptable: Plasma 6.7.4 on the host (ernst's desktop then tracks floating
unstable and diverges from the fleet), or a VM with the dGPU passed through (VFIO
binds the card exclusively, taking it from ROCm/Ollama — the outcome `clan.nix`
rejects). Neither is attractive today, which is why it is parked rather than
scheduled.
