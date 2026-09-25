"""The nightly pass — deterministic, and loud when it fails.

IT DOES NOT CALL THE MODEL, and that absence is the design.  Every write-up of
this memory pattern that automated a "synthesis" or "compaction" step reported
the same outcome: the step failed silently, roughly half the time, and nobody
noticed for weeks because a background job that produces nothing looks exactly
like a background job with nothing to do.  One of them measured it — ~50% of
automated flushes timed out, exited quietly or wrote an empty file, and the
scheduled 6pm compile "literally never triggered once in production".

So this does only what can be checked by reading the tree:

  * rebuild index.md from the pages (the index is derived, never hand-written,
    and never written by the model either — an index the agent maintains is an
    index that drifts from the pages it indexes);
  * flag pages with no summary, which are invisible to retrieval because the
    index line is what the keyword match runs against;
  * flag pages not touched in `staleDays`;
  * flag duplicate titles, which is how the same fact ends up on two pages;
  * commit, if anything changed.

Non-zero exit on a broken tree, because under SN4 a failed oneshot on a timer
is silent and needs an alert pointed at it — there is one in
service-modules/monitoring.nix.

A model-driven pass may still be worth having. If it is ever added it should be
a command a person runs, not a timer.
"""

from __future__ import annotations

import argparse
import collections
import datetime as _dt
import os
import sys

from memory import INDEX, LOG, Wiki


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="mneme-lint", description=__doc__)
    ap.add_argument("--wiki", required=True)
    ap.add_argument("--stale-days", type=int, default=180)
    args = ap.parse_args(argv if argv is not None else sys.argv[1:])

    if not os.path.isdir(args.wiki):
        print(f"mneme-lint: no wiki at {args.wiki}", file=sys.stderr)
        return 1
    if not os.path.isdir(os.path.join(args.wiki, ".git")):
        print(
            f"mneme-lint: {args.wiki} is not a git repository — every fact the "
            f"agent writes is supposed to be a commit, so this is a real fault "
            f"and not cosmetic",
            file=sys.stderr,
        )
        return 1

    wiki = Wiki(args.wiki)
    pages = wiki.pages()
    problems: list[str] = []

    # Invisible to retrieval: the index line is what a keyword search reads.
    for p in pages:
        if not p.summary:
            problems.append(f"{p.path}: no summary — retrieval cannot see it")

    # The same fact on two pages.
    by_title = collections.defaultdict(list)
    for p in pages:
        by_title[p.title.strip().lower()].append(p.path)
    for title, paths in sorted(by_title.items()):
        if len(paths) > 1:
            problems.append(f"duplicate title {title!r}: {', '.join(paths)}")

    # Stale.  A warning, never a deletion: this module does not remove facts.
    cutoff = _dt.date.today() - _dt.timedelta(days=args.stale_days)
    for p in pages:
        if not p.updated:
            continue
        try:
            when = _dt.date.fromisoformat(p.updated)
        except ValueError:
            problems.append(f"{p.path}: unparseable updated: {p.updated!r}")
            continue
        if when < cutoff:
            problems.append(f"{p.path}: not touched since {p.updated}")

    changed = wiki.rebuild_index()
    if changed:
        wiki._append_log(f"lint rebuilt {INDEX} ({len(pages)} pages)")
        wiki._commit("mneme: lint — rebuild index", [INDEX, LOG])

    print(f"mneme-lint: {len(pages)} pages, index {'rebuilt' if changed else 'unchanged'}")
    for problem in problems:
        print(f"  ! {problem}")

    # Problems are REPORTED, not fatal.  A page without a summary is a thing to
    # fix at leisure; making the unit fail on it would put a permanent red
    # light on the dashboard and train everyone to ignore the alert — which is
    # exactly the failure M24b's hacs-deps-check note describes.  Only a broken
    # tree (above) exits non-zero.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
