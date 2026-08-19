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

Verified against the repo on 2026-08-19 (`main` @ `cc2a3f2`).

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
| M1 — Kvantum linkGeneration drift | **open** | — | No fix on `main`: the string `kvantum` appears nowhere in the repo. See [M1](#m1-fixkvantum-stylix-linkgen-drift) for the on-disk evidence gathered |
| M2 — ernst VLAN bridge | **open** | — | [M2](#m2-featernst-vlan-bridge) — high risk, gates M2b/M3/M5 |
| M2b — Jellyfin on a tap | **open** | — | [M2b](#m2b-featernst-jellyfin-tap) |
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
| L2 | `skynet-iot` VLAN → `ernst:8096/tcp` | UDM-Pro ZBF (off-repo) | TVs / streaming devices live on the IoT VLAN | **M5** — same as L1 | open |
| L2a | IoT name resolution for L2 | UDM-Pro DHCP + ZBF (off-repo) | IoT clients could not resolve `jellyfin.skynet.lan` — needed either the IoT DHCP DNS pointed at Technitium (10.0.5.3) plus a `skynet-iot → 10.0.5.3:53` rule, or a per-device DNS override | **M5** — repoint at Traefik; keep whichever DNS path is still required and promote it out of this ledger if it becomes permanent | open — ⚠️ *record the exact form actually applied on the UDM-Pro when M5 starts; it was not captured here* |
| L3 | `networking.firewall.allowedTCPPorts = [ 8096 ]` on the host | `machines/ernst/containers/jellyfin.nix` | Jellyfin shares the host network namespace (`privateNetwork = false`), so its port is a host port | **M2b** — the tap gives the container its own L2 identity; the host port opening goes away and the ACL moves to the UDM-Pro | open |
| L4 | arr WebUI ports `9696` / `8989` / `7878`, mgmt-VLAN scoped | M4 (host firewall, v1) | arr v1 runs on host networking like Jellyfin did | **M5** for the routes, plus a tap migration mirroring M2b | not yet created |
| L5 | Traefik `ipAllowList` on the arr + Grafana routes (mgmt + wg-travel) | M5 (`traefik` container) | There is no identity provider yet | **M7** — replaced by the Authelia forward-auth middleware | not yet created |

---

## M1 — `fix/kvantum-stylix-linkgen-drift`

**Goal.** Home Manager's `linkGeneration` intermittently trips over
`~/.config/Kvantum/Base16Kvantum` existing as a real directory on miralda,
turning a routine `clan machines update miralda` into a failed activation. Find
the actual writer before writing any fix — the cleanup hook is only correct if
the thing that recreates the directory is understood.

**Depends on.** Nothing. **Risk.** Low, but it touches `home.activation` ordering
on a machine Sabine's config shares modules with.

**State verified 2026-08-19** — no fix exists on `main`:

- The string `kvantum` appears **nowhere** in the repo (`rg -i kvantum` → no hits).
  Stylix owns the Kvantum target entirely; `stylix.targets.qt.enable` evaluates to
  `true` for `lgo` on miralda. Stylix is pinned to a commit
  (`4fa830ff900efc842425aaa88c6e41da99f2823d` in `flake.nix`), so an upstream fix
  after that commit would not be in the tree.
- On-disk right now: `~/.config/Kvantum/` is a real directory containing the store
  symlink `kvantum.kvconfig`; `Base16Kvantum/` is a real directory containing two
  store symlinks (`Base16Kvantum.kvconfig`, `Base16Kvantum.svg`). All point at the
  **current** HM generation (`bc18cpa0…-home-manager-files`), mtime 2026-08-13
  10:57 — the same shape and mtime as other HM-managed directories such as
  `~/.config/foot/`.
- That shape is HM's ordinary fallback when the parent directory already exists,
  so it is **not by itself proof of drift**. The activation journal could not be
  read from this session (`journalctl -u home-manager-lgo.service` needs root).
  Phase 1 must therefore start by establishing that the failure still reproduces.

````text
Read CLAUDE.md fully before doing anything.

Work in the clanarchy repo on miralda. Branch: fix/kvantum-stylix-linkgen-drift.

Problem: Home Manager activation on miralda intermittently fails in
linkGeneration because ~/.config/Kvantum/Base16Kvantum exists as a real
directory where HM wants to place its own entry. This is diagnose-then-fix:
do not write a workaround before Phase 1 concludes.

PHASE 1 — DIAGNOSIS (no .nix changes yet).

State already established, do not redo:
  - `rg -i kvantum` over the repo returns nothing. There is no repo-side
    Kvantum config; Stylix's qt target owns it
    (stylix.targets.qt.enable = true for lgo on miralda).
  - Stylix is pinned by commit in flake.nix
    (4fa830ff900efc842425aaa88c6e41da99f2823d).
  - On disk today: ~/.config/Kvantum is a real dir holding the store symlink
    kvantum.kvconfig; Base16Kvantum/ is a real dir holding two store symlinks.
    All resolve to the current home-manager-files generation. This is HM's
    normal fallback shape, not proof of failure on its own.

Establish, with evidence pasted into the PR body:
  1. Does it still reproduce? Read the activation journal
     (`sudo journalctl -u home-manager-lgo.service -n 200`, and
     `journalctl --user -u home-manager-*` if relevant) for linkGeneration
     errors — "Existing file ... would be clobbered", or a non-symlink at a
     path HM manages. If there is no failure in recent history, say so
     plainly and stop: close the branch with the evidence rather than adding
     a hook against a problem that no longer occurs.
  2. If it reproduces: identify the writer. The candidates, distinguish them:
     - Stylix's qt/kvantum activation writing a real directory itself;
     - a runtime Qt/Kvantum consumer (Kvantum Manager, a KDE app, the
       pinentry-qt path) creating ~/.config/Kvantum on first run;
     - a stale generation whose files were never collected.
     Use file mtimes, the store paths the symlinks resolve to versus the
     current generation, and `nix eval` on the HM file set to see exactly
     what HM believes it owns under .config/Kvantum.
  3. Check Stylix upstream for a post-pin fix touching the qt/kvantum target
     (git log on the input's repo since the pinned commit, plus its issue
     tracker). Report the finding either way.

PHASE 2 — FIX, chosen by what Phase 1 found.

  a. If upstream fixed it: propose a Stylix input bump. ASK FIRST before
     bumping — the pin is deliberate and a bump moves theming fleet-wide.
     Report what else the bump would pull in (`nix flake lock --update-input
     stylix` on a scratch copy, then diff the lock; do not commit the lock
     change until approved).
  b. Otherwise: a guarded home.activation cleanup hook, ordered BEFORE
     linkGeneration (home.activation.<name> =
     lib.hm.dag.entryBefore [ "linkGeneration" ] ...). It must:
     - act only on the specific path(s) Phase 1 identified;
     - delete ONLY when the path is a real directory/file — never when it is
       a symlink (a symlink is HM's own, and removing it corrupts the
       generation);
     - be idempotent and silent in the normal case.
     Placement: decide between miralda-only (machines/miralda/) and shared
     (modules/desktop/ or modules/users/lgo.nix) by checking whether biene is
     exposed to the same path — biene runs labwc with the same Stylix qt
     target, so state that check explicitly rather than assuming.

TEST PLAN in the PR body: two consecutive `clan machines update miralda`
runs complete cleanly, the second one being the real proof (the first can
mask the problem by removing the offending path). Include the exact journal
lines to check afterwards.

Constraints:
- Never commit to main. Branch first, PR via `gh pr create` (title
  imperative, <=70 chars, no prefix; body = summary + test plan).
- No new flake inputs. The Stylix bump in 2a needs explicit approval.
- Minimal diffs; commit only the files this change touches.
- Verify by evaluation:
    nix flake check
    nix eval --no-update-lock-file --raw \
      '.#nixosConfigurations.miralda.config.system.build.toplevel.drvPath'
  and the same for biene if the fix lands in a shared module.
- Claude does not deploy. Put the deploy steps in the PR body as a runbook
  lgo executes: `clan machines update miralda` from the devShell (the
  deploy-* shell helpers were removed in #59 — do not reintroduce them).
- Update docs/roadmap.md's status table in the same PR.
````

---

## M2 — `feat/ernst-vlan-bridge`

**Goal.** Replace ernst's plain static `enp13s0` with a VLAN-filtering bridge
`br0`, so containers and guests can each hold their own L2 identity on the right
VLAN and be firewalled by the UDM-Pro as distinct hosts. `enp13s0` becomes a
tagged trunk; the host itself stays untagged (PVID) on the current server VLAN
with its address, gateway and DNS moved to `br0` unchanged. Every milestone after
this one depends on it.

**Depends on.** Nothing. **Risk.** **High — remote lockout is possible.** ernst is
reachable only over the network being reconfigured.

**Repo facts the prompt encodes:** `machines/ernst/networking.nix` currently
declares `50-enp13s0` with `Address 10.0.50.10/24`, `Gateway 10.0.50.1`,
`DNS 10.0.5.3`, `Domains "~. skynet.lan"`, `MulticastDNS = true`,
`RequiredForOnline = "yes"`, and a `clanarchy.initrdSsh` block bound to the raw
`enp13s0`. The `Domains = "~."` catch-all is load-bearing — it is what routes
every lookup through Technitium.

!!! warning "There is no boot-only deploy mode"

    `clan machines update` runs `switch-to-configuration boot` **and** `switch`
    (CLAUDE.md). A networkd reconfiguration therefore lands live, mid-session.
    The runbook must be console-first: have the Comet KVM open on the iGPU head
    *before* starting, not after.

````text
Read CLAUDE.md fully before doing anything.

Work in the clanarchy repo on miralda. Branch: feat/ernst-vlan-bridge.
THIS IS THE HIGH-RISK MILESTONE: ernst is reachable only over the network
this change reconfigures. Remote lockout is a realistic outcome of a mistake.

GOAL. Convert machines/ernst/networking.nix from a plain static address on
enp13s0 to a VLAN-filtering bridge:

  - br0 is a VLAN-aware bridge (netdev with VLANFiltering=yes).
  - enp13s0 becomes a tagged trunk port on br0, carrying the VLANs ernst
    needs to place guests on.
  - The host keeps its current identity: untagged / PVID on the server VLAN
    it is on today, with Address=10.0.50.10/24, Gateway=10.0.50.1,
    DNS=10.0.5.3 moved verbatim onto br0.
  - Include ONE commented-out worked example of a MAC-pinned per-service tap
    on br0 (netdev Kind=tap + a bridge-port network + BridgeVLAN tagging),
    so M2b/M3/M5 have a pattern to copy rather than invent. Pin the MAC
    explicitly so the UDM-Pro DHCP reservation is stable.

MUST SURVIVE VERBATIM (read the file header before touching it — the
reasoning is written down there):
  - Domains = "~. skynet.lan". The "~." catch-all is what forces every
    lookup through Technitium at 10.0.5.3; losing it silently changes the
    resolver for the whole machine.
  - MulticastDNS = true (mDNS across the LAN and ZeroTier).
  - The wait-online caveat: the unplugged Intel I226-V (enp12s0, igc) must
    never be able to block boot. wait-online is currently disabled
    fleet-wide by clan-core; if the bridge work changes that, add
    `systemd.network.wait-online = { anyInterface = true; ignoredInterfaces
    = [ "enp12s0" ]; };` and say so.
  - The 50-* prefix ordering, which is what makes our units win against
    clan-core's 99-ethernet-default-dhcp wildcard. Keep the new units in the
    same numeric neighbourhood and check the resulting ordering.
  - clanarchy.initrdSsh stays bound to the RAW enp13s0. Stage 1 has no
    bridge, and this is a recovery channel — ernst's zroot is encrypted, so
    every boot already passes through initrd SSH for the passphrase.

DELIVERABLE — code plus a cutover runbook in the PR body and, if it is long
enough to want a permanent home, docs/runbooks/ernst-vlan-bridge-cutover.md.
The runbook must state:

  - Prerequisite, before anything is deployed: out-of-band console. The
    GL.iNet Comet KVM watches the iGPU head (card0). Confirm it is reachable
    and shows a console first. Also confirm the previous boot generation is
    selectable from the systemd-boot menu — that is the rollback.
  - That `clan machines update ernst` applies the change LIVE (there is no
    stage-for-next-boot mode — CLAUDE.md), so the SSH session may drop at
    the moment networkd reconfigures. Plan for it instead of being surprised
    by it: run the update from a session you can afford to lose, and have
    the KVM open.
  - The UDM-Pro side: which VLANs must be tagged on the switch port feeding
    ernst's SFP+ before the trunk config is deployed. Getting this wrong is
    the most likely cause of a dead link.
  - Verification, in order: `networkctl status br0 enp13s0`,
    `bridge vlan show`, `bridge link show`, `ip -br addr`, then a ping
    matrix — ernst -> gateway, ernst -> 10.0.5.3, a mgmt-VLAN host -> ernst,
    a Family-VLAN host -> ernst:8096 (Jellyfin must still answer; the interim
    rules L1/L2 in docs/roadmap.md depend on it), and `resolvectl status br0`
    showing the "~." routing domain.
  - Recovery: boot-menu rollback to the previous generation via the KVM, and
    what initrd-SSH can and cannot do (it unlocks zroot; it is not a rescue
    shell for stage 2).
  - lgo executes the runbook. Claude does not deploy.

Constraints:
- Never commit to main. Branch first, PR via `gh pr create` (title
  imperative, <=70 chars, no prefix; body = summary + test plan + manual
  steps + the cutover runbook).
- No new flake inputs.
- Minimal diffs; commit only the files this change touches.
- Verify by evaluation:
    nix flake check
    nix eval --no-update-lock-file --raw \
      '.#nixosConfigurations.ernst.config.system.build.toplevel.drvPath'
  Also eval the generated networkd units and paste the relevant ones into
  the PR body:
    nix eval --json \
      '.#nixosConfigurations.ernst.config.systemd.network.networks' \
      | jq 'keys'
- Claude does not deploy: `clan machines update ernst` is lgo's step.
- Update docs/roadmap.md's status table in the same PR.
````

---

## M2b — `feat/ernst-jellyfin-tap`

**Goal.** Move the Jellyfin container off the host network namespace onto its own
MAC-pinned tap on `br0`, giving it a distinct L2 identity the UDM-Pro can
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
private network namespace with a MAC-pinned tap on br0, following the
migration plan already written in that file's header ("Networking — v1: HOST
namespace"). Read that header first; it names the intended shape.

Scope:
  - containers.jellyfin.privateNetwork = true, with a tap on br0 on the
    services VLAN. Pin the MAC (stable DHCP reservation) and copy the pattern
    from the commented example M2 left in machines/ernst/networking.nix.
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
  - DHCP reservation for the pinned MAC on the services VLAN.
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
  - MAC-pinned tap on br0, on the VLAN chosen for this guest. Reuse the
    pattern M2 left commented in machines/ernst/networking.nix.
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
tap-migration note in the file header mirroring the one Jellyfin carried.
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
machines/ernst/containers/traefik.nix, with its own MAC-pinned tap on br0
(pattern from M2). That tap's address is the identity every consumer VLAN
gets its ONE permanent ZBF rule for — the whole point of the milestone.

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
  (a) backend-side firewall source-restriction to Traefik's tap address, or
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
