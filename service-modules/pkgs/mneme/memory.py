"""The wiki — a git-versioned markdown memory.

WHY A DIRECTORY OF MARKDOWN AND NOT A VECTOR STORE.  The pattern here is the
LLM-wiki one: an `index.md` naming every page in one line each, pages grouped by
kind, and retrieval by reading the index and then the pages it points at.  No
embeddings, no similarity search, no second database.  Its stated working range
is ~150-200 dense pages, which a household will not exceed for years, and
inside that range it is exact rather than approximate: a page either is in the
index or it is not.

WHY GIT.  Every fact the agent writes is a commit, so "what does it think it
knows" is `git log`, "who told it that" is `git show`, and "that is wrong" is
`git revert`.  That is the whole audit story and it needed no code.

THE CONSTITUTION IS NOT IN HERE.  SOUL.md and IRON_RULES.md are symlinks into
the Nix store and this module refuses to write them.  The line is the same one
`configuration.yaml` and `.storage` draw in the hub next door: the constitution
is configuration, the wiki is state.

DATES ON EVERYTHING.  Each written line and each page's front matter carries
`[YYYY-MM-DD]`.  That is the single habit the post-mortems of these systems all
converge on, and the reason is mechanical rather than aesthetic: it makes the
nightly pass a `grep` over today instead of a parse of a conversation
transcript, which is the component that failed ~50% of the time in the write-up
this design borrows from.
"""

from __future__ import annotations

import datetime as _dt
import logging
import os
import re
import subprocess
from dataclasses import dataclass

_LOG = logging.getLogger("mneme.memory")

# The directories a page may live in.  A flat namespace would work and would
# rot: the point of naming the buckets is that the index stays readable when
# there are eighty pages in it.
SECTIONS = {
    "00-core": "hard facts about the house that rarely change",
    "01-people": "one page per member of the household",
    "02-devices": "entity ids, rooms, quirks — what Assist gets wrong twice",
    "03-routines": "we do X at Y",
    "04-facts": "dated one-liners that have not earned a page yet",
}

# Written by the agent, not by hand, and excluded from being written AS pages.
INDEX = "index.md"
LOG = "log.md"

# Store-managed, symlinked in, refused by every write path here.
CONSTITUTION = ("SOUL.md", "IRON_RULES.md")

# ── 00-core IS READ-ONLY TO THE AGENT, AND THAT IS THE INJECTION BOUNDARY ────
#
# Anything the agent learns from a device name, a calendar entry, an article
# title or a guest speaking to it can end up proposed as a page — and a page is
# read back as context on every later turn.  So the section holding the facts
# that shape its behaviour is one a person edits and the agent cannot.
#
# This is the gate every write-up of this pattern flags and it is much cheaper
# to build now than to retrofit after something has been written into core.
AGENT_WRITABLE = tuple(s for s in SECTIONS if s != "00-core")

_SLUG = re.compile(r"^[a-z0-9][a-z0-9-]*$")


def today() -> str:
    return _dt.date.today().isoformat()


class MemoryError(Exception):
    """A refusal the model should see, not a crash."""


@dataclass
class Page:
    path: str          # "01-people/lutz.md", relative to the wiki root
    title: str
    summary: str
    updated: str


class Wiki:
    def __init__(self, root: str, author: str = "mneme <mneme@goclan.org>") -> None:
        self.root = root
        self.author = author

    # ── paths ───────────────────────────────────────────────────────────────
    def _resolve(self, rel: str, *, for_write: bool) -> str:
        """Validate a caller-supplied path and return it absolute.

        EVERY REFUSAL HERE IS A MODEL-FACING MESSAGE.  The caller is a language
        model that will have invented the path from a prompt, so a refusal has
        to say what to do instead; a bare exception produces a tool result the
        model cannot act on and it will simply try again the same way.
        """
        rel = (rel or "").strip().lstrip("/")
        if not rel:
            raise MemoryError("No path given.")
        if rel in CONSTITUTION:
            raise MemoryError(
                f"{rel} is part of the constitution and is read-only. It is "
                f"managed in the repository, not in memory."
            )
        if rel in (INDEX, LOG):
            raise MemoryError(
                f"{rel} is maintained automatically. Write a page under one of "
                f"{', '.join(AGENT_WRITABLE)} instead."
            )
        if not rel.endswith(".md"):
            rel += ".md"

        parts = rel.split("/")
        if len(parts) != 2:
            raise MemoryError(
                "A page path is '<section>/<name>.md'. Sections: "
                + ", ".join(SECTIONS)
            )
        section, name = parts
        if section not in SECTIONS:
            raise MemoryError(
                f"Unknown section '{section}'. Sections: " + ", ".join(SECTIONS)
            )
        if for_write and section not in AGENT_WRITABLE:
            raise MemoryError(
                f"'{section}' is read-only — a person maintains it. Write to "
                + ", ".join(AGENT_WRITABLE)
                + " instead."
            )
        stem = name[:-3]
        if not _SLUG.match(stem):
            raise MemoryError(
                f"'{name}' is not a usable page name. Use lower-case letters, "
                f"digits and hyphens, e.g. 'dishwasher.md'."
            )

        # Belt and braces.  The checks above already make traversal
        # unrepresentable; this catches any future path that reaches here by
        # another route, because the cost of being wrong is writing outside the
        # wiki.
        full = os.path.realpath(os.path.join(self.root, section, name))
        if not full.startswith(os.path.realpath(self.root) + os.sep):
            raise MemoryError("Path escapes the wiki.")
        return full

    def _rel(self, full: str) -> str:
        return os.path.relpath(full, self.root)

    # ── reading ─────────────────────────────────────────────────────────────
    def pages(self) -> list[Page]:
        out: list[Page] = []
        for section in SECTIONS:
            d = os.path.join(self.root, section)
            if not os.path.isdir(d):
                continue
            for name in sorted(os.listdir(d)):
                if not name.endswith(".md"):
                    continue
                full = os.path.join(d, name)
                out.append(self._page_meta(full))
        return out

    def _page_meta(self, full: str) -> Page:
        title = summary = updated = ""
        try:
            with open(full, encoding="utf-8") as fh:
                for line in fh:
                    if line.startswith("title:"):
                        title = line.split(":", 1)[1].strip()
                    elif line.startswith("summary:"):
                        summary = line.split(":", 1)[1].strip()
                    elif line.startswith("updated:"):
                        updated = line.split(":", 1)[1].strip()
                    elif line.startswith("# ") and not title:
                        title = line[2:].strip()
                    if title and summary and updated:
                        break
        except OSError:
            pass
        rel = self._rel(full)
        return Page(
            path=rel,
            title=title or os.path.basename(full)[:-3],
            summary=summary,
            updated=updated,
        )

    def read(self, rel: str) -> str:
        full = self._resolve(rel, for_write=False)
        if not os.path.exists(full):
            raise MemoryError(f"No page at {self._rel(full)}.")
        with open(full, encoding="utf-8") as fh:
            return fh.read()

    def index_text(self) -> str:
        p = os.path.join(self.root, INDEX)
        if not os.path.exists(p):
            return ""
        with open(p, encoding="utf-8") as fh:
            return fh.read()

    # THERE IS DELIBERATELY NO constitution() HERE.  SOUL.md and IRON_RULES.md
    # are read from the Nix store by the server (`--soul-dir`) and are not
    # copied into the wiki, so there is exactly one source for them.  They
    # appear in CONSTITUTION above only so that every write path can refuse a
    # model that tries to edit them by name.

    def search(self, query: str, limit: int = 8) -> list[tuple[str, str]]:
        """Case-insensitive term search over titles, summaries and bodies.

        NOT A RANKING FUNCTION AND NOT PRETENDING TO BE ONE.  It scores a page
        by how many of the query's terms appear in it, with title and summary
        hits worth more than body hits.  At this corpus size that is enough,
        and it has the property an embedding search does not: you can predict
        what it will return by reading the page.
        """
        terms = [t for t in re.split(r"\W+", (query or "").lower()) if len(t) > 2]
        if not terms:
            return []
        scored: list[tuple[int, str, str]] = []
        for page in self.pages():
            try:
                body = self.read(page.path).lower()
            except MemoryError:
                continue
            head = (page.title + " " + page.summary).lower()
            score = sum(3 for t in terms if t in head) + sum(
                1 for t in terms if t in body
            )
            if score:
                scored.append((score, page.path, self._excerpt(body, terms)))
        scored.sort(key=lambda r: (-r[0], r[1]))
        return [(p, e) for _, p, e in scored[:limit]]

    @staticmethod
    def _excerpt(body: str, terms: list[str], width: int = 240) -> str:
        for t in terms:
            i = body.find(t)
            if i >= 0:
                start = max(0, i - width // 3)
                return " ".join(body[start : start + width].split())
        return " ".join(body[:width].split())

    # ── writing ─────────────────────────────────────────────────────────────
    def write(self, rel: str, content: str, reason: str, source: str = "") -> str:
        full = self._resolve(rel, for_write=True)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        page_rel = self._rel(full)
        body = self._with_front_matter(page_rel, content, source)
        with open(full, "w", encoding="utf-8") as fh:
            fh.write(body)
        self._append_log(f"write {page_rel} — {reason}")
        self._commit(f"mneme: {reason}", [page_rel, LOG])
        return page_rel

    def append(self, rel: str, line: str, reason: str, source: str = "") -> str:
        full = self._resolve(rel, for_write=True)
        page_rel = self._rel(full)
        if not os.path.exists(full):
            return self.write(rel, f"- [{today()}] {line.strip()}", reason, source)
        with open(full, "a", encoding="utf-8") as fh:
            fh.write(f"\n- [{today()}] {line.strip()}\n")
        self._touch_updated(full)
        self._append_log(f"append {page_rel} — {reason}")
        self._commit(f"mneme: {reason}", [page_rel, LOG])
        return page_rel

    def _with_front_matter(self, page_rel: str, content: str, source: str) -> str:
        content = content.strip()
        if content.startswith("---"):
            return content + "\n"
        title = os.path.basename(page_rel)[:-3].replace("-", " ")
        first = next(
            (l.strip() for l in content.splitlines() if l.strip() and not l.startswith("#")),
            "",
        )
        summary = " ".join(first.split())[:160]
        lines = [
            "---",
            f"title: {title}",
            f"summary: {summary}",
            f"updated: {today()}",
        ]
        if source:
            # WHERE THIS CAME FROM, kept because a wiki page is read back as
            # context and therefore has to be attributable.  IRON_RULES tells
            # the model that page content is data; this is what lets a person
            # check who supplied it.
            lines.append(f"source: {' '.join(source.split())[:200]}")
        lines += ["---", "", content, ""]
        return "\n".join(lines)

    def _touch_updated(self, full: str) -> None:
        try:
            with open(full, encoding="utf-8") as fh:
                text = fh.read()
        except OSError:
            return
        new, n = re.subn(r"(?m)^updated:.*$", f"updated: {today()}", text, count=1)
        if n:
            with open(full, "w", encoding="utf-8") as fh:
                fh.write(new)

    def _append_log(self, message: str) -> None:
        p = os.path.join(self.root, LOG)
        with open(p, "a", encoding="utf-8") as fh:
            fh.write(f"- [{today()}] {message}\n")

    # ── index ───────────────────────────────────────────────────────────────
    def rebuild_index(self) -> bool:
        """Regenerate index.md from the pages. Returns True if it changed.

        DERIVED, NEVER HAND-EDITED, and never written by the model either: an
        index the agent maintains is an index that drifts from the pages, and
        the index is the thing retrieval depends on.  The nightly lint is the
        only writer.
        """
        lines = [
            "---",
            "title: index",
            f"updated: {today()}",
            "---",
            "",
            "# Index",
            "",
            "One line per page. This file is generated — edit the pages instead.",
            "",
        ]
        pages = self.pages()
        for section, blurb in SECTIONS.items():
            in_section = [p for p in pages if p.path.startswith(section + "/")]
            if not in_section:
                continue
            lines.append(f"## {section} — {blurb}")
            lines.append("")
            for p in in_section:
                summary = p.summary or "(no summary)"
                stamp = f" [{p.updated}]" if p.updated else ""
                lines.append(f"- `{p.path}` — {p.title}: {summary}{stamp}")
            lines.append("")
        text = "\n".join(lines)

        p = os.path.join(self.root, INDEX)
        old = ""
        if os.path.exists(p):
            with open(p, encoding="utf-8") as fh:
                old = fh.read()
        if old == text:
            return False
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(text)
        return True

    # ── git ─────────────────────────────────────────────────────────────────
    def _git(self, *args: str, check: bool = True) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["git", "-C", self.root, *args],
            check=check,
            capture_output=True,
            text=True,
        )

    def _commit(self, message: str, paths: list[str]) -> None:
        """One commit per write.

        FAILURE HERE IS LOGGED AND NOT RAISED, deliberately.  The page is
        already on disk; refusing the whole tool call because git was unhappy
        would lose a fact the household just supplied in order to preserve an
        audit trail of facts.  A repository that stops committing shows up in
        `mneme-lint`, which is a unit with an alert on it.
        """
        try:
            self._git("add", "--", *paths)
            if not self._git("diff", "--cached", "--quiet", check=False).returncode:
                return  # nothing staged: identical content rewritten
            self._git(
                "-c", f"user.name={self.author.split('<')[0].strip()}",
                "-c", f"user.email={self.author.split('<')[1].rstrip('>')}",
                "commit", "-q", "-m", message,
            )
        except (subprocess.CalledProcessError, OSError, IndexError) as err:
            _LOG.error("git commit failed for %s: %s", paths, err)
