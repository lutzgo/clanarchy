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
| **Miniflux** | The **intake and the filter**. Polls feeds, applies rules, forwards survivors. You barely open it | **Ephemeral** — entries age out | "what should get through?" |
| **Karakeep** | The **keep AND the reading surface**. Everything that survives the filter lands here, archived, with notes and highlights | **Permanent** — snapshotted, never auto-deleted | "what am I reading, and where was that thing?" |
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

## How feed items reach Karakeep

**You do not read in Miniflux.** Miniflux polls, applies your rules, and hands
what survives to Karakeep over a webhook. Everything after that — reading,
notes, highlights, filing — happens in Karakeep, which is the better surface
for it and the only one with an archived copy of the page.

That pipeline is M28's bridge, a small Go service running inside the Miniflux
container (`machines/ernst/containers/miniflux.nix`). It is a loopback call:
no address, no firewall rule, nothing on the network.

```
feed ──► Miniflux ──► rules decide ──► bridge ──► Karakeep ──► you
         (polls)      (block/keep,     (webhook)  (crawl, archive,
                       rewrite)                    tag, index)
```

### Why not just use Karakeep's own RSS?

Karakeep subscribes to feeds natively, and **for a feed you want in full it is
the right answer** — one service, no bridge. Its subscriptions take a name, a
URL, an enabled flag and a tag-import toggle.

What it cannot do is **filter**. No rules, no keyword blocking, no regex. If
you want a noisy feed minus the noise, that decision has to happen before
Karakeep sees it, and Miniflux is what makes it.

**Pick one path per feed and never both.** A feed subscribed in Miniflux *and*
in Karakeep is the duplicate generator — see below.

### Setting it up

**In Miniflux** — *Settings → Integrations → Webhook*:

| Field | Value |
|---|---|
| Webhook URL | `http://127.0.0.1:8081/webhook` |
| Secret | Miniflux generates it — copy it into `clan vars` |

**Turn OFF the in-app Karakeep integration** (*Settings → Integrations →
Karakeep*) once the bridge works. It is not harmful to leave on — Karakeep
deduplicates, so a doubly-posted entry is a no-op — but two mechanisms doing
one job is two things to debug later.

Then `clan vars generate ernst --generator miniflux-karakeep-bridge`, which
asks for that secret and for a Karakeep API key. **Make the key its own**,
labelled `miniflux-bridge`: the extensions, Floccus and the dashboard all draw
keys from the same page and look identical.

### Adding a feed backfills NOTHING, and that is deliberate

**Measured 2026-09-20.** Two feeds added, 40 entries fetched, and the bridge
logged nothing at all — with the SSRF guard already lifted, so that was not the
cause.

**Miniflux does not fire the integration for entries found on a feed's FIRST
fetch.** Only entries discovered on a *subsequent* refresh count as new.
Otherwise subscribing to a feed with 500 archived items would dump all 500 into
Karakeep at once, which nobody wants.

So after adding a feed, the correct expectation is: **nothing happens until
that feed next publishes something.** For a news site that is minutes; for a
quiet blog it can be weeks. It is not broken.

**To prove the path immediately**, open any entry in Miniflux and hit *Save*.
That fires the webhook's `save_entry` event, which the bridge handles
regardless of `SAVE_NEW_ENTRIES`, and a bookmark appears in Karakeep within
seconds. It is the only way to exercise the live pipeline on demand.

### On duplicates, which is the thing that usually goes wrong

**Karakeep deduplicates server-side on the exact URL.** Verified in its own
source (`attemptToDedupLink`): a repeat POST returns the existing bookmark
instead of making a second one. There is an explicit guard that re-submitting
an already-**archived** bookmark stays a no-op rather than unarchiving it — so
a feed re-announcing an old entry cannot resurrect something you have read and
filed.

Two things still produce duplicates, and both have answers:

- **Tracking parameters.** `?utm_source=…` makes a different URL, so it makes
  a different bookmark. **This is the best reason to run Miniflux rather than
  Karakeep's own RSS**: its rewrite rules strip those before the URL is ever
  forwarded, which nothing on the Karakeep side could do.
- **The same feed subscribed twice** — once in Miniflux, once in Karakeep's own
  RSS. Karakeep will dedupe the identical URLs, but any rewriting Miniflux does
  makes the two paths disagree and both survive. One feed, one path.

Upstream notes the dedup is not race-proof. At one webhook delivery at a time,
that is not a shape this deployment can produce.

### What still needs a human in Miniflux

Three things, and nothing else:

1. **Subscribing** to a feed.
2. **Writing a rule** when something noisy gets through — *Feeds → the feed →
   Blocklist / Keeplist*, which are regexes over title and content.
3. **Unsubscribing** when a feed stops earning its place.

### Tags and provenance

Feed items arrive through the bridge as ordinary API bookmarks. Karakeep records
where each came from, so `source:` separates the paths without any tag
convention:

| Query | What it finds |
|---|---|
| `source:api` | the bridge, and Floccus |
| `source:extension` | the browser extension |
| `source:rss` | Karakeep's own feed subscriptions, if you use any |

The bridge sets no tags of its own. Karakeep's AI tagger adds subject tags to
everything it crawls, which is what you actually search by.

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

### Categories organise FEEDS, not reading — and they stop at the bridge

Miniflux has categories and nothing else: no folders, no tags on feeds.

**They do not reach Karakeep.** The bridge forwards a URL; it carries no
category, no feed name and no tag. So everything from every category lands in
one undifferentiated Inbox, and `Daily` versus `Reference` makes no difference
to what you see there. An earlier version of this guide called them "reading
modes", which was true when you read in Miniflux and has not been true since
M28.

What they are still good for is **managing the subscription list**: pausing or
unsubscribing a whole group, seeing at a glance what you have taken on, and
knowing where to look when something noisy needs a Blocklist rule. A workable
split on that basis:

- `Daily` — high-volume news. The group most in need of rules, because
  everything here reaches your Inbox.
- `Reference` — low-signal, subscribe-and-forget.
- `Watch` — release feeds, changelogs, security advisories.

**If you ever want a category NOT to reach Karakeep, the bridge cannot do it** —
`SAVE_NEW_ENTRIES` is global. The lever is per-feed Blocklist rules, or not
subscribing.

---

## The daily inbox workflow

### There are three inboxes, and naming them is most of the work

Nobody designed it that way; it falls out of having three ways in. An inbox
you have not named is one you cannot empty.

| Inbox | What is in it | Emptied by | Cadence |
|---|---|---|---|
| ~~Miniflux unread~~ | Nothing you need to look at — the bridge forwards, Miniflux ages entries out | Itself | Never |
| **Karakeep inbox** | Everything the filter let through, plus what you saved by hand | Archiving or filing each one | **Daily — this is the only one** |
| ~~Floccus arrivals~~ | Browser bookmarks — **Floccus syncs them into a LIST** | Nothing needed | Never |

**The third is not an inbox after all, and that is worth knowing because it
looks like it should be.** Verified 2026-09-20: Floccus-synced bookmarks do not
appear in `-is:archived -is:inlist`, because the adapter puts them in a
Karakeep list. They are therefore excluded from the Inbox for free — no tag
convention, no query, nothing to maintain.

So there are **two** inboxes, and only one of them needs daily attention.

### The one rule that makes it work

> **Capture is automatic. Your only job is deciding what to keep, after the
> fact.**

Nothing needs saving, because everything that passed the filter is already
here, already archived. That removes the decision people actually stall on —
*is this worth keeping?* asked while reading, with the article half-finished —
and replaces it with a cheaper one asked later: *archive, file, or delete?*

The corollary is that **the filter is where the real work happens**, and it is
done once per feed rather than once per item. A feed that keeps putting rubbish
in your inbox does not need more discipline from you; it needs a Blocklist rule
or an unsubscribe.

---

### Set-up, once

Karakeep's **smart lists** are saved queries that re-evaluate themselves, so
the inboxes below are defined rather than maintained. Create these four
(*Lists → new → smart*):

| Name | Query | What it is |
|---|---|---|
| **Inbox** | `-is:archived -is:inlist` | **The only one you work daily.** Everything unread and unfiled |
| **Link rot** | `is:broken` | Pages that no longer resolve — the archive is now the only copy |
| **Untagged** | `-is:tagged` | A handful is the queue; a growing pile means the tagger is stuck |
| **This week** | `-is:archived age:<7d` | What actually arrived recently, when the Inbox has a backlog |

**There is deliberately no "From feeds" list, and an earlier version of this
guide got that wrong.** It suggested `#miniflux`, a tag set by Miniflux's
*in-app* Karakeep integration — which M28 turned off, because the bridge
replaced it. **The bridge sets no tags at all.** That query now matches
nothing.

**Nor can `source:` separate feed items from browser bookmarks.** Both the
bridge and Floccus create bookmarks through the API, so both are `source:api`
and the two are indistinguishable by origin. The qualifier is still worth
knowing — `source:extension` does isolate things saved with the Karakeep
browser button — but it will not give you a feeds-only view.

**Floccus does not pollute the Inbox, and this was verified rather than
assumed.** Its adapter syncs into a Karakeep *list*, so its bookmarks are
already `is:inlist` and the Inbox query excludes them without any help. That is
the tidiest possible outcome and it is why no `Bar` list is needed.

**Calibrate `source:` once anyway if you build queries on it.** Search
`source:api` and `source:extension` and see what each returns on your instance
rather than trusting this page.

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

### There is no daily Miniflux pass any more

That is the point of the bridge. Feeds are polled, filtered and forwarded
without you, and the only inbox you work is Karakeep's.

If you find yourself opening Miniflux daily, something is wrong upstream: a
feed is too noisy and wants a Blocklist rule, or it does not deserve a
subscription.

### The reading pass — Karakeep, whenever you actually have attention

This is the whole workflow now, and it can be on the sofa:

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
| Subscribe to a feed | Miniflux bookmarklet, or paste the URL in Miniflux. Items flow to Karakeep by themselves |
| Silence part of a noisy feed | Miniflux → the feed → **Blocklist** (regex over title and content) |
| Separate feed items from browser bookmarks | You cannot by origin — both are `source:api`. Use lists and tags instead |
| Keep a page you are browsing | Karakeep browser extension |
| Bookmark for navigation | Browser bookmarks bar — Floccus syncs it to Karakeep, and archives it there, but a later deletion in the bar removes it |
| Find something you kept | Karakeep search — it covers page *contents* |
| Triage the backlog | Karakeep → **Inbox** smart list (`-is:archived -is:inlist`) |
| Daily | Work the **Inbox** smart list in Karakeep. Miniflux runs unattended |
| Whenever you have attention | Work the **Inbox** list: archive, file, or delete |
| Weekly | Drain Inbox harder; check **Link rot** and **Untagged** |
| Monthly | Unsubscribe dead feeds; add rules for whatever is still noisy; export OPML |
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

### The VPN trap, and the policy that resolves it

**This section described an unresolved trap until 2026-09-27. The policy now
exists** — see below before acting on anything here.

Measured 2026-09-19, and true of a UDM-Pro with no VPN policy. A tunnelled
client gets an address on **VLAN 70**, and:

- it **cannot reach VLAN 90 at all** — not Traefik, not any backend. DNS works
  (VLAN 5 is reachable) and SSH to ernst works (VLAN 50 is reachable), which
  makes it look like the services are down rather than unreachable;
- the **public** path is simultaneously unavailable, because a full-tunnel
  client egresses from the house's own WAN address, and connecting to
  `78.94.91.74` from inside is a NAT hairpin the UDM-Pro does not do.

So the VPN took away the path that was working and did not supply the one it
promised, and **neither failure named the cause**.

**RESOLVED 2026-09-27 — the policy `Allow VPN to Traefik` is configured**, and
it is exactly the narrow shape this guide asked for:

| Field | Value |
|---|---|
| Source zone | `VPN`, any address, any port |
| Destination zone | `Services`, **IP `10.0.90.12`**, port **HTTPS/443** |
| Action | Allow, with auto return traffic |
| Protocol / IP version | TCP, IPv4 |
| Schedule | Always |

Traefik on 443 and nothing else. **Do not widen it to VLAN 70 → VLAN 90
wholesale** — that would hand every tunnelled device the backends directly and
undo M5's backend-bypass hardening for exactly the clients most likely to be
someone else's laptop.

**Still owed: an end-to-end check from a tunnelled client.** The policy matches
the recommendation, but nobody has yet confirmed a connection from VLAN 70
through Traefik to a backend. The cheapest proof is opening
`audiobookshelf.goclan.org` in the phone app with the VPN up; if that works, so
does every other name on VLAN 90.

## Read-along books — Storyteller, and how to stage a pair

Storyteller takes a DRM-free **EPUB** and the matching **audiobook** and emits a
single EPUB3 with sentence-level synchronised playback. It is the only thing in
this stack that produces a new artifact rather than serving an existing one, and
it is also the only one that can saturate the box, so the staging step is
deliberate rather than automatic.

### Two ways in, and only one of them is usable here

Checked against the deployed 2.9.3 build's route table — `books/upload`,
`books/merge`, `books/[bookId]/process`:

| Route | Works? |
|---|---|
| Chunked upload through the browser | Technically, but a 2.2 GB audiobook means pulling it to a laptop and pushing it back through Traefik to reach a path two directories away |
| **Auto-import watcher on a directory** | **This one.** |

There is **no import-from-server-path flow**. That is the whole reason
`/srv/audiobooks/storyteller-import` exists.

### Why the watcher is NOT pointed at the libraries

Storyteller can see both libraries read-only, at `/library/ebooks` and
`/library/audiobooks`. Do not point auto-import at either:

- **`/library/audiobooks` is 116 GB.** The watcher would sweep the entire
  household collection in and start whisper transcription across all of it —
  the most CPU-expensive thing this box can do, against a Jellyfin transcode,
  the HTPC session and an interactive Ollama session. `containers/storyteller.nix`
  requires one known-good pair be checked by hand *before* any batch; a watcher
  on the whole library is that rule inverted.
- **`/library/ebooks`** is only 14 MB and harmless, but ebooks with no audio half
  are not pairs — they just queue up waiting to be matched.

Both mounts are read-only and must stay that way. `/import` is the only
read-write mount, and nothing of value lives in it.

### Settings, once — already done, here to be verified

All four were set on 2026-09-27 and read back out of `storyteller.db` on
2026-10-05. Nothing below needs doing again; it is here so a wrong value can be
recognised.

In Storyteller → Settings:

- **Automatic import → Enable**, path **`/import/`** — the *container* path, not
  the host path. `/srv/media/ingest/cwa` is CWA's drop box and is not mounted
  here at all; pointing at it silently watches nothing.
- **Readaloud location → "In the Storyteller internal folder"**. The default,
  "Alongside input with a suffix", writes next to the input file — which for a
  library-sourced pair is a read-only mount, so it cannot work.
- **Whisper model** — `tiny` is the bundled default and is fine for clean
  English. Much of this library is German (Eschbach, Zeh, Kling, Dusse,
  Sonneborn, Moers); those want `small` or `medium`.
- Leave turbo mode and both parallelism values at **1** until one book has been
  timed. The image is the **CPU** build by design (`-rocm` was rejected so it
  cannot contend with Ollama for the 7900 XTX), so "GPU if available" resolves
  to CPU regardless.

### The weekly ntfy notification, and what it is telling you

A timer on ernst (`storyteller-pair-watch`, Mondays 09:00) runs
`storyteller-stage new` and pushes any result to the ZFS ntfy topic. The body is
a bullet list of **slugs** and the footer repeats the staging command. It is the
only thing in this stack that announces itself, so it is usually where the
workflow starts.

It **notifies and never stages** — `containers/storyteller.nix` explains why at
length: alignment costs hours of CPU per book, so committing the box to four of
them has to be somebody's decision.

Three commands, all on ernst, all from the same derivation as the watcher (so
the watcher can never announce something the tool would refuse):

| Command | Answers |
|---|---|
| `storyteller-stage pairs` | every title present in **both** libraries |
| `storyteller-stage new` | pairs not yet in Storyteller's DB and not yet staged — tab-separated `slug`, `ebook`, `audiobook` |
| `storyteller-stage list` | what is currently sitting in the watch folder |

**Read the candidates before staging them — the matcher over-matches.** It
lowercases, strips punctuation and asks whether either title contains the other,
then takes the **first** ebook that hits. That is deliberately crude (the author
directories do not line up: Audiobookshelf files Banks under `Iain M. Banks`,
Bindery under `Iain Banks`), and it produces three kinds of junk, all of them
present in the 2026-10-05 run:

- **Wrong ebook, right audiobook.** `Outgrowing God (2019)` matched the ebook
  `God (2016)` because "god" is a substring and that file came first — the real
  `Outgrowing God` EPUB is in the same author directory. Check the ebook path,
  not just the slug.
- **Coincidental substring.** `Death of Poe (2026)` matched an ebook called
  `Poe`; `Classic Science Fiction- Selected Short Stories…` matched a PKD
  collection called `Short stories`.
- **Language mismatch.** `For the Win (German Edition)` against the English
  EPUB. Whisper would transcribe German audio and the aligner would then try to
  fit it to English text.

It also **under**-reports: the join only looks at `<author>/<title>/` audiobook
directories (`-mindepth 2 -maxdepth 2 -type d`), so an author whose books sit as
loose files directly under the author directory is invisible to it. Cory
Doctorow's shelf is like that — a dozen `.m4b` files and one subdirectory, and
only the subdirectory is ever considered.

### Staging a pair — use the tool, not `cp`

```bash
ssh root@10.0.50.10
storyteller-stage new                       # pick a line, verify both paths
storyteller-stage rendezvous-with-rama \
  "/srv/media/library/books/Arthur C. Clarke/Rendezvous with Rama (1973)/Rendezvous with Rama - Arthur C. Clarke.epub" \
  "/srv/audiobooks/library/Arthur C. Clarke/Rendezvous with Rama (1973)"
```

The slug is just the directory name under the watch folder; Storyteller takes
the title from the EPUB's metadata, not from it.

`storyteller-stage` is generated from `containers/storyteller.nix`'s own `let`
bindings, so it cannot disagree with the deployment about uid 3022, the `media`
gid, or either library root. It gets four things right that a hand-rolled `cp`
gets wrong:

1. **Both halves in one subdirectory.** Storyteller's scanner skips any EPUB
   sitting directly in the watch folder — it logs `Found an EPUB file that was
   not in a book folder: skipping` and moves on.
2. **Hardlinks the audio.** `/srv/audiobooks/storyteller-import`,
   `/srv/audiobooks/library` and Storyteller's `/data` are all on
   **zdata/audiobooks**, so the audio half is `ln`: instant, zero bytes, however
   many gigabytes the book is. A `cp` works and silently costs the full size
   every time. The ebook half comes from `zdata/media` and is a real copy, which
   at kilobytes does not matter.
3. **Ownership.** A fresh directory is `root:root`; the setgid bit fixes the
   group of new files and never the owner, so the container (uid 3022) would see
   files it cannot read.
4. **EPUB only.** azw3 and mobi are refused up front, with the conversion route,
   rather than failing an hour into transcription.

### …then press **Create readaloud**. The watcher does not.

**This is the step the rest of this guide used to skip, and it is the only
manual one.** Read out of the deployed 2.9.3 bundle's scanner: it creates the
book row, pulls metadata and cover art out of the EPUB, and logs
`Scanning complete`. It does **not** enqueue any work. Nothing happens until a
human opens `storyteller.goclan.org`, picks the new book and presses the button.

The button is labelled **Create readaloud** on the book's own page, under the
cover. There is no "Start processing" anywhere in this build — that is the name
of the API route behind it (`POST /api/v2/books/<id>/process`), not of anything
on screen.

So the full loop is:

1. `storyteller-stage <slug> <ebook> <audiobook-dir>` on ernst.
2. Within ~5 seconds: `Detected a change in /import/, scanning for new book
   files...` in `journalctl -u podman-storyteller`, and the book appears in the
   web UI with cover and metadata, unprocessed.
3. **In the UI: Create readaloud.** Transcode → transcribe → align. It is
   `Nice = 15` / `CPUWeight = 20`, so it will not starve anything, which also
   means it is not fast — Consider Phlebas took about 8½ hours wall-clock on
   `whisper.cpp:medium`.
4. The synced EPUB3 lands in `/data/assets/<Title>/aligned/<Title>.epub` and the
   `readaloud` row flips to `ALIGNED`.

### Stage one pair at a time — the scanner duplicates books

**Measured 2026-10-05: three pairs staged in one sitting produced six books.**
Every change fires *two* concurrent scans — `Detected a change in /import/` is
logged twice, every time — and each scan snapshots the existing book list when
it *starts*, so neither sees the other's insert. Two rows, same title, same
source paths, different `uuid` and a ` [xxxxxxxx]` suffix on the second one's
asset directory.

It is made worse by scans dying part-way:

```
ERROR: Encountered an error scanning for new book files in /import/
  … at async I.getCoverArt
[Error: Command failed: ffprobe -i "/tmp/storyteller/Audio/00006-00001.flac" …
```

The scanner re-extracts cover art for **every** book under `/import` on every
pass, including ones already imported, and one bad extraction aborts the whole
scan — so the next filesystem change rescans from a stale snapshot and imports
again. A pair that is finished with `/import` (status `ALIGNED`) is worth
clearing out for this reason alone, not just for tidiness.

Both are upstream races in 2.9.3, not something this deployment configures. Work
around them:

- Stage **one** pair, wait for `Scanning complete` in the journal and for the
  book to appear, then stage the next.
- If a duplicate happens anyway, delete one of the two from its own page
  (**Delete book**) *before* creating a readaloud. It is safe: the delete route
  removes the book row and at most that book's own asset directory and generated
  readaloud. It never touches `ebook.filepath` or `audiobook.filepath`, so the
  staged pair in `/import` survives, and the two asset directories are distinct
  because of the suffix.
- Tell them apart by UUID. **The UUID is not displayed anywhere in the UI — it
  is the URL.** Opening a book puts `…/books/<uuid>` in the address bar, and
  hovering a cover in the grid puts it in the status bar. To go straight to the
  one you mean, paste its URL. The two pages are otherwise identical — same
  title, same cover, same `/import/<slug>` paths — so the URL is the only thing
  to check before pressing Delete.
- The surviving row should be the one whose asset directory has **no** suffix,
  i.e. the first-created of the two:

```bash
ssh root@10.0.50.10
nix shell nixpkgs#sqlite -c sqlite3 -readonly \
  /srv/audiobooks/storyteller/storyteller.db \
  "select uuid, title, suffix, created_at from book order by title, created_at;"
```

**Delete book leaves the asset directory behind** unless the delete included
assets — it is only cover art at this stage (a few hundred KB), but it
accumulates. Sweep the orphans by comparing the two lists:

```bash
ssh root@10.0.50.10 'ls /srv/audiobooks/storyteller/assets/'
# any directory with a ` [xxxxxxxx]` suffix whose book no longer exists in the
# query above is dead; rm -rf it.
```

**Leave the staged directory in `/import` until processing has finished.** The
DB stores the *source paths*, not copies: `audiobook.filepath` stays
`/import/<slug>` and the splitter reads from it when processing starts, which
may be days after the import. Clearing the watch folder early produces

```
ERROR: Encountered error while running task "SPLIT_TRACKS" for book <uuid>
  ENOENT: no such file or directory, scandir '/import/consider-phlebas'
```

which is what happened on 2026-09-28 and cost a re-stage. Leaving it costs
nothing anyway — the audio is a hardlink. Once `aligned_at` is set the directory
can go; `storyteller-stage new` will not re-announce the title, because it
de-duplicates against Storyteller's database rather than against the watch
folder.

### Which pairs actually exist

Both halves must be the same title and the ebook must be **EPUB**. Do not keep a
list here — it goes stale the moment Bindery or the audiobook grabber lands
anything. Ask the machine:

```bash
ssh root@10.0.50.10 storyteller-stage new
```

For scale: on 2026-10-05 that returned six candidate lines, of which two were
clean matches (`Rendezvous with Rama`, `Childhood's End` — both Clarke, both
flat mp3 directories), one was the right audiobook with the wrong ebook picked
(`Outgrowing God`), and three were junk by the rules in the section above. One
genuinely-aligned book exists so far: **Consider Phlebas**, imported
2026-09-27 and aligned 2026-09-28 with `whisper.cpp:medium`.

### Where the output goes

Into Storyteller's own `/data`, served through `storyteller.goclan.org` and read
in the **Storyteller Reader** app (Android and iOS — set the server URL, log in,
download). Do not route it anywhere else: Audiobookshelf cannot render EPUB
media overlays, and CWA's ingest converts and deletes what it takes in, which
would destroy the synchronisation that is the entire point. The synced book is
a terminal artifact.

### Reading a synced book — the Storyteller app, and the VPN

The synced EPUB3 is a terminal artifact: it stays in Storyteller's `/data` and is
read in the **Storyteller Reader** app (Android `dev.smoores.Storyteller`, and
iOS). Set the server URL, log in, download. Position syncs across devices when
the app can reach the server.

**Two things had to change before the app could connect at all, and only one of
them is in this repo.**

**1. Forward-auth had to come off (done, 2026-09-27).** `storyteller.goclan.org`
was in `protectedHosts`. Measured with the middleware still in place:

```
GET  /api/v2/books  -> 302  https://auth.goclan.org/?rd=…
POST /api/v2/token  -> 303  https://auth.goclan.org/?rd=…
```

`/api/v2/token` is the login call. The app posts credentials there and carries a
token afterwards — so the redirect intercepted the one request that would have
produced a credential. The app could never authenticate, and the symptom is
indistinguishable from a broken server. It is now in `appApiHosts`, the same
client-compatibility clause as Audiobookshelf, Komga, Navidrome and CWA.

It is deliberately **not** in `wanExposed`. This name answers the LAN and the
VPN and never the public internet, which is what makes dropping forward-auth a
smaller decision here than it was for the five WAN names. Storyteller's own
accounts are now the entire boundary on it.

**2. The VPN needs a UDM-Pro policy, and that cannot live in this repo — it is
configured (2026-09-27).** `Allow VPN to Traefik`: VPN zone → Services zone,
IP `10.0.90.12`, TCP/443 only. See
[the VPN section above](#the-vpn-trap-and-the-policy-that-resolves-it) for the
full shape and for why it must not be widened.

**Audiobookshelf needed no repo change for either half** — it has carried the
forward-auth bypass since M14 and is already on `wan`. Over the VPN it was
blocked by the routing policy alone.

So both apps should now work over the tunnel: point them at
`https://audiobookshelf.goclan.org` and `https://storyteller.goclan.org`.
Downloads need the Storyteller app in the **foreground** — background
downloading is not implemented, and an audiobook is gigabytes, so do the first
one on wifi.

If a connection fails, distinguish the two causes before changing anything: a
**302 to `auth.goclan.org`** means forward-auth (a repo problem), while a
**timeout or no route** means the UDM-Pro policy or the zone assignment (not a
repo problem). They are unrelated and the symptoms do not overlap.
