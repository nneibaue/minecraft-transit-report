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

from pydantic_ai import FunctionToolset  # noqa: E402
from pydantic_ai.messages import ToolReturnPart  # noqa: E402
from test_agent import (  # noqa: E402
    Script,
    call,
    configure,
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


# ----------------------------------------------------------------- runner (TAP output)
TESTS: list[Callable[[], Any]] = [
    test_rules_path_sits_beside_env_resolved_from_the_source_file,
    test_load_rules_without_a_file_returns_an_empty_rule_book,
    test_add_rule_then_list_rules_shows_the_rule_in_process_and_on_disk,
    test_remove_rule_drops_the_first_exact_match_only,
    test_set_overflow_is_saved_and_reported_by_list_rules,
    test_rule_tools_are_always_offered_whatever_is_connected,
    test_rules_json_is_git_ignored,
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
