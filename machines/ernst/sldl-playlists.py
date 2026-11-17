"""Rebuild the sldl batch's Spotify playlists as .m3u files Navidrome imports.

Each CSV in CSV_DIR (a Spotify export: Song, Artist, Album, ISRC, ...) becomes
OUT_DIR/<csv name>.m3u, listing the library files that match its rows.  Tracks
are matched against Navidrome's OWN database, read-only, because Navidrome has
already read every file's tags — this script never opens an audio file.

Matching, in order:
  1. ISRC, when the file carries one (about a third of the rows, measured)
  2. first artist + title, both normalised (case, accents, punctuation,
     "(Remastered 2011)", " - Live", "feat. X")
  3. title, with one artist name containing the other
Among several files for one key, the one on the row's album wins, then one
inside an album folder, then a lossless one.

A row that matches nothing is left out; the playlist grows on later runs as
the batch's downloads are staged and published.  A file is rewritten only
when its content changes, because Navidrome re-imports a playlist whenever
its mtime moves.  Only files carrying MARKER are ever replaced or removed,
so a hand-made playlist in OUT_DIR is left alone.
"""

import csv
import json
import os
import re
import sqlite3
import sys
import tempfile
import unicodedata
from pathlib import Path

DB = os.environ.get("NAVIDROME_DB", "/srv/state/navidrome/navidrome.db")
CSV_DIR = Path(os.environ.get("CSV_DIR", "/srv/media/soulseek/sldl/csv"))
OUT_DIR = Path(os.environ.get("OUT_DIR", "/srv/media/library/music/_playlists"))
DRY = os.environ.get("DRY", "0") != "0"
MARKER = "#GENERATED-BY:sldl-playlists"
LOSSLESS = {"flac", "alac", "wav", "aiff", "ape", "wv"}


def norm(s):
    s = unicodedata.normalize("NFKD", s or "").encode("ascii", "ignore").decode().lower()
    s = re.sub(r"\s*[\(\[].*?[\)\]]", "", s)
    s = re.sub(r"\s+-\s+.*$", "", s)
    s = re.sub(r"\b(feat|ft)\b\.?.*$", "", s)
    return re.sub(r"[^a-z0-9]+", "", s)


def first_artist(s):
    return re.split(r"\s*(?:,|;|&| feat\.? | ft\.? | x )\s*", s or "", maxsplit=1)[0]


def load_library():
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    libs = dict(con.execute("select id, path from library"))
    by_isrc, by_at, by_t = {}, {}, {}
    rows = con.execute(
        "select library_id, path, title, artist, album, suffix, tags "
        "from media_file where missing = 0"
    )
    for lib_id, path, title, artist, album, suffix, tags in rows:
        f = {
            "path": os.path.join(libs[lib_id], path),
            "album": norm(album),
            "deep": path.count("/") >= 2,
            "lossless": (suffix or "").lower() in LOSSLESS,
        }
        try:
            t = json.loads(tags or "{}")
        except ValueError:
            t = {}
        for i in t.get("isrc") or []:
            v = i.get("value") if isinstance(i, dict) else i
            if v:
                by_isrc.setdefault(v.upper(), []).append(f)
        by_at.setdefault((norm(first_artist(artist)), norm(title)), []).append(f)
        by_t.setdefault(norm(title), []).append((norm(artist), f))
    con.close()
    return by_isrc, by_at, by_t


def best(cands, album):
    return max(cands, key=lambda f: (f["album"] == album, f["deep"], f["lossless"]))


def match(row, by_isrc, by_at, by_t):
    album = norm(row.get("Album"))
    c = by_isrc.get((row.get("ISRC") or "").strip().upper())
    if c:
        return best(c, album)
    a, t = norm(first_artist(row.get("Artist"))), norm(row.get("Song"))
    if not t:
        return None
    c = by_at.get((a, t))
    if c:
        return best(c, album)
    c = [f for na, f in by_t.get(t, []) if a and na and (a in na or na in a)]
    return best(c, album) if c else None


def write_if_changed(path, text):
    if path.exists() and path.read_text(encoding="utf-8") == text:
        return False
    if not DRY:
        fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".tmp-", suffix=".m3u")
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.chmod(tmp, 0o664)
        os.replace(tmp, path)
    return True


def main():
    by_isrc, by_at, by_t = load_library()
    if not DRY:
        OUT_DIR.mkdir(mode=0o2770, exist_ok=True)
    wanted, total, hit, changed = set(), 0, 0, 0
    for csv_path in sorted(CSV_DIR.glob("*.csv")):
        name = csv_path.stem
        with csv_path.open(encoding="utf-8-sig", newline="") as fh:
            rows = list(csv.DictReader(fh))
        lines, seen = [], set()
        for row in rows:
            f = match(row, by_isrc, by_at, by_t)
            if f and f["path"] not in seen:
                seen.add(f["path"])
                lines.append(f["path"])
        total += len(rows)
        hit += len(lines)
        out = OUT_DIR / (name.replace("/", "_") + ".m3u")
        wanted.add(out.name)
        text = "\n".join(["#EXTM3U", f"#PLAYLIST:{name}", MARKER, *lines]) + "\n"
        if write_if_changed(out, text):
            changed += 1
            print(f"  {len(lines):4d}/{len(rows):<4d} {name}")
    if OUT_DIR.is_dir():
        for old in OUT_DIR.glob("*.m3u"):
            if old.name not in wanted and MARKER in old.read_text(encoding="utf-8", errors="replace"):
                print(f"  removed {old.name} (its CSV is gone)")
                if not DRY:
                    old.unlink()
    print(
        f"{len(wanted)} playlists, {hit} of {total} rows matched "
        f"({100 * hit // max(total, 1)}%), {changed} file(s) "
        f"{'would change (dry run)' if DRY else 'written'}"
    )


if __name__ == "__main__":
    sys.exit(main())
