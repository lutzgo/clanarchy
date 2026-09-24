"""Build-time tests for the parts of mneme that fail silently.

Run by the derivation's checkPhase.  Plain asserts and no test framework: the
point is to make the build fail, not to produce a report.
"""

from __future__ import annotations

import json
import sys

import mneme


def test_preamble_merges_into_the_existing_system_message() -> None:
    # Home Assistant always sends its Assist prompt as messages[0].  A second
    # system message is dropped by some chat templates, so the preamble must
    # land inside the first one.
    messages = [
        {"role": "system", "content": "You are a voice assistant for HA."},
        {"role": "user", "content": "hi"},
    ]
    out = mneme.inject_preamble(messages, "RULES")
    assert len(out) == 2, out
    assert out[0]["role"] == "system"
    assert out[0]["content"].startswith("RULES")
    assert "voice assistant" in out[0]["content"]
    # The caller's list is not mutated.
    assert messages[0]["content"] == "You are a voice assistant for HA."


def test_preamble_is_inserted_when_there_is_no_system_message() -> None:
    out = mneme.inject_preamble([{"role": "user", "content": "hi"}], "RULES")
    assert [m["role"] for m in out] == ["system", "user"]
    assert out[0]["content"] == "RULES"


def test_preamble_on_empty_history() -> None:
    out = mneme.inject_preamble([], "RULES")
    assert out == [{"role": "system", "content": "RULES"}]


def test_tool_results_are_paired_with_the_calls_they_answer() -> None:
    # THE CENTRAL ASYMMETRY.  Ollama carries no tool_call_id anywhere; OpenAI
    # requires one on the assistant's call and on the tool result.  Pairing is
    # by position, so two calls in one turn must come back in order.
    messages = [
        {"role": "user", "content": "lights off"},
        {
            "role": "assistant",
            "content": "",
            "tool_calls": [
                {"function": {"name": "HassTurnOff", "arguments": {"name": "kitchen"}}},
                {"function": {"name": "HassTurnOff", "arguments": {"name": "hall"}}},
            ],
        },
        {"role": "tool", "content": '{"speech": "done"}'},
        {"role": "tool", "content": '{"speech": "done"}'},
    ]
    out = mneme._ollama_to_openai_messages(messages)

    assistant = out[1]
    ids = [c["id"] for c in assistant["tool_calls"]]
    assert len(set(ids)) == 2, ids
    assert [out[2]["tool_call_id"], out[3]["tool_call_id"]] == ids

    # Arguments cross as a JSON STRING, which is what OpenAI wants and what
    # Ollama does not use.
    args = assistant["tool_calls"][0]["function"]["arguments"]
    assert isinstance(args, str)
    assert json.loads(args) == {"name": "kitchen"}


def test_orphan_tool_result_still_gets_an_id() -> None:
    # History trimming (_trim_history in HA) can drop the assistant turn that
    # requested a call while keeping its result.  That must not raise.
    out = mneme._ollama_to_openai_messages([{"role": "tool", "content": "{}"}])
    assert out[0]["tool_call_id"].startswith("call_")


def test_user_images_become_openai_content_parts() -> None:
    out = mneme._ollama_to_openai_messages(
        [{"role": "user", "content": "what is this", "images": ["QUJD"]}]
    )
    parts = out[0]["content"]
    assert parts[0] == {"type": "text", "text": "what is this"}
    assert parts[1]["image_url"]["url"].startswith("data:image/jpeg;base64,QUJD")


def test_image_mime_is_sniffed_not_assumed() -> None:
    # ollama.Image carries no MIME type.  A PNG announced as image/jpeg works
    # on some backends and not others, so the magic bytes decide.
    assert _mime_of("iVBORw0KGgoAAAA") == "image/png"
    assert _mime_of("/9j/4AAQSkZJRg") == "image/jpeg"
    assert _mime_of("R0lGODlhAQABAA") == "image/gif"
    assert _mime_of("UklGRiQAAABXRU") == "image/webp"
    # Unrecognised falls back rather than refusing; upstream names the problem.
    assert _mime_of("bm90IGFuIGltYWdl") == "image/jpeg"
    # An already-formed data URL is passed through untouched.
    assert mneme._as_data_url("data:image/png;base64,AAA") == "data:image/png;base64,AAA"


def _mime_of(b64: str) -> str:
    url = mneme._as_data_url(b64)
    return url.split(";", 1)[0].removeprefix("data:")


def test_streamed_tool_calls_are_reassembled() -> None:
    # OpenAI splits one call across deltas: name first, arguments as text
    # fragments.  Ollama wants one chunk with arguments as an object.
    acc = mneme._ToolCallAccumulator()
    acc.feed([{"index": 0, "id": "x", "function": {"name": "HassTurnOn", "arguments": ""}}])
    acc.feed([{"index": 0, "function": {"arguments": '{"na'}}])
    acc.feed([{"index": 0, "function": {"arguments": 'me": "kitchen"}'}}])
    out = acc.drain()
    assert out == [{"function": {"name": "HassTurnOn", "arguments": {"name": "kitchen"}}}]
    assert acc.drain() == []


def test_unparseable_tool_arguments_are_surfaced_not_dropped() -> None:
    acc = mneme._ToolCallAccumulator()
    acc.feed([{"index": 0, "function": {"name": "HassTurnOn", "arguments": "{oops"}}])
    out = acc.drain()
    assert out[0]["function"]["name"] == "HassTurnOn"
    assert out[0]["function"]["arguments"] == {"__raw": "{oops"}


def test_multiple_streamed_calls_keep_their_order() -> None:
    acc = mneme._ToolCallAccumulator()
    acc.feed([{"index": 1, "function": {"name": "second", "arguments": "{}"}}])
    acc.feed([{"index": 0, "function": {"name": "first", "arguments": "{}"}}])
    assert [c["function"]["name"] for c in acc.drain()] == ["first", "second"]


def test_request_translation_pins_the_model_and_drops_residency_controls() -> None:
    body = {
        "model": "whatever-the-client-typed",
        "messages": [{"role": "user", "content": "hi"}],
        "tools": [{"type": "function", "function": {"name": "HassTurnOn"}}],
        "keep_alive": "-1s",
        "options": {"num_ctx": 8192},
        "think": False,
    }
    out = mneme.ollama_to_openai(body, "qwen3-coder-30b", "RULES")
    assert out["model"] == "qwen3-coder-30b"
    assert out["stream"] is True
    assert out["tool_choice"] == "auto"
    assert out["chat_template_kwargs"] == {"enable_thinking": False}
    # llama-swap owns residency and the window lives with the model (SN1).
    assert "keep_alive" not in out
    assert "options" not in out
    assert "num_ctx" not in json.dumps(out)


def test_structured_output_becomes_a_json_schema_response_format() -> None:
    schema = {"type": "object", "properties": {"n": {"type": "integer"}}}
    out = mneme.ollama_to_openai(
        {"messages": [], "format": schema}, "m", "RULES"
    )
    assert out["response_format"]["type"] == "json_schema"
    assert out["response_format"]["json_schema"]["schema"] == schema


def test_no_tools_means_no_tool_choice() -> None:
    out = mneme.ollama_to_openai({"messages": [], "tools": []}, "m", "RULES")
    assert "tools" not in out
    assert "tool_choice" not in out


def main() -> int:
    failures = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("test_") or not callable(fn):
            continue
        try:
            fn()
        except AssertionError as err:
            failures += 1
            print(f"FAIL {name}: {err}", file=sys.stderr)
        else:
            print(f"ok   {name}")
    if failures:
        print(f"{failures} test(s) failed", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
