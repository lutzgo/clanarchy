"""mneme — the household agent daemon.

WHAT THIS IS.  A translating, prompt-injecting proxy that sits between Home
Assistant and llama-swap.  It presents TWO north-side protocols and speaks ONE
south-side protocol:

    Home Assistant  --/api/tags, /api/chat (Ollama)-->  mneme  --/v1/*-->  llama-swap
    nvf / opencode  --/v1/chat/completions (OpenAI)-->

WHY THE OLLAMA SURFACE EXISTS, because it looks like a strange choice and is
not.  ernst runs Home Assistant 2026.5.4.  The native `llama_cpp` conversation
integration — the one that takes any OpenAI-compatible base URL — landed in
2026.8 and does not exist in this release.  `openai_conversation` in 2026.5.4
has no base-URL option at all: it can only talk to api.openai.com.  What 2026.5.4
DOES have is `ollama`, fully wired to the Assist LLM API with tool calling and
a "Control Home Assistant" selector.  So the Ollama wire protocol is the only
fully-local conversation path this hub has, and since this daemon has to sit in
the request path anyway — that is where the constitution and (from M29b) the
wiki index are injected — presenting Ollama on its north side costs one
translation layer and no architecture.

When ernst's nixpkgs reaches Home Assistant >= 2026.8, the migration is a
config-flow change in the browser: delete the Ollama entry, add a llama.cpp
entry pointing at this same daemon's /v1.  Nothing here has to move.

THE TRANSLATION IS NOT SYMMETRIC, and the asymmetry is the only interesting
part of this file.  Ollama's tool protocol has no tool_call_id: an assistant
message carries `tool_calls[].function.{name,arguments}` with arguments as a
JSON OBJECT, and a tool result is a bare `{"role": "tool", "content": "..."}`
with nothing tying it to the call it answers.  OpenAI requires an id on both
ends.  So ids are SYNTHESISED here by position — see `_ollama_to_openai_messages`
— which is correct only because Home Assistant emits tool results in call order
and immediately after the assistant turn that requested them
(homeassistant/components/ollama/entity.py, `_convert_content`).  If a future
release interleaves them, this pairing is where it will break, and it will break
loudly (an OpenAI 400 naming an unmatched tool_call_id) rather than silently.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import logging
import os
import sys
import uuid
from typing import Any

import aiohttp
from aiohttp import web

_LOG = logging.getLogger("mneme")

# The digest Home Assistant shows in the device registry.  Ollama's /api/tags
# entries carry one and the python client's pydantic model accepts None, but a
# plausible constant costs nothing and keeps the UI from rendering an empty
# field.  It is not a hash of anything.
_FAKE_DIGEST = "0" * 64


# ─────────────────────────────────────────────────────────────────────────────
# The system preamble.
#
# Stored as files in the Nix store and read once at startup rather than
# embedded as string literals, so M29b can extend the constitution without
# touching this file — and so `cat` on a running host shows exactly what the
# model is being told.
# ─────────────────────────────────────────────────────────────────────────────
class Preamble:
    """The constitution, assembled once at startup."""

    def __init__(self, soul_dir: str) -> None:
        self._parts: list[str] = []
        for name in ("SOUL.md", "IRON_RULES.md"):
            path = os.path.join(soul_dir, name)
            try:
                with open(path, encoding="utf-8") as handle:
                    self._parts.append(handle.read().strip())
            except OSError as err:
                # Fatal on purpose.  A daemon that silently runs without its
                # iron rules is the failure mode this whole design exists to
                # avoid; an agent that can call HassTurnOn should not start
                # without the section that tells it not to invent entity ids.
                raise SystemExit(f"mneme: cannot read {path}: {err}") from err
        self._text = "\n\n".join(self._parts)

    def text(self) -> str:
        return self._text


def inject_preamble(messages: list[dict[str, Any]], preamble: str) -> list[dict[str, Any]]:
    """Put the constitution in front of whatever system prompt arrived.

    Home Assistant builds its own system message (the Assist prompt plus the
    exposed-entity list) and puts it first.  We PREPEND INTO that message
    rather than adding a second system message: chat templates disagree about
    what to do with two, and the Qwen family merges only the first — a second
    one is silently dropped by some templates and concatenated by others.
    Editing the first is the only behaviour that is the same everywhere.
    """
    if not messages:
        return [{"role": "system", "content": preamble}]

    out = [dict(m) for m in messages]
    if out[0].get("role") == "system":
        existing = out[0].get("content") or ""
        out[0]["content"] = f"{preamble}\n\n{existing}".strip()
    else:
        out.insert(0, {"role": "system", "content": preamble})
    return out


# ─────────────────────────────────────────────────────────────────────────────
# Ollama -> OpenAI
# ─────────────────────────────────────────────────────────────────────────────
def _ollama_to_openai_messages(messages: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Translate an Ollama message list, synthesising tool_call ids.

    `pending` holds the ids minted for the most recent assistant turn's tool
    calls, in order.  Each subsequent `role: tool` message claims the next one.
    See this module's docstring for why that pairing is sound here.
    """
    out: list[dict[str, Any]] = []
    pending: list[str] = []

    for msg in messages:
        role = msg.get("role")

        if role == "tool":
            call_id = pending.pop(0) if pending else f"call_{uuid.uuid4().hex[:24]}"
            out.append(
                {
                    "role": "tool",
                    "tool_call_id": call_id,
                    "content": msg.get("content") or "",
                }
            )
            continue

        if role == "assistant":
            new: dict[str, Any] = {"role": "assistant", "content": msg.get("content") or ""}
            calls = msg.get("tool_calls") or []
            if calls:
                pending = []
                new["tool_calls"] = []
                for call in calls:
                    fn = call.get("function") or {}
                    call_id = f"call_{uuid.uuid4().hex[:24]}"
                    pending.append(call_id)
                    args = fn.get("arguments")
                    # Ollama carries arguments as an object; OpenAI wants the
                    # JSON text of that object.
                    if not isinstance(args, str):
                        args = json.dumps(args if args is not None else {})
                    new["tool_calls"].append(
                        {
                            "id": call_id,
                            "type": "function",
                            "function": {"name": fn.get("name") or "", "arguments": args},
                        }
                    )
            out.append(new)
            continue

        # user / system, and the image case.
        content = msg.get("content") or ""
        images = msg.get("images") or []
        if role == "user" and images:
            parts: list[dict[str, Any]] = [{"type": "text", "text": content}]
            for image in images:
                parts.append(
                    {"type": "image_url", "image_url": {"url": _as_data_url(image)}}
                )
            out.append({"role": "user", "content": parts})
        else:
            out.append({"role": role or "user", "content": content})

    return out


# Base64 prefixes of the magic bytes each format starts with.  Sniffing beats
# assuming: `ollama.Image` carries no MIME type at all, and a PNG announced as
# image/jpeg is the kind of thing that works on one backend and not the next.
_B64_MAGIC = (
    ("iVBORw0KGgo", "image/png"),
    ("/9j/", "image/jpeg"),
    ("R0lGOD", "image/gif"),
    ("UklGR", "image/webp"),
)


def _as_data_url(image: Any) -> str:
    """Accept what the ollama client sends for an image and make it a data URL.

    `ollama.Image(value=attachment.path)` serialises to a base64 string with no
    MIME type; a caller may also hand us something already shaped like a data
    URL.  Anything else is passed through and will fail upstream with a message
    that names it.

    NOTE THAT THE SERVED MODEL DECIDES WHETHER THIS WORKS AT ALL.  Attaching an
    image to an Assist conversation reaches llama-swap as a multimodal request,
    and `qwen3-coder-30b` has no vision tower — the upstream error is the
    correct answer there, not something to paper over here.  The vision model
    on this host is a separate entry in an exclusive GPU group; see
    service-modules/local-ai.md.
    """
    if isinstance(image, str):
        if image.startswith("data:"):
            return image
        mime = next((m for prefix, m in _B64_MAGIC if image.startswith(prefix)), "image/jpeg")
        return f"data:{mime};base64,{image}"
    if isinstance(image, dict) and "value" in image:
        return _as_data_url(image["value"])
    return str(image)


def ollama_to_openai(body: dict[str, Any], model: str, preamble: str) -> dict[str, Any]:
    """Build the upstream OpenAI request from an /api/chat body."""
    messages = inject_preamble(
        _ollama_to_openai_messages(body.get("messages") or []), preamble
    )

    out: dict[str, Any] = {
        # The model llama-swap serves, NOT whatever the caller typed.  Home
        # Assistant sends back the name it read from /api/tags, so these agree
        # today; pinning it here means a stale config entry cannot ask
        # llama-swap for a model that would evict the resident one.
        "model": model,
        "messages": messages,
        "stream": True,
    }

    tools = body.get("tools")
    if tools:
        out["tools"] = tools
        out["tool_choice"] = "auto"

    # AI Task structured output.  Home Assistant passes the JSON schema through
    # `format`; llama.cpp takes it as an OpenAI json_schema response format and
    # constrains sampling with it (a real grammar, not a prompt instruction).
    fmt = body.get("format")
    if isinstance(fmt, dict) and fmt:
        out["response_format"] = {
            "type": "json_schema",
            "json_schema": {"name": "structured_output", "schema": fmt, "strict": False},
        }
    elif fmt == "json":
        out["response_format"] = {"type": "json_object"}

    # `think` is Ollama's per-request reasoning toggle.  llama-server exposes
    # the equivalent through the chat template's own kwargs, which is where the
    # Qwen templates read it from.
    think = body.get("think")
    if think is not None:
        out["chat_template_kwargs"] = {"enable_thinking": bool(think)}

    # DELIBERATELY DROPPED: `keep_alive` and `options.num_ctx`.
    #
    # keep_alive is Ollama's residency control.  llama-swap owns residency here
    # through its own per-model `ttl` and its exclusive GPU group, and honouring
    # a client's request to pin a model would let the hub evict the coding agent
    # by accident.
    #
    # num_ctx is Ollama's per-request context window, and llama.cpp has no such
    # thing: the window is fixed when llama-swap spawns llama-server, from the
    # `contextLength` declared in roles.models.  That is SN1 answered at the
    # mechanism — the window lives with the model — so a client-supplied value
    # is not merely ignored, it has nowhere to go.  Home Assistant's default of
    # 8192 is therefore cosmetic; the real window is whatever the model declares.
    return out


# ─────────────────────────────────────────────────────────────────────────────
# OpenAI -> Ollama
# ─────────────────────────────────────────────────────────────────────────────
def _now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).isoformat(timespec="milliseconds").replace(
        "+00:00", "Z"
    )


def _ollama_chunk(model: str, message: dict[str, Any], done: bool, reason: str | None = None) -> bytes:
    payload: dict[str, Any] = {
        "model": model,
        "created_at": _now(),
        "message": message,
        "done": done,
    }
    if done:
        payload["done_reason"] = reason or "stop"
    return (json.dumps(payload) + "\n").encode("utf-8")


class _ToolCallAccumulator:
    """Reassemble OpenAI's streamed tool calls.

    OpenAI streams a tool call across many deltas: the first carries `index`,
    `id` and `function.name`, and the rest carry fragments of
    `function.arguments` as TEXT.  Ollama emits a whole tool call in one chunk
    with arguments as an OBJECT, so nothing can be forwarded until the stream
    ends.
    """

    def __init__(self) -> None:
        self._calls: dict[int, dict[str, Any]] = {}

    def feed(self, deltas: list[dict[str, Any]]) -> None:
        for delta in deltas:
            index = delta.get("index", 0)
            call = self._calls.setdefault(index, {"name": "", "arguments": ""})
            fn = delta.get("function") or {}
            if fn.get("name"):
                call["name"] = fn["name"]
            if fn.get("arguments"):
                call["arguments"] += fn["arguments"]

    def drain(self) -> list[dict[str, Any]]:
        out: list[dict[str, Any]] = []
        for _, call in sorted(self._calls.items()):
            raw = call["arguments"] or "{}"
            try:
                args = json.loads(raw)
            except json.JSONDecodeError:
                # Hand it over as a single string argument rather than dropping
                # the call.  Home Assistant's `_parse_tool_args` repairs some
                # malformed shapes, and a tool call that reaches it and fails
                # intent parsing produces a message in the log; one dropped
                # here produces silence and a model that appears to ignore the
                # request.
                _LOG.warning("tool call %s: unparseable arguments %r", call["name"], raw)
                args = {"__raw": raw}
            if not isinstance(args, dict):
                args = {"__value": args}
            out.append({"function": {"name": call["name"], "arguments": args}})
        self._calls.clear()
        return out


# ─────────────────────────────────────────────────────────────────────────────
# The server
# ─────────────────────────────────────────────────────────────────────────────
class Mneme:
    def __init__(self, cfg: argparse.Namespace) -> None:
        self.cfg = cfg
        self.preamble = Preamble(cfg.soul_dir).text()
        self.session: aiohttp.ClientSession | None = None

    async def start(self, app: web.Application) -> None:
        # No total timeout: a request that has to wait for llama-swap to load a
        # 21 GiB model off zdata takes minutes, and karakeep already had to
        # raise its own timeout to 300s for exactly this.  The read timeout is
        # what actually protects us — it fires on a stalled socket, not on a
        # slow-but-alive load.
        timeout = aiohttp.ClientTimeout(total=None, sock_connect=10, sock_read=self.cfg.read_timeout)
        self.session = aiohttp.ClientSession(timeout=timeout)

    async def stop(self, app: web.Application) -> None:
        if self.session is not None:
            await self.session.close()

    # ── plumbing ────────────────────────────────────────────────────────────
    @property
    def upstream(self) -> str:
        return self.cfg.upstream.rstrip("/")

    async def _post_upstream(self, payload: dict[str, Any]) -> aiohttp.ClientResponse:
        assert self.session is not None
        headers = {"Content-Type": "application/json"}
        if self.cfg.upstream_api_key:
            headers["Authorization"] = f"Bearer {self.cfg.upstream_api_key}"
        return await self.session.post(
            f"{self.upstream}/chat/completions", json=payload, headers=headers
        )

    # ── health ──────────────────────────────────────────────────────────────
    async def healthz(self, request: web.Request) -> web.Response:
        return web.json_response({"status": "ok", "model": self.cfg.model})

    # ── the Ollama surface ──────────────────────────────────────────────────
    async def api_version(self, request: web.Request) -> web.Response:
        # The ollama client checks that this parses; the value is not compared
        # against anything by Home Assistant.  Reporting a real-looking version
        # rather than "mneme" keeps client-side version gates satisfied.
        return web.json_response({"version": "0.12.0"})

    def _tag_entry(self) -> dict[str, Any]:
        return {
            "name": self.cfg.model,
            "model": self.cfg.model,
            "modified_at": _now(),
            "size": 0,
            "digest": _FAKE_DIGEST,
            "details": {
                "parent_model": "",
                "format": "gguf",
                "family": "mneme",
                "families": ["mneme"],
                "parameter_size": "",
                "quantization_level": "",
            },
        }

    async def api_tags(self, request: web.Request) -> web.Response:
        # EXACTLY ONE ENTRY, and that is deliberate.  Home Assistant's config
        # flow builds its model picker from this list and offers to `pull`
        # anything the user names that is not in it.  One entry means the
        # picker has one correct choice and the download path is unreachable.
        return web.json_response({"models": [self._tag_entry()]})

    async def api_show(self, request: web.Request) -> web.Response:
        return web.json_response(
            {
                "details": self._tag_entry()["details"],
                "model_info": {},
                "capabilities": ["completion", "tools"],
            }
        )

    async def api_chat(self, request: web.Request) -> web.StreamResponse:
        try:
            body = await request.json()
        except json.JSONDecodeError:
            return web.json_response({"error": "invalid JSON"}, status=400)

        payload = ollama_to_openai(body, self.cfg.model, self.preamble)

        response = web.StreamResponse(
            status=200, headers={"Content-Type": "application/x-ndjson"}
        )
        await response.prepare(request)

        try:
            upstream = await self._post_upstream(payload)
        except aiohttp.ClientError as err:
            _LOG.error("upstream unreachable: %s", err)
            await response.write(
                _ollama_chunk(
                    self.cfg.model,
                    {"role": "assistant", "content": f"[mneme] upstream unreachable: {err}"},
                    done=True,
                    reason="error",
                )
            )
            await response.write_eof()
            return response

        async with upstream:
            if upstream.status != 200:
                detail = (await upstream.text())[:500]
                _LOG.error("upstream %s: %s", upstream.status, detail)
                await response.write(
                    _ollama_chunk(
                        self.cfg.model,
                        {
                            "role": "assistant",
                            "content": f"[mneme] upstream HTTP {upstream.status}: {detail}",
                        },
                        done=True,
                        reason="error",
                    )
                )
                await response.write_eof()
                return response

            calls = _ToolCallAccumulator()
            finish = "stop"

            async for raw in upstream.content:
                line = raw.decode("utf-8", "replace").strip()
                if not line or not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    break
                try:
                    event = json.loads(data)
                except json.JSONDecodeError:
                    _LOG.warning("undecodable SSE payload: %r", data[:200])
                    continue

                choices = event.get("choices") or []
                if not choices:
                    continue
                choice = choices[0]
                delta = choice.get("delta") or {}

                if choice.get("finish_reason"):
                    finish = choice["finish_reason"]

                if delta.get("tool_calls"):
                    calls.feed(delta["tool_calls"])

                message: dict[str, Any] = {"role": "assistant"}
                emit = False
                if delta.get("content"):
                    message["content"] = delta["content"]
                    emit = True
                # llama.cpp emits reasoning under either name depending on the
                # template; Ollama calls it `thinking` and that is what Home
                # Assistant reads.
                reasoning = delta.get("reasoning_content") or delta.get("reasoning")
                if reasoning:
                    message["thinking"] = reasoning
                    emit = True
                if emit:
                    await response.write(_ollama_chunk(self.cfg.model, message, done=False))

            pending = calls.drain()
            if pending:
                await response.write(
                    _ollama_chunk(
                        self.cfg.model,
                        {"role": "assistant", "content": "", "tool_calls": pending},
                        done=False,
                    )
                )
                finish = "tool_calls" if finish == "stop" else finish

            await response.write(
                _ollama_chunk(
                    self.cfg.model, {"role": "assistant", "content": ""}, done=True, reason=finish
                )
            )

        await response.write_eof()
        return response

    # ── the OpenAI surface ──────────────────────────────────────────────────
    #
    # Same daemon, same preamble, no translation: this is what nvf, opencode
    # and Open WebUI will use, and what Home Assistant itself will use once its
    # native llama.cpp integration is available here.
    async def v1_models(self, request: web.Request) -> web.Response:
        return web.json_response(
            {
                "object": "list",
                "data": [
                    {
                        "id": self.cfg.model,
                        "object": "model",
                        "created": 0,
                        "owned_by": "mneme",
                    }
                ],
            }
        )

    async def v1_chat(self, request: web.Request) -> web.StreamResponse:
        try:
            body = await request.json()
        except json.JSONDecodeError:
            return web.json_response({"error": "invalid JSON"}, status=400)

        body = dict(body)
        body["model"] = self.cfg.model
        body["messages"] = inject_preamble(body.get("messages") or [], self.preamble)

        try:
            upstream = await self._post_upstream(body)
        except aiohttp.ClientError as err:
            return web.json_response({"error": f"upstream unreachable: {err}"}, status=502)

        async with upstream:
            if not body.get("stream"):
                payload = await upstream.read()
                return web.Response(
                    body=payload,
                    status=upstream.status,
                    content_type="application/json",
                )

            response = web.StreamResponse(
                status=upstream.status,
                headers={"Content-Type": "text/event-stream", "Cache-Control": "no-cache"},
            )
            await response.prepare(request)
            async for chunk in upstream.content.iter_any():
                await response.write(chunk)
            await response.write_eof()
            return response


def build_app(cfg: argparse.Namespace) -> web.Application:
    mneme = Mneme(cfg)
    app = web.Application(client_max_size=64 * 1024 * 1024)
    app.on_startup.append(mneme.start)
    app.on_cleanup.append(mneme.stop)
    app.add_routes(
        [
            web.get("/healthz", mneme.healthz),
            web.get("/api/version", mneme.api_version),
            web.get("/api/tags", mneme.api_tags),
            web.post("/api/show", mneme.api_show),
            web.post("/api/chat", mneme.api_chat),
            web.get("/v1/models", mneme.v1_models),
            web.post("/v1/chat/completions", mneme.v1_chat),
        ]
    )
    return app


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="mneme", description=__doc__)
    parser.add_argument("--listen", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=11435)
    parser.add_argument(
        "--upstream",
        default="http://127.0.0.1:11434/v1",
        help="OpenAI-compatible base URL, including /v1.",
    )
    parser.add_argument("--upstream-api-key", default=os.environ.get("MNEME_UPSTREAM_API_KEY", ""))
    parser.add_argument("--model", required=True, help="The llama-swap model name to serve.")
    parser.add_argument("--soul-dir", required=True, help="Directory holding SOUL.md and IRON_RULES.md.")
    parser.add_argument("--read-timeout", type=float, default=600.0)
    parser.add_argument("--log-level", default="INFO")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> None:
    cfg = parse_args(argv if argv is not None else sys.argv[1:])
    logging.basicConfig(
        level=getattr(logging, cfg.log_level.upper(), logging.INFO),
        format="%(levelname)s %(name)s %(message)s",
    )
    _LOG.info("serving %s on %s:%d -> %s", cfg.model, cfg.listen, cfg.port, cfg.upstream)
    web.run_app(build_app(cfg), host=cfg.listen, port=cfg.port, print=None)


if __name__ == "__main__":
    main()
