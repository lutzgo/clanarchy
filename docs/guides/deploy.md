# Deploying and testing

The devShell (from `nix develop` or via `direnv allow`) exposes one function per machine plus a couple of test helpers. All of them shell out to `nixos-rebuild` or `gh` — nothing magical, just less to type.

## Per-machine deploy functions

| Function | Target host | Env override |
|----------|-------------|--------------|
| `deploy` | `root@miralda.goclan.org` | (none) |
| `deploy-biene` | `root@biene.local` | `BIENE_HOST=` |
| `deploy-birte` | `root@birte.local` | `BIRTE_HOST=` |
| `deploy-ernst` | `root@ernst.skynet.lan` | `ERNST_HOST=` |

All four take an optional `boot` or `switch` argument (default: `switch`):

```bash
deploy              # miralda — nixos-rebuild switch, activates immediately
deploy boot         # miralda — stage into the next boot entry, don't switch
deploy-biene boot   # biene   — same, over SSH
BIENE_HOST=biene.skynet.lan deploy-biene    # override target host at the shell
```

Any extra arguments after the action are forwarded to `nixos-rebuild`, so `deploy switch --show-trace` works.

Under the hood every deploy runs with `--no-reexec -j auto`. Do not use `--fast` or `--build-host localhost` — those bypass sandboxing in ways that have burned this repo before.

## `deploy` vs. `clan machines update`

`deploy` builds the closure locally, pushes it, and activates. It skips the full clan inventory evaluation, which is what makes it fast. If you have changed **`sops` recipients**, a **clan var generator**, or anything the inventory needs to re-eval, run:

```bash
clan machines update <machine>
```

instead — that walks the full clan-core code path and re-evaluates vars/secrets. Otherwise stick with the plain deploy function.

## Testing a PR in a VM

`test-pr` checks out a PR, builds the VM variant, and boots it in QEMU. The reviewer's branch is left on the PR HEAD (they can `gh pr checkout` to switch to it locally).

```bash
test-pr <PR#>                   # defaults to biene
test-pr <PR#> miralda           # or any machine
test-vm                         # build+run VM for the current tree (defaults to biene)
test-vm ernst                   # ernst VM smoke test (no GUI)
```

The VM configuration lives in `modules/vm-variant.nix` — it overlays a QEMU-friendly disk setup on top of each machine's real disko config.

The VM image is written into `./result` (Nix build output). Delete `<machine>.qcow2` in the repo root between runs if you want a fresh disk.

## Pushing with `push`

`git push` requires a writable `~/.config/git`. On this repo's `miralda`, that path is a read-only impermanence bind mount, so the credential helper never fires. The `push` function reads `gh auth token` at runtime and inlines the token into the HTTPS remote URL:

```bash
push                    # git push origin main
push origin my-branch   # git push origin my-branch
```

First-time setup on a new machine (once, persisted by impermanence):

```bash
gh auth login
```

`gh pr create`, `gh issue`, etc. work directly — they don't need this workaround.

## Regenerating option docs

```bash
gendocs                 # writes docs/reference/*.md from live NixOS config
properdocs serve        # local preview at http://localhost:8000
```

The `docs/reference/*.md` pages are committed to git; run `gendocs` after adding a new `clanarchy.*` option so the reference table stays in sync.
