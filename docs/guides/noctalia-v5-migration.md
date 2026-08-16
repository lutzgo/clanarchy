# Noctalia v5 migration (deferred)

**Status: not started, deliberately.** The `noctalia` flake input is pinned to a pre-v5 revision. This page records why, what the migration involves, and the condition for lifting the pin — so the decision does not have to be re-derived from the flake comment every time someone notices the input is stale.

## The pin

```nix
# flake.nix
noctalia.url = "github:noctalia-dev/noctalia-shell/272cd91408b5ff6e329e6397eed042fe422069e7";
```

| | |
|---|---|
| Pinned rev | `272cd91408b5ff6e329e6397eed042fe422069e7` |
| Rev date | 2026-05-26 |
| Latest **stable** upstream tag | `v4.7.7` |
| v5 status | still **beta** (`v5.0.0-beta.8` at time of writing) |

Two independent reasons to sit still, and both must clear before this moves:

1. **v5 has not shipped stable.** Every v5 tag upstream is a beta. Migrating a 1150-line config onto a moving pre-release means rewriting it more than once.
2. **v5 rewrote the Home Manager module** from typed Nix options to freeform TOML. This is not a version bump; it is a rewrite of how the config is expressed.

## Scope of the rewrite

`modules/desktop/noctalia-hm.nix` is **1150 lines** and declares roughly **41 widget/plugin entries** under `programs.noctalia-shell.settings`. It is consumed by:

- `modules/desktop/niri-hm.nix` (miralda)
- `modules/desktop/labwc-hm.nix` (biene)
- `modules/users/sabine.nix` (plugin declarations)
- `flake.nix` (HM sharedModules wiring)

So both headful desktops depend on it, and a botched migration takes out the shell on the daily driver *and* Sabine's machine at once.

What the migration has to deal with:

- **Typed options → freeform TOML.** The current file leans on the module's type checking to catch mistakes at eval time. Freeform TOML moves those failures to runtime, where a bad key is a silently missing widget rather than a build error. Expect to lose the eval-time safety net and to need actual on-screen verification of every panel.
- **Stylix interaction.** The Stylix noctalia target injects eight settings values (bar/dock/osd/notifications `backgroundOpacity`, bar `capsuleOpacity`, ui `panelBackgroundOpacity`, ui `fontDefault`/`fontFixed`). The current file uses `lib.mkForce` on these to win the merge. Freeform TOML has no option-merge semantics, so this coordination has to be re-established by hand — see the Stylix notes in `CLAUDE.md`.
- **Float vs integer.** Opacity/scale/ratio values must stay floats (`1.0`, not `1`). Under typed options a wrong type is an eval error; under freeform TOML it is a wrong value at runtime.
- **Per-user plugin state.** `modules/users/sabine.nix` writes `noctalia/plugins.json` with `force = true`, and biene's wallpaper handling pins `~/.cache/noctalia/wallpapers.json`. Both touch paths the new schema may relocate.

## Unpin condition

Lift the pin when **all** of the following hold:

1. Upstream has a **stable** v5 release (a non-beta tag), and it has been out long enough that the settings schema has stopped moving.
2. There is time to do the rewrite and verify it on hardware — this is not a merge-and-see change. Both miralda and biene need their panels, docks, launcher, OSD and notifications checked visually.
3. Ideally: migrate one machine first (biene is the better canary — it is not the daily driver) and keep the other on the pin until the new config is proven.

Until then, bumping `noctalia` in `flake.lock` will fail to evaluate or produce a broken shell. That is intended; the pin is the safeguard.

## Related

- Pin comment in `flake.nix` (`inputs.noctalia`) — cross-references this page
- `CLAUDE.md` → Noctalia Stylix target conflicts, Nix float vs integer
- [`docs/guides/noctalia-profiles.md`](noctalia-profiles.md) — Sabine's Shell Profile workflow, which the rewrite must preserve
