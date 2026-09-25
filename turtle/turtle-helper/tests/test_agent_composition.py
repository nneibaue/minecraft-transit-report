"""Zero-spend checks for bridge/agent.py's bridge-side rules and composition (Phase 2 plan 02-06).

Covers D-08 (sorting rules persist on the bridge in a git-ignored ``rules.json`` beside ``.env``,
edited through ``list_rules``/``add_rule``/``remove_rule``/``set_overflow``) and D-07's Python
half (``sort_chest`` composing ``list_chest`` + ``push_one_slot`` over the wire). Same style as
``tests/test_agent.py``, whose fakes and scripted model this module reuses: no model call, no
network, no test-framework dependency; running the file directly emits TAP.

    uv run python tests/test_agent_composition.py
"""

from __future__ import annotations

import asyncio
import inspect
import json
import os
import subprocess
import sys
import tempfile
import traceback
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
os.environ.setdefault("PYDANTIC_AI_NO_BANNER", "1")  # keep pydantic-ai's banner off the TAP stream

import anthropic  # noqa: E402
from pydantic_ai import FunctionToolset  # noqa: E402
from pydantic_ai.messages import RetryPromptPart, ToolReturnPart  # noqa: E402
from test_agent import (  # noqa: E402
    Recorder,
    Script,
    call,
    configure,
    make_settings,
    parts,
    require_build_toolset,
    require_tool,
    run_tool_through_model,
)

from bridge import agent as a  # noqa: E402
from bridge.settings import Settings  # noqa: E402

PROJECT_DIR = Path(__file__).resolve().parent.parent

RULE_TOOLS = ["add_rule", "list_rules", "remove_rule", "set_overflow"]

# The description strings the pre-swap LOCAL_TOOLS/DEVICE_TOOLS dicts carried for these tools.
CARRIED_DESCRIPTIONS = {
    "list_rules": "Show the sorting rules and overflow chest.",
    "add_rule": (
        "Add a sorting rule: items whose id matches the Lua pattern go to dest. "
        "First matching rule wins."
    ),
    "remove_rule": "Remove a sorting rule by its exact pattern.",
    "set_overflow": "Set the chest that receives items no rule matches.",
}


def require_attr(name: str) -> Any:
    value = getattr(a, name, None)
    assert value is not None, f"agent.py defines no {name!r}"
    return value


@contextmanager
def rules_in_temp_dir() -> Iterator[Path]:
    """Point agent.rules_path at a fresh temp file for one test; restore it afterwards."""
    require_attr("rules_path")
    previous = a.rules_path
    with tempfile.TemporaryDirectory() as tmp:
        a.rules_path = Path(tmp) / "rules.json"
        try:
            yield a.rules_path
        finally:
            a.rules_path = previous


async def tool_returns(tool_name: str, *calls: list[Any]) -> list[Any]:
    """Run one tool through the scripted model for each call and collect what it returned."""
    tool = require_tool(tool_name)
    messages = await run_tool_through_model(tool, Script(*calls, "done"))
    return [p.content for p in parts(messages) if isinstance(p, ToolReturnPart)]


# ----------------------------------------------------------------- Task 1: rules.json + rule tools
def test_rules_path_sits_beside_env_resolved_from_the_source_file() -> None:
    rules_path = require_attr("rules_path")
    assert isinstance(rules_path, Path), type(rules_path)
    assert rules_path == PROJECT_DIR / "rules.json", rules_path
    env_file = Settings.model_config["env_file"]
    assert isinstance(env_file, Path), env_file
    assert rules_path.parent == env_file.parent, (rules_path, env_file)
    assert rules_path.is_absolute(), rules_path


def test_load_rules_without_a_file_returns_an_empty_rule_book() -> None:
    load_rules = require_attr("load_rules")
    with rules_in_temp_dir() as path:
        assert not path.exists()
        assert load_rules() == {"rules": [], "overflow": None}
        assert not path.exists(), "load_rules() must not create the file"


async def test_add_rule_then_list_rules_shows_the_rule_in_process_and_on_disk() -> None:
    configure({})
    with rules_in_temp_dir() as path:
        added = await tool_returns(
            "add_rule",
            call("add_rule", pattern="_ore$", dest="minecraft:chest_1"),
            call("add_rule", pattern="^minecraft:", dest="minecraft:chest_2"),
        )
        assert added == [{"ok": True, "count": 1}, {"ok": True, "count": 2}], added
        listed = await tool_returns("list_rules", call("list_rules"))
        expected = {
            "rules": [
                {"pattern": "_ore$", "dest": "minecraft:chest_1"},
                {"pattern": "^minecraft:", "dest": "minecraft:chest_2"},
            ],
            "overflow": None,
        }
        assert listed == [expected], listed
        assert json.loads(path.read_text(encoding="utf-8")) == expected, path.read_text()


async def test_remove_rule_drops_the_first_exact_match_only() -> None:
    configure({})
    with rules_in_temp_dir() as path:
        await tool_returns(
            "add_rule",
            call("add_rule", pattern="ingot", dest="minecraft:chest_1"),
            call("add_rule", pattern="ingot", dest="minecraft:chest_2"),
            call("add_rule", pattern="_ore$", dest="minecraft:chest_3"),
        )
        removed = await tool_returns(
            "remove_rule",
            call("remove_rule", pattern="ingot"),
            call("remove_rule", pattern="ingo"),  # a prefix is not an exact match
            call("remove_rule", pattern="nothing-like-this"),
        )
        assert removed == [{"removed": True}, {"removed": False}, {"removed": False}], removed
        on_disk = json.loads(path.read_text(encoding="utf-8"))
        assert on_disk["rules"] == [
            {"pattern": "ingot", "dest": "minecraft:chest_2"},
            {"pattern": "_ore$", "dest": "minecraft:chest_3"},
        ], on_disk


async def test_set_overflow_is_saved_and_reported_by_list_rules() -> None:
    configure({})
    with rules_in_temp_dir() as path:
        result = await tool_returns("set_overflow", call("set_overflow", dest="minecraft:chest_9"))
        assert result == [{"overflow": "minecraft:chest_9"}], result
        listed = await tool_returns("list_rules", call("list_rules"))
        assert listed == [{"rules": [], "overflow": "minecraft:chest_9"}], listed
        assert json.loads(path.read_text(encoding="utf-8"))["overflow"] == "minecraft:chest_9"
        # load_rules() reads the same file back, so a restarted bridge sees the same overflow
        assert require_attr("load_rules")()["overflow"] == "minecraft:chest_9"


def test_rule_tools_are_always_offered_whatever_is_connected() -> None:
    registries: tuple[dict[str, dict[str, object]], ...] = (
        {},
        {"chat-1": {"role": "chat", "caps": ["say"]}},
        {"w1": {"role": "computer", "caps": ["status"]}},
    )
    for registry in registries:
        configure(dict(registry))
        toolset = require_build_toolset()()
        for name in RULE_TOOLS:
            assert name in toolset.tools, (registry, sorted(toolset.tools))
            assert toolset.tools[name].description == CARRIED_DESCRIPTIONS[name], (
                name,
                toolset.tools[name].description,
            )
    schemas = {
        name: FunctionToolset([require_tool(name)]).tools[name].function_schema.json_schema
        for name in RULE_TOOLS
    }
    assert schemas["add_rule"].get("required") == ["pattern", "dest"], schemas["add_rule"]
    assert schemas["remove_rule"].get("required") == ["pattern"], schemas["remove_rule"]
    assert schemas["set_overflow"].get("required") == ["dest"], schemas["set_overflow"]
    assert schemas["list_rules"].get("required", []) == [], schemas["list_rules"]
    for name in RULE_TOOLS:
        assert "device" not in schemas[name].get("properties", {}), (name, schemas[name])


def test_rules_json_is_git_ignored() -> None:
    lines = (PROJECT_DIR / ".gitignore").read_text(encoding="utf-8").splitlines()
    assert "rules.json" in lines, lines
    check = subprocess.run(
        ["git", "check-ignore", "-q", str(PROJECT_DIR / "rules.json")],
        cwd=PROJECT_DIR,
        check=False,
    )
    assert check.returncode == 0, "git does not ignore turtle-helper/rules.json"


# ----------------------------------------------------------------- Task 2: sort_chest (D-07)
# The pre-swap DEVICE_TOOLS description; the composed tool must read the same to the model.
SORT_CHEST_DESCRIPTION = (
    "Sort every item in an inventory into destinations using the saved rules. "
    "Returns counts and anything it couldn't place."
)
SOURCE = "minecraft:chest_0"
BOTH = ["list_chest", "push_one_slot", "status"]  # what a plain computer running client.lua has


class Worker(Recorder):
    """A recorder that answers each device tool from its own scripted queue of result frames."""

    def __init__(
        self, replies: dict[str, list[dict[str, object]]], worker: str | None = "w1"
    ) -> None:
        super().__init__(worker=worker)
        self.replies_by_tool = {tool: list(queue) for tool, queue in replies.items()}

    async def send_cmd(
        self, device_id: str, tool: str, args: dict[str, object] | None = None
    ) -> dict[str, object]:
        self.cmds.append((device_id, tool, args))
        queue = self.replies_by_tool.get(tool)
        return queue.pop(0) if queue else {"ok": True, "data": {}}


def wire(rec: Recorder, devices: dict[str, dict[str, object]] | None = None) -> None:
    """agent.configure() with this recorder's fakes, the way bridge.main() wires the real ones."""
    client = anthropic.AsyncAnthropic(api_key="sk-ant-test")  # never used to send anything
    registry = devices if devices is not None else {}
    a.configure(make_settings(), client, registry, rec.send_cmd, rec.say, rec.default_worker)
    a.histories.clear()


def listing(*items: tuple[int, str, int]) -> dict[str, object]:
    """A list_chest result frame with data shaped like client.lua's tools.list_chest."""
    data = {
        "name": SOURCE,
        "size": 27,
        "items": [{"slot": slot, "name": name, "count": count} for slot, name, count in items],
    }
    return {"type": "result", "cid": "c1", "ok": True, "data": data}


def pushed(moved: int) -> dict[str, object]:
    """A push_one_slot result frame: client.lua returns {moved = pushItems(...)}."""
    return {"type": "result", "cid": "c2", "ok": True, "data": {"moved": moved}}


def failed(error: str) -> dict[str, object]:
    """The result frame session() sends when a tool raised (pcall caught it)."""
    return {"type": "result", "cid": "c3", "ok": False, "error": error}


def write_rules(path: Path, *rules: tuple[str, str], overflow: str | None = None) -> None:
    book = {"rules": [{"pattern": p, "dest": d} for p, d in rules], "overflow": overflow}
    path.write_text(json.dumps(book), encoding="utf-8")


async def sort(**args: object) -> list[Any]:
    """Drive sort_chest once through the scripted model and return what it handed back."""
    tool = require_tool("sort_chest")
    messages = await run_tool_through_model(tool, Script(call("sort_chest", **args), "done"))
    return [p.content for p in parts(messages) if isinstance(p, ToolReturnPart)]


def pushes(rec: Recorder) -> list[tuple[str, object, object]]:
    return [
        (device, args["slot"], args["dest"])
        for device, tool, args in rec.cmds
        if tool == "push_one_slot" and args is not None
    ]


def test_sort_chest_is_offered_only_when_one_device_has_both_primitives() -> None:
    turtle_caps = [
        "dig",
        "inspect",
        "list_chest",
        "move",
        "push_one_slot",
        "refuel",
        "status",
        "turn",
    ]
    cases: list[tuple[dict[str, dict[str, object]], bool]] = [
        ({}, False),
        ({"chat-1": {"role": "chat", "caps": ["say"]}}, False),
        ({"w1": {"role": "computer", "caps": BOTH}}, True),
        ({"t1": {"role": "turtle", "caps": turtle_caps}}, True),
        ({"w1": {"role": "computer", "caps": ["list_chest", "status"]}}, False),
        ({"w1": {"role": "computer", "caps": ["push_one_slot", "status"]}}, False),
        # one primitive each on two devices is not enough: a single device must advertise both
        (
            {
                "w1": {"role": "computer", "caps": ["list_chest"]},
                "w2": {"role": "computer", "caps": ["push_one_slot"]},
            },
            False,
        ),
        (
            {"chat-1": {"role": "chat", "caps": ["say"]}, "w1": {"role": "computer", "caps": BOTH}},
            True,
        ),
    ]
    for registry, expected in cases:
        configure(dict(registry))
        names = sorted(require_build_toolset()().tools)
        assert ("sort_chest" in names) is expected, (registry, names)


def test_sort_chest_args_take_from_name_and_an_optional_device() -> None:
    configure({})
    registered = FunctionToolset([require_tool("sort_chest")]).tools["sort_chest"]
    schema = registered.function_schema.json_schema
    assert schema.get("required") == ["from_name"], schema
    assert set(schema["properties"]) == {"device", "from_name"}, schema
    assert registered.description == SORT_CHEST_DESCRIPTION, registered.description


async def test_sort_chest_pushes_each_matched_item_and_reports_what_it_could_not_place() -> None:
    rec = Worker(
        {
            "list_chest": [
                listing(
                    (1, "minecraft:iron_ore", 10),
                    (2, "minecraft:cobblestone", 64),
                    (5, "minecraft:diamond", 3),
                )
            ],
            "push_one_slot": [pushed(10), pushed(1)],  # the diamond chest takes only one
        }
    )
    wire(rec)
    with rules_in_temp_dir() as path:
        write_rules(path, ("_ore$", "minecraft:chest_1"), ("diamond", "minecraft:chest_2"))
        result = await sort(from_name=SOURCE)
    assert result == [
        {
            "moved": 11,
            "no_rule": ["minecraft:cobblestone"],
            "destination_full": ["minecraft:diamond"],
        }
    ], result
    assert rec.cmds == [
        ("w1", "list_chest", {"name": SOURCE}),
        (
            "w1",
            "push_one_slot",
            {"from": SOURCE, "slot": 1, "dest": "minecraft:chest_1", "limit": 10},
        ),
        (
            "w1",
            "push_one_slot",
            {"from": SOURCE, "slot": 5, "dest": "minecraft:chest_2", "limit": 3},
        ),
    ], rec.cmds


async def test_sort_chest_first_matching_rule_wins_then_overflow_catches_the_rest() -> None:
    rec = Worker(
        {
            "list_chest": [
                listing(
                    (1, "minecraft:iron_ore", 8),
                    (2, "minecraft:cobblestone", 64),
                    (3, "mekanism:hdpe_sheet", 5),
                )
            ],
            "push_one_slot": [pushed(8), pushed(64), pushed(5)],
        }
    )
    wire(rec, {"t9": {"role": "turtle", "caps": BOTH}})
    with rules_in_temp_dir() as path:
        write_rules(
            path,
            ("_ore$", "minecraft:chest_1"),  # iron_ore matches this AND the next; first wins
            ("^minecraft:", "minecraft:chest_2"),
            overflow="minecraft:chest_9",
        )
        result = await sort(device="t9", from_name=SOURCE)
    assert result == [{"moved": 77, "no_rule": [], "destination_full": []}], result
    assert pushes(rec) == [
        ("t9", 1, "minecraft:chest_1"),
        ("t9", 2, "minecraft:chest_2"),
        ("t9", 3, "minecraft:chest_9"),
    ], rec.cmds


async def test_sort_chest_returns_the_list_chest_error_and_pushes_nothing() -> None:
    error = failed("no inventory called minecraft:chest_0")
    rec = Worker({"list_chest": [error]})
    wire(rec)
    with rules_in_temp_dir() as path:
        write_rules(path, ("ore", "minecraft:chest_1"))
        result = await sort(from_name=SOURCE)
    assert result == [error], result
    assert [tool for _, tool, _ in rec.cmds] == ["list_chest"], rec.cmds
    nobody = Worker({}, worker=None)
    wire(nobody)
    no_worker = await sort(from_name=SOURCE)
    assert no_worker == [{"ok": False, "error": "no turtle or computer connected"}], no_worker
    assert nobody.cmds == [], nobody.cmds


async def test_sort_chest_stops_on_a_failed_push_and_reports_progress() -> None:
    rec = Worker(
        {
            "list_chest": [
                listing(
                    (1, "minecraft:iron_ore", 8),
                    (2, "minecraft:gold_ore", 4),
                    (3, "minecraft:copper_ore", 2),
                )
            ],
            "push_one_slot": [pushed(8), failed("no inventory called minecraft:chest_404")],
        }
    )
    wire(rec)
    with rules_in_temp_dir() as path:
        write_rules(path, ("iron", "minecraft:chest_1"), ("_ore$", "minecraft:chest_404"))
        (result,) = await sort(from_name=SOURCE)
    assert result.get("ok") is False, result
    assert "minecraft:chest_404" in str(result.get("error")), result
    assert result.get("moved") == 8, result  # what had been moved before the failure
    assert len(pushes(rec)) == 2, rec.cmds  # slot 3 is never attempted after the failure


def test_lua_patterns_match_like_string_find_not_like_regex() -> None:
    from bridge import lua_pattern

    cases = [
        ("minecraft:iron_ore", "_ore$", True),
        ("minecraft:iron_ore_block", "_ore$", False),
        ("minecraft:oak_log", "^minecraft:.*_log$", True),
        ("mekanism:oak_log", "^minecraft:", False),
        ("minecraft:iron_ingot", "%a+:iron_ingot", True),
        ("minecraft:iron_ingot", "ingot", True),
        ("a.b", "a%.b", True),
        ("axb", "a%.b", False),  # %. is a literal dot, unlike regex's unescaped dot
        ("minecraft:chest_3", "chest_%d+$", True),
        ("minecraft:chest_x", "chest_%d+$", False),
        ("minecraft:x", "^[%a_]+:%l$", True),
        ("MINECRAFT:x", "^[%l_]+:", False),
        ("ab", "a%d-b", True),  # `-` is Lua's lazy repeat, not a literal hyphen
        ("a12b", "a%d-b", True),
        ("mekanism:hdpe_sheet", "[^:]+:hdpe", True),
        ("minecraft:iron_ore", "iron+", True),
        ("minecraft:iron_ore", "^iron", False),
    ]
    for text, pattern, expected in cases:
        assert lua_pattern.matches(text, pattern) is expected, (text, pattern, expected)
    for unsupported in ("%b()", "%f[%w]x", "(a)%1", "[unclosed", "trailing%"):
        try:
            lua_pattern.matches("abc", unsupported)
        except lua_pattern.LuaPatternError:
            pass
        else:
            raise AssertionError(f"{unsupported!r} should be rejected as an unsupported pattern")


async def test_add_rule_rejects_a_malformed_lua_pattern_with_a_retry() -> None:
    configure({})
    with rules_in_temp_dir() as path:
        tool = require_tool("add_rule")
        script = Script(call("add_rule", pattern="[unclosed", dest="minecraft:chest_1"), "done")
        messages = await run_tool_through_model(tool, script)
        retries = [p for p in parts(messages) if isinstance(p, RetryPromptPart)]
        assert len(retries) == 1 and retries[0].tool_name == "add_rule", [
            type(p).__name__ for p in parts(messages)
        ]
        assert "[unclosed" in str(retries[0].content), retries[0].content
        assert not path.exists(), "a rejected rule must not be saved"


# ----------------------------------------------------------------- runner (TAP output)
TESTS: list[Callable[[], Any]] = [
    test_rules_path_sits_beside_env_resolved_from_the_source_file,
    test_load_rules_without_a_file_returns_an_empty_rule_book,
    test_add_rule_then_list_rules_shows_the_rule_in_process_and_on_disk,
    test_remove_rule_drops_the_first_exact_match_only,
    test_set_overflow_is_saved_and_reported_by_list_rules,
    test_rule_tools_are_always_offered_whatever_is_connected,
    test_rules_json_is_git_ignored,
    test_sort_chest_is_offered_only_when_one_device_has_both_primitives,
    test_sort_chest_args_take_from_name_and_an_optional_device,
    test_sort_chest_pushes_each_matched_item_and_reports_what_it_could_not_place,
    test_sort_chest_first_matching_rule_wins_then_overflow_catches_the_rest,
    test_sort_chest_returns_the_list_chest_error_and_pushes_nothing,
    test_sort_chest_stops_on_a_failed_push_and_reports_progress,
    test_lua_patterns_match_like_string_find_not_like_regex,
    test_add_rule_rejects_a_malformed_lua_pattern_with_a_retry,
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
