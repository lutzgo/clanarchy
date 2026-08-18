# Deploying

Deployment is the clan CLI. There is no wrapper around it in this repo, on
purpose — see [Why there is no `deploy` helper](#why-there-is-no-deploy-helper).

```bash
nix develop                      # or let direnv do it
clan machines update <machine>
```

`<machine>` is one of `miralda`, `biene`, `birte`, `ernst`. Omit it entirely and
clan attempts every configured machine, which is rarely what you want.

## Everyday use

```bash
clan machines update ernst          # build and switch
clan machines update miralda biene  # several at once
clan machines list                  # what is managed
clan machines generations ernst     # what has been deployed
```

Clan resolves each machine's target host from its own deployment configuration,
so nothing has to be passed for the normal case. To override it for one
invocation:

```bash
clan machines update biene --target-host root@biene.skynet.lan
```

Useful flags, all from `clan machines update --help`:

| Flag | Use |
|------|-----|
| `--target-host HOST` | deploy to a different address than the configured one |
| `--build-host HOST` | build somewhere other than the target (e.g. build on a fast box, deploy to a slow one) |
| `--tags TAG...` | select machines by inventory tag instead of by name |
| `--host-key-check {strict,ask,accept-new,tofu,none}` | SSH host-key policy; `ask` is the default and is what prompts on a first ZeroTier connection |
| `--no-check` | skip the pre-switch safety checks (switch inhibitors) |
| `--debug` | full logging when something is wrong |

## Differences from the old `deploy` helper

If you have muscle memory from the removed functions, two things changed:

- **`MIRALDA_HOST=` / `BIENE_HOST=` / `BIRTE_HOST=` / `ERNST_HOST=` are gone.**
  Use `--target-host` instead.
- **There is no "stage for the next boot without activating" mode.**
  `deploy <machine> boot` had one; `clan machines update` does not expose it.
  Clan runs `switch-to-configuration boot` and then `switch`, so the boot entry
  is written *and* the change is activated. If you genuinely need to stage
  without activating, that is a `nixos-rebuild boot --flake .#<machine>
  --target-host root@<host>` invocation typed deliberately, not something this
  repo wraps.

## Why there is no `deploy` helper

The devShell used to carry `deploy`, `deploy-miralda`, `deploy-biene`,
`deploy-birte` and `deploy-ernst`. They drove `nixos-rebuild` directly, which
made them fast, but it also meant they **skipped clan's inventory evaluation** —
so they could not apply secrets or clan vars. The result was two ways to deploy
that looked interchangeable and were not: one of them quietly did less, and the
difference only showed up later as a machine missing a secret it should have
had.

`clan machines update` is the interface this repo is built around: the inventory
in `clan.nix`, the service modules, and every `clan.core.vars.generators.*` all
assume it. Keeping a second path that bypassed half of that was a bug waiting
for someone to hit it.

## Regenerating secrets

Deployment does not create vars. When a generator is added or changed:

```bash
clan vars generate <machine>     # prompts for any new inputs
clan machines update <machine>
```

`clan vars generate` commits the encrypted result under
`vars/per-machine/<machine>/`. It is the only thing that should ever write
there.

## When a deploy fails

`clan machines update` exits non-zero if any unit failed during activation, and
prints the failing units at the end. That output is worth reading rather than
retrying — several real problems on ernst surfaced exactly there, including a
mount that had been failing on every boot for a month.

A failed *unit* does not mean a failed *deploy*: the new generation is still
activated. Check with:

```bash
ssh root@<machine> systemctl --failed
```

## Related

- [Updating machines](updating-machines.md) — flake input bumps and the update cadence
- [Accepting pull requests](accepting-pull-requests.md) — review and merge flow
- [First-time install](first-time-install.md) — `clan flash` / `clan machines install`
