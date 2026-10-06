"""The tools mneme owns, as opposed to the ones Home Assistant owns.

THE SPLIT IS THE WHOLE IDEA.  A request from Home Assistant arrives with HA's
own Assist tools in it — HassTurnOn and friends.  mneme appends its own, and
when the model calls one it is executed HERE and the loop continues; when the
model calls one of HA's, it goes back to HA untouched.  Neither side knows the
other's tools exist.

WHY TOOLS AND NOT RAG.  Memory is retrieved by injection (see the server) so
that recall does not depend on the model choosing to look — M11 measured what
that costs.  But WRITING, searching the web and making a picture are actions,
and an action the model takes on purpose is exactly what a tool is for.

THE THREE HAVE DIFFERENT COSTS AND THAT IS STATED IN THEIR DESCRIPTIONS.
Memory is free.  Web search leaves the house, through SearXNG, which is the
only thing on this host with a door to the open internet.  Image generation
EVICTS THE RESIDENT 21 GiB LANGUAGE MODEL, because llama-swap runs its GPU
backends in an exclusive group — so every picture stalls this agent and the
coding agent for a reload each way.  The model is told so, because a model that
does not know an action is expensive will take it for a whim.
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import re
import time
import urllib.parse
import uuid
from typing import Any

import aiohttp

from memory import MemoryError, Wiki, today

_LOG = logging.getLogger("mneme.tools")

# What a tool result must not exceed.  A tool that returns 40 KB of search
# results spends the whole context window on one turn and the model then has no
# room to answer — the failure looks like the model ignoring the results.
MAX_RESULT_CHARS = 6000


def _fn(name: str, description: str, properties: dict, required: list[str]) -> dict:
    return {
        "type": "function",
        "function": {
            "name": name,
            "description": description,
            "parameters": {
                "type": "object",
                "properties": properties,
                "required": required,
            },
        },
    }


class Toolbox:
    """mneme's own tools, and their execution."""

    def __init__(
        self,
        wiki: Wiki | None,
        *,
        search_url: str = "",
        image: dict[str, Any] | None = None,
        documents_url: str = "",
        documents_token: str = "",
        session_factory=None,
    ) -> None:
        self.wiki = wiki
        self.search_url = search_url.rstrip("/")
        self.image = image or {}
        self.documents_url = documents_url.rstrip("/")
        self.documents_token = documents_token
        self._session_factory = session_factory
        # Resolved once per process from /api/correspondents/ and
        # /api/document_types/, which a household has a handful of.  The search
        # response carries ids, not names, and an id is no use to the model.
        self._doc_names: dict[str, dict[int, str]] = {}

    # ── declaration ─────────────────────────────────────────────────────────
    def schemas(self) -> list[dict]:
        out: list[dict] = []
        if self.wiki is not None:
            out += [
                _fn(
                    "memory_search",
                    "Search your long-term memory of this household for pages "
                    "matching a query. Free and fast; use it whenever a "
                    "question might depend on something you were told before.",
                    {"query": {"type": "string", "description": "Words to look for."}},
                    ["query"],
                ),
                _fn(
                    "memory_read",
                    "Read one page of your memory in full, by the path shown in "
                    "the index or in a search result.",
                    {"path": {"type": "string", "description": "e.g. 01-people/lutz.md"}},
                    ["path"],
                ),
                _fn(
                    "memory_write",
                    "Create or replace a page of your memory. Use this for a "
                    "durable fact about the household, a person, a device or a "
                    "routine. Every write is recorded and reviewable, so write "
                    "what you were actually told and not what you inferred.",
                    {
                        "path": {
                            "type": "string",
                            "description": "<section>/<name>.md — sections: "
                            "01-people, 02-devices, 03-routines, 04-facts",
                        },
                        "content": {"type": "string", "description": "Markdown body."},
                        "reason": {
                            "type": "string",
                            "description": "Short note on why, for the commit message.",
                        },
                    },
                    ["path", "content", "reason"],
                ),
                _fn(
                    "memory_append",
                    "Add one dated line to an existing page. Prefer this over "
                    "rewriting a page when you are adding a fact rather than "
                    "correcting one.",
                    {
                        "path": {"type": "string"},
                        "line": {"type": "string", "description": "One sentence."},
                        "reason": {"type": "string"},
                    },
                    ["path", "line", "reason"],
                ),
            ]

        if self.search_url:
            out.append(
                _fn(
                    "web_search",
                    "Search the web. Use it for anything you cannot know from "
                    "memory or from the house: news, opening hours, facts that "
                    "change. Results are summaries and links, not full pages.",
                    {
                        "query": {"type": "string"},
                        "count": {
                            "type": "integer",
                            "description": "How many results, 1-10. Default 5.",
                        },
                    },
                    ["query"],
                )
            )

        if self.documents_url and self.documents_token:
            out.append(
                _fn(
                    "document_search",
                    "Search the household's scanned paper — letters, bills, "
                    "contracts, insurance, medical and official post. Use it "
                    "for anything that would have arrived on paper. Returns "
                    "titles and the matching lines, NOT whole documents: to "
                    "answer from a document you must then read it.",
                    {
                        "query": {
                            "type": "string",
                            "description": (
                                "Words that appear IN the document. This is a "
                                "full-text search over scanned text, not a "
                                "question — search 'Versicherung Beitrag', "
                                "not 'what does my insurance cost'."
                            ),
                        },
                        "limit": {
                            "type": "integer",
                            "description": "How many documents, 1-10. Default 5.",
                        },
                    },
                    ["query"],
                )
            )
            out.append(
                _fn(
                    "document_read",
                    "Read the text of one document found by document_search, "
                    "by its id. Long documents come back in numbered parts; "
                    "the reply says whether more remain, and you ask for the "
                    "next part by number.",
                    {
                        "document_id": {
                            "type": "integer",
                            "description": "The id from document_search.",
                        },
                        "part": {
                            "type": "integer",
                            "description": "Which part to read. Default 1.",
                        },
                    },
                    ["document_id"],
                )
            )

        if self.image.get("url"):
            out.append(
                _fn(
                    "generate_image",
                    "Generate a picture from a text description and return a "
                    "link to it. EXPENSIVE: it takes the graphics card away "
                    "from the language model for about a minute, so only do it "
                    "when a picture is actually what was asked for.",
                    {
                        "prompt": {
                            "type": "string",
                            "description": "What to draw, in English, in detail.",
                        }
                    },
                    ["prompt"],
                )
            )
        return out

    def owns(self, name: str) -> bool:
        return name in {s["function"]["name"] for s in self.schemas()}

    # ── execution ───────────────────────────────────────────────────────────
    async def call(self, name: str, args: dict[str, Any], *, source: str = "") -> str:
        try:
            if name == "memory_search":
                return self._memory_search(args.get("query", ""))
            if name == "memory_read":
                return _clip(self.wiki.read(args.get("path", "")))
            if name == "memory_write":
                rel = self.wiki.write(
                    args.get("path", ""),
                    args.get("content", ""),
                    args.get("reason", "no reason given"),
                    source=source,
                )
                return f"Written and committed: {rel}"
            if name == "memory_append":
                rel = self.wiki.append(
                    args.get("path", ""),
                    args.get("line", ""),
                    args.get("reason", "no reason given"),
                    source=source,
                )
                return f"Appended and committed: {rel}"
            if name == "web_search":
                return await self._web_search(
                    args.get("query", ""), int(args.get("count") or 5)
                )
            if name == "document_search":
                return await self._document_search(
                    args.get("query", ""), int(args.get("limit") or 5)
                )
            if name == "document_read":
                return await self._document_read(
                    int(args.get("document_id") or 0), int(args.get("part") or 1)
                )
            if name == "generate_image":
                return await self._generate_image(args.get("prompt", ""))
        except MemoryError as err:
            # A refusal, phrased for the model.
            return f"Refused: {err}"
        except Exception as err:  # noqa: BLE001 - a tool must not kill the turn
            _LOG.exception("tool %s failed", name)
            return f"The tool failed: {type(err).__name__}: {err}"
        return f"Unknown tool {name}."

    # ── memory ──────────────────────────────────────────────────────────────
    def _memory_search(self, query: str) -> str:
        hits = self.wiki.search(query)
        if not hits:
            return "Nothing in memory matches that."
        return _clip(
            "\n".join(f"- `{path}` — {excerpt}" for path, excerpt in hits)
        )

    # ── documents ───────────────────────────────────────────────────────────
    #
    # Paperless-ngx's REST API over the `doc0` leg (M32b).  The account behind
    # the token is NOT a superuser and holds four `view_*` permissions, which
    # is measured rather than asserted — DELETE, PATCH and the upload endpoint
    # all answer 403 to this token.
    #
    # WHY FULL-TEXT AND NOT DATES.  An earlier draft took `created_after` /
    # `correspondent` filters.  The first scan through this pipeline came back
    # with `created = 1983-10-19` — paperless guesses a date out of the OCR
    # text and gets it wrong — so a date filter here would silently exclude the
    # documents it was meant to find.  The date that matters is the one written
    # ON the paper, and that is in the text, which `document_read` returns.
    # Filters can come back when the corpus is big enough to need them and the
    # classifier has had something to learn from.

    def _doc_headers(self) -> dict[str, str]:
        return {"Authorization": f"Token {self.documents_token}"}

    async def _doc_get(self, path: str, params: dict[str, Any]) -> Any:
        url = f"{self.documents_url}{path}?" + urllib.parse.urlencode(params)
        session = self._session_factory()
        async with session.get(
            url, headers=self._doc_headers(), timeout=aiohttp.ClientTimeout(total=30)
        ) as resp:
            if resp.status == 401 or resp.status == 403:
                # Worth its own message: this is the one failure a person can
                # fix, and it does not look like an auth problem from outside.
                raise RuntimeError(
                    "the document archive refused mneme's token "
                    f"(HTTP {resp.status}); either paperless-provision failed "
                    "to write it into the database, or this daemon could not "
                    "read it — check mneme's own startup log first"
                )
            if resp.status != 200:
                raise RuntimeError(f"document archive returned HTTP {resp.status}")
            return await resp.json(content_type=None)

    async def _doc_name_map(self, kind: str) -> dict[int, str]:
        """id -> name for correspondents / document types, fetched once."""
        if kind in self._doc_names:
            return self._doc_names[kind]
        try:
            payload = await self._doc_get(f"/api/{kind}/", {"page_size": 200})
            self._doc_names[kind] = {
                int(r["id"]): str(r.get("name", "")) for r in payload.get("results", [])
            }
        except Exception:  # noqa: BLE001 - a missing name must not kill a search
            self._doc_names[kind] = {}
        return self._doc_names[kind]

    @staticmethod
    def _strip_highlight(markup: str) -> str:
        """Paperless marks matches with <span class="match termN">…</span>.

        The model does not need the markup, but it DOES need to know which
        words matched, so the span becomes *emphasis* rather than nothing.
        """
        text = re.sub(r'<span class="match[^"]*">(.*?)</span>', r"*\1*", markup or "")
        text = re.sub(r"<[^>]+>", "", text)
        return " ".join(text.split())

    async def _document_search(self, query: str, limit: int) -> str:
        if not query.strip():
            return "Give me words that appear in the document."
        limit = max(1, min(limit, 10))

        payload = await self._doc_get(
            "/api/documents/", {"query": query, "page_size": limit}
        )
        results = payload.get("results") or []
        if not results:
            return (
                f"Nothing in the paper archive matches {query!r}. "
                "It may not be scanned yet, or the words on the page may differ."
            )

        corr = await self._doc_name_map("correspondents")
        types = await self._doc_name_map("document_types")

        lines = [f"{payload.get('count', len(results))} match(es); showing {len(results)}."]
        for r in results:
            bits = [f"[id {r.get('id')}] {r.get('title') or '(untitled)'}"]
            who = corr.get(r.get("correspondent")) if r.get("correspondent") else None
            what = types.get(r.get("document_type")) if r.get("document_type") else None
            if who:
                bits.append(f"from {who}")
            if what:
                bits.append(what)
            # Paperless's own guess, and labelled as one — see the note above.
            if r.get("created"):
                bits.append(f"filed {r['created']} (auto-detected, may be wrong)")
            lines.append(" · ".join(bits))

            hit = r.get("__search_hit__") or {}
            excerpt = self._strip_highlight(hit.get("highlights", ""))
            if excerpt:
                lines.append(f"    …{excerpt}…")
        lines.append("Use document_read with an id to read one.")
        return _clip("\n".join(lines))

    async def _document_read(self, document_id: int, part: int) -> str:
        if document_id <= 0:
            return "Give me a document id from document_search."
        part = max(1, part)

        payload = await self._doc_get(f"/api/documents/{document_id}/", {})
        content = (payload.get("content") or "").strip()
        title = payload.get("title") or "(untitled)"
        if not content:
            return f"[id {document_id}] {title} has no extracted text."

        chunk = page_of(content, part)
        if chunk is None:
            total = page_count(content)
            return f"[id {document_id}] {title} has only {total} part(s)."
        text, part, total = chunk

        head = f"[id {document_id}] {title} — part {part} of {total}"
        tail = (
            f"\n\n(part {part} of {total}; ask for part {part + 1} to continue)"
            if part < total
            else f"\n\n(end of document, {total} part(s) total)"
        )
        return head + "\n\n" + text + tail

    # ── web ─────────────────────────────────────────────────────────────────
    async def _web_search(self, query: str, count: int) -> str:
        """SearXNG's JSON API.

        `format=json` has to be enabled in SearXNG's own settings, and it is on
        this host — the role's own troubleshooting section documents the same
        call.  If this ever returns HTML instead, that is the setting and not
        this code.
        """
        count = max(1, min(count, 10))
        url = f"{self.search_url}/search?" + urllib.parse.urlencode(
            {"q": query, "format": "json", "safesearch": "0"}
        )
        session = self._session_factory()
        async with session.get(url, timeout=aiohttp.ClientTimeout(total=30)) as resp:
            if resp.status != 200:
                return f"Search failed: HTTP {resp.status}."
            payload = await resp.json(content_type=None)

        results = payload.get("results") or []
        if not results:
            answers = payload.get("answers") or []
            if answers:
                return _clip("\n".join(str(a) for a in answers))
            return "No results."
        lines = []
        for r in results[:count]:
            title = " ".join(str(r.get("title", "")).split())
            body = " ".join(str(r.get("content", "")).split())
            link = r.get("url", "")
            lines.append(f"- {title}\n  {body}\n  {link}")
        return _clip("\n".join(lines))

    # ── images ──────────────────────────────────────────────────────────────
    async def _generate_image(self, prompt: str) -> str:
        """Queue an SDXL workflow on ComfyUI, wait, and publish the PNG.

        THE PICTURE IS SERVED BY HOME ASSISTANT, not by mneme.  mneme listens
        on a point-to-point ULA that only the hub can reach, so a URL it served
        itself would be unreachable from the browser that has to display it.
        Home Assistant serves its own `www/` at `/local/`, that directory is on
        this host, and the hub is already behind Traefik with a public name —
        so writing the file there is the only delivery that needs no new
        listener, no new route and no new hostname.
        """
        if not prompt.strip():
            return "Refused: no prompt."
        base = self.image["url"].rstrip("/")
        session = self._session_factory()

        workflow = build_sdxl_workflow(
            prompt=prompt,
            checkpoint=self.image.get("checkpoint", "sd_xl_base_1.0.safetensors"),
            steps=int(self.image.get("steps", 25)),
            width=int(self.image.get("width", 1024)),
            height=int(self.image.get("height", 1024)),
            negative=self.image.get("negative", ""),
        )

        async with session.post(
            f"{base}/prompt",
            json={"prompt": workflow},
            timeout=aiohttp.ClientTimeout(total=120),
        ) as resp:
            if resp.status != 200:
                detail = (await resp.text())[:300]
                return f"Image generation refused by ComfyUI: HTTP {resp.status} {detail}"
            queued = await resp.json(content_type=None)
        prompt_id = queued.get("prompt_id")
        if not prompt_id:
            return "ComfyUI accepted the request but returned no prompt id."

        # Poll.  A first generation includes loading a 6.9 GiB checkpoint AND
        # evicting the language model, so the ceiling is generous; the interval
        # is not, because a household asking for a picture is waiting.
        deadline = time.monotonic() + float(self.image.get("timeout", 600))
        outputs = None
        while time.monotonic() < deadline:
            await asyncio.sleep(2)
            async with session.get(
                f"{base}/history/{prompt_id}",
                timeout=aiohttp.ClientTimeout(total=30),
            ) as resp:
                if resp.status != 200:
                    continue
                history = await resp.json(content_type=None)
            entry = history.get(str(prompt_id)) or {}
            status = (entry.get("status") or {}).get("status_str")
            if status == "error":
                return "ComfyUI reported an error generating the image."
            if entry.get("outputs"):
                outputs = entry["outputs"]
                break
        if not outputs:
            return "Image generation timed out."

        images = [
            img
            for node in outputs.values()
            for img in (node.get("images") or [])
            if img.get("filename")
        ]
        if not images:
            return "ComfyUI finished but produced no image."
        img = images[0]

        view = f"{base}/view?" + urllib.parse.urlencode(
            {
                "filename": img["filename"],
                "subfolder": img.get("subfolder", ""),
                "type": img.get("type", "output"),
            }
        )
        async with session.get(
            view, timeout=aiohttp.ClientTimeout(total=120)
        ) as resp:
            if resp.status != 200:
                return f"Could not fetch the finished image: HTTP {resp.status}."
            blob = await resp.read()

        name = f"{today()}-{uuid.uuid4().hex[:8]}.png"
        out_dir = self.image["outputDir"]
        try:
            os.makedirs(out_dir, exist_ok=True)
            tmp = os.path.join(out_dir, "." + name)
            with open(tmp, "wb") as fh:
                fh.write(blob)
            os.chmod(tmp, 0o644)
            os.replace(tmp, os.path.join(out_dir, name))
        except OSError as err:
            return f"Could not publish the image: {err}"

        url = self.image["publicBase"].rstrip("/") + "/" + name
        return f"Image ready: {url}"


def build_sdxl_workflow(
    *,
    prompt: str,
    checkpoint: str,
    steps: int,
    width: int,
    height: int,
    negative: str = "",
) -> dict:
    """The minimal SDXL graph, in ComfyUI's API format.

    HAND-WRITTEN RATHER THAN EXPORTED, because an exported workflow carries
    node positions, widget indices and a frontend version, and the thing that
    breaks it is the checkpoint name being substituted in by string replacement
    — which is precisely the failure Open WebUI's `COMFYUI_WORKFLOW_NODES`
    exists to paper over.  Six nodes built from typed arguments cannot have
    that failure.

    `--use-split-cross-attention` is NOT set here and must not be: it is a
    ComfyUI process flag, already applied by roles.imagegen, and without it
    this stack returns images that are sharp, detailed and unrelated to the
    prompt.  See service-modules/local-ai.md.
    """
    return {
        "1": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {"ckpt_name": checkpoint},
        },
        "2": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": prompt, "clip": ["1", 1]},
        },
        "3": {
            "class_type": "CLIPTextEncode",
            "inputs": {"text": negative, "clip": ["1", 1]},
        },
        "4": {
            "class_type": "EmptyLatentImage",
            "inputs": {"width": width, "height": height, "batch_size": 1},
        },
        "5": {
            "class_type": "KSampler",
            "inputs": {
                "seed": int.from_bytes(os.urandom(4), "big"),
                "steps": steps,
                "cfg": 7.0,
                "sampler_name": "dpmpp_2m",
                "scheduler": "karras",
                "denoise": 1.0,
                "model": ["1", 0],
                "positive": ["2", 0],
                "negative": ["3", 0],
                "latent_image": ["4", 0],
            },
        },
        "6": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["5", 0], "vae": ["1", 2]},
        },
        "7": {
            "class_type": "SaveImage",
            "inputs": {"filename_prefix": "mneme", "images": ["6", 0]},
        },
    }


# ── PAGING IS NOT OPTIONAL, AND IT IS A FREE FUNCTION SO IT IS TESTABLE ─────
#
# `_clip` cuts every tool result at MAX_RESULT_CHARS.  Without paging, a long
# contract would be silently truncated and the model would answer from its
# first two pages while believing it had read the whole thing — a wrong answer
# delivered confidently, which is the worst failure this tool can have.
#
# The page is smaller than the clip so the header and footer always fit inside
# it; if they did not, the clip would eat the "ask for part N+1" line and the
# model would never learn there was more.
DOC_PAGE_CHARS = MAX_RESULT_CHARS - 600


def page_count(content: str) -> int:
    content = content or ""
    if not content:
        return 1
    return (len(content) + DOC_PAGE_CHARS - 1) // DOC_PAGE_CHARS


def page_of(content: str, part: int) -> tuple[str, int, int] | None:
    """(text, part, total) for a 1-based part, or None if it is out of range."""
    content = content or ""
    total = page_count(content)
    if part < 1 or part > total:
        return None
    start = (part - 1) * DOC_PAGE_CHARS
    return content[start : start + DOC_PAGE_CHARS], part, total


def _clip(text: str, limit: int = MAX_RESULT_CHARS) -> str:
    text = text or ""
    if len(text) <= limit:
        return text
    return text[:limit] + f"\n… truncated at {limit} characters."
