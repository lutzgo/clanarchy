# Working in clanarchy

Conventions for anyone — person or coding agent — making a change here. Read
this first; it is deliberately short. `CLAUDE.md` points at this file, and
OpenCode reads it directly.

**Clanarchy** is a NixOS configuration built on [clan-core](https://clan.lol),
managing five machines: `miralda` and `jens` (lgo's laptops, Niri), `biene`
(Sabine's laptop, labwc), `birte` (Steam Deck, Jovian), `ernst` (homelab server
— NAS, VM host, GPU compute, ~20 containerised services).

Per-machine layout: [docs/architecture/machines.md](docs/architecture/machines.md).
Shared modules and clan services: [docs/architecture/modules.md](docs/architecture/modules.md).
Decisions that bite if you don't know them: [docs/architecture/decisions.md](docs/architecture/decisions.md).

---

## 1. The one gate

```bash
check                 # every machine; or: check miralda jens
```

`check` is a devShell function (`scripts/check.sh`). It evaluates each machine's
toplevel and prints one line each. CI runs the same script.

**A pass proves the configuration evaluates — not that the system works.** Two
known cases pass here and fail on the machine: an nspawn container name over 12
characters (`vb-<name>` hits IFNAMSIZ, fails at container *start*), and a uid
colliding with a static one in nixpkgs' `ids.nix` (an option conflict, not an
eval error). After any deploy, check `systemctl --failed` on the host **and
inside each container** — the host's view is clean either way.

Enter the devShell with direnv, or `nix develop`. It also provides `push`,
`gendocs`, `docs serve`.

## 2. Deployment is the clan CLI

```bash
clan machines update <machine>      # miralda | jens | biene | birte | ernst
clan vars generate <machine>        # (re)generate secrets, then update
```

**Do not add a wrapper, in any form, including a thin alias.** `deploy`,
`deploy-<machine>`, `test-pr` and `test-vm` were removed in #59 because they
drove `nixos-rebuild` directly and so skipped clan's inventory evaluation —
meaning they could not apply secrets or vars. See
[docs/guides/deploy.md](docs/guides/deploy.md).

There is no stage-for-next-boot mode: `clan machines update` runs
`switch-to-configuration boot` *and* `switch`. It needs a **TTY** — a pending
vars prompt kills it with `termios.error` when run from a tool, and generators
run for *every* machine, so an unrelated pending prompt blocks any target.

With `nixos-rebuild` (local recovery only) always use `--no-reexec`, never
`--fast`, and never `--build-host localhost`.

## 3. Version control is jj, not git

`.jj/` and `.git/` sit side by side; `.git` stays authoritative, so `gh`, CI and
clan are unaffected. **Do not mix the two inside one session** — that is where
the confusion comes from. Full reference, including recovery:
[docs/guides/jj-workflow.md](docs/guides/jj-workflow.md).

**Never land a change directly on `main`.** Even a one-line docs edit gets its
own bookmark and its own PR. One change → one bookmark → one PR.

```bash
jj git fetch                                   # tracked main advances on its own
jj new main -m "<message>"                     # create the change
# …edit. There is no `git add` and no `git commit`: editing again *is* amending.
jj st                                          # READ THIS before the next line
jj bookmark set <type>/<slug> -r @
jj git push --bookmark <type>/<slug>           # same command first time and after
gh pr create --head <type>/<slug>              # --head: jj leaves HEAD detached
```

| Prefix | For |
|--------|-----|
| `feat/`  | New user-visible feature or module |
| `fix/`   | Bug fix |
| `docs/`  | Docs, guides, README |
| `chore/` | Tooling, deps, flake bumps, refactors with no behaviour change |
| `vars/`  | Clan-vars regeneration only |
| `wip/`   | Exploratory work not ready for review |

Two traps, both of which have cost real time:

- **A new file is invisible to Nix until jj snapshots it.** jj snapshots when a
  jj command runs, not when the file appears, and Nix cannot read a path git
  does not track — it fails with `… is not tracked by Git`, naming *git* rather
  than jj. `check` runs `jj status` first for this reason.
- **Auto-snapshot sweeps in other people's edits.** jj snapshots the *whole*
  working copy into `@`, so an unrelated change made in another window is
  included with no command at all. Read `jj st` immediately before
  `jj bookmark set` and treat any file you did not touch as a stop sign. Eject
  one with `jj restore --from main@origin --into <bookmark> <path>`.

Merging (yours to run, not an agent's):
`gh pr merge <n> --squash`, then delete the remote ref separately —
**not** `--delete-branch`, which needs a checked-out git branch and so fails
*after* the merge has gone through. See
[docs/guides/accepting-pull-requests.md](docs/guides/accepting-pull-requests.md).

## 4. Where a new feature goes

The choice is about **how a machine opts in**, not about size. Full guide:
[docs/guides/adding-a-module.md](docs/guides/adding-a-module.md).

| Where | Use when | How a machine gets it |
|---|---|---|
| `modules/<topic>.nix` + `commonBase`/`commonHeadful` | Every machine could plausibly want it, and it costs nothing when off | Imported fleet-wide in `lib/mk-machine.nix`; **inert** until the machine sets its option |
| `modules/<topic>.nix` + one machine's import list | It only applies to one or two named machines | Listed in that machine's `clan.machines.<name>` block in `flake.nix` |
| `service-modules/<name>.nix` | Assignment is a **role** — different machines take different parts | Registered in `clan.nix` as `@clanarchy/<name>`, assigned in `inventory.instances` |

**Default to the first.** Reach for a clan service only when the feature really
has roles; if the answer to "which role?" is always "the only one", it should not
be one.

Namespace options under `clanarchy.`, guard the whole `config` body with
`lib.mkIf cfg.enable`, and default to off.

## 5. Secrets are clan vars

Declare a generator; never read a path. Three failures that have taken services
down here:

- **A blank prompt is not an "optional credential".** Blank stores nothing,
  `.path` becomes the literal `/no-such-path`, and every later deploy re-prompts
  — fatal without a TTY.
- **Clan var paths do not exist inside nspawn containers.** Never point an
  in-container unit at `/run/secrets/vars/…`; stage host-side into
  `/run/<svc>-secrets` and bind-mount. The failure is a silent `243/CREDENTIALS`.
- **`clan vars generate` commits as a jj *sibling*.** After running it:
  `jj diff --from main --to @ --stat -- vars/` — non-empty? — then get it onto
  `main` in a `vars/`-prefixed PR. Both halves. A secret that stays in a working
  copy is a secret a `jj new main` silently discards.

Renaming a generator, or a file inside one, **regenerates the secret or re-fires
its prompt**. Don't, cosmetically.

## 6. How to write a change

1. **Build the thing that was asked for, first.** Splitting a milestone is fine;
   shipping the scaffolding and then drifting is not. A milestone is finished
   when the person can do the thing they asked for, not when its infrastructure
   is green. Say plainly when the requested capability is not yet delivered.
2. **One deploy per *round* of findings, not one per finding.** Verify
   everything before reporting — a failing check is a reason to keep looking,
   not to stop. Batch every defect found in one pass into one fix PR. Only ask
   for a deploy when nothing further can be learned without one.
3. **"This known trap does not apply here" must be measured.** Grep for the
   pattern you claim is absent; read the upstream module's *code*, not its
   documentation; run a two-arm control when two consumers might differ. If it
   cannot be measured before deploying, write it as a prediction *with the
   symptom to look for*, not as a settled fact.
4. **Verify against the real system before asking for a deploy.** `nix eval`
   proves the configuration builds and nothing else. Run the code against the
   live system, exercise guards by breaking the config deliberately and
   confirming the drv hash returns unchanged, and run the package's own tests
   (`nix build .#checks.x86_64-linux.mneme`).
5. **Match the register to the evidence.** *Measured* — say "MEASURED on
   <host> <date>:" and give the command and its output. *Reasoned* — say "this
   is reasoned, not measured" plus the symptom if wrong. *Unverified* — say so
   in the session summary, not only in a comment.
6. **Comments carry invariants, not history.** One or two lines where changing
   the line breaks something. Incident narrative belongs in
   `docs/incidents/`; rejected alternatives belong in the PR body. If a
   sentence would be true in more than one file, it belongs in the shared module
   those files call.
7. **Do not echo the household's data back.** The archive here holds medical
   letters, contracts and bills. When a verification step prints document
   content, redact it — quote lengths, field names and structure instead.

## Checklist before asking for a deploy

- [ ] The requested capability is in this change, or its absence is stated
- [ ] Every defect from the last verification round is in this change
- [ ] `check` passes
- [ ] Package tests pass, and new silent-failure behaviour has a test
- [ ] The real code ran against the real system where that was possible
- [ ] Every "does not apply here" claim has an observation behind it
- [ ] `vars/` changes are committed and heading for `main`
- [ ] The manual steps are listed in order, with the ones that gate the deploy
      marked
