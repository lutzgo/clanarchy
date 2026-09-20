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

### It saves ENTRIES you pick, not FEEDS — and this is the first thing to get wrong

**Subscribing to a feed in Miniflux puts nothing in Karakeep.** The integration
is per-entry and manual: it fires when you hit **Save** on an individual entry,
exactly like Miniflux's Wallabag integration. Feeds are never synced; entries
you choose are.

That is the whole design rather than a limitation — the river stays in
Miniflux, and only what you decided to keep crosses over. But the failure mode
is silent and looks like a broken integration: you subscribe, wait, and nothing
appears.

**Test it once so you know it works:** open an entry, click *Save*, and it
should appear in Karakeep within seconds tagged `miniflux`. Press `?` in
Miniflux for the keyboard shortcut — saving is a single key and worth learning,
since it is the one action the daily pass repeats.

### If you want a whole feed archived automatically

Karakeep subscribes to RSS itself — *User Settings → RSS Subscriptions*. It
polls hourly and imports every new entry as a full bookmark. No webhook and no
third-party bridge (one exists; it is not needed).

**Use it sparingly, because it cuts against the model in two ways.** Every
imported entry is crawled, screenshotted and AI-tagged, which is GPU work per
item against the same model the coding agent uses — a chatty feed is a
standing load. And it fills the *permanent* keep with unread noise, which is
precisely what Miniflux's ephemerality exists to prevent.

Good for a low-volume source you genuinely want in full: a friend's blog that
posts monthly, a changelog you must not miss. Bad for anything you would put in
`Daily`. If a feed belongs in both, it belongs in Miniflux and you press Save.

### The tags are for provenance, not for state

Anything arriving this way is tagged `miniflux`, which is the useful half: it
is the only thing that distinguishes a feed capture from a Floccus-synced
browser bookmark, since both reach Karakeep through the same API. Several
queries below depend on it.

`new` is optional and slightly redundant. An earlier version of this guide
built the triage queue out of it — save, then remove the tag once filed — which
works but has two problems: it is a convention you have to maintain by hand,
and it only ever covers things that came from Miniflux. **The inbox below is
defined from Karakeep's own states instead** (`-is:archived -is:inlist`), which
needs no discipline and catches everything however it arrived. Keep `new` if
you like the extra signal; nothing depends on it.

Karakeep's AI tagging adds subject tags on top. No conflict: `miniflux` is
*provenance*, the AI's are *subject*.

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

## The daily inbox workflow

### There are three inboxes, and naming them is most of the work

Nobody designed it that way; it falls out of having three ways in. An inbox
you have not named is one you cannot empty.

| Inbox | What is in it | Emptied by | Cadence |
|---|---|---|---|
| **Miniflux unread** | Everything you subscribe to | Skimming, then *mark all read* | Daily |
| **Karakeep inbox** | Things you saved but have not filed | Archiving or filing each one | Daily-ish |
| **Floccus arrivals** | Browser bookmarks, synced in | Nothing — they accumulate | Monthly, if ever |

The third is the one that bites, because it is silent: bookmarks you make in
the browser arrive in Karakeep with no tag and no list, so without a query that
separates them they sit in the second inbox forever, diluting it with things
you never meant to triage.

### The one rule that makes it work

> **Reading time is capture time only. Filing is a different activity.**

Deciding *where something goes* while you are reading is what turns a ten
minute skim into forty minutes and is why people stop opening their reader. The
skim produces exactly one decision per item — keep or don't — and nothing else.

---

### Set-up, once

Karakeep's **smart lists** are saved queries that re-evaluate themselves, so
the inboxes below are defined rather than maintained. Create these four
(*Lists → new → smart*):

| Name | Query | What it is |
|---|---|---|
| **Inbox** | `-is:archived -is:inlist` | Saved, not yet filed. **The one you actually work.** |
| **From feeds** | `#miniflux -is:archived` | Today's captures from the reader |
| **Link rot** | `is:broken` | Bookmarks whose page no longer resolves |
| **Untagged** | `-is:tagged` | The AI tagger failed or is stuck |

**Calibrate `source:` once before you trust any query built on it.** Karakeep
records where each bookmark came from — `api`, `extension`, `rss`, `mobile`,
`web`, `cli`, `singlefile`, `import` — but which value a given tool produces is
worth *checking* rather than assuming. Search `source:api`, then
`source:extension`, and see what each returns on your instance. Both Floccus
and the Miniflux integration go through the API, so `#miniflux` is what tells
them apart:

```
source:api -#miniflux        # ≈ Floccus arrivals
```

If that returns your browser bookmarks, add it as a fifth smart list called
**Bar**. If it does not, find the value that works before writing one.

### "Archived" does not mean what you think

This is the single most confusing thing in Karakeep and it is worth one
paragraph.

**`is:archived` is a DONE state, not a preservation state.** Every bookmark has
a stored page snapshot the moment it is crawled — that is not optional and not
something you trigger. Archiving is the *email* sense of the word: filed away,
out of the inbox, still there when you search.

So **archive is your "done" button.** Pressing it does not create a copy and
un-pressing it does not destroy one.

---

### The daily pass — Miniflux, about ten minutes

1. Open Miniflux. **`Daily` category only.** Do not look at the others.
2. Skim. Read headlines and first paragraphs.
3. Anything worth more than a skim → **Save to Karakeep** (the integration —
   one click). **Do not read it now.**
4. **Mark all as read.** Not "mark the ones I finished" — all of them.
5. Close Miniflux.

That is the whole thing. If the unread count in `Weekly` or `Reference` is
bothering you, that is a *feed subscription* problem, not a reading problem —
see the monthly pass.

**The unread count is not a debt.** Miniflux ages entries out by design;
anything you did not get to was, by definition, not worth getting to.

### The reading pass — Karakeep, whenever you actually have attention

Separate from the skim, and it can be hours later or on the sofa:

1. Open the **Inbox** smart list.
2. Read things. For each, exactly one of:
   - **Archive it** — read, done, findable by search later. The common case.
   - **Add it to a list** — you will come back to it deliberately
     (`Read later`, `Reference`, `Projects`, `Cooking`).
   - **Delete it** — it was not what you hoped.
3. Stop when you stop. The inbox does not have to be empty every day.

Note that both archiving *and* filing remove an item from the Inbox query, so
the list shortens as you work whichever verb you choose.

### The weekly pass — about fifteen minutes

- Drain whatever is left in **Inbox**. Be harsher than during the week; if it
  has sat for seven days, archive or delete it rather than reading it.
- Check **Link rot**. A broken bookmark is a page you can now only read in
  Karakeep's snapshot — which is why the snapshot exists. Worth knowing about
  while you still remember why you saved it.
- Check **Untagged**. A handful is the queue; a growing pile means the tagger
  or the inference link is broken, and `journalctl -M karakeep -u
  karakeep-workers` on ernst is where that shows.

### The monthly pass — about ten minutes

- **Unsubscribe dead feeds.** Sort by read-ratio in Miniflux. A feed you have
  never clicked through from in three months is noise with a good reputation.
  **This is the highest-value habit in the whole stack and the one nobody
  does** — every feed you drop makes the daily pass shorter forever.
- **Sweep the Bar list** if you made one, or ignore it deliberately. Browser
  bookmarks are navigation; they do not owe you triage.
- **Export OPML** (*Miniflux → Settings → Export*). Small, and the only part of
  this stack with a portable interchange format.

---

### When you fall behind

You will. The failure mode is not falling behind, it is *avoiding the tool
because you fell behind*.

- **Miniflux**: mark everything read. There is no penalty and no lost data
  worth mourning — anything genuinely important recurs.
- **Karakeep Inbox over ~50 items**: declare bankruptcy. Select all, archive
  all. Nothing is deleted, everything stays searchable, and you get an empty
  inbox for the price of admitting you were not going to read them. **An
  archived bookmark you never read is worth exactly as much as an unarchived
  one you never read**, minus the guilt.

If bankruptcy happens twice in a quarter, the problem is upstream: too many
feeds in `Daily`, or too low a bar at capture time. Fix the input, not the
backlog.

---

### On starring in Miniflux

Miniflux has a star. **Prefer saving to Karakeep instead**, because a star is a
pointer into a database that deletes its own entries, and a save is a copy that
does not. Use the star only as a within-session "come back to this in a minute".

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

**Smart lists are worth more than manual lists for anything rule-shaped** —
they are saved queries that re-evaluate themselves, so the thing stays true
without being maintained. The four in
[Set-up, once](#set-up-once) are all of this kind. Keep manual lists for the
genuinely hand-curated: `Read later`, `Reference`, `Projects`, `Cooking`.

**Adding to a list is one of the two ways out of the Inbox**, the other being
archive — both satisfy `-is:archived -is:inlist`, so either empties it.

### On deleting

Delete freely during the reading pass. **A bookmark manager you never delete
from becomes a landfill with a search box**, and the search is what you are
paying for.

One caveat with real weight here: deleting from Karakeep deletes the archived
copy too, and that copy
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
| Triage the backlog | Karakeep → **Inbox** smart list (`-is:archived -is:inlist`) |
| Daily | Skim `Daily` in Miniflux → save keepers → mark all read |
| Whenever you have attention | Work the **Inbox** list: archive, file, or delete |
| Weekly | Drain Inbox harder; check **Link rot** and **Untagged** |
| Monthly | Unsubscribe dead feeds; sweep browser bookmarks; export OPML |
| Yearly | Export OPML from Miniflux |

---

## Reaching this from another network

Two paths, and they fail in confusingly similar ways.

**The public path** — `miniflux.goclan.org` and `karakeep.goclan.org` are both
on the `wan` entrypoint. Miniflux is behind Authelia's forward-auth (you get
the portal, then 2FA); Karakeep answers its own sign-in page and sends you to
Authelia from there. Nothing to set up: open the URL.

**The VPN path** — the UniFi WireGuard server. Import the client config into
NetworkManager so Noctalia's `network-manager-vpn` widget can toggle it; that
is the same arrangement `modules/desktop/desktop-common.nix` describes for
IVPN, and the widget only ever sees NetworkManager connections.

```bash
nmcli connection import type wireguard file skynetvpn.conf
nmcli connection modify skynetvpn connection.autoconnect no
```

`autoconnect no` matters — a full tunnel coming up on the home LAN is not what
you want. **Do not run it alongside IVPN**: both are `AllowedIPs = 0.0.0.0/0`,
and two things with authority over the default route is how a kill-switch
becomes an outage nobody can diagnose.

### The trap: with the VPN up, BOTH paths break

Measured 2026-09-19. A tunnelled client gets an address on **VLAN 70**, and:

- it **cannot reach VLAN 90 at all** — not Traefik, not any backend — because
  the UDM-Pro has no policy permitting it. DNS works (VLAN 5 is reachable) and
  SSH to ernst works (VLAN 50 is reachable), which makes it look like the
  services are down rather than unreachable;
- the **public** path is simultaneously unavailable, because a full-tunnel
  client egresses from the house's own WAN address, and connecting to
  `78.94.91.74` from inside is a NAT hairpin the UDM-Pro does not do.

So the VPN takes away the path that was working and does not supply the one it
promised. The fix is one UDM-Pro policy — `VPN (70)` → `10.0.90.12:443/tcp` —
and it is written up in
[the app-API ingress guide](ernst-app-api-ingress.md#vpn-clients-land-on-vlan-70-and-cannot-reach-vlan-90-by-default).

**Until that rule exists, turn the VPN off to reach these two services.**
