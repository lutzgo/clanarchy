# Formatting

The formatter is [alejandra](https://github.com/kamadorueda/alejandra). It is
declared in `flake.nix` as `formatter`, so `nix fmt` works, and the devShell
wraps it as `fmt` and `fmt-check`.

```
fmt-check                    # what would change, repo-wide. Safe any time.
fmt modules/containers/      # format one path
nix fmt                      # the whole tree — read the next section first
```

## The repo is not formatted yet, and that is deliberate

Declaring a formatter is safe. Running it over all 160 `.nix` files is a change
that must not be mixed with anything else, for two reasons.

**It would make bisection useless for a while.** A commit that touches every
file sits in the history forever. If a deploy goes wrong a week later,
`jj diff` against the last good generation has to be read through a reformat of
the entire tree. So the repo-wide pass waits until the current work is deployed
and verified — not because formatting is risky to run, but because of when its
diff would be in the way.

**It is not provably safe the way a comment change is.** Nix ignores whitespace
between tokens, so reformatting cannot change what evaluates — *except inside
indented strings*. `''…''` strips the common leading indentation of its lines,
so if a formatter re-indents a block unevenly, the stripped result changes. This
repo has a great many embedded shell scripts, config-file heredocs and YAML
fragments inside `''…''`, and three separate times in M2 a change that "could
not possibly reach the derivation" did exactly that:

- a `#` comment inside a microvm's nftables ruleset,
- a `#` inside a `script = ''…''` in home-assistant.nix,
- a path in a `cat > "$out" <<EOF` heredoc that writes janitorr's YAML.

## So the repo-wide pass has a gate

Run it on its own branch, then prove it changed nothing:

```
alejandra .
for m in miralda jens biene birte ernst; do
  nix eval --raw ".#nixosConfigurations.$m.config.system.build.toplevel.drvPath"
done
```

Every one of the five hashes must be **identical** to `main`'s. If any moved,
find out why before merging — `nix-diff` on the two toplevels names the leaf
derivation that differs, which is how the janitorr heredoc was found:

```
nix shell nixpkgs#nix-diff -c nix-diff <main-drv> <branch-drv>
```

A moved hash is not automatically wrong — it means a string's content changed,
and you have to look at which one and decide. It is never something to wave
through.

## After that pass

Add `alejandra --check .` to `scripts/check.sh` and to CI in the same commit as
the reformat. Adding it earlier would just fail on a tree nobody has formatted
yet.
