# Adding a module or an option

How a new feature gets into clanarchy: where the code goes, what shape it takes, how it
reaches a machine, and what to check before it lands.

For adding a whole *machine*, see [adding a machine](adding-a-machine.md). For the
branch-and-PR mechanics, see [the jj workflow](jj-workflow.md).

---

## 1. Decide where it goes

Three places, and the choice is about **how a machine opts in**, not about size.

| Where | Use when | How a machine gets it |
|-------|----------|-----------------------|
| `modules/<topic>.nix` + `commonBase` / `commonHeadful` | Every machine could plausibly want it, and it costs nothing when off | Imported fleet-wide in `lib/mk-machine.nix`; **inert** until the machine sets its option |
| `modules/<topic>.nix` + a machine's import list | It only ever applies to one or two named machines | Listed explicitly in that machine's `clan.machines.<name>` block in `flake.nix` |
| `service-modules/<name>.nix` | Assignment is a **role** — different machines take different parts of the same feature | Registered in `clan.nix` as `@clanarchy/<name>`, assigned per machine in `inventory.instances` |

**Default to the first.** It is the dominant pattern in this repo and the one that scales:
`modules/hardware/convertible.nix`, `modules/hardware/zsa.nix`,
`modules/nix-remote-builder.nix` and `modules/immich-upload.nix` are all imported by every
machine and do nothing at all until one opts in. That keeps `flake.nix` from growing a line
per machine per feature, and it means enabling the feature later is a one-line change in
one file.

Reach for `service-modules/` only when the feature genuinely has **roles** — the way
`@clanarchy/monitoring` has a `client` on every machine and a `server` on ernst, or
`@clanarchy/machine-type` dispatches `laptop` / `server` / `htpc`. A clan service is
heavier: a `_class`, a manifest, a readme, and an inventory instance. If the answer to
"which role?" is always "the only one", it should not be a clan service.

---

## 2. Write the module

The house shape, in full — `modules/apps/emulation.nix` and
`modules/hardware/convertible.nix` are the short and long worked examples:

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.clanarchy.backup;
in
{
  options.clanarchy.backup = {
    enable = lib.mkEnableOption "nightly restic backup of /persist";

    repository = lib.mkOption {
      type = lib.types.str;
      description = "restic repository URL.";
      example = "s3:https://…";
    };
  };

  config = lib.mkIf cfg.enable {
    # …
  };
}
```

Three rules that are not negotiable, because fleet-wide import depends on them:

1. **Namespace everything under `clanarchy.`.** That is what `gendocs` walks (step 5) and
   what keeps the repo's options separable from nixpkgs'.
2. **Guard the entire `config` body on the option** with `lib.mkIf cfg.enable`. A module
   imported by five machines that does anything unconditionally is a module that changes
   five machines.
3. **Default to off.** `mkEnableOption` already does; do not add a `default = true` to save
   a line somewhere.

Write the header comment for the reader who will want to undo your decision. The modules in
this repo explain *why* — `modules/apps/emulation.nix` explains why Switch emulation is its
own flag rather than part of a blanket one, and that paragraph is the reason nobody merges
them back together by accident.

---

## 3. Wire it up

Fleet-wide, in `lib/mk-machine.nix` — `commonBase` for every machine, `commonHeadful` for
workstations only (it adds stylix, display, apps; ernst uses `commonBase`):

```nix
  commonBase = [
    # …
    # Nightly restic backups. Declares `clanarchy.backup` and guards its body
    # on it, so importing it fleet-wide is inert until a machine opts in.
    ../modules/backup.nix
  ];
```

Machine-specific instead, in `flake.nix`:

```nix
  clan.machines.ernst = {
    imports = [ (mkModuleArgs { }) ] ++ commonBase ++ [
      ./modules/backup.nix
    ];
  };
```

Then turn it on in `machines/<name>/configuration.nix`:

```nix
  clanarchy.backup = {
    enable = true;
    repository = "…";
  };
```

!!! warning "The new file is invisible to Nix until jj snapshots it"
    `modules/backup.nix` is a **new** file, and Nix cannot read a path git does not track.
    jj snapshots the working copy when a jj command *runs*, not when the file appears — so
    run `jj st` before the first `nix eval`, or it fails with
    `Path 'modules/backup.nix' in the repository … is not tracked by Git`, naming git
    rather than jj. This is the one thing `git add` used to cover that jj does not cover
    for free. See [the jj workflow guide](jj-workflow.md).

---

## 4. Secrets: a clan var, not a file

If the feature needs a credential, declare a generator rather than reading a path:

```nix
  clan.core.vars.generators.backup-password = {
    files.password.secret = true;
    prompts.password = {
      description = "restic repository password — must NOT be blank";
      type = "hidden";
    };
  };
```

Two things that have taken services down in this repo:

- **A blank prompt is not an "optional credential".** Blank stores nothing, `.path`
  evaluates to the literal `/no-such-path`, and every later deploy re-prompts — which is
  fatal in any context without a TTY.
- **Clan var paths do not exist inside nspawn containers.** Never point an in-container
  unit at `/run/secrets/vars/…`; stage host-side into `/run/<svc>-secrets` and bind-mount.
  The failure is a silent `243/CREDENTIALS`.

Generators run for **every machine in the flake** on any `clan machines update`, so an
unanswered prompt anywhere blocks every deploy. Run `clan vars generate <machine>` at a
real terminal first.

---

## 5. Regenerate the option reference

```bash
gendocs      # devShell function → python3 scripts/gen-options.py
```

This writes `docs/reference/*.md` from the live evaluated options. CI regenerates it on
push to `main` too (`.github/workflows/gendocs.yml`), so a missed run is not fatal — but
two things in that script fail **silently**, and both will simply leave your option out of
the published reference with no error:

- **`PAGES` maps option prefixes to pages.** A new top-level prefix — `clanarchy.backup.` —
  matches nothing and is dropped. Add it to an existing page's `prefixes` list, or add a
  page. (`clanarchy.immich.` was folded onto the apps page for exactly this reason, and
  the script carries a comment explaining why rather than a silent mismatch.)
- **Only `miralda` and `biene` are evaluated** (`fetch_options()`). An option that exists
  only on ernst, birte or jens never appears. If your module is not in `commonBase` or
  `commonHeadful`, check that one of those two machines imports it.

Then update the module table in `CLAUDE.md` by hand — "Shared Module Layout" for
`modules/`, "Service Modules" for `service-modules/`. That table is prose, not generated,
and it is what a future session reads first.

---

## 6. Verify before it lands

```bash
jj st                                    # ONLY your files — jj snapshots the whole tree
nix eval --no-update-lock-file --raw \
  '.#nixosConfigurations.miralda.config.system.build.toplevel.drvPath'
```

Evaluate **every machine your module is imported by** — for anything in `commonBase` that
is all five. CI does this on the PR (`.github/workflows/check.yml`), but locally it is
seconds and catches the whole class of error that reaches a PR here: missing options,
renamed attributes, type mismatches, broken wiring.

Then deploy it to one machine before merging. There is no stage-only mode — `clan machines
update` activates — so for anything that could cost you the machine (bootloader, disko,
impermanence) have console or [remote unlock](remote-unlock.md) access to hand first.

```bash
clan machines update <machine>
```

A clean `nix eval` proves less than it looks for some changes. Two known cases: an nspawn
container name over 12 characters evaluates fine and fails at container *start* (`vb-<name>`
hits `IFNAMSIZ`), and a uid colliding with a static one in nixpkgs' `ids.nix` is an option
conflict rather than an eval error. Check `systemctl --failed` on the target after
deploying — and for containers, inside each container too, since the host's view is clean
either way.

---

## 7. Open the PR

`feat/` for a new module or option, `chore/` for a refactor with no behaviour change. The
[jj workflow](jj-workflow.md) has the mechanics; the
[review checklist](accepting-pull-requests.md) is what it will be judged against.

Include in the body what the module's header comment cannot: what you measured, and what
you decided against.
