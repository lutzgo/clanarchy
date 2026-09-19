# The reading stack — feeds in, bookmarks kept, pages archived

Miniflux, Karakeep and Floccus (M27). This guide is the *workflow*: what each
part is for, how a link travels through them, and the decisions worth making
once rather than every time.

The infrastructure — containers, ingress, auth — is in
[the M27 section of the roadmap](../roadmap.md). This page assumes it works.

---

## The mental model, in one table

The whole thing rests on one distinction. Get this right and the rest follows.

| | What it is | Lifetime | Answers |
|---|---|---|---|
| **Miniflux** | The **intake**. A river of everything you subscribe to | **Ephemeral** — entries age out | "what's new?" |
| **Karakeep** | The **keep**. Things you decided to keep, with a copy of the page | **Permanent** — snapshotted, never auto-deleted | "where was that thing?" |
| **Floccus** | The **sync**. Your browsers' own bookmark trees, mirrored into Karakeep | Follows the browsers | "the bookmarks bar, everywhere" |

**Miniflux is not an archive and must never be used as one.** Its entries are
retained for a fixed window and then removed — that is what keeps it fast and
what keeps the database small. If you want something after next month, it goes
in Karakeep. Every workflow below is a variation on that single rule.

**Karakeep keeps a COPY, not a link.** It crawls the page, extracts the text,
takes a screenshot and stores a full-page snapshot. That is the point: a
bookmark to a dead page is a tombstone, and roughly a tenth of what you save
will be dead within a couple of years.

---

## Connecting Miniflux to Karakeep — yes, do it

Miniflux ships a first-class Karakeep integration (*Settings → Integrations →
Karakeep*). It turns "I want to keep this" from a copy-paste into one click in
the reader.

**This is the piece that makes the two services a stack rather than two tabs.**
Without it, Miniflux is a reader you read *next to* an archive. With it, triage
and keeping are one motion.

### Settings

| Field | Value |
|---|---|
| Save entries to Karakeep | ✅ |
| Karakeep API key | an API key from *Karakeep → Settings → API keys* |
| Karakeep API Endpoint | `https://karakeep.goclan.org/api/v1/bookmarks` |
| Karakeep Tags | `miniflux, new` |

**Use the public hostname, not `10.0.90.29:3000`.** Both work, and the public
name is the right answer for the same reason `containers/homepage.nix` gives
for reaching Nextcloud by name: the direct route would need a new accept rule
in `containers/karakeep.nix` and a hardcoded peer address, to save one layer-2
hop on a request that happens only when you click *Save*. `karakeep.goclan.org`
carries no forward-auth (it is an `appApiHosts` name), so the API token passes
straight through Traefik.

**Make this key its own**, distinct from the browser extensions' and the
dashboard's. They all come from the same page in Karakeep and look identical;
revoking the wrong one breaks something you will not immediately connect to the
revocation. Label it `miniflux`.

### The tags matter more than they look

Anything arriving this way is tagged `miniflux` and `new`. That gives you:

- a way to find everything that came from a feed rather than from a browser;
- a **triage queue** — `new` is a tag you remove once you have actually read
  and filed the thing, so `tag:new` is your backlog and its size is honest.

Karakeep's AI tagging adds topic tags on top (see below). The two do not
conflict: these two are *provenance* and *state*, the AI's are *subject*.

### It is a manual setting, and that is not an oversight

Miniflux keeps integration settings per-user in its database, so this is not
reachable from Nix — the same situation as Nextcloud's serverinfo token. If it
is ever lost (a database restore, a new account), it is four fields on one page.
Worth a note in your password manager next to the API key.

---

## Adding feeds

### The normal way: the bookmarklet

*Miniflux → Settings → Integrations → Bookmarklet.* Drag it to the bookmarks
bar once, per browser. On any site, click it: Miniflux discovers the feed and
offers to subscribe.

This is deliberately **not** a browser extension. There is no official Miniflux
one, the third-party options are unaffiliated code holding an API token, and
the bookmarklet does the same job with nothing installed.

### When a site has no feed

In rough order of effort:

1. **Look harder.** Many sites still have `/feed`, `/rss`, `/atom.xml` or
   `/index.xml` without advertising it. Try them before concluding anything.
2. **RSS-Bridge / RSSHub.** Generate a feed from a site that has none. Neither
   is deployed here; adding one is its own decision, not a footnote to this
   guide.
3. **Accept that it is not a feed** and put the site in Karakeep as a bookmark
   instead. Not everything belongs in the river.

### Categories are the only organisation that scales

Miniflux has categories and nothing else — no folders, no tags on feeds. Use
them as **reading modes**, not as subjects:

- `Daily` — things you genuinely read every day. Keep it small enough to finish.
- `Weekly` — worth reading, not worth interrupting for.
- `Reference` — high-volume, low-signal; skim headlines, read almost nothing.
- `Watch` — release feeds, changelogs, security advisories. Skimmed for events.

Subject-based categories ("Nix", "Photography") feel natural and fail, because
the question at reading time is *how much attention do I have right now*, not
*what is this about*. Subjects are what Karakeep's tags are for, after the fact.

---

## Consuming and curating — the daily loop

The loop is four steps and takes as long as you let it:

1. **Skim `Daily`.** Miniflux marks entries read as you scroll. Do not fight it.
2. **For anything worth more than a skim, save to Karakeep** with the
   integration above. This is the *only* decision that matters in the whole
   workflow: *is this worth having in a year?*
3. **Mark all as read** without guilt. The unread count is not a debt. A feed
   reader you feel bad about is a feed reader you stop opening.
4. **Periodically, drain `tag:new` in Karakeep** — that is where the real
   curation happens, and it is a separate activity from reading.

### On starring in Miniflux

Miniflux has a star. **Prefer saving to Karakeep instead**, because a star is a
pointer into a database that deletes its own entries, and a save is a copy that
does not. Use the star only as a within-session "come back to this in a minute".

### Unsubscribing is the real maintenance

Once a month, sort feeds by read-ratio (*Feeds → sort*). A feed you have never
clicked through from in three months is noise with a good reputation.
Unsubscribe. This is the single highest-value habit in the whole stack and the
one nobody does.

---

## Archiving and curating in Karakeep

### What happens automatically when something arrives

1. **The crawler** fetches the page, extracts readable text, and stores a
   full-page snapshot plus a screenshot.
2. **AI tagging** runs against ernst's own inference server — `qwen3-coder-30b`
   over the `ai0` link, the model llama-swap already has resident — and adds
   subject tags and a summary. Nothing leaves the house.
3. **Meilisearch** indexes the text, so search covers the *contents* of what you
   saved, not just titles and URLs.

Tagging is asynchronous. A just-saved bookmark is untagged for a few seconds to
a minute; that is the queue, not a fault.

### Lists are for intent, tags are for subject

Karakeep has both and they are not interchangeable:

- **Tags** answer *what is this about*. Mostly AI-generated. Let them be messy;
  search is what you actually use.
- **Lists** answer *what am I going to do with this*. Few, hand-made, and worth
  keeping deliberate: `Read later`, `Reference`, `Projects`, `Cooking`.

Smart lists (saved queries) are worth more than manual lists for anything
rule-shaped — `tag:new` as your triage queue is the obvious first one.

### The triage pass

Whenever `tag:new` gets uncomfortable:

1. Open it. For each item: does this belong in a list? Does it need a better
   title? Is it actually rubbish?
2. Remove the `new` tag — that is the whole point of it.
3. Delete freely. **A bookmark manager you never delete from becomes a landfill
   with a search box.**

Note that deleting from Karakeep deletes the archived copy too, and that copy
may be the only one left. ZFS snapshots on `zdata/state` are the safety net for
regret, and there is no trash can with a retention period — see
[ernst zdata datasets](ernst-zdata-datasets.md).

---

## Browser bookmarks — Floccus

Floccus syncs each browser's **native bookmark tree** with Karakeep. It is not
the same act as saving to Karakeep, and conflating the two causes most of the
confusion people have with this setup — but the difference is **not** what an
earlier version of this guide claimed.

**Floccus-synced bookmarks ARE fully archived.** Once a link lands in Karakeep
it is an ordinary bookmark whatever put it there: the crawler fetches it,
extracts the text, takes a screenshot, the AI tags it and Meilisearch indexes
it. Verified on the real instance — Floccus-synced entries carry generated
subject tags and real page screenshots, not favicons.

The actual difference is **ownership**, and it matters more than archiving did:

| | Lives in | Archived? | Deleting it in the browser… |
|---|---|---|---|
| Karakeep extension / Miniflux integration | Karakeep only | **Yes** | n/a — the browser has no copy |
| Floccus | Bookmarks bar **and** Karakeep | **Yes** | **…deletes it from Karakeep on the next sync** |

**That last cell is the whole point.** Floccus is a *sync* tool, not an import:
it makes two trees match, in both directions. So a page you "kept" by
bookmarking it is hostage to the bookmarks bar — tidy the bar six months later
and the archived copy goes with it, silently, because that is Floccus working
correctly.

A bookmark saved through the extension or from Miniflux is not in the browser
at all, so no amount of bookmark housekeeping can touch it.

**So: bookmarks bar for things you navigate to, Karakeep for things you want to
keep.** A banking login belongs in the bar. An article you want in a year
should be saved with the extension, *even if it is also bookmarked* — the two
are not redundant, because only one of them survives a tidy-up.

> **Worth proving to yourself once**, rather than taking on trust: bookmark a
> throwaway page, let it sync, delete it from the bar, sync again, and see
> whether it is still in Karakeep. The answer determines how much you should
> trust the bar as a keeping mechanism, and it is cheap to find out.

### Setup, per browser

Installed declaratively on miralda and jens for all four browsers — see
`service-modules/software.nix` and `machines/miralda/home-modules/browsers.nix`.
Configuring them is manual, because neither extension exposes a managed-storage
schema:

1. Karakeep extension → server `https://karakeep.goclan.org` → its own API key.
2. Floccus → *Add account* → **Karakeep** → same URL → its own API key.
3. Choose which local folder syncs. **Start with one folder, not the whole
   tree.**

### Two warnings worth reading before the first sync

**Give every browser its own API key**, labelled. Eight browser instances
sharing one key means one revocation breaks all of them, and you will not know
which one you meant to fix.

**The first sync is the dangerous one.** Floccus merges two trees, and if one
side is empty it can look like "delete everything" to the other. Sync one small
folder first and confirm both ends look right before pointing it at the root.

---

## When the same page arrives twice

It will: you save an article from Miniflux, then bookmark it in the browser a
week later. Karakeep deduplicates on URL for identical links, but tracking
parameters (`?utm_source=…`) make two URLs that are the same page.

Not worth solving systematically. Strip tracking parameters when you notice,
and merge duplicates during the triage pass. A handful of duplicates costs
less than a rule that occasionally hides something.

---

## What is backed up, and what is not

| | Snapshotted | Notes |
|---|---|---|
| Karakeep (`/srv/state/karakeep`) | ✅ `zdata/state`, auto-snapshot on | The archive AND the SQLite database |
| Miniflux (`/srv/state/miniflux`) | ✅ same dataset | Mostly feed subscriptions; entries are transient by design |
| Meilisearch index | ❌ container rootfs | **Deliberate** — derived data, rebuilt from Karakeep on demand |
| Browser bookmark trees | via Floccus → Karakeep | The browsers are not backed up; Karakeep is |

**There is still no off-box backup of any of this** — ZFS snapshots live on the
same pool as the data. That is a fleet-wide gap, not one this stack introduces,
and `zdata/backup` is reserved and deliberately uncreated.

**Export your Miniflux feed list occasionally** (*Settings → Export → OPML*).
It is small, it is the one thing that is genuinely painful to rebuild by hand,
and it is the only part of this stack with a portable interchange format.

---

## Adding a person to Karakeep

Not a footnote — there is **no** other route, and it surprises people:

1. `DISABLE_SIGNUPS = "false"` in `machines/ernst/containers/karakeep.nix`
2. `clan machines update ernst`
3. They sign in once through Authelia — the account is created on the callback
4. Back to `"true"`, `clan machines update ernst` again

There is no password form, no admin invite and no CLI. While signups are on,
any Authelia identity that can pass two-factor gets an account on first login,
and since `karakeep.goclan.org` is public that window is on the internet. Keep
it to minutes.

---

## Quick reference

| Task | Where |
|---|---|
| Subscribe to a feed | Miniflux bookmarklet, or paste the URL in Miniflux |
| Keep an article you are reading | Miniflux → *Save* (goes to Karakeep, tagged `miniflux, new`) |
| Keep a page you are browsing | Karakeep browser extension |
| Bookmark for navigation | Browser bookmarks bar — Floccus syncs it to Karakeep, and archives it there, but a later deletion in the bar removes it |
| Find something you kept | Karakeep search — it covers page *contents* |
| Triage the backlog | Karakeep, `tag:new` |
| Monthly maintenance | Unsubscribe dead feeds in Miniflux; drain `tag:new`; delete rubbish |
| Yearly | Export OPML from Miniflux |
