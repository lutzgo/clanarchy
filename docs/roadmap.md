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

Verified against the repo on 2026-08-25 (`main` @ `133a39d`).

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
| M3 — VPN microvm + qBittorrent | **done — deployed 2026-08-20** | [#83](https://github.com/lutzgo/clanarchy/pull/83) | `wg-qbittorrent` on the microvm tier: tap on VLAN 90, IVPN wg-quick tunnel, guest-side nftables killswitch. **Killswitch proven**: with wg0 down the guest emitted zero packets and DNS failed rather than leaking. **Hardlink chain proven**, with a negative control — `UMask=0002` is what M4 depends on. Three things had to be fixed after the first deploy: wg-quick wins any routing-rule priority race, a tmpfiles/oneshot contradiction in `jellyfin.nix` had been silently resetting the media directory modes since M2b, and the UDM-Pro policy editor has two Port sections. [M3](#m3-featernst-vpn-microvm-done-deployed-2026-08-20) |
| M4 — arr stack | **done — deployed, proven, and survived an unplanned power cut 2026-08-21** | [#85](https://github.com/lutzgo/clanarchy/pull/85) | Prowlarr/Sonarr/Radarr in one nspawn container, `machines/ernst/containers/arr.nix`. **Departs from its own prompt on networking**: veth on br0 / VLAN 90 (MAC `02:00:00:90:00:05`, `10.0.90.13`) rather than the host-networking v1 the prompt described, because that prompt predates M2b and `networking.nix` already names M4 as a pattern-B consumer. Consequence worth knowing: the arr reaches qBittorrent at L2 over `br0`, so **the UDM-Pro never sees that traffic** and the ZBF rule the prompt listed as a manual step does not exist — the guest's `api_clients` nftables set is the only thing enforcing it. The milestone is **not** done until the `stat` proof runs on ernst. [M4](#m4-featernst-arr-stack) |
| M5 — Traefik | **done — deployed 2026-08-23, proven 2026-08-24** | [#86](https://github.com/lutzgo/clanarchy/pull/86) | `machines/ernst/containers/traefik.nix`: nspawn container on `vb-traefik`, VLAN 90, MAC `02:00:00:90:00:04` → `10.0.90.12`. One wildcard `*.goclan.org` over ACME DNS-01 at Cloudflare, scoped API token via clan var `traefik-acme`, store on `zdata` at `/srv/state/traefik`. Routes: jellyfin (no middleware, ever) + prowlarr/sonarr/radarr behind the interim `mgmt-only` ipAllowList (L5). **Backend bypass hardening is mechanism (a)** — each backend's own firewall accepts its web port only from `10.0.90.12` — because Jellyfin, the arr, qBittorrent and Traefik are all ports on `br0` and their traffic never reaches the UDM-Pro, so an intra-zone ZBF rule could not see it. **Two consequences on deploy day**: direct access to `10.0.90.10:8096` and `10.0.90.13:{9696,8989,7878}` stops working immediately, so TV clients must move to `jellyfin.goclan.org` in the same window; and the ACME propagation check queries `1.1.1.1`/`9.9.9.9` directly, which a UDM-Pro DNS-interception rule would silently break. [M5](#m5-featernst-traefik) |
| M6 — monitoring | **done — deployed, alerting proven end to end, and survived a real reboot 2026-08-24; biene/birte pending** | [#87](https://github.com/lutzgo/clanarchy/pull/87) | **Working**: container on `10.0.90.14`, VLAN 90 won unaided, every deployed target scraping `up`, Grafana served through Traefik, and `traefik_tls_certs_not_after` (89 d) + `zfs_pool_health` (0/0) both confirmed **live** — retiring the two metric names that had only been read out of binaries' strings. **Notifications arrive**, from both publishers, on rotated topics — the first confirmed ntfy delivery in this fleet's history. **Survived a real reboot**: `mon0` and `vb-monitoring` created by a boot rather than a deploy, container back on `.14`, the TSDB holding pre-reboot samples, `clanarchy-impermanence-check` green — which closes invariant #7 for this milestone and the `mon0`-across-a-reboot question inherited from M2b. **Three deploys, each caught a real defect.** The first stopped at `monitoring-secrets`, by design — and the value it refused exposed that `modules/observability/zfs-ntfy.nix`'s zedlet **has never worked on ernst**: the var holds a bare topic (what the prompt's own `openssl rand -hex 12` hint produces), curl could not resolve it as a hostname, and `>/dev/null 2>&1` threw the error away. The second exposed that **`systemd-networkd-wait-online` could never succeed in this container** — a veth has no carrier until both ends are up, and `mon0`'s host end is brought up by `postStart`, which runs *after* the container's boot, so wait-online was waiting on an event its own completion gates. The 20 s cap contained it; `RequiredForOnline = "no"` fixes it. [Details](#first-deploy-2026-08-24-the-fail-closed-path-fired-and-it-found-an-older-bug). `service-modules/monitoring.nix` (+ `.md`, + one dashboard as JSON): a clan service module with a `client` role on all four machines and a `server` role on ernst. **Scrape targets are derived from `roles.client` membership** — each machine's address comes from the `zerotier-ip-<machine>-zerotier` var clan-core already generates, so adding a machine to the role is the only step needed. The stack is one nspawn container on `vb-monitoring`, VLAN 90, MAC `02:00:00:90:00:06` → `10.0.90.14`, state on `zdata` at `/srv/state/monitoring`. **The one genuinely new piece of engineering is a SECOND interface**: `mon0`, a point-to-point ULA veth to the host, because both things Prometheus must scrape — ernst's own exporters (VLAN 50) and three laptops (ZeroTier, which terminates in the host netns) — are unreachable from VLAN 90. The host forwards and SNATs onto `zt+`, which has the useful side effect that scrapes arrive at a laptop from ernst's own ZeroTier address, i.e. the one source each client permits. **Alerting is (b), keep both**, with the overlap made empty: ZED owns pool state, Prometheus owns everything else and has no `zfs_pool_health` rule, and `ZedNotRunning` is the interlock. Both end at the same ntfy topic. [M6](#m6-featmonitoring) |
| M7 — Authelia | **done — deployed 2026-08-24; both accounts enrolled on TOTP + WebAuthn; L5 retired in code and in the device; Grafana OIDC and the reboot still pending** | [#90](https://github.com/lutzgo/clanarchy/pull/90) | Authelia 4.39 in an nspawn container, `machines/ernst/containers/authelia.nix`, on `vb-authelia` / VLAN 90 / MAC `02:00:00:90:00:07` → `10.0.90.15`, SQLite on `zdata` at `/srv/state/authelia`. **L5 is retired by deletion, not by stacking** — the `mgmt-only` ipAllowList is gone from `containers/traefik.nix` and the four admin routers carry a `forwardAuth` middleware instead. The cost is stated rather than buried: the login portal is now reachable from the IoT VLAN, because the `Allow Traefik` ZBF rule already permits IoT → `10.0.90.12:443`; what it meets there is `two_factor` plus regulation (3 failures / 5 min → 15 min ban, per user, in SQLite). **The bypass list the brief asked for came back EMPTY**, and that is a finding: `auth.goclan.org` carries no middleware on its own router, so `/api/oidc/*`, `/.well-known/*` and `/api/health` never pass through forward-auth in the first place — a `bypass` rule would match nothing and read as enforcement. Grafana moves to Authelia OIDC with its local admin kept, and **break-glass needed one new line to be true at all**: with the Grafana route behind forward-auth, the local form is unreachable through Traefik, so `10.0.90.14:3000` now also accepts `fdca:fe90::1` — the host end of M6's `mon0` — reachable only as `ssh -N -L 3000:[fdca:fe90::2]:3000 root@ernst`. **Proven offline against the real 4.39.20 binary**: the rendered config, the staged OIDC client block, the generated `users_database.yml` and the JWKS fragment all pass `authelia validate-config`, and all three vars generators were run end to end. [M7](#m7-featernst-authelia) |
| M8 — Tvheadend / SAT>IP live TV | **built, awaiting deploy — 2026-08-27; Phase 0 cleared the same day with live evidence** | — | lgo opened the scope gate deliberately (live TV wanted alongside MediathekArr) and Phase 0 cleared interactively: `DVBC-4` in `satipdesc.xml`, all 8 probed muxes lock, ZDF HD captured end-to-end (13.7 MB / 12 s, h264 720p50 + 2× AC-3 + EIT in-mux). **Two premises fell in the build session**: nixpkgs **removed tvheadend entirely** (PR #332259), so it is a from-source build (`--disable-libav` — the FFmpeg-4 coupling that killed it upstream is transcoding-only, which Jellyfin owns); and the FRITZ!Box is **directly cabled to ernst's spare NIC** (`enp12s0` → `br-fritz` → container `fritz0`), so no UniFi VLAN, no ZBF rule, and **L6/L7 retired as never-created**. Interleaved-TCP RTP is 461-rejected by the box — UDP unicast, one firewall line. Shape **(ii)**: Tvheadend shares tuners + EPG, **Jellyfin's DVR records** into `/srv/media/library/recordings`. [M8](#m8-featernst-tvheadend) |
| M9 — TubeSync | **open** | — | Feeds the Jellyfin library directly. First occupant of the **podman** tier (not in nixpkgs — verified), so it builds the tier as well as the service; podman's attachment to `br0` is unsolved here. [M9](#m9-featernst-tubesync) |
| M10 — Kodi + IR remote | **dropped — 2026-08-20** | — | Dropped by lgo before any code was written: the couch requirement is Plasma Bigscreen plus Steam, and Kodi is a third media UI nobody asked for. The IR-receiver half was orthogonal and survives as a [backlog entry](#floating-backlog) |
| M11 — fleet-local coding agent | **open — Parts 2/3/4 done 2026-08-26; Part 1 outstanding** | — | Phase 0 (2026-08-25) falsified three of the brief's premises and proved the context trap with numbers. Since then: the **§7 Nix landed** as per-machine role settings, closing [SN1](#sn1-the-model-tag-silently-sets-the-context-window); candidate (C) is an explicit **"not taking"**; and Part 3's tool-call defect is **fixed** — but not as predicted. There is **no Modelfile template to correct** (compiled Go renderer/parser), the parser is **correct**, and the model was dropping the opening `<tool_call>` tag; restating it in the system prompt went 5/40 → **80/80**. A new confound surfaced: **`q8_0` halves tool-call reliability** without that rule. **Phase 1 stays blocked on Part 1** — the multi-file edit, the Claude Code comparison and real-task rates are lgo's. Tasks and a validated grader now exist at `~/.local/share/m11-bakeoff/tasks/`. [M11](#m11-featfleet-local-coding-agent) |
| M12 — arr helpers | **done — deployed and merged 2026-08-26 (#100); (a) Byparr split out as [M12b](#m12b-featernst-byparr)** | — | UmlautAdaptarr, Bazarr, Cleanuparr, MediathekArr and the recyclarr additions all landed inside the **existing** arr container, with no new veth, MAC, DHCP reservation or UDM-Pro work — so the hand-rolled-derivation approach M14 depends on is proven. All five units active on ernst. **Four of the six premises did not survive checking**: Byparr is no longer Camoufox-based and is a browser-packaging job in its own right; **MediathekArr is TWO processes**, and upstream's `main` is a diverged, older tree than its own release tag; **Unpackerr is measured out**; and **UmlautAdaptarr is inert here** — all six indexers are Cardigann HTML scrapers, which it architecturally cannot serve. **One thing is still outstanding**: the first real recyclarr sync fires at 00:03 the night of 2026-08-26 and is what adopts Sonarr's existing `Remux + WEB 2160p` (59 series) — see [the profile census](#the-profile-census-re-measured--and-one-number-this-repo-had-wrong). Depends on M4. [M12](#m12-featernst-arr-helpers) |
| M12c — library profile reassignment | **open — requested 2026-08-26** | — | Recyclarr creates profiles but **never assigns a title to one**, and this library's titles predate the guides. Rules for "high" and "low" quality per shows/films settled by **Q&A first**, then an agent reassigns title by title. **The hazard is the film side**: 2389 of 2432 movies sit on a non-upgrading `Ultra-HD` profile, and every TRaSH profile is upgrade-enabled — a bad rule moves them all and queues most of 13 TB through the VPN. Demotions first, promotions in watched batches, search-on-edit OFF. Depends on M12. [M12c](#m12c--library-profile-reassignment) |
| M13 — media lifecycle | **built, awaiting deploy — 2026-08-26** | — | Jellyseerr (internal scope), Janitorr (dry-run) and Scraparr all land in the **existing** arr container; three M6 exporter targets, not four. **Janitorr publishes no artifact at all** — GitHub releases carry zero assets and the only channel is a Paketo OCI image — so it is the repo's first from-source **Gradle/Spring Boot 4** build, with a committed 350-artifact mitm-cache lock. **Three roadmap premises did not survive checking**: `services.jellyseerr` is now a renamed alias for **`services.seerr`**; **Ollama serves no `/metrics`** (404, measured), so its target is dropped and handed to M15 with the reasoning; and **Jellystat is deferred** — it needs PostgreSQL, and Janitorr's own docs now recommend `janitorr-stats` instead. Janitorr also has **no web UI**, so its port is bound to loopback and routed nowhere. Depends on M6. [M13](#m13-featernst-media-lifecycle) |
| M14 — libraries | **open** | — | Lidarr + slskd + Soularr, Kapowarr, Questarr, Audiobookshelf, Storyteller. Introduces a **second write path** into `/srv/media`, so it owes its own hardlink proof with a negative control — M3's does not transfer. Depends on M12. [M14](#m14-featernst-libraries) |
| M15 — Tdarr / space reclamation | **open** | — | Its own container with VAAPI on the 7900 XTX, plus GPU arbitration against a card that now has three other claimants. **M11's VRAM numbers changed this materially**: a fully-resident Ollama at 64k leaves ~2 GB, so CPU-only Tdarr is now a serious default rather than a fallback — and Muxarr must be evaluated first, because it may reclaim more per CPU-hour with no GPU question at all. Depends on M12. [M15](#m15-featernst-tdarr) |
| M16 — external ingress | **open** | — | Make `jellyseerr.goclan.org` reachable from the internet, and **only** that. First service accepting connections from outside the home network, so the milestone is about the boundary rather than the service. Creates a permanent bypass row under invariant #4. Depends on M13. [M16](#m16-featernst-external-ingress) |

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

## Standing notes

Not invariants — an invariant is a property of the **system** that a milestone
must design around. These are properties of the **ground** a milestone stands
on: hazards that live in a file somebody will edit for an unrelated reason, and
decisions the fleet owes itself but has not made. They are here rather than
inside the milestone that discovered them precisely because the person who trips
over them will not be reading that milestone.

### SN1 — The model tag silently sets the context window

**Ollama derives `num_ctx` from the model when it is not set explicitly.**
Measured on 2026-08-25: `qwen3-coder:30b` on ernst → **32768**;
`qwen2.5-coder:7b` on miralda → **4096**. So editing the `models` list in
`clan.nix` — which is what `service-modules/local-ai.nix`'s `models` option
invites — **changes the context window fleet-wide, with no diff that shows it.**
A one-word edit that reads as "use the smaller model" is actually "quarter the
context and break tool calling", and nothing in the review says so.

The consequence is not degraded output, which is what makes it dangerous.
Measured at `num_ctx = 8192`: a **17,083-token** file (`containers/arr.nix`) was
silently truncated to **4,098** tokens. HTTP 200, no flag, no warning anywhere in
the response. Truncation **keeps the tail and drops the head** at roughly
`num_ctx/2` — and the system message and tool definitions live at the front, so
**tool calling went to 0/6**. Asked for a fact from the dropped head, the model
did not decline: it **invented a plausible, placeholder-shaped MAC address**
(`00:11:22:33:44:55` in place of `02:00:00:90:00:05`) — precisely the kind of
value that survives a skim of a diff.

**So `num_ctx` must be set explicitly wherever the model is declared, and the
two must be reviewed together.** A model-tag change is a context change until
proven otherwise.

**CLOSED 2026-08-26 at the place the hazard lives.** `roles.ollama` now carries
a `contextLength` setting and both machines set it explicitly — ernst 32768,
miralda 4096. The window no longer moves when `models` is edited, and the two
now sit adjacent in `clan.nix` so a review sees both. The hazard is recorded
rather than deleted because it returns the moment a **new** machine joins
`roles.ollama` without setting it: the option defaults to `null`, which restores
exactly the model-derived behaviour above. **Adding a machine to that role means
setting its context.**

A second hazard of the same shape was found while closing this one and is worth
reading together with it: `kvCacheType = "q8_0"` roughly **halves tool-call
reliability** (83% → 38%) unless the client's system prompt explicitly demands
the `<tool_call>` wrapper — a server-side VRAM optimisation whose cost lands in
a different component and appears in no readback. Measured, interleaved, n=30
per arm. Both are documented in `service-modules/local-ai.md`.

Cross-referenced from [M11](#m11-featfleet-local-coding-agent) (which measured
it) and [M15](#m15-featernst-tdarr) (whose entire VRAM budget depends on it).

### SN2 — IPv6 is off, and that is now a decision

**ernst's connection is a static full IP stack** — static public IPv4 *and*
native IPv6, no CGNAT, no DS-Lite. Confirmed by lgo, 2026-08. Every milestone to
date was written as if the fleet were v4-only, and until now nothing forced the
question.

**What the repo does today.** Every container sets `IPv6AcceptRA = false` and
takes DHCPv4 only — `containers/jellyfin.nix`, `arr.nix`, `traefik.nix`,
`authelia.nix`, the monitoring container, and the microvm guest, which disables
v6 outright (M3 records that wg-quick aborts under `set -e` on a dual-stack
`Address` line). VLAN 90 carries no GUA. The one v6 in the fleet is M6's `mon0`,
a point-to-point ULA veth to the host — deliberate, scoped, and not what this
note is about.

**That uniformity is an accident, not a decision.** It propagated by copying
M2b's working pattern into every subsequent container. No milestone argued for
it, and no milestone has ever tested it.

**The hazard, precisely.** The v4 security model rests on UDM-Pro ZBF policies
and — implicitly, unexamined — on RFC1918 plus NAT as a backstop. That backstop
is why a ZBF mistake has so far cost reachability *from another VLAN* rather than
*from the internet*: M5 lost a round to `Servers` missing from a source list and
the failure was a timeout, not an exposure. **IPv6 has no NAT and no equivalent
backstop.** If RAs ever reach VLAN 90, every container becomes globally
addressable the moment it accepts one, and the only thing between the internet
and the arr container's `8989` is the UDM-Pro's **IPv6** firewall — a *different*
rule set from the v4 policies this repo has maintained and corrected since M2,
and one **no milestone has ever audited**. The failure would be silent: nothing
in the fleet monitors for an unexpected GUA.

**Measured 2026-08-25, on ernst and in every container** — the baseline this note
exists to be checked against:

```
ip -6 addr show                                  # on ernst
  br0            fe80::b08b:e1ff:fef2:1e7c/64          link-local only
  mon0           fdca:fe90::1/128                      M6's ULA, host end
  ztzavl64zk     fdda:106a:123a:d561:…:711f/88         ZeroTier rfc4193
  enp13s0        (no inet6 at all — bridge port)

nixos-container run <c> -- ip -6 addr show eth0
  jellyfin       fe80::ff:fe90:2/64                    link-local only
  traefik        fe80::ff:fe90:4/64                    link-local only
  arr            fe80::ff:fe90:5/64                    link-local only
  monitoring     fe80::ff:fe90:6/64                    link-local only
  authelia       fe80::ff:fe90:7/64                    link-local only
```

**Link-local only, everywhere. No GUA anywhere on VLAN 90, and none on the host
either** — ernst holds no ISP-delegated v6 address at all today. So the native-v6
half of the connection is, at the fleet's edge, entirely unused. That is the safe
state and it is the *current* state; it is not a state anything defends.

**A GUA anywhere on VLAN 90 makes this an incident, not a note.** Re-run the
block above before believing otherwise.

**The decision owed, either answer acceptable:**

- **(a) VLAN 90 is v4-only, deliberately and permanently.** `IPv6AcceptRA = false`
  is promoted from a copied line to an invariant with a stated reason, and the
  next container that omits it is a review comment rather than an accident.
- **(b) IPv6 is supported**, in which case the UDM-Pro's v6 ruleset is audited,
  proven default-deny inbound, and maintained in parallel from then on — a
  standing cost, not a one-time one.

**Not decided here.** Recorded as owed.

**Triggers**, any of which forces it: [M16](#m16-featernst-external-ingress)
choosing the port forward (the tunnel sidesteps v6 entirely); any milestone
setting `IPv6AcceptRA = true` on VLAN 90; any UDM-Pro change enabling RAs or
DHCPv6 on the Services network; any service needing v6 reachability from outside.

Cross-referenced from [M16](#m16-featernst-external-ingress) and
[Floating / backlog](#floating-backlog).

### SN3 — A broken instrument is indistinguishable from a bad result

M11's session very nearly recorded a tool-calling score of **0/10** for
`qwen3-coder:30b` and wrote the conclusion that follows from it. The true score
was **28/40**. The difference was a `jq` scoping bug in the session's *own*
grader (`$a|has(.)` rebinds `.` to `$a`) — a defect in the measuring apparatus,
producing a damning number about the thing being measured.

That is the same epistemics as SN1's truncation finding, seen from the other
side. There, a silently truncated context is indistinguishable from a stupid
model. Here, a silently broken grader is indistinguishable from a stupid model.
In both cases the observation is confident, internally consistent, and about the
wrong subject.

**This repo already knows the answer and has paid for it twice.** M3's synthetic
hardlink proof carries a **negative control** — the same file at `0644`, which
*must* fail with `EPERM` — for exactly this reason: without it, the test cannot
distinguish a working chain from root bypassing the check, which is what an
earlier revision of M3's own plan did. M6 found a zedlet that had never once
delivered a notification, because it discarded curl's stderr and therefore could
not report its own failure.

**The rule: check the instrument before believing a number, and especially
before believing a number that confirms what you expected.** A measurement that
agrees with the prediction gets less scrutiny than one that contradicts it, which
is precisely backwards — the confirming result is the one whose harness nobody
re-reads. In practice this means: a negative control wherever one is possible
(M14 owes one and its prompt says so), and a sanity path wherever one is not.

**Why this is a standing note and not a tenth invariant.** The nine invariants
are each a property of the *system* with a *mechanism* behind it — a dataset
boundary, a firewall rule, a tier, a directory. A milestone respects them in its
**design**. This is a rule about **method**, it binds every milestone's test plan
rather than any milestone's architecture, and it has no mechanism to point at.
Filing it as invariant #10 would dilute a list whose value is that every entry
names something concrete you can go and check.

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
| L5 | Traefik `ipAllowList` on the arr + Grafana routes (mgmt + wg-travel) | M5 (`traefik` container) | There is no identity provider yet | **M7** — replaced by the Authelia forward-auth middleware | **RETIRED 2026-08-24 by M7 ([#90](https://github.com/lutzgo/clanarchy/pull/90)) — in code AND on the device. Re-verified 2026-08-25**, because this row's own trigger had fired and a row left in the future tense is a row nobody can tell the state of: `grep -n ipAllowList machines/ernst/containers/traefik.nix` returns **four comments and no definition**, and the four routers that carried it (`prowlarr`, `sonarr`, `radarr`, `grafana`) each carry `middlewares = [ "authelia" ]` instead. The deploy that made it effective happened the same day — `https://sonarr.goclan.org/` answered `302 → auth.goclan.org/?rd=…`, which is the middleware and not the ACL. **Nothing is left to remove**; the resolution owed by [L4's reasoning](#interim-rule-ledger) (a permit rule doing nothing is what someone later "fixes" by removing the restriction) is that the shim is gone rather than inert. Created in [#86](https://github.com/lutzgo/clanarchy/pull/86) as middleware `mgmt-only`, `sourceRange = 10.0.10.0/24, 10.0.50.0/24, 10.0.70.0/24`; extended to a fourth router (Grafana) by [#87](https://github.com/lutzgo/clanarchy/pull/87). **Deleted, not stacked underneath forward-auth** — the option this row's own notes raised. The argument, in full in `containers/authelia.nix`: an IP allow-list under an identity provider means valid credentials plus a correct TOTP code still fail from anywhere nobody pre-declared, which is most of what the identity provider was added for; and two mechanisms for one property is what `containers/traefik.nix` argues against in its own words. Both warnings this row carried were honoured — `trustForwardHeader = false` on the new middleware keeps the peer-address semantics and still ignores client-supplied `X-Forwarded-*` (Traefik writes those itself from the real request either way), and the VLAN 70 lockout it warned about is moot because the replacement does not filter by source at all. **What is lost with it**: the arr and Grafana login surfaces are now visible from the IoT VLAN. That is the trade, and the compensating control is Authelia's per-user regulation, not a network ACL |
| L6 | Tvheadend ports `9981` / `9982` on the host, mgmt-VLAN scoped | M8 (host firewall, v1) | Only if M8 lands before M2b — Tvheadend v1 would then run on host networking like Jellyfin's and arr's did | **M5** for the web route, plus a veth migration mirroring M2b. Never created at all if M2b lands first | **RETIRED as never-created (M8 built 2026-08-27).** M2b landed first, so Tvheadend never ran on host networking; it went straight to a veth on VLAN 90 plus a Traefik route, exactly as this row predicted. 9982 (HTSP) ended up opened to nobody at all — no client for it exists in this fleet |
| L7 | FRITZ!Box → Tvheadend on the ephemeral **UDP** range | UDM-Pro ZBF (off-repo), M8 | SAT>IP media is unicast RTP on a return flow the RTSP rule does not cover | Proving RTP **interleaved over the RTSP TCP connection**, which reduces the whole ACL to TCP 49000 + 554 | **RETIRED as never-created (M8 built 2026-08-27), by a route this row did not predict.** Phase 0 measured interleaved-TCP as UNAVAILABLE — the 6591 answers `461 Unsupported Transport` to a TCP SETUP — so the "avoid" path was closed. But the FRITZ!Box ended up **directly cabled to ernst's spare NIC** (`enp12s0` → `br-fritz`), so the RTP return flow never crosses the UDM-Pro at all: the "broad, ugly" ephemeral-UDP ACL became one source-scoped iptables line inside the tvheadend container (`-s 192.168.178.1 -p udp`). No UDM-Pro rule of any kind exists for M8 |
| — | **M11 creates no row, and that is a property worth stating** | — | Ollama on ernst stays bound to localhost and is reached over an SSH tunnel on local port **11435**; the working tree was left at `133a39d`. So the milestone that added a coding agent to the fleet changed ernst's attack surface **not at all**, and if it stops after Phase 1 it stays that way | **permanent, unless M11 Phase 2 is taken** — and Phase 2 is optional and separately justified. Its trigger is a *second client actually needing it*, not tidiness | not created. Listed so a later session does not read the absence as an oversight. **If Phase 2 is ever taken, read [M11's session prompt](#the-prompt-for-the-m11-remainder) first** — its Phase 2 block is the constraint: Ollama has no authentication and its API includes model *pull* and *delete*, so it is an unauthenticated admin endpoint and the recommendation is ZeroTier-only, never a LAN listener |
| — | **M12 created no row, as predicted — confirmed 2026-08-26** | — | Everything in M12 landed inside the **existing** arr container and opened no port reachable outside it. The one thing it *did* touch is the explicit port list `containers/arr.nix` feeds to its `concatMapStrings` Traefik source-restriction, which gained `bazarr` 6767, `cleanuparr` 11011 and `mediathekarr` 5007 — plus three ordinary Traefik routers behind `authelia` and three names in `protectedHosts`, which are invariant #3 working as designed and not shims. **Four ports were deliberately kept OFF the list**: `flaresolverr` 8191 as before, MediathekArr's indexer 5008, and UmlautAdaptarr's 5005 and **5006**. All four bind `0.0.0.0`/`[::]`, so the container firewall is the only thing keeping them off VLAN 90 — and 5006 is an HTTP proxy, the same class of gift as 8191. Byparr, when [M12b](#m12b-featernst-byparr) lands, inherits FlareSolverr's exact posture | **permanent** — there is nothing interim here | not created |
| L8 | TubeSync web UI port, mgmt-VLAN scoped | M9 (host/container firewall, v1) | Only if M9 lands before M5 — an admin UI with no proxy in front of it yet. Mgmt-scoped, so invariant #3 does not cover it | **M5** — replace with the Traefik route. Never created at all if M5 lands first | **never created — M5 landed first.** M9 gets a Traefik route (`tubesync.goclan.org`, behind the `authelia` forward-auth middleware — M7 deleted `mgmt-only`, so copy the *arr routers, not this row's original wording) and opens no port. Adding it also means adding the hostname to `access_control` in `containers/authelia.nix`, which is deny-by-default: a route with the middleware and no matching rule fails closed. Note this does not solve M9's actual open question, which is how a podman container attaches to `br0` on VLAN 90 at all |
| — | **M13's Jellyseerr and M15's Tdarr routes** | Traefik (`containers/traefik.nix`), M13 and M15 | Both are ordinary Traefik routers on names the M5 wildcard already covers, riding the permanent `Allow Traefik` rule. **Neither is a shim** — listed so nobody creates a ledger row for a route | **permanent** — this is invariant #3 working as designed, not an exception to it | not created. **Two corrections against older wording**: M13's Jellyseerr router deliberately carries **no** middleware (it is a household service and its posture is Jellyseerr's own Jellyfin-account login — see M13), and M15's Tdarr router carries **`authelia`**, not `mgmt-only`, because M7 deleted `mgmt-only` (L5). Copy the *arr routers. Adding either hostname also means adding it to `access_control` in `containers/authelia.nix`, which is deny-by-default: a route with the middleware and no matching rule fails **closed** |
| — | `WAN → jellyseerr.goclan.org` | M16 — mechanism decided in that milestone (Cloudflare Tunnel recommended over a UDM-Pro port forward) | **This is a deliberate bypass of the "hosts on VLANs the UDM-Pro controls" threat model that every milestone before M16 assumed.** Architecture invariant #4 requires bypasses to be listed; this is one, and it is the first thing in the fleet that accepts a connection from outside the home network | **permanent** — written as a `—` row, in the same shape as the qBittorrent WebUI row, so a future milestone does not mistake it for something to retire and "fix" by removing the restriction | **not created — M16 has not been taken.** Recorded ahead of time because the row's *shape* is a constraint on M16 rather than an outcome of it. **Auth posture belongs in this row when it is created**: the unauthenticated attack surface must be **Authelia**, not Jellyseerr's Node application — forward-auth with 2FA required on the external path, Jellyseerr's own login kept underneath for the reason M6 kept Grafana's local admin. **Invariant #4's Jellyfin exemption does not transfer**: it exists because TV and mobile clients cannot survive a forward-auth redirect, and Jellyseerr's only client is a browser. The two rows sit next to each other and the exemption will look transferable |

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
but publishing then needs an `Authorization: Bearer` header. **That support
exists as of [#88](https://github.com/lutzgo/clanarchy/pull/88)** — see
[Enabling ntfy auth](#enabling-ntfy-auth-the-order-matters) — and it is the only
thing that makes a future leak survivable rather than fatal: a leaked *topic* is
then worth nothing on its own, and a leaked *token* is revocable from ntfy's web
UI without touching a machine.

### Enabling ntfy auth — the order matters

`clanarchy.zfs.ntfy.auth.enable` is **off by default and enabled on no
machine**, deliberately: it is one switch shared by the zedlet and M6's
Alertmanager bridge, and turning it on before the token exists leaves
`clan vars generate` prompting for something nobody has — and, on ernst, a
`monitoring-secrets` that fails closed and takes the monitoring container down
with it. That is the exact round M6's first deploy lost. **Do the ntfy side
first.**

1. **ntfy account**, on whichever instance `clanarchy.zfs.ntfy.baseUrl` points
   at (`https://ntfy.sh` by default).
2. **Reserve both topics** under that account — ernst's and miralda's — and set
   each to **deny anonymous access**. This is the step that actually changes
   anything: until a topic is reserved, the token is decoration and the topic
   is still the whole access control.
3. **Mint one access token per machine** (Account → Access tokens), each with
   **write** access to that machine's topic. One token for both would work; one
   per machine is preferred for the same reason each machine has its own topic —
   revocation stays per-machine.
4. **Enable it**, per machine, in `machines/<name>/configuration.nix` beside the
   existing `clanarchy.zfs.ntfy.enable`:
   ```nix
   clanarchy.zfs.ntfy.auth.enable = true;
   ```
5. **Generate and deploy**, ernst last if you want a safe order — miralda proves
   the zedlet path with nothing else riding on it:
   ```bash
   clan vars generate miralda   # prompts for the tk_… token; rejects a password by shape
   clan machines update miralda
   clan vars generate ernst
   clan machines update ernst   # no manual restart: restartUnits handles it
   ```
6. **Prove it**, with the same smoke test the rotation used — and prove the
   negative too, which is the half that shows the reservation took:
   ```bash
   # Should arrive.
   ssh root@ernst 'nixos-container run monitoring -- curl -s -XPOST localhost:9093/api/v2/alerts \
     -H "Content-Type: application/json" \
     -d "[{\"labels\":{\"alertname\":\"AuthTest\"},\"annotations\":{\"summary\":\"auth test\"}}]"'

   # Should now be REFUSED (403) rather than delivered — anonymous publish.
   curl -s -o /dev/null -w '%{http_code}\n' -d test https://ntfy.sh/<topic>
   ```
   A `200` on the second command means the topic is not reserved yet and step 2
   was skipped; the first command would still work, which is why both are here.

**Rolling back** is `auth.enable = false` plus a deploy — the topic var is
untouched by any of this, and the token generator is separate precisely so
nothing here can invalidate it.

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

**Built and deployed 2026-08-24, in
[#90](https://github.com/lutzgo/clanarchy/pull/90).** The container came up on
the first attempt and nothing in the repo needed changing — see
[the deploy notes](#first-deploy-2026-08-24-it-came-up-first-try-and-the-one-open-question-closed)
for what was measured, including the one question the PR shipped deliberately
unanswered. Three things remain unproven and are listed under
[Still to do](#still-to-do): TOTP enrolment, the Grafana OIDC login, and the
reboot invariant #7 demands.

The sections before the deploy notes were written *before* it and are kept as
written: the design arguments they make are what the deploy tested.

### Close-out — 2026-08-25

**What was built.** One nspawn container (`machines/ernst/containers/authelia.nix`)
holding Authelia 4.39 on `vb-authelia` / VLAN 90 / MAC `02:00:00:90:00:07` →
`10.0.90.15`, uid/gid **3008**, SQLite on `zdata` at `/srv/state/authelia`. One
`forwardAuth` middleware in `containers/traefik.nix`. One OIDC client for Grafana.
Three vars generators. One root helper, `authelia-code`.

**What is behind it today**, enumerated rather than described, because "the admin
UIs" is the kind of phrase that stops being true without anyone noticing:

| Router | Middleware | Why |
|---|---|---|
| `prowlarr.goclan.org` | `authelia` | admin UI, browser-only client |
| `sonarr.goclan.org` | `authelia` | admin UI, browser-only client |
| `radarr.goclan.org` | `authelia` | admin UI, browser-only client |
| `grafana.goclan.org` | `authelia` | admin UI; keeps its own local admin underneath as break-glass |
| `jellyfin.goclan.org` | **none, ever** | **invariant #4's exemption, and it survived** — TV and mobile clients cannot survive a forward-auth redirect. Verified in code (`services = jellyfin`, no `middlewares` attribute) and on the wire (`302 → /web/`, its own redirect, no portal) |
| `auth.goclan.org` | **none, necessarily** | it is the page the redirect points at; a middleware here would redirect an unauthenticated user to itself |

**What was measured.** The container came up first try with nothing overridden,
which answered the one question the PR shipped deliberately open: nixpkgs' authelia
module applies seven sandbox options with no `!config.boot.isContainer` guard, and
**all seven are in effect inside nspawn** with the service active and zero
restarts. Not pre-emptively deleting them was worth the risk — doing so would have
permanently weakened an identity provider to avert a failure that does not occur.
Both accounts are enrolled on TOTP and WebAuthn, read out of
`authentication_logs` and `sign_count` rather than asserted. The 408s were a
hypothesis when the PR shipped and are now confirmed fixed.

**What departed from the brief.** The bypass list came back **empty** and that is
the finding, not an omission — `auth.goclan.org` carries no middleware, so the
OIDC and health endpoints are never forwarded for authorization and a `bypass`
rule would match nothing while reading as enforcement. And the `mgmt-only`
ipAllowList was **deleted rather than stacked underneath** forward-auth, at a
stated cost: the login portal is now visible from the IoT VLAN.

**L5 is resolved, and the resolution is "gone", not "inert".** This row's removal
trigger was M7 and it has fired; the ledger's own rule is that such a row is
removed or re-argued, and leaving one in place is exactly the failure
[L4](#interim-rule-ledger) names — a permit rule doing nothing, which someone
later "fixes" by removing the restriction instead. Re-verified 2026-08-25 rather
than inherited: `grep -n ipAllowList containers/traefik.nix` returns **four
comments and no definition**. The row is updated to record the device state as
well as the code state, because a status written in the future tense of a deploy
that has since happened is a row nobody can read the state of.

**Still open**, and none of it blocks anything downstream: Grafana's OIDC button
has never been clicked, `lgo`'s TOTP is registered but never exercised (worth one
deliberate login before relying on it as the YubiKey fallback), and the reboot
invariant #7 demands has not been taken since `db.sqlite3` grew to four
credentials.

**Goal, unchanged from the brief.** A single sign-on layer in front of the admin
UIs: Authelia as a Traefik forward-auth middleware, replacing the interim
`ipAllowList` on the *arr and Grafana routes, with TOTP as the second factor.

**Authelia over Keycloak, and it was a choice.** One Go binary against a JVM
stack; `/api/authz/forward-auth` exists natively, where Keycloak in front of the
*arr would need oauth2-proxy as well — two components for a milestone whose point
is one; it is still an OIDC provider, which is the other half of the work; and
there is no SAML consumer and no directory to federate against, which is what
Keycloak's weight actually buys. What would reopen it: an actual SAML consumer,
or a second person's directory. The full version is in the header of
`machines/ernst/containers/authelia.nix`.

### Shape

| Piece | Value |
|---|---|
| Container | `machines/ernst/containers/authelia.nix`, nspawn, `vb-authelia` on `br0` / VLAN 90 |
| Address | MAC `02:00:00:90:00:07` → `10.0.90.15` (DHCP reservation on the UDM-Pro) |
| Ids | uid/gid 3008 `authelia-main`, continuing the 3000-range table in `networking.nix` |
| State | `/srv/state/authelia` → `/var/lib/authelia-main` — SQLite, plus the notifier's file |
| Ports | 9091 from `10.0.90.12` only; 9959 (telemetry) from `10.0.90.14` only |
| Vars | `authelia-secrets` (5 generated), `authelia-users` (1 prompt per account), `authelia-oidc` (a pair) |

**Accounts: `lgo` and `go`, both in `admins`.** Confirmed with lgo before the file
was written, per the brief. `sgo` is the expected next entry and is one line in
`autheliaUsers` plus `clan vars generate ernst` — the prompts, the
`users_database.yml` and the access-control subject list are all derived from that
one list, so there is nothing to keep in step.

**Three tiers untouched.** Authelia holds credentials and fetches nothing on
anyone's behalf, so it is trusted-tier / nspawn under invariant #1. Its state is
on `zdata` under invariant #7, and that invariant has never had a sharper edge in
this repo: every TOTP secret in the house is in one SQLite file, and putting it on
`zroot` would have worked perfectly until the next reboot and then locked every
account out of every admin UI at once, with the recovery path itself behind the
thing that broke.

### The ipAllowList is deleted, not stacked — and the cost is real

The brief asked for this to be evaluated rather than assumed. **Decision: remove
it.** Three reasons and one cost.

- **An IP allow-list under an IdP defeats the IdP.** The point of adding
  credentials plus TOTP is that access stops depending on where you are. Keeping
  the list means valid credentials and a correct code still fail from a phone on
  the IoT VLAN, or from any network nobody pre-declared.
- **Two mechanisms for one property** is what `containers/traefik.nix` argues
  against in its own words — "two sources of truth for one property is how you get
  a rule nobody dares delete because nobody can prove what it does." That applies
  to the control it shipped as interim.
- **The layering is already there and is untouched.** Every backend still refuses
  its own web port from anything but `10.0.90.12`, so the only path to the *arr is
  through Traefik — and now the only way through Traefik is through Authelia.

**The cost, stated rather than buried: the login portal becomes visible from the
IoT VLAN.** The `Allow Traefik` ZBF policy already permits IoT → `10.0.90.12:443`,
so a compromised smart device can now see a login form it previously could not.
What it meets there is a `two_factor` policy and regulation — three failures in
five minutes cost a fifteen-minute ban, tracked **per user** in `db.sqlite3` and
therefore surviving a restart. Per user and not per source is the right axis: an
attacker on the LAN can change source address at will and cannot change which
account they are guessing at.

The two warnings ledger row L5 carried were both honoured. `trustForwardHeader`
is **false**, so the middleware keeps the peer-address semantics the ipAllowList
had (Traefik writes `X-Forwarded-Method/-Proto/-Host/-Uri` onto the auth request
from the *actual* request regardless; the flag only decides whether a
client-supplied header is passed through instead — and nothing sits in front of
this proxy). Authelia's own Traefik documentation shows `true`, which is written
for deployments behind a CDN; this is not one. And the VLAN 70 lockout the row
warned about is moot, because the replacement does not filter by source at all.

### The bypass list came back empty, and that is the answer

The brief said to enumerate the OIDC endpoints and health checks that must be
unauthenticated "for the flow to work", and not to use a broad prefix. Enumerated,
**the list is empty.**

`auth.goclan.org` carries no middleware on its Traefik router — it cannot, since
it is the page the forward-auth redirect points at. So
`/.well-known/openid-configuration`, `/api/oidc/authorization`, `/api/oidc/token`,
`/api/oidc/userinfo` and `/api/health` are never forwarded for authorization in
the first place. An `access_control` rule with `policy: bypass` only ever applies
to requests Traefik forwards, and no request to those paths is one of them.
Adding such rules would be worse than adding none: they would read as enforcement
while matching nothing.

What is there instead is `default_policy: deny` plus **one** rule naming the four
protected hostnames explicitly, with `subject: ["group:admins"]`. Explicit
hostnames rather than `*.goclan.org` so that adding a route in
`containers/traefik.nix` with the middleware attached and forgetting to add it
here fails **closed**.

### Grafana: OIDC, and break-glass needed one new line to be true

Grafana moves to `auth.generic_oauth` against Authelia, with PKCE required on both
ends and `groups` mapped to roles (`admins` → Admin, everyone else → Viewer,
`role_attribute_strict = false` so an unexpected claim shape demotes rather than
locks out). The client secret is generated **as a pair** in one run — plaintext for
Grafana, pbkdf2 digest for Authelia — because two values that must correspond and
are produced separately will eventually disagree, and the failure mode is
`invalid_client` with no indication which half is wrong. The digest is staged out
of sops into a file rather than written into the config, so no credential material
lands in the world-readable Nix store.

Two switches that look like one: `users.allow_sign_up` stays **false** (the local
form) while `auth.generic_oauth.allow_sign_up` must be **true**, or an OIDC login
succeeds at the issuer and then fails at Grafana with "signup is not allowed".

**The break-glass account was already there and was already unreachable.** M6
kept Grafana's local admin precisely so it would work when the identity provider
is what is broken. Putting the Grafana route behind forward-auth makes that
account unreachable through Traefik — the login form itself is behind the thing
that is down. So the monitoring container now also accepts `:3000` from
`fdca:fe90::1`, the **host** end of M6's `mon0` point-to-point ULA veth:

```bash
ssh -N -L 3000:[fdca:fe90::2]:3000 root@ernst
# then http://localhost:3000, log in as `admin`
```

Host-only, root-only, one `ip6tables` line, and it reuses machinery M6 already
built. `auto_login` is deliberately off for the same reason — it would send anyone
hitting `/login` straight to the issuer, including the person trying to reach that
form. `signout_redirect_url` is deliberately unset too, so signing out of a
dashboard is not also signing out of the *arr.

### Authelia is now a scrape target

`service-modules/monitoring.nix` gains `settings.authelia.{address,metricsPort}`
and a matching job, source-restricted on the other end to `10.0.90.14` exactly
like Traefik's. Reason: after this milestone an Authelia that is down is every
admin UI in the house being down, and an identity provider nobody watches is the
thing that fails silently. **No new alert rule** — `InstanceDown` keys on
`always_on="true"`, a label only the machine targets carry, and the same is
already true of the `traefik` job. What this buys is the history and the `up`
series to read after an outage.

The module learns nothing about Authelia beyond those settings: no generator name
is hard-wired and no address is assumed, so it stays a clan service module that
happens to be pointed at an IdP on ernst rather than one that requires one. The
OIDC secret's generator is *named* in settings, and the `mkIf`-on-a-config-block
shape M6 discovered the hard way is reused for the `restartUnits` wiring — guard
the definition, not the value, or `clan vars check` reports a missing secret on
every machine that never enabled it.

### The notifier is a file, and TOTP enrolment is therefore an operator step

Authelia requires exactly one notifier; the choices are SMTP and a file. SMTP
would mean a mail credential, an outbound path to a mail host, and a third-party
dependency in the login path of every admin UI in the house. The file is cheaper
— but "cheaper" turned out to be wrong about *how much* cheaper, and this
section originally said `cat`, which is the bug that cost a round on deploy day.

**Authelia 4.39 will not let you register a 2FA device on a merely
authenticated session.** It first requires a *session elevation*: an
eight-character one-time code, sent through the notifier, typed back before the
QR appears. So every enrolment is a round trip through a file on ernst, and
three things bite:

1. **The file is overwritten, not appended — and the trap is the opposite of
   what it looks like.** Authelia's filesystem notifier truncates on every
   send, so `notification.txt` always holds exactly the newest notification.
   Measured: six rows in `one_time_code`, **one** `Date:` block in the file,
   mtime frozen at the last send. So the file is never stale — *your terminal
   is*. `the code didn't match any recorded code challenges` and `the code
   challenge has expired` both mean the same thing: what you typed is not what
   is currently valid. Re-read the file, not your scrollback.
2. **Codes expire in five minutes.** This is the actual failure mode, which is
   why the helper prints the age.
3. **Generating codes is rate-limited in stacked buckets**, and clicking again
   because "it didn't work" is what makes it much worse:
   `bucket=1 delay=35s`, `bucket=2 delay=545s`, `bucket=3 delay=1745s` — 29
   minutes. The UI reports this as *"Failed to generate the One-Time Code.
   Please try again later"*, which sounds like a broken notifier and is not.
   **While rate-limited no new notification is written**, so the file keeps
   showing the last (expired) code — which reads exactly like a broken helper
   and is the rate limit being obeyed. The limiter is **in-memory** (there is
   no rate-limit table in the schema), so `machinectl restart authelia` clears
   it at the cost of every active session. It applies **per source address**,
   so one person fumbling blocks every account from that machine.

Hence **`authelia-code`**, a root helper on ernst that prints the newest code
and its age and nothing else:

```console
# authelia-code
EAW9R3EC

  for      {Lutz lutz0go@gmail.com}
  subject  Confirm your identity
  issued   2026-08-24 17:34:28  40 s ago
```

An age older than five minutes prints `EXPIRED, request a new one` instead — the
specific confusion on deploy day was an expired code being reported as "didn't
match", and an age in front of it makes a stale read obvious before it is typed.

The flow, once per account: log in with the password → Settings → 2FA →
One-Time Password → **ADD** → `authelia-code` → type it → scan the QR.

**One UI trap that is not ours**: the 2FA page can land on *Security Key*
(WebAuthn) even when the account's preferred method is TOTP. With nothing
registered it then offers only "Register device" and no code box, which looks
exactly like a broken login. Click **METHODS** and pick One-Time Password. Both
accounts hit this.

Password reset is disabled for the matching reason: the reset flow mails a link to
a file on ernst, so "reset your password" already means "get a shell on ernst" —
and someone with that can re-run `clan vars generate ernst`, which is the real
reset path and the one that keeps sops as the single source of truth. That is also
what keeps `users_database.yml` read-only.

### What was verified, offline, against the real binary

This is the part that distinguishes a claim from a prediction. Everything below
was run on miralda before the PR was opened.

| Check | Result |
|---|---|
| `nix flake check` | passed |
| `toplevel.drvPath` on all four machines | evaluated |
| `authelia validate-config` on the **rendered** config + staged OIDC client block + generated `users_database.yml` + the module's JWKS fragment | **"Configuration parsed and loaded successfully without errors"** — Authelia 4.39.20, `X_AUTHELIA_CONFIG_FILTERS=template` and all four `AUTHELIA_*_FILE` env vars set exactly as the module sets them |
| All three vars generators, run end to end with fake prompts | produced 64-char secrets, a verifying 4096-bit RSA key, a two-user `users_database.yml` with `$argon2id$` digests, and a matching plaintext/pbkdf2 pair |
| The short-password guard | exits 1 with the message, as intended |
| Traefik dynamic config | four routers carry `authelia`; **`jellyfin` carries none**; `auth.goclan.org` carries none |
| Container firewalls | authelia 9091 ← `.12` only, 9959 ← `.14` only; monitoring 3000 ← `.12` **and** `fdca:fe90::1` |

**Not verified, because it cannot be without deploying:** that
`authelia-main.service` starts inside nspawn at all. nixpkgs' authelia module sets
a large systemd sandbox unconditionally — `ProtectKernelTunables`,
`ProtectControlGroups`, `RestrictNamespaces`, `PrivateUsers`,
`MemoryDenyWriteExecute`, `ProtectSystem=strict` — and, unlike the jellyfin
module, it is **not** container-aware: there is no `!config.boot.isContainer`
guard on any of them. `containers/traefik.nix` records that some of those conflict
with nspawn's own mount-namespace setup.

**Nothing was overridden pre-emptively**, and that is deliberate: this repo's own
lesson from M2/M2b is that a plausible inference recorded as a measurement is how
you end up fixing a hazard that does not exist. If the unit fails,
`systemctl status authelia-main` names the option, the fix is a three-line
`mkForce` block already written out in a comment in the file — and whoever applies
it should record **which one it actually was**, not which one it might have been.

> **Answered on deploy, and the guess was wrong in the safe direction:** all
> seven options are in effect and the service is active with zero restarts. The
> measurement is [below](#first-deploy-2026-08-24-it-came-up-first-try-and-the-one-open-question-closed).
> Not overriding them was worth the risk — pre-emptively deleting six hardening
> options would have permanently weakened the unit to avert a failure that never
> occurs.

### First deploy, 2026-08-24: it came up first try, and the one open question closed

`clan vars generate ernst` → reservation → Technitium zone → `clan machines
update ernst`, in that order. **The container started on the first attempt and
nothing in the repo needed changing.**

| Check | Result |
|---|---|
| `machinectl list` | `authelia` present, `10.0.90.15` |
| `bridge vlan show dev vb-authelia` | `90 PVID Egress Untagged` — networkd won the race unaided, as it has for every veth since M2b |
| `authelia-secrets.service` | active (exited) |
| `authelia-main` inside the container | **active**, `NRestarts=0`, `ExecMainStatus=0`, "Startup complete" |
| `/srv/state/authelia/db.sqlite3` | created, 304 KB, owned by uid 3008 — on `zdata`, where it belongs |
| `https://auth.goclan.org/` | **200**, certificate verifies (the M5 wildcard already covered the name) |
| `https://sonarr.goclan.org/` | **302 → `auth.goclan.org/?rd=…&rm=GET`** |
| `https://grafana.goclan.org/` | **302 → `auth.goclan.org/?rd=…&rm=GET`** |
| `https://jellyfin.goclan.org/` | **302 → `/web/`** — its own redirect, no portal. The exemption holds |
| `/.well-known/openid-configuration` | serves, issuer `https://auth.goclan.org` |

**THE UNMEASURED QUESTION IS ANSWERED: the upstream systemd sandbox works
unmodified inside nspawn.** The PR shipped with nothing overridden and an
explicit instruction to record what actually happened, because nixpkgs'
authelia module — unlike jellyfin's — carries no `!config.boot.isContainer`
guard on any of it. From `systemctl show authelia-main`:

```
ProtectKernelTunables=yes   ProtectKernelModules=yes   ProtectControlGroups=yes
RestrictNamespaces=yes      PrivateUsers=yes           MemoryDenyWriteExecute=yes
ProtectSystem=strict
```

All seven in effect, service active, zero restarts. The mechanism, for the next
person who wonders: nixos-containers runs nspawn **privileged** (no
`--private-users`), so PID 1 inside holds `CAP_SYS_ADMIN` and systemd can apply
each of these inside that namespace. The jellyfin module's guard is about a
different case.

The transferable part is not "these options are fine in nspawn". It is that
pre-emptively deleting six hardening options from an identity provider, on a
guess, would have permanently weakened the unit to avert a failure that does not
occur — the same shape as M2's `br0` MAC prediction, caught before it cost
anything this time.

### The one thing that did go wrong was a client-side negative cache

`http://auth.goclan.org` from a browser on miralda returned
`ERR_NAME_NOT_RESOLVED` while everything above was already working. The name was
correct, the zone was correct, and Technitium was answering:

```
dig +short @10.0.5.3 auth.goclan.org   →  10.0.90.12     (NOERROR)
resolvectl query auth.goclan.org       →  not found
resolvectl query grafana.goclan.org    →  10.0.90.12  -- link: wlp1s0
```

Same link, same resolver, same zone — one name failing and its siblings
succeeding is the signature. **systemd-resolved on miralda had cached an
NXDOMAIN from a lookup made before the Technitium zone existed.**
`resolvectl flush-caches` fixed it in one command and the name resolved in 4 ms.

This is the **same 30-minute negative cache** `containers/traefik.nix` documents
at length for the ACME challenge, arriving from the other direction: `goclan.org`
lives at Cloudflare, its SOA minimum is 1800, and Cloudflare answers a
nonexistent name under it with NXDOMAIN rather than NODATA. Anything that asks
for a `*.goclan.org` name **before** its Technitium zone exists poisons its own
resolver for half an hour.

**So the ordering in the manual steps is load-bearing, and it is not obvious
why**: create the Technitium record before anyone types the name, not merely
before the deploy. If it is already cached, no config change clears it —
`resolvectl flush-caches` on the client, or wait it out. Every future milestone
that adds a name (M8's Tvheadend, M9's TubeSync) inherits this.

*(Noticed in passing and not chased: miralda's NM profile is named `skynet`, and
`modules/networking/skynet-dns-nm.nix` targets a profile named `home`, so the
`~.` routing domain it means to set is not on the link — `resolvectl status
wlp1s0` shows a DNS server and no DNS Domain. It works anyway because the link is
`+DefaultRoute`, but the global scope still falls back to 1.1.1.1. Unrelated to
M7; worth a `fix/` branch.)*

### Still to do

- **Enrolment — DONE 2026-08-24, both accounts, both methods.** Read out of the
  database rather than asserted:

  | user | TOTP | WebAuthn | proven by |
  |---|---|---|---|
  | `go`  | created 16:50:22, **used** 17:42:28 | created 18:17:50, `sign_count=4` | TOTP + WebAuthn rows in `authentication_logs`, both `successful=1` |
  | `lgo` | created 18:15:39, never used | created 18:16:24, `sign_count=7` | WebAuthn row, `successful=1` |

  `sign_count > 0` is the thing worth reading: it is the authenticator's own
  counter, so it only moves on a real assertion. **`lgo`'s TOTP is registered
  but has never been exercised** — not a fault, just the one credential in the
  set that nothing has proven. Worth a single deliberate login via METHODS →
  One-Time Password before relying on it as the fallback for a lost YubiKey,
  which is the entire reason it exists.
- **Break-glass rehearsed 2026-08-24 — works.**
- **The 408 fix — CONFIRMED 2026-08-24, and it was a hypothesis when it
  shipped.** Last 408 at 17:42:35; `container@traefik` picked up the
  `serversTransport` at 17:52:47; zero since, through the WebAuthn
  registrations at 18:16 and 18:18 — i.e. through exactly the browse-then-idle
  pattern that produced them. The hedge is removed from
  `containers/traefik.nix` and the measurement is recorded there.
- **Grafana OIDC has not been exercised** — the "Sign in with Authelia" button
  has not been clicked, so the token exchange and the group→role mapping are
  unproven. Everything *around* it has been checked from the monitoring
  container: it resolves `auth.goclan.org`, discovery returns 200 with TLS
  verifying, and the client secret is staged `0400` uid 3007.
- **The reboot** (invariant #7), and it is now the right time: `db.sqlite3`
  holds four credentials rather than one, so the test is worth what it costs.
  Reboot, then log in again with the same YubiKey. If the dataset were wrong
  this is where it shows.

### Manual steps — lgo's, and in this order

1. **`clan vars generate ernst`** — BEFORE the deploy, not after. Three new
   generators; two prompts, one per account. clan-core cannot know a sops
   secret's path until the secret exists, so a deploy that runs first bakes
   `/no-such-path` into the staging script and produces a system whose staging
   unit can never succeed however often it is restarted. The failure is at least
   fail-closed and loud: the unit fails, `container@authelia` never starts, and
   there is no identity provider rather than one that lets everything through.
2. **DHCP reservation** on the Services network (VLAN 90): MAC
   `02:00:00:90:00:07` → `10.0.90.15`. **Inside the pool** (`10.0.90.6`–`.254`) —
   UniFi accepts an address from the `.2`–`.5` range and then silently hands out
   an ordinary pool lease instead. M2b lost a round to exactly that.
3. **Technitium**: `auth.goclan.org` → `10.0.90.12` (Traefik, not the container).
   Same shape as every other name; the wildcard certificate already covers it, so
   there is no certificate work.
4. **No UDM-Pro rule.** The `Allow Traefik` policy already permits every consumer
   zone to `10.0.90.12:443`, and that is the only address involved. Nothing new
   is exposed to any zone. *(While in there: M6 measured that this policy's
   source list is `LAN + IoT` only and does **not** include `Servers`, contrary
   to what the ledger claims. Unrelated to M7, still worth fixing.)*
5. **`clan machines update ernst`.**
6. **Enrol TOTP, per account**, with `authelia-code` on ernst — see the notifier section for the three traps. Do lgo's
   first and confirm it works before touching anything else.
7. **Verify from the road**, or at least from a non-management VLAN. The whole
   point of retiring L5 is that this now works; it is also the thing that will
   quietly not.

### Test plan

Run after `clan machines update ernst`:

```bash
# The veth landed on VLAN 90 — the one thing that races.
bridge vlan show dev vb-authelia          # expect: 90 PVID Egress Untagged
ip -br link show master br0               # expect: enp13s0 + five vb-* veths

# Staging succeeded and the container is up.
systemctl status authelia-secrets         # active (exited)
nixos-container status authelia
nixos-container run authelia -- systemctl status authelia-main
nixos-container run authelia -- ip -br addr show eth0   # 10.0.90.15

# The authz endpoint answers, and answers 401 to an unauthenticated probe.
nixos-container run authelia -- \
  curl -sS -o /dev/null -w '%{http_code}\n' localhost:9091/api/authz/forward-auth

# It is NOT reachable from the host — mechanism (a) doing its job.
curl -m5 http://10.0.90.15:9091/ || echo "refused from the host — correct"

# End to end, from a browser:
#   https://sonarr.goclan.org      → redirected to auth.goclan.org
#   log in + TOTP                  → lands on Sonarr
#   https://jellyfin.goclan.org    → NO redirect, Jellyfin's own login
#   https://grafana.goclan.org     → forward-auth, then "Sign in with Authelia"
#
# And from a network that the deleted ipAllowList would have refused —
# a phone on IoT, or wg-travel. This is the milestone's actual deliverable.

# Break-glass, with Authelia deliberately stopped:
#   machinectl stop authelia
#   ssh -N -L 3000:[fdca:fe90::2]:3000 root@ernst
#   http://localhost:3000  → local admin form, still works
#   machinectl start authelia

# The reboot is part of the milestone (invariant #7): db.sqlite3 holds every
# enrolled TOTP secret and has never been tested against a real rollback.
#   systemctl reboot
#   …then log in again with the SAME TOTP code source.
```

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

### What the *arr ecosystem does and does not provide here (surveyed 2026-08)

**Added 2026-08-25. Additive: Phase 0's gate and the four open questions above
are unchanged, and the session prompt below is unchanged.** What follows is a
survey result, one structural rethink, and **one scope question that may kill the
milestone** — sequenced after M12 rather than answered now.

#### The survey result is a NEGATIVE one, and that is the useful part

**awesome-arr was read in full. It has NO live-TV or DVR category, and no PVR
*arr exists.**

**That is STRUCTURAL, not an omission.** The *arr model is *"find a release,
download it, import it"*. A PVR is *"a tuner exists, schedule against an EPG,
capture in real time"*. **Sonarr cannot do the second, and no fork does.** The two
are not the same problem wearing different clothes.

**TVHEADEND STAYS.** Recorded here so a future session does not re-survey the same
list hoping for a "Tvheadendarr".

#### Reconsider the split: Tvheadend as SCHEDULER, or as TUNER ONLY?

M8 assumed Tvheadend owns **both** tuner sharing **and** recording. **Jellyfin has
native Live TV and DVR**: it can consume a tuner (Tvheadend via plugin, or
M3U/HDHomeRun), read an EPG, **schedule series recordings**, and **record into a
library it ALREADY INDEXES** — which is the expensive half of M8's
post-recording chain, for free.

**EVALUATE BOTH AND ARGUE ONE:**

- **(i) Tvheadend records**; something bridges recordings into `/srv/media` and
  triggers a Jellyfin scan. **More parts** — but recordings survive a Jellyfin
  rebuild, and **Tvheadend's scheduler is far more capable**: conflict resolution,
  priorities, timeshift, pre/post padding.
- **(ii) Tvheadend is a tuner-sharing daemon ONLY**; **Jellyfin's DVR** schedules
  and records. **Fewer parts**, recordings land in the library **by construction**,
  **no bridge to write**. But **DVR state lives in Jellyfin's database** and its
  scheduler is **materially weaker**.

**Shape (ii) may collapse most of M8. TEST IT BEFORE BUILDING (i).** Jellyfin
already has a container, a veth and a VAAPI device — **(ii)'s marginal cost is a
plugin and a tuner URL.**

#### The recordings→library bridge is UNSOLVED upstream, if (i) wins

Tvheadend records to **its own directory with its own naming**. **Jellyfin will not
match those to series, and Sonarr will not import them without help.**

**awesome-arr's Fetcharr does EXACTLY this pattern** — watches a PVR box, copies
new episodes of followed shows into the library, triggers a scan — **but for Fetch
TV and Plex.** **Design reference, not a dependency.**

**Nobody has written the Tvheadend→Jellyfin equivalent.** So **(i) costs a small
bespoke tool** — Go, or a systemd path unit plus a script, in this repo's idiom —
**and the milestone must budget for it rather than discovering it mid-session.**

Two constraints on it: recordings land **inside the `/srv/media` hardlink domain**
per invariant #2 (plain subdirectory, no dataset), and **the trigger is a path unit
or Tvheadend's post-recording hook, NOT a polling timer.**

#### MPEG-TS normalisation is a real step, not a nicety

DVB-C recordings are **MPEG-TS**, often with **broken or discontinuous
timestamps**, **teletext subtitle tracks Jellyfin handles poorly**, and **multiple
audio tracks** (German / original / audio description) that a two-language
household does not all want.

**MUXARR** strips redundant audio and subtitle tracks **WITHOUT re-encoding**, with
*arr integration for original-language detection — **cheap, lossless, the right
default**. **TRANSCODERR** is the heavier plugin-configurable pipeline, **only if
remuxing is insufficient**.

**SEE [M15](#m15-featernst-tdarr) for the shared Muxarr evaluation — whichever
lands first owns it.** M15 has its own reason to want Muxarr (space reclamation in
a two-language library), and evaluating it twice would be a waste; evaluating it
zero times because each milestone assumed the other did is the likelier failure.

**AUTOPULSE** for the library-scan trigger — **only relevant under (i)**. Under
(ii) there is nothing to trigger, because Jellyfin recorded the file itself.

#### The scope challenge M8 must now answer, and it may kill the milestone

**[M12](#m12-featernst-arr-helpers) adds MediathekArr**, which pulls ARD and ZDF
content **on demand** through the normal Sonarr/Radarr pipeline.

**For German free-to-air that covers most of what recording is FOR.** The
öffentlich-rechtliche broadcasters put their programming in the Mediathek, and a
Mediathek pull arrives **correctly named, correctly matched, already demuxed, with
subtitles** — needing **no tuner, no SAT>IP RTSP session, no ephemeral-UDP ACL
(ledger row L7), and no FRITZ!Box cooperation at all.** It sidesteps every one of
M8's four open questions simultaneously.

**SO M8's PHASE 0 GAINS A QUESTION AHEAD OF ITS EXISTING ONES:** after M12 is
deployed and **MediathekArr has been used in anger for a few weeks**, **what is
actually missing?**

**The only answers that justify the milestone:**

- **genuinely live viewing** — sport, news, events — where on-demand is useless;
- **private broadcasters** (RTL, ProSieben, Sat.1), whose catch-up is paywalled or
  absent;
- **Depublizierung** — content removed after a statutory availability window,
  where **recording is the only way to keep it**;
- **regional programming** absent from the national Mediathek.

**If none of those matter, M8 SHOULD BE DROPPED**, and ledger rows **L6 and L7
retired as never-created**. **Dropping on evidence is the [M10](#m10-kodi-ir-remote-dropped)
pattern and is a good outcome**, not a failure — M10 was dropped before any code
was written and the roadmap is better for it.

**DO NOT DROP IT NOW.** The question is recorded and **sequenced after M12**; it
needs weeks of real use to answer, and answering it from a desk would be exactly
the inference-recorded-as-measurement this file keeps catching.

#### Dispatcharr as Plan B

**M8's death condition is "the FRITZ!Box's DVB-C is branding-locked."** If Phase 0
finds that, **the fallback is IPTV**, and **Dispatcharr is the tool for that
shape** — an IPTV tuner with channel, EPG and logo management, presenting a
**normalised M3U/EPG** to Jellyfin or Tvheadend.

**NOT in awesome-arr** — it surfaced from community configs, **so verify
maintenance status before relying on it.**

**The legal shape differs from DVB-C** and is **not a decision to make casually,
or in a docs PR.**

#### Checked and rejected as not applicable

- **ErsatzTV / Tunarr** — build custom live channels **FROM your library**. The
  **opposite direction**; they consume a library rather than filling one.
- **iPlayarr** — **same Newznab-shim architecture as MediathekArr** and **worth
  understanding as a template**, but it is BBC iPlayer.
- **Fetcharr** — reference design only, per above.
- **Medusa / SickGear** — Sonarr *alternatives*, not PVR schedulers. **Same
  structural gap**, so they change nothing.

**Note on the ledger:** this amendment does **NOT** retire L6 or L7. It records
**the condition under which they would be retired as never-created** — which is
M8 being dropped after the scope question above is answered.
*(Superseded 2026-08-27: both rows are now retired as never-created, by the
build below — for the opposite reason. M8 was opened, not dropped.)*

### Build session close-out (2026-08-27) — Phase 0 cleared live, and two premises fell

Everything above this heading is the milestone as planned; where they disagree,
this section is right. The scope gate was opened **by operator decision** — lgo
wants live TV alongside MediathekArr — and Phase 0 was cleared interactively in
the same session, with the operator patching cables while the session probed.

**Phase 0 evidence, all measured 2026-08-27:**

- `satipdesc.xml` → `<satip:X_SATIPCAP>DVBC-4</satip:X_SATIPCAP>` — four DVB-C
  frontends, present despite the Vodafone-branded firmware (`6591lgi`). **No
  branding lock.** The box even publishes its own channel M3U with full tuning
  parameters (213 channels): `http://192.168.178.1/dvb/m3u/channellist.m3u`.
- **Stream test**: ZDF HD (450 MHz, 256QAM, sr 6900) captured over raw
  RTSP/UDP from ernst — 12 s → 13.7 MB of MPEG-TS (~9.1 Mbit/s); ffprobe on
  the file: h264 1280×720@50 + 2× AC-3 + **an EPG data stream**, so EIT rides
  the mux and the OTA grabber needs no external XMLTV source.
- **Mux sweep**: all 8 probed frequencies lock (quality 13–14, level 114–131);
  330 MHz (Das Erste) locks noticeably slower than the rest.
- **RTP transport question (L7): answered by measurement, against the
  preferred option.** SETUP over interleaved-TCP → `461 Unsupported
  Transport`; UDP unicast works. This is also why ffmpeg's RTSP client
  *hangs silently* against this box when RTP can't arrive — probe with a raw
  RTSP client (the session's probe scripts) or tcpdump, not ffprobe alone.

**Premise 1 fell: tvheadend is NOT in nixpkgs — it was removed** (package and
module, also gone from unstable; nixpkgs PR #332259, "stuck on an unmaintained
version that required FFmpeg 4"). Instead of moving tiers, M8 follows M13's
Janitorr precedent: a from-source build in
`machines/ernst/containers/pkgs/tvheadend.nix`, pinned to an upstream master
rev (upstream is active; no stable tag since 2018), with `--disable-libav` —
the FFmpeg coupling that killed the nixpkgs package lives entirely in
transcoding, which Jellyfin owns. Three configure flags **download things at
build time** and must never be dropped: `--disable-ffmpeg_static`,
`--disable-pcloud_cache`, `--disable-dvbscan` (scan tables substituted from
`pkgs.dtv-scan-tables`). The binary was built and smoke-tested in-session.

**Premise 2 fell: there is no UniFi half at all.** Phase 0's 0.1/0.2 assumed
the FRITZ!Box lands on a UniFi VLAN. It is in **Vodafone bridge mode** (the
UDM-Pro holds the public IP), and its first patched leg sat IPv4-silent on the
USW — which turned out to be a *port class* property, not bridge-mode
inertness: **one FRITZ LAN port (the guest port) is IPv4-dark** (no ARP, no
DHCPv4, RA-only, services blocked) while the others serve the full
192.168.178.0/24 with DHCP, UI and SAT>IP. The fix was topological: the
FRITZ!Box is now **cabled directly into `enp12s0`**, ernst's previously unused
second NIC, joined to the tvheadend container's `fritz0` veth by a dedicated
two-port bridge `br-fritz`. Consequences: no VLAN decision, no rogue-DHCP
exposure (the FRITZ's DHCP server can only ever reach the container), no ZBF
rule, no DHCP-reservation for the FRITZ, and **L6 + L7 retired as
never-created**. The host holds no address on the FRITZ segment; the
container's `fritz0` is static `192.168.178.2/24`, no gateway, no DNS.

**One hazard measured and closed by construction**: the FRITZ sends IPv6 RAs
carrying a default route (6to4 + ULA). A manually-upped `enp12s0` during
Phase 0 briefly gave *the host* an IPv6 default route via the FRITZ — an SN2
violation. Every interface in `tvheadend.nix` pins `IPv6AcceptRA = false`,
and Avahi carries an explicit `denyInterfaces` for the segment.

**Shape (ii) won, as the amendment predicted**: Tvheadend is a tuner-sharing
and EPG daemon; **Jellyfin's DVR schedules and records**, into
`/srv/media/library/recordings` (plain subdir of the hardlink domain, 2770
root:media, RW-bound into the jellyfin container as
`/media/Server001/Recordings` — the one writable media bind that container
has). uid 3026 therefore has its own group and **no media access**; escalating
to shape (i) is a new argument, not a config flip. HTSP (9982) is bound but
opened to nobody; 9981 is reachable only from Traefik
(`tvheadend.goclan.org`, behind `authelia`) and Jellyfin.

**First deploy (2026-08-27) found one real defect, and it is a hardening
trap worth propagating.** The service crash-looped on **SIGSYS**
(`status=31/SYS`, core dumped, nothing in Tvheadend's own log — it never got
far enough to open one), and the only symptom through the front door was
Traefik answering **502 Bad Gateway**. The cause: `SystemCallFilter =
[ "@system-service" "~@privileged" ]` removes **`chown`**, which is a member
of *both* sets — and Tvheadend calls `chown(lockfile, -1, -1)` at startup, a
**no-op** that changes neither owner nor group. seccomp filters on the
syscall number, not its arguments, so a call that could not possibly do
anything privileged still killed the process. Fixed by appending `"@chown"`
**after** the `~@privileged` line (order is load-bearing: systemd applies the
lines in sequence). Adding it back costs nothing real — the unit runs
unprivileged with `CapabilityBoundingSet=""`, so without `CAP_CHOWN` the
kernel refuses any chown that would actually change an owner; the syscall is
permitted, the operation stays impossible.

**The general lesson, and it is the sibling of M13's `RuntimeDirectoryUser`
finding**: `systemd-analyze security` scores the unit *better* with the
crashing filter, because it rates directives rather than whether the process
survives them. The A/B that actually settled it was `systemd-run --user` with
the three filter lines against the real binary — it starts and serves
`/playlist/channels.m3u` (200); with only the first two it dies instantly.
**Run the service under the filter, not just the analyzer over it.**

**The second deploy found something structural, and it killed two items the
prompt asked for.** `tvheadend.goclan.org` reached Tvheadend's own login box
and then rejected every attempt — which looks exactly like a wrong password
and is not one. **Tvheadend's own HTTP auth cannot coexist with Authelia
forward-auth**: both use the `Authorization` header. Measured through the
real chain:

| request | result |
|---|---|
| no `Authorization` header | **302** — Authelia redirect, normal |
| *any* `Authorization` header | **401 — from Authelia**, before Tvheadend is reached |

Tvheadend challenges with **Digest only** (no Basic at all — verified against
the built binary: `WWW-Authenticate: Digest realm="tvheadend", qop=auth, …`).
The browser answers in `Authorization`; Traefik hands that request to
Authelia for authorization; Authelia reads the header as *its own*
credential, does not find `tvhadmin` in its user database, and returns 401.
The browser re-prompts forever.

Worth recording because it generalises: **any backend whose own auth uses the
`Authorization` header is incompatible with a forward-auth middleware on the
same router.** The *arr apps do not hit this because they use form/cookie
auth with an API-key header; Tvheadend is the first HTTP-auth backend in this
fleet.

**Resolved by lgo, 2026-08-27: Authelia is the auth boundary, Tvheadend runs
`--noacl`.** So the prompt's **superuser credential and its clan var are
gone** (the var was generated, then removed as orphaned), and so is its
**streaming-only Jellyfin user** — Jellyfin needs no credential in its M3U or
XMLTV URLs. What guards the port instead is the container firewall, which
admits exactly two sources: Traefik (behind two-factor) and Jellyfin. **That
firewall is now the only thing between the LAN and an unauthenticated admin
UI, so widening it means revisiting this decision.** Two coherent
alternatives are recorded in the file header for whoever does.

Also worth knowing for the next hand-rolled unit: the superuser file format
*was* correct all along, and three separate hypotheses (wrong path, wrong
JSON keys, plaintext-vs-`password2` obfuscation) were each disproved by
measurement before the actual cause surfaced — the decisive test was
`curl -u` versus `curl --digest` against the binary, which returned 401 and
200 respectively.

**The third deploy found a defect in Tvheadend itself, and it needed a
patch.** Jellyfin's tuner worked immediately — the M3U parsed and all 109
channels were read — but **the guide was empty and "Map Channels" was
blank**, with this in Jellyfin's log:

```
System.Xml.XmlException: Invalid character in the given encoding. Line 72029, position 252.
   at Jellyfin.XmlTv.XmlTvReader.GetChannels()
```

Tvheadend serves its guide as `encoding="utf-8"` **without guaranteeing the
bytes are valid UTF-8**, and .NET's `XmlReader` is strict, so it discards the
whole document. Measured: **5 bad bytes in 8.9 MB, all from one broadcaster**
(Bibel TV), whose EIT text carries mangled umlauts — `k<c3><c2>nnen` for
"können", `F<c3>llen` for "Fällen". **109 channels of guide data lost to five
bytes.**

**Upstream already tries to handle this** (`htsbuf.c`, issue #5909): it
validates the UTF-8 *lead* byte and the remaining buffer length. It then
copies the continuation bytes unchecked, directly beneath a comment saying so
— *"We should probably check each character in the range is also valid."*
`0xc3` announces a two-byte sequence and `0xc2` is not a continuation byte, so
that exact gap is what lets this through. The patch
(`pkgs/tvheadend-xmltv-utf8.patch`) closes it: continuation bytes must be
`10xxxxxx`, and a lead byte with a bogus continuation is replaced by a space
— the same treatment the function already gives a wholly invalid lead byte.
It is upstream-shaped and should be offered upstream rather than carried
forever; re-check on every rev bump.

**Verified by A/B against the real byte sequences**, since the EPG lives in
memory (`epgdb.v3` was 79 bytes) and could not be replayed from a state copy.
Unpatched, both real sequences emit invalid UTF-8; patched, both become
valid, while correctly-encoded 2-byte umlauts, a 3-byte €, a 4-byte emoji,
XML escaping and end-truncated sequences are all byte-identical.

**AND THE PATCH ALONE DID NOT FIX IT — JELLYFIN CACHES THE XMLTV FILE.**
After the deploy the live guide was provably clean (0 invalid bytes, strict
XML parse OK, 109 channels / 15,448 programmes), yet Jellyfin kept throwing
*the identical exception at the identical byte offset*, and "Refresh Guide
Data" did not help. The giveaway was that the offset never moved: it was
re-parsing a 9.3 MB copy at
`/var/cache/jellyfin/xmltv/<hash>.xml`, downloaded before the fix and
confirmed to still contain the bad bytes. Deleting that one file and
refreshing again pulled a clean copy and the error stopped.

So the operational rule, which applies to **any** future change to what
Tvheadend serves: **fixing the source is only half — clear Jellyfin's XMLTV
cache too.** Note `/var/cache/jellyfin` is a tmpfs here (see
`containers/jellyfin.nix`), so restarting the Jellyfin container clears it as
a side effect; deleting the single file is the surgical version and does not
interrupt playback.

**PLAYBACK WORKS, 2026-08-27 — and the transcode watch-item resolved the
best way it could.** The prompt asked to verify whether SD MPEG-2 falls back
to software decode on the Granite Ridge iGPU. On the path measured, **nothing
decodes at all**: Jellyfin served the stream as **DirectStream with
`-codec:v:0 copy`**. Tvheadend hands over a passthrough remux
(`profile=pass`), Jellyfin copies the video elementary stream, and the iGPU
is never involved — so the VAAPI question is moot for any client that can
handle the broadcast codec natively. It only becomes live again for a client
that cannot, and that is where the MPEG-2 question should be re-asked.

**One thing to let settle rather than fix.** Of 37 muxes, **15 are currently
marked `scan_result: 2` (failed)** and several EPG subscriptions sit in state
`Bad` with zero bytes. That reads like dead muxes and **is probably not**:
394 MHz is among the "failed" ones, and Phase 0 measured that exact frequency
locking cleanly (quality 14, real payload) — and BILD HD, which lives on it,
is one of the mapped channels. The likelier explanation is **tuner
starvation**: four tuners, 37 muxes, and an initial EPG sweep that occupies
all four at once, so scans that cannot get a frontend time out and are
recorded as failures. It is not blocking, because live viewing at weight 100
preempts EPG grabs at weight 4 — which is exactly the mechanism the tuner
ceiling section describes, working. **Do not delete muxes on this evidence**;
re-check the scan results once the first full EPG sweep has finished, and
only then disable whatever is genuinely absent.

Two DNS notes from the same deploy, neither a code defect: `tvheadend` had to
be created in Technitium as its **own primary zone** (`tvheadend.goclan.org`
with an `@` A record → `10.0.90.12`), which is how every other `*.goclan.org`
override on this resolver is shaped — the parent zone is Cloudflare's, so a
name that is not locally authoritative returns NXDOMAIN from upstream. And
the first wrong attempt was cached by systemd-resolved on the client, so
`resolvectl flush-caches` was needed after fixing it.

**Manual steps that remain lgo's** (also in the PR body): DHCP reservation
`02:00:00:90:00:0a` → `10.0.90.18` on the UDM-Pro (inside the pool!);
Technitium record for `tvheadend` (**as its own primary zone**);
`clan machines update ernst`; then the in-UI checklist — SAT>IP network on
the discovered server, mux scan, channel mapping, EIT grabber on, and
Jellyfin's Live TV wiring (M3U tuner + XMLTV guide from
`http://10.0.90.18:9981`, DVR path to the recordings library). **No `clan
vars generate` step and no Tvheadend user creation** — both died with the
auth finding above.

**Two more checklist items were wrong and are corrected here.** *"Set the
SAT>IP network's max input streams to 4"* — **there is no such setting**, and
the instruction misread how the SAT>IP client works. The ceiling is the
number of frontends Tvheadend creates, which comes from the device's "Tuner
configuration" (`tunercfgu`), left at **Auto**: it reads `X_SATIPCAP` from
`satipdesc.xml` (`DVBC-4`) and creates exactly four. Auto beats pinning
`DVBC-4` by hand — if Vodafone's firmware changes the tuner count, Auto
follows and a hand-pinned value silently would not. Contention is resolved by
**subscription weight** (EPG grab 4, live viewing 100), so a live tune
preempts an EPG grab rather than failing, which is why the initial EPG scan
saturating all four tuners is fine. The same auto-detection also got the
transport right unprompted: `tcp_mode: false` on disk, matching Phase 0's
measured 461.

**Configured and verified on ernst 2026-08-27**: four tuners under "GoFRITZ -
192.168.178.1", 116 services found, **109 channels mapped** (7 ignored, 0
failed), EIT grabber enabled, and — the flow that actually matters — from
**inside the Jellyfin container**, `playlist/channels.m3u` returns 200 with
109 channels and `xmltv/channels` returns 200 with **15,552 programmes**.
Stream URLs carry `profile=pass`, i.e. Tvheadend remuxes and never
transcodes, which is what shape (ii) requires.

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

## M11 — `feat/fleet-local-coding-agent`

**Status: Parts 2, 3 and 4 done 2026-08-26. Part 1 outstanding, and it blocks
Phase 1.** The decision the milestone exists to make — which agent — **still has
not been made**, and cannot be made by a machine; see
[What was not done](#what-was-not-done-and-why-a-machine-could-not-do-it).

Phase 0 (2026-08-25) left the tree untouched at `133a39d`. The 2026-08-26
session landed the first Nix of this milestone: the §7 server-side block, as
per-machine role settings. The findings live at `~/.local/share/m11-bakeoff/` —
`README.md`, `PHASE0-NOTES.md`, wrappers, **re-runnable probes**, and now
`tasks/` for Part 1. `PHASE0-NOTES.md` is the primary source and **§8 supersedes
§3's attribution**; this section is the durable summary.

| Part | Owner | Status |
|---|---|---|
| 1 — the human bake-off | lgo | **outstanding — blocks Phase 1.** Tasks + validated grader ready |
| 2 — candidate (C) | lgo | **decided: not taking it**, [below](#part-2--candidate-c-is-not-being-taken) |
| 3 — the tool-call fix | Claude | **done**, and the remedy was not the predicted one — [below](#part-3--the-tool-call-defect-corrected-twice) |
| 4 — the §7 declarative question | lgo | **decided: landed**, as role settings |

**Goal.** Decide whether a locally-hosted coding agent, driven by ernst's
`qwen3-coder:30b` on the 7900 XTX, can carry a useful share of daily work on this
fleet — and if so, which agent, packaged how. Phase 1 packages the winner; Phase 2
is optional network exposure.

**Depends on.** Ollama on ernst (done). **Risk.** Low in the repo — Phase 0
deliberately touches nothing — and the real risk is epistemic: naming a winner on
synthetic evidence, which is what the phase structure exists to prevent.

### Four premises the brief asserted that were false

*(Three found in Phase 0 and listed here; the fourth — "the tool-call parser is
template-driven, so fix the Modelfile template" — was found on 2026-08-26 and
is in [Part 3](#part-3--the-tool-call-defect-corrected-twice). It is the only
one the roadmap itself asserted rather than inherited from the brief.)*

Recorded as falsifications rather than silently corrected, because the point of
recording one is that a future reader can see the reasoning was **checked** rather
than inherited. This is the same discipline M2b applied to M2's `br0`-MAC
prediction.

**1 — "M11 adds a local agent to a fleet with none." FALSE.**
`clan.nix` already declares `roles.ollama.machines.ernst.settings.models =
[ "qwen3-coder:30b" ]` **and** `roles.opencode.machines.miralda.settings.user =
"lgo"`. Both predate this milestone. So M11 is not an addition. It is a **choice
between agents on a fleet that already ships one**, plus a **repair of what is
already there** — and the repair is needed whichever way the choice goes.

**2 — "The deployed opencode config works." FALSE, and it has never worked.**
`service-modules/local-ai.nix` renders, via `xdg.configFile."opencode/config.json"`:

```json
{"model":"ollama/qwen2.5-coder:7b","providers":{"ollama":{"baseUrl":"http://localhost:11434/v1"}}}
```

opencode 1.15.10 rejects it outright:

```
Error: Configuration is invalid at /home/lgo/.config/opencode/config.json
↳ Unrecognized key: providers
```

It is wrong in **four independent ways** against the current schema: `providers` →
`provider`; `baseUrl` → `options.baseURL`; no `npm` key (the provider needs
`@ai-sdk/openai-compatible` or it never loads); no `models` map.

**The failure mode is the interesting part and it is what Phase 1 has to design
around.** opencode **merges** its config sources, so a broken read-only store file
does not sit inertly beside a good one — **it aborts every run**. There is no
"ignore the bad file and continue". Both `OPENCODE_CONFIG` and
`OPENCODE_CONFIG_DIR` were tried; both still load it and both still choke. **Only
relocating `XDG_CONFIG_HOME` avoids it.** So the deployed config does not merely
fail to help — it makes opencode **unusable on miralda**, and **it cannot be
overridden from the environment.**

**That is a declarative-delivery lesson with teeth, and it generalises past this
tool.** A Nix-rendered config in the read-only store is not merely *inert* when
wrong. It is **load-bearing and fatal**, and the usual escape hatch — point the
program somewhere else with an env var — does not exist for a program that merges
rather than selects. Any milestone rendering config into the store for a tool that
*also* reads config from elsewhere must check that property before assuming the
pattern transfers.

This is the **third** instance of this shape in one service module; the other two
are already written into `local-ai.nix`'s own comments (the `qwen3-coder:8b` tag
that never existed, and the `DynamicUser` persist trap). It deploys green and does
nothing — [SN1](#sn1-the-model-tag-silently-sets-the-context-window) again, one
layer up.

**3 — "`ssh -L 11434:127.0.0.1:11434 ernst` gives miralda ernst's Ollama." FALSE.**
**miralda runs its own Ollama on `127.0.0.1:11434`** (`qwen2.5-coder:7b`). The
forward cannot bind. The harness uses local port **11435** instead.

**Why this matters far more than it looks.** A half-working forward would not
error. It would **silently talk to miralda's local 7B at 4096 context** — which is
the single worst possible bake-off failure, because it would have produced exactly
the "local models are bad at tool calling" result the brief predicted, **for
entirely the wrong reason**, and the number would have looked plausible enough to
write down. Same shape as M2b's item 1: a prediction that would have been recorded
as a measurement.

*(Noticed in passing, not M11's problem: miralda's own Ollama runs at **100% CPU** —
the `gfx1103` HSA override is not getting the model onto the 780M. It makes the
tunnel to ernst worth more, not less.)*

### The context trap — proven, with numbers

The brief predicted the shape. The session proved it, and the proof is sharper
than the prediction. These are measurements, and M15 and any future session can
cite them without re-deriving.

`machines/ernst/containers/arr.nix` is 65,643 bytes ≈ **17,083 prompt tokens**.
Fed to the model with two tool definitions:

| `num_ctx` | `prompt_eval_count` | tool calls (6 trials) |
|---|---|---|
| 8192 | **4098** — silently truncated | **0 OK, 6 NO_CALL** |
| 32768 | 17083 — intact | 6 OK, 0 failures |
| 65536 | 17083 — intact | 6 OK, 0 failures |

At 8192 the server discarded **76% of the prompt**, returned **HTTP 200**, and set
**no flag anywhere in the response**. The mechanism looks like: when the prompt
exceeds `num_ctx`, truncate to roughly `num_ctx/2` and **keep the tail**. Tool
calling died because the system message and the tool definitions sit at the
**front** and were the first thing cut.

Same file, same question, asking for one fact from the **head** (`arrMac`) and one
from the **tail** (`environment.systemPackages`):

| `num_ctx` | head fact (`arrMac`) | tail fact (`curl`) |
|---|---|---|
| 8192 | **`00:11:22:33:44:55` — FABRICATED** | `curl` — correct |
| 32768 | `02:00:00:90:00:05` — correct | `curl` — correct |

**It did not decline. It invented a placeholder-shaped MAC address that would
survive a skim of a diff.** That is the most useful single line this session
produced, and it is the exact shape of two defects already recorded in this repo:
the recyclarr duplicate-instance bug (green timer, exit 0, syncing nothing) and
the UmlautAdaptarr https-bypass that M12 has to check for explicitly. **A system
that fails by succeeding.** A config readback here would have shown
`num_ctx: 8192` and told you nothing at all — the only way to catch it is to
measure the thing itself.

**The second-order hazard is worse and has its own standing note.** `num_ctx` is
**model-derived**: 30b → 32768, 7b → 4096. So changing the model tag in `clan.nix`
silently changes the context fleet-wide, with no diff that shows it. See
[SN1](#sn1-the-model-tag-silently-sets-the-context-window), which exists because
that hazard lives in a file somebody will edit for an unrelated reason.

### Measurements — VRAM and throughput

Card: RX 7900 XTX at `0000:03:00.0`, **24560 MiB** total. Idle baseline (the HTPC
session) 877–1093 MiB. Ollama 0.32.3, `qwen3-coder:30b`.

| KV config | `num_ctx` | VRAM | of total | placement | decode tok/s |
|---|---|---|---|---|---|
| f16 (default) | 32768 | 22361 | 91.0% | 100% GPU | 124.2 |
| f16 | 32768 | 22361 | 91.0% | 100% GPU | 126.1 |
| f16 | 65536 | 24471 | 99.6% | **4% CPU / 96% GPU** | 98.5 |
| **flash-attn only**, f16 | 65536 | **24471** | 99.6% | **4% CPU / 96% GPU** | **97.5** |
| flash-attn + **q8_0** | 32768 | 20757 | 84.5% | 100% GPU | 111.5 |
| flash-attn + **q8_0** | **65536** | **22482** | 91.5% | **100% GPU** | **112.6** |
| flash-attn + q8_0 | 131072 | 24494 | 99.7% | 6% CPU / 94% GPU | 75.2 |

**`q8_0` KV cache is the whole win.**

- **Flash attention alone is a measured NO-OP.** 24471 MiB and 97.5 tok/s —
  statistically identical to the no-flash baseline at the same context. It is the
  *enabler*, not the saving. Recorded as a measured no-op so nobody re-tries it as
  an optimisation.
- **`q8_0` turns 64k from SPILLING into FULLY RESIDENT**: 22482 MiB, 100% GPU,
  112.6 tok/s, for **~11% decode cost** against f16 at 32k. Two times the context
  for one tenth the speed is not a close call.

**Throughput is not a problem and the brief was wrong to fear it.** The brief
warned that spilling to system RAM would make Ollama "unusably slow, maybe 5
tok/s". Measured: the **128k spill still ran 75 tok/s**, and the 64k f16 spill ran
98.5. The framing was right in *kind* — spilling is a real cost and a real reason
to keep `q8_0` — and **badly wrong in degree**, by more than an order of
magnitude. Corrected explicitly rather than dropped, because M15 designs its GPU
arbitration against this number and would otherwise inherit the exaggeration and
treat eviction as fatal.

### Tool calling — the central hypothesis, inverted

**This is the most important finding in the milestone, and it reverses the
argument the brief was built on.**

**88 graded trials. Zero invented arguments. Zero missing arguments. Zero
refusals.** The brief's stated worry — that models under ~70B are prone to
hallucinating tool arguments — **did not occur even once**.

Every failure was **one** thing: the model emitted a **correct** call in
qwen3-coder's native `<function=…>` XML —

```
<function=grep_repo>
<parameter=pattern>
API client
</parameter>
</function>
</tool_call>
```

— and **Ollama's template parser failed to convert it**, returning
`tool_calls: null` and leaking the markup into `content` as prose.

**The model behaved. The parser did not.**

| endpoint | condition | OK | UNPARSED_XML |
|---|---|---|---|
| native `/api/chat` | 1 tool, "read this file" | 6/10 | 4 |
| native `/api/chat` | 2 tools, "read this file" | 8/10 | 2 |
| native `/api/chat` | 1 tool, "go find X" | 10/10 | 0 |
| native `/api/chat` | 2 tools, "go find X" | 4/10 | 6 |
| **native, total** | short prompts | **28/40 (70%)** | **12/40 (30%)** |
| `/v1/chat/completions` | short, "read this file" | 5/10 | 5 |
| `/v1/chat/completions` | short, "go find X" | 1/10 | 9 |
| `/v1/chat/completions` | **long (17k `arr.nix`)** | **9/10** | 1 |

**And it is not the OpenAI shim.** Native `/api/chat` fails at the **same ~30%
rate** as `/v1` on short prompts. So the defect is in the **model template's
parser**, not in the compatibility layer.

**That matters for the escape hatch, and the roadmap has to say so.** The brief
named *"measured evidence that the /v1 shim mangles tool calls"* as the trigger
for migrating to **llama-swap + llama-server**. That trigger has **superficially
fired** — but the diagnosis is different, and **llama-swap would not fix this**:
swapping the wrapper moves the same template problem somewhere else. Migrating on
the strength of the original trigger would be work spent on the wrong layer.

**The corrected trigger.** The fix candidate is a **corrected Modelfile template
in Ollama** — the parser is template-driven, so the template is where the defect
lives and where the repair belongs. **The migration case only reopens if that
proves impossible.**

> **Falsified 2026-08-26.** There is no template: the Modelfile is
> `TEMPLATE {{ .Prompt }}` plus a **compiled Go** renderer and parser, and the
> parser is correct — the *model* drops the opening `<tool_call>` tag. The fix
> is a system-prompt reinforcement (5/40 → 80/80), and **llama-swap is closed
> off entirely**, since the same model would emit the same malformed call
> through any wrapper. See [Part 3](#part-3--the-tool-call-defect-corrected-twice).

**M11's session recommends holding off on llama-swap**, and the reasoning matters
more than the conclusion: (i) the defect is *upstream of* the wrapper, so the
migration does not address it; (ii) both agents **recovered in practice**, because
a real agent retries and the next turn usually parses — so the measured 30% is a
latency and token cost, not a failure rate; and (iii) Ollama runs llama.cpp
underneath anyway, so the migration buys a different API surface and not better
inference. Three reasons, none of which is "it would be a lot of work".

**The degradation model also flipped.** The brief predicted a **soft band** — tool
calling degrading gradually as context pressure rose. Measured:

- thin prompts → **70%** native / **30%** on `/v1`
- 17k-token code context → **~100%** native (12/12) / **90%** on `/v1`

A substantial code context appears to **steer** the model *into* the structured
format. **There is no soft degradation band.** Context pressure is **harmless
until you exceed `num_ctx`, and then total** — 0/6, per the table above. That is a
**cliff, not a slope**, and it changes how the failure should be monitored:
**there is nothing to watch trending, only a threshold to stay under.** Sample
sizes are 6–10 per cell; treat the direction as solid and the exact percentages as
indicative.

### Part 3 — the tool-call defect, corrected twice

**Everything above this heading was written on 2026-08-25 and its numbers
stand. Its attribution does not.** Part 3 set out to fix the parser via a
corrected Modelfile template. That remedy does not exist, and pursuing it would
have been a session spent on a file that is not there. Measured 2026-08-26;
full detail in `PHASE0-NOTES.md` §8.

**There is no Modelfile template to correct — falsified premise #4.**

```
$ ollama show --modelfile qwen3-coder:30b
TEMPLATE {{ .Prompt }}
RENDERER qwen3-coder
PARSER   qwen3-coder
```

`TEMPLATE` is a bare passthrough. `RENDERER` and `PARSER` name **compiled Go**
in the ollama binary (`model/renderers/qwen3coder.go`, `model/parsers/`), not
editable template text. The roadmap's own instruction — *"the parser is
template-driven, so the template is where the defect lives"* — was wrong about
the mechanism it was directing the next session toward.

**And the parser is correct. So is the renderer. The model is at fault.**
`model/parsers/qwen3coder.go` enters tool-collection **only** on the literal
string `<tool_call>`, with no `<function=` fallback. The renderer **already**
injects an `<IMPORTANT>` reminder that the `<function=...>` block *"must be
nested within `<tool_call></tool_call>` XML tags"*. A probe written to ask the
one decisive question — in a failed call, is the opening tag present or absent?
— returned **8 absent, 0 present**, and across 200+ trials since, the
"present but unparsed" count has never left zero.

**So Phase 0's headline — "the model behaved, the server-side parser did not" —
is backwards.** The model drops one tag while emitting its closing partner, and
ignores an instruction it was already given. That also **closes the llama-swap
escape hatch for good**: swapping the wrapper carries the same model emitting
the same malformed call. The migration case does not reopen on this evidence.

**The fix is four lines of system prompt**, restating the one missing tag:

| condition | baseline | + reinforcement |
|---|---|---|
| 2 tools, "go find X" | 2/20 (10%) | **20/20** |
| 2 tools, "read this file" | 3/20 (15%) | **20/20** |

**80/80 valid calls with the rule against 5/40 without**, across both KV cache
types. It ships in `~/.local/share/m11-bakeoff/toolcall-rule.md`, is wired into
the harness's `opencode.json`, and is documented in
`service-modules/local-ai.md` for whatever Phase 1 packages. Aider is immune —
it never asks for a tool call at all.

### The q8_0 confound — a VRAM setting that costs tool calls

**Nobody had measured these two together.** Phase 0 measured VRAM under `q8_0`
and tool calling in separate runs, then §7 recommended landing `q8_0`
permanently on the strength of the VRAM run alone. Flipping only the KV type,
interleaved to control for drift, n=30 per arm, identical prompt and context:

| KV cache | baseline system prompt | + reinforcement |
|---|---|---|
| `f16`  | 83%, 83% | 100% |
| `q8_0` | 40%, 36% | 100% |

**Quantising the KV cache roughly halves tool-call formatting reliability** —
it degrades instruction-following on exactly the structural detail this model
was already weakest at. **The reinforcement erases the difference entirely.**

So `q8_0` is free *only* if the client sends the rule; otherwise it silently
trades agent reliability for VRAM. That is the same shape as the context trap
and the recyclarr bug: a change that reports success while the cost lands
somewhere nobody is looking, invisible in any readback. The two settings are
now documented together in the `kvCacheType` option description **so they
cannot be read apart**, which is the only durable form this finding has.

**M15 should note this**: its GPU arbitration inherits `q8_0` from ernst's
ollama config, and the tool-call cost is a property of that choice.

### Part 4 — the §7 block landed, as role settings

**Decided by lgo, 2026-08-26: land it.** `roles.ollama` now carries
`contextLength` and `kvCacheType`, both `nullOr` and defaulting to `null`, with
`OLLAMA_FLASH_ATTENTION=1` set from inside the KV-cache branch rather than
exposed as a third knob — it is a prerequisite, not a choice.

Settings rather than constants, which was the stated condition and matters:

| machine | context | KV cache | why |
|---|---|---|---|
| ernst | 32768 | `q8_0` | 24 GiB discrete 7900 XTX |
| miralda | 4096 | *(unset → f16)* | 780M iGPU out of shared system RAM |

Verified by evaluation, not by reading the diff:

```
ernst    {"OLLAMA_CONTEXT_LENGTH":"32768","OLLAMA_FLASH_ATTENTION":"1","OLLAMA_KV_CACHE_TYPE":"q8_0","ROCR_VISIBLE_DEVICES":"0"}
miralda  {"HSA_OVERRIDE_GFX_VERSION":"11.0.3","OLLAMA_CONTEXT_LENGTH":"4096","ROCR_VISIBLE_DEVICES":"0"}
```

**miralda does not inherit ernst's window**, which was the whole point of the
per-machine requirement. This also makes the `q8_0` drop-in on ernst durable —
it previously lived in a `systemctl edit --runtime` override that a reboot
discarded. **It is landed but not deployed**: `clan machines update ernst` and
`clan machines update miralda` are lgo's step.

### Part 2 — candidate (C) is not being taken

**Decided by lgo, 2026-08-26: not taking it.** `codecompanion.nvim` /
`avante.nvim` will not be evaluated for M11. Recorded here as a decision with a
date rather than allowed to lapse a second time, which is what the previous
revision of this section explicitly warned against.

The argument *for* it has not gone away and is still the one in the
[alternatives](#alternatives-considered): miralda is already nushell + zellij +
foot + nvf, and every other candidate adds a fourth context to switch into.
What makes it declinable now is sequencing, not merit — **taking it means a
flake change in service of an evaluation, before the bake-off that would tell
you whether an in-editor agent is worth having at all.** Part 1 is the blocking
work; adding a third candidate widens it rather than advancing it.

**The re-check trigger, so this is a deferral with an exit and not a burial:**
revisit (C) if Part 1 concludes that a local agent earns a permanent place in
the workflow. At that point the question stops being "which agent" and becomes
"where does it live", which is the question (C) actually answers — and it
composes with whichever of (A)/(B) wins rather than competing with it.

### Both agents work — and one new point for Aider

Identical task in a throwaway repo: add docstrings to both functions in
`calc.py`, make `divide` raise `ValueError` on a zero divisor. **Both completed a
real edit against ernst's 30B.**

- **OpenCode 1.15.10** — completed it via **native tool calls**. Correct,
  idiomatic Google-style docstrings, correct guard. Slow on a cold model (~10 min,
  largely loading 18 GB); **~40 s warm**.
- **Aider 0.86.1** — completed it via a **SEARCH/REPLACE block, 2.5k tokens
  sent**, and **auto-committed**. Noticeably faster and far cheaper in tokens.

The milestone's structural argument shows up in the very first measurement: Aider
spends no tokens on tool schemas and **cannot be hurt by the parser bug above**,
because it never asks the model to emit a tool call at all. OpenCode buys a real
agentic loop and pays for it in both tokens and exposure to the one defect that
was actually measured.

**A packaging finding the brief could not have anticipated, and it is a real
argument for Aider on *this* fleet specifically.** **OpenCode fetches ~15 MB of
npm at runtime into its config directory.** Running it created a `node_modules/`
next to the config with a generated `package.json` pinning
`@opencode-ai/plugin@1.15.10`, and the `@ai-sdk/openai-compatible` provider named
in `opencode.json` is resolved the same way. So:

- **A Nix-rendered `opencode.json` is not sufficient to make the agent work.** The
  config names a provider downloaded from the network on first use, so the
  declared thing is not the running thing.
- **The config directory must be WRITABLE.** Today `~/.config/opencode` is a
  read-only store symlink (`xdg.configFile`), so opencode cannot write beside it.
  Any Phase 1 module has to hand it a writable directory **and** a `/persist`
  entry, or it refetches after every rollback.

Combined with falsification (2), **opencode's config story is actively hostile to
the delivery mechanism this repo uses everywhere else.** That is a first-class
Phase 1 consideration, not a footnote. Aider has no equivalent problem:
`nixpkgs#aider-chat` is a closed Python derivation with no runtime fetch.

### What was not done, and why a machine could not do it

**The bake-off itself.** A machine cannot run "two weeks of real use". Three
required measurements are lgo's and remain outstanding:

| # | Required | Status |
|---|---|---|
| 1 | Tool-call reliability over **real tasks** | **partial** — 88 synthetic trials done; the real-task rate is lgo's |
| 2 | Long-context task on `arr.nix` | **done** — it is the `num_ctx` proof |
| 3 | **Multi-file clanarchy edit**, driven end to end | **not done** — single-file smoke test only |
| 4 | **Claude Code comparison**, honest gap | **not done** — lgo's, and the brief explicitly called it **not optional** |
| 5 | tokens/sec and VRAM at the chosen config | **done** |

(4) is what turns tiering from a guess into evidence. Naming a winner now would be
exactly the rationalisation the phase structure exists to prevent.

**Candidate (C) — the in-editor option — was NOT installed in Phase 0**, because
`codecompanion.nvim` / `avante.nvim` cannot be added without touching the flake
(they are nvf plugins, and the nvf option namespace is declared at the NixOS
level via `home-manager.sharedModules`), and Phase 0 forbade flake changes.

**Resolved 2026-08-26: not taking it**, with a re-check trigger — see
[Part 2](#part-2--candidate-c-is-not-being-taken). It is no longer an open
thread.

**Part 1 is now equipped.** The three outstanding measurements have tasks, a
throwaway-worktree harness, and a grader validated against both a positive and a
negative control at `~/.local/share/m11-bakeoff/tasks/`. Two multi-file tasks:
one objectively gradeable with a hard cross-file dependency, one with a
known-good reference solution. **(b), the Claude Code comparison, remains lgo's
alone** — that has not changed and cannot.

### State of the harness — record this, it is an asset

`~/.local/share/m11-bakeoff/` holds `README.md`, `PHASE0-NOTES.md`, wrapper
scripts (`bin/m11-tunnel`, `bin/m11-aider`, `bin/m11-opencode`), and
**re-runnable probes** (`probes/ctx-vram-probe.sh`, `matrix.sh`, `matrix-v1.sh`,
`matrix-long.sh`, `toolcall-probe.sh`, `toolcall-probe2.sh`, `v1-probe.sh`). **It
is the instrument that produced every number above.** The next session should
re-run it, not rebuild it.

It lives outside the repo on purpose — Phase 0 says no PR — and that directory is
persisted for `lgo`, so it survives a rollback without anything being declared.

Aider was installed via `nix profile`; removal is one command.

**The `q8_0` drop-in on ernst was a `systemctl edit --runtime` override at
`/run/systemd/system/ollama.service.d/override.conf`, runtime-only and lost on
reboot.** That was deliberate while nothing was declarative: both agents are
pinned to 32768, which works under either KV config, so a reboot cost speed and
never correctness. **Superseded 2026-08-26** — `kvCacheType = "q8_0"` is now a
role setting in `clan.nix` and survives reboot once ernst is deployed. The
override on the running daemon is now redundant with the declared config rather
than in conflict with it.

Two probes were added on 2026-08-26 and belong to the asset:
`probes/rawcapture.sh` (records the leaked content instead of grading it — it is
what proved the parser innocent) and `probes/kv-toolcall-confound.sh` (flips the
KV type, interleaved, and **always restores the drop-in it found**).

### The open question for lgo — CLOSED 2026-08-26, landed

**Resolved: landed, as role settings.** See
[Part 4](#part-4--the-7-block-landed-as-role-settings) for what shipped and the
evaluated proof that miralda does not inherit ernst's window. The section below
is kept as the record of the question and both horns, because the reasoning is
what a future session needs, not the outcome.

One thing the argument below did **not** know, and it strengthens the "land it"
horn rather than weakening it: `q8_0` carries a **tool-call cost** that no
readback reveals. A setting with an invisible cost in another component is
exactly the kind that must be declared and commented rather than left in a
runtime drop-in nobody re-derives.

**The brief said server-side work happens regardless of the outcome, AND said
nothing declarative. Those conflict.** M11's session kept everything
non-declarative and wrote the ready-to-land Nix into **§7 of `PHASE0-NOTES.md`**
instead, explicitly flagging it as lgo's call rather than making it.

It is a small block on `service-modules/local-ai.nix`'s `roles.ollama` setting
`OLLAMA_CONTEXT_LENGTH = "32768"`, `OLLAMA_FLASH_ATTENTION = "1"` and
`OLLAMA_KV_CACHE_TYPE = "q8_0"` — with the per-machine caveat that these are sized
for ernst's 24 GB and **miralda's iGPU must not inherit 32768**, so they want to be
role settings rather than constants.

**Both horns, and it is reasonable either way:**

- **Land it.** It makes the measured configuration **durable and reviewable**,
  survives the reboot that currently reverts it, and — the strongest argument —
  closes [SN1](#sn1-the-model-tag-silently-sets-the-context-window) at the one
  place the hazard actually lives. It is independent of which agent wins.
- **Hold it.** Landing it means writing declarative configuration **before the
  agent decision that Phase 0 exists to inform**, which is the sequencing the
  phase structure was set up to protect. And a setting landed now is a setting
  reviewed against a bake-off that has not happened.

**Not resolved here. It is lgo's.** Verified 2026-08-25: `local-ai.nix`'s
`environmentVariables` block holds `ROCR_VISIBLE_DEVICES` and nothing else, so
none of this is landed and the 32768 in production is the model default.

### Honest scope — revised, and the revision matters

The brief framed the expected ceiling as a **model** limitation: 30B models
hallucinate tool arguments, cannot hold large contexts, will need Claude for
anything serious. **The measurements do not support the first claim at all.**

So the tiering conclusion stands but **its reasoning changes**, and the corrected
reasoning is what belongs here — because the next model upgrade will be evaluated
against whichever prior this file records:

- **The context ceiling is real and hard.** At 32768, `arr.nix` alone is 17k
  tokens — **52% of the window for one file**, and a milestone prompt from this
  document is 20k+ tokens on its own. A 30B at 32k **cannot hold a milestone-scale
  prompt and reason about a codebase at once.** That is arithmetic and it is not
  going away.
- **The tool-call failures are NOT a model ceiling and must not be recorded as
  one.** ~~They are a **parser bug with a named fix candidate** (the Modelfile
  template).~~ **Corrected 2026-08-26:** they are a model *formatting* slip —
  one dropped `<tool_call>` tag — and they are **fixed by four lines of system
  prompt** (5/40 → 80/80). The conclusion is unchanged and now better founded:
  this is not a ceiling, it is a prompt the client failed to send. Recording it
  as a model property would make the next 30B look no better than this one for
  reasons that have nothing to do with capability.

A milestone concluding *"the local agent handles a good fraction of daily work and
the rest still needs Claude"* remains the success condition. **But it should be
reached for the right reason.** Treat any claim of parity as a testing failure.

### Alternatives considered

**Agents.**

- **Crush** — Charm's fork. **FSL-1.1-MIT**: source-available, reverting to plain
  MIT two years after each release rather than permissive outright. A real
  difference for a repo whose stated preference is FOSS and auditability, and
  worth stating rather than filing as "open source".
- **Goose** — the Linux Foundation's Agentic AI Foundation. General-purpose and
  function-calling-driven, which points it straight at the one defect that was
  actually measured.
- **Cline / Kilo Code** — VS Code-shaped. Wrong for this workstation.
- **Codex CLI** — Apache-2.0, genuinely open, OpenAI-oriented.
- **Nanocoder** — MIT, **local inference by DEFAULT with cloud as explicit
  opt-in**, which is philosophically the closest thing to how this fleet runs.
  **Rejected on maturity (~2k stars), not on design** — that is a reason that
  expires, so **re-check it** rather than treating the rejection as settled.

**The naming situation, because it will otherwise waste a session.** There were
**two** projects called OpenCode. Charm acquired the original, the community
split, **Charm's version was renamed CRUSH**, and the SST-maintained fork kept the
name. **Then it moved again: `sst/opencode` → `anomalyco/opencode`** after the
team rebranded to Anomaly. Old references, Docker tags and flake inputs pointing
at `sst/opencode` break. **Record whichever the repo actually pins and the date
verified** — as of 2026-08-25 this repo pins nothing of its own: it uses
`pkgs.opencode` from the nixpkgs pin (`fcb8fcd`, 2026-08-09), version **1.15.10**,
so the naming question is nixpkgs' problem and not this repo's *until someone adds
a flake input*. Release cadence is extreme — three patch releases in four days in
August 2026 — so if an input is ever added, **record whether the pin is a tag or a
branch, and flag a branch as a problem.**

**Inference server, corrected.** **Ollama runs llama.cpp underneath**, so the
choice is about **wrapper and API surface**, not inference quality — which is
itself an argument against churning on it.

- **llama-swap + llama-server** — the escape hatch stays open, but **its trigger is
  now different**; see the tool-calling section. Do not take it on the original
  trigger.
- **vLLM** — still not the answer. ROCm targets CDNA / MI-series; RDNA3
  (`gfx1100`) is community-maintained and historically painful; it preallocates
  VRAM aggressively, which is exactly the wrong property on a card
  [M15](#m15-featernst-tdarr) has to arbitrate; and its batching advantage is
  worthless for one user.

### The prompt for the M11 remainder

````text
Read CLAUDE.md fully before doing anything.

Work in the clanarchy repo on miralda. Branch: feat/fleet-local-coding-agent.

READ M11 IN docs/roadmap.md FIRST, and read ~/.local/share/m11-bakeoff/
PHASE0-NOTES.md IN FULL. Phase 0 is DONE and its findings are not to be
re-derived. Where the roadmap summary and PHASE0-NOTES.md disagree, the file
wins.

THE HARNESS ALREADY EXISTS AND IS RE-RUNNABLE. Do not rebuild it.
  ~/.local/share/m11-bakeoff/
    README.md  PHASE0-NOTES.md
    bin/m11-tunnel  bin/m11-aider  bin/m11-opencode
    probes/{ctx-vram-probe,matrix,matrix-v1,matrix-long,
            toolcall-probe,toolcall-probe2,v1-probe}.sh
It is the instrument that produced every number in the roadmap section. If a
number looks wrong, re-run the probe before disbelieving the number — and
before believing it, because a broken grader nearly cost this milestone a
wrong conclusion once already (roadmap standing note SN3).

PORT 11434 IS TAKEN ON MIRALDA by its own local ollama. The tunnel to ernst
uses 11435:
    ssh -N -L 11435:127.0.0.1:11434 root@10.0.50.10
Anyone copying the obvious `ssh -L 11434:...` gets a bind failure — or, on a
machine where it does bind, silently talks to a LOCAL 7B at 4096 context and
produces a plausible, wrong bake-off result. Check what you are talking to
before trusting any measurement:
    curl -s localhost:11435/api/tags | jq -r '.models[].name'

════════════════════════════════════════════════════════════════════════════
PART 1 — THE HUMAN BAKE-OFF.  lgo's, not Claude's.  BLOCKING for Phase 1.
════════════════════════════════════════════════════════════════════════════
Three measurements are outstanding and a machine cannot produce them. If they
are not in this session, say so and STOP before naming a winner — naming one
on synthetic evidence is exactly what Phase 0's structure exists to prevent.

  (a) A MULTI-FILE clanarchy edit, driven end to end by each candidate. Not a
      smoke test. Something with a real dependency between files.
  (b) THE CLAUDE CODE COMPARISON, on the same tasks. The brief called this
      explicitly not optional: it is what turns tiering from a guess into
      evidence. Record the honest gap, including where the local agent won.
  (c) REAL-TASK tool-failure rates, as opposed to the 88 graded synthetic
      trials already done. The synthetic rate is ~30% UNPARSED_XML with full
      recovery on retry; the question is what that costs over real work.

Record all three the way Phase 0 recorded its numbers: what was run, what came
back, and what the instrument was.

════════════════════════════════════════════════════════════════════════════
PART 2 — CANDIDATE (C), AND IT NEEDS A DECISION NOT A DEFERRAL
════════════════════════════════════════════════════════════════════════════
codecompanion.nvim / avante.nvim were NOT evaluated in Phase 0 because an nvf
plugin cannot be added without touching the flake, and Phase 0 forbade that.
Owner: lgo.

It is the option best fitted to a nushell + zellij + foot + nvf workstation,
and it is the one most likely to be quietly forgotten BECAUSE it needs a flake
change. Either:
  - open a wip/ branch that installs it (nvf plugin, wired through
    programs.nvf.settings the way modules/users/lgo.nix already does, with
    inputs.nvf pinned as nvf.follows = "govim/nvf"), evaluate it against the
    same tasks as (a), or
  - record an explicit "not taking (C)" in docs/roadmap.md with the reason.
Do NOT let it lapse a second time.

════════════════════════════════════════════════════════════════════════════
PART 3 — THE TOOL-CALL FIX.  Correct the remedy, not just the diagnosis.
════════════════════════════════════════════════════════════════════════════
88 trials, ZERO invented arguments, ZERO missing arguments, ZERO refusals.
Every failure was ollama's template parser returning tool_calls: null on a
CORRECT native <function=…> XML call. Native /api/chat fails at the SAME rate
as /v1, so it is NOT the OpenAI shim.

THE FIX CANDIDATE IS A CORRECTED MODELFILE TEMPLATE IN OLLAMA. Try that first.
  - Extract the current template: `ollama show --modelfile qwen3-coder:30b`
  - The parser is template-driven, so the defect and the repair are in the
    same place.
  - Measure with probes/toolcall-probe2.sh before and after. A fix is a
    changed OK rate on the same probe, not a plausible-looking template.

DO NOT MIGRATE TO llama-swap + llama-server ON THE ORIGINAL TRIGGER. The brief
named "measured evidence that the /v1 shim mangles tool calls" as the trigger
and it has SUPERFICIALLY fired — but the diagnosis is different and llama-swap
would move the same template problem somewhere else. Ollama runs llama.cpp
underneath; the migration buys a different API surface, not better inference.
The migration case reopens ONLY if the template fix proves impossible. Record
which happened.

════════════════════════════════════════════════════════════════════════════
PART 4 — THE §7 DECLARATIVE QUESTION.  ASK LGO, DO NOT DECIDE IT.
════════════════════════════════════════════════════════════════════════════
PHASE0-NOTES.md §7 holds ready-to-land Nix for service-modules/local-ai.nix:
OLLAMA_CONTEXT_LENGTH=32768, OLLAMA_FLASH_ATTENTION=1, OLLAMA_KV_CACHE_TYPE=q8_0.
It is NOT landed (verified 2026-08-25: environmentVariables holds only
ROCR_VISIBLE_DEVICES), and the q8_0 setting currently lives in a
`systemctl edit --runtime` drop-in on ernst that dies on reboot.

Landing it makes the measured configuration durable and reviewable and closes
standing note SN1 at the place the hazard lives. Not landing it keeps Phase 0's
"nothing declarative" rule intact until the agent decision is made. Reasonable
either way; it is lgo's call.

IF IT IS LANDED: make them ROLE SETTINGS, not constants. They are sized for
ernst's 24 GB and miralda's 780M iGPU must not inherit 32768.

════════════════════════════════════════════════════════════════════════════
PHASE 1 — PACKAGE THE WINNER
════════════════════════════════════════════════════════════════════════════
Only after Part 1. Two corrections folded in from Phase 0:

IF OPENCODE WINS, PHASE 1 REPAIRS — DOES NOT EXTEND — WHAT clan.nix ALREADY
DECLARES. roles.opencode.machines.miralda already exists and its rendered
config HAS NEVER WORKED. opencode 1.15.10 rejects it: `Unrecognized key:
providers`. It is wrong four ways: providers -> provider; baseUrl ->
options.baseURL; no npm key (the provider needs @ai-sdk/openai-compatible or
it never loads); no models map.

  AND IT FAILS CLOSED, HARD. opencode MERGES config sources, so the broken
  store file ABORTS EVERY RUN. OPENCODE_CONFIG and OPENCODE_CONFIG_DIR were
  both tried; both still load it and both still choke. Only relocating
  XDG_CONFIG_HOME avoids it. A wrong Nix-rendered config in the store is not
  inert — it is fatal and un-overridable from the environment.

  AND THE CONFIG DIRECTORY MUST BE WRITABLE. opencode fetches ~15 MB of npm at
  runtime into it (@opencode-ai/plugin, @ai-sdk/openai-compatible). Today
  ~/.config/opencode is a read-only store symlink via xdg.configFile, so a
  plain Nix-rendered file DOES NOT SOLVE THIS. Hand it a writable directory
  AND a /persist entry, or it refetches after every rollback. Say in the file
  header which mechanism you chose and what it costs.

IF AIDER WINS: nixpkgs#aider-chat is a closed Python derivation with no
runtime fetch, so none of the above applies. The Phase 0 install was via
`nix profile`; Phase 1 makes it declarative. Carry over
~/.local/share/m11-bakeoff/aider.model.settings.yml rather than re-deriving it.

TRANSPORT STAYS THE SSH TUNNEL, ON PORT 11435, made durable as a systemd USER
unit (not a system unit — the tunnel is per-user and the agent runs as lgo).
NOTE THE 11434 COLLISION PROMINENTLY in the file header; it will bite anyone
who copies the obvious command.

NO NEW MAC, NO NEW ADDRESS, NO NEW uid. Ollama has its existing static uid;
the agent runs as lgo on the client. machines/ernst/networking.nix says this
explicitly so nobody adds one for symmetry.

════════════════════════════════════════════════════════════════════════════
PHASE 2 — NETWORK EXPOSURE.  OPTIONAL, AND SEPARATELY JUSTIFIED.
════════════════════════════════════════════════════════════════════════════
DO NOT TAKE THIS AS PART OF PHASE 1. Its trigger is A SECOND CLIENT ACTUALLY
NEEDING IT, not tidiness. If there is one client, the tunnel is the answer and
ernst's attack surface stays unchanged — which is what the ledger records as a
deliberate property of M11.

OLLAMA HAS NO AUTHENTICATION, AND ITS API INCLUDES MODEL PULL AND DELETE.
Treat it as an unauthenticated ADMIN endpoint, not as a read-only inference
service. That is the whole threat model.

RECOMMEND ZEROTIER ONLY. ZeroTier terminates in ernst's HOST netns, which is
where Ollama already lives, so it needs no new plumbing — no veth, no VLAN 90
address, no UDM-Pro rule, and no LAN listener at all. miralda keeps the tunnel.
Bind NARROWLY to the ZeroTier address; NEVER 0.0.0.0.

PROVE THE NEGATIVE. Use M2b's netns recipe (roadmap, "Diagnosing this from
ernst") to probe from VLAN 20 and show the port is unreachable:
    ip netns add p20; ip link add vb-p20 type veth peer name eth0p
    ip link set eth0p netns p20; ip link set vb-p20 master br0 up
    bridge vlan add dev vb-p20 vid 20 pvid untagged
    ... dhcpcd, then curl -m5 http://<ernst>:11434/api/tags
A positive test with no negative control is a failed phase.

════════════════════════════════════════════════════════════════════════════
NEVER RUN `opencode serve` AS A SHARED SERVICE.  IN ANY PHASE.
════════════════════════════════════════════════════════════════════════════
Upstream binds it to 127.0.0.1:3080 by design and warns against exposing it,
because THE AGENT CAN RUN SHELL COMMANDS. An exposed opencode server is remote
code execution with a nice TUI. The agent runs on each CLIENT; only Ollama is
ever shared. Headless-server mode looks like the natural homelab answer and it
is the wrong one — write that into the file header so a later session does not
"discover" it.

════════════════════════════════════════════════════════════════════════════
Constraints:
- Never commit to main. Branch first, PR via `gh pr create` (title
  imperative, <=70 chars, no prefix; body = summary + test plan + manual
  steps).
- Phase 1 may add a flake input only if the winner needs one; say so in the PR
  body and pin it by tag, never by branch (opencode shipped three patch
  releases in four days in August 2026).
- Minimal diffs; commit only the files this change touches.
- Verify by evaluation:
    nix flake check
    nix eval --no-update-lock-file --raw \
      '.#nixosConfigurations.miralda.config.system.build.toplevel.drvPath'
    nix eval --no-update-lock-file --raw \
      '.#nixosConfigurations.ernst.config.system.build.toplevel.drvPath'
- Claude does not deploy: `clan machines update <machine>` is lgo's step.
- Update docs/roadmap.md's status table in the same PR, and update standing
  note SN1 if the §7 block lands.
````

---

## M12 — `feat/ernst-arr-helpers`

**Status: DONE — deployed and merged 2026-08-26 (PR #100).** Five of the six
shipped; (a) Byparr is split out as [M12b](#m12b-featernst-byparr) and (e)
Unpackerr is measured out. All five units are active on ernst and `main` builds
byte-identical to the deployed generation.

**Two things outlive the merge and are not defects:**

1. **The first real recyclarr sync had not run at merge time** — the timer fires
   at 00:03. That run creates the two German profiles and **adopts Sonarr's
   existing `Remux + WEB 2160p`, which 59 series ride**. Watch the activity
   queue afterwards; the lever if it misbehaves is Sonarr's "Upgrade Until
   Custom Format Score" on that profile, not the Nix.
2. **Manual configuration is by design, not backlog.** Bazarr's language
   profiles, Cleanuparr's cleaners (enabled one at a time, unlinked/orphan
   last) and Radarr's MediathekArr download client all live in application
   databases. Faking them from Nix would create a second source of truth for
   state the applications own — the same call the *arr root folders lost.

The prompt at the end of this section is kept **as it was written**, so that what
it assumed and what turned out to be true can be compared — **four** of its
premises were false, and the sections below are the record of that.

### What actually shipped, and what the session falsified

**Phase A, re-run on the session's own date (2026-08-26) rather than trusted from
the 2026-08-25 table.** The table held: `bazarr` has a module (1.6.0),
`unpackerr` is packaged (0.15.2) with no module, and byparr / umlautadaptarr /
cleanuparr / mediathekarr have neither. Checked against `nixpkgs-unstable` too —
none of the four is there either, so there was no cheaper path.

**Three premises did not survive, and each cost real work:**

1. **Byparr is not Camoufox-based any more.** v3.0.4 (2026-08-18) is Playwright
   plus `invisible-playwright`. Packaging it needs three PyPI packages nixpkgs
   does not have (`invisible-playwright`, `invisible-core`, `playwright-captcha`),
   a pin of `playwright==1.60.*` against the **1.59.1** in ernst's nixpkgs,
   **Python 3.14 exactly**, and a **sealed patched-Firefox engine** that
   `invisible-core` downloads and verifies against its own digest at run time.
   The `/v1` route *does* still exist, so the drop-in claim itself is fine. Split
   out as **[M12b](#m12b-featernst-byparr)** — it is a browser-packaging
   milestone, and its realistic failure mode is a Byparr that starts, answers
   `/v1` and never solves a challenge.

2. **MediathekArr is TWO processes, and its `main` branch is a trap.** The
   Dockerfile at tag `v1.0-beta.12` publishes **two** projects and starts both:
   `MediathekArrServer` (Newznab indexer, **5008**) and `MediathekArrDownloader`
   (SABnzbd shim **and the setup wizard**, **5007**). Upstream's compose file
   publishes only 5007 and its README mentions only 5007, so packaging half the
   product — an indexer whose results nothing can download — is the easy
   mistake. Worse, **`main` is a diverged, OLDER tree than the tag**: it carries
   a single-process Dockerfile, a downloader that hardcodes its output directory
   relative to the assembly, and a routine that **downloads a static ffmpeg build
   from johnvansickle.com at run time**. Every signal points at `main` — it is
   the default branch, it is "8 commits ahead", and the repo's `pushed_at` is
   2026-08-10 — and all of those are wrong. The 8 commits are LICENSE and README
   edits; the 2026-08-10 push is *"Fix star history"*.

3. **Unpackerr is measured out.** M12 (e) made it conditional and the condition
   failed, decisively — see below.

**Everything else went as written**, including the parts that were warnings
rather than instructions: UmlautAdaptarr's ports really are `[::]:5005` and
`0.0.0.0:5006` rather than localhost, so the container firewall is genuinely
load-bearing rather than belt-and-braces.

### The measurements, all re-run rather than inherited

**(a) The exit country, 2026-08-26** — M12 required this specifically because a
measurement carried forward untested is the failure M2b's item 1 warns about:

| from | URL | result |
|---|---|---|
| the `arr` container | `https://eztvx.to/` | **200** |
| the IVPN exit | `https://eztvx.to/` | **451** |
| the IVPN exit | — | `95.211.172.88`, country **NL** (Leaseweb) |

Identical to M4's 2026-08-21 finding. It is a property of the **exit country**,
not of the solver, so it survives Byparr being deferred — and it is what decides
MediathekArr's placement in the *opposite* direction (see below).

**FlareSolverr's footprint, for the comparison M12b will need:** 243 MB resident,
842 MB peak.

**(e) Archive-delivered releases — the Unpackerr gate, 2026-08-26:**

| check | result |
|---|---|
| Sonarr, last 50 grabs | **50/50 torrent**, client qBittorrent |
| Radarr, entire history (30) | **30/30 torrent**, client qBittorrent |
| download clients configured | **one**, qBittorrent. No usenet client exists in either app |
| `*.rar *.r0[0-9] *.zip *.zipx *.7z` under `/srv/media/torrents` | **0**, out of 986 files |
| the same under `/srv/media/library` | **0** |

**SKIPPED.** There is nothing for it to unpack, and the reason is structural
rather than incidental: this stack has no usenet path at all. **The trigger to
revisit is a usenet download client being added** — not a hunch, and not the
passage of time. `uid 3013` stays reserved and unused, and
`machines/ernst/networking.nix` says so. `pkgs.unpackerr` exists (0.15.2) and
needs a unit, not a derivation, if that day comes.

### Packaging: three derivations, two shapes, and why neither is a flake input

**UmlautAdaptarr and Cleanuparr take the upstream RELEASE ARTIFACT**
(`linux-x64.zip`, `Cleanuparr-*-linux-amd64.zip`), because that is what upstream
publishes and **it is the same shape nixpkgs itself uses for the four
neighbouring services in the same container** — `prowlarr`, `radarr` and
`sonarr` are release tarballs, `bazarr` is a release zip. A hand-rolled
derivation that built from source with a nuget lock would be the odd one out.

**MediathekArr is built from source** with `buildDotnetModule`, because it
publishes **no release assets at all** — every release from `v1.0-beta.5` to
`v1.0-beta.12` has an empty assets array and the only binary channel is a Docker
image, which is precisely what M12 rejects.

**The prompt asked for flake inputs; the tree has pinned hashes instead**, and
the intent is kept in full — nothing tracks a moving target. The mechanism is
not, for the reason the recyclarr block already argues one file over: a flake
input is a row in `flake.lock` and `nix flake update` moves every row it can,
with nothing distinguishing "bump nixpkgs" from "silently move the
release-rewriting proxy in front of every indexer". A version and a hash in the
derivation cannot move without an edit, and the edit names the version. For a
published zip the flake-input form is also a poor mechanical fit — `github:`
inputs fetch a source tree, not an artifact.

**Three packaging findings worth carrying to M14**, which owes its own
derivations:

- **Self-contained .NET publishes need `autoPatchelfHook` and little else** —
  but CoreCLR's `libcoreclrtraceptprovider.so` wants `liblttng-ust.so.0` (LTTng
  2.12) and nixpkgs carries 2.14. It is dlopen'd only when tracing is switched
  on. Delete the file; do not pin an EOL tracing library into a media service's
  closure, and do not `--ignore-missing` it either — that leaves a broken `.so`
  that fails on the day somebody does turn tracing on.
- **Single-file self-contained publishes are different from ordinary ones.**
  Cleanuparr is one 197 MB ELF: `autoPatchelf` fixes only the outer apphost, and
  the bundled natives are extracted at *run* time, unpatched. They need
  `LD_LIBRARY_PATH` on the wrapper.
- **`Directory.GetCurrentDirectory()` is not the content root.** MediathekArr's
  wizard serves from `<cwd>/static/download`, so `ASPNETCORE_CONTENTROOT` does
  not help and the process aborts before binding. `makeWrapper --chdir` is the
  fix.

**Everything was smoke-tested locally before being wired in** — each binary run
by hand, ports and endpoints confirmed: UmlautAdaptarr binding 5005 + 5006,
Cleanuparr answering 200 on 11011 and creating its SQLite database, the
MediathekArr indexer returning a Newznab `caps` document on 5008, and the
downloader returning `{"version":"4.3.3"}` on 5007 with `mkvmerge` and `ffmpeg`
resolved from the store.

### Two decisions that departed from this milestone's own prompt

**UmlautAdaptarr takes `DynamicUser`, not the reserved uid 3010.** The prompt's
uid table assigns it 3010, "own group, no media access". The access half is kept
exactly; the static uid is not, and **M12's own rule is what overturns it**: *"a
service with no persistent state has no reason to make that switch at all."*
Verified against upstream rather than assumed — **no SQLite anywhere in the
repository, caching is `IMemoryCache`, and its `docker-compose.yml` declares no
volumes**. A static uid would buy nothing and cost the six directives
`DynamicUser` silently implies, which is the Prowlarr trap in reverse. **3010
stays reserved and unused**, with the reason recorded next to it, because a gap
in a numbering scheme with no explanation gets closed by the next person who
needs a number.

**The fork question: UmlautAdaptarr, not UmlautAdaptarrEX.** Surveyed
2026-08-26 — the original is C#, 303 stars, pushed 2026-08-10; **EX is a
TypeScript REWRITE**, not a fork: 28 stars, one author, four weeks old in its
current shape. Three reasons, and "it is canonical" is not one of them: (1) this
component sits in the request path of every indexer search in the stack and its
documented failure mode is already *works fine and does nothing*, which is the
worst possible property to pair with a young reimplementation; (2) **TRaSH's
German guide names the original**, and the recyclarr German profiles in this
same milestone are transcribed from that guide; (3) EX's advertised advantage is
**broader multi-language** handling, and this is a two-language household — it
buys nothing against the risk in (1). Revisit if the original goes quiet, not
because EX gets newer.

### What the first deploy actually found (2026-08-26)

**Deployed clean apart from two crash-loops, both dynamic-linking or
`$PATH` faults that no amount of evaluation could have caught — and, more
usefully, that BOTH LOCAL SMOKE TESTS MISSED for the same underlying reason.**

| unit | first deploy | cause |
|---|---|---|
| `bazarr` | **active**, 200 on 6767 | — |
| `cleanuparr` | **active**, 200 on 11011 | — |
| `mediathekarr-indexer` | **active**, serving Newznab on 5008 | — |
| `umlautadaptarr` | **crash-loop**, SIGABRT | `No usable version of libssl was found` |
| `mediathekarr-downloader` | **crash-loop**, SIGABRT | `error trying to start process 'which'` |

**The libssl one is the interesting one, because `autoPatchelf` reported "0
dependencies could not be satisfied" and was telling the truth.** .NET's OpenSSL
shim does not link against libssl at all:

```
patchelf --print-needed libSystem.Security.Cryptography.Native.OpenSsl.so
  libdl.so.2  libpthread.so.0  libc.so.6
patchelf --print-rpath  …
  (empty)
```

It `dlopen()`s `libssl.so.3` **by soname** at run time, probing a version list.
**A dlopen by soname is invisible to build-time ELF analysis**, so a clean
`autoPatchelf` run is not evidence of anything for a self-contained .NET
publish. Fixed with `openssl` on `LD_LIBRARY_PATH` via the wrapper — the same
treatment `cleanuparr.nix` already needed for its extracted bundle natives,
which is exactly why Cleanuparr came up first time and UmlautAdaptarr did not.

**The `which` one is a plain runtime dependency nobody would guess**:
MediathekArr's `FfmpegUtils` and `MkvMergeUtils` do not probe `$PATH`
themselves, they **shell out to `which`** and read its stdout. systemd's unit
`PATH` is coreutils/findutils/gnugrep/gnused/systemd and carries no `which`.

**THE LESSON IS ABOUT THE SMOKE TESTS, NOT THE TWO BUGS**, and it generalises to
every hand-rolled derivation M14 and M15 will need:

- The UmlautAdaptarr smoke test **proved the service BINDS, not that it can
  TALK** — it died on a stub *arr's malformed response before ever making an
  outbound HTTPS request. **Any future smoke test here needs one real outbound
  call.**
- The MediathekArr smoke test **inherited the tester's `$PATH`**, which had
  `which` in it, and logged a cheerful *"ffmpeg found in PATH"*. **A smoke test
  inherits an interactive environment; a unit does not.** Re-verify under
  `env -i` with a systemd-shaped `PATH`.

Both fixes were re-verified that way before being pushed.

**Two documentation defects also surfaced and are corrected in `arr.nix`:**

1. **The recyclarr preview command in the file did not work** — `recyclarr` is
   not on `$PATH` inside the container (`systemPackages` is deliberately just
   `curl`), so it failed with `runuser: failed to execute recyclarr: Permission
   denied`, which reads like a permissions fault and is a PATH one. The working
   form derives the binary from `systemctl show recyclarr -p ExecStart`.
   **And a trap in reading its output**: `/var/lib/recyclarr/config.yml` is
   regenerated by `ExecStartPre`, *not* by the deploy, so straight after a
   rebuild a preview faithfully processes the **previous** generation's instance
   list. The real check that the new instances are deployed is
   `systemctl cat recyclarr | grep -c LoadCredential` — one per `_secret`, i.e.
   **five** with M12's three extra instances (verified).
2. **A security claim in the header was false.** It said the API keys are
   "never in config.yml on disk". The recyclarr module's `ExecStartPre`
   **substitutes them in plaintext** into `/var/lib/recyclarr/config.yml`, which
   is `-rw-r--r--` in a `drwxr-xr-x` directory. Left as-is deliberately — every
   tenant of this container is already trusted with *arr API access — but the
   claim is corrected in place, with the condition that would change it.

### The recyclarr block was WRONG, and the deploy is what proved it

**Recyclarr deduplicates on `base_url`, not on instance name.** M12's first
attempt gave each new profile its own instance (`sonarr.series-german`, and so
on) on the strength of this repo's own "instance names must be unique" warning.
Unique names are **necessary and not sufficient**. Measured on ernst with
`--log debug`:

```
[DBG] Split instances: [
  {"BaseUrl":"http://localhost:7878","InstanceNames":["movies","movies-german"]},
  {"BaseUrl":"http://localhost:8989","InstanceNames":["series","series-german","series-remux-2160p"]}]
```

…and then it **synced nothing and exited 0** — the same fails-by-succeeding bug
the M4 header already documented, on a dimension the warning did not cover. At
the default log level the command prints two "Initializing provider" lines and
stops, which looks like success. **The check is the ABSENCE of "Processing" and
"Completed at".**

**The rule is now: ONE INSTANCE PER SERVER, ALWAYS.** Extra profiles go in
`quality_profiles`; the cross-contamination worry that motivated separate
instances is solved properly by **`assign_scores_to`** on each
`custom_format_groups.add` entry, referencing profiles by `trash_id` (a name can
be changed in the *arr UI, silently detaching the scores). Every group carries an
explicit `assign_scores_to`, including single-target ones — relying on the
"applies to all guide-backed profiles" default is exactly what made the block's
correctness change the moment a second profile appeared.

Corrected and re-previewed against the live instances: both servers now report
`Processing` and `Completed at`.

### The profile census, re-measured — and one number this repo had wrong

Taken from each app's `/api/v3` endpoints, 2026-08-26:

| Sonarr — 139 series | upgradeAllowed | count |
|---|---|---|
| `HD-1080p` | false | 67 |
| `HD - 720p/1080p` | false | 13 |
| **`Remux + WEB 2160p`** | **true** | **59** |
| `Ultra-HD` | false | **0** |

| Radarr — 2432 movies | upgradeAllowed | count |
|---|---|---|
| **`Ultra-HD`** | false | **2389** |
| `Remux + WEB 2160p` | true | 27 |
| `HD - 720p/1080p` | false | 16 |

**M4's "133 series on a hand-made `upgradeAllowed = false` Ultra-HD profile" is
false, and appears to have conflated the two services.** Sonarr's Ultra-HD is
*empty*; the 2389-on-Ultra-HD pile is **Radarr's**. The bulk-edit safety rule is
unchanged and now rests on correct numbers — the hazard is on the film side,
where a mass promotion could pull most of a 13 TB library against ~47.6 TB free.

**Consequence for M12 (g): the Sonarr Remux-2160p profile ADOPTS, it does not
create.** Sonarr already has a profile named exactly `Remux + WEB 2160p` with
**59 of its 139 series on it**, upgradeAllowed = true. Syncing the guide profile
under its guide name takes that profile over and rewrites it, with
`reset_unmatched_scores` zeroing every CF the configured groups do not name.
**lgo chose adoption on 2026-08-26**, with the consequence stated: those 59
series can have their current files fall below the new cutoff and queue 2160p
upgrade searches. The alternative — an explicit `name` so recyclarr builds a
separate profile and leaves the existing one alone — was considered and rejected
because bringing the profile actually in use into line with TRaSH is the point.
**Watch the activity queue after the first real sync**; the lever if it misbehaves
is Sonarr's "Upgrade Until Custom Format Score" on that profile, not the Nix.

### UmlautAdaptarr is INERT here, and the reason is architectural

**M12 called (b) the highest-value item in the milestone. That judgement assumed
an indexer set this fleet does not have.** Established 2026-08-26, after the
deploy, by reading upstream's source rather than its README:

1. **All six Prowlarr indexers are `Cardigann`** — EZTV, LimeTorrents, Nyaa.si,
   The Pirate Bay, TorrentDownload, YTS. Every one a definition-driven **HTML
   scraper**, all torrent protocol. Cardigann's Site Link is a select populated
   from the bundled YAML definition, so the `https` → `http` edit the upstream
   README requires **cannot be made**. That is the symptom, not the cause.
2. **Both integration modes converge on the same requirement.**
   `HttpProxyService` (5006) rewrites an intercepted request to
   `http://localhost:5005/{apiKey}/{host}{pathAndQuery}`; `SearchController`'s
   routes are constrained on the **Newznab `t=`** parameter; and
   `UrlUtilities.BuildUrl` does `new UriBuilder("https", domain)`. So either way
   it fetches **the indexer's own Newznab/Torznab API** and rewrites the XML.
   **The target must speak Newznab/Torznab at its own domain.** A Cardigann
   tracker speaks HTML, and Prowlarr is what turns that into Torznab — *inside*
   Prowlarr, after the proxy hop.
3. **So M12's manual step 2 would have BROKEN searches, not enabled them.** A
   Cardigann request carries no `t=`, no route matches, UmlautAdaptarr answers
   **404**. Tagging those six indexers with the proxy would have taken all six
   offline. The read-only Site Link dropdown is the only reason it did not
   happen. **The instruction in this milestone's manual steps was wrong and is
   corrected there.**
4. **The non-proxy mode is not an escape.** `IsValidDomain` demands a dotted
   host and the scheme is hardcoded to https, so pointing it at Prowlarr's own
   Torznab — which really is XML over plain http — is rejected twice over.

**It stays deployed.** It runs clean (`NRestarts=0`) and does real work that
costs nothing: it syncs Sonarr's 139 series and resolves German titles for
**130** of them. The day an indexer with a real API is added it becomes useful
with a UI change and no deploy, and removing it would mean re-deriving all of the
above later. **The trigger to revisit is an indexer with an API, not a Prowlarr
update.**

**Same root cause as the Unpackerr finding**: this stack is 100% torrent, 100%
Cardigann, with no usenet path at all. Two of M12's six items turned out to
depend on a usenet-shaped library that does not exist here — worth weighing
before M14 assumes otherwise.

**Radarr is disabled in UmlautAdaptarr's config, and not by preference.**
Upstream lists "Radarr Support — in Arbeit" and the codebase agrees:
`Providers/` holds `ArrClientBase`, `SonarrClient`, `LidarrClient` and
`ReadarrClient` — **there is no `RadarrClient.cs`**. With
`Radarr__0__Enabled=true` the journal showed only `Init SonarrClient (Sonarr)`
and never mentioned Radarr: the setting was accepted and silently ignored. It is
now set to `false` rather than deleted, so the answer lives next to the switch.

### MediathekArr: 5007 is the one that matters, and 5008 is not in any path

**Corrected after the deploy.** M12's packaging notes say the indexer on 5008 is
"what Prowlarr is pointed at". It is not. The setup wizard runs inside the
**downloader** and registers the Prowlarr indexer against
`http://localhost:5007` — and that works, because **5007 serves the full
Newznab API too**. Asked both ports the same question:

```
curl 'http://localhost:5007/api?t=tvsearch&q=Tatort'   → total="3012"
curl 'http://localhost:5008/api?t=tvsearch&q=Tatort'   → total="3012"
```

Byte-identical, correctly-formatted release titles from both. So the downloader
is self-sufficient and **nothing points at 5008**.

**Both units are kept anyway**, and the reason is not inertia: only the indexer
registers `RulesetBackgroundService`, which refreshes per-show naming rules from
`mediathekarr.pcjones.de` on a timer — the downloader's journal shows no ruleset
activity at all. One matching query is not evidence that ruleset upkeep is
irrelevant, and inferring that from a single result is the species of mistake
this milestone has already made four times. It costs ~90 MB (the downloader is
~70 MB). **Revisit only by first answering whether 5007 gets its rulesets some
other way.**

**Was the two-process packaging still worth it?** Yes, but not for the reason
predicted. The value was not "Prowlarr needs 5008" — it was that building only
`MediathekArrServer`, which upstream's repo Dockerfile at `main` suggests, would
have shipped **no SABnzbd endpoint at all** and no wizard, i.e. an indexer whose
results nothing could download and no way to configure it.

### Three things the deploy will decide, which evaluation cannot

1. **`ProtectSystem = "strict"` on five new units.** The same call-out M4 made
   for sonarr/radarr: if one fails to start with *"Read-only file system"*, add
   the path it names to `ReadWritePaths`, or drop to `ProtectSystem = "full"`.
   A loud, pre-diagnosed failure is worth more than an untightened unit.
2. **Bazarr's first start against a bind-mounted `/var/lib/bazarr`.** Radarr
   needed an explicit `.config` tmpfiles rule for exactly this shape (an
   unsafe-path-transition refusal two levels above the error message). Bazarr's
   module declares only `dataDir` itself, so there is no nested implicit parent
   and it should not repeat — but "should not" is why it is on this list.
3. **`arr-api-keys` on a cold boot.** It now gates UmlautAdaptarr as well as
   recyclarr, and it exits 1 if either `config.xml` is unreadable. That is
   fail-closed and correct; `Restart = on-failure` with `RestartSec = 30s` is
   what makes it recover rather than stay down.

### The recyclarr additions are three new INSTANCES, not three new profiles

The trap here is real and quiet: **`custom_format_groups` is declared per
INSTANCE, not per profile**, so every group in a block is scored onto every
profile in that block. Appending the German profile to the existing
`sonarr.series` block would push the English WEB-1080p group set onto the German
profile and the German unwanted-formats set onto the English one — a config that
syncs cleanly and scores nonsense. Separate instances keep each profile with the
groups its TRaSH template pairs it with, which is what *"transcribe whole
custom-format groups"* is actually protecting.

Added, all transcribed from config-templates @ `9faf65f` (the rev the existing
blocks already name, so one `git show` checks the whole file):

| instance | profile | template |
|---|---|---|
| `radarr.movies-german` | `[German] Remux + WEB 2160p` | `radarr/templates/german-uhd-remux-web.yml` |
| `sonarr.series-german` | `[German] HD Bluray + WEB` | `sonarr/templates/german-hd-bluray-web.yml` |
| `sonarr.series-remux-2160p` | `Remux + WEB 2160p` | `sonarr/templates/remux-web-2160p.yml` |

The German profiles are pitched to **match** their English counterparts rather
than sit below them — UHD for films, HD for series — because a German profile a
step below the English one would make *"upgrade to German when it appears"* a
downgrade in everything except language.

**An Anime profile was ASKED FOR and DECLINED (2026-08-26)**, as M12 (g)
requires. Recorded so it is not re-litigated; reopen it as a fourth instance,
never by extending one of the blocks above.

**Profilarr stays REJECTED.** Same job, but it keeps state in its own database.

### Hardening: measured before and after

`systemd-analyze security --offline=true --root=<toplevel>`, 2026-08-26:

| unit | upstream / bare | this file |
|---|---|---|
| `bazarr` | **9.0 UNSAFE** | **1.4 OK** |
| `umlautadaptarr` | 9.4 UNSAFE | **1.3 OK** |
| `cleanuparr` | 9.0 UNSAFE | **1.4 OK** |
| `mediathekarr-indexer` | 9.0 UNSAFE | **1.4 OK** |
| `mediathekarr-downloader` | 9.0 UNSAFE | **1.4 OK** |
| `arr-api-keys` (renamed) | 9.4 UNSAFE | 1.0 OK (unchanged) |
| `prowlarr` / `sonarr` / `radarr` | — | 1.3 OK (unchanged) |
| `flaresolverr` | 3.0 OK | 3.0 OK (untouched) |
| `recyclarr` | 3.9 OK | 3.9 OK (untouched) |

**Bazarr's 9.0 is real upstream, and it is the finding.** The nixpkgs module
sets `Type`, `User`, `Group`, `SyslogIdentifier`, `ExecStart`, `Restart`,
`KillSignal` and `SuccessExitStatus` — and **no hardening directive of any
kind**. Not a reduced set like Prowlarr's: none. So the block in `arr.nix` is
not a tightening of upstream's choices, it is the whole of them. The other four
have no upstream unit at all, so their baseline is the unit anybody would write
first (`Type`, `User`, `Group`, `ExecStart`), measured against the same nixpkgs.

### Ports: three added to the one list, four deliberately kept off it

The Traefik source-restriction in `containers/arr.nix` is a `concatMapStrings`
over one explicit list, and extending it is the whole mechanism — no second
mechanism, and **not** `extraInputRules`, which is consumed only under nftables
and would produce no rule and no warning.

**Added** (browser UIs, so they also get ordinary Traefik routers behind
Authelia, plus a name in `protectedHosts` — deny-by-default means a route
without one fails *closed*): `bazarr` 6767, `cleanuparr` 11011, `mediathekarr`
5007.

**Kept off**, which is the more important half: `flaresolverr` 8191 (as before),
the MediathekArr **indexer** 5008, and UmlautAdaptarr's **5005 and 5006**. All
three of those bind `0.0.0.0`/`[::]` rather than localhost — measured — so
inside the container's netns they are on the veth, and the only thing keeping
them off VLAN 90 is that the list does not name them and the chain ends in
`nixos-fw-log-refuse`. **5006 in particular is an HTTP proxy**, i.e. the same
class of gift as FlareSolverr's 8191.

### Manual steps — lgo's, and required before any of this does anything

None of these can be faked from Nix without creating a second source of truth
for state the applications own; that is the same call the *arr root folders lost.

1. **DNS**: `bazarr`, `cleanuparr` and `mediathekarr` under `goclan.org` in
   Technitium, pointing at Traefik. The M5 wildcard certificate already covers
   all three.
2. ~~**UmlautAdaptarr in Prowlarr.** Every indexer URL must change `https` →
   `http`…~~ **WITHDRAWN — this step is wrong for this fleet and would have
   broken all six indexers.** See
   [UmlautAdaptarr is INERT here](#umlautadaptarr-is-inert-here-and-the-reason-is-architectural).
   Cardigann indexers cannot take an `http` Site Link, and if they could, the
   proxy would answer **404** to every request because a Cardigann fetch carries
   no Newznab `t=` parameter. **Do nothing in Prowlarr.**
3. **MediathekArr**: open `https://mediathekarr.goclan.org/download` and run
   **Open Setup & Migration Wizard**. It does most of the work itself — done
   2026-08-26, and what it actually wired was:
   - `POST /api/v3/downloadclient` on **Sonarr** — SABnzbd, `localhost:5007`,
     **URL Base `download`**, category `tv`;
   - `POST /api/v1/indexer` on **Prowlarr** — Newznab at
     `http://localhost:5007` (**not** 5008; see below), which Prowlarr's
     `fullSync` then pushed to both Sonarr and Radarr automatically.

   **The wizard only offers Sonarr, so Radarr's download client is the one
   manual step left**: Radarr → Settings → Download Clients → **SABnzbd**,
   host `localhost`, port `5007`, **URL Base `download`**, category `movies`,
   SSL off. The API key is not validated (`Settings__ApiKey` is unset, so
   `AssureApiKey` accepts anything) — any value works.

   **URL Base is an ADVANCED field and the form hides it by default.** Flip
   "Advanced Settings: Shown" at the top of any Settings page first, or it does
   not appear at all. Without it the test fails as

   ```
   Unable to connect to SABnzbd, HTTP request failed: [400:BadRequest]
   [GET] at [http://localhost:5007/api?mode=get_config&apikey=x&output=json]
   ```

   which reads like a connectivity or auth fault and is neither: `/api` on 5007
   is the **Newznab indexer** endpoint, and it returns 400 because
   `mode=get_config` is not a Newznab query. The SABnzbd shim lives at
   `/download/api`, which answers 200 with `complete_dir` set to
   `/srv/media/torrents/mediathek/complete`. Sonarr has the field set because
   the wizard wrote it through the API, where the advanced flag does not apply.
   **Expect thin coverage regardless**: upstream lists Radarr support as
   *"limited, WIP"* — "you can find a few movies via interactive search, but
   not a lot… you can however find all movies via a text search in Prowlarr
   and send the result to Radarr."

   **`/var/lib/mediathekarr` staying empty is correct, not a failure.** The
   wizard configures the *arrs, not itself; MediathekArr's own settings —
   paths, categories, parallelism — come from the environment variables
   declared in `arr.nix`, so `mediathekarr.json` is never written. That is the
   better outcome for this repo: the config is a reviewable diff rather than a
   file nobody can reconstruct.
4. **Bazarr**: provider credentials, then **German and English profiles in both
   directions** — German subtitles on English content *and* English on German.
   Configuring only one is the common half-done outcome.
5. **Cleanuparr**: every cleaner starts **disabled**. Turn them on one at a
   time, and leave the unlinked/orphan handling for last — it reasons about
   hardlink counts on the tree whose hardlink correctness is the point of M3
   and M4.
6. **Recyclarr never reassigns a title.** Promote titles to the new profiles
   **INDIVIDUALLY**. Re-measured 2026-08-26 (see the census above): the
   bulk-edit hazard is mostly on the **Radarr** side — 2389 of 2432 films sit
   on a hand-made `upgradeAllowed = false` "Ultra-HD" profile, and every TRaSH
   profile ships `upgradeAllowed = true`. Mass-promoting those would queue most
   of a 13 TB film library against ~47.6 TB free, through the VPN.
   **One exception to "never assigned":** Sonarr's `Remux + WEB 2160p` is
   adopted, not created — 59 series are already on it. Watch the activity queue
   after the first real sync.

---

**Goal.** Six additions to the *arr stack, **all inside the existing `arr`
container**: Byparr replacing FlareSolverr, UmlautAdaptarr, Bazarr, Cleanuparr,
MediathekArr, and a set of recyclarr additions.

**Depends on.** M4. **Risk.** Medium — five of the six need hand-rolled
derivations, and that is the point.

**Why it is first.** No new veth, no new MAC, no new DHCP reservation, no UDM-Pro
work at all. **It proves the hand-rolled-derivation approach that M14 depends on
without touching a network boundary** — so a milestone that goes wrong goes wrong
in one place, and the packaging risk and the networking risk are never in flight
together.

### (a) Byparr replaces FlareSolverr

**Drop-in**: same port `8191`, same `/v1` API, same Prowlarr indexer-proxy entry.
Camoufox-based rather than undetected-chromedriver, because **FlareSolverr fails
on 2026 Cloudflare Turnstile and Managed Challenges** — which is the capability
the thing exists to provide.

**`arr.nix`'s FlareSolverr rationale transfers and must be preserved verbatim in
substance:**

- **`DynamicUser = true`.** FlareSolverr keeps upstream's, and Byparr must too.
  There is no persistent state — only a `RuntimeDirectory` — so **the Prowlarr
  trap cannot fire here**. M4 switched Prowlarr to a static uid and had to restate
  six hardening options `DynamicUser` had been implying; a service with nothing to
  persist has no reason to pay that.
- **NOT in group `media`.** The boundary protecting the library is the **uid**,
  not the container. `/srv/media`'s `2770 root:media` directories stay closed to
  it.
- **`8191` is absent from the firewall list and stays absent.** Its entire API is
  *"fetch this URL for me"* — **an SSRF primitive with a web API in front.** That
  sentence is the reason, and it should survive the rename.

**RE-RUN M4's MEASUREMENT. DO NOT INHERIT IT.** `curl https://eztvx.to/` from the
arr container **and** from the IVPN exit; record both status codes. M4 measured
`200` vs `451 Unavailable For Legal Reasons` on 2026-08-21, and that finding is a
property of **the exit country** (Leaseweb NL) rather than of the solver — Byparr
does not change it. But **a measurement carried forward untested is the failure
M2b's item 1 warns about**, and M11 has just produced a fresh example of exactly
that: a premise that survived unchecked into a brief and was false. Two minutes of
`curl` settles it.

Also record **memory footprint against FlareSolverr**. Camoufox is a patched
Firefox; undetected-chromedriver is a patched Chromium. They are not the same
weight and the container has other tenants.

### (b) UmlautAdaptarr

**Highest-value item in this milestone**, and the reason should be written out
rather than assumed.

German releases with umlauts are **not imported correctly**, are often **not found
at all** (the *arrs search `o` for `ö`), and Sonarr/Radarr **always expect the
English TMDB/TVDB title** — which breaks German productions and translations
outright. The characteristic symptom is *"Found matching series/movie via grab
history, but release was matched to series by ID"*. **TRaSH's German
quality-profile guide recommends it by name.**

**The mechanism decides where it goes.** It **presents itself to the *arrs as an
indexer** but actually **sits between them and the real indexer**, rewriting
searches and results and renaming releases so the *arrs recognise them.

**Two traps, and the second is the dangerous one:**

1. **Configure it in PROWLARR, not per-arr.** Per-arr configuration costs a speed
   penalty on multi-indexer search.
2. **Every indexer URL must change `https` → `http`** so it can intercept locally;
   outbound to the real indexer stays `https`. **AN INDEXER LEFT ON `https` WORKS
   FINE AND SILENTLY BYPASSES IT ENTIRELY.** Nothing breaks, nothing logs, and the
   umlaut handling this milestone exists for simply does not happen for that
   indexer. **Fails-by-succeeding — the third documented instance in this repo**,
   alongside recyclarr's duplicate-instance bug (green timer, exit 0, syncing
   nothing) and [M11's silent truncation](#the-context-trap-proven-with-numbers)
   (HTTP 200, 76% of the prompt discarded, a fabricated answer). **Check every
   indexer explicitly and put the list in the PR body.**

A fork exists, **UmlautAdaptarrEX**, with broader multi-language handling.
**Evaluate both, pick one, and argue it** — do not pick the fork because it is
newer or the original because it is canonical.

### (c) Bazarr

**Upstream module — confirmed present in ernst's pin, 2026-08-25.**

Bazarr writes `.srt` sidecars **next to the media**, so **`media` must be its
PRIMARY group** — the same `PrivateUsers = true` reason `sonarr` and `radarr` have
it. `arr.nix`'s header explains that in full; **refer to it, do not re-derive it.**

German and English profiles, **both directions** — a two-language household wants
German subtitles on English content and English subtitles on German content, and
configuring only one is the common half-done outcome.

### (d) Cleanuparr

**It retires three things, which is why they are not added:** **Decluttarr**,
**Huntarr** and **Checkrr**. Record that, so a later session does not "discover"
one of them.

Beyond stalled / blocked / malicious cleanup — it exists because of `*.lnk` and
`*.zipx` files getting stuck in queues — it does **missing-content search**,
**cutoff-unmet search**, and **custom-format score upgrade search with score
tracking**.

**The part that matters here:** it removes downloads that are **orphaned, have no
hardlinks, or are no longer referenced by the arrs**. That turns **M4's link-count
invariant from something proven once with `stat` into something a service watches
continuously** — which is a genuine upgrade to the property this whole stack rests
on.

**Configure conservatively on the first deploy.** A cleaner that deletes is a
cleaner that can delete the wrong thing, and this one reasons about hardlink
counts on a tree whose hardlink correctness is the entire point of M3 and M4.

### (e) Unpackerr — CONDITIONAL on a measurement

**Check the last ~50 grabs for archive-delivered releases.** If there are none,
**record that and SKIP IT**, and write the finding into the roadmap so it is not
re-litigated in six months.

**Packaging note, measured 2026-08-25 and contradicting an earlier draft of this
milestone:** `pkgs.unpackerr` **exists** in ernst's pin at **0.15.2**. There is
**no `services.unpackerr` module**, so it still needs a unit written by hand — but
it does **not** need a derivation.

### (f) MediathekArr

ARD / ZDF Mediathek as a Prowlarr indexer. It answers a stated complaint: the
MediathekViewer Jellyfin plugin is poor.

**The mechanism changes the uid decision.** It pretends to be **both**: a usenet
**INDEXER** (parsing MediathekViewWeb) **and** a SABnzbd **DOWNLOADER** (fetching
video and subtitles over plain HTTP from the Mediatheken). **Unlike Prowlarr it
DOES write to `/srv/media` and DOES need a `media`-group uid.** Prowlarr's "no
media access at all" argument does not transfer, and assuming it does would
produce a service that fails on its first download.

**It talks to the internet on its own behalf, so argue it explicitly against
invariant #1** rather than filing it under "it's in the arr container already".
The argument is probably yes, and it should be made in FlareSolverr's shape —
measured and stated, not waved through:

- public-broadcaster HTTP, not tracker traffic;
- no killswitch value — there is nothing here a VPN protects;
- and **the exit-country problem runs the OTHER way**: these are German services
  best reached from a **German** IP, so the microvm tier's IVPN exit (Leaseweb NL)
  would be the wrong side of the same coin M4 measured at `451`.

**NOTE FOR M8: this changes whether M8 needs to exist.** Cross-referenced from
[the M8 amendment](#what-the-arr-ecosystem-does-and-does-not-provide-here-surveyed-2026-08),
which turns it into a Phase 0 question ahead of M8's existing ones.

### (g) recyclarr additions — not a new service

The recyclarr block is **already inlined with provenance** (config-templates @
`9faf65f`) because M4 discovered that v8's official templates are *starter
configs*, not include-able fragments. **Keep that shape.** Three additions:

- **German quality profiles**, from TRaSH's German guide. The behaviour to
  configure: **grab the best English release first, then upgrade to German /
  German-DL when one appears**, upgrading until *"Upgrade Until Custom Format
  Score"*. This is the companion to (b) — the profiles decide what is wanted, and
  UmlautAdaptarr is what makes it findable.
- **A Remux-2160p profile for SONARR**, created alongside and **assigned
  PER-SERIES**. **M4 measured why**: 133 series sit on a hand-made
  `upgradeAllowed = false` "Ultra-HD" profile, and a bulk reassignment would queue
  a re-download of most of **6.1 TB** of television plus the same again for
  **13 TB** of films — roughly **the whole 47.6 TB of free space, through the
  VPN**. **The rule is individual promotion.** Restate it in the file header;
  someone will eventually "tidy up" with a bulk edit and this is the sentence that
  has to stop them.
- **An Anime profile if lgo wants it. Ask rather than assume** — it is a
  substantial custom-format set for content nobody has said they watch.

**TRANSCRIBE WHOLE CUSTOM-FORMAT GROUPS.** TRaSH's own guidance: scores and CF
combinations are **tested together to prevent download loops**, and most undesired
results come from changing scores or omitting CFs that work together. A
half-transcribed group is not a smaller version of the same thing.

**DO NOT ADD PROFILARR.** Same job, but it keeps state in **its own database**;
the Nix attrset is a reviewable diff with recorded provenance and is strictly
better here. **Record the rejection** so a later session does not discover it as a
missing piece.

### Packaging and hardening

`virtualisation.oci-containers` **inside an nspawn container is REJECTED** — see
[the packaging constraint](#packaging-the-constraint-shaping-m12-m14-and-m15).

Every new unit gets `systemd-analyze security --offline=true`, before/after in the
PR body, following M4's table. **Watch for the Prowlarr trap in reverse**: any
upstream unit shipping `DynamicUser = true` that gets switched to a static uid
**silently loses `NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`,
`ProtectHome=read-only`, `RemoveIPC` and `RestrictSUIDSGID`**, because
`DynamicUser` implies all six and upstream sets none explicitly. **Restate all
six.** M4 measured Prowlarr at **8.2 EXPOSED** before this was caught.

### Ports and uids

**No new MAC, no new address, no DHCP reservation, no UDM-Pro rule.** Everything
lands in the existing `arr` container on `10.0.90.13`.

The container's Traefik source-restriction is generated by a `concatMapStrings`
over **one explicit port list** (`[ prowlarrPort sonarrPort radarrPort ]` in
`containers/arr.nix`). **EXTEND THAT LIST.** Do not add a second mechanism, and
**do not reach for `extraInputRules`** — it is declared unconditionally but
consumed only under `networking.nftables`, so it would produce **no rule and no
warning**. M5 recorded that trap; this is where it would next be stepped in.

uids are reserved in `machines/ernst/networking.nix`: **3009 bazarr, 3010
umlautadaptarr, 3011 cleanuparr, 3012 mediathekarr, 3013 unpackerr**. Byparr takes
**no uid** — it keeps upstream's `DynamicUser`, exactly as FlareSolverr does.

````text
Read CLAUDE.md fully before doing anything.

Work in the clanarchy repo on miralda. Branch: feat/ernst-arr-helpers.
Prerequisite: M4 deployed (it is). Read M12 in docs/roadmap.md first — the
decisions below are recorded there with their reasoning. Do not re-litigate
them; if you overturn one, argue it in a file-header comment.

SHAPE. Everything lands in the EXISTING container,
machines/ernst/containers/arr.nix. NO new veth, NO new MAC, NO new DHCP
reservation, NO UDM-Pro work. That is deliberate: this milestone proves the
hand-rolled-derivation approach M14 depends on WITHOUT touching a network
boundary, so packaging risk and networking risk are never in flight together.

(a) BYPARR REPLACES FLARESOLVERR. Drop-in: same port 8191, same /v1 API, same
    Prowlarr indexer-proxy entry. Camoufox-based rather than
    undetected-chromedriver, because FlareSolverr fails on 2026 Cloudflare
    Turnstile and Managed Challenges.
    PRESERVE arr.nix's FlareSolverr rationale, it transfers intact:
      - DynamicUser = true. No persistent state, only RuntimeDirectory, so
        the Prowlarr trap cannot fire. Do NOT give it a static uid.
      - NOT in group media. The boundary protecting the library is the uid,
        not the container.
      - 8191 ABSENT from the firewall list, and it stays absent: its entire
        API is "fetch this URL for me" — an SSRF primitive with a web API in
        front.
    RE-RUN M4's MEASUREMENT, DO NOT INHERIT IT:
        curl -o /dev/null -w '%{http_code}\n' https://eztvx.to/
    from the arr container AND from the IVPN exit. Record both. M4's
    200-vs-451 finding is a property of the exit COUNTRY, not of the solver,
    and Byparr does not change it — but a measurement carried forward untested
    is the failure M2b's item 1 warns about, and M11 just produced a fresh
    example of a premise that survived unchecked into a brief.
    Also record memory footprint against FlareSolverr.

(b) UMLAUTADAPTARR. Highest-value item; write out WHY in the file header.
    German releases with umlauts are not imported correctly, are often not
    FOUND at all (the *arrs search "o" for "ö"), and Sonarr/Radarr always
    expect the English TMDB/TVDB title — breaking German productions and
    translations, with the symptom "Found matching series/movie via grab
    history, but release was matched to series by ID". TRaSH's German
    quality-profile guide recommends it by name.
    It presents itself to the *arrs as an INDEXER but actually sits BETWEEN
    them and the real indexer, rewriting searches and results and renaming
    releases so the *arrs recognise them.
    TWO TRAPS:
      - Configure it in PROWLARR, not per-arr, or multi-indexer search takes
        a speed penalty.
      - Every indexer URL must change https -> http so it can intercept
        locally; outbound to the indexer stays https. AN INDEXER LEFT ON
        https WORKS FINE AND SILENTLY BYPASSES IT ENTIRELY. Check every
        indexer explicitly and put the list in the PR body.
    A fork exists (UmlautAdaptarrEX) with broader multi-language handling.
    Evaluate both, pick one, ARGUE it.

(c) BAZARR. Upstream module — CONFIRMED present in ernst's pin 2026-08-25.
    It writes .srt sidecars NEXT TO THE MEDIA, so group media must be its
    PRIMARY group, for the same PrivateUsers = true reason sonarr and radarr
    have it. arr.nix's header explains it — refer, do not re-derive.
    German and English profiles, BOTH directions.

(d) CLEANUPARR. It RETIRES three things, therefore do not add them and record
    that: Decluttarr, Huntarr, Checkrr.
    Beyond stalled/blocked/malicious cleanup (it exists because of *.lnk and
    *.zipx files getting stuck), it does missing-content search, cutoff-unmet
    search, and custom-format score upgrade search with score tracking.
    THE PART THAT MATTERS: it removes downloads that are orphaned, have no
    hardlinks, or are no longer referenced by the arrs. That turns M4's
    link-count invariant from something proven once with `stat` into
    something a service watches continuously.
    CONFIGURE CONSERVATIVELY ON FIRST DEPLOY. A cleaner that deletes is a
    cleaner that can delete the wrong thing.

(e) UNPACKERR — CONDITIONAL ON A MEASUREMENT. Check the last ~50 grabs for
    archive-delivered releases. If there are none, RECORD THAT AND SKIP IT,
    writing the finding into docs/roadmap.md so it is not re-litigated.
    NOTE: pkgs.unpackerr EXISTS (0.15.2, verified 2026-08-25) — there is no
    services.unpackerr module, so it needs a unit but NOT a derivation.

(f) MEDIATHEKARR. ARD/ZDF Mediathek as a Prowlarr indexer. Answers a stated
    complaint: the MediathekViewer Jellyfin plugin is poor.
    THE MECHANISM CHANGES THE UID DECISION: it pretends to be a usenet
    INDEXER (parsing MediathekViewWeb) AND a SABnzbd DOWNLOADER (fetching
    video and subtitles over plain HTTP from the Mediatheken). Unlike
    Prowlarr it DOES write to /srv/media and DOES need a media-group uid.
    It talks to the internet on its own behalf — ARGUE EXPLICITLY against
    invariant #1 whether that is acceptable in the nspawn tier, in
    FlareSolverr's shape. Probably yes: public broadcaster HTTP not tracker
    traffic, no killswitch value, and the exit-country problem runs the OTHER
    way since these are German services best reached from a German IP. But
    ARGUE it, do not wave it through.
    CROSS-REFERENCE M8: this changes whether M8 needs to exist.

(g) RECYCLARR ADDITIONS — not a new service. The block is inlined with
    provenance (config-templates @ 9faf65f) because v8's templates are
    starter configs, not include-able fragments. KEEP THAT SHAPE.
      - German quality profiles from TRaSH's German guide: grab the best
        English release first, upgrade to German/German-DL when one appears,
        upgrading until "Upgrade Until Custom Format Score". Companion to (b).
      - A Remux-2160p profile for SONARR, created alongside, assigned
        PER-SERIES. M4 measured why: 133 series on a hand-made
        upgradeAllowed=false "Ultra-HD" profile, and bulk reassignment would
        queue a re-download of most of 6.1 TB plus the same again for 13 TB
        of films — roughly the whole 47.6 TB of free space, through the VPN.
        THE RULE IS INDIVIDUAL PROMOTION. Restate it in the header; someone
        will "tidy up" with a bulk edit.
      - An Anime profile IF LGO WANTS IT. ASK, do not assume.
    TRANSCRIBE WHOLE CUSTOM-FORMAT GROUPS. TRaSH's guidance: scores and CF
    combinations are tested together to prevent download loops, and most
    undesired results come from changing scores or omitting CFs that work
    together.
    DO NOT ADD PROFILARR. Same job, state in its own database; the Nix
    attrset is a reviewable diff with recorded provenance and is strictly
    better. RECORD the rejection so a later session does not "discover" it.

PACKAGING. Phase A of this milestone is to establish which of these have
upstream modules AS OF THE SESSION DATE, and to use THAT list rather than any
list written earlier — including the one in docs/roadmap.md. As of 2026-08-25:
bazarr has a module; unpackerr has a package but no module; byparr,
umlautadaptarr, cleanuparr and mediathekarr have neither and need hand-rolled
derivations pinned as flake inputs.
  virtualisation.oci-containers INSIDE an nspawn container is REJECTED. State
  this in the file header. It would be faster and it is a real regression from
  what arr.nix is: a container whose entire value is that upstream units,
  upstream hardening and systemd-analyze scores are legible. A Docker image
  inside it is opaque to every one of those. The escape hatch when upstream
  ships only an image is the PODMAN TIER invariant #1 already names and M9 is
  opening — not oci-containers-in-nspawn.

HARDENING. `systemd-analyze security --offline=true` on every new unit,
before/after in the PR body, following M4's table.
  WATCH FOR THE PROWLARR TRAP IN REVERSE: any upstream unit shipping
  DynamicUser = true that gets switched to a static uid SILENTLY loses
  NoNewPrivileges, PrivateTmp, ProtectSystem=strict, ProtectHome=read-only,
  RemoveIPC and RestrictSUIDSGID, because DynamicUser implies all six and
  upstream sets none explicitly. RESTATE ALL SIX. M4 measured Prowlarr at
  8.2 EXPOSED before this was caught.

PORTS. Append to the ONE explicit list already in arr.nix — the Traefik
source-restriction is a concatMapStrings over it. Do NOT add a second
mechanism, and do NOT reach for extraInputRules, which is declared
unconditionally but consumed only under nftables and would produce no rule and
no warning.
  Candidates: bazarr 6767, umlautadaptarr 5005/5006, cleanuparr 11011.
  VERIFY EACH against upstream defaults; do not trust this list.

UIDS, reserved in machines/ernst/networking.nix — do not invent new ones:
  3009 bazarr (media primary), 3010 umlautadaptarr (own group, no media
  access — a proxy, same argument as prowlarr), 3011 cleanuparr (media
  primary; it DELETES files and needs write), 3012 mediathekarr (media
  primary; it downloads over HTTP), 3013 unpackerr (media primary,
  CONDITIONAL on (e)).
  Byparr gets NO uid — it keeps upstream DynamicUser, like FlareSolverr.

LEDGER: M12 creates no interim rule and opens no port reachable outside the
container. The roadmap already says so; leave that row alone.

Constraints:
- Never commit to main. Branch first, PR via `gh pr create` (title
  imperative, <=70 chars, no prefix; body = summary + test plan + manual
  steps).
- New flake inputs ARE expected here (the hand-rolled derivations). Pin each
  by tag or rev, never by branch, and say in the PR body what each one is.
- Minimal diffs; commit only the files this change touches.
- Verify by evaluation:
    nix flake check
    nix eval --no-update-lock-file --raw \
      '.#nixosConfigurations.ernst.config.system.build.toplevel.drvPath'
- Claude does not deploy: `clan machines update ernst` and
  `clan vars generate ernst` are lgo's steps.
- Update docs/roadmap.md's status table in the same PR.
````

---

## M12b — `feat/ernst-byparr`

**Split out of [M12](#m12-featernst-arr-helpers) on 2026-08-26**, before any code
was written, because the milestone's own description of it was wrong and what it
actually needs is a browser-packaging job rather than an arr-helper one.

**Goal, unchanged.** Replace FlareSolverr with Byparr: same port `8191`, same
`/v1` API, same Prowlarr indexer-proxy entry. **FlareSolverr fails on 2026
Cloudflare Turnstile and Managed Challenges**, which is the capability the thing
exists to provide, so this does not go away — it waits.

**Depends on.** M12 (deployed). **Risk.** High, and concentrated in one place.

### What the M12 session established, so this one does not re-derive it

- **`POST /v1` still exists** in v3.0.4 (`src/endpoints.py`, alongside `GET /`
  → `/docs` and `GET /health`). The drop-in claim holds.
- **It is NOT Camoufox.** `pyproject.toml` at v3.0.4 lists `fastapi[standard]`,
  `invisible-playwright`, `playwright==1.60.*`, `playwright-captcha`,
  `pydantic`, `pydantic-settings`, `trafilatura`. The browser is a **patched
  Firefox driven through Playwright**.
- **`requires-python = "==3.14.*"`.** ernst's pin has `python314` (3.14.6), so
  this one is available — it is just not the default `python3` (3.13.14).
- **The playwright pin conflicts.** Byparr wants `1.60.*`; ernst's nixpkgs has
  **1.59.1** for both `playwright` and `playwright-driver`. Note
  `invisible-playwright` itself declares `playwright<=1.61.0,>=1.55`, so the
  1.59.1 in the pin satisfies *it* — the conflict is Byparr's own pin, and
  whether relaxing it is safe is a question for this milestone, not an
  assumption.
- **Three PyPI packages are missing from nixpkgs**, checked against ernst's pin
  **and** `nixpkgs-unstable`: `invisible-playwright`, `invisible-core` (which
  `invisible-playwright` depends on and which owns the download machinery), and
  `playwright-captcha`.
- **The engine is fetched, sealed, and verified at run time.**
  `invisible-playwright fetch` delegates to `invisible_core.download`, which
  checks a cached engine against a **seal** before downloading and refuses
  anything that does not match (`invisible_core.seal.active_seal`,
  `verify_engine`). That is *good* news for packaging — a digest exists — but
  the URL and digest have to be extracted from `invisible_core` and pinned as a
  fixed-output derivation. **This is the milestone's real work.**
- **Upstream's own Dockerfile pins `ubuntu:24.04`** with the comment that
  Playwright 1.58 is incompatible with Ubuntu 26.04. Read that before assuming
  the stock nixpkgs Firefox will do.

### The failure mode to design against, stated up front

**Do not ship a Byparr that runs on stock `playwright-driver.browsers` Firefox
because it was easier.** `invisible-playwright` *is* the stealth layer; without
it the service starts, answers `/v1`, returns 200s, and never solves a
challenge. That is the fourth instance of the fails-by-succeeding shape this repo
keeps paying for, and it would be the most expensive one yet because it would
look like a working replacement.

**The acceptance test is therefore not "it starts".** It is a real Cloudflare
challenge solved end to end — the M12 measurement gives the instrument:
`https://eztvx.to/` returns **200 with a `cdn-cgi/challenge-platform` body** from
the arr container, i.e. a *solvable* challenge rather than a 451 refusal.

### What carries over from M12 unchanged

- **`DynamicUser = true`**, `RuntimeDirectory` only, **not** in group `media`.
  No persistent state, so the Prowlarr trap cannot fire. FlareSolverr's shape.
- **`8191` is ABSENT from the firewall list in `containers/arr.nix` and stays
  absent.** Its entire API is *"fetch this URL for me"* — an SSRF primitive with
  a web API in front. Prowlarr reaches it on `127.0.0.1`.
- **The exit-country measurement holds** (200 from the container, 451 from the
  Leaseweb NL exit, re-run 2026-08-26). It is a property of the exit country,
  not of the solver, so Byparr does not change it and it keeps this in the
  nspawn tier.
- **Record memory against FlareSolverr's measured baseline: 243 MB resident,
  842 MB peak.** Camoufox was a patched Firefox and so is this, but a Playwright
  Firefox is not the same weight as an undetected-chromedriver Chromium, and the
  container has six other tenants now.

**If it turns out the engine cannot be pinned reproducibly**, say so and stop —
the podman tier invariant #1 names, which [M9](#m9-featernst-tubesync) is
opening, is the escape hatch for an upstream that only ships an image.
**`virtualisation.oci-containers` inside the nspawn container remains rejected.**

---

## M12c — library profile reassignment

**Requested by lgo on 2026-08-26**, during M12's deploy, as the answer to a
problem M12 deliberately refused to solve: recyclarr creates and maintains
quality profiles but **never assigns a title to one**, and this library's titles
are on profiles that predate the guides.

**Goal.** Decide, by Q&A, what "high quality" and "low quality" mean for shows
and for films in this household — then have an agent do the reassignment, title
by title, against those rules.

**Depends on.** M12 deployed and its recyclarr profiles synced at least once, so
the target profiles exist and their custom-format scores are settled.

### Why this is a milestone and not a chore

**Every other milestone in this repo has been about a config that can be
reviewed as a diff. This one changes a database, 2571 rows at a time, and the
mistake is not reversible by `git revert`.** The starting position, measured
2026-08-26:

| Sonarr — 139 series | upgradeAllowed | count |
|---|---|---|
| `HD-1080p` | false | 67 |
| `HD - 720p/1080p` | false | 13 |
| `Remux + WEB 2160p` | **true** | 59 |
| `Ultra-HD` | false | 0 |

| Radarr — 2432 movies | upgradeAllowed | count |
|---|---|---|
| `Ultra-HD` | false | **2389** |
| `Remux + WEB 2160p` | **true** | 27 |
| `HD - 720p/1080p` | false | 16 |

**The hazard is the film side and it is the whole reason the "individual
promotion" rule exists.** 2389 films sit on a non-upgrading profile. Every TRaSH
profile ships `upgradeAllowed = true`. Move them all at once and Radarr queues
an upgrade search for each — against a 13 TB library and ~47.6 TB of free space,
through the VPN. **A rule engine that gets its rules slightly wrong does this
faster than a human with a multi-select box, not slower.**

### The shape it should take

**Phase 0 — the Q&A, and it is the milestone's actual content.** The rules are
lgo's, not the agent's, and they have to be written down before anything moves.
At minimum:

- What earns 2160p? Everything that exists in it, or a named list — franchises,
  anything with an Atmos/DV track, anything above some TMDB rating, recent
  releases only?
- What is the floor? Is `HD - 720p/1080p` a deliberate "I do not care about
  this" tier, or historical accident?
- **German-language titles**: M12 added `[German] Remux + WEB 2160p` and
  `[German] HD Bluray + WEB`. Does a German production go to a German profile
  automatically, or only when a German release actually exists?
- **Does anything move DOWN?** Demotion is the cheap half — it frees space and
  triggers no downloads — and is probably where a first pass should start.
- What must never be touched at all?

**Phase 1 — classify, do not act.** The agent reads both libraries through the
`/api/v3` endpoints and emits a **proposed** mapping: current profile → target
profile, per title, with the rule that fired. That file is reviewed as a diff.
**This is the deliverable of Phase 1; nothing is written to either app.**

**Phase 2 — apply, in batches, demotions first.** `PUT /api/v3/movie/editor`
and Sonarr's `/api/v3/seriesEditor` take bulk edits, so batching is native.
Rules that must hold:

- **Demotions and no-op moves first**, in one batch, and confirm the queue stays
  empty afterwards.
- **Promotions in small batches with the queue watched between them.** The
  measurement that matters is Radarr's activity queue depth and `zdata` free
  space, not the count of rows changed.
- **`searchForMovie` / monitored-search must be OFF for the edit itself.** The
  editor endpoint can trigger a search on change; that flag is the difference
  between "reassigned 400 films" and "queued 400 downloads".

**Phase 3 — record the rules where they will be re-read.** The rules belong in
the repo even though the state they produce does not. A later session that finds
a title on an odd profile needs to know whether that was a rule or a mistake.

### The one thing that must not be assumed

**Recyclarr will fight this if the rules disagree with it.** It owns the profile
*definitions* and rewrites them on every sync; this milestone owns the
*assignments*. Those are separable — but only as long as nobody solves an
assignment problem by editing a profile's cutoff in the UI, because the next
recyclarr run will revert it and the reassignment will look like it drifted.

---

## M13 — `feat/ernst-media-lifecycle`

**Goal.** Close the loop between *requesting* media and *reaping* it: Jellyseerr
at internal scope, Janitorr for disk-space-aware deletion, Scraparr for *arr
metrics, and four more exporter targets for M6.

**Depends on.** M6. **M7 IS DONE** — read its actual configuration rather than
planning around a dependency. [M7's close-out](#close-out-2026-08-25) enumerates
exactly which routers carry forward-auth today.

**Risk.** Medium, and concentrated in one place: **Janitorr deletes things.**

### Close-out (2026-08-26) — what was built, and the four premises that failed

Everything below this heading is the milestone **as planned**. This section is
what the session actually found. Where the two disagree, this section is right
and the planning text is left in place unedited, so the difference stays
visible.

**Shipped, all inside the existing `arr` container — no new veth, MAC, DHCP
reservation or UDM-Pro rule:** Jellyseerr at internal scope, Janitorr in
dry-run, Scraparr, and three M6 exporter targets.

**1. `services.jellyseerr` no longer exists under that name.** In ernst's own
pin it is a `mkRenamedOptionModule` alias for **`services.seerr`**, the package
attribute is `seerr` (3.2.0), and the 26.05 rename also moved the state path —
`StateDirectory=seerr` at `/var/lib/seerr`, gated on `stateVersion >= 26.05`.
The bind mount had to land on the new path; the old one would have been
silently unpersisted. The uid table's name is kept as `jellyseerr` deliberately.

**2. Janitorr publishes NO artifact.** Its GitHub releases carry **zero
assets** — the only distribution channel is `ghcr.io/schaka/janitorr`, built by
`bootBuildImage --publishImage`, i.e. a **Paketo buildpack image** rather than a
jar. `virtualisation.oci-containers` inside an nspawn container is rejected for
this repo, so this became the first **from-source Gradle build** here: Spring
Boot 4.1.1, Kotlin 2.4.10, JDK 25, a committed 350-artifact `mitm-cache` deps
lock. Four things made it non-obvious, all written up in
`machines/ernst/containers/pkgs/janitorr.nix` — the load-bearing one being that
`build.gradle.kts` pins `vendor.set(JvmVendorSpec.ADOPTIUM)`, so `pkgs.jdk25`
fails the toolchain match and `foojay-resolver` tries to **download a JDK** in
the sandbox. `temurin-bin-25` plus `auto-download=false` fixes it.

It built on the first real attempt. The bug that *did* bite was a `callPackage`
trap: a `jre_headless ? temurin-bin-25` default is never used, because
`jre_headless` **exists in nixpkgs** and is Java 21 — so the derivation built
fine and the jar died at runtime with `UnsupportedClassVersionError` (class file
69 vs 65). Only running the built wrapper catches that.

**3. Ollama serves no `/metrics`.** Measured on ernst, 2026-08-26, ollama
0.32.3: `GET /metrics` → **404**, `GET /api/tags` → 200. The target is
**dropped**, not deferred-in-place: a job that can only ever be down is worse
than no job. **Handed to [M15](#m15-featernst-tdarr)**, which wants the series
anyway and should scrape **the card, not Ollama** — its arbitration covers three
claimants and Ollama's own view cannot see the other two. Note ernst's pin has
`prometheus-nvidia-gpu-exporter` and **no AMD equivalent**, so that is a
hand-rolled derivation when M15 gets there.

**4. Jellystat is deferred, and upstream agrees.** It has no nixpkgs package, is
a Vite SPA plus an Express backend, and needs **PostgreSQL** — which this
container does not have. More decisively, Janitorr's own example compose now
says, verbatim: *"New users without an existing stats setup should only enable
janitorr-stats and skip Jellystat/Streamystats entirely."* So the watch-history
feed is a `janitorr-stats` question, not a Jellystat one — and neither is needed
for the space-based expiry M13 ships.

**Also corrected, smaller:**

- **Janitorr has no web UI at all** — zero `@RestController`/`@Controller`
  classes at v2.2.0, no static resources, and upstream says "You don't have to
  publish ANY ports." It nonetheless *binds* one because spring-boot-webmvc is
  on the classpath, so its port is pinned to 8978 **and bound to 127.0.0.1**,
  and it is routed nowhere and firewalled nowhere. The roadmap's "janitorr 8978"
  was a port to close, not to open.
- **Scraparr's env-var mode does support multiple instances** at v3.1.0
  (`SONARR_PROD_URL` alias form) *and* `*_API_KEY_FILE`. The roadmap's stated
  reason for the file-based path has expired; its conclusion has not.
- **node_exporter's `zfs` collector was re-enabled on ernst only.** M6's comment
  claimed the dedicated pool exporter "supersedes" it. It does not — the pool
  exporter answers *health/capacity/fragmentation*, the collector answers *ARC*.
  New `exporters.arc` option, on for ernst, off for the laptops.
- **Two new source-restriction rules were needed that the plan did not
  anticipate**, both because a scrape is not a browser: the `arr` container now
  accepts 7100 from the monitoring container, and `jellyfin` accepts 8096 from
  both the `arr` container (Janitorr's API calls) and the monitoring container.
- **The qBittorrent exporter overturns a stated decision** in
  `microvms/wg-qbittorrent.nix` — "the hash, not the password, reaches the
  guest". An exporter must *present* a credential, and a PBKDF2 verifier cannot
  be replayed, so the plaintext is now staged 0400 root:root and handed over via
  `LoadCredential`. The two alternatives (the WebUI API Key, already measured at
  HTTP 403; and disabling `LocalHostAuth`) are both worse.
- `pkgs.prometheus-qbittorrent-exporter` is **martabal/qbit-exp** (Rust), not
  esanchezm's Python exporter of the same descriptive name. Different
  environment variables entirely.

**Hardening**, `systemd-analyze security --offline=true`, measured against a
baseline built with no hardening at all:

| unit | before | after |
|---|---|---|
| `seerr` | 6.1 MEDIUM (stock module, `DynamicUser`) | **1.4 OK** |
| `janitorr` | 9.0 UNSAFE | **2.8 OK** |
| `janitorr-config` | 9.4 UNSAFE | **1.2 OK** |
| `scraparr` | 9.0 UNSAFE | **1.4 OK** |
| `qbittorrent-exporter` (in the microvm) | — (new unit, `DynamicUser` kept) | **1.6 OK** |

`janitorr` is the highest of the four because it deliberately carries **no
`SystemCallFilter`**: a JVM needs `@privileged`-adjacent calls during class
loading, and a filter that kills the runtime unpredictably is worse than none.
The reasoning is beside the unit.

**One bug was caught by `systemd-analyze verify` and is worth propagating.**
`RuntimeDirectoryUser=` and `RuntimeDirectoryGroup=` **are not systemd
directives.** The NixOS module accepts them, writes them into the unit, and
systemd drops them with `Unknown key … ignoring` — a journal line and nothing
else. `janitorr-config` runs as root, so `/run/janitorr` would have been
`root:root 0750` and Janitorr (group `media`) could not have **traversed** it to
read its own config: the same "group needs x on the directory, not just r on the
file" failure `microvms/wg-qbittorrent.nix` already documents. Ownership comes
from the unit's own `User=`/`Group=`, or from an explicit `chown`. **Run
`systemd-analyze verify` on new units, not just `systemd-analyze security`** —
the second one scores a unit without noticing that a directive is fictional.

### Jellyseerr — internal scope only, and the split is deliberate

**Confirmed wanted.** And **lgo has decided it must be reachable from the
INTERNET.** **THAT IS SPLIT INTO [M16](#m16-featernst-external-ingress) AND MUST
NOT BE IMPLEMENTED HERE.**

M13 ships it at **internal scope**: a Traefik router **without** the mgmt-only
middleware, reachable from LAN and IoT. **No new UDM-Pro rule** — invariant #3's
one permanent consumer rule (`LAN + IoT → traefik:443`) already exists as
*"Allow Traefik"*.

**CONFIRM AGAINST THE LIVE POLICY, NOT THE LEDGER.** M6 found the live source
list had **silently lost `Servers`** while the ledger row claimed all three
networks. Table and device have demonstrably disagreed before, and this is a
milestone that assumes the rule rather than creating one.

**Why internal first, widened in M16, deliberately.** The household proves the
request workflow before an ingress boundary is added — and the external change
then gets reviewed **as an external change**, rather than as one line in a
library-cleanup milestone. That is the same reasoning that gave M2b its own
milestone instead of folding it into Jellyfin.

**AUTHELIA NOW EXISTS — and Jellyseerr does NOT go behind it in M13.** M16 decides
the external auth posture; doing it now and reworking it there is **two changes to
one router**. M13's posture is **Jellyseerr's own Jellyfin-account login**, which
is also the credential the household already has.

### Janitorr

Disk-space-aware reaping across **Radarr, Sonarr, Jellyseerr and Jellyfin**:
remote deletion, tag-based schedules, tag-based exclusions, configurable
expiration.

**Three constraints, all of them first-deploy constraints:**

1. **Dry-run is enabled in the shipped config template and the first deploy keeps
   it.** Read what it would have deleted before letting it delete.
2. **Jellyfin deletion needs a real USER, not an API key.** Create a dedicated
   one. This is an in-UI step and therefore an lgo manual step, not something the
   session can fake.
3. **It only picks up media the *arrs downloaded.** Anything imported by hand, or
   arriving via MediathekArr's own path, is invisible to it — say so out loud
   rather than discovering it as a gap.

**Additionally enable the *arr Recycle Bin on the first deploy.** Two independent
safety nets on the first run of a deleting service is not belt-and-braces, it is
the minimum for a service pointed at 47 TB.

**With Jellyseerr confirmed, the Jellyseerr integration is LOAD-BEARING rather
than a nicety.** Without it, reaped media leaves **orphaned requests**, and the
household **re-requests things that were deleted on purpose** — a loop that
consumes the bandwidth the reaping was meant to save and looks, from the couch,
exactly like the system being broken.

**It does NOT delete after watching.** That is a different tool, and someone will
expect it to. Write that into the file header.

### Scraparr, not Exportarr

**Record the rejection.** Exportarr needs **one instance per app**, each with its
own uid, its own port and its own firewall line — in a container whose entire
philosophy is *"one list in one place"* and whose Traefik source-restriction is
literally a `concatMapStrings` over a single explicit port list. Scraparr is **one
service, one port (`7100`), one config**, multi-instance via aliases.

**It supports `*_API_KEY_FILE`, which maps onto systemd `LoadCredential=`.**
**REUSE M4's `recyclarr-api-keys` oneshot rather than building a second staging
mechanism.** M4's argument holds unchanged and is worth restating: the keys are
generated **by the apps themselves** into their own `config.xml`, so reading them
there keeps **one source of truth** and **survives a UI key rotation with no
deploy**. A prompted clan var would be a second copy with no link to the first.

**Env-var mode does NOT support multiple instances** — so the file-based path is
not merely tidier, it is the only one that works here.

### The exporter fleet, as M6 targets

- **Jellyfin's NATIVE `/metrics` endpoint** — enable it in Jellyfin's config.
  **No exporter. Do not add one.**
- **A qBittorrent exporter.** Note it lives in the microvm guest, so its scrape
  path is the same VLAN-90 layer-2 hop the *arr already use.
- **node_exporter's `zfs` collector** for pool health and ARC. Note M6
  **deliberately disabled** the `zfs` collector on the laptops and runs a
  dedicated pool exporter on ernst — check which one actually answers the question
  before adding a second source for it.
- **Jellystat** for playback analytics. **Not Prometheus** — but it feeds
  **Janitorr's expiry logic**, which is what earns it a slot in this milestone
  rather than a backlog entry.
- **NO TDARR EXPORTER.** That arrives with [M15](#m15-featernst-tdarr), which owns
  it because queue depth is only meaningful once there is a queue.

**ADD AN OLLAMA TARGET.** [M11](#m11-featfleet-local-coding-agent) turned Ollama
from a background convenience into **interactive tooling**, and
[M15's arbitration](#m15-featernst-tdarr) will need **VRAM-occupancy history that
predates it**. M11 measured **22482 MiB at 64k with q8_0 against a 24560 MiB
card** — **2078 MiB of headroom**. That margin is thin enough that having the
trend *before* M15 starts is worth more than adding it afterwards and waiting a
month for data.

### Shape, ports and uids

Jellyseerr, Janitorr and Scraparr all land in the **existing `arr` container**
unless the session argues otherwise; none of them needs its own L2 identity, and
M12 has already established the pattern for extending the port list.

uids reserved in `machines/ernst/networking.nix`: **3014 jellyseerr** (own group —
**no media access**, it requests rather than writes), **3015 janitorr** (`media`
primary — **it deletes files**), **3016 scraparr** (own group — it reads REST APIs
only).

Ports to verify against upstream defaults, not to trust from here: **jellyseerr
5055**, **janitorr 8978**, **scraparr 7100**. Append to the one explicit list;
`extraInputRules` would produce no rule and no warning.

**Ledger: no interim rows.** Jellyseerr's router is invariant #3 working as
designed. See [the ledger note](#interim-rule-ledger).

````text
Read CLAUDE.md fully before doing anything.

Work in the clanarchy repo on miralda. Branch: feat/ernst-media-lifecycle.
Prerequisite: M6 deployed (it is). Read M13 in docs/roadmap.md first.

M7 IS DONE. Read machines/ernst/containers/{traefik,authelia}.nix and the M7
close-out in docs/roadmap.md for what is ACTUALLY behind forward-auth today —
prowlarr, sonarr, radarr, grafana; jellyfin deliberately not; auth.goclan.org
necessarily not. Do not plan around M7 as a dependency and do not re-derive
its configuration.

GOAL. Close the loop between requesting media and reaping it.

JELLYSEERR — INTERNAL SCOPE ONLY.
  lgo has decided Jellyseerr must eventually be reachable FROM THE INTERNET.
  THAT IS M16 AND MUST NOT BE IMPLEMENTED HERE. If you find yourself editing
  anything about WAN ingress, stop — you are in the wrong milestone.
  M13 ships a Traefik router with NO mgmt-only middleware, reachable from LAN
  and IoT, riding the existing permanent "Allow Traefik" ZBF rule. No new
  UDM-Pro rule.
  CONFIRM AGAINST THE LIVE POLICY, NOT THE LEDGER. M6 found the live source
  list had silently lost `Servers` while the ledger claimed all three
  networks. Table and device have demonstrably disagreed before.
  DO NOT put Jellyseerr behind forward-auth in M13. M16 decides the external
  auth posture, and doing it now then reworking it there is two changes to one
  router. M13's posture is Jellyseerr's own Jellyfin-account login.
  Internal first / widen in M16 is deliberate: the household proves the
  request workflow before an ingress boundary is added, and the external
  change then gets reviewed AS an external change rather than as a line in a
  library-cleanup milestone.

JANITORR. Disk-space-aware reaping across Radarr, Sonarr, Jellyseerr and
Jellyfin: remote deletion, tag-based schedules, tag-based exclusions,
configurable expiration.
  THREE CONSTRAINTS:
    - Dry-run is enabled in the shipped config template and THE FIRST DEPLOY
      KEEPS IT. Read what it would have deleted before letting it delete.
    - Jellyfin deletion needs a real USER, not an API key. Create a dedicated
      one — an lgo manual step for the PR body, not something you can fake.
    - It only picks up media the *arrs downloaded. Say so out loud.
  ADDITIONALLY ENABLE THE *ARR RECYCLE BIN on first deploy.
  With Jellyseerr confirmed, the Jellyseerr integration is LOAD-BEARING:
  without it, reaped media leaves orphaned requests and the household
  re-requests things deleted on purpose.
  It does NOT delete after watching. That is a different tool and someone will
  expect it to — write that into the file header.

SCRAPARR, NOT EXPORTARR. RECORD THE REJECTION: Exportarr needs one instance
per app, each with its own uid, port and firewall line, in a container whose
philosophy is "one list in one place". Scraparr is one service, one port
(7100), one config, multi-instance via aliases.
  It supports *_API_KEY_FILE, which maps onto systemd LoadCredential=. REUSE
  M4's recyclarr-api-keys oneshot rather than building a second staging
  mechanism: the keys are generated BY THE APPS into their own config.xml, so
  reading them there keeps one source of truth and survives a UI key rotation
  with no deploy.
  ENV-VAR MODE DOES NOT SUPPORT MULTIPLE INSTANCES — the file path is the only
  one that works, not merely the tidier one.

EXPORTER FLEET, as M6 targets:
  - Jellyfin's NATIVE /metrics endpoint (enable in its config — NO exporter,
    do not add one).
  - A qBittorrent exporter.
  - node_exporter's zfs collector for pool health and ARC. NOTE: M6
    deliberately disabled the zfs collector on the laptops and runs a
    dedicated pool exporter on ernst — check which one answers the question
    before adding a second source.
  - Jellystat for playback analytics. Not Prometheus, but it feeds Janitorr's
    expiry logic, which is what earns it a slot here.
  - NO TDARR EXPORTER — that arrives with M15, which owns it.
  - ADD AN OLLAMA TARGET. M11 made it interactive tooling rather than a
    background convenience, and M15's GPU arbitration will need VRAM-occupancy
    history that PREDATES it. M11 measured 22482 MiB at 64k with q8_0 against
    a 24560 MiB card — 2078 MiB of headroom. Having the trend before M15
    starts is worth more than adding it after and waiting a month for data.

SHAPE. Jellyseerr, Janitorr and Scraparr land in the EXISTING arr container
unless you argue otherwise in a file-header comment. None needs its own L2
identity.

PORTS: append to the ONE explicit list in arr.nix that the Traefik
source-restriction concatMapStrings iterates. Do NOT add a second mechanism,
and do NOT reach for extraInputRules (declared unconditionally, consumed only
under nftables — no rule, no warning). Candidates to VERIFY against upstream
defaults: jellyseerr 5055, janitorr 8978, scraparr 7100.

UIDS, reserved in machines/ernst/networking.nix — do not invent new ones:
  3014 jellyseerr (own group, NO media access), 3015 janitorr (media primary,
  it deletes files), 3016 scraparr (own group, reads REST APIs only).

PACKAGING. Establish IN-SESSION which of these have upstream modules and use
THAT list, not this one. As of 2026-08-25: jellyseerr HAS a module; janitorr,
scraparr and jellystat have neither module nor package and need hand-rolled
derivations pinned as flake inputs.
  virtualisation.oci-containers INSIDE an nspawn container is REJECTED — see
  the packaging section of docs/roadmap.md. State this in the file header.

HARDENING. `systemd-analyze security --offline=true` on every new unit,
before/after in the PR body, following M4's table. Watch for the Prowlarr trap
in reverse: an upstream unit with DynamicUser = true switched to a static uid
silently loses NoNewPrivileges, PrivateTmp, ProtectSystem=strict,
ProtectHome=read-only, RemoveIPC and RestrictSUIDSGID. Restate all six.

MANUAL STEPS for the PR body (lgo's):
  - Technitium record for jellyseerr.goclan.org -> 10.0.90.12 (Traefik).
    CREATE IT BEFORE ANYONE TYPES THE NAME, not merely before the deploy —
    M7 recorded that Cloudflare answers a nonexistent *.goclan.org name with
    NXDOMAIN and the SOA minimum is 1800, so an early lookup poisons the
    client's resolver for half an hour.
  - The dedicated Jellyfin USER for Janitorr's deletions.
  - Jellyseerr's own first-run wizard (Jellyfin server, libraries, users).
  - `clan machines update ernst` and `clan vars generate ernst`.

TEST PLAN in the PR body:
  - jellyseerr.goclan.org reachable from LAN AND from IoT (it is a household
    service; a mgmt-only test proves nothing about the actual users).
  - A real request flows through to Sonarr/Radarr.
  - JANITORR IN DRY RUN: paste what it WOULD have deleted. That listing is
    the deliverable, not a formality.
  - Scraparr's /metrics answers, and its targets appear `up` in Prometheus.
  - The Ollama target appears `up` and reports VRAM.
  - THE NEGATIVE CONTROL: jellyseerr.goclan.org is NOT reachable from outside
    the home network. It must not be, until M16.

Constraints:
- Never commit to main. Branch first, PR via `gh pr create` (title
  imperative, <=70 chars, no prefix; body = summary + test plan + manual
  steps).
- New flake inputs expected (the hand-rolled derivations). Pin by tag or rev,
  never by branch.
- Minimal diffs; commit only the files this change touches.
- Verify by evaluation:
    nix flake check
    nix eval --no-update-lock-file --raw \
      '.#nixosConfigurations.ernst.config.system.build.toplevel.drvPath'
- Claude does not deploy: `clan machines update ernst` and
  `clan vars generate ernst` are lgo's steps.
- Update docs/roadmap.md's status table in the same PR.
````

---

## M14 — `feat/ernst-libraries`

**Goal.** Extend the stack past film and television: music (Lidarr + slskd +
Soularr), comics (Kapowarr), games (Questarr), audiobooks (Audiobookshelf), and
synced ebook/audiobook artifacts (Storyteller).

**Depends on.** M12 — which is what proves the hand-rolled-derivation approach
this milestone leans on hardest. **Risk.** Medium-high, and **not** where it
looks: the risk is the **second write path into `/srv/media`**, not the number of
services.

### Music: Lidarr + slskd + Soularr

**Lidarr** — upstream module, confirmed present in ernst's pin 2026-08-25.

**SoulSync considered and REJECTED for now — record why**, because it looks like a
tidier answer and is not:

- ~400k LOC across a Python backend and a JS/TS frontend;
- a Vite/React bundle **Docker builds automatically and a Python install must
  build by hand**;
- **Deno** plus a **yt-dlp nightly** for YouTube on bare metal;
- and, decisively, **its own movie/TV/YouTube pipeline** with Prowlarr indexers
  and Radarr/Sonarr-class quality profiles — **a second opinionated system pointed
  at the same library.**

**Revisit later as a REPLACEMENT for the music half, never as an addition.** Two
systems with quality profiles over one library is the failure this repo has spent
M4 and M12 avoiding.

**slskd goes in the `wg-qbittorrent` MICROVM.** Soulseek is **P2P on the open
internet on ernst's behalf** — invariant #1 puts it one tier up, and the guest
already has the killswitch and the exit.

**COUNTER-ARGUMENT TO RECORD, and it is a real one.** Soulseek peer connectivity
through a shared commercial VPN exit can be poor — many peers are unreachable and
some clients de-prioritise VPN sources. And **the IVPN exit is Leaseweb NL**,
which M4 measured as **legally blocked by at least one indexer** (`451`). **MEASURE
BEFORE COMMITTING.** If it fails, **the fallback is the arr container with the
tradeoff written down** — a documented tier violation with a stated reason, **not
a silent move**.

**Soularr stays in the arr container** and reaches slskd's API **across VLAN 90**,
the way the *arrs reach qBittorrent: same bridge, layer 2, **no UDM-Pro rule** —
the same departure-2 argument M4 recorded, and for the same reason (both endpoints
are ports on `br0`, so the UDM-Pro never sees the traffic and a ZBF permit would
match nothing). **The guest's `api_clients` nftables set grows a second PORT, not
a second client.**

### The verification that makes this milestone worth doing — and it is NOT M4's

**M14 introduces a SECOND WRITE PATH into `/srv/media`: files from slskd rather
than from qBittorrent.**

M3 proved the hardlink chain **for qBittorrent specifically**, and what made it
work was **`UMask = 0002` ON THE SOURCE FILE** — `fs.protected_hardlinks` refuses
`link()` on a file you do not own unless you have read **and write** on it.
**slskd's umask is not qBittorrent's, and nothing has checked it.**

**RUN THE SYNTHETIC PROOF WITH THE NEGATIVE CONTROL, exactly as M3 did:**

1. Create a file as **slskd's uid**, in a `2770 root:media` directory.
2. Link it as **lidarr's uid**, in group `media`. Confirm **one inode** and
   **`links=2`**.
3. Then **`chmod` that file `0644`** and confirm the same link now fails with
   **`EPERM`**.

**Without step 3 the test cannot distinguish a working chain from root bypassing
the check** — which is the mistake an earlier revision of M3's own plan made (it
created the file as root and linked it as root, and would have passed whatever
`UMask` was set to). It is also the same failure class as
[M11's grader bug](#sn3-a-broken-instrument-is-indistinguishable-from-a-bad-result):
**a broken instrument is indistinguishable from a good result.**

**A link count of 1 on a real Lidarr import is a FAILED milestone**, not a
cosmetic issue. Treat it as M4 treated the same number.

### Comics, games, audiobooks

- **Kapowarr** — comics acquisition. **Komga and CWA already serve** the reading
  side; this is the acquisition half only. **Note Mylar3** as the older,
  more-mature alternative **considered and not chosen** — record the reason
  whichever way it goes.
- **Questarr** — games. Prowlarr app-sync, SQLite-backed.
- **Audiobookshelf** — upstream module, confirmed present 2026-08-25. **Its own
  storage tree, no hardlink-domain interaction** — so it is the one service here
  that does not owe the proof above. Multi-user with per-user progress, and good
  kids' handling, which is the reason it beats a Jellyfin audiobook library.

### Storyteller — confirmed in scope

**lgo has matched ebook + audiobook pairs**, which is the precondition: **without
both halves DRM-free for the same title it does nothing at all.** That fact is
what moves it from "interesting" to "in scope", and it should be stated first so
nobody adds it speculatively elsewhere.

It takes the pair and emits **a single EPUB3 with embedded audio and
sentence-level sync via forced alignment.**

**Complementary to Audiobookshelf, not overlapping**: ABS **serves the library**,
Storyteller **produces synced artifacts from pairs**. Both can be true at once and
the file header should say so.

**The binding step is CPU-heavy forced alignment.** Sixteen Zen 5 cores make that
a non-issue in absolute terms, but **it MUST be `nice`'d and `CPUWeight`-limited**
so it cannot compete with:

- a Jellyfin transcode,
- an HTPC session,
- **or — new since [M11](#m11-featfleet-local-coding-agent) — an interactive
  Ollama session.** That third claimant did not exist when this was first sketched
  and it is the one whose degradation is most visible: a coding agent that gets
  slower mid-session for no apparent reason.

**Alignment degrades on long musical intros and messy EPUB formatting**; claimed
accuracy is **90–95% on clean sources**. **Bind ONE known-good pair and check the
sync by hand before batching.**

**Justify the slot on language-learning and accessibility, not convenience** —
that is what it is actually for, and a convenience argument would not survive the
CPU cost.

**VERIFY the deploy story against the upstream GitLab repo, not blog posts** — the
write-ups are promotional and thin. **If no sane non-Docker path exists, that
argues for the PODMAN TIER [M9](#m9-featernst-tubesync) is opening, NOT for
`oci-containers` inside nspawn.**

### Readarr is archived upstream

**Do not add it.** It has a NixOS module in ernst's pin — **that is not evidence
it is maintained**, it is evidence nixpkgs has not removed it yet.

**VERIFY IN-SESSION what the current live successor is** — nixpkgs, awesome-arr,
the fork landscape — and **record findings WITH THE DATE**. **DO NOT write a fork
name from memory.** The first two to check are **LazyLibrarian** and **CWA's own
downloader**.

### Shape, ports and uids

uids reserved in `machines/ernst/networking.nix`: **3017 lidarr**, **3018
soularr**, **3019 kapowarr**, **3020 questarr**, **3021 audiobookshelf** (own
tree, not `/srv/media`), **3022 storyteller** — all `media` primary — and **3024
slskd**, which is **in the MICROVM GUEST, not the container**. **slskd's numeric
id must agree with the host wherever it writes to shared storage**, exactly as
qBittorrent's `3001` does; virtiofsd runs without id translation, so guest uid
3024 *is* host uid 3024.

Ports to verify against upstream defaults: **lidarr 8686**, **kapowarr 5656**,
**questarr 5000**, **audiobookshelf 13378**. Append to the one explicit list in
`arr.nix`; `extraInputRules` produces no rule and no warning.

````text
Read CLAUDE.md fully before doing anything.

Work in the clanarchy repo on miralda. Branch: feat/ernst-libraries.
Prerequisite: M12 merged and deployed. Read M14 in docs/roadmap.md first.

GOAL. Extend the stack past film and TV: music (Lidarr + slskd + Soularr),
comics (Kapowarr), games (Questarr), audiobooks (Audiobookshelf), and synced
ebook/audiobook artifacts (Storyteller).

════════════════════════════════════════════════════════════════════════════
THE VERIFICATION THAT MAKES THIS MILESTONE WORTH DOING — AND IT IS NOT M4's
════════════════════════════════════════════════════════════════════════════
M14 introduces a SECOND WRITE PATH into /srv/media: files from slskd rather
than qBittorrent. M3 proved the hardlink chain for QBITTORRENT SPECIFICALLY,
and what made it work was UMask = 0002 ON THE SOURCE FILE —
fs.protected_hardlinks refuses link() on a file you do not own unless you have
read AND write. slskd's umask is not qBittorrent's and NOTHING HAS CHECKED IT.

RUN THE SYNTHETIC PROOF WITH THE NEGATIVE CONTROL, exactly as M3 did:
  1. create a file as slskd's uid in a 2770 root:media directory
  2. link it as lidarr's uid in group media -> ONE INODE, links=2
  3. chmod that file 0644, link again -> MUST fail EPERM

WITHOUT STEP 3 THE TEST CANNOT DISTINGUISH A WORKING CHAIN FROM ROOT BYPASSING
THE CHECK — the mistake an earlier revision of M3's own plan made, and the same
failure class as M11's grader bug (roadmap standing note SN3): a broken
instrument is indistinguishable from a good result.

A LINK COUNT OF 1 ON A REAL LIDARR IMPORT IS A FAILED MILESTONE.

════════════════════════════════════════════════════════════════════════════
MUSIC
════════════════════════════════════════════════════════════════════════════
LIDARR — upstream module (confirmed in ernst's pin 2026-08-25).

SLSKD GOES IN THE wg-qbittorrent MICROVM. Soulseek is P2P on the open internet
on ernst's behalf — invariant #1 puts it one tier up, and the guest has the
killswitch and the exit.
  COUNTER-ARGUMENT TO RECORD: Soulseek peer connectivity through a shared
  commercial VPN exit can be poor, and the IVPN exit is Leaseweb NL, which M4
  measured as legally blocked by at least one indexer (451).
  MEASURE BEFORE COMMITTING. If it fails, the fallback is the arr container
  WITH THE TRADEOFF WRITTEN DOWN — a documented tier violation with a stated
  reason, not a silent move.

SOULARR stays in the arr container and reaches slskd's API across VLAN 90 the
way the *arrs reach qBittorrent: same bridge, L2, NO UDM-Pro rule — the same
departure-2 argument M4 recorded. The guest's api_clients nftables set grows a
second PORT, not a second client.

SOULSYNC — CONSIDERED AND REJECTED FOR NOW. Record why: ~400k LOC across a
Python backend and JS/TS frontend, a Vite/React bundle Docker builds
automatically and Python installs must build by hand, Deno plus a yt-dlp
nightly for YouTube on bare metal, and — decisively — its own movie/TV/YouTube
pipeline with Prowlarr indexers and Radarr/Sonarr-class quality profiles: a
second opinionated system pointed at the same library. Revisit later as a
REPLACEMENT for the music half, never an addition.

════════════════════════════════════════════════════════════════════════════
COMICS, GAMES, AUDIOBOOKS
════════════════════════════════════════════════════════════════════════════
KAPOWARR — comics acquisition; Komga and CWA already serve the reading side.
  Note Mylar3 as the older, more-mature alternative considered; record the
  reason whichever way you go.
QUESTARR — games. Prowlarr app-sync, SQLite-backed.
AUDIOBOOKSHELF — upstream module (confirmed 2026-08-25), OWN storage tree, no
  hardlink-domain interaction, so it does not owe the proof above. Multi-user
  with per-user progress; good kids' handling.

READARR IS ARCHIVED UPSTREAM. DO NOT ADD IT. It still has a NixOS module in
ernst's pin — that is not evidence it is maintained, only that nixpkgs has not
removed it. VERIFY IN-SESSION what the current live successor is (nixpkgs,
awesome-arr, the fork landscape) and RECORD FINDINGS WITH THE DATE. DO NOT
WRITE A FORK NAME FROM MEMORY. LazyLibrarian and CWA's own downloader are the
first two to check.

════════════════════════════════════════════════════════════════════════════
STORYTELLER — CONFIRMED IN SCOPE
════════════════════════════════════════════════════════════════════════════
lgo has matched ebook+audiobook pairs — that is the precondition, and without
both halves DRM-free for the same title it does nothing.

It takes the pair and emits a SINGLE EPUB3 with embedded audio and
SENTENCE-LEVEL sync via forced alignment.

COMPLEMENTARY to Audiobookshelf, not overlapping: ABS serves the library,
Storyteller produces synced artifacts from pairs. Say so in the file header.

THE BINDING STEP IS CPU-HEAVY FORCED ALIGNMENT. 16 Zen 5 cores make that a
non-issue in absolute terms, but it MUST be nice'd and CPUWeight-limited so it
cannot compete with a Jellyfin transcode, an HTPC session, OR — new since M11
— AN INTERACTIVE OLLAMA SESSION. That third claimant did not exist when this
was sketched and it is the one whose degradation is most visible.

Alignment degrades on long musical intros and messy EPUB formatting; claimed
accuracy 90-95% on clean sources. BIND ONE KNOWN-GOOD PAIR AND CHECK THE SYNC
BY HAND BEFORE BATCHING.

Justify the slot on language-learning and accessibility, not convenience.

VERIFY THE DEPLOY STORY AGAINST THE UPSTREAM GITLAB REPO, NOT BLOG POSTS — the
write-ups are promotional and thin. If no sane non-Docker path exists, that
argues for the PODMAN TIER M9 is opening, NOT for oci-containers inside nspawn.

════════════════════════════════════════════════════════════════════════════
PACKAGING, UIDS, PORTS
════════════════════════════════════════════════════════════════════════════
Establish IN-SESSION which have upstream modules and use THAT list. As of
2026-08-25: lidarr, slskd and audiobookshelf HAVE modules; soularr, kapowarr,
questarr and storyteller have neither module nor package.
  virtualisation.oci-containers INSIDE an nspawn container is REJECTED. State
  it in the file header.

UIDS, reserved in machines/ernst/networking.nix — do not invent new ones:
  3017 lidarr, 3018 soularr, 3019 kapowarr, 3020 questarr,
  3021 audiobookshelf (own tree, not /srv/media), 3022 storyteller
    — all media primary
  3024 slskd — MICROVM GUEST, not the container. Its numeric id must agree
    with the host wherever it writes to shared storage; virtiofsd runs without
    id translation, so guest uid 3024 IS host uid 3024, exactly like
    qBittorrent's 3001.

PORTS to VERIFY against upstream defaults: lidarr 8686, kapowarr 5656,
questarr 5000, audiobookshelf 13378. Append to the ONE explicit list in
arr.nix that the Traefik source-restriction concatMapStrings iterates. Do NOT
reach for extraInputRules — no rule, no warning.

HARDENING. `systemd-analyze security --offline=true` on every new unit,
before/after in the PR body, following M4's table. Prowlarr trap in reverse:
DynamicUser -> static uid silently drops NoNewPrivileges, PrivateTmp,
ProtectSystem=strict, ProtectHome=read-only, RemoveIPC, RestrictSUIDSGID.
Restate all six.

MANUAL STEPS for the PR body (lgo's):
  - Technitium records for the new names, created BEFORE anyone types them
    (M7's NXDOMAIN negative-cache finding).
  - slskd's Soulseek account credentials -> clan vars generator, prompted.
  - In-UI bootstrap for Lidarr / Kapowarr / Questarr / Audiobookshelf as a
    reproducible checklist, per M4's configuration policy.
  - `clan machines update ernst` and `clan vars generate ernst`.

TEST PLAN in the PR body:
  - THE HARDLINK PROOF WITH ITS NEGATIVE CONTROL, synthetic first, then a
    REAL Lidarr import with `stat` output. links=1 is a failed milestone.
  - slskd reachable from the arr container over VLAN 90 and from nowhere else.
  - Soulseek peer connectivity measured THROUGH THE VPN EXIT, with a real
    download completing — this is the go/no-go for the microvm placement.
  - ONE Storyteller binding checked by hand for sync drift before any batch.
  - `systemd-analyze security` table.

Constraints:
- Never commit to main. Branch first, PR via `gh pr create` (title
  imperative, <=70 chars, no prefix; body = summary + test plan + manual
  steps).
- New flake inputs expected. Pin by tag or rev, never by branch.
- Minimal diffs; commit only the files this change touches.
- Verify by evaluation:
    nix flake check
    nix eval --no-update-lock-file --raw \
      '.#nixosConfigurations.ernst.config.system.build.toplevel.drvPath'
- Claude does not deploy: `clan machines update ernst` and
  `clan vars generate ernst` are lgo's steps.
- Update docs/roadmap.md's status table in the same PR.
````

---

## M15 — `feat/ernst-tdarr`

**Goal.** Tdarr in its own nspawn container with VAAPI access to the RX 7900 XTX,
transcoding to AV1 — **plus a GPU arbitration scheme making it the preemptible
claimant on a card that now has three others.**

**Depends on.** M12. **Risk.** High, and **entirely in the arbitration**, not in
the transcoding.

**[M11](#m11-featfleet-local-coding-agent) changed this milestone materially.**
Read that section's VRAM table before designing anything here.

### Why its own container

`/dev/dri` passthrough into the **arr** container would hand the GPU to **Prowlarr
and Byparr too** — a strictly larger blast radius for no capability. That is
`arr.nix`'s own argument for giving Prowlarr no media access, applied to a
different resource.

And **the boundary that matters here is device access**, which nspawn's
`bindMounts` express directly. Follow M2b's pattern: veth on `br0`, VLAN 90,
MAC-pinned, DHCP reservation.

### The GPU problem, and why the obvious fix is wrong

**Invariant #5 arbitrates ONE mutual exclusion**: `display-manager.service` vs the
Bigscreen container, via a flag file and `ConditionPathExists` in
`modules/roles/htpc.nix`.

**COPYING THAT PATTERN IS THE OBVIOUS MOVE AND IT IS WRONG.** Say so explicitly in
the file header, because it is the first thing anyone will reach for.

The existing claimants **coexist deliberately**: compute goes through the **render
node**, KMS through the **card node**, so a session and ROCm coexist and merely
compete for **VRAM**. **Tdarr's VAAPI ALSO uses the render node.** There is **no
device-level exclusivity to enforce** — this is **RESOURCE PRIORITY**, and
`ConditionPathExists` is a **mutual-exclusion primitive**. Using it here would
either forbid a coexistence that is fine, or forbid nothing at all.

### M11 supplied the VRAM budget, and it is tighter than anyone assumed

**Cite these rather than re-measuring.** Card total **24560 MiB**; idle baseline
(the HTPC session) 877–1093 MiB.

| Configuration | VRAM | Placement | tok/s |
|---|---|---|---|
| 64k, no KV quantisation (f16) | **24471 MiB** | **SPILLING** — 4% CPU / 96% GPU | 98.5 |
| 64k, flash attention **alone** | 24471 MiB | **a measured NO-OP** — identical to baseline | 97.5 |
| 64k, **q8_0 KV cache** | **22482 MiB** | **100% GPU resident** | 112.6 |

**A fully-resident Ollama at 64k leaves 2078 MiB — roughly 2 GB — of headroom on
the card.**

**THERE IS ESSENTIALLY NO VRAM FOR TDARR WHILE OLLAMA IS LOADED.** That is not an
arbitration nicety to be tuned later. **It is the central constraint of the
milestone, and any design that assumes coexistence is wrong before it starts.**

*(Note the figure against an earlier draft of this section, which said "~1.5 GB".
The measured number is 24560 − 22482 = **2078 MiB**. It does not change the
conclusion, and it is recorded correctly here because this file's own repeated
lesson is that a number nobody re-derived is a number nobody can trust.)*

**CORRECT ONE INHERITED EXAGGERATION.** Earlier planning warned that spilling to
system RAM would make Ollama *"unusably slow, maybe 5 tok/s"*. **Measured: the
128k spill still ran 75 tok/s**, and the 64k f16 spill ran 98.5. Spilling is a
real cost and a real reason to keep `q8_0` — **but it is not catastrophic, and the
arbitration must not be designed as though eviction were fatal.** A design that
treats a spill as an outage will over-restrict Tdarr into never running at all.

### The trigger problem, sharpened by M11

**Ollama is request-driven and IDLES**, so *"Ollama is active"* is **not a systemd
state**. And the idle gaps are **exactly when a Tdarr worker would claim VRAM** —
and it will **still be holding it when the next prompt arrives**.

**Since M11, that failure presents to lgo as the coding agent degrading
mid-session for no visible reason** — which is both the worst diagnostic
experience available and the hardest thing to attribute to a transcoder.

**Design accordingly, and argue the primitive rather than picking one:**

- **Tdarr workers STOPPED, not deprioritised**, when the HTPC session **or**
  Ollama is active. Deprioritising a worker does not return its VRAM; only
  stopping it does, and VRAM is the contended resource here rather than compute.
- **Resumption from checkpointed jobs.** Tdarr claims support for this. **VERIFY
  rather than trust, and record how a killed job actually recovers** — a
  preemptible service whose preemption corrupts its work unit is not preemptible.
- **Establish what signal exists BEFORE designing against it.** Candidates: the
  model loader's unit state, VRAM-occupancy polling, an API-side hook, or a
  keepalive window after the last request. **The HTPC session IS a systemd state
  and is the easy half** — do that one first and do not let it disguise how hard
  the Ollama half is.
- [M13](#m13-featernst-media-lifecycle) adds an **Ollama scrape target**
  specifically so this milestone starts with VRAM-occupancy history rather than
  guessing at the shape of the idle gaps.

**DO NOT VFIO-BIND ANYTHING.** Invariant #5 rejects passthrough and explains why
Bigscreen-in-a-VM was not taken. Nothing here reopens that.

### The encoding decision is a measurement, not an inherited opinion

**VCN AV1 on RDNA3 is fast but trails SVT-AV1 on quality-per-bit.** Tdarr's
worker/node split allows **both**: GPU workers for backlog, CPU workers on 16 Zen 5
cores for archival masters.

**Encode one known file both ways at comparable target sizes; VMAF or SSIMULACRA2
in the PR body.** Not an opinion, a number.

**GIVEN THE VRAM FINDING, CPU-ONLY TDARR IS NOW A SERIOUS DEFAULT rather than a
fallback.** It **sidesteps the arbitration problem entirely** — no render-node
contention, no VRAM budget, no idle-gap detection, no preemption design — and the
9950X is not a weak encoder. **Argue it explicitly instead of assuming GPU
workers.** If CPU-only wins, most of the hard half of this milestone evaporates,
and that is a good outcome rather than a diminished one.

### Evaluate Muxarr FIRST, and be willing to stop there

**Stripping redundant audio and subtitle tracks WITHOUT re-encoding may reclaim
more space per CPU-hour in a two-language household than transcoding does** — at
**zero quality risk** and with **no GPU arbitration at all**.

**MEASURE what a Muxarr pass would reclaim BEFORE building the container.** If
that is most of the win: **ship Muxarr and record Tdarr as unnecessary. That is a
successful milestone**, not an abandoned one.

**OVERLAP WITH [M8](#m8-featernst-tvheadend)**: the M8 amendment also names Muxarr,
for normalising MPEG-TS recordings. **Whichever lands first owns the evaluation.**
Cross-referenced from both.

### What NOT to transcode

The Radarr profile **deliberately** grabs **Remux-2160p with TrueHD Atmos and
dual-layer Dolby Vision**. `arr.nix`'s recyclarr block explains what "remux"
means: **streams lifted UNTOUCHED off the UHD Blu-ray, 40–80 GB per film.**

**Treat the remux tier as an ARCHIVAL MASTER. Never re-encode it in place.** A
smaller viewing copy is a **SECOND file**, and **the milestone must decide how
Jellyfin picks between them** — that decision is part of the deliverable, not a
follow-up, because a library with two versions of every film and no selection
rule is worse than one with one.

**Audio: pass TrueHD / Atmos through untouched.** Lossy Atmos is a **different
product**, not a smaller version of the same one.

### Storage and monitoring

**Output lands in the `/srv/media` hardlink domain, so invariant #2 applies: NO
NEW DATASETS.** Plain subdirectories only. Own state at `/srv/state/tdarr` per
invariant #7.

**Add `tdarr-exporter` to M6's targets IN THIS MILESTONE.** Queue depth and
in-flight progress are what tell you whether the arbitration is **starving** it —
and **a preemptible service that never runs looks identical to one that works.**
That is the same epistemics as
[SN3](#sn3-a-broken-instrument-is-indistinguishable-from-a-bad-result), and it is
why the exporter is not deferred to M13.

### Packaging, uid and address

**Measured 2026-08-25, and it contradicts an earlier draft of this milestone:**
`services.tdarr` **is an upstream NixOS module** in ernst's pin, and
`pkgs.tdarr` **is packaged at 2.74.01**. **No hand-rolled derivation is needed for
Tdarr itself** — verify that still holds at session time, but do not start by
writing one. **Muxarr** has neither module nor package.

uid **3023 tdarr**, `media` primary, **plus the `render` group for `/dev/dri`**.
MAC: the next free entry after `02:00:00:90:00:07` (authelia) — see the
reservation block in `machines/ernst/networking.nix`. **The address must be inside
the DHCP pool `10.0.90.6–.254`**; UniFi accepts a `.2`–`.5` address and then
silently hands out an ordinary lease, which cost M2b, M5 and M6 a round each.

**Ledger**: Tdarr gets a Traefik router behind the **`authelia`** middleware — not
`mgmt-only`, which M7 deleted. Copy the *arr routers, and remember
`containers/authelia.nix`'s `access_control` is deny-by-default, so a route with
the middleware and no matching rule fails **closed**.

````text
Read CLAUDE.md fully before doing anything.

Work in the clanarchy repo on miralda. Branch: feat/ernst-tdarr.
Prerequisite: M12 merged and deployed. Read M15 in docs/roadmap.md first, and
read M11's VRAM table before designing anything — it is the constraint.

GOAL. Tdarr in its own nspawn container with VAAPI access to the RX 7900 XTX,
transcoding to AV1, plus a GPU arbitration scheme making it the PREEMPTIBLE
claimant on a card that now has three others.

════════════════════════════════════════════════════════════════════════════
EVALUATE MUXARR FIRST, AND BE WILLING TO STOP THERE
════════════════════════════════════════════════════════════════════════════
Stripping redundant audio and subtitle tracks WITHOUT re-encoding may reclaim
more space per CPU-hour in a two-language household than transcoding does —
zero quality risk, no GPU arbitration at all.
MEASURE WHAT A MUXARR PASS WOULD RECLAIM BEFORE BUILDING THE CONTAINER. If
that is most of the win, SHIP MUXARR AND RECORD TDARR AS UNNECESSARY. That is
a SUCCESSFUL milestone.
OVERLAP WITH M8: the M8 amendment also names Muxarr for MPEG-TS recordings.
Whichever lands first owns the evaluation — check whether M8 already did it.

════════════════════════════════════════════════════════════════════════════
WHY ITS OWN CONTAINER
════════════════════════════════════════════════════════════════════════════
/dev/dri passthrough into the arr container would hand the GPU to Prowlarr and
Byparr too — a strictly larger blast radius for no capability, which is
arr.nix's own argument for giving Prowlarr no media access. And the boundary
that matters is DEVICE ACCESS, which nspawn's bindMounts express.
Follow M2b's pattern: veth on br0, VLAN 90, MAC-pinned, DHCP reservation
INSIDE the pool (10.0.90.6-.254) — UniFi accepts a .2-.5 address and then
silently hands out an ordinary lease. M2b, M5 and M6 each lost a round to it.
Next free MAC is after 02:00:00:90:00:07 (authelia) — see the reservation
block in machines/ernst/networking.nix.

════════════════════════════════════════════════════════════════════════════
THE GPU PROBLEM, AND WHY THE OBVIOUS FIX IS WRONG
════════════════════════════════════════════════════════════════════════════
Invariant #5 arbitrates ONE mutual exclusion: display-manager vs the Bigscreen
container, via a flag file and ConditionPathExists in modules/roles/htpc.nix.
COPYING THAT PATTERN IS THE OBVIOUS MOVE AND IT IS WRONG. SAY SO EXPLICITLY IN
THE FILE HEADER.
The existing claimants COEXIST DELIBERATELY: compute through the render node,
KMS through the card node, so a session and ROCm coexist and merely compete for
VRAM. TDARR'S VAAPI ALSO USES THE RENDER NODE. There is no device-level
exclusivity to enforce — this is RESOURCE PRIORITY, and ConditionPathExists is
a MUTUAL-EXCLUSION primitive.

M11 SUPPLIED THE VRAM BUDGET. CITE IT, DO NOT RE-MEASURE.
Card total 24560 MiB. Idle (HTPC session) 877-1093 MiB.
  - 64k, no KV quantisation:      24471 MiB — SPILLING (4% CPU / 96% GPU)
  - 64k, flash attention ALONE:   24471 MiB — a measured NO-OP, 97.5 tok/s
  - 64k, q8_0 KV cache:           22482 MiB — 100% GPU resident, 112.6 tok/s
A FULLY-RESIDENT OLLAMA AT 64k LEAVES 2078 MiB — ROUGHLY 2 GB. THERE IS
ESSENTIALLY NO VRAM FOR TDARR WHILE OLLAMA IS LOADED. That is not an
arbitration nicety, it is the CENTRAL CONSTRAINT, and any design that assumes
coexistence is wrong before it starts.

CORRECT ONE INHERITED EXAGGERATION. Earlier planning warned that spilling to
system RAM would make Ollama "unusably slow, maybe 5 tok/s". MEASURED: the
128k spill still ran 75 tok/s. Spilling is a real cost and a real reason to
keep q8_0, but it is NOT catastrophic, and the arbitration must not be designed
as though eviction were fatal — a design that treats a spill as an outage will
over-restrict Tdarr into never running at all.

THE TRIGGER PROBLEM, SHARPENED BY M11. Ollama is request-driven and IDLES, so
"Ollama is active" is NOT a systemd state. The idle gaps are exactly when a
Tdarr worker would claim VRAM — and it will still be holding it when the next
prompt arrives. Since M11 that failure presents to lgo as THE CODING AGENT
DEGRADING MID-SESSION FOR NO VISIBLE REASON.
DESIGN ACCORDINGLY, AND ARGUE THE PRIMITIVE:
  - Tdarr workers STOPPED, not deprioritised, when the HTPC session or Ollama
    is active. Deprioritising does not return VRAM; only stopping does.
  - Resumption from checkpointed jobs. Tdarr claims support — VERIFY rather
    than trust, and record how a killed job ACTUALLY recovers. A preemptible
    service whose preemption corrupts its work unit is not preemptible.
  - ESTABLISH WHAT SIGNAL EXISTS BEFORE DESIGNING AGAINST IT: the loader's
    unit state, VRAM-occupancy polling, an API-side hook, or a keepalive
    window after the last request. The HTPC session IS a systemd state and is
    the easy half — do it first, and do not let it disguise how hard the
    Ollama half is.
  - M13 added an Ollama scrape target so you start with VRAM-occupancy
    HISTORY rather than guessing at the shape of the idle gaps. Use it.

DO NOT VFIO-BIND ANYTHING. Invariant #5 rejects passthrough and explains why
Bigscreen-in-a-VM was not taken.

════════════════════════════════════════════════════════════════════════════
ENCODING — A MEASUREMENT, NOT AN INHERITED OPINION
════════════════════════════════════════════════════════════════════════════
VCN AV1 on RDNA3 is fast but trails SVT-AV1 on quality-per-bit. Tdarr's
worker/node split allows both: GPU workers for backlog, CPU workers on 16 Zen 5
cores for archival masters. ENCODE ONE KNOWN FILE BOTH WAYS at comparable
target sizes; VMAF or SSIMULACRA2 in the PR body.

GIVEN THE VRAM FINDING, CPU-ONLY TDARR IS NOW A SERIOUS DEFAULT rather than a
fallback: it sidesteps the arbitration problem ENTIRELY, and the 9950X is not
a weak encoder. ARGUE IT EXPLICITLY instead of assuming GPU workers.

WHAT NOT TO TRANSCODE. The Radarr profile deliberately grabs Remux-2160p with
TrueHD Atmos and dual-layer Dolby Vision — arr.nix's recyclarr block explains
that "remux" means streams lifted UNTOUCHED off the UHD Blu-ray, 40-80 GB per
film. TREAT THE REMUX TIER AS AN ARCHIVAL MASTER; NEVER RE-ENCODE IN PLACE. A
smaller viewing copy is a SECOND FILE, and THIS MILESTONE MUST DECIDE HOW
JELLYFIN PICKS BETWEEN THEM — that decision is part of the deliverable.
Audio: pass TrueHD/Atmos through UNTOUCHED. Lossy Atmos is a different
product, not a smaller version of the same one.

════════════════════════════════════════════════════════════════════════════
STORAGE, MONITORING, PACKAGING
════════════════════════════════════════════════════════════════════════════
STORAGE. Output lands in the /srv/media hardlink domain, so invariant #2
applies: NO NEW DATASETS, plain subdirectories only. Own state at
/srv/state/tdarr per invariant #7.

MONITORING. Add tdarr-exporter to M6's targets IN THIS MILESTONE. Queue depth
and in-flight progress are what tell you whether arbitration is STARVING it —
a preemptible service that never runs looks identical to one that works
(roadmap standing note SN3).

PACKAGING. VERIFIED 2026-08-25 and it contradicts earlier drafts: services.tdarr
IS an upstream NixOS module in ernst's pin, and pkgs.tdarr is packaged at
2.74.01. NO HAND-ROLLED DERIVATION IS NEEDED FOR TDARR ITSELF — re-verify at
session time, but do not start by writing one. Muxarr has neither module nor
package.
  virtualisation.oci-containers INSIDE an nspawn container is REJECTED. State
  it in the file header.

UID 3023 tdarr, media primary, PLUS the render group for /dev/dri. Reserved in
machines/ernst/networking.nix.

LEDGER. Tdarr gets a Traefik router behind the `authelia` middleware — NOT
mgmt-only, which M7 deleted. Copy the *arr routers. containers/authelia.nix's
access_control is DENY-BY-DEFAULT, so a route with the middleware and no
matching rule fails CLOSED — add the hostname there too.

HARDENING. `systemd-analyze security --offline=true`, before/after in the PR
body, following M4's table.

MANUAL STEPS for the PR body (lgo's):
  - DHCP reservation on VLAN 90, INSIDE the pool.
  - Technitium record for tdarr.goclan.org -> 10.0.90.12, created BEFORE
    anyone types the name (M7's NXDOMAIN negative-cache finding).
  - Tdarr's in-UI library, flow and worker configuration as a reproducible
    checklist, per M4's configuration policy.
  - `clan machines update ernst`.

TEST PLAN in the PR body:
  - The Muxarr reclamation measurement, FIRST, with the decision it produced.
  - bridge vlan show dev vb-tdarr -> 90 PVID Egress Untagged.
  - vainfo inside the container names Navi 31, NOT the iGPU.
  - The encode comparison with VMAF or SSIMULACRA2 numbers.
  - THE ARBITRATION, exercised deliberately: start a transcode, then start an
    Ollama session, and show the worker STOPPED and the job RESUMED. A design
    that is never tested under contention is not tested.
  - tdarr-exporter targets `up` in Prometheus with queue depth reporting.

Constraints:
- Never commit to main. Branch first, PR via `gh pr create` (title
  imperative, <=70 chars, no prefix; body = summary + test plan + manual
  steps).
- A new flake input is expected only if Muxarr is taken; Tdarr needs none.
- Minimal diffs; commit only the files this change touches.
- Verify by evaluation:
    nix flake check
    nix eval --no-update-lock-file --raw \
      '.#nixosConfigurations.ernst.config.system.build.toplevel.drvPath'
- Claude does not deploy: `clan machines update ernst` is lgo's step.
- Update docs/roadmap.md's status table in the same PR.
````

---

## M16 — `feat/ernst-external-ingress`

**The milestone.** Make `jellyseerr.goclan.org` reachable **from the internet**,
and **ONLY** that.

**Depends on.** M13. **M7 IS DONE** — the auth half is configuration, not
speculation. **Risk.** High, and it is a **different kind** of risk from every
milestone before it.

### Why it is its own milestone

**Every prior threat model in this repo has been "hosts on VLANs the UDM-Pro
controls."** M5 reasoned about consumer zones. M2b reasoned about IoT. M4 reasoned
about a bridge the UDM-Pro never sees. Even M7's stated cost — *"the login portal
becomes visible from the IoT VLAN"* — is a statement about a VLAN.

**M16 deletes that assumption.** It is a **deliberate bypass under invariant #4**,
**must be listed** in the ledger, and it **re-opens invariant #1's tier question**
for whatever terminates the external connection. A milestone that changes the
shape of the threat model does not belong inside one that cleans up a library.

### What does not exist yet

**There is NO WAN ingress path on ernst.** Traefik's wildcard certificate comes
from **ACME DNS-01 at Cloudflare**, which proves domain control with **no inbound
path whatsoever**. **Do not mistake a working certificate for a working ingress** —
`containers/traefik.nix` says "split horizon, no public A records" in its own
header, and that is still true.

**Measured precondition, supplied by lgo: a STATIC FULL IP STACK — static public
IPv4 and native IPv6, no CGNAT, no DS-Lite.** **Confirm the addresses in-session**
rather than inheriting this line.

**THIS KILLS BOTH PRACTICAL OBJECTIONS TO A PORT FORWARD** — no DDNS, no rotating
address. **So option (A) is now genuinely SIMPLER than (B), and (B) must win on
its security argument alone or lose.** That is the honest framing and it should
not be softened.

### (A) UDM-Pro port forward, WAN `:443` → `10.0.90.12:443`

No new daemon, no third party in the TLS path, one rule created once.

**THE OBJECTION THAT SHOULD DECIDE IT:** it makes **EVERY Traefik router
internet-reachable**, gated on nothing but **middleware correctness**. After M7
that means the `authelia` forward-auth middleware becomes the only thing keeping
`sonarr.goclan.org` private — **and a middleware one edit from wrong FAILS OPEN.**

Compare two decisions this repo has already made the other way:

- **M2b's `DefaultPVID = "none"`**, chosen precisely because a missed VLAN
  application then **fails closed** — no connectivity — rather than fail-open onto
  VLAN 50.
- **[L4's reasoning](#interim-rule-ledger)**: a permit rule doing nothing is what
  someone later "fixes" by removing the restriction.

**NOT a reason to reject it: "exposing a static IP."** The address is already
public and M3 recorded it (`78.94.91.74`). That objection sounds like security and
is not one.

### (B) Cloudflare Tunnel (`cloudflared`), outbound-only

**THE DECIDING PROPERTY: the tunnel DECLARES which hostnames it serves.**
`jellyfin`, `sonarr`, `radarr`, `prowlarr`, `grafana` and `auth` **do not resolve
or route from outside at all** — not "are refused", **are not there**.

**Adding a service to the internet becomes an EXPLICIT ACT** rather than the
default consequence of creating a Traefik route. That is
**fail-closed-by-construction**, which is the property this repo has chosen at
every previous fork — `DefaultPVID = "none"`, Authelia's `default_policy: deny`
with explicit hostnames, `mkOverride` rather than a silent merge.

The **Cloudflare account and a scoped API token already exist** for ACME DNS-01,
so the third-party relationship is not new. The *dependency* is.

**HONEST COSTS, all of which belong in the PR body:**

- **Cloudflare terminates TLS and can see plaintext.** That is a real disclosure
  for a request UI carrying **Jellyfin credentials**. Say it plainly.
- **A third party in the availability path.** Cloudflare down means Jellyseerr
  externally down — internally unaffected, which is the mitigation.
- **Cloudflare's terms have historically restricted proxying large media
  streams.** Jellyseerr is low-bandwidth so **it does not bite** — **but it is a
  hard reason the tunnel must NEVER grow a `jellyfin.goclan.org` hostname**, and
  that must be **written down BEFORE someone later "just adds one more"**. It is
  the single most predictable future edit to this configuration.

**TIER QUESTION — argue it, do not default.** `cloudflared` holds a **persistent
outbound connection to a third party** and is **what an attacker reaches first**.
Invariant #1 tiers by trust and workload, and "talks to the internet on its own
behalf" is the *exact* phrase that moved qBittorrent to the microvm. Place it
deliberately.

### IPv6 — this is a trigger

**See [SN2](#sn2-ipv6-is-off-and-that-is-now-a-decision).** **(B) sidesteps v6
entirely** — the tunnel is outbound and the address family of the ingress stops
being the household's problem.

**(A) does not, and forces the decision.** If **(A) wins**: audit the UDM-Pro's
**IPv6** ruleset, prove **default-deny inbound**, or explicitly commit VLAN 90 to
v4-only — **and update SN2 from "owed" to "decided"** in the same PR. A milestone
that opens a v4 hole and leaves the v6 question open has done half a boundary.

### Recommendation, argued rather than inherited

**(B).** The failure mode bought off is **"six admin UIs silently exposed by one
bad middleware edit"** — and **designing that class of failure out, rather than
being careful about it, is what this repo has done at every previous fork.**

The counter-argument is real and should be weighed rather than dismissed: (B) adds
a daemon, a dependency, and a party that can read the plaintext. If the session
concludes (A) on the strength of that, **it must then carry the v6 audit and an
explicit answer to "what stops the next Traefik route from being public".**

### Auth — M7 is done, so this is configuration

**Read what Authelia actually protects today** ([M7's close-out](#close-out-2026-08-25)
enumerates it) and build on it.

**The unauthenticated attack surface must be AUTHELIA, not Jellyseerr's Node
application.** Forward-auth with **2FA required** on the external path.

**Jellyseerr's own Jellyfin-account login stays underneath** — for the reason M6
kept Grafana's admin account under the middleware, and M7 then had to build a path
back to it: **it is the credential that still works when the identity provider is
the broken thing.**

**INVARIANT #4's JELLYFIN EXEMPTION DOES NOT TRANSFER, and the roadmap says so
because the two rows sit next to each other in the ledger.** The exemption exists
because **TV and mobile clients cannot survive forward-auth**. **Jellyseerr's only
client is a browser.** Do not read the exemption as licence to skip forward-auth
here.

Note also that M13 deliberately ships Jellyseerr **without** the middleware at
internal scope, so **M16 is where that router's posture changes** — one change to
one router, made once, reviewed as an external change.

### Wizarr — in scope here, and record why it moved

**Previously rejected as overkill**: three people, accounts created by hand once.

**M16 changes the arithmetic.** Every household member now needs an **Authelia
account in addition to their Jellyfin one**, and [M14](#m14-featernst-libraries)
adds **Audiobookshelf** to a set already including **Komga**. **Wizarr's value is
the multi-service invite, which is exactly the problem M16 creates.**

**DECIDE AND ARGUE the identity relationship** rather than letting it emerge: does
Wizarr provision the **Authelia** account too, or only downstream services? **Which
is the source of truth for "who is allowed in"?** A defensible answer is
**Authelia owns identity, Wizarr owns service enrolment** — but **STATE it**,
because an invite system that half-owns identity is how two account stores drift.

**WIZARR STAYS INTERNAL.** An invite endpoint reachable from outside is a
**self-service account creation endpoint**. Internal route, **no** mgmt-only
middleware (it does not exist any more), invites delivered **out of band**.

**If the session concludes it still is not worth it, record that and drop it.**
Three people is still three people.

uid **3025 wizarr**, own group, **conditional** — reserved so that taking it does
not require a table edit, and left unclaimed if it is dropped.

### Ledger

**A PERMANENT bypass row under invariant #4**: `WAN → jellyseerr.goclan.org`,
**mechanism and auth posture in the same row**, written as a **`—` row** like the
qBittorrent WebUI one **so a future milestone does not mistake it for something to
retire.** The row is [already drafted](#interim-rule-ledger) with "not created"
status; M16 fills it in.

**`cloudflared`'s uid depends on the tier decision — do not reserve one yet.**

### Test plan must include negative controls

**From a connection genuinely outside the home network — a phone on mobile data,
not a laptop on the LAN.** This is the distinction that makes the test mean
anything, and it is the one most likely to be fudged.

- `jellyseerr.goclan.org` **reaches Authelia**, and Jellyseerr **only after auth**.
- `jellyfin`, `sonarr`, `radarr`, `prowlarr`, `grafana`, `auth` and (if it exists)
  `tubesync` `.goclan.org` **ALL UNREACHABLE**. **Record the failure mode for
  each**, because the two options fail differently and the difference is itself
  the measurement:
  - under **(B)** they should **fail to resolve or route**;
  - under **(A)** they **resolve and are refused by forward-auth** — **a WEAKER
    result**, and the evidence that justifies (B).
- **Repeat the whole negative set over IPv6** if the client has it. **A v4-only
  test proves half the boundary**, and SN2 exists because nobody has ever tested
  the other half.
- If **(B)** won, **the UDM-Pro's WAN view shows no new inbound permit.** That is
  the check that proves the tunnel did what it claimed.

**A PASS ON THE POSITIVE TEST WITH NO NEGATIVE CONTROLS IS A FAILED MILESTONE.**

````text
Read CLAUDE.md fully before doing anything.

Work in the clanarchy repo on miralda. Branch: feat/ernst-external-ingress.
Prerequisite: M13 merged and deployed (Jellyseerr live at INTERNAL scope).
Read M16 in docs/roadmap.md first, and read standing note SN2 (IPv6).

M7 IS DONE. Read machines/ernst/containers/{traefik,authelia}.nix for what is
ACTUALLY behind forward-auth today. This milestone is configuration, not
speculation about an identity provider that might exist.

THE MILESTONE. Make jellyseerr.goclan.org reachable FROM THE INTERNET, and
ONLY that. It is the first service in this fleet accepting connections from
outside the home network, so THE MILESTONE IS ABOUT THE BOUNDARY, not about
Jellyseerr.

WHAT DOES NOT EXIST YET: there is NO WAN ingress path on ernst. Traefik's
wildcard cert comes from ACME DNS-01 at Cloudflare, which proves domain
control with NO inbound path. DO NOT MISTAKE A WORKING CERTIFICATE FOR A
WORKING INGRESS.

MEASURED PRECONDITION, supplied by lgo: STATIC FULL IP STACK — static public
IPv4 AND native IPv6, no CGNAT, no DS-Lite. CONFIRM THE ADDRESSES IN-SESSION.
This kills both practical objections to a port forward (no DDNS, no rotating
address), so option (A) is now genuinely SIMPLER than (B), and (B) MUST WIN ON
ITS SECURITY ARGUMENT ALONE OR LOSE.

════════════════════════════════════════════════════════════════════════════
(A) UDM-Pro port forward, WAN :443 -> 10.0.90.12:443
════════════════════════════════════════════════════════════════════════════
No new daemon, no third party in the TLS path, one rule created once.
THE OBJECTION THAT SHOULD DECIDE IT: it makes EVERY Traefik router
internet-reachable, gated on nothing but middleware correctness. The authelia
forward-auth middleware becomes the only thing keeping sonarr.goclan.org
private, AND A MIDDLEWARE ONE EDIT FROM WRONG FAILS OPEN.
  Compare M2b's DefaultPVID = "none", chosen because a miss there fails CLOSED.
  Compare L4's reasoning: a permit rule doing nothing is what someone later
  "fixes" by removing the restriction.
NOT A REASON TO REJECT IT: "exposing a static IP". The address is already
public and M3 recorded it.

════════════════════════════════════════════════════════════════════════════
(B) Cloudflare Tunnel (cloudflared), outbound-only
════════════════════════════════════════════════════════════════════════════
THE DECIDING PROPERTY: the tunnel DECLARES which hostnames it serves. jellyfin,
sonarr, radarr, prowlarr, grafana and auth do not resolve or route from outside
AT ALL — not "are refused", ARE NOT THERE. Adding a service to the internet
becomes an EXPLICIT ACT rather than the default consequence of creating a
Traefik route — the same fail-closed-by-construction property this repo has
chosen at every previous fork.
The Cloudflare account and scoped API token already exist for ACME DNS-01.

HONEST COSTS, ALL IN THE PR BODY:
  - Cloudflare terminates TLS and CAN SEE PLAINTEXT — a real disclosure for a
    request UI carrying Jellyfin credentials. Say it plainly.
  - A third party in the availability path.
  - Cloudflare's terms have historically restricted proxying large media
    streams. Jellyseerr is low-bandwidth so it does not bite — BUT IT IS A
    HARD REASON THE TUNNEL MUST NEVER GROW A jellyfin.goclan.org HOSTNAME,
    written down BEFORE someone later "just adds one more".

TIER QUESTION: cloudflared holds a persistent outbound connection to a third
party and is what an attacker reaches first. ARGUE ITS PLACEMENT AGAINST
INVARIANT #1. DO NOT DEFAULT. "Talks to the internet on its own behalf" is the
exact phrase that put qBittorrent in a microvm.

RECOMMENDATION, ARGUED NOT INHERITED: (B). The failure mode bought off is "six
admin UIs silently exposed by one bad middleware edit", and designing that
class of failure out rather than being careful about it is what this repo has
done at every previous fork. If you conclude (A) instead, you must ALSO carry
the v6 audit below and an explicit answer to "what stops the next Traefik
route from being public".

════════════════════════════════════════════════════════════════════════════
IPv6 — THIS IS A TRIGGER FOR STANDING NOTE SN2
════════════════════════════════════════════════════════════════════════════
(B) sidesteps v6 entirely. (A) DOES NOT, and forces the decision.
IF (A) WINS: audit the UDM-Pro's IPv6 ruleset, PROVE DEFAULT-DENY INBOUND, or
explicitly commit VLAN 90 to v4-only — and UPDATE SN2 FROM "owed" TO "decided"
in the same PR. A milestone that opens a v4 hole and leaves the v6 question
open has done half a boundary.
SN2's baseline measurement (2026-08-25) is link-local only on every container
and no GUA anywhere on VLAN 90. RE-RUN IT. A GUA there is an incident.

════════════════════════════════════════════════════════════════════════════
AUTH — M7 IS DONE, SO THIS IS CONFIGURATION
════════════════════════════════════════════════════════════════════════════
THE UNAUTHENTICATED ATTACK SURFACE MUST BE AUTHELIA, NOT JELLYSEERR'S NODE
APPLICATION. Forward-auth with 2FA required on the external path.
Jellyseerr's own Jellyfin-account login stays UNDERNEATH, for the reason M6
kept Grafana's admin account under the middleware: it is the credential that
still works when the identity provider is the broken thing.
M13 deliberately shipped Jellyseerr WITHOUT the middleware at internal scope,
so THIS is where that router's posture changes — one change, one router, made
once and reviewed as an external change.

INVARIANT #4 SAYS Jellyfin's native auth stays forever because TV and mobile
clients cannot survive forward-auth. THAT EXEMPTION IS ABOUT JELLYFIN. It is
NOT licence to skip forward-auth on Jellyseerr, whose only client is a browser.
SAY SO IN THE FILE HEADER — the two rows sit next to each other in the ledger
and the exemption will look transferable.

Adding the hostname to the middleware also means adding it to `access_control`
in containers/authelia.nix, which is DENY-BY-DEFAULT: a route with the
middleware and no matching rule fails CLOSED.

════════════════════════════════════════════════════════════════════════════
WIZARR — IN SCOPE HERE, AND RECORD WHY IT MOVED
════════════════════════════════════════════════════════════════════════════
Previously rejected as overkill: three people, accounts created by hand once.
M16 CHANGES THE ARITHMETIC — every household member now needs an AUTHELIA
account in addition to their Jellyfin one, and M14 adds Audiobookshelf to a set
already including Komga. Wizarr's value is the MULTI-SERVICE INVITE, which is
exactly the problem M16 creates.

DECIDE AND ARGUE THE IDENTITY RELATIONSHIP: does Wizarr provision the Authelia
account too, or only downstream services? WHICH IS THE SOURCE OF TRUTH for
"who is allowed in"? A defensible answer is Authelia owns identity, Wizarr owns
service enrolment — but STATE it.

WIZARR STAYS INTERNAL. An invite endpoint reachable from outside is a
self-service account creation endpoint. Internal route, no mgmt-only middleware
(it no longer exists), invites out of band.
If you conclude it still is not worth it, RECORD THAT AND DROP IT.
uid 3025, own group, CONDITIONAL — reserved in machines/ernst/networking.nix.

════════════════════════════════════════════════════════════════════════════
LEDGER
════════════════════════════════════════════════════════════════════════════
A PERMANENT bypass row under invariant #4: WAN -> jellyseerr.goclan.org,
MECHANISM AND AUTH POSTURE IN THE SAME ROW, written as a "—" row like the
qBittorrent WebUI one so a future milestone does not mistake it for something
to retire. The row is already drafted in docs/roadmap.md with "not created"
status — fill it in, do not create a second one.
cloudflared's uid depends on the tier decision; do not reserve one until it is
made.

════════════════════════════════════════════════════════════════════════════
TEST PLAN — THE NEGATIVE CONTROLS ARE THE MILESTONE
════════════════════════════════════════════════════════════════════════════
FROM A CONNECTION GENUINELY OUTSIDE THE HOME NETWORK — a phone on mobile data,
NOT a laptop on the LAN. This is the distinction most likely to be fudged.

  - jellyseerr.goclan.org reaches AUTHELIA, and Jellyseerr only AFTER auth.
  - jellyfin, sonarr, radarr, prowlarr, grafana, auth and (if it exists)
    tubesync .goclan.org ALL UNREACHABLE. RECORD THE FAILURE MODE FOR EACH:
      under (B) they should fail to RESOLVE or ROUTE;
      under (A) they resolve and are refused by forward-auth — A WEAKER
      RESULT, and itself the measurement that justifies (B).
  - REPEAT THE WHOLE NEGATIVE SET OVER IPv6 if the client has it. A v4-only
    test proves half the boundary.
  - If (B) won, the UDM-Pro's WAN view shows NO new inbound permit.

A PASS ON THE POSITIVE TEST WITH NO NEGATIVE CONTROLS IS A FAILED MILESTONE.

Constraints:
- Never commit to main. Branch first, PR via `gh pr create` (title
  imperative, <=70 chars, no prefix; body = summary + test plan + manual
  steps).
- cloudflared is packaged (2026.5.2 as of 2026-08-25) — no flake input needed
  for (B). Verify at session time.
- Minimal diffs; commit only the files this change touches.
- Verify by evaluation:
    nix flake check
    nix eval --no-update-lock-file --raw \
      '.#nixosConfigurations.ernst.config.system.build.toplevel.drvPath'
- Claude does not deploy: `clan machines update ernst`, `clan vars generate
  ernst`, and every UDM-Pro / Cloudflare change are lgo's steps.
- Update docs/roadmap.md's status table AND the interim-rule ledger in the
  same PR — this is the milestone that fills in the WAN bypass row, and (if
  (A) wins) updates standing note SN2 from "owed" to "decided".
````

---

## Packaging — the constraint shaping M12, M14 and M15

**Establish which services have upstream modules IN-SESSION, on the session's own
date, and use THAT list.** Not the one below, and not the one in any milestone
prompt. Both go stale, and this repo has already paid for a plausible inference
recorded as a measurement three times (M2's VLAN 80, M2b's `br0` MAC, and M11's
three falsified premises).

**Surveyed 2026-08-25** against ernst's own pin (`nixpkgs` @ `fcb8fcd`,
2026-08-09), by evaluating `nixosConfigurations.ernst`:

| | upstream NixOS module | packaged |
|---|---|---|
| bazarr, lidarr, jellyseerr, audiobookshelf, slskd, autobrr | **yes** | yes |
| **tdarr** | **yes** — `services.tdarr` | **yes**, 2.74.01 |
| **unpackerr** | **no** | **yes**, 0.15.2 — needs a unit, not a derivation |
| readarr | yes | yes — **but archived upstream; a module is not maintenance** |
| cloudflared | — | yes, 2026.5.2 |
| byparr, umlautadaptarr, cleanuparr, scraparr, soularr, kapowarr, questarr, storyteller, muxarr, janitorr, wizarr, jellystat, mediathekarr, dispatcharr | no | no |

**Two of these contradict earlier drafts of the milestones above** — tdarr and
unpackerr were both listed as needing hand-rolled derivations and neither does.
That is exactly why the survey is a step rather than a table.

Everything in the last row needs a **hand-rolled derivation**. Expected shapes,
**to be confirmed not assumed**: ~~byparr (Python + Camoufox)~~ **byparr (Python
+ Playwright + `invisible-playwright`; NOT Camoufox — corrected 2026-08-26, see
[M12b](#m12b-featernst-byparr))**, umlautadaptarr (.NET), cleanuparr (.NET),
scraparr (Python), soularr (Python), kapowarr (Python), questarr (Node),
storyteller (**Docker-first — check whether a sane non-Docker path exists at
all**), muxarr (check), janitorr (JVM), jellystat (Node), mediathekarr (.NET).

**M12 settled three of these in practice and the answers generalise** — read
[its packaging section](#packaging-three-derivations-two-shapes-and-why-neither-is-a-flake-input)
before writing the next one. In short: **take the upstream release artifact when
there is one** (it is what nixpkgs does for `sonarr`, `radarr`, `prowlarr` and
`bazarr`), build from source only when there is not; and **pin with a version and
a hash in the derivation rather than a flake input**, because `nix flake update`
moves every row in the lock and nothing distinguishes "bump nixpkgs" from
"silently move a service in the request path of every search".

### `virtualisation.oci-containers` inside an nspawn container is REJECTED

**State this in every milestone that adds a service.**

It would be faster, and it is **a real regression from what `arr.nix` is**: a
container whose **entire value** is that upstream units, upstream hardening and
`systemd-analyze` scores are **legible**. M4's Prowlarr table — 8.2 EXPOSED before,
1.3 OK after — is only possible because the unit is a NixOS unit. **A Docker image
inside it is opaque to every one of those.**

**The escape hatch when upstream ships only an image is the PODMAN TIER invariant
#1 already names and [M9](#m9-featernst-tubesync) is opening — not
`oci-containers`-in-nspawn.**

### M11 added a packaging lesson worth generalising here

**A Nix-rendered config in the read-only store is not inert when wrong.**

opencode **merges** its config sources, so a malformed store file **aborts every
run** — and **cannot be overridden by environment variables** (`OPENCODE_CONFIG`
and `OPENCODE_CONFIG_DIR` were both tried; only relocating `XDG_CONFIG_HOME`
avoids it). **And opencode fetches ~15 MB of npm at runtime into its config
directory**, so **the directory must be WRITABLE** — a `xdg.configFile` store
symlink is not enough, and needs a `/persist` entry or it refetches after every
rollback.

**Any milestone rendering config into the store for a tool that also WRITES there
must check both properties before assuming the pattern transfers.** The pattern
works everywhere else in this repo because everywhere else the tool only reads.

### Hardening is not optional, and one trap is worth restating everywhere

Every milestone requires **`systemd-analyze security --offline=true` on every new
unit**, with **before/after scores in the PR body**, following M4's table. Offline
analysis works against the container's generated units, so it can be run **before**
a deploy.

**WATCH FOR THE PROWLARR TRAP IN REVERSE.** Any upstream unit shipping
`DynamicUser = true` that gets switched to a **static uid** **SILENTLY loses**
`NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, `ProtectHome=read-only`,
`RemoveIPC` and `RestrictSUIDSGID` — because `DynamicUser` **implies all six** and
upstream sets **none** of them explicitly. **Restate all six.** M4 measured
Prowlarr at **8.2 EXPOSED** before this was caught, and the switch itself looked
like a one-line change.

The corollary, which M12 depends on: **a service with no persistent state has no
reason to make that switch at all.** FlareSolverr keeps `DynamicUser`; Byparr
should too.

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

**~~recyclarr.~~ Landed with M4** ([#85](https://github.com/lutzgo/clanarchy/pull/85)),
outside that milestone's own prompt, with the template body transcribed inline and
its provenance recorded (config-templates @ `9faf65f`). **Extended by
[M12(g)](#m12-featernst-arr-helpers)**, which adds the German quality profiles and
a per-series Remux-2160p profile for Sonarr. This entry is kept only so the
sequencing is legible; there is nothing left to evaluate.

**IPv6 on VLAN 90 — a decision the fleet owes itself.** Promoted out of the
backlog into [standing note SN2](#sn2-ipv6-is-off-and-that-is-now-a-decision),
because it is not a piece of work waiting to earn a milestone: it is a question
that several future milestones will trip over, and it needs to be answered
*before* one of them answers it by accident. Measured baseline (2026-08-25):
link-local only on every container, no GUA anywhere. **A GUA on VLAN 90 makes it
an incident.** [M16](#m16-featernst-external-ingress) is the nearest trigger.

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

**Expose Ollama via Traefik — and [M11](#m11-featfleet-local-coding-agent) now
argues against it.** The original entry reopened the native-vs-container decision:
Ollama runs as a host service because ROCm wants the card directly, so a Traefik
route means deciding whether it stays native with a route pointed at the host or
moves into a container with GPU access plumbed through.

M11's Phase 2 supersedes the question rather than answering it. **Ollama has no
authentication and its API includes model *pull* and *delete*** — it is an
unauthenticated **admin** endpoint, not a read-only inference service, so a
Traefik route would need forward-auth that no API client speaks. **ZeroTier
terminates in ernst's host netns, where Ollama already lives**, so a second client
needs no route, no veth and no UDM-Pro rule. **The recommendation is ZeroTier
only, and the trigger is a second client actually needing it.** Keep this entry as
the place the *native-vs-container* question is recorded, but do not treat a
Traefik route as the obvious answer to remote access.

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
