# Accepting pull requests into `main`

Clanarchy uses a simple branch-per-change workflow: nothing lands on `main` except through a pull request. This guide covers reviewing and merging PRs, and the recovery steps when something goes wrong.

Bookmark naming and PR conventions are described in [CLAUDE.md → Version Control Workflow](https://github.com/lutzgo/clanarchy/blob/main/CLAUDE.md); the mechanics of driving the repo are in [the jj workflow guide](jj-workflow.md).

The repo is driven with jj, colocated with git — but **`gh` is unaffected**, so the entire review-and-merge path below is unchanged apart from the local checkout and cleanup steps.

---

## Quick reference

| Command | What it does |
|---------|--------------|
| `gh pr list` | Open PRs on this repo |
| `gh pr view <n>` | Show PR summary + checks |
| `gh pr diff <n>` | Show the full diff |
| `gh pr checks <n>` | CI status for the PR |
| `gh pr merge <n> --squash --delete-branch` | Squash-merge and delete the branch |
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
   Prefer the machine the change actually targets. Note this activates — there
   is no stage-only mode (see [deploy.md](deploy.md)), so for a change that
   could cost you the machine (bootloader, disko, impermanence), have console
   or [remote unlock](remote-unlock.md) access to hand before you run it.
5. **Secrets are not committed.** Anything under `vars/per-machine/*/` should only change if the PR explicitly regenerated a var. Never commit plaintext keys.

---

## Merge

Squash-merge is the default — it keeps `main` linear and each PR shows up as a single commit:

```bash
gh pr merge <n> --squash --delete-branch
```

Use `--merge` (a real merge commit) only when the branch history itself is meaningful, e.g. a multi-step machine bring-up where each commit is worth preserving.

After merging, sync your local view. There is no checkout and no fast-forward merge: a
tracked `main` advances on its own, and the bookmark for a branch GitHub has just deleted
is forgotten rather than deleted (forgetting drops it locally without trying to push the
deletion back to a remote that no longer has it):

```bash
jj git fetch
jj bookmark forget <branch>
```

---

## Reject / request changes

```bash
gh pr review <n> --request-changes --body "…"
gh pr comment <n> --body "…"
gh pr close   <n>                # abandon
```

Prefer inline review comments (`gh pr review <n> --comment --body …`) for small fixes over closing and reopening.

---

## Recovery

**Merged the wrong PR.** Revert with a follow-up PR, never by force-pushing `main`:

```bash
jj git fetch
jj new main -m "Revert PR #<n>: <reason>"
jj backout -r <merged-rev>       # no -m 1 to get wrong; jj handles merges itself
jj squash                        # fold the backout into @
jj bookmark set fix/revert-pr-<n> -r @
jj git push --bookmark fix/revert-pr-<n>
gh pr create --title "Revert PR #<n>" --body "Reverts #<n>: <reason>"
```

**Local `main` diverged from `origin/main`.** This failure mode does not arise under jj:
`main` is a bookmark that moves only when you move it or when `jj git fetch` advances it,
and nothing is ever "checked out on" it, so stray commits cannot accumulate there. If it
does somehow point somewhere unexpected, put it back with:

```bash
jj bookmark set main -r main@origin
```

**Anything else.** `jj undo` reverses the last operation; `jj op log` + `jj op restore <op>`
reverses further back, including operations git does not record at all.

Never `git push --force` (or `--force-with-lease`) to `main`. If a bad commit already reached the remote, revert it via a PR instead.

---

## When Claude opens the PR

When Claude Code creates a PR on your behalf:

- The bookmark name follows the `<type>/<slug>` convention in [CLAUDE.md → Version Control Workflow](https://github.com/lutzgo/clanarchy/blob/main/CLAUDE.md).
- The PR title is imperative and unprefixed; the body contains a summary and a test plan.
- Claude will not merge the PR itself — merging is always your call. Review, then run `gh pr merge <n> --squash --delete-branch` when ready.
