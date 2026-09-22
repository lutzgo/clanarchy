# The jj (Jujutsu) workflow

Clanarchy is driven with [jj](https://jj-vcs.github.io/jj/), **colocated** with git. This
guide is the reference for how a change gets from an idea to `main`. The short version —
the invariants and the eight-step loop — lives in
[CLAUDE.md → Version Control Workflow](https://github.com/lutzgo/clanarchy/blob/main/CLAUDE.md);
this page is the why, the translation table, and the recovery paths.

---

## What "colocated" means here

`.jj/` and `.git/` sit side by side in the repo root. `.git` remains authoritative:

- **GitHub, `gh` and CI are untouched.** `gh pr create`, `gh pr merge`, and all three
  workflows in `.github/workflows/` see an ordinary git repository, because that is what
  they are talking to.
- **`clan machines update` is untouched.** It builds the flake from the working directory
  exactly as before.
- **git still works.** Every git command remains valid against the same repo. It is the
  escape hatch, not the daily driver — and mixing the two within one session is the one
  thing worth avoiding, because it is where the confusion comes from.
- Every `jj` command synchronises jj's view with git's automatically. There is no import
  or export step to remember.

One consequence to know about: jj keeps git's index in sync with the working-copy commit
`@`, so `git status` reads differently than it used to — changes show up as staged. Use
`jj st`.

`.jj/` is self-ignoring (it contains its own `.gitignore` with `/*`), so it never appears
in `git status` and is never copied into a flake build.

### First-time setup: track `main`

Do this once per clone, before anything else:

```bash
jj bookmark track main --remote=origin
```

Without it `jj git fetch` updates `main@origin` but leaves the local `main` bookmark
where it is, so `jj new main` silently builds on a stale trunk. jj tracks the default
bookmark automatically on `jj git clone`, but **not** when a repo is colocated into an
existing git checkout with `jj git init --colocate` — which is how this one came to be.

The tell is in the fetch output:

```
bookmark: main@origin   [updated] untracked
```

`untracked` there means `main` will not follow. (`main@origin` as an argument is
deprecated syntax at 0.41; use `--remote=origin`.)

### New files: the one thing that still needs a deliberate step

Nix refuses to read files a git repository does not track:

```
error: Path 'modules/foo.nix' in the repository "…" is not tracked by Git.
```

Under git the fix was `git add`. Under jj there is no `add` — but the fix is not *nothing*
either. jj snapshots the working copy into `@` (and exports that to git's index, which is
what Nix reads) **when a jj command runs**, not when the file appears on disk. So a file
created and then immediately passed to `nix eval`, `nix build` or `clan machines update`
is still invisible.

Running any jj command first is enough:

```bash
jj st                       # snapshots; the new file shows as `A`
clan machines update miralda
```

This bites exactly where it costs most — a new module under `modules/` or `machines/` — and
the error names git, not jj, which sends you looking in the wrong place. Confirmed
behaviour, not theory: verified against `nix eval …miralda…toplevel.drvPath` while
preparing this migration.

---

## Why jj for this repo specifically

This repo's workflow is branch-per-change with mandatory PRs and a high rate of small docs
and config commits. The stumbles it produced were consistently *git-shaped* rather than
substance-shaped:

- a `--delete-branch` that pulled a branch out from under an in-flight edit, leaving an
  amend landing on `main`;
- rebase conflicts between two PRs touching adjacent rows of the same table;
- repeated `commit --amend` + `push --force-with-lease` cycles just to keep one PR tidy.

jj's model removes the class rather than the instances. There is no index and no detached
HEAD; the working copy is already a commit, so there is nothing to stage and nothing to
amend; history rewriting is ordinary rather than dangerous; and `jj undo` makes every
operation reversible.

Three hazards stop existing outright:

- **"Accidentally committed on `main`."** Nothing is ever *on* a bookmark in jj. `main`
  moves only when you move it. jj's default `immutable_heads()` revset resolves through
  `trunk()` to `main@origin`, so jj mechanically refuses to rewrite anything that has
  already landed — the CLAUDE.md invariant becomes enforced, not merely stated.
- **`git add -A` sweeping up unrelated work.** There is no index to over-stage.
- **Baking a token into `.git/config` via `git push -u`.** jj bookmarks carry no per-branch
  `remote`/`merge` configuration, so there is nothing to bake a token into.

---

## Translation table

| git | jj |
|---|---|
| `git fetch origin && git switch main && git merge --ff-only origin/main` | `jj git fetch` — a tracked `main` advances on its own |
| `git switch -c docs/foo` | `jj new main -m "<message>"` — the name can wait |
| `git add <files> && git commit -m …` | nothing; edits are snapshotted into `@`. `jj describe -m …` sets the message |
| `git commit --amend` | nothing; editing the files *is* amending `@` |
| `git status` / `git diff` | `jj st` / `jj diff` |
| name the branch | `jj bookmark set docs/foo -r @` |
| `push origin docs/foo` | `jj git push --bookmark docs/foo` |
| `commit --amend` + `push --force-with-lease` | `jj bookmark set docs/foo -r @` + `jj git push --bookmark docs/foo` — identical to the first push |
| `git rebase main` | `jj rebase -d main` |
| `git log --oneline` | `jj log` |
| `gh pr checkout <n>` | `jj git fetch && jj new <branch>@origin` |
| after merge: `git switch main && git merge --ff-only && git branch -d <branch>` | `jj git fetch && jj bookmark forget <branch>` |
| `git reflog` surgery | `jj undo`, or `jj op log` + `jj op restore <op>` |
| splitting a commit | `jj split`, `jj squash --into <rev>`, `jj absorb` |
| `git revert <sha>` | `jj backout -r <rev>` |

---

## The PR loop

```bash
jj git fetch
jj new main -m "Add the thing"          # create the change

# …edit files. No add, no commit. `jj st` shows what is in @.

jj bookmark set feat/the-thing -r @     # name it
jj git push --bookmark feat/the-thing   # --bookmark starts tracking a new one
gh pr create                            # title imperative, ≤70 chars, unprefixed
```

Review feedback:

```bash
# …edit files again — this amends @ in place.
jj bookmark set feat/the-thing -r @
jj git push --bookmark feat/the-thing   # exactly the same command as before
```

The push command is the same every time. `--bookmark` starts tracking a bookmark the remote
has not seen, so there is no separate "first push" form — `--allow-new` existed for that and
is deprecated as of jj 0.41.

And there is no `--force-with-lease` to get right or wrong: jj updates the remote only if
its current state still matches what jj last fetched, which is what `--force-with-lease`
was for.

After the PR is squash-merged and the remote branch deleted:

```bash
jj git fetch
jj bookmark forget feat/the-thing
```

### Credentials

jj performs remote operations by spawning a real `git` subprocess, so `jj git push` picks
up the gh credential helper that `programs.gh` writes into `~/.config/git/config`. Nothing
extra is needed, and the devShell's `push` helper has no jj counterpart because it does not
need one — see the comment in `scripts/devshell.sh`.

### Signing

jj does not inherit git's `commit.gpgsign`; it signs only when `signing.behavior` asks it
to, and this repo leaves that at its default of not signing. This matches
`programs.git.signing.signByDefault = false` in `modules/users/lgo.nix`, so nothing here
needs the `--no-gpg-sign` that git commits used to.

### Auto-snapshot sweeps in other people's edits

This is the sharp edge of the model, and the one thing that is genuinely *more* dangerous
than its git equivalent.

jj snapshots the entire working copy into `@`. Not the files you edited — all of them. So
if anything else changes the tree while you are working (you in another window, someone
else on the machine, a tool writing a config), that change silently becomes part of your
revision and gets pushed with it. There is no `git add` to scope, and therefore no moment
at which you were asked.

Under git this hazard required you to type `git add -A`. Under jj it requires you to type
nothing. The mitigation is correspondingly different: **read `jj st` immediately before
`jj bookmark set`**, and treat any path you did not touch yourself as a stop sign.

To eject a file that already made it into a change:

```bash
jj restore --from main@origin --into <bookmark> <path>
jj git push --bookmark <bookmark>
```

`jj restore --into` rewrites the *revision*; it does not touch the working copy, so the
other person's edit stays on disk where they left it. That is exactly what you want — you
are removing it from your change, not undoing their work.

(This happened while this very guide was being written: a concurrent edit to
`machines/miralda/configuration.nix` was swept into the migration branch and pushed. The
recipe above is what removed it.)

---

## Deploying from a PR branch

Replaces `gh pr checkout <n>`:

```bash
jj git fetch
jj new <branch>@origin        # working copy now matches that branch
clan machines update <machine>
```

`jj new` puts an empty change on top of the branch, so the files on disk are exactly the
branch's. To go back, `jj edit <change-id>` (find it with `jj log`) or
`jj abandon && jj new main`.

**This does not soften the deploy hazard.** `clan machines update` applies the *whole*
configuration present in the working directory, not a diff — so two open PRs against one
machine still means the second deploy silently reverts the first. Verify with a drift check
against `readlink /run/current-system` after merging, exactly as before.

---

## Things that behave differently because the repo is colocated

**`gh pr merge --delete-branch` fails.** jj leaves git's `HEAD` detached, so gh cannot
work out which branch you are on and aborts with `could not determine current branch:
failed to run git: not on any branch` — *after* it has already merged the PR. Merge and
delete as two steps:

```bash
gh pr merge <n> --squash
gh api -X DELETE repos/lutzgo/clanarchy/git/refs/heads/<branch>
```

**`gh pr merge` does not fetch.** Unchanged from the git era: run `jj git fetch`
afterwards, and check that `main` actually moved before building on it.

**`jj bookmark set` refuses to move a bookmark sideways.** If you rebuild a branch on a
fresh base — rather than adding to it — jj stops with `Refusing to move bookmark backwards
or sideways`. That is the guard working; when the replacement is deliberate, say so:

```bash
jj bookmark set --allow-backwards <bookmark> -r @
```

---

## Configuration

`~/.config/jj/config.toml` is declared by `programs.jujutsu` in `modules/users/lgo.nix`,
alongside `programs.git`, for the same reason: `~/.config` is an impermanence bind mount,
and the two identities must match or a change picks up a different author name depending on
which tool wrote it.

That makes the file a read-only `/nix/store` symlink, so `jj config set --user` will fail —
exactly as `git config --global` already does. Change it in `modules/users/lgo.nix` and
redeploy.

**Removing it before a deploy is a one-time step, and only for a real file.** On a machine
that still has a hand-written `~/.config/jj/config.toml`, home-manager refuses to clobber
it and the failure takes the whole `lgo` activation with it — so it has to go first. But
once home-manager owns the path it is a symlink, and deleting *that* and redeploying leaves
you with **no config at all**: home-manager only re-links when the generation changes, and
a redeploy of the same generation is a no-op. Check before you remove:

```bash
[ -L ~/.config/jj/config.toml ] && echo "managed — leave it alone" || rm -f ~/.config/jj/config.toml
```

If you have already deleted the symlink, the cheapest fix is to recreate it by hand
pointing at the live generation (`readlink ~/.config/git/config` shows which
`home-manager-files` path that is); the next real config change re-links it properly.

The declared set is deliberately minimal. Before adding a key, check it against
`jj config list --include-defaults`: a misspelled key is a silent no-op in jj, but the
home-manager module will serialise it happily. In particular
`revset-aliases."immutable_heads()"` is **not** set — the builtin default already covers
`main@origin`, and redefining it could only weaken the protection described above.

---

## Recovery

**Undo the last thing jj did**, whatever it was:

```bash
jj undo
```

**Go further back.** Every jj operation is recorded, including working-copy snapshots:

```bash
jj op log
jj op restore <operation-id>
```

This is the general safety net. It covers the cases that used to need `git reflog`, and it
covers them for operations git does not record at all, such as an abandoned change.

**Reverting something already merged** — still via a PR, never by force-pushing `main`:

```bash
jj git fetch
jj new main -m "Revert PR #<n>: <reason>"
jj backout -r <merged-rev>
jj squash                                # fold the backout into @
jj bookmark set fix/revert-pr-<n> -r @
jj git push --bookmark fix/revert-pr-<n>
gh pr create --title "Revert PR #<n>"
```

**"My local `main` diverged."** This does not arise. `main` is a bookmark that moves when
you move it or when `jj git fetch` advances it; there is no notion of being checked out on
it, so nothing accumulates there by accident. If `main` somehow does point somewhere
unexpected, `jj bookmark set main -r main@origin` puts it back.

---

## The shell prompt

jj keeps git's `HEAD` **detached** — it points at the parent of the working-copy revision,
never at a branch. So starship's builtin `git_branch` renders the literal string `HEAD` in
every shell inside a jj repo: accurate about git, useless to read.

`modules/desktop/noctalia-hm.nix` replaces it with two starship `custom` modules, selected
by `jj root` rather than by a folder test so they work in subdirectories too:

- inside a jj repo, the bookmark on `@` if it has one (`feat/the-thing`), otherwise
  `<parent bookmark>~<change id>` (`main~sksuvx`) — the usual state right after `jj new main`;
- anywhere else, the builtin `git_branch`, re-rendered through `starship module` so it keeps
  its own symbol, truncation and powerline caps.

Both jj calls pass `--ignore-working-copy`, which is load-bearing rather than an
optimisation: without it jj snapshots the working copy on every prompt render, so *drawing
a prompt would mutate the repo*.

## TUI

`lazyjj` is installed for lgo and bound to `Space+G` in Helix and `g` in Yazi — the slots
lazygit used to hold. `lazygit` is still installed and still works against the colocated
`.git`; it is simply no longer bound, and shows git's view rather than jj's.
