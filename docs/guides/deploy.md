# Deploying

Deployment is the clan CLI. There is no wrapper around it in this repo, on
purpose — see [why](#why-there-is-no-deploy-helper) at the end.

```bash
nix develop                      # or let direnv do it
clan machines update <machine>
```

`<machine>` is one of `miralda`, `jens`, `biene`, `birte`, `ernst`. Omit it
entirely and clan attempts every configured machine, which is rarely what you
want.

## Everyday use

```bash
clan machines update ernst          # build and switch
clan machines update miralda biene  # several at once
clan machines list                  # what is managed
clan machines generations ernst     # what has been deployed
```

Clan resolves each machine's target host from its own deployment configuration,
so nothing has to be passed in the normal case.

| Flag | Use |
|------|-----|
| `--target-host HOST` | deploy to a different address than the configured one |
| `--build-host HOST` | build somewhere other than the target — useful for birte, which is slow |
| `--tags TAG...` | select machines by inventory tag instead of by name |
| `--host-key-check {strict,ask,accept-new,tofu,none}` | SSH host-key policy; `ask` is the default and is what prompts on a first ZeroTier connection |
| `--no-check` | skip the pre-switch safety checks (switch inhibitors) |
| `--debug` | full logging when something is wrong |

### When the configured name is not resolving

A laptop on a foreign network before ZeroTier is up is the usual case:

```bash
# ZeroTier IPv6 (read it on the machine: ip -6 addr show altname zerotier)
clan machines update biene --target-host root@<biene-zt-ipv6>

# LAN hostname when on the home network
clan machines update biene --target-host root@biene.skynet.lan
```

See [networking](networking.md#biene-not-reachable-from-a-different-network)
for the connectivity checks to run first.

## It needs a TTY

`clan vars generate` runs for **every** machine in the flake as part of an
update, so an unanswered prompt anywhere blocks any target — and a prompt with
nowhere to appear fails with `termios.error` rather than something legible. Run
deploys from a real terminal, not from a tool or a script.

## Outside the devShell

```bash
nix develop --command clan machines update miralda
```

Or drive `nixos-rebuild` yourself, which is what to reach for in the one case
clan does not cover — staging a change for the next boot *without* activating
it:

```bash
nix --extra-experimental-features 'nix-command flakes' run \
  nixpkgs#nixos-rebuild -- boot \
  --flake .#miralda \
  --target-host root@miralda.goclan.org \
  --no-reexec -j auto
```

Always `--no-reexec`, never `--fast`, and never `--build-host localhost`.

**There is no stage-for-next-boot mode in clan.** `clan machines update` runs
`switch-to-configuration boot` *and* `switch`, so the boot entry is written and
the change is activated. That matters for anything that could cost you the
machine — bootloader, disko, impermanence — so have console or
[remote unlock](remote-unlock.md) access to hand before running it.

## Vars, and the health check

Deployment does not create vars. When a generator is added or changed:

```bash
clan vars generate <machine>     # prompts for any new inputs
clan machines update <machine>
```

`clan vars generate` commits the encrypted result under `vars/`. It is the only
thing that should ever write there — and it commits as a **jj sibling**, so
check `jj diff --from main --to @ --stat -- vars/` is non-empty afterwards and
get the result onto `main` in its own `vars/`-prefixed PR.

!!! warning "The health check covers every machine"
    `clan machines update` health-checks **all** machines before proceeding. If
    any machine has vars needing re-encryption the update is blocked — repair
    with `clan vars fix <name>`. This used to be cited as a reason to fall back
    to the `deploy` helper; that helper is gone, and bypassing the check was
    never a fix.

## When a deploy fails

`clan machines update` exits non-zero if any unit failed during activation, and
prints the failing units at the end. That output is worth reading rather than
retrying — several real problems on ernst surfaced exactly there, including a
mount that had been failing on every boot for a month.

A failed *unit* does not mean a failed *deploy*: the new generation is still
activated. And the host's view is not the whole picture — for ernst, check
inside each container too:

```bash
ssh root@<machine> systemctl --failed

# on ernst, per container — the host's view is clean either way
for c in $(machinectl list --no-legend | awk '{print $1}'); do
  echo "== $c"
  systemd-run --machine="$c" --collect --pipe --quiet systemctl --failed --no-legend
done
```

`--collect` is not optional: without it a failed probe unit lingers and fires a
spurious `ContainerSystemdUnitFailed` alert.

### Build succeeds but the copy fails

The build happens locally; only the store closure is copied. If hostname
resolution is the problem, pass the address directly with
`--target-host root@<ip>`.

### SSH signing fails

`sign_and_send_pubkey: signing failed … agent refused operation` is a YubiKey
problem, not a deploy problem — see [YubiKey](yubikey.md#ssh-signing-fails).

## Why there is no `deploy` helper

The devShell used to carry `deploy`, `deploy-miralda`, `deploy-biene`,
`deploy-birte` and `deploy-ernst`, plus `MIRALDA_HOST=`-style environment
overrides. They drove `nixos-rebuild` directly, which made them fast, but it
also meant they **skipped clan's inventory evaluation** — so they could not
apply secrets or clan vars. The result was two ways to deploy that looked
interchangeable and were not: one quietly did less, and the difference only
showed up later as a machine missing a secret it should have had.

`clan machines update` is the interface this repo is built around: the inventory
in `clan.nix`, the service modules, and every `clan.core.vars.generators.*` all
assume it. Keeping a second path that bypassed half of that was a bug waiting
for someone to hit it. Do not reintroduce them in any form, including a thin
alias.

## Related

- [Accepting pull requests](accepting-pull-requests.md) — review and merge flow
- [First-time install](first-time-install.md) — `clan flash` / `clan machines install`
- [YubiKey](yubikey.md) — the card that authenticates the deploy
