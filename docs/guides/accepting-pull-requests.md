# Accepting pull requests into `main`

Clanarchy uses a simple branch-per-change workflow: nothing lands on `main` except through a pull request. This guide covers reviewing and merging PRs, and the recovery steps when something goes wrong.

Branch naming and PR conventions are described in [CLAUDE.md → Git Workflow](https://github.com/lutzgo/clanarchy/blob/main/CLAUDE.md).

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
   gh pr checkout <n>
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

After merging, sync your local `main`:

```bash
git switch main
git fetch origin
git merge --ff-only origin/main
git branch -d <branch>   # only if the branch is fully merged
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

**Merged the wrong PR.** Revert with a follow-up PR, don't force-push `main`:

```bash
git switch -c fix/revert-pr-<n>
git revert -m 1 <merge-sha>      # -m 1 only if --merge; drop -m for squash
gh pr create --title "Revert PR #<n>" --body "Reverts #<n>: <reason>"
```

**Local `main` diverged from `origin/main`** (e.g. you accidentally committed on `main`):

```bash
git switch main
git log --oneline origin/main..HEAD    # see the stray commits
git switch -c chore/rescue-main        # move them onto a branch
git switch main
git reset --hard origin/main           # only after confirming the rescue branch has them
```

Never `git push --force` (or `--force-with-lease`) to `main`. If a bad commit already reached the remote, revert it via a PR instead.

---

## When Claude opens the PR

When Claude Code creates a PR on your behalf:

- The branch name follows the `<type>/<slug>` convention in [CLAUDE.md → Git Workflow](https://github.com/lutzgo/clanarchy/blob/main/CLAUDE.md).
- The PR title is imperative and unprefixed; the body contains a summary and a test plan.
- Claude will not merge the PR itself — merging is always your call. Review, then run `gh pr merge <n> --squash --delete-branch` when ready.
