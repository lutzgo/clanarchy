# Video courses in Jellyfin

Bought video courses — Proko's *Drawing Basics*, so far — watched in Jellyfin as
a TV show, with metadata written from a manifest in this repo and never looked
up online.

The moving parts:

| Thing | Where |
|---|---|
| Library root | `/srv/media/library/courses` on ernst → `/media/Server001/Courses` in the Jellyfin container |
| Ingest | `/srv/media/ingest/courses/<course-slug>/` |
| Manifests | [`machines/ernst/courses/`](../../machines/ernst/courses) — one JSON file per course |
| Tool | `course-import`, declared in [`machines/ernst/courses.nix`](../../machines/ernst/courses.nix), body in [`machines/ernst/course-import.sh`](../../machines/ernst/course-import.sh) |

## Why this is not Sonarr, and not the TV-Shows library

**Sonarr cannot hold this.** It has no path to a series that is not on TheTVDB —
no manual entry, no alternative metadata source. Upstream's own answer to the
question is "add it to TVDB first", which is not something to do with a paid
course. Nothing here is or can be \*arr-managed. That is also why the library
root is a *sibling* of `tvshows/` rather than a directory inside it: Sonarr's
root-folder scan would otherwise list every course as an unmapped folder
forever.

**And it is a separate Jellyfin library, not a folder in TV-Shows,** because
Jellyfin's metadata providers are a *per-library* setting. A course has no TVDB
entry, so every scan of a library it sits in produces a failed identification
and, occasionally, a wrong match against a real series. The switch that stops
that is "no internet metadata" — and inside TV-Shows that switch would apply to
all 155 real series too. A second library is the only scope at which "local NFO
only" can be expressed.

## Layout

One show per **course**, one season per **chapter**:

```
/srv/media/library/courses/
  Proko - Drawing Basics/
    tvshow.nfo
    Season 01/                                  <- chapter "Getting Started"
      season.nfo
      Proko - Drawing Basics - S01E12 - Warmup - Mushrooms.mp4
      Proko - Drawing Basics - S01E12 - Warmup - Mushrooms.nfo
      Proko - Drawing Basics - S01E12 - Warmup - Mushrooms.en.srt
      Proko - Drawing Basics - S01E12 - Warmup - Mushrooms.txt
      Proko - Drawing Basics - S01E07 - Project - Simplify from Observation - level-1-pear-1.jpg
```

The alternative — one show named "Proko" with a season per *course* — was
rejected because Drawing Basics alone is 185 lessons, and a flat 185-episode
season throws away the chapter structure, which is the only navigation the
course actually has.

Subtitles carry the `.en.` component so Jellyfin labels the track English rather
than "Undefined". Reference images keep their original name as a ` - ` suffix:
`… - level-1-pear-1.jpg` matches none of Jellyfin's image suffixes (`-poster`,
`-fanart`, `-thumb`, `-banner`, `-logo`, `-clearart`, `-disc`), so none of them
is mistaken for episode artwork.

## The workflow

Download lessons on a laptop, then from that laptop:

```bash
rsync -av --info=progress2 ~/Videos/proko/ root@ernst:/srv/media/ingest/courses/drawing-basics/
```

Then on ernst:

```bash
course-import list                       # courses, and how far each one has got
course-import status drawing-basics      # per-lesson: in library / waiting / downloading
course-import import -n drawing-basics   # dry run
course-import import drawing-basics      # do it
course-import orphans drawing-basics     # files no manifest entry claims
```

`import` **moves** rather than copies. Ingest and the library are on the same
`zdata/media` dataset, so the move is a rename: instant, and with no window in
which a half-written 3 GB lesson is visible to a Jellyfin scan.

Re-running `import` is safe and is how metadata is corrected: edit the manifest
and run it again. A changed `plot` is rewritten into the `.nfo`; a changed
`title` *additionally renames* the episode and every one of its sidecars,
because an episode is identified by its `SxxExx`, not by its title.

### Artwork

The library has its image fetchers switched off, so the only artwork it will
ever have is what you put there. Save the course cover image into the **ingest
root** (not a lesson subdirectory) and the next `import` files it:

| Save it as | Jellyfin uses it for |
|---|---|
| `poster.jpg` | the show's poster — wants 2:3 |
| `backdrop.jpg` or `fanart.jpg` | the full-width background — 16:9 |
| `banner.jpg`, `thumb.jpg`, `logo.png`, `clearlogo.png` | the corresponding slot |
| `season01-poster.jpg` | the poster for season 1 (these live at the **show** root, not inside the season directory) |

Proko's own course cover is the `og:image` on the course page — 16:9, so it is a
`backdrop.jpg`, not a poster. These are deliberately **not** committed next to
the manifest: it is the vendor's artwork, and the repo is not where that
belongs.

### Things it deliberately will not do

- **A lesson whose video has not arrived is left entirely alone** — no NFO, no
  subtitle move. Writing metadata for an absent video leaves orphaned sidecars
  in the library that the real import later has to collide with.
- **A download still in progress is skipped and said so.** Chromium writes
  `<name>.mp4.crdownload` and renames on completion, so a partial is never
  importable; `status` reports it as `downloading` rather than
  `not downloaded`, because those two call for different actions.
- **It never guesses a lesson's number or title.** Both come from the manifest.

## The manifest

One JSON file per course in `machines/ernst/courses/`, named for the course
slug. Adding a course is adding a file; adding a chapter is editing one. No Nix
change is needed for either — but both still go through a PR, like everything
else, and both need a `clan machines update ernst` to reach the machine, because
the manifests are baked into the store path the tool reads.

```json
{
  "show": {
    "title": "Proko - Drawing Basics",
    "sorttitle": "Proko 01 Drawing Basics",
    "studio": "Proko",
    "genres": ["Education", "Art"],
    "creator": "Stan Prokopenko",
    "url": "https://www.proko.com/course/drawing-basics",
    "plot": "…"
  },
  "chapters": [
    {
      "season": 1,
      "title": "Getting Started",
      "lessons": [
        { "slug": "learning-how-to-draw", "title": "Learning How to Draw", "plot": "…" },
        { "slug": "project-simplify-from-observation",
          "title": "Project - Simplify from Observation",
          "plot": "…",
          "resources": ["level-1-pear-1.jpg", "level-2-portrait.jpg"] }
      ]
    }
  ]
}
```

- `season` — the season number for that chapter. `lessons: []` is fine; an empty
  chapter produces no season directory, so listing all eight chapters up front
  does not leave seven empty seasons in Jellyfin.
- `slug` — **the download filename stem, which is also the lesson's URL slug**,
  and which disagrees with the title often enough to matter:
  `simplify-from-observation-pear-demo` is the lesson *Demo - Simplify Pear from
  Observation*. There is no rule that derives one from the other, so the mapping
  is stated and the tool refuses to guess.
- Episode number is the lesson's **position in its chapter**, never a sort of
  the ingest directory. Inserting a lesson renumbers everything after it — which
  is correct, and which `import` will carry out as renames on the next run.
- `resources` — files that are not named after the slug (reference photos, for
  instance) and so would otherwise be reported as orphans.

### Where the plots came from

Proko's lesson pages carry an intro paragraph for some lessons and nothing for
others. The manifest uses that text where it exists and a one-line summary of
the title where it does not, so a few of the `plot` values in
`drawing-basics.json` are editorial rather than quoted. Correct any of them by
editing the manifest and re-running `import`.

### Adding the rest of Drawing Basics

Only chapter 1, *Getting Started*, is filled in. Chapters 2–8 (`Lines`,
`Shapes`, `How Perspective Works`, `Intuitive Perspective`, `Values`, `Edges`,
`Bonus Content`) are present with empty `lessons` arrays. The course page only
renders the first chapter's lesson list without JavaScript, so the remaining
titles have to come from the playlist sidebar on proko.com, in order.

`course-import orphans drawing-basics` is the prompt for this: anything sitting
in ingest that no manifest entry claims is a lesson that still needs a row.

## Jellyfin: adding the library

This is UI state and is **not** declarative — it has to be done once by hand,
after the first `clan machines update ernst` that ships this.

Dashboard → Libraries → **Add Media Library**:

| Field | Value |
|---|---|
| Content type | **Shows** |
| Display name | `Courses` |
| Folder | `/media/Server001/Courses` |
| Metadata downloaders (Shows / Seasons / Episodes) | **uncheck everything** |
| Image fetchers | **uncheck everything** |
| Metadata savers / "Nfo saver" | **leave off** |

NFO *reading* needs no setting: Jellyfin always reads local NFO and always gives
it priority over remote providers — it cannot even be turned off. The
downloaders are unchecked only to stop pointless failed TVDB lookups on every
scan, and `<lockdata>true</lockdata>` in each file stops a hand-triggered
"Identify" from overwriting anything.

The "Nfo saver" being off is belt-and-braces: the bind mount is read-only, so
Jellyfin could not write into the library even if it were enabled. `course-import`
is the only writer.

## Troubleshooting

**The show appears but every episode is "Episode 1".** The season directory has
no `season.nfo`, or Jellyfin scanned mid-import. Re-run `course-import import`
and then Scan Library Files.

**An episode shows the wrong title.** The `.nfo` wins over the filename, so the
manifest is what to fix — not the file name. Edit it and re-run `import`; the
rename happens automatically.

**A lesson is in ingest but `status` says `not downloaded`.** Its filename stem
does not match the manifest `slug`. `course-import orphans <course>` lists
exactly these.

**Jellyfin cannot read the files.** They should be `root:media 0640` inside
directories that are `root:media 2770`. `course-import` sets this explicitly
rather than relying on the setgid bit, because ingest and library are on the
same dataset — so `mv` is a rename, and **a rename carries the file's original
ownership across regardless of setgid on the destination**. Files rsync'd in as
`root:root` would otherwise stay `root:root`, and Jellyfin (uid 964, group
`media`) could not read them.
