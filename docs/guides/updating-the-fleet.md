# Updating the whole fleet

The fleet follows **one channel**: `nixpkgs` is the `nixos-unstable` channel
tarball (`flake.nix`), which only advances after NixOS's own system tests
pass. Every other input follows `nixpkgs`. Updating means moving
`flake.lock` forward on that channel. Nobody writes hashes: `nix flake update`
writes them, and they are what makes every machine build the same thing.

## The weekly update PR

`.github/workflows/update.yml` runs every Monday at 04:00 UTC (or by hand:
Actions → Update → Run workflow). It runs `nix flake update`, runs the same
gate as `check.yml`, and opens **one** PR, `chore(flake): weekly input update
<date>`:

- ✅ in the body: all five machines evaluate. Merge it, then deploy (below).
- ❌ in the body: it is a draft. The log is in the PR. Either fix it on that
  branch or ignore it; next week's run tries again.

Doing it by hand is the same thing:

```bash
jj new main
nix flake update
nix develop -c bash scripts/check.sh      # five machines + fmt, all OK
```

## What does NOT move on its own

These are pinned in `flake.nix` on purpose, each with its reason next to it.
`nix flake update` leaves them where they are; changing one is its own PR.

| Input / setting | Pinned to | Why |
|---|---|---|
| `simple-nixos-mailserver` | commit `9004c7d` | upstream dropped kresd; needs unbound in the mail container first |
| ernst's kernel | `linuxPackages_6_18` (LTS) | the NAS changes kernel series only by hand; ZFS must support it |
| `niri-tablet`, `oniri`, `noctalia`, `zjstatus` | tags / commits | upstream release pins |

ZFS machines are safe on this channel: if OpenZFS does not build against a
kernel, evaluation fails in `check`, so the PR goes red before anything
deploys.

Anything touching a service with persistent state (Immich, Nextcloud,
Paperless, the mail stack) when it changes *behaviour*, not just version,
gets a snapshot first:

```bash
zfs snapshot zdata/state@pre-<change>-$(date +%Y%m%d-%H%M)
```

## Deploy, in this order

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

## Verify, and mean it

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
