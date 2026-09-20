"""The Claude tool-use agent loop: device/local tool schemas and per-player chat handling."""

from __future__ import annotations

import json
import logging
from collections.abc import Awaitable, Callable
from typing import Any, cast

import anthropic

from bridge.settings import Settings

log = logging.getLogger("bridge")

# ----------------------------------------------------------------- injected via configure()
# Annotation-only module globals: importing this module has zero side effects. bridge.py's
# main() calls configure() once, after Settings and the Anthropic client are built, to hand
# these values across the module boundary without agent.py ever importing bridge.py.
SendCmdFn = Callable[[str, str, dict[str, object] | None], Awaitable[dict[str, object]]]
SayFn = Callable[[str, str | None], Awaitable[None]]
DefaultWorkerFn = Callable[[], str | None]

settings: Settings
client: anthropic.AsyncAnthropic
devices: dict[str, dict[str, object]]
send_cmd: SendCmdFn
say: SayFn
default_worker: DefaultWorkerFn
system: str

SYSTEM_TEMPLATE = """You are {robot_name}, a helpful robot assistant living inside a Minecraft
(All the Mods 9) world, in the spirit of Heinlein's Hired Girl. Players give you chores in chat;
you carry them out using turtles and computers connected to you, then report back briefly.

Rules:
- Call list_devices first if you don't know what's connected. Pass "device" only when there are
  several.
- Prefer high-level tools (sort_chest) over step-by-step movement. Do not walk a turtle around
  one block at a time unless asked.
- When something can't be done, say so plainly and suggest what would fix it (e.g. a missing
  rule).
- Finish every task with exactly one say() containing a short, friendly summary (1-2 sentences).
  No markdown in chat.
- Item ids look like "minecraft:iron_ingot" or "mekanism:hdpe_sheet". Inventory names look like
  "minecraft:chest_3".
"""


def configure(
    new_settings: Settings,
    new_client: anthropic.AsyncAnthropic,
    new_devices: dict[str, dict[str, object]],
    new_send_cmd: SendCmdFn,
    new_say: SayFn,
    new_default_worker: DefaultWorkerFn,
) -> None:
    """Hand runtime values from bridge.py to this module. Called once, from main()."""
    global settings, client, devices, send_cmd, say, default_worker, system
    settings = new_settings
    client = new_client
    devices = new_devices
    send_cmd = new_send_cmd
    say = new_say
    default_worker = new_default_worker
    system = SYSTEM_TEMPLATE.format(robot_name=new_settings.robot_name)


# ----------------------------------------------------------------- agent tools
# Tools the model sees. Anything with "device" is forwarded to that device's Lua tool
# of the same name; the schema here is just so Claude fills args correctly.
DEVICE_TOOLS: list[dict[str, object]] = [
    {
        "name": "status",
        "description": "Fuel, position, and attached peripherals of a device.",
        "input_schema": {"type": "object", "properties": {"device": {"type": "string"}}},
    },
    {
        "name": "list_chest",
        "description": "List the items in an inventory on the wired network.",
        "input_schema": {
            "type": "object",
            "properties": {
                "device": {"type": "string"},
                "name": {"type": "string", "description": "peripheral name e.g. minecraft:chest_0"},
            },
            "required": ["name"],
        },
    },
    {
        "name": "sort_chest",
        "description": (
            "Sort every item in an inventory into destinations using the saved rules. "
            "Returns counts and anything it couldn't place."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "device": {"type": "string"},
                "from": {"type": "string", "description": "source inventory peripheral name"},
            },
            "required": ["from"],
        },
    },
    {
        "name": "list_rules",
        "description": "Show the sorting rules and overflow chest.",
        "input_schema": {"type": "object", "properties": {"device": {"type": "string"}}},
    },
    {
        "name": "add_rule",
        "description": (
            "Add a sorting rule: items whose id matches the Lua pattern go to dest. "
            "First matching rule wins."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "device": {"type": "string"},
                "pattern": {
                    "type": "string",
                    "description": (
                        "Lua pattern matched against item id, e.g. 'ingot' or '^minecraft:.*_log$'"
                    ),
                },
                "dest": {"type": "string", "description": "destination inventory peripheral name"},
            },
            "required": ["pattern", "dest"],
        },
    },
    {
        "name": "remove_rule",
        "description": "Remove a sorting rule by its exact pattern.",
        "input_schema": {
            "type": "object",
            "properties": {"device": {"type": "string"}, "pattern": {"type": "string"}},
            "required": ["pattern"],
        },
    },
    {
        "name": "set_overflow",
        "description": "Set the chest that receives items no rule matches.",
        "input_schema": {
            "type": "object",
            "properties": {"device": {"type": "string"}, "dest": {"type": "string"}},
            "required": ["dest"],
        },
    },
    {
        "name": "move",
        "description": "Move a turtle up to N steps. Stops early if blocked.",
        "input_schema": {
            "type": "object",
            "properties": {
                "device": {"type": "string"},
                "dir": {"type": "string", "enum": ["forward", "back", "up", "down"]},
                "steps": {"type": "integer"},
            },
            "required": ["dir"],
        },
    },
    {
        "name": "turn",
        "description": "Turn a turtle left or right.",
        "input_schema": {
            "type": "object",
            "properties": {
                "device": {"type": "string"},
                "dir": {"type": "string", "enum": ["left", "right"]},
            },
            "required": ["dir"],
        },
    },
    {
        "name": "dig",
        "description": "Dig the block in a direction.",
        "input_schema": {
            "type": "object",
            "properties": {
                "device": {"type": "string"},
                "dir": {"type": "string", "enum": ["forward", "up", "down"]},
            },
        },
    },
    {
        "name": "inspect",
        "description": "Name the blocks in front, above and below a turtle.",
        "input_schema": {"type": "object", "properties": {"device": {"type": "string"}}},
    },
    {
        "name": "refuel",
        "description": "Burn fuel items from the turtle's inventory.",
        "input_schema": {
            "type": "object",
            "properties": {"device": {"type": "string"}, "count": {"type": "integer"}},
        },
    },
]

LOCAL_TOOLS: list[dict[str, object]] = [
    {
        "name": "list_devices",
        "description": "List connected devices, their roles and the tools each supports.",
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "say",
        "description": (
            "Speak in game chat. Use once at the end with a short summary, not for every step."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "text": {"type": "string"},
                "to": {
                    "type": "string",
                    "description": "player name to whisper to; omit to broadcast",
                },
            },
            "required": ["text"],
        },
    },
]

histories: dict[str, list[dict[str, object]]] = {}  # per-player conversation memory
MAX_TURNS = 20


async def run_tool(name: str, args: dict[str, object]) -> dict[str, object]:
    """Execute a tool by name with JSON args, return a JSON-safe result."""
    if name == "list_devices":
        return {d: {"role": v["role"], "caps": v["caps"]} for d, v in devices.items()}
    if name == "say":
        to_arg = args.get("to")
        to = to_arg if isinstance(to_arg, str) else None
        await say(str(args["text"]), to)
        return {"ok": True}
    device_arg = args.pop("device", None)
    device = device_arg if isinstance(device_arg, str) else default_worker()
    if not device:
        return {"ok": False, "error": "no worker device connected"}
    return await send_cmd(device, name, args)


async def handle_request(user: str, text: str) -> None:
    """Process a chat request through the tool-use loop and speak the result."""
    log.info("request from %s: %s", user, text)
    hist = histories.setdefault(user, [])
    hist.append({"role": "user", "content": f"[{user}] {text}"})

    def _bad_start() -> bool:
        # must start on a plain user text message
        return hist[0]["role"] != "user" or not isinstance(hist[0]["content"], str)

    while len(hist) > 1 and (len(hist) > MAX_TURNS * 2 or _bad_start()):
        hist.pop(0)

    for _ in range(12):  # cap tool rounds per request
        # DEVICE_TOOLS/LOCAL_TOOLS and hist are plain JSON-shaped dicts (the tool-use loop is
        # hand-rolled, not the SDK's typed builders); cast past the SDK's generated TypedDict
        # unions rather than duplicate them here. Values are valid at runtime.
        resp = await client.messages.create(
            model=settings.model,
            max_tokens=1024,
            system=system,
            tools=cast(Any, DEVICE_TOOLS + LOCAL_TOOLS),
            messages=cast(Any, hist),
        )
        hist.append({"role": "assistant", "content": resp.content})
        if resp.stop_reason != "tool_use":
            break
        results = []
        for block in resp.content:
            if block.type == "tool_use":
                out = await run_tool(block.name, dict(block.input))
                log.info("tool %s(%s) -> %s", block.name, block.input, json.dumps(out)[:200])
                results.append(
                    {"type": "tool_result", "tool_use_id": block.id, "content": json.dumps(out)}
                )
        hist.append({"role": "user", "content": results})
