# Updating the whole fleet

Bumping flake inputs and rolling the result across all five machines.
For deploying one machine, see [Deploying](deploy.md); this guide is about the
part that has repeatedly gone wrong — **which** inputs move, in what order, and
how to know before deploying that nothing broke.

## The rule: never plain `nix flake update`

`nix flake update` bumps everything at once, and in this flake at least two
inputs have been *measured* to break a machine on their own. When sixteen
inputs move together, a broken eval tells you nothing about which one did it,
and you are bisecting a sixteen-way change with a household depending on the
result.

Update in **named stages**, each its own PR, each gated before merge:

```bash
nix flake update <input> [<input> …]     # named, never bare
```

Bare `nix flake update` is reasonable in exactly one case: you intend to read
and act on every line of the resulting diff.

## Stage 0 — know where you are

```bash
# direct inputs, oldest first — these are what you are deciding about
for i in $(jq -r '.nodes.root.inputs | keys[]' flake.lock); do
  n=$(jq -r --arg i "$i" '.nodes.root.inputs[$i]' flake.lock)
  d=$(jq -r --arg n "$n" '.nodes[$n].locked.lastModified // empty' flake.lock)
  [ -n "$d" ] && printf '%-26s %s\n' "$i" "$(date -d @"$d" +%Y-%m-%d)"
done | sort -k2
```

Everything else in `flake.lock` is transitive and moves when its parent does.

Then establish the **baseline drvPaths**, because the only trustworthy statement
about an input bump is which machines' derivations it changed:

```bash
for m in ernst miralda jens biene birte; do
  printf '%-8s %s\n' "$m" \
    "$(nix eval --no-update-lock-file --raw ".#nixosConfigurations.$m.config.system.build.toplevel.drvPath")"
done | tee /tmp/drv-before.txt
```

## Stage 1 — the inputs that move cleanly

Bump the ones with no known coupling, all in one PR. After bumping:

```bash
nix develop -c bash scripts/check.sh     # five machines + fmt, all OK
```

Then diff the drvPaths against `/tmp/drv-before.txt`. **A machine whose drvPath
is unchanged is not being redeployed** — that is the single most useful fact in
the whole process, and it is how you keep the deploy list short.

For a machine that *did* move, find out why with `nix-diff`, not by guessing:

```bash
nix-diff /nix/store/<before>.drv /nix/store/<after>.drv | head -40
```

**Do not read `nix build --dry-run` as the change set.** It lists every
derivation missing from *this laptop's* store, which wildly overstates a remote
host's rebuild — it once read `container-arr` as changing when its system drv
was byte-identical (#346).

## Stage 2 — the coupled and the dangerous, one PR each

Inputs that are known not to move alone. **Verify each claim here before
trusting it — these expire.** The check is two minutes:

```bash
nix flake update <input>
nix eval --no-update-lock-file --raw '.#nixosConfigurations.<machine>.config.system.build.toplevel.drvPath'
git checkout flake.lock          # or: cp back a copy you made first
```

Current state of the known couplings, re-measured 2026-11-01:

| Input | Status |
|---|---|
| `nixpkgs` | One input for the whole fleet since #368 (the nixpkgs-unstable channel tarball, `flake.nix`). The old `nixpkgs-unstable` input and its `importService` coupling with birte are gone along with the second package set. |
| `jovian-nixos` | **No longer blocked.** It used to fail with `attribute 'holo-session-selection' missing`; that was Jovian moving its package set into a `makeScope` namespace, fixed in #362 by using `pkgs.jovianPackages.*`. Moved alone successfully on 2026-10-25. |
| `clan-core` | Carries `nixpkgs` with it. Treat as a nixpkgs bump, never as a small one. |

Anything touching a service with persistent state — Immich, Nextcloud,
Paperless, the mail stack — is its own PR with its own rollback plan, not part
of a sweep. Take a `pg_dump` **and** a ZFS snapshot first:

```bash
zfs snapshot zdata/state@pre-<change>-$(date +%Y%m%d-%H%M)
```

## Stage 3 — deploy, in this order

Deploy **ernst last**. It runs the ingress path, so if it comes up wrong
nothing else is reachable by name — and you want the laptops already updated and
able to help diagnose.

```
miralda → jens → biene → birte → ernst
```

Skip any machine whose drvPath did not move.

Before the first deploy, check that no machine has a pending vars prompt —
generators run for *every* machine, so an unrelated one blocks all targets:

```bash
for m in ernst miralda jens biene birte; do printf '%-8s ' "$m"; clan vars check "$m"; done
```

Then, per machine:

```bash
nix develop -c clan machines update <machine>
```

**On biene and birte, do not deploy naively.** `clan machines update` compiles
on the *target*, and a handheld APU compiling vendor Mesa takes hours while
ernst idles. Use the build-on-ernst-and-relay recipe in
[AGENTS.md](https://github.com/lutzgo/clanarchy/blob/main/AGENTS.md) §2.

## Stage 4 — verify, and mean it

A deploy that exits 0 has not been verified. For each machine:

```bash
# the generation must equal what the tree builds — not merely "a new one"
readlink /run/current-system
nix eval --no-update-lock-file --raw '.#nixosConfigurations.<m>.config.system.build.toplevel'

systemctl --failed
```

On ernst that host-level check proves nothing about the containers, which is
where most of the fleet actually lives:

```bash
for c in $(machinectl list --no-legend | awk '{print $1}'); do
  n=$(systemd-run --machine="$c" --collect --pipe --quiet systemctl --failed --no-legend | wc -l)
  [ "$n" != "0" ] && echo "$c: $n failed"
done
podman ps --format '{{.Names}} {{.Status}}'
```

`--collect` is not optional: without it the probe unit lingers and fires a false
`ContainerSystemdUnitFailed` alert.

Then exercise the surfaces a broken update actually shows up in — a couple of
vhosts through Traefik, the service index, and Prometheus targets.

## Traps that have each cost a day

- **`gh pr merge` does not fetch.** Run `jj git fetch` after merging, then check
  `@-` *is* the merge commit. `jj st` saying "no changes" is not evidence.
- **Deploying from a branch applies that branch's whole config**, not a diff.
  Two open PRs on one machine means the second deploy silently reverts the
  first. Deploy from `main` after merging.
- **Stopping a deploy does not stop the target.** See [AGENTS.md](https://github.com/lutzgo/clanarchy/blob/main/AGENTS.md) §2.
- **`clan vars generate` commits as a jj sibling.** After running it,
  `jj diff --from main --to <bookmark> -- vars/` must be non-empty, or the
  deploy ships the old secret.
- **A drifted machine deploys more than your change.** Always compare want
  against `readlink /run/current-system` before starting, so you know whether
  you are shipping one input bump or three weeks of backlog.

## Related

- [Deploying](deploy.md) — the single-machine path, and what to do when it fails
- [AGENTS.md](https://github.com/lutzgo/clanarchy/blob/main/AGENTS.md) — the build-host recipe and the jj loop
- [Accepting pull requests](accepting-pull-requests.md)
