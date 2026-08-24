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

Verified against the repo on 2026-08-20 (`main` @ `f9b305e`).

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
| ernst `@blank` snapshots | **done — executed 2026-08-18** | — | `zroot/root@blank` + `zroot/home@blank` taken 21:35–21:36, all five steps of `docs/runbooks/ernst-enable-impermanence.md` including the one-way door. **Observed, not assumed**: `clanarchy-impermanence-check` failed at 21:33 — the #54 tripwire doing its job — passed at 21:36 once the snapshots existed, and passed again on the 21:37 reboot (`ExecMainStatus=0`). Step 5's checks hold: `/root/.ssh/authorized_keys` gone with SSH still working, `container@jellyfin` active, its journal intact across the reboot |
| M1 — Kvantum linkGeneration drift | **closed — did not reproduce** | — | Four consecutive activations in the retained journal all passed `linkGeneration`. The on-disk shape that looked like drift is Stylix's `recursive = true` working as designed. See [M1](#m1-kvantum-linkgeneration-drift-closed) |
| M2 — ernst VLAN bridge | **done — deployed 2026-08-20** | [#73](https://github.com/lutzgo/clanarchy/pull/73) | `br0` VLAN-filtering bridge, `enp13s0` as tagged trunk; VLAN 90 (Services) created for M2b/M5. Cutover verified: `br0` holds `10.0.50.10/24`, `enp13s0` enslaved, the `br0 50 PVID Egress Untagged` self entry present, NM now `unmanaged`. [Runbook](runbooks/ernst-vlan-bridge-cutover.md). See [M2](#m2-ernst-vlan-bridge-built-cutover-pending) |
| M2b — Jellyfin on its own veth | **done — deployed 2026-08-20** | [#82](https://github.com/lutzgo/clanarchy/pull/82) | Jellyfin on `10.0.90.10` via MAC-pinned veth `vb-jellyfin`, VLAN 90. **L3 retired.** Survived a reboot: `br0`'s pinned MAC reproduced at first boot-time creation, the VLAN race won by networkd, `/srv/state/jellyfin` intact through the rollback, `clanarchy-impermanence-check` green. The Nix half deployed first try; the [UDM-Pro half took five rounds](#the-udm-pro-half-cost-more-than-the-nix-half) and disproved M2's Connection-State finding. [M2b](#m2b-jellyfin-on-its-own-veth-done-deployed-2026-08-20) |
| M3 — VPN microvm + qBittorrent | **done — deployed 2026-08-20** | [#83](https://github.com/lutzgo/clanarchy/pull/83) | `wg-qbittorrent` on the microvm tier: tap on VLAN 90, IVPN wg-quick tunnel, guest-side nftables killswitch. **Killswitch proven**: with wg0 down the guest emitted zero packets and DNS failed rather than leaking. **Hardlink chain proven**, with a negative control — `UMask=0002` is what M4 depends on. Three things had to be fixed after the first deploy: wg-quick wins any routing-rule priority race, a tmpfiles/oneshot contradiction in `jellyfin.nix` had been silently resetting the media directory modes since M2b, and the UDM-Pro policy editor has two Port sections. [M3](#m3-featernst-vpn-microvm-done--deployed-2026-08-20) |
| M4 — arr stack | **done — deployed, proven, and survived an unplanned power cut 2026-08-21** | [#85](https://github.com/lutzgo/clanarchy/pull/85) | Prowlarr/Sonarr/Radarr in one nspawn container, `machines/ernst/containers/arr.nix`. **Departs from its own prompt on networking**: veth on br0 / VLAN 90 (MAC `02:00:00:90:00:05`, `10.0.90.13`) rather than the host-networking v1 the prompt described, because that prompt predates M2b and `networking.nix` already names M4 as a pattern-B consumer. Consequence worth knowing: the arr reaches qBittorrent at L2 over `br0`, so **the UDM-Pro never sees that traffic** and the ZBF rule the prompt listed as a manual step does not exist — the guest's `api_clients` nftables set is the only thing enforcing it. The milestone is **not** done until the `stat` proof runs on ernst. [M4](#m4-featernst-arr-stack) |
| M5 — Traefik | **done — deployed 2026-08-23, proven 2026-08-24** | [#86](https://github.com/lutzgo/clanarchy/pull/86) | `machines/ernst/containers/traefik.nix`: nspawn container on `vb-traefik`, VLAN 90, MAC `02:00:00:90:00:04` → `10.0.90.12`. One wildcard `*.goclan.org` over ACME DNS-01 at Cloudflare, scoped API token via clan var `traefik-acme`, store on `zdata` at `/srv/state/traefik`. Routes: jellyfin (no middleware, ever) + prowlarr/sonarr/radarr behind the interim `mgmt-only` ipAllowList (L5). **Backend bypass hardening is mechanism (a)** — each backend's own firewall accepts its web port only from `10.0.90.12` — because Jellyfin, the arr, qBittorrent and Traefik are all ports on `br0` and their traffic never reaches the UDM-Pro, so an intra-zone ZBF rule could not see it. **Two consequences on deploy day**: direct access to `10.0.90.10:8096` and `10.0.90.13:{9696,8989,7878}` stops working immediately, so TV clients must move to `jellyfin.goclan.org` in the same window; and the ACME propagation check queries `1.1.1.1`/`9.9.9.9` directly, which a UDM-Pro DNS-interception rule would silently break. [M5](#m5-featernst-traefik) |
| M6 — monitoring | **done — deployed, alerting proven end to end, and survived a real reboot 2026-08-24; biene/birte pending** | [#87](https://github.com/lutzgo/clanarchy/pull/87) | **Working**: container on `10.0.90.14`, VLAN 90 won unaided, every deployed target scraping `up`, Grafana served through Traefik, and `traefik_tls_certs_not_after` (89 d) + `zfs_pool_health` (0/0) both confirmed **live** — retiring the two metric names that had only been read out of binaries' strings. **Notifications arrive**, from both publishers, on rotated topics — the first confirmed ntfy delivery in this fleet's history. **Survived a real reboot**: `mon0` and `vb-monitoring` created by a boot rather than a deploy, container back on `.14`, the TSDB holding pre-reboot samples, `clanarchy-impermanence-check` green — which closes invariant #7 for this milestone and the `mon0`-across-a-reboot question inherited from M2b. **Three deploys, each caught a real defect.** The first stopped at `monitoring-secrets`, by design — and the value it refused exposed that `modules/observability/zfs-ntfy.nix`'s zedlet **has never worked on ernst**: the var holds a bare topic (what the prompt's own `openssl rand -hex 12` hint produces), curl could not resolve it as a hostname, and `>/dev/null 2>&1` threw the error away. The second exposed that **`systemd-networkd-wait-online` could never succeed in this container** — a veth has no carrier until both ends are up, and `mon0`'s host end is brought up by `postStart`, which runs *after* the container's boot, so wait-online was waiting on an event its own completion gates. The 20 s cap contained it; `RequiredForOnline = "no"` fixes it. [Details](#first-deploy-2026-08-24-the-fail-closed-path-fired-and-it-found-an-older-bug). `service-modules/monitoring.nix` (+ `.md`, + one dashboard as JSON): a clan service module with a `client` role on all four machines and a `server` role on ernst. **Scrape targets are derived from `roles.client` membership** — each machine's address comes from the `zerotier-ip-<machine>-zerotier` var clan-core already generates, so adding a machine to the role is the only step needed. The stack is one nspawn container on `vb-monitoring`, VLAN 90, MAC `02:00:00:90:00:06` → `10.0.90.14`, state on `zdata` at `/srv/state/monitoring`. **The one genuinely new piece of engineering is a SECOND interface**: `mon0`, a point-to-point ULA veth to the host, because both things Prometheus must scrape — ernst's own exporters (VLAN 50) and three laptops (ZeroTier, which terminates in the host netns) — are unreachable from VLAN 90. The host forwards and SNATs onto `zt+`, which has the useful side effect that scrapes arrive at a laptop from ernst's own ZeroTier address, i.e. the one source each client permits. **Alerting is (b), keep both**, with the overlap made empty: ZED owns pool state, Prometheus owns everything else and has no `zfs_pool_health` rule, and `ZedNotRunning` is the interlock. Both end at the same ntfy topic. [M6](#m6-featmonitoring) |
| M7 — Authelia | **open** | — | [M7](#m7-featernst-authelia) |
| M8 — Tvheadend / SAT>IP live TV | **open — operator gate first** | — | Steps 1–3 (patching, UniFi, stream test) are lgo's and must clear before a session starts; the milestone dies if the FRITZ!Box's DVB-C is branding-locked. [M8](#m8-featernst-tvheadend) |
| M9 — TubeSync | **open** | — | Feeds the Jellyfin library directly. First occupant of the **podman** tier (not in nixpkgs — verified), so it builds the tier as well as the service; podman's attachment to `br0` is unsolved here. [M9](#m9-featernst-tubesync) |
| M10 — Kodi + IR remote | **dropped — 2026-08-20** | — | Dropped by lgo before any code was written: the couch requirement is Plasma Bigscreen plus Steam, and Kodi is a third media UI nobody asked for. The IR-receiver half was orthogonal and survives as a [backlog entry](#floating-backlog) |

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

Since **2026-08-18** this is enforced rather than aspirational. ernst had no
`@blank` snapshots until then, so its rollback was a silent no-op and *no
milestone to date has had to think about `/persist`* — state survived because
nothing reset it, not because anything was declared correctly. That is over.
Anything written to `zroot` now disappears on the next boot unless it is
declared. M2b, M3 and M4 each carry service state that had never once been
tested against a real rollback, so for those three the first reboot after deploy
is part of the milestone, not an afterthought. **M2b and M3 have now passed
that reboot** — M3's `/srv/state/qbittorrent` survived intact while
`/var/lib/microvms` was correctly rebuilt from the store, which is the
distinction the invariant is about. M4 remains untested against it.
`clanarchy-impermanence-check` (#54) is the tripwire: it passes on ernst, and a
milestone that makes it fail has broken something.

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
| L1 | `LAN (1)` → Jellyfin `10.0.90.10:8096/tcp` | UDM-Pro ZBF policy `Allow Jellyfin to Services`, ID `10001` | Jellyfin is reached directly; there is no reverse proxy yet | **M5** — repoint clients at `jellyfin.<domain>` and replace with the permanent `LAN → traefik:443` rule | **RETIRED 2026-08-23** — policy deleted from the UDM-Pro by lgo with [#86](https://github.com/lutzgo/clanarchy/pull/86). It was already inert by then: the container refuses `8096` from anything but `10.0.90.12`, so the policy was permitting traffic the backend drops. Deleted anyway, because a permit rule that does nothing is the kind of thing someone later "fixes" by removing the restriction instead |
| L2 | `IoT (20)` → Jellyfin `10.0.90.10:8096/tcp` | UDM-Pro ZBF policy `Allow Jellyfin to Services`, ID `10000` | TVs / streaming devices live on the IoT VLAN | **M5** — same as L1 | **RETIRED 2026-08-23** — policy deleted from the UDM-Pro by lgo with [#86](https://github.com/lutzgo/clanarchy/pull/86). This was the row with a household cost attached: the TV on VLAN 20 lost Jellyfin from the moment M5 deployed until it was pointed at `jellyfin.goclan.org`. Deploy and repoint in one window, and note the same will apply to every future backend that moves behind the proxy. **Careful deleting by ID**: `Allow Jellyfin to DNS` also carried ID `10000` and is PERMANENT — match on the destination (`10.0.90.10:8096`), not the number |
| L2a | IoT name resolution for L2 | — | IoT clients could not resolve `jellyfin.skynet.lan` | **M5** — repoint at Traefik | **PROMOTED OUT OF THE LEDGER by M5 — permanent, and nothing was ever built for it.** Re-checked as the milestone required. The substance changes (the name IoT must resolve is now `jellyfin.goclan.org`, not `jellyfin.skynet.lan`) but the plumbing does not: M2b measured `dig @10.0.5.3` succeeding from VLAN 20, so IoT's path to Technitium works and is what serves the new name too. There is no shim here to retire and never was — the row existed to track a constraint that turned out not to exist. It stays listed only so a future milestone does not re-derive it from scratch |
| — | `Services → DNS-Container` `:53` | UDM-Pro ZBF policy `Allow Jellyfin to DNS`, ID `10000` | The `services` zone is isolated by default, so the container could not resolve at all | **permanent** — not interim, listed here only so it is not mistaken for one | created by M2b. `Services → External` was predicted to be needed too and **was not** — it already passed. M5 leans on both: Traefik resolves through Technitium, and reaches Let's Encrypt and Cloudflare's API through External |
| — | `LAN (1)` + `IoT (20)` + `Servers (50)` → traefik `10.0.90.12:80,443/tcp` | UDM-Pro ZBF policy `Allow Traefik`, ID `10006` | **This is the rule M5 exists to make possible** — one permanent rule per consumer zone, pointing at one address, replacing L1/L2 and pre-empting L4/L8 | **permanent** — every future web service is a Traefik route plus a Technitium record, and touches the UDM-Pro not at all | **created 2026-08-23** with [#86](https://github.com/lutzgo/clanarchy/pull/86). Same shape as the qBittorrent and arr rows: source zone `Internal` narrowed to the listed networks, **ports in the Destination card** (the source card has a Port section too and it is the one you see first), `Auto Allow Return Traffic` ticked. **`80` is in the list on purpose**: Traefik's `:80` entryPoint serves nothing but a 308 to `:443`, and permitting only 443 would leave that listener unreachable. Two things cost a round each — see the note below. **CORRECTION, measured 2026-08-24 during M6's deploy: the live policy's source list is `LAN + IoT` only — `Servers` is NOT in it**, and `curl -k https://10.0.90.12/` from ernst times out, which is the same symptom M5 lost a round to. Either the row was written from intent rather than from the device, or the network was removed afterwards. Re-add `Servers` unless there is a reason not to; M5's argument for it (the firewall and the `mgmt-only` ipAllowList should agree about what management access means, and the ipAllowList already trusts `10.0.50.0/24`) still holds. Nothing in M6 depends on it |
| L3 | `networking.firewall.allowedTCPPorts = [ 8096 ]` on the host | `machines/ernst/containers/jellyfin.nix` | Jellyfin shares the host network namespace (`privateNetwork = false`), so its port is a host port | **M2b** — the veth on VLAN 90 gives the container its own L2 identity; the host port opening goes away and the ACL moves to the UDM-Pro | **retired in [#82](https://github.com/lutzgo/clanarchy/pull/82)** — the line is deleted from the repo; 8096 is now opened only inside the container's own netns. Effective on the next `clan machines update ernst` |
| — | `LAN (1) → qBittorrent 10.0.90.11:8080,22/tcp` | UDM-Pro ZBF, M3 | The qBittorrent WebUI (and the guest's SSH) are reachable from the management networks and nowhere else | **permanent** — architecture invariant #4 names this bypass explicitly. It is listed here only so a future milestone does not mistake it for an interim row and "fix" it by adding a Traefik route | **created and verified 2026-08-20.** Source zone `Internal`, narrowed to the `LAN` + `Servers` networks; destination `10.0.90.11` tcp `8080,22`; `Auto Allow Return Traffic` ticked. Servers (50) does need to be listed — with it, `ssh` from ernst itself works. **The port belongs in the Destination card**: the editor has a Port section in *both* zone cards and the source one is the one you see first, which matches only traffic *from* 8080/22, i.e. never |
| L4 | `LAN (1)` + `Servers (50)` → arr `10.0.90.13:9696,8989,7878/tcp` | UDM-Pro ZBF, M4 | The three arr WebUIs are reached directly; there is no reverse proxy yet | **M5** — replace with the permanent `LAN → traefik:443` rule and Traefik routes | **never created — superseded by M5, [#86](https://github.com/lutzgo/clanarchy/pull/86).** M4 shipped without it and M5 landed before anyone needed it badly enough to add it, so the interim rule this row describes has no lifetime at all: the arr UIs go straight from "reachable only from inside `br0`" to "reachable through Traefik". **Do not create it now.** The three ports are source-restricted to `10.0.90.12` in `containers/arr.nix`, so a ZBF permit for them would be a rule the backend ignores. Earlier revisions of this table also predicted a host-firewall row plus a veth migration; M4 skipped v1 and went straight to the veth, so neither ever existed either |
| L5 | Traefik `ipAllowList` on the arr + Grafana routes (mgmt + wg-travel) | M5 (`traefik` container) | There is no identity provider yet | **M7** — replaced by the Authelia forward-auth middleware | **created in [#86](https://github.com/lutzgo/clanarchy/pull/86)** as middleware `mgmt-only` in `containers/traefik.nix`, `sourceRange = 10.0.10.0/24, 10.0.50.0/24, 10.0.70.0/24` — LAN, Servers, and the travel/wg VLAN. Applied to the prowlarr / sonarr / radarr routers and **not** to jellyfin. **The Grafana half arrived with M6 ([#87](https://github.com/lutzgo/clanarchy/pull/87))** — same middleware, same three ranges, on a fourth router (`grafana.goclan.org` → `10.0.90.14:3000`), so M7 replaces one middleware and not two mechanisms. Grafana keeps its own admin login underneath the forward-auth: it is the account that still works when the identity provider is the thing that is broken, which is exactly when someone wants a dashboard. Two things M7 must not get wrong: it matches the TCP peer address and ignores `X-Forwarded-For` (correct, because nothing sits in front of this proxy — do not add `forwardedHeaders`), and VLAN 70 is in the list on purpose, so replacing it must not lock lgo out from the road |
| L6 | Tvheadend ports `9981` / `9982` on the host, mgmt-VLAN scoped | M8 (host firewall, v1) | Only if M8 lands before M2b — Tvheadend v1 would then run on host networking like Jellyfin's and arr's did | **M5** for the web route, plus a veth migration mirroring M2b. Never created at all if M2b lands first | **never created — both gates have now closed.** M2b landed first, so Tvheadend was never going to run on host networking; M5 has landed too, so the web route already exists as a pattern to copy. M8 should go straight to a veth on VLAN 90 plus a Traefik route, exactly as M4 did |
| L7 | FRITZ!Box → Tvheadend on the ephemeral **UDP** range | UDM-Pro ZBF (off-repo), M8 | SAT>IP media is unicast RTP on a return flow the RTSP rule does not cover | Proving RTP **interleaved over the RTSP TCP connection**, which reduces the whole ACL to TCP 49000 + 554 | not yet created — **avoid**; take the interleaved-TCP path if M8's Phase 0 shows it works |
| L8 | TubeSync web UI port, mgmt-VLAN scoped | M9 (host/container firewall, v1) | Only if M9 lands before M5 — an admin UI with no proxy in front of it yet. Mgmt-scoped, so invariant #3 does not cover it | **M5** — replace with the Traefik route. Never created at all if M5 lands first | **never created — M5 landed first.** M9 gets a Traefik route (`tubesync.goclan.org`, behind the `mgmt-only` middleware) and opens no port. Note this does not solve M9's actual open question, which is how a podman container attaches to `br0` on VLAN 90 at all |

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
| 70 | Travel (wg) | 10.0.70.0/24 | not carried |
| — | *(site-to-site WG peer)* | 10.0.80.0/24 | routed to `wgsrv1` — **not available** |
| **90** | **Services** | **10.0.90.0/24** | tagged — **new**, created for M2b/M5 |

VLAN 90 did not exist before this milestone. M2b and M5 both assumed a services
zone; there wasn't one, so services would have shared the host's firewall zone
and invariant #3 would have meant nothing. It is tagged on the trunk now, before
anything uses it, so M2b/M3/M5 never need a switch-port change.

Services is **90**, and the two numbers it is not are both deliberate:

- **not 70** — that is the travel/WireGuard VLAN, the one M5's interim
  `ipAllowList` and M7's wg-travel lockout warning refer to;
- **not 80** — `10.0.80.0/24` is routed to a live site-to-site WireGuard peer
  (`allowed ips: 10.0.70.2/32, 10.0.80.0/24` on `wgsrv1`, 16 GiB in / 56 GiB
  out). Services was originally built there and its gateway silently never
  answered ARP; see below.

30/40/60/70/80 are deliberately off the trunk: a VLAN that is not carried cannot
be reached by a typo in a future container unit, and travel reaches services
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
also 50. It cannot be placed on VLAN 90, which is the whole point. Correcting
that file header belongs to M2b, which owns the file.

### Two UDM-Pro findings from the cutover prep

**~~A ZBF policy with `Connection State: All` silently never matches.~~
DISPROVED by M2b — see [that milestone's UDM-Pro section](#the-udm-pro-half-cost-more-than-the-nix-half).**
The original observation: the new `Allow Jellyfin from IoT to Servers` rule sat
at ID `10000` — first in evaluation order, ahead of `Block IoT to Trusted` — and
still logged **zero hits** while the TV failed to connect; every field matched
the working `Allow Jellyfin from LAN to Servers` rule except Connection State,
and setting it to `Custom → New` appeared to fix it.

The conclusion drawn from that was wrong twice over. `All` matches fine — M2b
watched the SYN traverse a rule set to `All`. And the LAN rule this was compared
against was **not carrying its traffic at all**: LAN and Servers are both in the
`Internal` zone, and `Internal → Internal` is `Allow All`, so the blanket zone
rule was doing the work and the Jellyfin rule's settings were never exercised.
The real variable is **`Auto Allow Return Traffic`**, which is independent of
Connection State. Do not reach for `Custom → New` on the strength of this
paragraph; read M2b's table.

What *does* hold from this finding: the policy list is sorted **alphabetically by
name**, not by evaluation order — read the **ID** column instead — and a zero hit
count is a *matching* problem rather than an ordering one.

**VLAN 80's gateway was silent because the *subnet* was already taken.**
`10.0.80.0/24` is claimed by the `skynet-travel` WireGuard config, so the UDM-Pro
held two routes for it and `10.0.80.0/24 dev wgsrv1 proto VPN` shadowed the
connected `dev br80`. With `arp_filter = 1` on the UDM's bridges, an ARP reply is
conditional on the kernel routing back to the sender out of the same interface —
it would have used `wgsrv1`, so it silently declined to answer on `br80`.

Everything else tested correct: bridge members enslaved, address present,
requests visibly arriving, sysctls identical to the working `br20`, ebtables
empty. **A free VLAN ID does not imply a free subnet** — check new subnets against
`ip route show` on the UDM-Pro before creating the network. Full diagnostic
sequence in the [cutover runbook](runbooks/ernst-vlan-bridge-cutover.md).

**Resolved by renumbering.** `wg show` identified the claimant as a live
site-to-site peer, not a stale entry — 16.02 GiB received / 55.78 GiB sent — so
reclaiming the subnet would have broken that tunnel's routing. Services moved to
**VLAN 90 / `10.0.90.0/24`**, verified free first, and `10.0.80.0/24` is the only
subnet routed to `wgsrv1`. Renumbering keeps the convention that the VLAN ID is
the third octet, which `10.0.90.0/24` on VLAN 80 would have broken.

### Carried forward

- **Pin `br0`'s MAC before M2b.** ~~Not done here~~ — **done in M2b**
  ([#82](https://github.com/lutzgo/clanarchy/pull/82)), which is where the
  second port arrives — but **not to the value this note predicted, and the
  hazard it named cannot occur.** `br0` never inherited `enp13s0`'s MAC; it
  carries a networkd-assigned `b2:8b:e1:f2:1e:7c` with
  `addr_assign_type = 3` (`NET_ADDR_SET`), which makes the kernel skip
  lowest-port-MAC adoption entirely. See M2b's item 1.
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

## M2b — Jellyfin on its own veth (done — deployed 2026-08-20)

**Deployed and verified across a reboot.** The repo change applied on the first
attempt; the UDM-Pro work either side of it took five rounds and is written up
[below](#the-udm-pro-half-cost-more-than-the-nix-half), because M4, M5 and M8 all
add rules into the same zone.

Jellyfin now runs in its own network namespace on a MAC-pinned veth
(`02:00:00:90:00:02`), whose host side `vb-jellyfin` is a VLAN-90 port on `br0`.
That gives it an L2 identity the UDM-Pro firewalls as a distinct client rather
than as "ernst", which is what retires ledger row **L3**: the host-side
`allowedTCPPorts = [ 8096 ]` is deleted, and 8096 is opened only inside the
container's own netns.

**Addressing is DHCP with a reservation**, not a static address in the repo. The
UDM-Pro already owns the subnet, the pool and every other reservation on it; a
second copy here would be a source of truth that diverges silently. The
*resolver* is the opposite call — declared in the container (`DNS=10.0.5.3`,
`Domains=~. skynet.lan`, `UseDNS=false`) for the same reason note 1 in
`machines/ernst/networking.nix` declares it on `br0`: a DHCP-supplied resolver
that quietly changes does not fail loudly.

### Four things worth carrying forward

1. **`br0`'s MAC is pinned — but M2's stated reason for it was wrong, and
   following it would have caused the very outage it warned about.** M2 deferred
   the pin to M2b on the theory that a Linux bridge adopts the numerically
   **lowest** port MAC, so the veth added here (random, locally administered,
   `0x02`/`0x06`/`0x0a` … all below `enp13s0`'s `0xa0`) would silently move
   ernst's L2 identity. Measured on ernst 2026-08-20, before deploying anything:

   ```
   ip -br link show br0                      → b2:8b:e1:f2:1e:7c   (NOT enp13s0's)
   cat /sys/class/net/br0/addr_assign_type   → 3                   (NET_ADDR_SET)
   ```

   systemd-networkd sets a MAC on the netdevs it creates, so
   `br_stp_recalculate_bridge_id()` returns early rather than adopting a port
   address. The kernel behaviour is real; it simply cannot fire on a
   networkd-created bridge. Pinning to §1.4's `a0:ad:9f:1c:9d:74` as instructed
   would therefore have **changed** `br0`'s MAC on the same deploy that moves
   Jellyfin, on the interface carrying ernst's only management address — two
   risks in one deploy, to avert a hazard that does not exist. The observed
   `b2:8b:e1:f2:1e:7c` is pinned instead, which is a no-op today.

   The pin still earns its place, for the reason nobody had checked: **`br0` has
   never survived a reboot.** The current boot began 2026-08-18 21:37; `br0` was
   created live by the cutover deploy at 2026-08-20 10:11. No boot has ever
   regenerated it, so nothing has confirmed networkd's value is reproducible.
   Pinning settles that in the safe direction either way.

   **The transferable lesson:** §1.4 recorded `enp13s0`'s MAC and *predicted*
   `br0` would inherit it; nobody re-read `br0` afterwards. Same failure shape as
   M2's VLAN 80 — a plausible inference recorded as a measurement. Record what
   you measured.
2. **`services.jellyfin.openFirewall` is still `false`, for a new reason.** The
   obvious v2 move is to flip it true now that the container has its own
   firewall. Upstream's `openFirewall` opens 8096 **and** 8920/tcp **and**
   1900+7359/udp — exactly the three ports this file has always refused. The
   container carries an explicit `allowedTCPPorts = [ 8096 ]` instead.
3. **The VLAN application genuinely races, so it is asserted twice.** networkd
   applies `[BridgeVLAN]` only once it observes the link's master, and nspawn
   sets that master out of band from `container@jellyfin.service`. An idempotent
   `bridge vlan add … vid 90 pvid untagged` runs as `ExecStartPost` (prefixed
   `-`, so a backstop cannot become a new failure mode). With
   `DefaultPVID = "none"` a miss is fail-closed — no connectivity — not
   fail-open onto VLAN 50. `bridge vlan show dev vb-jellyfin` is still the
   check; do not trust silence from either mechanism.
4. **`wait-online` inside the container is capped at 20 s, and the number is
   load-bearing.** `services.jellyfin` is `after`/`wants`
   `network-online.target`, so wait-online gates it on a DHCP lease. But
   `container@jellyfin` is `Type=notify` with `TimeoutStartSec=1min`, and the
   container only notifies READY once its own boot completes — so at the stock
   120 s timeout a DHCP failure would stall the container past 60 s, the host
   would kill it, and `Restart=on-failure` would loop it forever with no
   reachable state to debug. At 20 s the container always finishes booting and
   leaves one obviously failed unit instead.

### The UDM-Pro half cost more than the Nix half

The repo change deployed cleanly on the first attempt. Getting clients to reach
it took five rounds, all of them off-repo, and every one of them was invisible
from ernst's side — the container answered `HTTP 200` over L2 the whole time.
Recorded in full because M4, M5 and M8 all add rules into this same zone.

**`Auto Allow Return Traffic` is the load-bearing checkbox, and it is
independent of Connection State.** The state list governs the *forward*
direction; the checkbox generates the reverse rule (it appears in the policy
list as a separate `… (Return)` row with State `Return Traffic`). Measured, with
tcpdump on both the trunk and the container veth:

| Forward Connection State | Auto Allow Return | Result |
|---|---|---|
| `Custom → New` | ✓ | SYN ok, SYN-ACK ok, **client's ACK + HTTP request dropped** |
| `Custom → New+Est+Related` | ✗ | SYN ok, **SYN-ACK dropped** |
| `All` | ✗ | SYN ok, **SYN-ACK dropped** |
| **`All`** | **✓** | **works** |

Both failure modes present as "the service is down". Neither logs anything. The
tell is a rule with a **non-zero hit count** and a connection that still hangs —
hits prove the forward rule matched, so the problem is the return leg.

**This also disproves M2's `Connection State: All` finding.** `All` matches
fine. M2 compared a broken IoT rule against a "working" LAN rule — but LAN and
Servers are **both in the `Internal` zone**, and `Internal → Internal` is
`Allow All`, so that LAN rule was never carrying its traffic and its settings
were never exercised. Moving Jellyfin into the `services` zone removed the
blanket allow and exposed the flaw for the first time. A rule that appears to
work because a broader rule is doing the work is worth more suspicion than a
rule that visibly fails.

**Diagnosing this from ernst, without touching the TV.** A veth on `br0` tagged
into any VLAN the trunk carries, with its own netns and a DHCP lease, reproduces
a real client's path exactly — the traffic leaves on the trunk and is routed by
the UDM-Pro like any other client's. That turned a five-round guessing game with
a television into a scripted test:

```bash
ip netns add p20
ip link add vb-p20 type veth peer name eth0p
ip link set eth0p netns p20
ip link set vb-p20 master br0 up
bridge vlan add dev vb-p20 vid 20 pvid untagged      # 20 = IoT; 1 = LAN
ip netns exec p20 ip link set eth0p address 02:00:00:20:00:99
ip netns exec p20 ip link set eth0p up
ip netns exec p20 dhcpcd -1 -q eth0p
ip netns exec p20 curl -m5 -o /dev/null -w '%{http_code}\n' http://10.0.90.10:8096/health
ip link del vb-p20; ip netns del p20                 # leaves nothing behind
```

Sniffing `enp13s0` while it runs is what localises the drop: a packet the
UDM-Pro forwards appears **twice** on the trunk (once outbound on the client
VLAN, once inbound on VLAN 90), a packet it drops appears **once**. That single
observation replaces all speculation about which matcher is wrong.

**Two smaller findings.**

- A UniFi **fixed IP must sit inside the DHCP pool** to be served. `10.0.90.3`
  was chosen from the `.2`–`.5` range the cutover runbook set aside — but that
  range is for addresses *hard-coded on the client*, not for reservations. The
  container was handed an ordinary pool lease instead, silently. Reserved
  `10.0.90.10` (in-pool) instead.
- Only **one** of the two ZBF rules the runbook predicted was actually needed.
  `Services → DNS-Container` had to be created; `Services → External` already
  passed. Probing beat predicting, at a cost of about thirty seconds.

**Ordering was never the problem, but check it anyway.** The IoT rule sits at ID
`10000`, ahead of `Block IoT to Trusted` at `10001`, which is correct and was
correct throughout. The policy list still displays alphabetically by name — read
the **ID** column.

### The units live with the service, not with the topology

`60-vb-jellyfin` sits in `machines/ernst/containers/jellyfin.nix`, beside the
container that creates the veth and the rest of that service's host-side
footprint (udev alias, tmpfiles, perms oneshot) — not in
`machines/ernst/networking.nix`. That file describes the topology (bridge, trunk,
VLAN map, the two attachment patterns) and should not accumulate one unit per
service as M3/M4/M5 land. The one thing kept central there is the MAC allocation
table, because a convention nobody can find in one place is not a convention.
**M4 and M5 should follow the same split.**

### Manual steps — lgo's, and required before the deploy

1. **DHCP reservation** on the Services network (VLAN 90) for MAC
   `02:00:00:90:00:02` → `10.0.90.10`. It **must be inside the DHCP pool**
   (`10.0.90.6`–`.254`); UniFi will accept an address from the `.2`–`.5` range
   the cutover runbook set aside but then silently hand out an ordinary pool
   lease instead. That range is for addresses hard-coded on the client, not for
   reservations.
2. **Two new permanent ZBF rules** the `Services` zone needs in order to function
   at all — it is isolated by default, which the cutover runbook flagged so their
   absence would read as expected rather than as a bug:
   `Services → DNS-Container` (Technitium at 10.0.5.3, or nothing resolves) and
   `Services → External` (metadata and plugin downloads). Both permanent, so
   neither goes in the ledger.
3. **Retarget L1 and L2** from `10.0.50.10:8096` to the container's new address,
   and from the `Servers` zone to `Services`. They stay interim; only the target
   changes. Rename the IoT policy so it stops naming the wrong zone. **TICK
   `Auto Allow Return Traffic`** — without it the SYN is forwarded and the
   SYN-ACK is dropped, which looks exactly like a dead service. Connection State
   `All` is fine and is *not* a substitute for the checkbox; see the
   [UDM-Pro section](#the-udm-pro-half-cost-more-than-the-nix-half).
4. **Repoint the TV bookmark** at the new address (L2a: it is an IP, not a name,
   so the bookmark is the only thing that knows).
5. **Technitium**: repoint the `jellyfin` record at the container address. It
   moves once more, to Traefik, in M5.

### Test plan

Run after `clan machines update ernst`:

```bash
# The veth landed on VLAN 90 — the one thing that races.
bridge vlan show dev vb-jellyfin          # expect: 90 PVID Egress Untagged
ip -br link show master br0               # expect: enp13s0 + vb-jellyfin

# br0's MAC is unchanged by the second port (it was already NET_ADDR_SET).
ip -br link show br0                      # expect: b2:8b:e1:f2:1e:7c

# The container has its own address and can resolve.
nixos-container status jellyfin
nixos-container run jellyfin -- ip -br addr show eth0
nixos-container run jellyfin -- resolvectl status eth0
nixos-container run jellyfin -- getent hosts jellyfin.skynet.lan

# The host no longer listens on 8096.
ss -lntp | grep 8096 || echo "not on the host — correct"

# VAAPI survived the netns change (it should be untouched, but prove it).
nixos-container run jellyfin -- vainfo --display drm \
  --device /dev/jellyfin-igpu-render      # expect the iGPU, NOT Navi 31
```

### Results, verified across a reboot on 2026-08-20

The reboot was the point. ernst has been genuinely impermanent only since
2026-08-18 (invariant #7), and M2b is the first of the three milestones the
invariant names as never having been tested against a real rollback. It was also
the **first boot at which `br0` was created from config** rather than by a live
deploy — the open question the MAC pin was written against.

| Check | Result |
|---|---|
| `br0` MAC at first boot-time creation | `b2:8b:e1:f2:1e:7c`, `addr_assign_type=3` — **pin reproduced** |
| `bridge vlan show dev vb-jellyfin` | `90 PVID Egress Untagged` — networkd won the race unaided |
| Container | `10.0.90.10`, MAC `02:00:00:90:00:02`, DNS `10.0.5.3` / `skynet.lan ~.`, resolves |
| `systemd-networkd-wait-online` (in container) | `success`, no failed units, system `running` |
| **`/srv/state/jellyfin` through the rollback** | **intact** — `jellyfin.db` 221 MB and live, `encoding.xml` still `vaapi` + `EnableHardwareEncoding` |
| `clanarchy-impermanence-check` | `success` / `0`; both `@blank` snapshots present |
| Host `:8096` | absent — L3 stays retired across boots |
| VAAPI | `radeonsi … raphael_mendocino` = iGPU, not Navi 31 |
| `zpool status` | `zroot` **ONLINE**, both mirror legs; `zdata` ONLINE |
| Clients (veth probes on VLAN 1 and VLAN 20) | `HTTP 200` from both |

Two notes for whoever reads this next:

- **The shutdown was slow and logged "resource or device busy", and POST took
  long enough to look like a failure to boot.** It was neither — ernst came up
  normally and asked for the zroot passphrase on the TV. Given
  `docs/incidents/ernst-slot12-drop-2026-08-11.md` and the fact that the **only
  ESP lives on `disk.system-a`**, a slow POST on this machine reads as a dead
  boot disk. It is worth knowing that it is usually just HBA enumeration.
- **`mirroredBoots` is still not done, and this reboot showed why it matters.**
  With one ESP, any slot-12 recurrence turns a healthy mirrored pool into an
  unbootable machine. `machines/ernst/disko.nix` already carries the commented
  layout and a four-step procedure in its header.

---

## M3 — `feat/ernst-vpn-microvm` (done — deployed 2026-08-20)

**Goal.** Put qBittorrent behind a VPN in a microvm with a real killswitch —
default-deny egress inside the guest, so a VPN failure means no traffic rather
than leaked traffic. The guest gets its own kernel because it is the one workload
on ernst that talks to the open internet on its own behalf. Downloads land on
`/srv/media` at a path and ownership that let the host-side *arr hardlink them
later.

**Depends on.** M2. **Risk.** Medium-high — new flake input, new isolation tier,
and the uid/gid decision here is the single most common integration failure in
this kind of stack.

**Deployed and verified across a reboot.** The repo half needed three rounds
after the first deploy; every one of them is written up below, because two were
in code this milestone did not write and one is a trap M4 and M5 will hit in the
same form. Operator procedure:
[the deploy runbook](runbooks/ernst-vpn-microvm-deploy.md).

### What shipped

`microvm.nix` as a flake input (`nixpkgs.follows = "nixpkgs"`, so the guest is
26.05 like its host), its `nixosModules.host` on ernst, and one
fully-declarative guest, `wg-qbittorrent`:

- **Tap on br0, Services VLAN 90**, MAC `02:00:00:90:00:03`, `10.0.90.11` by
  DHCP reservation — the M2b pattern, one tier up.
- **wg-quick tunnel to IVPN** whose entire config is a single clan-vars file.
  Nothing about the provider is in the repo, not even the endpoint.
- **A killswitch that is nftables, not routing.** Output `policy drop`, three
  exceptions on the LAN interface: the tunnel to the endpoint, DHCPv4, and
  replies to management-network connections.
- **virtiofs shares at identical paths**: `/srv/media/torrents` read-write,
  `/srv/state/qbittorrent` → `/var/lib/qBittorrent`, a read-only secrets
  staging directory, and the host's `/nix/store`.
- **A stateless guest**: tmpfs root, no volume, nothing persisted.

### What actually broke, and what it teaches

**1 — wg-quick wins any routing-rule priority race, by construction.** This was
the one that made the milestone look dead: SSH and the WebUI hung, the SYN
reached the guest, and nothing came back.

The carve-out that keeps replies to management clients out of the tunnel was a
`[RoutingPolicyRule]` per management network at priority 100. wg-quick runs
*after* networkd and adds its two rules **without an explicit priority**; the
kernel's `fib_default_rule_pref()` returns "one less than the second rule in the
list", so it landed at 99 and 98 — ahead of ours, **because** ours were at 100.
Measured on the running guest:

```
98:  from all lookup main suppress_prefixlength 0     ← wg-quick
99:  not from all fwmark 0xca6c lookup 51820          ← wg-quick
100: from all to 10.0.10.0/24 lookup main             ← never consulted
```

Lowering the number cannot win; wg-quick would take one lower still. **Anything
that competes on rule priority loses to a program that picks its priority at run
time relative to what it finds.**

The fix competes on route specificity instead. `suppress_prefixlength 0` rejects
only prefix length 0 — the default route — so an explicit `/24` in `main` is
found by *wg-quick's own first rule* whatever the priorities settle at. The
management networks are plain routes with `Gateway=_dhcp4`. Removing our rules
also put wg-quick back at its documented 32764/32765, which is the confirmation:
it had been dragged down by ours.

**2 — a two-year-old contradiction in `containers/jellyfin.nix`, surfaced
because M3 is the first thing to WRITE to the media tree.** The hardlink test
failed with `EACCES`, and the cause was that
`/srv/media/library/movies` was `root:root 0755`, not the `root:media 2770` that
file intends.

It declared those four directories **twice, with different values**: `0755 root
root` in `systemd.tmpfiles.rules`, and `root:media 2770` in
`jellyfin-library-perms.service`. tmpfiles **enforces mode and ownership on
every run**, not only at creation, and runs on every deploy; the oneshot is
`RemainAfterExit` and runs once per boot. So the oneshot won at boot and
tmpfiles took it back at the next `clan machines update`.

Invisible for as long as Jellyfin was the only consumer — it never writes, 0755
grants the traversal it needs, and the files themselves are `root:media 0640`.
It would have surfaced in M4 as the silent copy-instead-of-hardlink that
milestone exists to catch. **The tmpfiles rules now carry the intended values**
and the oneshot is a redundant backstop that agrees with them. The general
lesson: where tmpfiles and a service both describe a path, tmpfiles wins on
every deploy, so tmpfiles is where the truth belongs.

**3 — `UMask=0002` is the milestone, and it is now measured rather than
argued.** virtiofsd runs without id translation, so guest uid 3001 *is* host uid
3001; the download directories are setgid `root:media`. But at systemd's default
umask the files land `0644` — group-**read** — and `fs.protected_hardlinks`
refuses `link()` on a file you do not own unless you have read **and write** on
it. Verified on ernst:

```
file created by qbittorrent (uid 3001, umask 0002) → 0664
  link as uid 3002, group media   → rc=0, one inode, links=2
  same file chmod 0644, same link → EPERM, "Operation not permitted"
```

The negative control is the point: without it the test cannot distinguish a
working chain from root bypassing the check, which is exactly what an earlier
revision of this plan did — it created the file as root and linked it as root,
and would have passed whatever `UMask` was set to.

**4 — the endpoint must be an IP literal, and validating one input is not
enough.** wg-quick resolves a hostname endpoint using the guest's resolver,
which is in-tunnel, which does not exist until the handshake that needs the
endpoint. The generator rejects a non-IPv4 endpoint — and on the first real run
it did exactly that, on `95.211.95.9.2049`, a dot typed instead of a colon.

But clan collects **all** prompts and only then runs the script, so exiting on
the first bad value charged six correct answers for one typo, and the message
blamed a hostname because that was the only failure the author had imagined.
The generator now validates every input, accumulates the errors, and reports
them together; the checks cover the address (rejecting a dual-stack line, since
the guest disables IPv6 and wg-quick would abort under `set -e`), the DNS, both
keys (43 base64 chars + `=`, catching a truncated paste) and the MTU.

**5 — IVPN specifics that shaped the design.** The in-tunnel resolvers live at
`10.0.254.x` — AntiTracker, with `.2`/`.3` the classic pair and a wider range
beyond it; the one in use here is `10.0.254.4` (Basic filtering). **That is
inside `10.0.0.0/16`**, which is why the management carve-out is per-subnet and
never a supernet: a `/16` version, which is what the first draft had, would have
routed every DNS query at `eth0` where the killswitch correctly drops it —
tunnel up, `wg show` perfect, not one name resolving. IVPN also specifies
**MTU 1412**, lower than the 1420 wg-quick derives, and too-high does not fail
cleanly: the handshake completes and transfers stall on the first full-size
packet. Port forwarding was removed service-wide in September 2023, so the
guest's inbound rule for the torrent port is inert by design.

**6 — the L2 probe needs a different success criterion than M2b's.** Jellyfin
accepted 8096 from anywhere inside its netns; this guest firewalls by source
address, so a probe on `10.0.90.5` is *correctly* dropped for ICMP, the WebUI
and SSH. The check is the ARP entry, which resolves anyway because `arp` is a
netfilter family `table inet` does not touch:

```
10.0.90.11 dev eth0p lladdr 02:00:00:90:00:03 REACHABLE
```

That single line proves the reservation took, the guest is alive at L2, and it
is bound to the right MAC — while everything else failing proves the input chain
works. ernst also has no `dhcpcd` (`roles/server.nix` zeroes
`environment.defaultPackages`), so the probe takes a static address from the
`.2`–`.5` range the cutover runbook set aside.

**7 — the UDM-Pro policy editor has two Port sections**, one inside the Source
Zone card and one inside the Destination Zone card, and the source one is the
one you see first. A service port entered there matches only traffic *from*
8080/22, i.e. never. Symptom: a hanging connection with a **zero hit count** —
M2b's "zero hits means the matcher is wrong, non-zero with a hang means the
return leg" split, in its first real use. The filled-in field table is in the
runbook; M4, M5, M8 and M9 all add rules to this same zone.

**8 — two upstream facts.** microvm.nix warns that qemu hangs when a guest has
*exactly* 2 GB (microvm-nix/microvm.nix#171), so the guest has 4 GB. And the
qemu runner implements no notify socket, so `microvm@` is `Type=simple`: a guest
that fails to finish booting leaves a running service and a readable console log
in ernst's journal rather than being killed at `TimeoutSec` and restart-looped
out of reach.

### Decisions that departed from this milestone's own prompt

- **`/srv/media/torrents`, not `/srv/media/downloads`.** The prompt named
  `downloads`; the deployed tree does not have one.
  `containers/jellyfin.nix` already creates `torrents/{movies,tv}` beside
  `library/{movies,tvshows}`, and those are the directories M4 imports *from*.
  Only `torrents/incomplete` and `torrents/complete` were added, both inside the
  one hardlink domain.
- **The guest runs sshd.** The prompt asked for a minimal guest, and this is the
  one addition. M3's own test plan requires running commands *inside* the guest,
  and the qemu runner wires the serial console to the service's stdout — good
  for reading a boot, useless for typing into. Key-only, root-only, management
  networks only, host key from the vars generator (the guest's root is a tmpfs,
  so a self-generated key would be new every boot). It earned its place during
  the debugging above several times over.
- **The WebUI password is a clan var too.** Forced by the configuration model:
  qBittorrent's config is rendered declaratively on every start, so a
  UI-set password would be discarded at the next deploy. The generator emits
  qBittorrent's PBKDF2 format directly, so only the hash reaches the guest.

**No interim ledger rows.** The WebUI's management-only exposure is a
*permanent* bypass, named as such in architecture invariant #4, and is listed in
the ledger as a `—` row so nobody later mistakes it for something to retire.

### Results, verified across a reboot on 2026-08-20

The reboot was the point: invariant #7 names M3 as one of three milestones
carrying state that had never met a real rollback, and this was the first boot
at which the tap and the microvm state directory were built from config rather
than by a live deploy.

| Check | Result |
|---|---|
| Exit IP, in-guest vs miralda | `95.211.172.88` (IVPN) vs `78.94.91.74` (home WAN) — different |
| Tunnel | handshake re-established after boot with no intervention |
| DNS | resolves in-tunnel via `10.0.254.4`; nothing reaches a LAN resolver |
| **Killswitch, wg0 stopped** | **guest emitted ZERO packets on `tap-vpn`**; `curl` rc=6 (no resolution), `getent` rc=2, raw-IP `curl` rc=28 (timeout — dropped, not rejected) |
| **Hardlink chain** | **one inode, `links=2`**, linked by uid 3002 in group media; the 0644 control refused `EPERM` |
| `/srv/state/qbittorrent` through the rollback | intact — `qBittorrent.conf`, `qBittorrent-data.conf`, `categories.json` |
| `/var/lib/microvms/wg-qbittorrent` | rebuilt from the store at boot, as designed — deliberately not persisted |
| `bridge vlan show dev tap-vpn` | `90 PVID Egress Untagged` — networkd won unaided, no backstop needed |
| `br0` MAC | `b2:8b:e1:f2:1e:7c` — M2b's pin reproduced |
| Media directory modes after a real boot | `2770 root:media` on all six |
| `clanarchy-impermanence-check` | `success` / `0`; both `@blank` snapshots present |
| Host `:8080` | absent |
| Guest failed units | none |
| `zpool status -x` | all pools healthy |

### Left for later

- **`warning: user activation for go failed`** on every ernst deploy, with
  `activation returned 4 — retrying` and success on the retry. The couch user's
  session dbus; it predates M3 and nothing here touches it. A
  [backlog entry](#floating-backlog), not a milestone.
- **The `sshd-keygen` refusal** in the guest's boot log is fixed
  (`services.sshd-keygen.enable = false` — there are no host keys to generate,
  by design), but it is worth knowing that an empty `hostKeys` list produces a
  unit systemd refuses noisily.

---

## M4 — `feat/ernst-arr-stack`

**Goal.** Prowlarr, Sonarr and Radarr in an nspawn container, writing into the
same `/srv/media` hardlink domain qBittorrent writes to, with state on
`/srv/state`. The value of this milestone is the *verified* hardlink chain — a
stack that silently copies instead of linking will fill a 6-wide raidz1 twice
over.

**Depends on.** M3 (for the download client and the uid/gid decision) and
Jellyfin. **Risk.** Medium.

**Status: done. Deployed, hardlink chain proven on a real import, and the whole
thing survived an unplanned power cut on 2026-08-21** — which is a harsher
version of the reboot invariant #7 asked for, and it arrived without being
scheduled.

### Results after the outage

M4 was the last of the three milestones the invariant names as carrying state
that had never met a real rollback. It has now met one, ungracefully.

| Check | Result |
|---|---|
| `zpool status -x` | all pools healthy; `zroot` + `zdata` ONLINE after an unclean loss |
| `clanarchy-impermanence-check` | `success` / `0`; both `@blank` snapshots present |
| Failed units, host and container | none |
| `br0` MAC | `b2:8b:e1:f2:1e:7c` — the pin reproduced again |
| VLAN 90 on `vb-jellyfin`, `vb-arr`, `tap-vpn` | all landed unaided on a cold boot |
| `microvm@wg-qbittorrent` | active |
| prowlarr / sonarr / radarr / flaresolverr | all active |
| **`/srv/state/*` through the rollback** | **intact** — sonarr 171 M, radarr 3.9 G, prowlarr 4.4 M, jellyfin 34 G, qbittorrent 5.2 M |
| **M4 hardlinks** | **still `links=2` on the same inodes** |

One of the surviving hardlinks is an `EZTVx.to` release — the indexer
FlareSolverr was added for, working end to end.

### The proof

Sonarr imported an 8.2 GB episode from qBittorrent's download tree into the
library. `stat` on both paths, from the host:

```
ino=66816  links=2  -rw-rw-r--  3001:media  8227310727
  /srv/media/library/tvshows/House of the Dragon/Season 3/…DV HDR H.265.mkv
  /srv/media/torrents/complete/tv/…DDP5.1 Atmos DV HDR. H.265.mkv
```

One inode, two names, 8.2 GB counted once rather than twice. Owned `3001:media`
at mode `0664` — qBittorrent's file, linked by Sonarr running as uid 3002
through group `media`, which is exactly the chain M3's `UMask=0002` was set up
for and the failure this milestone existed to catch.

Two details worth keeping:

- **It worked despite the qBittorrent categories having no save path.** The
  file landed in `torrents/complete/tv` rather than the `torrents/tv` that
  `containers/jellyfin.nix` declares, because an empty category save path falls
  back to `Session\DefaultSavePath`. Both are plain subdirectories of the one
  `/srv/media` dataset, so `link()` succeeded anyway. That is invariant #2
  earning its keep: the hardlink domain is the *dataset*, not the directory
  layout, so getting the layout wrong costs tidiness and not disk.
- **The synthetic proof ran first and was worth it.** Before any UI existed, a
  file created as uid 3001 mode 0664 was linked by uid 3002 (`links=2`, same
  inode) and the same file at 0644 was refused with `EPERM`. That separated
  "the plumbing works" from "the *arr chose to hardlink", so when the real
  import arrived there was only one thing left to doubt.

### What shipped

One nspawn container `arr` (`machines/ernst/containers/arr.nix`) running all
three services, on its own L2 identity:

- **veth `vb-arr` on `br0`, Services VLAN 90**, MAC `02:00:00:90:00:05`,
  `10.0.90.13` by DHCP reservation — the M2b pattern, copied from the working
  version rather than from the sketch.
- **`/srv/media` bound read-write at the identical path**, whole-dataset and as
  one mount, so `st_dev` matches across `torrents/` and `library/` and no
  *arr Remote Path Mapping is needed.
- **State on zdata** at `/srv/state/{sonarr,radarr,prowlarr}`, bound to each
  package's upstream default path so no `dataDir` override is required.
- **uid 3002 sonarr / 3003 radarr** with `media` (gid 3000) as their **primary**
  group, and **uid 3004 prowlarr** with no media access at all.

### Three decisions that departed from this milestone's own prompt

**1 — Networking is the veth, not host networking, and the prompt is stale
rather than wrong.** The prompt says "v1: HOST networking, exactly like
Jellyfin's v1" with a migration note for later; it was written before M2b
landed. Since then `machines/ernst/networking.nix`'s worked example B is
titled "systemd-nspawn container (M4 arr, M5 Traefik)" — the topology file
already expected this. Following the prompt would have re-opened host ports on
ernst two PRs after [#82](https://github.com/lutzgo/clanarchy/pull/82) deleted
the last one, and booked a migration PR to undo it.

**2 — The ZBF rule the prompt listed as a manual step does not exist, and must
not be created.** The prompt anticipated "a ZBF rule allowing the arr container
to reach the M3 guest's qBittorrent API … since the download client lives on a
different L2 identity". It does — and both identities are VLAN-90 ports on the
*same bridge*, so `br0` switches those frames locally and the UDM-Pro never sees
them. There is nothing for a firewall policy to match.

The consequence is the part worth carrying forward: M3's header claimed the
WebUI's exposure was "enforced twice, guest-side nftables and a ZBF rule on the
UDM-Pro". For this third source that is **not true** — the guest's nftables set
is the only enforcement. So the set was split rather than widened:
`mgmt_nets` still governs SSH and ping, and a new superset `api_clients` governs
the WebUI port alone. The arr gets the API and nothing else.

**3 — `mgmtNets` could not simply grow an entry, because it feeds routes as
well as rules.** M3 built one list with three consumers on purpose. Two of them
(the nftables input accept, the output established-reply accept) *do* want the
arr's address. The third — the routing carve-out that keeps replies off the
tunnel — must **not** have it: `10.0.90.0/24` is directly connected on the
guest's `eth0`, so `main` already holds a /24 for it, and a /24 survives
wg-quick's `suppress_prefixlength 0` untouched. Adding `10.0.90.13/32 via
<gateway>` on top would hairpin traffic through the UDM-Pro to reach a neighbour
two ports away on the same bridge. Hence `mgmtNets` (routed) plus `arrClient`
(not routed), joined into `allowedClients` for the nftables set only.

### Prowlarr's `DynamicUser`, and what turning it off costs

Upstream's prowlarr unit is `DynamicUser = true` with `StateDirectory`, i.e.
state under `/var/lib/private/prowlarr` owned by a uid systemd allocates at run
time. That is the shape this repo already paid for once on Ollama. It is
switched to a static uid 3004 here.

The trap in doing so: `DynamicUser = true` **implies** `NoNewPrivileges`,
`PrivateTmp`, `ProtectSystem=strict`, `ProtectHome=read-only`, `RemoveIPC` and
`RestrictSUIDSGID`, and upstream sets none of them explicitly — so a naive
`DynamicUser = false` silently makes Prowlarr the least confined service on the
box. All six are restated, plus the rest of the sonarr/radarr set that upstream
never applied to prowlarr at all.

Measured with `systemd-analyze security --offline=true` against the container's
own generated units, which is how it can be checked *before* a deploy:

| Service | Upstream directives | This PR |
|---|---|---|
| prowlarr | **8.2 EXPOSED** | **1.3 OK** |
| sonarr | 1.5 OK | 1.3 OK |
| radarr | 1.5 OK | 1.3 OK |

Offline analysis does credit `DynamicUser=`'s implications — `ProtectSystem`,
`PrivateTmp`, `NoNewPrivileges`, `RemoveIPC` and `RestrictSUIDSGID` all score ✓
in the baseline — so 8.2 is not an artefact of scoring a switched-off
`DynamicUser`. It is everything `DynamicUser` never implied.

### Two things that could not be tested without deploying

Both are called out in the file so a first-deploy failure is recognised rather
than diagnosed from scratch.

- **`ProtectSystem = "strict"` on sonarr/radarr.** Upstream sets nothing;
  `ReadWritePaths` is enumerated as `/srv/media` plus the service's own state
  directory. If a service fails to start with "Read-only file system", add the
  path it names, or drop to `ProtectSystem = "full"`.
- **Authentication is deliberately NOT declared.** Setting
  `settings.auth.method` via the env-var passthrough looks right and is a
  lockout: on a first start with no user in the database, an already-set
  `AuthenticationMethod` skips the "Create Admin User" wizard and leaves a login
  form no account can satisfy. The wizard is the intended bootstrap. Pinning
  auth declaratively is safe only *after* an account exists.

### `UMask = 0002` here means less than it did in M3

M3's header calls `UMask=0002` load-bearing, and for qBittorrent it is: the
*source* file's mode is what `fs.protected_hardlinks` checks. On the arr side it
is **not** what makes the import link — a hardlink shares qBittorrent's inode
and therefore its 0664 mode regardless. What 0002 changes here is everything the
*arr creates fresh: series and season directories, `.nfo` files, artwork, and
any import that copies rather than links. At 0022 those land writable by exactly
one uid, cancelling the point of the setgid bit on those directories.

### Two additions that grew the milestone, on request

Both are outside M4's prompt. Recorded here so the prompt and the tree do not
silently disagree.

**FlareSolverr**, because several Prowlarr indexers fail with *"blocked by
CloudFlare Protection"*. It is in the 26.05 pin with a NixOS module, so it
stays in the nspawn tier. Where it runs contradicts architecture invariant #1
and the contradiction was measured rather than argued — same URL, 2026-08-21:

| Path | `https://eztvx.to/` |
|---|---|
| ernst's home WAN (arr container) | `200`, real site + `cdn-cgi/challenge-platform` → **solvable** |
| IVPN exit `95.211.172.88` (microvm) | `451 Unavailable For Legal Reasons` → **not solvable** |

There is nothing to solve in a 451; the exit is Leaseweb NL and eztvx blocks
the Netherlands. The microvm placement would have been the more correct
architecture minus the capability it exists to provide. What makes the
container acceptable is that the boundary protecting the library is the **uid**,
not the container: FlareSolverr keeps upstream's `DynamicUser` and is not in
group `media`, so `/srv/media`'s `2770 root:media` directories are closed to it.
**Revisit if the IVPN exit ever leaves the Netherlands.**

**Recyclarr**, which M4's prompt calls out as explicitly out of scope. Two bugs
in the first version, both caught by `recyclarr sync --preview` against the live
instances and neither catchable by evaluation:

1. **The template ids did not exist.** `include: - template: …` was written from
   memory. In v8 the official config-templates repo ships *starter configs* for
   `recyclarr config create`, not include-able fragments. The template body is
   transcribed inline instead — better here anyway, since every profile and
   custom-format group becomes an explicit reviewable value rather than a remote
   id whose contents move under a `git fetch`.
2. **Instance names are a GLOBAL namespace, not per-service.** With `radarr.main`
   and `sonarr.main`, recyclarr logs `Duplicate instances: ["main"]` at DEBUG,
   syncs nothing, prints nothing to the console and **exits 0** — a green timer,
   forever, doing nothing. They are `movies` and `series` now.

The API keys are *not* a clan var, deliberately. Sonarr and Radarr generate them
on first run into their own `config.xml`; a prompted var would be a second copy
with no link to the first, and would silently go stale the day a key is rotated
in the UI. A hardened oneshot stages them out of `config.xml` into a root-only
tmpfs and the module's `_secret` turns them into `LoadCredential=` entries — one
source of truth, nothing in the store, nothing in the repo, and no generator,
because there is no secret here that ernst did not already hold.

### M4: what still has to happen on ernst

These are lgo's, and the first three gate the test plan.

1. **DHCP reservation** on the Services network (VLAN 90): MAC
   `02:00:00:90:00:05` → `10.0.90.13`. **Inside the pool** (`10.0.90.6`–`.254`)
   — UniFi accepts a `.2`–`.5` address and then silently hands out an ordinary
   lease instead, which cost M2b a round.
2. **UDM-Pro ZBF rule** — ledger row **L4**. `LAN` + `Servers` →
   `10.0.90.13` tcp `9696,8989,7878`. Port in the **Destination** card (M3 lost
   a round to the Source card's identical-looking Port section), and **tick
   `Auto Allow Return Traffic`** (M2b lost three rounds to that one).
3. **Technitium** records for `prowlarr` / `sonarr` / `radarr` → `10.0.90.13`.
   They move to Traefik in M5.
4. Nothing for arr → qBittorrent. Same VLAN, same bridge — see departure 2.
5. **In-UI bootstrap**, which is state the repo deliberately does not fake. The
   reproducible checklist is in the PR body: create each admin account through
   the first-run wizard; root folders `/srv/media/library/tvshows` (Sonarr) and
   `/srv/media/library/movies` (Radarr); qBittorrent as the download client at
   `10.0.90.11:8080` with **"Use hardlinks instead of copy" on**; Prowlarr
   applications pointed at `127.0.0.1:8989` / `127.0.0.1:7878`.

### The prompt this was built from

Kept verbatim, including the parts departed from above, because the departures
are only legible against it.

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

## M5 — `feat/ernst-traefik` (done — deployed 2026-08-23, proven 2026-08-24)

**Outcome.** Wildcard certificate issued by Let's Encrypt over DNS-01
(`Validations succeeded` 2026-08-23 18:22:45, one bundled SAN cert for
`goclan.org, *.goclan.org`). Jellyfin reachable by name over TLS from the LAN
and from IoT; `sonarr.goclan.org` returns **403** from IoT — the `mgmt-only`
ipAllowList answering, not a timeout, which is the distinction that proves the
middleware rather than the firewall is doing it. Backends reachable from
Traefik (`10.0.90.10:8096` → 200, `10.0.90.13:8989` → 302 login redirect) and
from nowhere else. **L1 and L2 deleted.** Transcoding through the proxy
verified on a TV client — the check that matters most, because chunked
transfer and long-lived connections are where reverse proxies break first and
nothing earlier in the test plan touches them.

**Five rounds, and four of the five were the UDM-Pro** — the DHCP reservation,
the destination zone, the source list, with the DNS-01 negative cache the only
one that was not. That is almost exactly M2b's ratio. M6 and M8 add rules to
this same zone: read the four bullets below before opening the policy editor.

**Built in [#86](https://github.com/lutzgo/clanarchy/pull/86).** What the code
does, and where it answered a question the prompt left open:

- **Domain and provider, the two things the prompt said to ask first:**
  `goclan.org`, rented on Cloudflare — confirmed by lgo, and independently by
  its NS records (`jamie`/`justin.ns.cloudflare.com`). One wildcard
  `*.goclan.org` plus the apex, requested **once at the `websecure`
  entryPoint** rather than per router, so there is one certificate and one
  renewal rather than four. Credential is a **scoped API token**
  (Zone:DNS:Edit + Zone:Zone:Read) via clan var `traefik-acme`, not the
  account-wide Global API Key; the generator rejects a Global Key by shape,
  because that mistake authenticates fine and is therefore invisible later.
- **lego's propagation check is pinned to public resolvers** (`1.1.1.1` /
  `9.9.9.9`) rather than inheriting the container's. As the zones were actually
  laid out, inheriting would have worked — Technitium hosts one small zone per
  *service* name and is not authoritative for `goclan.org` itself, so it would
  recurse for `_acme-challenge`. The pin makes that independent of the zone
  layout: hosting the whole `goclan.org` zone internally would make Technitium
  authoritative and it would answer NXDOMAIN forever.
- **The trap that actually fired was different, and it is worth knowing.**
  Measured on ernst 2026-08-23: issuance failed with
  `recursive nameservers: NS 9.9.9.9:53 returned NXDOMAIN for
  _acme-challenge.goclan.org` while the TXT was demonstrably live at
  `jamie.ns.cloudflare.com` the whole time. lego queried ~1 s after writing the
  record, Cloudflare's edge had not published, Cloudflare answers a nonexistent
  name with **NXDOMAIN rather than NODATA**, and `goclan.org`'s SOA minimum is
  **1800** — so the resolver cached that negative answer for thirty minutes and
  every retry inside that window hit lego's own poison. Fixed with
  `propagation.delayBeforeChecks = "60s"`, so the first query happens after the
  record exists and the negative entry is never created. **Not** fixed with
  `propagation.disableChecks`, which would hand the record to Let's Encrypt
  unverified and burn failed-validation rate limit with no local signal.
- **The UDM-Pro rule cost two rounds, both in the same dialog.** First, the
  **Destination Zone was `Internal`**, because that is what the dropdown offers
  first and `10.0.90.12` looks like an ordinary internal address. It is not —
  VLAN 90 is the **`Services`** zone, so the rule never matched and the
  `Internal → Services: Block All` zone default swallowed the traffic. The
  symptom is a browser timeout with a policy that looks correct in the list.
  The tell is the two rules that already worked: `Allow Arr…` and
  `Allow qBittorrent…` both name `Services` as the destination zone.
  Second, the source list was `LAN + IoT`, which locks out **ernst itself**:
  `br0` is a member of VLAN 50 only, so the host cannot speak VLAN 90 directly
  and its packets to `.12` hairpin out through `10.0.50.1` and back — subject
  to the same zone pair as any client. `curl` from ernst then times out after
  136 s while the identical request from a LAN browser succeeds. **`Servers`
  is in the source list** so that the firewall and Traefik's `mgmt-only`
  ipAllowList (which already trusts `10.0.50.0/24`) agree about what
  management access means. The qBittorrent row records the same lesson for
  `ssh`.
- **`.12` is not optional, and the reservation is the thing that grants it.**
  First deploy came up on `10.0.90.189` — an ordinary pool lease, because the
  UDM-Pro reservation did not exist yet. The pinned MAC was correct (the
  container's link-local `fe80::ff:fe90:4` derives from
  `02:00:00:90:00:04`), so this is purely a gateway-side omission — and it is
  not cosmetic: the backend allow-rules hard-code `10.0.90.12`, so Traefik on
  any other address gets dropped by every backend and every route returns 502.
- **Backend bypass: mechanism (a), and (b) was not merely worse — it cannot
  work.** Jellyfin (`.10`), qBittorrent (`.11`), Traefik (`.12`) and the arr
  (`.13`) are all ports on `br0`; traffic between them is switched at layer 2
  and never reaches the UDM-Pro. `containers/arr.nix` already depends on that
  property in the other direction. The adjacency this closes is the one that
  matters: the download client — the one workload with its own kernel
  *because* it faces the internet — sits one hop from the *arr APIs.
  Implemented as `extraCommands`, not `extraInputRules`: the latter is
  declared unconditionally but consumed only under `networking.nftables`,
  so it would have produced no rule and no warning.
- **Three hostnames, not three path prefixes**, for the arr. A path prefix
  needs a matching `UrlBase` in each app's own settings, and a missing one
  presents as a blank page with 404s on every asset. Subdomains need nothing
  kept in step.
- **L4 was never created and must not be now** — see the ledger. The prompt
  assumed an interim arr rule existed to be replaced; M4 shipped without one
  and M5 landed first, so those ports go straight from br0-only to proxied.

**Two things that bite on deploy day**, both in the PR body: direct access to
the backends stops the moment this deploys (the TV must move to
`jellyfin.goclan.org` in the same window), and a UDM-Pro DNS-interception rule
would silently break the ACME check by redirecting `1.1.1.1:53`.

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
on the Services VLAN (90). NOT a tap — a tap is the microvm primitive; an
nspawn container gets a veth pair whose host side is named vb-traefik.
COPY M2b's WORKING VERSION, not the sketch: machines/ernst/containers/
jellyfin.nix has the veth unit, the KeepMaster/BridgeVLAN wiring, the
ExecStartPost that settles the VLAN race, and the wait-online cap that keeps
a DHCP failure from restart-looping the container. Put traefik's unit in
traefik.nix beside the container, following the same split M2b used (the
topology file stays topology; only the MAC allocation table is central).
MAC 02:00:00:90:00:04 is already reserved for it there. That veth's address
is the identity every consumer VLAN gets its ONE permanent ZBF rule for —
the whole point of the milestone.

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

## M6 — `feat/monitoring` (built 2026-08-24; not yet deployed)

**Built in [#87](https://github.com/lutzgo/clanarchy/pull/87).** Evaluated on
all four machines and `nix flake check`; the alert rules are validated with
`promtool check rules` (6 rules, SUCCESS). **Nothing is deployed** — Claude does
not deploy, and the reboot half of invariant #7 has not been exercised for this
milestone's state.

### The problem the prompt did not anticipate: the container cannot reach what it must scrape

Every container on ernst since M2b lives on VLAN 90 and talks to things that
are also on VLAN 90. This one is the first that must reach things that are not,
and **both** of its scrape sources are off that VLAN:

- **ernst's own exporters.** The host holds `10.0.50.10` and `br0` is a member
  of VLAN 50 only, so a packet from `.14` to the host leaves the bridge, is
  routed by the UDM-Pro, and is subject to the `Services → Servers` zone pair.
  M5 lost a round to exactly this shape — `curl` from ernst to `10.0.90.12`
  timed out after 136 s while a LAN browser succeeded.
- **The three laptops.** They are not on any VLAN ernst carries. They are on
  ZeroTier, whose rfc4193 addresses live on the *host's* `zt*` interface inside
  the *host's* netns. From a container with its own netns there is no path at
  all — not a filtered one, an absent one.

Four ways out were considered. Host networking (`privateNetwork = false`) makes
both problems vanish and was rejected: it re-opens three host ports four PRs
after [#82](https://github.com/lutzgo/clanarchy/pull/82) deleted the last one
(ledger row L3), and it puts Grafana on VLAN 50 where Traefik needs a ZBF rule
to reach it. A second veth tagged into VLAN 50 solves the host half and not the
ZeroTier half. Giving the container its own ZeroTier identity means a second
node, a second clan var, and a mesh member nobody deploys to.

**What shipped is a second interface, `mon0`** — a `/128`-to-`/128` veth to the
host on a locally-chosen ULA (`fdca:fe90::1` host / `::2` container) that never
leaves the machine. `containers.<n>.extraVeths` creates it; the container gets
one host route plus **one `/128` route per scrape target**, and the host
forwards and SNATs them onto `zt+` via `networking.nat`.

Three things about that are worth carrying forward:

1. **The routes are per-target, not the ZeroTier `/88`.** They come from the
   same clan vars the targets do, so it costs nothing to maintain and the
   container can reach exactly the machines it scrapes and no other node on the
   mesh. Deriving the `/88` from an address by string-slicing was the first
   attempt and was dropped: ZeroTier's rfc4193 layout is `fd` + 8-byte network
   id + `9993` + 5-byte node id, so the prefix boundary falls **mid-group**, and
   a network id whose last byte is `0x00` would render with leading zeros
   stripped and slice wrong. A plausible-looking derivation that fails on one
   value in 256 is worse than no derivation.
2. **The SNAT is not just plumbing, it is the ACL.** Scrapes arrive at a laptop
   from ernst's own ZeroTier address — the one source the client role's firewall
   rule permits. One address to allow, fleet-wide, and it is the same address
   `clan machines update` already comes from.
3. **`net.ipv6.conf.all.forwarding = 1` is a no-op on ernst and would not be
   elsewhere.** The kernel stops accepting router advertisements by default once
   forwarding is on. ernst already sets `IPv6AcceptRA = false` on `br0` and the
   trunk and holds no RA-derived address, so nothing changes. Do not copy the
   `networking.nat` block to a machine that gets its IPv6 from RA.

### Targets are generated, and this is what makes it work

`roles.server.perInstance` reads `roles.client.machines` and, per machine, pulls
the address out of `zerotier-ip-<machine>-zerotier` with `clanLib.getPublicValue`
— a **shared, non-secret** var, so it is a plain file in the repo that any
machine's evaluation can read. Adding a machine to `roles.client` in `clan.nix`
is the only step needed to monitor it.

Two details that were not obvious:

- **`default = null`, not `getPublicValue`'s default throw.** A machine added to
  the role before `clan vars generate` has run for it would otherwise fail
  *every* machine's evaluation — including CI's — with an error naming a
  generator nobody has heard of. Unresolvable machines are dropped and reported
  in `warnings` instead.
- **Role-level settings are deprecated in `perInstance`.** The first version read
  `roles.server.settings.zerotierInstance` from the client role and clan-core
  warned at eval that the attribute goes away next release. The per-machine path
  (`roles.server.machines.<n>.settings`) is both supported and more correct.

### Alerting: (b), keep both, with the overlap made empty

The prompt required a choice and forbade the outcome where two systems alert on
one pool event. **ZED keeps pool and vdev state**: it is edge-triggered, it is
fleet-wide via `commonBase`, and — the argument that decides it — it keeps
working when the monitoring container is down. Prometheus cannot be the thing
that alerts on ernst's pool while the thing that would alert lives on ernst's
pool.

**Prometheus takes everything ZED cannot see** and carries **no
`zfs_pool_health` alert rule at all** — the metric is scraped and shown on the
dashboard, which is a panel and not a notification.

**`ZedNotRunning` is the interlock**, and it is what makes this a design rather
than an omission: the one thing ZED cannot report is its own death. It is a
separate rule from `SystemdUnitFailed` on purpose — a unit that is *stopped*
rather than *failed* does not trip that one.

Both paths end at the same ntfy topic, the existing `zfs-ntfy` clan var. That
var stores one value (the full topic URL, because that is all `curl` needs);
`alertmanager-ntfy` wants the two halves separately, so the host-side staging
oneshot splits it. A second var would have been a second thing to keep in step,
and the two publishers landing on different topics is precisely the failure the
"one alerting path" requirement exists to prevent.

### Six rules, one dashboard, and what was left out

`InstanceDown` (always-on machines only), `SmartFailurePredicted`,
`FilesystemFillingUp`, `SystemdUnitFailed`, `ZedNotRunning`,
`CertificateExpiringSoon`.

**`alwaysOn` defaults to false and ernst is the only true.** miralda, biene and
birte are a laptop, a laptop and a handheld: `up == 0` is their *normal* state
several times a day. Alerting on it would train everyone to ignore the topic
that also carries "the array is degraded" — so the down rule is scoped by label
and the other five still apply to them whenever they are up.

**The certificate rule needed a source that did not exist**, so M6 added one:
Traefik's Prometheus metrics on a **separate `metrics` entryPoint** (`:8082`),
source-restricted in the container firewall to `10.0.90.14`. A router on `:443`
would have been reachable by everything the permanent consumer-zone rule already
admits, and would then have needed a middleware to take that back. This closes
the gap `containers/traefik.nix` names in its own ACME comment — "there is no
monitoring on this until M6".

**Left out deliberately:** no Prometheus or Alertmanager route (they bind
loopback inside the container; `nixos-container run monitoring -- curl
localhost:9090` is the path, and the argument is the one M5 makes for the
Traefik dashboard), no blackbox exporter, no rule library, no Loki.

### Fleet cost on the laptops

node_exporter does no background work between scrapes, so the cost is one wakeup
per interval: **60 s**, not the 15 s Prometheus defaults to. Twenty collectors
whose output nothing here reads are disabled — the sysfs-walking ones (`hwmon`
stayed, `thermal_zone`, `powersupplyclass`, `dmi`, `edac` went), hardware this
fleet does not have (`mdadm`, `fibrechannel`, `infiniband`, `nvme`, `tapestats`),
and `zfs`, whose ARC statistics the dedicated pool exporter supersedes for every
question asked here. **Every name was checked against `node_exporter --help-long`
rather than assumed** — an unknown `--no-collector.X` is a start-up failure, not
a warning. The three optional exporters are off on all three laptops: the
`systemd` collector is the one with real per-scrape cost (D-Bus, every unit), and
smartctl re-queries every device on a timer.

### First deploy, 2026-08-24: the fail-closed path fired, and it found an older bug

`clan machines update ernst` applied cleanly — Traefik picked up the Grafana
route, the three exporters came up on the host, all six scrape-ACL rules and the
IPv6 masquerade were in place — and **the container never started**:

```
monitoring-secrets.service: zfs-ntfy url is not <baseurl>/<topic>:
                            <24-hex-topic>
container@monitoring.service: Dependency failed
```

That is the designed behaviour — the staging unit refuses a value it cannot
read, the container does not start, and there is no monitoring rather than
monitoring that silently cannot notify. But the value it refused was not
malformed. **It is a bare topic, and it is what the prompt asks for.**
`modules/observability/zfs-ntfy.nix` calls its var a "topic URL" and, in the
same sentence, suggests `openssl rand -hex 12` as the source — which produces
24 hex characters and no URL. Both descriptions are in one prompt; one of them
was followed.

**So the ZFS zedlet has never worked on ernst.** It passed that string to curl
verbatim, and curl did what curl does with a schemeless argument. Measured on
ernst the same day:

```
curl: (6) Could not resolve host: <24-hex-topic>
```

The zedlet ends its curl with `>/dev/null 2>&1`, so the error went nowhere. ZFS
alerting on the machine that holds the array had been dead since the module was
written, and nothing said so — including this milestone, which was designed
around "ZED owns pool state" and would have shipped that claim as fact.

**It was found by a consumer that failed loudly on the same input the original
had been failing silently on.** That is the transferable part, and it is worth
more than the fix: a notifier that cannot report its own failure is
indistinguishable from one that was never needed. Nothing in the M6 test plan
would have caught it either — every check was "does Prometheus alert", none was
"did ZED ever deliver anything".

Two changes, and the second matters more:

1. **`clanarchy.zfs.ntfy.splitScript`** — one normaliser, in `zfs-ntfy.nix`,
   accepting a full URL *or* a bare topic (which it completes against the new
   `clanarchy.zfs.ntfy.baseUrl`, default `https://ntfy.sh`). The zedlet uses it
   and so does M6's staging unit, deliberately: two publishers reading one value
   by two rules is how "one alerting path" quietly becomes two, and this
   milestone's ZED/Prometheus split rests on them landing on the same topic.
   **Not** fixed by re-prompting — the stored value is correct, only the
   reader's assumption was wrong, and touching the generator would invalidate
   the var on every machine holding one.
2. **The zedlet no longer discards curl's stderr.** It still exits 0 (ZED runs
   zedlets serially and one must never block the queue) and still drops stdout
   (ntfy echoes the message back as JSON), but a failed POST now says so in
   `journalctl -u zfs-zed`.

Unit-tested against seven inputs before redeploying — bare topic, full URL,
sub-path instance, trailing slash, no topic, empty, scheme-less-with-path — and
only the three well-formed shapes pass.

**Still unverified**: miralda also holds a `zfs-ntfy` var and its shape was not
readable from this session. If it is a bare topic too, its zedlet has been
equally dead, and the same deploy fixes it.

### An unrelated discrepancy found in passing: the `Allow Traefik` rule lost `Servers`

Measured on ernst 2026-08-24: `curl -k https://10.0.90.12/` **times out**. The
UDM-Pro policy's source list is `LAN + IoT`; `Servers` is not in it, though
[the ledger row](#interim-rule-ledger) records all three and M5's write-up says
explicitly that `Servers` is there "so that the firewall and Traefik's
`mgmt-only` ipAllowList agree about what management access means". M5 lost a
round to exactly this symptom.

Nothing in M6 depends on it — Prometheus scrapes Traefik's metrics over `br0` at
layer 2, and the browser reaching `grafana.goclan.org` comes from LAN. It is
recorded because a plausible inference written down as a measurement is the
failure shape this file keeps catching, and here is one more: the ledger says
three networks, the device has two.

### Manual steps — lgo's

1. **`clan vars generate ernst`** — prompts for the Grafana admin password
   (≥12 chars; the generator rejects shorter). It also generates Grafana's
   `secret_key` non-interactively. **Run this before the first deploy**: the
   staging unit bakes a secret path at build time, so a deploy that runs first
   produces a system whose unit can never succeed however often it is restarted.
   The failure is at least fail-closed — the container does not start.
2. **UDM-Pro: one DHCP reservation** on the Services network (VLAN 90), MAC
   `02:00:00:90:00:06` → `10.0.90.14`. It **must be inside the pool**
   (`10.0.90.6`–`.254`); UniFi accepts an address from the `.2`–`.5` range and
   then silently hands out an ordinary lease instead. M2b and M5 each lost a
   round to that, and here it is not cosmetic either: `containers/traefik.nix`
   hard-codes `.14` as Grafana's backend and as the only host allowed to read
   the metrics endpoint.
3. **Technitium**: `grafana.goclan.org` → `10.0.90.12` (Traefik), the same
   target as the other four names.
4. **UDM-Pro: NO new ZBF rule, and this is worth checking rather than
   assuming.** Grafana rides the existing permanent `Allow Traefik` rule
   (consumer zones → `10.0.90.12:80,443`). Every scrape path is either layer 2
   on `br0` (Traefik's metrics endpoint) or inside ernst (`mon0`, and ZeroTier
   out of the host's own netns). `alertmanager-ntfy` reaching ntfy.sh needs
   `Services → External`, which M2b measured as already passing.
5. **Deploy order: ernst first**, then the three clients in any order. Between
   the two the clients' exporters are not yet running and `up` is 0 for them,
   which is expected and — because `alwaysOn` is false for all three — does not
   alert.

### Test plan

```bash
# ── on ernst ────────────────────────────────────────────────────────────────
bridge vlan show dev vb-monitoring     # expect: 90 PVID Egress Untagged
ip -br addr show mon0                  # expect: fdca:fe90::1/128
nixos-container status monitoring
nixos-container run monitoring -- ip -br addr show eth0   # expect 10.0.90.14
nixos-container run monitoring -- ip -6 route             # host + one /128 per client

# The stack is up and every target is healthy.
nixos-container run monitoring -- curl -s localhost:9090/api/v1/targets \
  | jq -r '.data.activeTargets[] | "\(.labels.instance)\t\(.labels.job)\t\(.health)"'

# The ONE estimated number in the retention math — check it against ~8000.
nixos-container run monitoring -- curl -s \
  'localhost:9090/api/v1/query?query=prometheus_tsdb_head_series' | jq -r '.data.result[].value[1]'

# Alerting end to end.  This posts a real notification to the phone.
nixos-container run monitoring -- curl -s -XPOST localhost:9093/api/v2/alerts \
  -H 'Content-Type: application/json' \
  -d '[{"labels":{"alertname":"M6Smoke","severity":"warning"},
        "annotations":{"summary":"M6 smoke test","description":"delete me"}}]'
nixos-container run monitoring -- journalctl -u alertmanager-ntfy -n 20

# ── the negative controls, which are the half that proves anything ──────────
curl -m5 http://10.0.90.14:3000/            # from a laptop: MUST fail
curl -m5 http://10.0.90.12:8082/metrics     # from a laptop: MUST fail
curl -m5 http://[fdda:...:711f]:9100/metrics   # ernst's ZT addr from miralda: MUST fail

# ── from a management VLAN ──────────────────────────────────────────────────
# grafana.goclan.org → login page over TLS, then the "Clanarchy fleet"
# dashboard with panels populated (not "datasource not found").

# ── on each client, after its own deploy ────────────────────────────────────
systemctl status prometheus-node-exporter
ip6tables -L nixos-fw -n | grep 9100        # two accepts, both /128 sources
```

### Second deploy, 2026-08-24: the stack is up, and it caught one more real defect

Measured on ernst after the redeploy:

| Check | Result |
|---|---|
| `container@monitoring` / `monitoring-secrets` | both **active** |
| `bridge vlan show dev vb-monitoring` | `90 PVID Egress Untagged` — networkd won the race unaided |
| Container `eth0` | **`10.0.90.14/24`** — the DHCP reservation exists and is in-pool |
| `mon0` routes in the container | host `/128` + one `/128` per client, exactly as generated |
| Prometheus targets | `ernst` (node, zfs, smartctl), `miralda` (node), `traefik`, and the three self-jobs — **all `up`** |
| `biene` / `birte` | `down` — not yet deployed. **No alert**, because `alwaysOn` is false for both. The design working, not a gap |
| Traefik → Grafana backend | `200` from inside the traefik container |
| Grafana provisioning | datasource inserted with the pinned uid `clanarchy-prometheus`; dashboards "finished to provision", no errors |
| Firing alerts | none |

**Two metric names came off the wire and are correct**, which retires the doubt
recorded before deploy: `traefik_tls_certs_not_after` reports **89 days**
remaining on M5's wildcard, and `zfs_pool_health` reports `0` for both `zroot`
and `zdata`. They were read out of binaries' strings before; they are now read
out of a running instance.

**The defect: `systemd-networkd-wait-online` failed inside the container, on
every boot.** The journal dates it to the second:

```
12:14:58  mon0: Link UP
12:14:58  Starting Wait for Network to be Online...
12:15:18  Timeout occurred while waiting for network connectivity.
12:15:18  systemd-networkd-wait-online.service: FAILED
12:15:18  mon0: Gained carrier          ← the same second
```

`mon0` had `RequiredForOnline = "degraded"`, on the guess that a `/128`
point-to-point link never reaches `routable`. That guess was wrong twice over:
it *does* reach routable (it has a global address), and requiring **any** state
there cannot succeed. **A veth pair has no carrier until both ends are up**, and
the host end of `mon0` is brought up by `container@monitoring`'s `postStart` —
which `nixos-containers` runs only after nspawn reports the container started,
i.e. after the container's own boot has finished. wait-online was waiting for an
event that its own completion is a precondition for.

It resolved itself only because of the 20 s cap — the unit failed, boot
finished, READY fired, `postStart` ran, carrier appeared. That is exactly what
`containers/jellyfin.nix` designed the cap for ("one obviously failed unit
instead of a restart loop"), and here it did the job on a failure mode nobody
had predicted. The price was a permanently failed unit on every boot, which is
the kind of noise that hides the next real one.

Fixed with `RequiredForOnline = "no"` on `mon0` only. `eth0` keeps `"routable"`,
so a missing DHCP reservation is still caught. Nothing in the container needs
`mon0` at boot — Prometheus retries a failed scrape forever and the first retry
is seconds away.

### Third deploy, 2026-08-24: the zedlet fix is live, and the bug was fleet-wide

`wait-online` is `active` inside the container, no failed units on the host or in
it, `clanarchy-impermanence-check` `Result=success`, container still on
`10.0.90.14` with VLAN 90 correct.

The zedlet now resolves its URL through `splitScript` and builds
`https://ntfy.sh/<24-char topic>` — checked on ernst by printing the base and the
topic's *length* rather than the topic.

**And miralda's var is a bare topic too**, checked the same way
(`clan vars get miralda zfs-ntfy/url` piped through a shape test, never printed).
So this was never an ernst quirk: **the ZED zedlet had never delivered a
notification on any machine in the fleet.** Both are fixed by this deploy.

### THE TOPIC WAS LEAKED — ROTATED 2026-08-24, and the rotation was the delivery proof

While recording the findings above, the topic was pasted verbatim — as real
journal output — into `modules/observability/zfs-ntfy.nix`, this file, and a
comment on [#87](https://github.com/lutzgo/clanarchy/pull/87). **This repository
is public.** On a public ntfy instance the topic is the whole access control: it
grants both read and publish, so anyone holding it can read every pool alert
this fleet emits and inject fake ones.

All four occurrences are redacted, but redaction is not remediation — the value
survives in this branch's git history and in GitHub's comment edit history.
**Rotate it**, on both machines, and note that ernst and miralda have separate
topics by design (so one noisy machine can be muted without silencing the
other):

```bash
clan vars set ernst   zfs-ntfy/url      # new topic; openssl rand -hex 12
clan vars set miralda zfs-ntfy/url      # a DIFFERENT one
clan machines update ernst
clan machines update miralda
systemctl restart monitoring-secrets container@monitoring   # on ernst
```

Then re-subscribe both topics in the ntfy app and unsubscribe the old ones.

**Executed 2026-08-24, and notifications arrived** — both paths, on the new
topics. That single act closed three things at once: the exposure is remediated,
**ZED delivery is proven for the first time in this fleet's history**, and the
Alertmanager→ntfy bridge is proven end to end. Verified on ernst afterwards with
no secret printed: the staged `/run/monitoring-secrets/ntfy.yml` topic matches
the sops one (so the `monitoring-secrets` restart did land — it is not optional,
see below), and no unit is failed on the host or in the container.

Two things about the mechanics worth keeping:

- **`clan vars set` reads stdin when it is not a TTY**, so the value need never
  be displayed or enter shell history:
  `openssl rand -hex 12 | tr -d '\n' | clan vars set ernst zfs-ntfy/url`.
  It re-encrypts and auto-commits the sops file itself.
- **The `monitoring-secrets` restart is required and is not obvious.** That
  unit's script text embeds the *path* to the sops file, which does not change
  when its *contents* do — so systemd sees an unchanged unit, does not re-run
  it, and leaves the previous topic staged in `/run`. A deploy alone silently
  keeps publishing to the rotated-away topic. The zedlet has no such problem: it
  reads the file per event.

The generic lesson, since this file exists to carry them: **secret material
comes out of a `journalctl` paste as readily as out of a config file.** Every
other secret in this repo is handled correctly precisely because it is *shaped*
like a secret — a key, a token, a password. A 24-character topic reads like an
identifier, and that is exactly why it got copied.

**What rotation does not fix**: an unguessable topic is a bearer secret, not
authentication. ntfy supports reserving a topic and denying anonymous access,
but publishing then needs an `Authorization: Bearer` header that neither the
zedlet nor `alertmanager-ntfy` currently sends. Adding token support to both is
a small, self-contained follow-up and is the only thing that makes a future leak
survivable rather than fatal.

### Not yet proven

- ~~**That ZED can now actually deliver.**~~ **Proven 2026-08-24** on the rotated
  topics — see the rotation section above. This is the first confirmed ntfy
  delivery this fleet has ever produced, from either publisher.
- **biene and birte.** Deployed to neither; both show `down` (correctly
  unalerted, which is `alwaysOn = false` doing its job and is itself a small
  proof).
- **An Alertmanager silence across a reboot.** Silences and the notification
  log ride the container's own filesystem on `/var/lib/nixos-containers`
  (persisted by #54) rather than `zdata`, deliberately. No silence existed
  before the 2026-08-24 reboot, so that specific path is still untested —
  create one, reboot, check it is still there.

### The reboot — done 2026-08-24 13:16, and invariant #7 holds

The first boot since M6 deployed. Every earlier reboot in the window predates
it, so this is the only one that counts.

| Check | Result |
|---|---|
| System | `running`, **no failed units** on the host |
| `clanarchy-impermanence-check` | `Result=success`, `ExecMainStatus=0` — the #54 tripwire green through a real rollback |
| `zpool list` | `zroot` **ONLINE**, `zdata` **ONLINE** |
| `br0` MAC | `b2:8b:e1:f2:1e:7c` — **the M2b pin reproduced again**, now with a second container and a second veth type on the bridge |
| **`mon0` created by a BOOT, not a deploy** | `fdca:fe90::1/128` present — the open question this milestone inherited from M2b's `br0`, closed |
| `vb-monitoring` | `90 PVID Egress Untagged` — networkd won the VLAN race unaided, third service running |
| Container | `running`, no failed units, back on **`10.0.90.14`** (reservation honoured across a fresh DHCP cycle) |
| **`/srv/state/monitoring` through the rollback** | **intact** — `query_range` returns pre-reboot samples for `up{instance="ernst"}` spanning 12:16–13:11 CEST against a 13:16 boot |
| Targets after one scrape cycle | `ernst` (node/zfs/smartctl), `miralda`, `traefik`, and the three self-jobs all `up` |

**The TSDB continuity check is the one that mattered** and it is worth stating
how it was made convincing: `up == 1` after a reboot proves nothing — Prometheus
would report that on an empty database. Querying a *range that ends before the
boot* is what distinguishes "the data survived" from "the service restarted".

**One operational note, because it will read as a failure again.** The boot took
long enough to look like a dead machine: no ping, no initrd sshd on 2222, for
several minutes. That is this host's normal POST — HBA enumeration across eight
SAS SSDs — and M2b recorded the same thing after its reboot. `nc -z ernst 2222`
is the check that distinguishes "still in POST" from "waiting for the zroot
passphrase"; once it answers, `ssh ernst-initrd systemd-tty-ask-password-agent
--query` unlocks without walking to the TV.
- ~~**The reboot.**~~ **DONE — 2026-08-24 13:16, see below.**
- ~~**`mon0` across a reboot.**~~ **DONE — same reboot.**
- ~~**The zfs_exporter metric names.**~~ **Confirmed live 2026-08-24**:
  `zfs_pool_health` returns `0` for both `zroot` and `zdata`, and
  `traefik_tls_certs_not_after` puts M5's wildcard at 89 days. Both had only
  been read out of binaries' strings before. The reasoning that put the ZFS ones
  behind a dashboard panel rather than an alert still stands and is worth
  keeping: a name guessed wrong is then an empty panel, not a missed
  notification.

**Goal.** A fleet-wide clan service module: Prometheus, Alertmanager and Grafana
in an nspawn container on ernst, node_exporter on every machine, scrape targets
generated from the clan role membership rather than hand-listed. Alerting reuses
the ntfy topic that `modules/observability/zfs-ntfy.nix` already owns — one ZFS
alerting path, not two.

**Depends on.** M5 for the Grafana route (mgmt-only until M7). Prometheus itself
does not need it. **Risk.** Low-medium; the fleet-wide half touches laptops.

**The session prompt this was built from is kept below**, per the file's own
convention.

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

## M8 — `feat/ernst-tvheadend`

**Goal.** Live TV and a PVR backend in Jellyfin, fed by the four DVB-C tuners
already sitting in the FRITZ!Box 6591 Cable. The 6591 does **not** emit raw
multicast IPTV — it publishes its tuners as a **SAT>IP server**: RTSP for control,
**unicast** RTP for media. That single fact decides the shape of this milestone.
Unicast is routable, so this needs no IGMP snooping, no multicast relay, and none
of the multicast-relay machinery elsewhere in the stack; it is an ordinary
inter-VLAN flow the UDM-Pro can firewall like any other. The chain is:

```
FRITZ!Box 6591 (SAT>IP server, 4× DVB-C)
  → Tvheadend (SAT>IP client + PVR/EPG backend, nspawn on ernst)
    → Jellyfin Live TV (M3U tuner + XMLTV EPG)
```

**Its own milestone, not sub-tasks under Jellyfin.** M2b is a networking
migration of a service that already runs; this is a new service, a new isolation
unit, a new hardware dependency, and a chunk of off-repo validation that has to
happen *before* any Nix is written. Folding it into M2b would mean one session
holding two unrelated failure modes.

**Depends on.** Jellyfin (done) and M2 (done). Independent of M3–M7 — it can be
taken whenever [Phase 0](#phase-0-operator-gate-lgo) clears. Its container shape
follows whichever of M2b has landed by then (see the prompt).
**Risk.** Low-to-medium in the repo. The real risk is entirely outside it: if
this 6591 is a provider-branded unit with DVB-C/SAT>IP stripped from the
firmware, the milestone is dead and no amount of Nix fixes it. Phase 0 exists to
find that out for the price of a `curl`.

### Phase 0 — operator gate (lgo)

Steps 1–3 are physical, UniFi, and browser work. **Do them before opening a
session** and paste the evidence into it; a Claude session cannot patch a cable
or click a ZBF rule, and building a container against an unverified stream source
is how a milestone ends up debugging the wrong layer.

**0.1 — Physical wiring.** *Pre-check first, before touching a cable:* determine
how the 6591 is attached today and what mode it is in.

- Is it WAN-only into the UDM-Pro, or does it already have a LAN leg patched into
  the USW? If a leg already exists, 0.1 is a no-op and 0.2 is just VLAN
  assignment. **TODO — confirm.**
- Is it in **router mode** or **bridge/modem mode** (`Kabelmodem`-Betrieb)?
  **TODO — confirm.** This is not a detail: in bridge mode a LAN port may be a
  pure L2 path to the cable WAN, and patching it into the USW would bridge the
  provider's segment into skynet. In bridge mode SAT>IP is also typically gone,
  which folds this question into 0.3 anyway.
- If a leg is needed: patch a free LAN port on the 6591 into the USW. Note that
  the 6591 in router mode **runs its own DHCP server** on that LAN side. A second
  DHCP server on a production VLAN is a rogue-DHCP incident waiting to happen —
  either disable it on the FRITZ!Box, or land the leg on a VLAN where it cannot
  reach a client that would listen. Decide this deliberately in 0.2.

**0.2 — UniFi wiring.**

- Assign the FRITZ!Box's switch port to the target VLAN. **TODO — which VLAN?**
  The candidates are IoT (20), a dedicated appliance VLAN, or Services (90). It
  should *not* be Servers (50): the 6591 is provider-managed customer premises
  equipment, not a machine we administer. Whatever is chosen, record it here and
  in the container's file header — the ACL below and the ledger rows both
  key off it.
- Give it a stable address: a DHCP reservation on the UDM-Pro, or a static
  address on the FRITZ!Box itself. Prefer the reservation, for the same reason
  M2b prefers it — the network's source of truth stays in one place.
- Add the ZBF rule allowing the future Tvheadend host to reach the FRITZ!Box:
  - **TCP 49000** — the SAT>IP/TR-064 description endpoint (`satipdesc.xml`).
  - **TCP 554** — RTSP session setup and control.
  - **Media transport.** RTP is a *separate* unicast UDP flow the server opens
    back toward the client on client-chosen ports, so a stateful rule for 554
    does not cover it. Two ways out, and they are not equal: either allow
    FRITZ!Box → Tvheadend on the ephemeral UDP range (broad, ugly, and it is why
    ledger row **L7** exists below), or run RTP **interleaved over the existing
    RTSP TCP connection**, which keeps the whole ACL to two TCP ports and no
    return-path rule at all. Try interleaved first — the milestone prompt makes
    this a decision to prove, not to assume.
  - On any ZBF rule reaching a container zone, TICK `Auto Allow Return Traffic`.
    Connection State is NOT a substitute and the two are independent: the state
    list governs the forward direction, the checkbox creates the reverse rule.
    Leaving it unticked forwards the SYN and drops the SYN-ACK, which looks like
    a dead service rather than a firewall problem. Earlier revisions of this file
    said "use Custom → New, never All" — that advice was wrong and cost most of a
    session in M2b. See
    [M2b's UDM-Pro section](#the-udm-pro-half-cost-more-than-the-nix-half).
  - If the FRITZ!Box ends up on the same VLAN as Tvheadend, there is no ACL at
    all. Say so rather than creating a rule that does nothing.

**0.3 — Stream test, before any infrastructure exists.** This is the gate.

1. Confirm DVB-C / SAT>IP is actually enabled and present in the web UI
   (`Heimnetz → Mediaserver`, TV/SAT>IP section). **TODO — check for a
   provider/Vodafone branding lock**; branded firmware images have shipped with
   the tuner features removed, and the UI simply lacks the section rather than
   telling you why.
2. Fetch the description document — no client, no container, just:
   ```
   curl -s http://<fritzbox-ip>:49000/satipdesc.xml
   ```
   It must return a `<root>` with a `<satip:X_SATIPCAP>` advertising DVB-C
   frontends (expect `DVBC-4` or equivalent). Nothing returned, or a document
   with no SAT>IP capability line, means stop — the rest of the milestone has no
   source.
3. Play one channel end-to-end before trusting the description document, since a
   tuner can be advertised and still be unusable:
   ```
   ffprobe -rtsp_transport tcp \
     "rtsp://<fritzbox-ip>/?src=1&freq=<MHz>&msys=dvbc&mtype=256qam&sr=6900&pids=all"
   ```
   (or the same URL opened in VLC). Frequency, modulation and symbol rate are
   provider-specific — take them from an existing cable receiver or the
   provider's channel list. `-rtsp_transport tcp` is deliberate: if this works, it
   is also the evidence that the interleaved-TCP path in 0.2 is available.

Paste the `satipdesc.xml` capability line and the `ffprobe` stream summary into
the session. They are the prompt's prerequisite.

### Open questions carried into the session

- **FRITZ!Box branding lock** — is DVB-C/SAT>IP present in this unit's firmware
  at all? Gate for the entire milestone (0.3).
- **Operating mode** — router vs bridge/modem, which decides whether a LAN leg is
  even safe to patch (0.1).
- **Target VLAN for the FRITZ!Box** — unresolved, and it determines the ACL, the
  DHCP question, and the ledger rows (0.2).
- **RTP transport** — interleaved over RTSP TCP (preferred) vs a UDP return-path
  rule (row L7). Settled by 0.3's `-rtsp_transport tcp` result plus what
  Tvheadend's SAT>IP client actually supports.

````text
Read CLAUDE.md fully before doing anything.

Work in the clanarchy repo on miralda. Branch: feat/ernst-tvheadend.

PREREQUISITE — Phase 0 of M8 in docs/roadmap.md is CLEARED, and the evidence
is in this session: the FRITZ!Box's satipdesc.xml capability line, and an
ffprobe/VLC summary of one channel actually playing over an RTSP SAT>IP URL.
If that evidence is not here, STOP and say so. Do not build a container
against an unverified stream source, and do not "temporarily" scaffold one to
be filled in later — the whole point of the gate is that the failure mode
this milestone is most likely to hit lives outside the repo.

GOAL. Tvheadend on ernst as a SAT>IP client against the FRITZ!Box 6591's four
DVB-C tuners, publishing an M3U playlist and an XMLTV guide that Jellyfin
consumes as a Live TV tuner + EPG source.

SHAPE. One systemd-nspawn container named "tvheadend", in
machines/ernst/containers/tvheadend.nix, wired into flake.nix next to the
jellyfin container. nspawn is the right tier per invariant #1: trusted,
storage-heavy, and it talks to one appliance on the LAN — not to the
internet on its own behalf. Not a microvm, not podman (tvheadend is in
nixpkgs; no image escape hatch is needed).

NETWORKING — decide by what has landed, and say which branch you took:
  - If M2b (feat/ernst-jellyfin-tap) is merged, this container is BORN on a
    MAC-pinned veth on br0, Services VLAN (90). Do not repeat Jellyfin's
    host-networking detour just because the file next door started that way.
    Copy M2b's WORKING version from machines/ernst/containers/jellyfin.nix
    (not the sketch in networking.nix): host side named vb-tvheadend,
    KeepMaster = true, [BridgeVLAN] for 90, the idempotent ExecStartPost that
    settles the networkd-vs-nspawn race over the master, and the wait-online
    cap that keeps a DHCP failure from restart-looping the container. Unit
    goes in the container's own file, not the topology file. Allocate the
    next MAC from the table in machines/ernst/networking.nix. VERIFY with
    `bridge vlan show` regardless.
  - If M2b has NOT landed, ship host networking v1 exactly like Jellyfin's
    and arr's, with ports 9981 (HTTP/web) and 9982 (HTSP) opened on the host
    and scoped to the management VLAN on the UDM-Pro, plus a veth-migration
    note in the file header mirroring the one arr.nix carries. Add the host
    port opening to the interim-rule ledger as row L6.

SAT>IP CLIENT — the one configuration detail that decides whether this works:
  - Point Tvheadend at the STATIC description URL,
    http://<fritzbox-ip>:49000/satipdesc.xml. Do NOT rely on SSDP discovery.
    SSDP is multicast to 239.255.255.250:1900 and the UDM-Pro does not carry
    it between VLANs — and the fix for that is emphatically NOT to enable an
    SSDP/mDNS relay across a firewall boundary to save one config field.
    Static URL, one direction, done.
  - The NixOS module is `services.tvheadend` (httpPort 9981 / htspPort 9982).
    CHECK what it actually exposes for extra arguments rather than assuming
    an `extraArgs` option exists. If there is none, override ExecStart in
    LIST FORM WITH AN EMPTY FIRST ELEMENT ([ "" "…" ]) — a NixOS systemd
    drop-in is ADDITIVE, and `lib.mkForce` on a plain string appends a second
    ExecStart instead of replacing the first.
  - Record the FRITZ!Box's address and VLAN in the file header, with a note
    that it is provider CPE we do not administer — its firmware can change
    under us.

TUNER CEILING — a real constraint, not a footnote. The 6591 has FOUR DVB-C
frontends, and SAT>IP maps one RTSP session to one frontend: two clients on
the same mux still burn two tuners, unlike a locally attached card where
Tvheadend demuxes several services from one frontend. EPG grabbing and DVR
recordings consume from the same pool, and so does anything the FRITZ!Box
itself is doing. Set the SAT>IP network's max input streams to 4, decide and
document how much headroom the DVR gets versus live viewing, and put the
whole ceiling in the file header so the first "why did my recording fail"
has an answer in the repo.

STORAGE.
  - State at /srv/state/tvheadend, bound to the upstream default state path
    inside the container so the packaged unit needs no overrides — the same
    trick jellyfin.nix uses for /var/lib/jellyfin.
  - DVR recordings into /srv/media, as a PLAIN SUBDIRECTORY (invariant #2 —
    one hardlink domain; do not add a dataset under /srv/media). Pick the
    path so Jellyfin can present the recordings as a library, and note that
    /srv/media carries no snapshots.
  - Static uid/gid, member of the media group (gid 3000, fixed on the host in
    machines/ernst/containers/jellyfin.nix). nspawn does not remap gids here;
    numeric ids must match on both sides.

EPG. Prefer the over-the-air EIT grabber off the DVB-C stream — it needs no
external grabber, no new flake input, and no internet dependency. If you
conclude an external XMLTV grabber is needed, argue it in the file header
rather than adding one silently. Either way Tvheadend is what serves XMLTV
downstream.

OUTPUTS for Jellyfin: the M3U playlist and XMLTV endpoints Tvheadend serves
over HTTP. Verify the exact paths against the packaged version rather than
quoting them from memory, and put the resulting URLs in the PR body.

CREDENTIALS. Tvheadend's ACL/user database is UI state, not a Nix option.
Follow M4's configuration policy: create a dedicated, streaming-only
Tvheadend user for Jellyfin, and document the in-UI settings as a
reproducible checklist in the PR body so the state can be rebuilt from the
repo plus that list. The superuser credentials come from a clan vars
generator (clan.core.vars.generators.*), seeded into the state directory —
no plaintext in the repo, no placeholder that looks real. Document
`clan vars generate ernst` in the PR body.

JELLYFIN WIRING is a checklist, not code — Live TV configuration lives in
Jellyfin's own database. In the PR body, spell out: add Tvheadend's M3U
playlist as an M3U Tuner, add its XMLTV feed as the guide source, map
channels, and where the recordings library points. Note as a watch-item (not
a claim) that SD MPEG-2 channels may fall back to software decode on the
Granite Ridge iGPU while H.264/HEVC HD channels transcode in hardware —
verify with a live transcode, do not assume either way.

MANUAL STEPS — list them explicitly in the PR body, they are lgo's:
  - The Phase 0 items, if any remain open.
  - Technitium record for tvheadend.
  - The ZBF rule Tvheadend → FRITZ!Box (TCP 49000 + 554, plus whatever the
    RTP transport decision requires), with `Auto Allow Return Traffic` TICKED.
  - DHCP reservation for the container's MAC, if the veth path was taken.
  - The Jellyfin Live TV configuration checklist.
  - `clan machines update ernst` and `clan vars generate ernst`.

TEST PLAN in the PR body:
  - Tvheadend sees the SAT>IP server via the static XML URL and enumerates
    four DVB-C frontends.
  - A mux scan finds services; channels are mapped.
  - `curl` of the M3U and XMLTV endpoints FROM THE JELLYFIN SIDE returns
    real content — that is the flow that has to work, not a curl from the
    host.
  - Guide data populates in Jellyfin and a channel plays end-to-end on a
    real client (TV on the IoT VLAN, not just a browser on the mgmt VLAN).
  - The tuner ceiling is exercised deliberately: a fifth concurrent stream
    must fail cleanly, and the PR body says what "cleanly" looked like.
  - RTP transport: state which mode is in use and show the evidence.

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
  PR.
````

---

## M9 — `feat/ernst-tubesync`

**Goal.** TubeSync ([meeb/tubesync](https://github.com/meeb/tubesync)) on ernst:
subscribe to YouTube channels/playlists, download with yt-dlp on a schedule, and
write the results straight into the tree Jellyfin already scans — so new content
appears in the library with no second copy step and no import stage.

**Depends on.** Jellyfin (done). The auth and routing decisions below reference
M5 (Traefik) and M7 (Authelia); the milestone can land before either, but then it
carries an interim ledger row (**L8**) it would not otherwise need.
**Risk.** Medium, and *not* where it looks. TubeSync itself is a small service.
The risk is that this is the **first occupant of the podman tier** — invariant #1
lists podman as an escape hatch with "nothing yet" in it, and
`virtualisation.oci-containers` appears nowhere in this repo. This milestone
builds the tier as much as it deploys the service, and the networking question
below has no worked example anywhere in `machines/ernst/networking.nix`.

### Decisions to make in the session

**1 — Isolation tier: podman. Right answer, and the reason matters.**

Podman qualifies, but *not* because TubeSync is lightweight and SQLite-backed.
Invariant #1 tiers by **trust and workload**, not by footprint — Jellyfin is
lightweight too and it is nspawn; the arr stack is three services in one nspawn
container. The tier table gives podman exactly one job: *"escape hatch — upstream
ships only an image."*

TubeSync meets that test on the facts. **Verified 2026-08-20: there is no
`tubesync` attribute in nixpkgs.** Upstream ships a Docker image and a Django
app; there is no NixOS module and no package to drive from `services.*`. So the
nspawn argument that carries Jellyfin — "a real NixOS system view, upstream
hardening as-is, no OCI image drift" — has nothing to stand on here.

Two consequences to write into the file header rather than discover later:

- The tier's cost is the thing the invariant is warning about: an opaque image,
  a package tree we do not control, and drift we absorb rather than evaluate.
  Accept it explicitly, and state what would move this to nspawn later (someone
  packaging TubeSync, or a Django-app-from-source derivation).
- **Decide whether to run it rootless or rootful**, and say why. Rootless is the
  better default for an escape-hatch tier, but it interacts directly with the
  networking and PUID/PGID decisions below — do not pick it by reflex and then
  fight it in items 3 and 6.

**2 — Module path: `machines/ernst/containers/tubesync.nix`.**

Not `modules/services/tubesync.nix` — **there is no `modules/services/`
directory in this repo**, and `modules/` holds *cross-machine* shared modules
(`modules/desktop`, `modules/roles`, `modules/hardware`, …). A service that runs
on exactly one machine lives under that machine. The only existing service
container is `machines/ernst/containers/jellyfin.nix`, and M4 and M8 both add
siblings to it. Wire it into `flake.nix` next to them.

`modules/apps/containers.nix` is **not** a precedent to follow: it is the
workstation developer bundle (`clanarchy.apps.containers`, podman CLI +
docker-compat socket for `lgo`), pulled in via `modules/apps` — which is part of
`commonHeadful`, and ernst uses `commonBase`. It has never run a service.

Note in the PR body that `containers/` now holds one podman unit alongside two
nspawn ones, and either accept the name as generic or say why it stays.

**3 — Networking: the open problem. There is no worked example for this.**

"VLAN tap + MAC pin per the existing bridge convention" does not carry over —
M2 established that there are **two** attachment patterns and this is a third
case:

- a **tap** is a microvm primitive (M3's guest);
- a **veth**, host side `vb-<name>`, is the nspawn primitive (M2b, M4, M8);
- **podman is neither.** Its netavark backend does bridge/macvlan/ipvlan, and
  **macvlan is explicitly rejected for this architecture**: on `br0` it rides
  br0's own self VLAN (50, the *host* VLAN) and on `enp13s0` it rides the trunk's
  native VLAN, also 50. It cannot be placed on VLAN 90 at all. That finding is
  what M2b had to correct in Jellyfin's file header — do not re-derive it.

So the session must **choose and justify an attachment**, and this is its
hardest decision. Candidates, in the order worth trying:

- a manually created veth pair enslaved to `br0` with a `[BridgeVLAN]` for 90,
  handed to the container's netns — closest to worked example B, at the cost of
  wiring podman to a netns it did not create;
- a netavark bridge network parented on `br0` with the VLAN set on the port;
- host networking v1 with a documented migration note, exactly as Jellyfin and
  arr started — the honest fallback if the above turn into a research project.

Take the fallback rather than burning the milestone on it, but **say which and
why**. Whatever lands: MAC-pinned, a DHCP reservation on the UDM-Pro over a
static address, and **verify with `bridge vlan show`** that the VLAN actually
applied — networkd and the container runtime race over the master, and with
`DefaultPVID = "none"` a missed application is fail-closed.

Then a Technitium `tubesync` record, and per invariant #3 the consumer-facing
path is Traefik:443 — one route, no second permanent rule.

**Interim direct-port ZBF rule — probably not needed, unlike Jellyfin's.**
L1/L2 exist because Jellyfin is a *household* service on consumer VLANs with no
proxy yet. TubeSync is an **admin UI**: mgmt-VLAN scoped, which invariant #3
explicitly does not cover. If M9 lands after M5, point it at Traefik and create
nothing. If it lands before, add the host/container port as ledger row **L8**
with the M5 trigger — mgmt-scoped, not a consumer-zone rule.

**4 — Auth: Authelia SSO (M7), not `HTTP_USER`/`HTTP_PASS`.**

The Jellyfin carve-out does not apply, and the reason is worth stating precisely:
Jellyfin is exempt because TV and mobile clients cannot survive a forward-auth
redirect. TubeSync has no such client — the browser UI is the only ingress.

The integration in item 6 does **not** change this: TubeSync's "media servers"
feature is an **outbound** call from TubeSync to Jellyfin (a library-rescan
trigger). Forward-auth sits on TubeSync's *ingress*; it cannot break an egress
call. That is what makes SSO safe here, and it should be the recorded reason.

Tradeoff to record rather than skip: `HTTP_USER`/`HTTP_PASS` is one env pair and
works today with no dependency, but it is a second credential store outside
Authelia, no TOTP, and a per-service password that never gets rotated. SSO costs
a dependency on M7. **If M9 lands before M7**, use basic auth as the interim,
put the credentials in a clan vars generator (never plaintext, never a
real-looking placeholder), and note in the header that M7 replaces it.

**5 — Storage: config on `/srv/state`, downloads inside the media pool.**

- **Config** (SQLite db + thumbnails + yt-dlp cache) → `/srv/state/tubesync`,
  per invariant #7. Not `zroot`, which rolls back. A **bind mount, not a named
  podman volume** — a named volume puts state in podman's graph root and defeats
  the point of `/srv/state` being the one place state lives.
- **Downloads → a plain subdirectory under `/srv/media`.** Yes to the premise:
  same pool, same dataset, so Jellyfin picks it up with no copy step. Invariant
  #2 governs — `/srv/media` is **one** dataset with plain subdirectories, so do
  **not** add `zdata/media/youtube` or similar. Pick the path to sit alongside
  `library/movies` and `library/tvshows` and decide whether Jellyfin sees it as
  its own library or as another folder in an existing one.
- Two properties of that dataset to carry into the decision: `/srv/media` has
  **`com.sun:auto-snapshot=false`** (unlike `/srv/unsorted` and `/srv/gardens`),
  so downloads are not snapshotted — acceptable for re-downloadable content, but
  say so out loud. And it is a hardlink domain shared with the *arr import path;
  TubeSync does not hardlink, but it must not disturb the layout that does.
- Follow the ownership pattern already in `jellyfin.nix`: `root:media` with mode
  **2770** (setgid, so new files inherit gid `media`), applied by a unit ordered
  `after`/`requires` `srv-media.mount` — a tmpfiles rule alone races the mount.

**6 — Env vars to pin, and the one that will bite.**

- **`PGID` = 3000** — the `media` group, fixed on the host in
  `jellyfin.nix` and deliberately above NixOS's dynamic gid range. **`PUID`** =
  a new static uid, allocated and recorded like `jellyfinUid = 964` is.
- **The trap:** nspawn maps gids 1:1, which is why `jellyfin.nix` can say "these
  numbers MUST be identical on both sides." **Podman does not** — with a userns
  (and rootless always has one), the in-container `PUID`/`PGID` are *not* the
  uid/gid that land on disk. If files show up as `nobody:nobody` or as some
  sub-uid, this is why. Decide the mapping explicitly — `--userns=keep-id`, an
  idmap, or rootful with no remapping — and **verify with `stat` on a real
  downloaded file** that a `media`-group member can read it. Treat this exactly
  as M3 treats its uid/gid decision: a first-class design decision, not a
  permissions detail.
- **`TZ`** = `Europe/Berlin`, matching the host. It drives scheduling, so a
  wrong value silently shifts every download window.
- **Media-server connection**: TubeSync's Jellyfin integration needs the
  server URL and an **API key**. The key is a secret → clan vars generator,
  `neededFor` set if activation depends on it. Note the ordering dependency: the
  key is created *in Jellyfin's UI*, so it is an lgo manual step feeding a
  generator prompt, not something the session can produce.

**7 — Version pin and database.**

- **`v0.18.1`** is the version to pin as of Aug 2026 — **operator-supplied and
  not independently verified here** (it postdates this assistant's knowledge
  cutoff). Confirm against upstream releases at pin time rather than trusting
  this line.
- Pin by **image digest**, not by tag. A tag is mutable, and the entire cost of
  the podman tier is image drift we cannot evaluate — a digest is what converts
  that from "whatever the registry serves today" into something reproducible.
  Record the tag *and* the digest, and note how a bump is done.
- **MariaDB is not required.** TubeSync defaults to SQLite and supports
  MariaDB/PostgreSQL optionally; at a single-user, single-instance scale with no
  HA requirement, SQLite is correct — the same reasoning M7 uses for Authelia's
  storage. Do not add a database container. One note for the header: the SQLite
  file lives on ZFS, so if lock contention or checkpoint stalls ever show up,
  the first thing to check is the dataset's `recordsize`, not the schema.

### Open questions for the session that picks this up

- **Podman attachment to a VLAN-filtering bridge** — genuinely unsolved in this
  repo, and the milestone's real work (item 3).
- **Rootless vs rootful**, which cascades into the userns/PUID mapping (items 1
  and 6).
- **Ordering against M5 and M7** — decides whether L8 and the interim basic-auth
  path exist at all.
- **`v0.18.1`** — verify against upstream before pinning (item 7).

````text
Read CLAUDE.md fully before doing anything.

Work in the clanarchy repo on miralda. Branch: feat/ernst-tubesync.

READ M9 IN docs/roadmap.md FIRST. Seven decisions are already recorded there
with their reasoning. Do not re-litigate them. If you overturn one, record
the argument in the file header rather than changing course silently.

GOAL. TubeSync (github.com/meeb/tubesync) on ernst: subscribe to YouTube
channels and playlists, download with yt-dlp on a schedule, write straight
into the tree Jellyfin already scans — no import stage, no second copy.

TIER: podman — and the reason is NOT that TubeSync is small. Invariant #1
tiers by trust and workload; podman's one job is "upstream ships only an
image". TubeSync is not in nixpkgs (verify that still holds — it did on
2026-08-20), so there is nothing to drive from services.*. You are the FIRST
occupant of this tier: virtualisation.oci-containers appears nowhere in this
repo, so you are building the tier as well as the service. State in the file
header what would later move this to nspawn.

DECIDE ROOTLESS VS ROOTFUL EXPLICITLY, and early. It cascades into both the
networking and the uid mapping below. Do not pick by reflex and then fight it
in two other places.

FILE: machines/ernst/containers/tubesync.nix, wired into flake.nix next to
jellyfin.nix. NOT modules/services/ — that directory does not exist, and
modules/ holds cross-machine modules. modules/apps/containers.nix is the
workstation podman CLI bundle for lgo; it is not a precedent.

NETWORKING — the hard part, and there is no worked example in this repo.
  - A tap is the microvm primitive, a vb-* veth the nspawn one, and podman is
    neither. macvlan is REJECTED for this architecture: on br0 it rides the
    host self VLAN (50) and cannot be placed on 90. M2 established this — do
    not re-derive it.
  - Try in order: a veth pair enslaved to br0 with a [BridgeVLAN] for 90,
    handed to the container's netns; a netavark bridge network parented on
    br0; host networking v1 with a migration note in the header.
  - TAKE THE FALLBACK rather than burning the milestone on research — but say
    which you took and why.
  - Whatever lands: MAC-pinned, a DHCP reservation on the UDM-Pro in
    preference to a static address, and VERIFY with `bridge vlan show` that
    the VLAN actually applied. networkd and the runtime race over the master,
    and with DefaultPVID = "none" a miss is fail-closed, not fail-open.
  - Technitium record. The consumer path is Traefik:443 per invariant #3.
  - If this lands before M5, add the web UI port to the ledger as row L8,
    mgmt-scoped. If M5 is already in, create nothing.

AUTH: Authelia forward-auth (M7). The Jellyfin carve-out does not apply —
Jellyfin is exempt because TV and mobile clients cannot survive the redirect,
and TubeSync's only ingress is a browser. Its "media servers" feature is an
OUTBOUND call to Jellyfin, so forward-auth on ingress cannot break it; put
that in the header so a later session does not "fix" it. If M7 is not in yet,
use HTTP_USER/HTTP_PASS as the interim, credentials from a clan vars
generator, and note that M7 replaces it.

STORAGE.
  - Config (SQLite db, thumbnails, yt-dlp cache) at /srv/state/tubesync per
    invariant #7, as a BIND MOUNT — not a named podman volume, which would
    put state in podman's graph root and defeat the point.
  - Downloads into a PLAIN SUBDIRECTORY under /srv/media. Invariant #2: one
    dataset, plain subdirectories. Do NOT add zdata/media/youtube.
  - /srv/media carries com.sun:auto-snapshot=false, so downloads are not
    snapshotted. Acceptable for re-downloadable content — say so out loud
    rather than leaving it implied.
  - Ownership root:media mode 2770 (setgid), applied by a unit ordered
    after/requires srv-media.mount. A tmpfiles rule alone races the mount;
    jellyfin.nix explains why.

UID/GID — the one that will bite.
  - PGID = 3000 (the media group, fixed in jellyfin.nix). PUID = a new static
    uid, allocated and recorded the way jellyfinUid = 964 is.
  - nspawn maps gids 1:1, which is why jellyfin.nix can assert the numbers
    match on both sides. PODMAN DOES NOT. Under a userns — always, when
    rootless — the in-container PUID/PGID are not what lands on disk. If
    files appear as nobody:nobody, this is why.
  - Decide the mapping (--userns=keep-id, an idmap, or rootful with no
    remapping) and PROVE it: stat a real downloaded file and show a
    media-group member can read it. Treat this as M3 treats its uid/gid
    decision — a design decision, not a permissions detail.
  - TZ = Europe/Berlin, matching the host. It drives scheduling, so a wrong
    value silently shifts every download window.

JELLYFIN INTEGRATION needs the server URL and an API key. The key is a secret
-> clan vars generator. Note the ordering: the key is created in Jellyfin's
UI, so it is an lgo manual step feeding a generator prompt, not something the
session can produce.

IMAGE PIN. Pin by DIGEST, not tag — image drift is the entire cost of this
tier, and a tag is mutable. v0.18.1 is the intended version, but that line in
the roadmap is operator-supplied and was NOT independently verified; confirm
it against upstream releases before pinning. Record tag and digest, and how a
bump is performed. SQLite only — do NOT add a MariaDB container.

IMPERMANENCE. ernst has been genuinely impermanent since 2026-08-18 (see
invariant #7). Anything this service writes to zroot is gone on the next
boot. REBOOT ONCE after deploying and confirm the service returns with its
state intact. That is part of this milestone, not an afterthought — no
previous milestone had to think about it, and this is the first one that
does.

CONFIGURATION POLICY. Where a setting exists only in the UI (source
registration, media-server wiring), do NOT fake it — document the intended
in-UI settings in the PR body as a reproducible checklist, so the state can
be rebuilt from the repo plus that list.

MANUAL STEPS for the PR body (lgo's):
  - Create the Jellyfin API key, feeding the vars generator prompt.
  - Technitium record; DHCP reservation if a veth path was taken.
  - The ZBF rule, if one is needed at all.
  - `clan machines update ernst` and `clan vars generate ernst`.

TEST PLAN in the PR body:
  - The container starts and holds its own address, if it has one.
  - A subscription downloads a real video.
  - `stat` proves a media-group member can read it — the uid/gid decision.
  - Jellyfin picks the file up with NO copy step.
  - A reboot leaves both config and downloads intact.

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
  PR.
````

---

## M10 — Kodi + IR remote (dropped)

**Dropped 2026-08-20 by lgo, before any code was written.** The couch
requirement is **Plasma Bigscreen plus Steam**, and Kodi is a third media UI
nobody asked for — it would have been a second library front-end to configure,
persist and keep in sync with Jellyfin's, bought against a gap Bigscreen is
meant to close directly. Recorded rather than deleted so the numbering stays
stable and the next reader does not re-derive the idea.

What the entry got right and what it got wrong:

- **Wrong:** that the Bigscreen question made Kodi *safe* to ship. Being
  independent of an unresolved decision is not the same as being wanted; it
  argued Kodi could not be invalidated, never that it was needed.
- **Right, and kept:** the gap itself. Big Picture cannot add non-Steam
  shortcuts — only the desktop Steam client can — so the gamescope session
  still cannot act as a general launcher. That is now squarely
  [Bigscreen's problem to solve](#floating-backlog), not Kodi's.
- **Right, and moved to the backlog:** the **Flirc IR receiver**. It was
  bundled here but is orthogonal to every media UI — the SofaBaton X1S speaks
  Bluetooth only to its own hub, ernst's on-board MT7927 Bluetooth is dead
  until MediaTek's firmware redistribution clears, and Flirc presents as a
  plain USB HID keyboard that works identically under gamescope, Bigscreen and
  anything else. Dropping Kodi does not make the couch need an input device
  any less.

---

## Floating / backlog

Not sequenced. Each becomes a milestone when it earns one.

**`user activation for go failed` on every ernst deploy.** Activation reports
`Failed to start user unit basic.target … Did not receive a reply`, five times,
then `activation returned 4 — retrying`, and the retry succeeds. So every deploy
prints a wall of red and then works. It is the couch user's session dbus, not
its system units, and it predates M3 (visible in M2b-era deploys too). Worth
fixing because a deploy that always prints errors is a deploy nobody reads: the
next real failure will scroll past unnoticed. Start with whether `go` has a
lingering user manager at all (`loginctl user-status go`) — the account is
autologged into a gamescope session, so its bus may simply not be there when
activation reaches for it.

**Xbox pad over Bluetooth on ernst — blocked upstream, not by us.** The board's
MediaTek MT7927 (Filogic 380) Bluetooth half fails at HCI reset: `btmtk` on
6.18.43 has no case for hardware variant `0x6639`, and the firmware blob
`BT_RAM_CODE_MT6639_2_1_hdr.bin` is still in a draft linux-firmware MR pending
MediaTek's redistribution sign-off. The driver fixes are in mainline around
kernel 7.1, but the firmware is the real gate, so this is not a flake bump away.
Wired pads and USB dongles both work today — see
[the controllers guide](guides/htpc-controllers.md), which carries the two
one-line checks to re-run after a future bump.

**A Flirc USB IR receiver for the SofaBaton X1S.** Demoted here from M10 when
Kodi was dropped (2026-08-20) — it was bundled with Kodi but is orthogonal to
every media UI, and the couch still needs something a remote can drive.

The remote speaks Bluetooth only to its own hub, and its generic BT-keyboard
profile is unreliable against PCs. Flirc presents as a plain **USB HID
keyboard**, so keybinds work identically under gamescope, under Bigscreen, and
under any future shell — nothing configured for it is thrown away by a shell
decision, which is exactly why it outlived the milestone it arrived in. On this
machine it is worth more than it would be elsewhere: the MT7927 blocker above
means on-board Bluetooth is dead until MediaTek's firmware redistribution
clears, so an input path that does not depend on Bluetooth at all is the only
one that works today.

Gated on hardware lgo has to buy, and it may well be zero-config in NixOS —
verify that rather than inventing a module to have something to show. Whatever
lands goes in [the controllers guide](guides/htpc-controllers.md).

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

**Migrate the VCS workflow from git/gh to jj (Jujutsu), git-backed.** Colocated
(`jj git init --colocate`), so `.git` stays authoritative and `gh` keeps working
for PRs — nothing about GitHub, CI, or `clan machines update` changes. This is a
change to how *we* drive the repo, not to what the repo is.

Why it is worth doing here specifically: this repo's workflow is
branch-per-change with mandatory PRs and frequent small doc/config commits, and
several of this session's stumbles were git-shaped rather than
substance-shaped — a `--delete-branch` that pulled the branch out from under an
in-flight edit and left an amend landing on `main`, a rebase conflict from two
PRs touching adjacent rows of the same table, and repeated
`commit --amend` + `push --force-with-lease` cycles to keep one PR tidy. jj's
model (no index, no detached HEAD, every edit already a revision, first-class
conflicts that don't block you, trivial history rewriting) removes the class
rather than the instances.

Scope, which is mostly documentation:

- **`CLAUDE.md` "Git Workflow"** — the single most important file to rewrite.
  The branch-prefix table stays (it drives PR titles and the roadmap), but the
  mechanics change: `jj new`, `jj describe`, `jj bookmark set`,
  `jj git push --bookmark`. Keep the invariants stated as invariants — never
  land directly on `main`, PR via `gh pr create` — because they survive the tool
  change.
- **`docs/guides/accepting-pull-requests.md`** and any runbook step that spells
  out git commands.
- **The devShell** (`flake.nix`): add `jj`, and decide what happens to the
  `push` helper, which exists because `~/.config/git` is a read-only
  impermanence bind mount and reads the gh token at runtime. jj needs the
  equivalent, and that is the one genuinely fiddly part.
- **Impermanence**: `~/.config/jj` needs a persist entry, mirroring
  `~/.config/git`.
- **The milestone prompts below**, which name git commands verbatim.

Open questions to settle when it is picked up: whether Claude sessions should
drive jj or keep using git against the same colocated repo (both work; mixing
them in one session is where confusion would come from), and whether
`git config` signing carries over — note commits in this repo already need
`--no-gpg-sign`.

Not urgent, and deliberately not bundled with any ernst milestone: a VCS
migration that lands mid-buildout would make every subsequent PR harder to
review. Best done between milestones, in one pass, with the docs rewritten in
the same PR.

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

**MediathekViewDL needs a writable path.** Jellyfin's two library binds are both
`isReadOnly = true`, and `machines/ernst/containers/jellyfin.nix` states the
reason as a fact about the service: *"RO on both — Jellyfin never writes to
library data."* The plugin makes that false. It needs a third bind, RW, mapped
to something like `/media/Server001/Mediathek` so it fits the legacy path scheme
the imported database already uses — and **the header claim has to be corrected
in the same PR**, not left standing next to a bind that contradicts it.

*On the location, one correction.* A plain subdirectory under `/srv/media` is
not a problem to be avoided — it is exactly what invariant #2 prescribes. What
that invariant forbids is a **sub-dataset**, because hardlinks cannot cross a
dataset boundary; plain subdirectories are the prescribed shape, and `library/`
and `torrents/` already are ones. Nothing is "entering the *arr hardlink domain"
by sitting there: the domain is a property the single dataset provides, and
content nothing hardlinks simply never uses it. So `/srv/media/mediathek` as a
sibling of `library/` is compliant, and no invariant argues against it.

*The real question is snapshots, and it is not the one it looks like.*
`/srv/media` carries `com.sun:auto-snapshot=false`. For M9's YouTube downloads
that is fine and the entry says so — the content is re-downloadable. **Mediathek
content is not.** German public-broadcaster material has a legally mandated
availability window and is depublished when it expires, which is the entire
reason anyone downloads it. So the two options are not equivalent:

- `/srv/media/mediathek`, plain subdirectory. One bind, no disko change,
  invariant-compliant, **no snapshots**.
- `/srv/mediathek`, its own dataset with `com.sun:auto-snapshot=true`, matching
  the `/srv/unsorted` + `/srv/gardens` precedent from #66. Genuinely outside
  `/srv/media`. Costs a disko change and a dataset created on a live pool.

Recommend the first, and settle it **when this is picked up rather than later** —
the two paths are on different datasets, so changing your mind afterwards is a
full copy of the data, not a rename.

*Ownership: `root:media` 2770, and the existing config already decides this.*
The container's `jellyfin` user is **already** a member of `media` (gid 3000,
numerically identical host-side and in-container, since nspawn does not remap
gids), so the setgid pattern used for the *arr-managed subdirs works with no
additional plumbing, and new files inherit `gid=media` and stay group-writable.
Owning the directory `964:964` instead would work today and buy nothing, at the
cost of a second ownership scheme in one tree and a directory the fleet media
consumers `jellyfin.nix` already anticipates — Nextcloud external storage, the
*arr suite — cannot read.

*Library layout: a separate Jellyfin section, not a scan folder bolted onto the
existing ones.* Broadcast titles match TMDB poorly, so pointing the curated
library at this path pollutes it with mismatched metadata; a separate section
gets its own content type, metadata providers and scan schedule, and keeps the
one RW path visibly distinct from the two RO ones.

Two implementation notes for whoever picks it up: the new directory must be
added to **both** the `systemd.tmpfiles.rules` list and the explicit path lists
in `jellyfin-library-perms`, which enumerates directories rather than globbing;
and this is the first RW media bind, so it is worth checking nothing else in the
file reasons from the RO assumption.

Small enough that it does not need a number. Either fold it into whichever
Jellyfin-adjacent milestone is being worked when it comes up — M2b touches this
file already — or take it as a standalone `fix/` PR.

**Expose Ollama via Traefik.** Reopens the native-vs-container decision: Ollama
runs as a host service today because ROCm wants the card directly. Putting it
behind Traefik means deciding whether it stays native with a route pointed at the
host, or moves into a container with GPU access plumbed through.

**Un-parking Bigscreen.** Three routes now, and only the third does not require
conceding an invariant. The container diagnosis is settled and recorded in the
[status table](#current-state) — logind user units, KWin needing an active
graphical seat, a container unable to supply one — and #64's machinery is kept
because every route below reuses it. Do not re-derive it.

*Plasma 6.7.4 on the host.* Real seat, real VT, both requirements satisfied at
once. Costs ernst's desktop tracking floating unstable and diverging from the
fleet, which invariant #6 exists to prevent.

*A VM with the dGPU passed through.* Real seat, no fighting. VFIO binds the card
exclusively, taking it from ROCm/Ollama whenever the TV session runs — the
mutually-exclusive outcome invariant #5 and `clan.nix` explicitly reject.

*Build only the shell, out-of-tree, against the stable KDE scope.*
`pkgs/plasma-bigscreen.nix`, called via `kdePackages.callPackage` so
`mkKdeDerivation`, `plasma-workspace`, `plasma-nano`, `milou` and `kscreen` all
resolve to the 6.6.6 set already on the machine. Packaging reference:
[NixOS/nixpkgs#428353](https://github.com/NixOS/nixpkgs/pull/428353). Nothing
floats, nothing is VFIO-bound, and it needs **no new flake input** — the source
is a `fetchurl`, not an input. That is the whole argument for it: the other two
routes each buy a working Bigscreen by giving up an invariant, and this one does
not.

What it costs is honesty about version skew. KDE hard-asserts that the shell's
Plasma version matches the workspace it runs against, so the build has to
rewrite `PROJECT_VERSION` — a 6.7-era shell on a 6.6.6 workspace. Patching the
version string gets past the assert; it does not make the API compatible.
Expect to bisect. There is no binary cache for it, so it recompiles locally on
every KDE bump, and it is out-of-tree code we own until 26.11 ships
`kdePackages.plasma-bigscreen` in-tree — at which point the file is deleted.

The fallback if that skew bites: pre-release Bigscreen snapshots from
Feb–Mar 2026 carry `PROJECT_VERSION` `6.5.80`, the 6.6 beta, so they target 6.6
natively and have **zero** skew against 6.6.6 — a less polished shell with a far
smaller compatibility surface. Try the 6.7.x release first and drop back to a
snapshot on QML import errors rather than fighting them.

The gap that makes any of this necessary, verified 2026-08-20 by eval against
ernst's own package set:

```
system.nixos.release            -> 26.05
kdePackages.plasma-workspace    -> 6.6.6
kdePackages ? plasma-bigscreen  -> false
```

Bigscreen shipped with Plasma 6.7, released 2026-06-16 — after 26.05 branched —
so the attribute does not exist in ernst's pin at all. Everything the third
route would build *against* does resolve there, which is what makes it worth
listing rather than dismissing.

**Settled 2026-08-20: it stays backlog until it renders on the TV, then
graduates to a numbered milestone.** A derivation that does not work yet is a
package experiment with no fleet consequences and no operator steps — nothing
for a milestone to sequence. The moment it works it stops being that: it changes
what the TV runs, needs a session-switcher arm, and touches
`modules/roles/htpc.nix`. This section's own rule is that an item becomes a
milestone when it earns one, and the build succeeding is what earns it.
