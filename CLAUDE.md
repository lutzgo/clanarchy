# CLAUDE.md

**Read [AGENTS.md](AGENTS.md) first.** It is the canonical set of conventions for
working in this repository — the check command, the deploy interface, the jj
workflow and bookmark prefixes, where a new feature goes, how secrets work, and
how to write a change. OpenCode reads the same file, so there is one copy of the
rules rather than two that drift.

Architecture, for when a change needs it:

- [docs/architecture/machines.md](docs/architecture/machines.md) — the five
  machines, their files, and ernst's service tiers and allocation ledger.
- [docs/architecture/modules.md](docs/architecture/modules.md) — `modules/`,
  `service-modules/`, and how a machine is composed.
- [docs/architecture/decisions.md](docs/architecture/decisions.md) — decisions
  whose reason is not visible from the code.

## Claude Code specifics

- `.claude/settings.json` is tracked and shared; `.claude/settings.local.json`
  is not. The shared file denies mutating `git` commands on purpose — this repo
  is driven with jj, and mixing the two in one session is the documented failure
  mode. It also denies `clan machines install`, `clan vars generate`,
  `clan flash` and `nixos-rebuild`: those are the operator's to run, they need a
  TTY, and a deny turns a confusing failure into a clear block.
- `clan machines update` is NOT denied, as of 2026-10-20 and on request. A
  deploy still needs the YubiKey unlocked for ssh — the key must have been
  touched and its PIN entered in this session, or the deploy dies at
  `agent refused operation` with no prompt anyone can answer. So the operator
  is still in the loop; what changed is that they no longer have to type the
  command. Verify afterwards with `./scripts/post-deploy-check.sh <machine>`,
  which fails fast and names that exact failure.
- Open a PR with `gh pr create --head <bookmark>`. Without `--head` it fails
  with `not on any branch`, because jj leaves git's `HEAD` detached.
- Do not merge a PR unless asked. Merging is the operator's call.
