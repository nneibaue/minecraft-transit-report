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
    ModelRequestPart,
    ModelResponse,
    ModelResponsePart,
    RetryPromptPart,
    TextPart,
    ToolCallPart,
    ToolReturnPart,
)
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

    def respond(self, messages: list[ModelMessage], info: AgentInfo) -> ModelResponse:
        self.tools_seen.append(sorted(t.name for t in info.function_tools))
        self.messages_seen.append(list(messages))
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
    a.configure(make_settings(), client, devices or {}, rec.send_cmd, rec.say, rec.default_worker)
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


# ----------------------------------------------------------------- runner (TAP output)
TESTS: list[Callable[[], Any]] = [
    test_list_chest_without_name_is_rejected_before_the_tool_runs,
    test_device_tool_returns_send_cmd_result_without_raising,
    test_device_tool_with_no_worker_returns_error_dict,
    test_explicit_device_overrides_default_worker,
    test_push_one_slot_wire_args_match_client_lua,
    test_move_forwards_dir_and_steps_and_omits_unset_fields,
    test_every_primitive_is_a_typed_tool_with_the_lua_signature,
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
