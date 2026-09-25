"""The Pydantic AI agent: typed device/local tools, per-run toolset and per-player chat handling."""

from __future__ import annotations

import logging
from collections.abc import Awaitable, Callable
from typing import Literal

import anthropic
from pydantic import BaseModel, Field
from pydantic_ai import RunContext

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


# ----------------------------------------------------------------- device-forwarding tools
# One Pydantic argument model and one async tool function per client.lua primitive (D-06).
# pydantic-ai derives each tool's JSON schema from its argument model and its description from
# the docstring, and validates the model's call arguments before the function body runs: a
# malformed call goes back to the model as a retry prompt, never as a Python exception. Each
# function forwards the validated arguments to the device over the injected send_cmd and
# returns its result dict unchanged (send_cmd never raises, per plan 02-02).


class DeviceArgs(BaseModel):
    """Arguments every device-forwarding tool accepts: which connected device runs it."""

    device: str | None = Field(
        default=None, description="device id to send this to; omit to use the default worker"
    )


class StatusArgs(DeviceArgs):
    """Arguments for status."""


class ListChestArgs(DeviceArgs):
    """Arguments for list_chest."""

    name: str = Field(description="peripheral name e.g. minecraft:chest_0")


class PushOneSlotArgs(DeviceArgs):
    """Arguments for push_one_slot; `from_name` travels to the device as `from`."""

    from_name: str = Field(description="source inventory peripheral name")
    slot: int = Field(description="slot number in the source inventory")
    dest: str = Field(description="destination inventory peripheral name")
    limit: int | None = Field(
        default=None, description="most items to move from that slot; omit for the whole stack"
    )


class MoveArgs(DeviceArgs):
    """Arguments for move."""

    dir: Literal["forward", "back", "up", "down"]
    steps: int | None = Field(default=None, description="how many blocks to move; default 1")


class TurnArgs(DeviceArgs):
    """Arguments for turn."""

    dir: Literal["left", "right"]


class DigArgs(DeviceArgs):
    """Arguments for dig."""

    dir: Literal["forward", "up", "down"] = "forward"


class InspectArgs(DeviceArgs):
    """Arguments for inspect."""


class RefuelArgs(DeviceArgs):
    """Arguments for refuel."""

    count: int | None = Field(default=None, description="fuel items to burn per slot; default 1")


async def _forward(
    args: DeviceArgs, tool: str, wire: dict[str, object] | None = None
) -> dict[str, object]:
    """Send one primitive to args.device (or the default worker) and return the device's result.

    `wire` overrides the argument dict put on the wire; by default it is the model's fields minus
    `device`, with unset optionals omitted so the Lua side sees nil for them.
    """
    device_id = args.device or default_worker()
    if not device_id:
        return {"ok": False, "error": "no turtle or computer connected"}
    if wire is None:
        wire = args.model_dump(exclude={"device"}, exclude_none=True)
    return await send_cmd(device_id, tool, wire)


async def status(ctx: RunContext[None], args: StatusArgs) -> dict[str, object]:
    """Fuel, position, and attached peripherals of a device."""
    return await _forward(args, "status")


async def list_chest(ctx: RunContext[None], args: ListChestArgs) -> dict[str, object]:
    """List the items in an inventory on the wired network."""
    return await _forward(args, "list_chest")


async def push_one_slot(ctx: RunContext[None], args: PushOneSlotArgs) -> dict[str, object]:
    """Push one slot of a source inventory into a destination inventory over the wired network.

    The device never carries the items. Returns {"moved": <count>} from the device.
    """
    wire: dict[str, object] = {"from": args.from_name, "slot": args.slot, "dest": args.dest}
    if args.limit is not None:
        wire["limit"] = args.limit
    return await _forward(args, "push_one_slot", wire)


async def move(ctx: RunContext[None], args: MoveArgs) -> dict[str, object]:
    """Move a turtle up to N steps. Stops early if blocked."""
    return await _forward(args, "move")


async def turn(ctx: RunContext[None], args: TurnArgs) -> dict[str, object]:
    """Turn a turtle left or right."""
    return await _forward(args, "turn")


async def dig(ctx: RunContext[None], args: DigArgs) -> dict[str, object]:
    """Dig the block in a direction."""
    return await _forward(args, "dig")


async def inspect(ctx: RunContext[None], args: InspectArgs) -> dict[str, object]:
    """Name the blocks in front, above and below a turtle."""
    return await _forward(args, "inspect")


async def refuel(ctx: RunContext[None], args: RefuelArgs) -> dict[str, object]:
    """Burn fuel items from the turtle's inventory."""
    return await _forward(args, "refuel")


# ----------------------------------------------------------------- chat requests
async def handle_request(user: str, text: str) -> None:
    """Process one chat request from a player. Rebuilt on agent.run() in plan 02-05 Task 3."""
    raise NotImplementedError("the agent loop is being rebuilt on pydantic-ai (plan 02-05)")
