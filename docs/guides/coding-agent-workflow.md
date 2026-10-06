# Coding-agent workflow

Rules for Claude sessions working in this repository. They exist because the
same two failures keep happening, and both of them waste lgo's time rather than
the agent's: **deploys that could have been one**, and **comments that assert
instead of measure**.

The jj mechanics are in [the jj workflow](jj-workflow.md). This file is about
what to put *in* a change and *when to ask for a deploy* — the part that has
gone wrong repeatedly.

---

## 1. Build the thing that was asked for, first

M32 is the worked example of getting this wrong. The request was *"the local AI
should be able to read my documents and answer questions about them."* What
shipped first was a document store, and the AI half — the actual request —
arrived **nine PRs later**, after five of those PRs fixed defects in the
scaffolding.

Splitting a milestone is fine. Shipping the scaffolding and then *drifting* is
not. So:

- **Name the requested capability in the plan, and sequence it first or
  second.** Not "after the infrastructure settles".
- If a split is genuinely right, **the second half is the next change**, not the
  change after the fixes to the first half.
- A milestone is not finished when its infrastructure is green. It is finished
  when the person can do the thing they asked for.

> Say plainly, in the session, when the requested capability is not yet
> delivered. "Deployed and verified" about scaffolding reads as "done" to
> someone who asked for a feature.

---

## 2. One deploy per round of findings, not one per finding

**This is the rule that would have saved the most time.** M32 asked for six
separate `clan machines update ernst` runs, each a context switch for lgo, and
four of them were fixes for defects found by the previous one.

The repo's "one change → one bookmark → one PR" rule is about **reviewability**,
not about round-trip count. It does not mean one PR per line changed.

**During a deploy/verify cycle:**

- Verify **everything** before reporting — all the checks, not the first failure.
  A failing check is a reason to keep looking, not to stop and fix.
- **Batch every defect found in one pass into one fix PR.** Three defects found
  in one verification round is one PR, not three.
- Only ask for a deploy when there is nothing further that can be learned
  without one.

A fix PR per defect is the right shape when defects arrive *separately over
time*. It is the wrong shape when they arrive *together from one verification
pass*.

---

## 3. "This known trap does not apply here" must be measured

This repo rewards writing down *why* a hazard does not apply. That register is
earned by measurement; using it without one launders a guess into a fact that
the next reader will trust.

**Five of M32's defects were exactly such a comment.** Each sounded right:

| The comment claimed | Reality |
|---|---|
| a ULA leg needs configuring at both ends | nspawn already assigns the host end; the second definition collided |
| the module declares no tmpfiles rule for the consumption dir | it declares one, with no mode, so it rewrote only the group |
| systemd's `EnvironmentFile` keeps quotes in the value | systemd strips them; **bash's `source`** brace-expands an unquoted one |
| allauth's auth method differs from `user_oidc`'s | both send `client_secret_post` |
| `update_or_create(user=…)` rotates a DRF token | `key` is the primary key; Django INSERTs instead of updating |

**Before writing such a sentence, get an observation.** It is usually one
command:

- `grep` the repo for the pattern claimed to be absent — *"none of `mon0`,
  `ai1`, `web0` has a host-side network"* was one grep away.
- Read the upstream module's **code** for the option, not its documentation.
- Run a **two-arm control** when two consumers might differ. Bare-vs-quoted ×
  bash-vs-systemd settled the `EnvironmentFile` question in one command.
- If it cannot be measured before deploy, write it as a **prediction with the
  symptom to look for**, not as a settled fact.

---

## 4. Verify against the real system before asking for a deploy

`nix eval` proves the configuration builds. It proves nothing about whether the
thing works. The gap between those two is where every M32 defect lived.

What is available **without** a deploy, and should be used:

- **Run the code against the live system.** M32b's tools were exercised against
  the running paperless by copying two files to ernst and driving them — every
  path including 404, bad token, empty query, and out-of-range paging. That took
  minutes and replaced a deploy round-trip.
- **Read upstream's source** for the option being set. `enableLanguages` being
  derived from `PAPERLESS_OCR_LANGUAGE` by splitting on `+` was in the module,
  not in any documentation.
- **Measure the API shapes** a new consumer will depend on, with real data. The
  `created = 1983` finding changed the tool's design.
- **Exercise the guards by breaking the config deliberately**, then restore and
  confirm the drv hash is unchanged.
- **Run the package's own tests.** `pkgs/mneme` runs 37 at build time; new
  behaviour gets a test there, especially anything that fails *silently*.

---

## 5. State what is unverified, in the words of the thing not verified

Every claim lands in one of three buckets, and the register must match:

| Bucket | How to write it |
|---|---|
| Measured | *"MEASURED on ernst 2026-10-06:"* then the command and its output |
| Reasoned | *"This is reasoned, not measured"* plus the symptom if wrong |
| Unverified | Say so in the session summary, not only in a comment |

Never let a reasoned claim wear the measured register. `authelia.nix`'s
`client_secret_post` note is the model to copy — it says MEASURED and gives the
two-arm control that proves it.

---

## 6. Secrets are not done until they are on `main`

`clan vars generate` commits as a **jj sibling**, and the known hazard is "the
deploy ships the old secret". M32 found the other half: **the secret never lands
at all.** Four generators ran, deployed, and left their output uncommitted in a
working copy, where a `jj new main` would have silently discarded them.

Nothing failed, which is why it survived a whole session. The next deploy from a
clean checkout would have regenerated all four — and `paperless-admin` is a
recovery password, `paperless-secret` is Django's signing key.

**After any `clan vars generate`:**

```bash
jj diff --from main --to @ --stat -- vars/    # non-empty?
```

**and then get it onto `main`** in a `vars/`-prefixed PR. Both halves. The first
check alone is what the existing note covers and it is not sufficient.

---

## 7. Do not echo the household's data back

The archive this repo now hosts contains medical letters, contracts and bills.
When a verification step prints document content, **redact it** — the point of
the check is that the pipeline works, not what the paper says. Quote lengths,
field names and structure instead.

---

## Checklist before asking for a deploy

- [ ] The requested capability is in this change, or its absence is stated
- [ ] Every defect from the last verification round is in this change
- [ ] `nix eval` passes for the target machine **and** one control machine
- [ ] Package tests pass, and new silent-failure behaviour has a test
- [ ] The real code ran against the real system where that was possible
- [ ] Every "does not apply here" claim has an observation behind it
- [ ] `vars/` changes are committed and heading for `main`
- [ ] The manual steps are listed in order, with the ones that gate the deploy
      marked
