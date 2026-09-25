"""Zero-spend checks for bridge/agent.py's typed Pydantic AI tools (Phase 2 plan 02-05).

No model call and no network: every agent run goes through pydantic-ai's ``FunctionModel`` (a
scripted stand-in for Claude), and the ``send_cmd`` / ``say`` / ``default_worker`` callables that
``agent.configure()`` injects are fakes that record what the tools handed them. The pytest suite
is deferred to v1.1 (PROJECT.md), so this module has no test-framework dependency: every
``test_*`` function is pytest-collectable later, and running the file directly emits TAP.

    uv run python tests/test_agent.py
"""

from __future__ import annotations

import asyncio
import inspect
import logging
import os
import sys
import traceback
from collections.abc import Callable
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
os.environ.setdefault("PYDANTIC_AI_NO_BANNER", "1")  # keep pydantic-ai's banner off the TAP stream

import anthropic  # noqa: E402
from pydantic_ai import Agent, FunctionToolset  # noqa: E402
from pydantic_ai.messages import (  # noqa: E402
    ModelMessage,
    ModelRequest,
    ModelRequestPart,
    ModelResponse,
    ModelResponsePart,
    RetryPromptPart,
    TextPart,
    ToolCallPart,
    ToolReturnPart,
    UserPromptPart,
)
from pydantic_ai.models.anthropic import AnthropicModel  # noqa: E402
from pydantic_ai.models.function import AgentInfo, FunctionModel  # noqa: E402

from bridge import agent as a  # noqa: E402
from bridge.settings import Settings  # noqa: E402

DEVICE_PRIMITIVES = (
    "status",
    "list_chest",
    "push_one_slot",
    "move",
    "turn",
    "dig",
    "inspect",
    "refuel",
)
TURTLE_CAPS = sorted(DEVICE_PRIMITIVES)
COMPUTER_CAPS = ["list_chest", "push_one_slot", "status"]

# The description strings the hand-rolled DEVICE_TOOLS/LOCAL_TOOLS dicts carried; the typed tools
# must present the same text to the model so the swap changes nothing the model reads.
CARRIED_DESCRIPTIONS = {
    "status": "Fuel, position, and attached peripherals of a device.",
    "list_chest": "List the items in an inventory on the wired network.",
    "move": "Move a turtle up to N steps. Stops early if blocked.",
    "turn": "Turn a turtle left or right.",
    "dig": "Dig the block in a direction.",
    "inspect": "Name the blocks in front, above and below a turtle.",
    "refuel": "Burn fuel items from the turtle's inventory.",
    "list_devices": "List connected devices, their roles and the tools each supports.",
    "say": "Speak in game chat. Use once at the end with a short summary, not for every step.",
    # Plan 02-06: the rule tools moved from the device to the bridge (D-08), same descriptions.
    "list_rules": "Show the sorting rules and overflow chest.",
    "add_rule": (
        "Add a sorting rule: items whose id matches the Lua pattern go to dest. "
        "First matching rule wins."
    ),
    "remove_rule": "Remove a sorting rule by its exact pattern.",
    "set_overflow": "Set the chest that receives items no rule matches.",
}


class Recorder:
    """Fakes for the bridge callables agent.configure() injects; records every call made."""

    def __init__(self, worker: str | None = "w1", reply: dict[str, object] | None = None) -> None:
        self.worker = worker
        self.reply: dict[str, object] = reply if reply is not None else {"ok": True, "data": {}}
        self.cmds: list[tuple[str, str, dict[str, object] | None]] = []
        self.said: list[tuple[str, str | None]] = []

    async def send_cmd(
        self, device_id: str, tool: str, args: dict[str, object] | None = None
    ) -> dict[str, object]:
        self.cmds.append((device_id, tool, args))
        return dict(self.reply)

    async def say(self, text: str, to: str | None = None) -> None:
        self.said.append((text, to))

    def default_worker(self) -> str | None:
        return self.worker


class Script:
    """A scripted model: plays fixed turns in order and records what it was shown each call."""

    def __init__(self, *turns: list[ToolCallPart] | str) -> None:
        self.turns = list(turns)
        self.tools_seen: list[list[str]] = []
        self.messages_seen: list[list[ModelMessage]] = []
        self.instructions_seen: list[str | None] = []

    def respond(self, messages: list[ModelMessage], info: AgentInfo) -> ModelResponse:
        self.tools_seen.append(sorted(t.name for t in info.function_tools))
        self.messages_seen.append(list(messages))
        self.instructions_seen.append(info.instructions)
        turn: list[ToolCallPart] | str = self.turns.pop(0) if self.turns else "done"
        if isinstance(turn, str):
            return ModelResponse(parts=[TextPart(content=turn)])
        return ModelResponse(parts=list(turn))

    def model(self) -> FunctionModel:
        return FunctionModel(self.respond)


def make_settings() -> Settings:
    """Build a Settings for tests without reading any .env file on this machine."""
    return Settings(
        _env_file=None,
        bridge_token="correct-horse-battery",
        allowed_players=["Nate"],
        anthropic_api_key="sk-ant-test",
    )


def configure(devices: dict[str, dict[str, object]] | None = None, **fakes: Any) -> Recorder:
    """Wire agent.py the way bridge.main() does, with recording fakes and an offline client."""
    rec = Recorder(**fakes)
    client = anthropic.AsyncAnthropic(api_key="sk-ant-test")  # never used to send anything
    registry = devices if devices is not None else {}  # keep the caller's dict as the registry
    a.configure(make_settings(), client, registry, rec.send_cmd, rec.say, rec.default_worker)
    getattr(a, "histories", {}).clear()
    return rec


def require_tool(name: str) -> Any:
    tool = getattr(a, name, None)
    assert tool is not None, f"agent.py defines no typed tool function {name!r}"
    assert inspect.iscoroutinefunction(tool), f"{name} is not an async tool function"
    return tool


def parts(messages: list[ModelMessage]) -> list[ModelRequestPart | ModelResponsePart]:
    return [p for m in messages for p in m.parts]


def call(tool_name: str, **args: object) -> list[ToolCallPart]:
    return [ToolCallPart(tool_name=tool_name, args=dict(args))]


async def run_tool_through_model(
    tool: Any, script: Script, prompt: str = "[Nate] do it"
) -> list[ModelMessage]:
    """Drive one typed tool with a scripted model, isolated from build_toolset()."""
    agent: Agent[None, str] = Agent(script.model())
    result = await agent.run(prompt, toolsets=[FunctionToolset([tool])])
    return result.all_messages()


# ----------------------------------------------------------------- Task 1: typed device tools
async def test_list_chest_without_name_is_rejected_before_the_tool_runs() -> None:
    rec = configure()
    tool = require_tool("list_chest")
    script = Script(call("list_chest"), "done")  # the model forgets the required `name`
    messages = await run_tool_through_model(tool, script)
    retries = [p for p in parts(messages) if isinstance(p, RetryPromptPart)]
    assert len(retries) == 1, [type(p).__name__ for p in parts(messages)]
    assert retries[0].tool_name == "list_chest", retries[0]
    assert "name" in str(retries[0].content), retries[0].content
    assert rec.cmds == [], rec.cmds  # validation failed first, so nothing reached a device
    assert len(script.tools_seen) == 2, script.tools_seen  # the model got a second go


async def test_device_tool_returns_send_cmd_result_without_raising() -> None:
    failure: dict[str, object] = {"ok": False, "error": "w1 disconnected during command"}
    rec = configure(reply=failure)
    tool = require_tool("status")
    messages = await run_tool_through_model(tool, Script(call("status"), "done"))
    returns = [p for p in parts(messages) if isinstance(p, ToolReturnPart)]
    assert len(returns) == 1, [type(p).__name__ for p in parts(messages)]
    assert returns[0].content == failure, returns[0].content
    assert rec.cmds == [("w1", "status", {})], rec.cmds


async def test_device_tool_with_no_worker_returns_error_dict() -> None:
    rec = configure(worker=None)
    tool = require_tool("list_chest")
    script = Script(call("list_chest", name="minecraft:chest_0"), "done")
    messages = await run_tool_through_model(tool, script)
    returns = [p for p in parts(messages) if isinstance(p, ToolReturnPart)]
    assert len(returns) == 1, [type(p).__name__ for p in parts(messages)]
    assert returns[0].content == {"ok": False, "error": "no turtle or computer connected"}
    assert rec.cmds == [], rec.cmds


async def test_explicit_device_overrides_default_worker() -> None:
    rec = configure()
    tool = require_tool("inspect")
    await run_tool_through_model(tool, Script(call("inspect", device="turtle-7"), "done"))
    assert rec.cmds == [("turtle-7", "inspect", {})], rec.cmds


async def test_push_one_slot_wire_args_match_client_lua() -> None:
    rec = configure()
    tool = require_tool("push_one_slot")
    script = Script(
        call("push_one_slot", from_name="minecraft:chest_0", slot=3, dest="minecraft:chest_1"),
        call(
            "push_one_slot",
            device="t9",
            from_name="minecraft:chest_0",
            slot=4,
            dest="minecraft:chest_2",
            limit=8,
        ),
        "done",
    )
    await run_tool_through_model(tool, script)
    assert rec.cmds == [
        (
            "w1",
            "push_one_slot",
            {"from": "minecraft:chest_0", "slot": 3, "dest": "minecraft:chest_1"},
        ),
        (
            "t9",
            "push_one_slot",
            {"from": "minecraft:chest_0", "slot": 4, "dest": "minecraft:chest_2", "limit": 8},
        ),
    ], rec.cmds


async def test_move_forwards_dir_and_steps_and_omits_unset_fields() -> None:
    rec = configure()
    tool = require_tool("move")
    script = Script(call("move", dir="up"), call("move", dir="forward", steps=3), "done")
    await run_tool_through_model(tool, script)
    assert rec.cmds == [
        ("w1", "move", {"dir": "up"}),
        ("w1", "move", {"dir": "forward", "steps": 3}),
    ], rec.cmds


def test_every_primitive_is_a_typed_tool_with_the_lua_signature() -> None:
    configure()
    expected_required = {
        "status": [],
        "list_chest": ["name"],
        "push_one_slot": ["from_name", "slot", "dest"],
        "move": ["dir"],
        "turn": ["dir"],
        "dig": [],
        "inspect": [],
        "refuel": [],
    }
    for name in DEVICE_PRIMITIVES:
        tool = require_tool(name)
        registered = FunctionToolset([tool]).tools
        assert list(registered) == [name], registered
        schema = registered[name].function_schema.json_schema
        assert schema.get("required", []) == expected_required[name], (name, schema)
        assert "device" in schema["properties"], (name, schema)
        if name in CARRIED_DESCRIPTIONS:
            assert registered[name].description == CARRIED_DESCRIPTIONS[name], (
                name,
                registered[name].description,
            )
    move_dir = (
        FunctionToolset([require_tool("move")])
        .tools["move"]
        .function_schema.json_schema["properties"]
    )
    assert move_dir["dir"]["enum"] == ["forward", "back", "up", "down"], move_dir


# ----------------------------------------------------------------- Task 2: local tools, toolset
# Always in the toolset whatever is connected: the two Phase 1 local tools plus the four rule tools
# plan 02-06 moved onto the bridge (D-08). Sorted, because toolset_names() sorts.
LOCAL_TOOLS = ["add_rule", "list_devices", "list_rules", "remove_rule", "say", "set_overflow"]
# Python compositions (plan 02-06, D-07/D-09): offered only when one connected device advertises
# every primitive they need; sort_chest needs list_chest and push_one_slot, which both a plain
# computer and a turtle advertise.
COMPOSITIONS = ["sort_chest"]


def require_build_toolset() -> Any:
    build = getattr(a, "build_toolset", None)
    assert build is not None, "agent.py defines no build_toolset()"
    return build


def require_agent() -> Any:
    agent = getattr(a, "agent", None)
    assert agent is not None, "agent.py has no module-level agent after configure()"
    assert isinstance(agent, Agent), type(agent)
    return agent


def toolset_names(devices: dict[str, dict[str, object]]) -> list[str]:
    """Tool names build_toolset() registers for a given live device registry."""
    configure(devices)
    toolset = require_build_toolset()()
    assert isinstance(toolset, FunctionToolset), type(toolset)
    return sorted(toolset.tools)


def turtle(caps: list[str] | None = None) -> dict[str, object]:
    return {"role": "turtle", "caps": list(TURTLE_CAPS if caps is None else caps), "ws": object()}


def computer(caps: list[str] | None = None) -> dict[str, object]:
    return {"role": "computer", "caps": list(COMPUTER_CAPS if caps is None else caps)}


def test_toolset_with_no_devices_has_only_local_tools() -> None:
    assert toolset_names({}) == LOCAL_TOOLS


def test_toolset_with_computer_worker_adds_only_its_caps() -> None:
    names = toolset_names({"chat-1": {"role": "chat", "caps": ["say"]}, "w1": computer()})
    assert names == sorted(LOCAL_TOOLS + COMPUTER_CAPS + COMPOSITIONS), names
    for movement in ("move", "turn", "dig", "inspect", "refuel"):
        assert movement not in names, names


def test_toolset_with_turtle_adds_all_eight_primitives() -> None:
    names = toolset_names({"t1": turtle([*TURTLE_CAPS, "run_lua"])})
    assert names == sorted(LOCAL_TOOLS + list(DEVICE_PRIMITIVES) + COMPOSITIONS), names
    assert "run_lua" not in names, names  # an advertised cap with no typed tool adds nothing


def test_toolset_is_rebuilt_from_the_live_registry_each_call() -> None:
    devices: dict[str, dict[str, object]] = {}
    configure(devices)
    build = require_build_toolset()
    assert sorted(build().tools) == LOCAL_TOOLS
    devices["w1"] = computer()
    assert sorted(build().tools) == sorted(LOCAL_TOOLS + COMPUTER_CAPS + COMPOSITIONS)
    devices["t1"] = turtle()
    assert sorted(build().tools) == sorted(LOCAL_TOOLS + list(DEVICE_PRIMITIVES) + COMPOSITIONS)
    devices.clear()
    assert sorted(build().tools) == LOCAL_TOOLS
    assert build() is not build(), "build_toolset() must hand out a fresh toolset per run"


def test_local_tools_carry_the_old_descriptions() -> None:
    configure({})
    toolset = require_build_toolset()()
    for name in LOCAL_TOOLS:
        assert toolset.tools[name].description == CARRIED_DESCRIPTIONS[name], (
            name,
            toolset.tools[name].description,
        )
    say_schema = toolset.tools["say"].function_schema.json_schema
    assert say_schema.get("required") == ["text"], say_schema
    assert set(say_schema["properties"]) == {"text", "to"}, say_schema


async def test_list_devices_reports_roles_and_caps_only() -> None:
    configure({"w1": computer(), "t1": turtle()})
    tool = require_tool("list_devices")
    messages = await run_tool_through_model(tool, Script(call("list_devices"), "done"))
    returns = [p for p in parts(messages) if isinstance(p, ToolReturnPart)]
    assert len(returns) == 1, [type(p).__name__ for p in parts(messages)]
    assert returns[0].content == {
        "w1": {"role": "computer", "caps": COMPUTER_CAPS},
        "t1": {"role": "turtle", "caps": TURTLE_CAPS},
    }, returns[0].content


async def test_say_tool_calls_the_injected_say_and_accepts_null_to() -> None:
    rec = configure({})
    tool = require_tool("say")
    script = Script(
        call("say", text="Hello Nate", to=None),  # what the pre-swap model actually sent (02-04)
        call("say", text="psst", to="Nate"),
        call("say", text="all done"),
        "done",
    )
    messages = await run_tool_through_model(tool, script)
    returns = [p for p in parts(messages) if isinstance(p, ToolReturnPart)]
    assert [r.content for r in returns] == [{"ok": True}] * 3, returns
    assert rec.said == [("Hello Nate", None), ("psst", "Nate"), ("all done", None)], rec.said
    assert rec.cmds == [], rec.cmds


async def test_say_without_text_is_rejected_before_it_speaks() -> None:
    rec = configure({})
    tool = require_tool("say")
    messages = await run_tool_through_model(tool, Script(call("say", to="Nate"), "done"))
    retries = [p for p in parts(messages) if isinstance(p, RetryPromptPart)]
    assert len(retries) == 1 and retries[0].tool_name == "say", retries
    assert rec.said == [], rec.said


def test_configure_builds_the_agent_on_the_injected_anthropic_client() -> None:
    client = anthropic.AsyncAnthropic(api_key="sk-ant-test")
    rec = Recorder()
    settings = make_settings()
    a.configure(settings, client, {}, rec.send_cmd, rec.say, rec.default_worker)
    model = require_agent().model
    assert isinstance(model, AnthropicModel), type(model)
    assert model.client is client, "AnthropicProvider must wrap bridge.py's client, not a new one"
    assert model.model_name == settings.model, model.model_name


async def test_agent_has_no_tools_of_its_own_and_uses_system_as_instructions() -> None:
    configure({"t1": turtle()})  # a turtle is connected, yet without build_toolset()...
    agent = require_agent()
    script = Script("done")
    with agent.override(model=script.model()):
        result = await agent.run("[Nate] hi")  # ...no toolsets are passed for this run
    assert result.output == "done", result.output
    assert script.tools_seen == [[]], script.tools_seen  # ...so the model sees no tools at all
    # pydantic-ai strips the instructions' surrounding whitespace before the request goes out
    assert script.instructions_seen[0] == a.system.strip(), script.instructions_seen


# ----------------------------------------------------------------- Task 3: handle_request
class ModelBlewUpError(Exception):
    """A genuinely unexpected failure inside the model call (not a tool error)."""


async def run_request(script: Script, user: str, text: str) -> None:
    """Drive handle_request() exactly as bridge.on_event does, with the model scripted."""
    with require_agent().override(model=script.model()):
        await a.handle_request(user, text)


def histories() -> dict[str, list[ModelMessage]]:
    stored = getattr(a, "histories", None)
    assert isinstance(stored, dict), "agent.py has no per-player histories dict"
    return stored


def user_prompts(messages: list[ModelMessage]) -> list[str]:
    return [str(p.content) for p in parts(messages) if isinstance(p, UserPromptPart)]


def test_handle_request_keeps_the_phase_1_signature() -> None:
    sig = inspect.signature(a.handle_request, eval_str=True)
    assert list(sig.parameters) == ["user", "text"], sig
    assert all(p.annotation is str for p in sig.parameters.values()), sig
    assert sig.return_annotation is None, sig


async def test_handle_request_runs_the_model_with_the_per_run_toolset() -> None:
    devices: dict[str, dict[str, object]] = {}
    configure(devices)
    script = Script("done", "done")
    await run_request(script, "Nate", "what devices are connected?")
    devices["t1"] = turtle()  # a turtle connects between two requests
    await run_request(script, "Nate", "and now?")
    assert script.tools_seen == [
        LOCAL_TOOLS,
        sorted(LOCAL_TOOLS + list(DEVICE_PRIMITIVES) + COMPOSITIONS),
    ], script.tools_seen


async def test_handle_request_keeps_history_per_player() -> None:
    configure({})
    script = Script("hi Nate", "hi again", "hi Bob")
    await run_request(script, "Nate", "hello")
    await run_request(script, "Nate", "again")
    await run_request(script, "Bob", "yo")
    first, second, bob = script.messages_seen
    assert user_prompts(first) == ["[Nate] hello"], user_prompts(first)
    assert user_prompts(second) == ["[Nate] hello", "[Nate] again"], user_prompts(second)
    assert user_prompts(bob) == ["[Bob] yo"], user_prompts(bob)  # never another player's turns
    stored = histories()
    assert set(stored) == {"Nate", "Bob"}, set(stored)
    assert len(stored["Nate"]) == 4 and len(stored["Bob"]) == 2, {
        k: len(v) for k, v in stored.items()
    }
    assert all(isinstance(m, ModelRequest | ModelResponse) for m in stored["Nate"]), stored["Nate"]


async def test_failed_run_raises_and_leaves_that_players_history_untouched() -> None:
    configure({})
    await run_request(Script("ok"), "Nate", "hello")
    before = list(histories()["Nate"])

    def explode(messages: list[ModelMessage], info: AgentInfo) -> ModelResponse:
        raise ModelBlewUpError("model call blew up")

    try:
        with require_agent().override(model=FunctionModel(explode)):
            await a.handle_request("Nate", "again")
    except ModelBlewUpError:
        pass  # bridge.on_event's try/except is the intended catcher
    else:
        raise AssertionError("handle_request swallowed the failure instead of raising")
    assert histories()["Nate"] == before, histories()["Nate"]


async def test_history_is_bounded_and_trimmed_on_turn_boundaries() -> None:
    configure({})
    limit = getattr(a, "HISTORY_LIMIT", None)
    assert isinstance(limit, int) and limit > 0, limit
    turns = limit // 6 + 1  # each turn below is 6 messages, so the total overshoots the cap
    one_turn: list[list[ToolCallPart] | str] = [call("list_devices"), call("list_devices"), "ok"]
    script = Script(*(one_turn * turns))
    for i in range(turns):
        await run_request(script, "Nate", f"turn {i}")
    hist = histories()["Nate"]
    assert len(hist) <= limit, len(hist)
    assert isinstance(hist[0], ModelRequest) and isinstance(hist[0].parts[0], UserPromptPart), hist[
        0
    ]  # never cut inside a turn: the kept history starts on a player's prompt
    kept = user_prompts(hist)
    assert kept[0] != "[Nate] turn 0" and kept[-1] == f"[Nate] turn {turns - 1}", kept
    calls = sum(isinstance(p, ToolCallPart) for p in parts(hist))
    returns = sum(isinstance(p, ToolReturnPart) for p in parts(hist))
    assert calls == returns, (calls, returns)  # every kept tool_use still has its tool_result


async def test_runaway_tool_loop_is_cut_off_and_history_untouched() -> None:
    configure({})
    await run_request(Script("ok"), "Nate", "hello")
    before = list(histories()["Nate"])
    model_calls = 0

    def forever(messages: list[ModelMessage], info: AgentInfo) -> ModelResponse:
        nonlocal model_calls
        model_calls += 1
        return ModelResponse(parts=[ToolCallPart(tool_name="list_devices", args={})])

    try:
        with require_agent().override(model=FunctionModel(forever)):
            await a.handle_request("Nate", "loop")
    except Exception as exc:
        assert "UsageLimit" in type(exc).__name__, type(exc).__name__
    else:
        raise AssertionError("a request that never stops calling tools was not cut off")
    assert 2 <= model_calls <= 12, model_calls  # the old loop's cap of 12 model rounds carries over
    assert histories()["Nate"] == before, histories()["Nate"]


# ----------------------------------------------------------------- Task 4: the answer is spoken
# Plan 02-07's post-swap paid run (2026-09-24 22:17, claude-haiku-4-5): the model called
# list_devices, then gave its answer as plain text instead of through say, and the bridge dropped
# that text on the floor: two model round trips, no say cmd to the chat device, no log line, and the
# harness timed out after 30 s. An Agent with str output invites exactly that ending, so
# handle_request must speak the run's final output to the requester whenever the model did not,
# without repeating an answer the model already spoke through say.
POST_SWAP_ANSWER = (
    'One computer, "harness-worker", is connected; it can report status and list and push chest '
    "slots. No turtles right now."
)


class LogCatcher(logging.Handler):
    """Collects the bridge logger's formatted messages for the duration of one test."""

    def __init__(self) -> None:
        super().__init__()
        self.lines: list[str] = []

    def emit(self, record: logging.LogRecord) -> None:
        self.lines.append(record.getMessage())


async def test_plain_text_answer_is_spoken_to_the_requester_when_the_model_skips_say() -> None:
    rec = configure({"harness-worker": computer()})
    script = Script(call("list_devices"), POST_SWAP_ANSWER)  # the 22:17 shape: tool, then text
    catcher = LogCatcher()
    logging.getLogger("bridge").addHandler(catcher)
    try:
        await run_request(script, "DisraSenkovi", "what devices are connected?")
    finally:
        logging.getLogger("bridge").removeHandler(catcher)
    assert len(script.tools_seen) == 2, script.tools_seen  # two model round trips, as observed
    assert rec.said == [(POST_SWAP_ANSWER, "DisraSenkovi")], rec.said  # whispered to the asker
    assert any(POST_SWAP_ANSWER in line for line in catcher.lines), catcher.lines


async def test_answer_the_model_spoke_through_say_is_not_repeated() -> None:
    rec = configure({"harness-worker": computer()})
    spoken = "Just one computer, harness-worker, and the chat box."
    # The pre-swap 21:09 shape: list_devices, say(to=null), then a throwaway closing text.
    script = Script(call("list_devices"), call("say", text=spoken, to=None), "Done.")
    await run_request(script, "DisraSenkovi", "what devices are connected?")
    assert rec.said == [(spoken, None)], rec.said  # once, exactly as the model sent it


async def test_blank_final_output_without_say_speaks_nothing() -> None:
    # A completely empty response never reaches handle_request: pydantic-ai retries the model on it
    # and raises UnexpectedModelBehavior if it stays empty, which bridge.on_event's fallback speaks.
    # A whitespace-only answer does come through as the output and must not become a blank say.
    rec = configure({})
    await run_request(Script(call("list_devices"), "  \n"), "Nate", "hello")
    assert rec.said == [], rec.said
    assert user_prompts(histories()["Nate"]) == ["[Nate] hello"]  # the turn is still remembered


# ----------------------------------------------------------------- runner (TAP output)
TESTS: list[Callable[[], Any]] = [
    test_list_chest_without_name_is_rejected_before_the_tool_runs,
    test_device_tool_returns_send_cmd_result_without_raising,
    test_device_tool_with_no_worker_returns_error_dict,
    test_explicit_device_overrides_default_worker,
    test_push_one_slot_wire_args_match_client_lua,
    test_move_forwards_dir_and_steps_and_omits_unset_fields,
    test_every_primitive_is_a_typed_tool_with_the_lua_signature,
    test_toolset_with_no_devices_has_only_local_tools,
    test_toolset_with_computer_worker_adds_only_its_caps,
    test_toolset_with_turtle_adds_all_eight_primitives,
    test_toolset_is_rebuilt_from_the_live_registry_each_call,
    test_local_tools_carry_the_old_descriptions,
    test_list_devices_reports_roles_and_caps_only,
    test_say_tool_calls_the_injected_say_and_accepts_null_to,
    test_say_without_text_is_rejected_before_it_speaks,
    test_configure_builds_the_agent_on_the_injected_anthropic_client,
    test_agent_has_no_tools_of_its_own_and_uses_system_as_instructions,
    test_handle_request_keeps_the_phase_1_signature,
    test_handle_request_runs_the_model_with_the_per_run_toolset,
    test_handle_request_keeps_history_per_player,
    test_failed_run_raises_and_leaves_that_players_history_untouched,
    test_history_is_bounded_and_trimmed_on_turn_boundaries,
    test_runaway_tool_loop_is_cut_off_and_history_untouched,
    test_plain_text_answer_is_spoken_to_the_requester_when_the_model_skips_say,
    test_answer_the_model_spoke_through_say_is_not_repeated,
    test_blank_final_output_without_say_speaks_nothing,
]


def main() -> int:
    passed = failed = 0
    print(f"1..{len(TESTS)}")
    for n, fn in enumerate(TESTS, 1):
        try:
            if inspect.iscoroutinefunction(fn):
                asyncio.run(fn())
            else:
                fn()
        except Exception as exc:
            failed += 1
            print(f"not ok {n} - {fn.__name__}")
            detail = "".join(traceback.format_exception_only(type(exc), exc)).strip()
            print("  ---")
            print(f"  error: {detail}")
            print("  ...")
        else:
            passed += 1
            print(f"ok {n} - {fn.__name__}")
    print(f"# tests {len(TESTS)}")
    print(f"# pass {passed}")
    print(f"# fail {failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
