# Architecture invariants

Properties of the system that a change must design around. Breaking one is a
decision to argue for in a PR body, not a detail to slide past.


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
appear in the [ledger](ledger.md) with a removal trigger. Management
VLAN access is not covered by this rule and is expected to stay direct.

**4 — Names resolve to Traefik; bypasses are deliberate and listed.** Current
and planned bypasses: the qBittorrent WebUI (mgmt VLAN only, never a Traefik
route — see M3); Jellyfin's own authentication, which stays native forever
because TV and mobile clients cannot survive forward-auth; and — since M14 —
**Audiobookshelf's**, for the same client-compatibility reason and by operator
decision, app support being a stated requirement for that library.

**The clause is about CLIENTS, not about how household-y a service feels.** Two
services now sit behind no forward-auth on that basis and one does not:
Jellyseerr is unprotected too, but on a *different* argument (its posture is a
Jellyfin-account login, so removing forward-auth swaps one login for another).
Do not merge the two reasonings — a future service with a browser-only client
gets the middleware however household-facing it is.

**Since M22 there is a THIRD reasoning, and it is not the client clause.**
`photos.goclan.org` (Immich) carries no forward-auth for the usual reason —
two phone apps and the TV add-on, none of which can follow a 302 — but it is
also the first name in this fleet where **part of the surface is meant to be
unauthenticated**. An Immich shared album link is a URL the server answers to
an anonymous caller by design; that is how a family member with no account
here sees an album at all. Forward-auth would not weaken that feature, it
would delete it.

So for this one name the honest statement is not *"the application's own
accounts are the boundary"*. It is: **accounts bound the library, and
possession of a URL bounds anything explicitly shared** — from anywhere on the
internet, until the link is revoked. Immich offers a per-link expiry and
password and they are runtime state; nothing in this repo can set them.

The complete, enforced list of exempt names lives in
`machines/ernst/containers/ingress-policy.nix`, not here — that file is
consumed by both `traefik.nix` and `authelia.nix`, and `withWan` throws at
evaluation if a router disagrees with it.

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

