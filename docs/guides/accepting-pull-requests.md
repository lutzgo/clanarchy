# Accepting pull requests into `main`

Clanarchy uses a simple branch-per-change workflow: nothing lands on `main` except through a pull request. This guide covers reviewing and merging PRs, and the recovery steps when something goes wrong.

Bookmark naming and PR conventions are described in [AGENTS.md](https://github.com/lutzgo/clanarchy/blob/main/AGENTS.md); the mechanics of driving the repo are in [the jj workflow guide](jj-workflow.md).

The repo is driven with jj, colocated with git — but **`gh` is unaffected**, so the entire review-and-merge path below is unchanged apart from the local checkout and cleanup steps.

---

## Quick reference

| Command | What it does |
|---------|--------------|
| `gh pr list` | Open PRs on this repo |
| `gh pr view <n>` | Show PR summary + checks |
| `gh pr diff <n>` | Show the full diff |
| `gh pr checks <n>` | CI status for the PR |
| `gh pr merge <n> --squash` | Squash-merge (see below — **not** `--delete-branch`) |
| `gh pr close <n>` | Close without merging |

---

## Review checklist

Before merging, confirm:

1. **Scope matches the branch prefix.** A `docs/*` PR should not touch `.nix` files; a `fix/*` PR should not sneak in a refactor. If it does, ask for a split.
2. **No unrelated files.** Watch for accidental `flake.lock` bumps, stale `vars/` files, or leftover working-tree changes from other work.
3. **Build succeeds.** For NixOS module changes, run the relevant build locally before merging — CI is not a substitute:
   ```bash
   nix build .#nixosConfigurations.miralda.config.system.build.toplevel --no-link
   nix build .#nixosConfigurations.biene.config.system.build.toplevel   --no-link
   ```
4. **Deployment is safe.** If the PR changes anything under `machines/*/configuration.nix`, `disko.nix`, `impermanence.nix`, `yubikey.nix`, or `desktop/*.nix`, deploy it from the branch to one machine before merging:
   ```bash
   jj git fetch
   jj new <branch>@origin          # working copy now matches the PR branch
   clan machines update <machine>
   ```
   Prefer the machine the change actually targets. This **activates** — there is
   no stage-only mode (see [deploy](deploy.md)) — so for anything that could
   cost you the machine (bootloader, disko, impermanence) have console or
   [remote unlock](remote-unlock.md) access to hand first.
5. **Secrets are not committed.** Anything under `vars/` should only change if
   the PR explicitly regenerated a var. Never commit plaintext keys.
6. **Comment-only and docs-only PRs should leave the derivation untouched.**
   `nix eval --raw '.#nixosConfigurations.<m>.config.system.build.toplevel.drvPath'`
   before and after should be byte-identical. If it moved, something that looked
   like a comment was content — a `#` line inside a `''` block is a file in the
   store, not a Nix comment.

## Merge

```bash
gh pr merge <n> --squash
gh api -X DELETE repos/lutzgo/clanarchy/git/refs/heads/<branch>
jj git fetch && jj bookmark forget <branch>
```

Squash-merge is the default: it keeps `main` linear and each PR lands as one
commit. Use `--merge` only when the branch history itself is meaningful, e.g. a
multi-step machine bring-up where each commit is worth preserving.

**Why four commands and not `--delete-branch`**, why the fetch is not optional,
and what to do when a bookmark refuses to move: see
[the jj workflow](jj-workflow.md#things-that-behave-differently-because-the-repo-is-colocated).

## Reject / request changes

```bash
gh pr review <n> --request-changes --body "…"
gh pr comment <n> --body "…"
gh pr close   <n>                # abandon
```

Prefer inline review comments for small fixes over closing and reopening.

## When it goes wrong

Reverting a merged PR, undoing a jj operation, and putting a stray `main` back
are all in [the jj workflow's recovery section](jj-workflow.md#recovery). The one
rule that does not live there: never `git push --force` to `main`. If a bad
commit has already landed, revert it through a PR.

## When Claude opens the PR

- The bookmark name follows the `<type>/<slug>` convention in [AGENTS.md](https://github.com/lutzgo/clanarchy/blob/main/AGENTS.md).
- The PR title is imperative and unprefixed; the body contains a summary and a test plan.
- Claude will not merge the PR itself unless you ask — merging is your call. Review, then run `gh pr merge <n> --squash` (plus the ref deletion above) when ready.
