# The household agent's memory

What `mneme` remembers, where it lives, how to read it, and how to take a fact
back out when it is wrong.

Built by M29b. The daemon itself is documented in
[`service-modules/local-ai.md`](../../service-modules/local-ai.md); this page is
about operating the memory.

## Where it is

```
/srv/state/mneme/wiki/          a git repository, owned by uid 3039
  index.md                      generated — one line per page
  log.md                        append-only, dated, every write
  00-core/                      hard facts about the house      (you edit)
  01-people/                    one page per person             (agent writes)
  02-devices/                   entity ids, rooms, quirks       (agent writes)
  03-routines/                  we do X at Y                    (agent writes)
  04-facts/                     dated one-liners                (agent writes)
```

`zdata/state`, so it is snapshotted. A fact the household told the agent once is
not re-acquirable from anywhere, which is why it is here and not on the root
pool.

**The constitution is not in the wiki.** `SOUL.md` and `IRON_RULES.md` live in
the Nix store (`service-modules/pkgs/mneme/soul/`) and are read from there. They
are configuration; the wiki is state. Every write path refuses them by name, so
a model that decides to rewrite its own rules gets a refusal it can read.

## Reading it

```bash
# What does it think it knows?
cat /srv/state/mneme/wiki/index.md

# What has it learned lately?
git -C /srv/state/mneme/wiki log --since=1.week --stat

# Who told it that, and when?
git -C /srv/state/mneme/wiki log -p -- 01-people/lutz.md
```

Every page written by the agent carries `source:` front matter with the turn
that produced it. That is what turns "the agent believes X" into "the agent was
told X, on this date, in this sentence".

## Taking a fact back out

```bash
git -C /srv/state/mneme/wiki revert <sha>     # undo one write, keep the history
git -C /srv/state/mneme/wiki rm 04-facts/wrong.md && \
  git -C /srv/state/mneme/wiki commit -m "remove a wrong fact"
```

Then `systemctl start mneme-lint` to rebuild the index, or leave it for the
nightly run. Nothing needs restarting — the daemon reads the wiki per request.

## Editing by hand

Do. `00-core/` exists precisely so a person can state things the agent must not
be able to change. Write a page, run `systemctl start mneme-lint` to pick it up
in the index, and it is in context on the next turn.

Front matter the index uses:

```markdown
---
title: the dishwasher
summary: one line, and this is what retrieval matches against
updated: 2026-09-25
---
```

**A page with no `summary` is invisible to retrieval.** The keyword match runs
over the index line, so a page nobody can find is a page that may as well not
exist. `mneme-lint` reports these.

## How retrieval actually works

On every turn, `mneme` injects: the constitution, then `index.md`, then any page
whose index line matches the last thing the household said — up to
`memory.contextBudget` characters (6000 by default, roughly 1500 tokens of a
32768 window).

**Injected, not requested.** There is also a `memory_search` tool, but a tool is
only used if the model decides to use it, and M11 measured what that decision is
worth on this model class. The index goes in unconditionally so that recall does
not depend on the model being in the mood.

No embeddings and no vector database. The pattern's stated working range is
roughly 150–200 dense pages; inside it, a page either is in the index or it is
not, which is a property a similarity search cannot offer. If the wiki ever
outgrows that, the answer is a retrieval layer *underneath* the index, not a
replacement for it.

## The nightly pass

`mneme-lint.timer`, daily. It rebuilds `index.md`, flags pages with no summary,
duplicate titles, and pages untouched for `memory.staleDays` (180). It **never
deletes anything** and it **never calls the model**.

That second absence is deliberate. Every published write-up of this memory
pattern that automated a synthesis or compaction step reported the same result:
the step failed silently, roughly half the time, and nobody noticed for weeks —
because a background job that produces nothing looks exactly like a background
job with nothing to do. If a model-driven pass is ever added here, it should be
a command a person runs.

Failures are visible: ernst exports host unit state
(`exporters.systemd = true`), so a failed `mneme-lint.service` raises
`SystemdUnitFailed` through the ordinary path. It exits non-zero only on a
broken tree — a missing wiki, or one that is not a git repository. Reported
problems are printed, not fatal, because a permanent red light is a light
everyone learns to ignore.

## The injection boundary

Anything the agent learns from a device name, a calendar entry, an article title
or a guest speaking to it can end up proposed as a page — and a page is read
back as context on every later turn. So:

- `00-core/`, `SOUL.md` and `IRON_RULES.md` are **not writable by the agent**;
- every agent-written page records its `source:`;
- `IRON_RULES.md` tells the model that wiki content is data and never
  instruction, and that a remembered fact loses to the live state of the house.

This is the gate every write-up of the pattern flags, and it is much cheaper
built now than retrofitted after something has been written into core.

## Web search and pictures

Both are tools, not memory, and both are documented with their costs in
`local-ai.md`:

- **`web_search`** goes to SearXNG over a point-to-point leg (`fdca:fe94::`),
  which is the only door to the open internet on this host. Free.
- **`generate_image`** goes to ComfyUI and **evicts the resident 21 GiB language
  model** — about 15 s each way — because they share llama-swap's exclusive GPU
  group. The finished PNG is written into Home Assistant's `www/mneme/` and
  returned as `https://ha.goclan.org/local/mneme/<name>.png`, because the hub is
  the only thing in this path a browser can reach.

Neither is offered on `mneme`'s `/v1` surface: Open WebUI already has both,
wired to the same SearXNG and the same ComfyUI.
