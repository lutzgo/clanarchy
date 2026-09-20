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
| **Floccus arrivals** | Browser bookmarks, synced in | Nothing — they accumulate | Monthly, if ever |

The third is the one that bites, because it is silent: bookmarks you make in
the browser arrive in Karakeep with no tag and no list, so without a query that
separates them they sit in the second inbox forever, diluting it with things
you never meant to triage.

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

**Calibrate it once rather than trusting this page.** Search `source:api`, then
`source:extension`, and see what each returns on your instance. If Floccus
turns out to sync into a *list*, its bookmarks are already `is:inlist` and
therefore already excluded from your Inbox — which would be the tidiest
possible outcome and is worth five seconds to check.

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
