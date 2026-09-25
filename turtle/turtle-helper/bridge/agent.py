"""The Pydantic AI agent: typed device/local tools, per-run toolset and per-player chat handling."""

from __future__ import annotations

import logging
from collections.abc import Awaitable, Callable
from pathlib import Path
from typing import Literal

import anthropic
from pydantic import BaseModel, Field, ValidationError
from pydantic_ai import Agent, FunctionToolset, ModelRetry, RunContext
from pydantic_ai.messages import ModelMessage, ModelRequest, UserPromptPart
from pydantic_ai.models.anthropic import AnthropicModel
from pydantic_ai.providers.anthropic import AnthropicProvider
from pydantic_ai.usage import UsageLimits

from bridge import lua_pattern
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
say_in_chat: SayFn  # bridge.say(); named apart from the `say` tool the model calls
default_worker: DefaultWorkerFn
system: str
# The pydantic-ai Agent, built once in configure(). It carries the model and instructions
# only: every tool reaches it per run through build_toolset() (D-09), never at construction.
agent: Agent[None, str]

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
    """Hand runtime values from bridge.py to this module and build the Agent. Called once."""
    global settings, client, devices, send_cmd, say_in_chat, default_worker, system, agent
    settings = new_settings
    client = new_client
    devices = new_devices
    send_cmd = new_send_cmd
    say_in_chat = new_say
    default_worker = new_default_worker
    system = SYSTEM_TEMPLATE.format(robot_name=new_settings.robot_name)
    # AnthropicProvider wraps bridge.py's own client (the one main() already verified the model
    # against) rather than opening a second one from the API key.
    agent = Agent(
        AnthropicModel(new_settings.model, provider=AnthropicProvider(anthropic_client=new_client)),
        instructions=system,
    )


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
    result = await send_cmd(device_id, tool, wire)
    log.info("tool %s@%s(%s) -> %s", tool, device_id, wire, str(result)[:200])
    return result


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


# ----------------------------------------------------------------- local tools
# Always available, whatever is connected: they run on the bridge itself.


async def list_devices() -> dict[str, dict[str, object]]:
    """List connected devices, their roles and the tools each supports."""
    return {d: {"role": v["role"], "caps": v["caps"]} for d, v in devices.items()}


class SayArgs(BaseModel):
    """Arguments for say."""

    text: str
    to: str | None = Field(default=None, description="player name to whisper to; omit to broadcast")


async def say(ctx: RunContext[None], args: SayArgs) -> dict[str, object]:
    """Speak in game chat. Use once at the end with a short summary, not for every step."""
    await say_in_chat(args.text, args.to)
    return {"ok": True}


# ----------------------------------------------------------------- sorting rules (D-08)
# One global rule set for the one worker, kept on the bridge in rules.json beside .env: resolved
# from this file's location exactly as settings.py resolves .env, never from the process cwd. The
# file is git-ignored. The device stores only secret.txt and its Lua.
rules_path: Path = Path(__file__).resolve().parent.parent / "rules.json"


class SortRule(BaseModel):
    """One sorting rule: items whose id matches the Lua pattern go to dest."""

    pattern: str = Field(
        description="Lua pattern matched against item id, e.g. 'ingot' or '^minecraft:.*_log$'"
    )
    dest: str = Field(description="destination inventory peripheral name")


class RuleBook(BaseModel):
    """The saved sorting rules, in order (first match wins), and the overflow chest, if any."""

    rules: list[SortRule] = Field(default_factory=list)
    overflow: str | None = None


def load_rulebook(path: Path | None = None) -> RuleBook:
    """Read rules.json; a missing file is an empty rule book with no overflow, not an error."""
    path = rules_path if path is None else path
    if not path.exists():
        return RuleBook()
    return RuleBook.model_validate_json(path.read_text(encoding="utf-8"))


def save_rulebook(book: RuleBook, path: Path | None = None) -> None:
    """Write rules.json in full, via a sibling temp file so a crash mid-write cannot truncate it."""
    path = rules_path if path is None else path
    scratch = path.with_name(path.name + ".tmp")
    scratch.write_text(book.model_dump_json(indent=2) + "\n", encoding="utf-8")
    scratch.replace(path)


def load_rules() -> dict[str, object]:
    """The rule book as the JSON object the model sees: {"rules": [...], "overflow": ...}."""
    return load_rulebook().model_dump()


class AddRuleArgs(BaseModel):
    """Arguments for add_rule."""

    pattern: str = Field(
        description="Lua pattern matched against item id, e.g. 'ingot' or '^minecraft:.*_log$'"
    )
    dest: str = Field(description="destination inventory peripheral name")


class RemoveRuleArgs(BaseModel):
    """Arguments for remove_rule."""

    pattern: str = Field(description="the exact pattern of the rule to remove")


class SetOverflowArgs(BaseModel):
    """Arguments for set_overflow."""

    dest: str = Field(description="inventory peripheral name that receives unmatched items")


async def list_rules() -> dict[str, object]:
    """Show the sorting rules and overflow chest."""
    return load_rules()


async def add_rule(ctx: RunContext[None], args: AddRuleArgs) -> dict[str, object]:
    """Add a sorting rule: items whose id matches the Lua pattern go to dest. First matching rule wins."""  # noqa: E501
    try:
        lua_pattern.compile_pattern(args.pattern)
    except lua_pattern.LuaPatternError as exc:
        raise ModelRetry(f"{args.pattern!r} is not a usable Lua pattern: {exc}") from None
    book = load_rulebook()
    book.rules.append(SortRule(pattern=args.pattern, dest=args.dest))
    save_rulebook(book)
    return {"ok": True, "count": len(book.rules)}


async def remove_rule(ctx: RunContext[None], args: RemoveRuleArgs) -> dict[str, object]:
    """Remove a sorting rule by its exact pattern."""
    book = load_rulebook()
    index = next((i for i, rule in enumerate(book.rules) if rule.pattern == args.pattern), None)
    if index is None:
        return {"removed": False}
    del book.rules[index]
    save_rulebook(book)
    return {"removed": True}


async def set_overflow(ctx: RunContext[None], args: SetOverflowArgs) -> dict[str, object]:
    """Set the chest that receives items no rule matches."""
    book = load_rulebook()
    book.overflow = args.dest
    save_rulebook(book)
    return {"overflow": args.dest}


# ----------------------------------------------------------------- compositions (D-07)
# Anything with a loop or a policy lives here, never on the device. sort_chest is the loop
# client.lua used to run on-device (removed in plan 02-01), composed over the list_chest and
# push_one_slot primitives through the same send_cmd the forwarding tools use.


class ChestItem(BaseModel):
    """One occupied slot as client.lua's list_chest reports it."""

    slot: int
    name: str
    count: int


class ChestListing(BaseModel):
    """The data of a successful list_chest result."""

    name: str
    size: int
    items: list[ChestItem] = Field(default_factory=list)


class PushResult(BaseModel):
    """The data of a successful push_one_slot result: how many items pushItems moved."""

    moved: int


class SortOutcome(BaseModel):
    """What one sort_chest run achieved, in the shape the old Lua loop reported."""

    moved: int = 0
    no_rule: list[str] = Field(default_factory=list)  # item ids no rule (and no overflow) placed
    destination_full: list[str] = Field(default_factory=list)  # ids whose stack did not all fit

    def failed(self, error: str) -> dict[str, object]:
        """An error result that still reports the progress made before the failure."""
        return {"ok": False, "error": error, **self.model_dump()}


class SortChestArgs(DeviceArgs):
    """Arguments for sort_chest; `from_name` travels to the device as `from`."""

    from_name: str = Field(description="source inventory peripheral name")


def destination_for(item_name: str, book: RuleBook) -> str | None:
    """Where an item goes: the first rule whose Lua pattern matches wins, else the overflow."""
    for rule in book.rules:
        if lua_pattern.matches(item_name, rule.pattern):
            return rule.dest
    return book.overflow


async def sort_chest(ctx: RunContext[None], args: SortChestArgs) -> dict[str, object]:
    """Sort every item in an inventory into destinations using the saved rules. Returns counts and anything it couldn't place."""  # noqa: E501
    device_id = args.device or default_worker()
    if not device_id:
        return {"ok": False, "error": "no turtle or computer connected"}
    listed = await send_cmd(device_id, "list_chest", {"name": args.from_name})
    if not listed.get("ok"):
        return listed  # the device-side error, e.g. "no inventory called <from>"
    outcome = SortOutcome()
    try:
        listing = ChestListing.model_validate(listed.get("data"))
    except ValidationError:
        return outcome.failed(f"unexpected list_chest result from {device_id}: {listed!s:.200}")
    book = load_rulebook()
    for item in listing.items:
        dest = destination_for(item.name, book)
        if dest is None:
            if item.name not in outcome.no_rule:
                outcome.no_rule.append(item.name)
            continue
        wire: dict[str, object] = {
            "from": args.from_name,
            "slot": item.slot,
            "dest": dest,
            "limit": item.count,
        }
        pushed = await send_cmd(device_id, "push_one_slot", wire)
        if not pushed.get("ok"):
            return outcome.failed(f"push slot {item.slot} to {dest} failed: {pushed.get('error')}")
        try:
            moved = PushResult.model_validate(pushed.get("data")).moved
        except ValidationError:
            return outcome.failed(
                f"unexpected push_one_slot result from {device_id}: {pushed!s:.200}"
            )
        outcome.moved += moved
        if moved < item.count and item.name not in outcome.destination_full:
            outcome.destination_full.append(item.name)
    log.info("sort_chest@%s from %s -> %s", device_id, args.from_name, outcome)
    return outcome.model_dump()


# ----------------------------------------------------------------- per-run toolset (D-09)
DEVICE_PRIMITIVES: tuple[Callable[..., Awaitable[dict[str, object]]], ...] = (
    status,
    list_chest,
    push_one_slot,
    move,
    turn,
    dig,
    inspect,
    refuel,
)


# Each composition with the primitives it needs. Offered only when ONE connected device advertises
# all of them (D-09): the composition sends every command to that one device, so primitives split
# across two devices would not do.
COMPOSITIONS: tuple[tuple[Callable[..., Awaitable[dict[str, object]]], frozenset[str]], ...] = (
    (sort_chest, frozenset({"list_chest", "push_one_slot"})),
)


def _caps(entry: dict[str, object]) -> list[str]:
    caps = entry.get("caps")
    return [str(cap) for cap in caps] if isinstance(caps, list) else []


def build_toolset() -> FunctionToolset[None]:
    """The tools the model may call right now: local tools, every device primitive some connected
    device advertises in its hello caps, and each composition whose primitives one device has.

    Rebuilt from the live registry on every request, so with no turtle connected the model never
    sees move/turn/dig/inspect/refuel, and with no worker at all it sees only the local tools
    (list_devices, say and the four rule tools, which edit the bridge-side rules.json).
    """
    toolset: FunctionToolset[None] = FunctionToolset(
        [list_devices, say, list_rules, add_rule, remove_rule, set_overflow]
    )
    advertised = {cap for entry in devices.values() for cap in _caps(entry)}
    for primitive in DEVICE_PRIMITIVES:
        if primitive.__name__ in advertised:
            toolset.add_function(primitive)
    for composition, needed in COMPOSITIONS:
        if any(needed <= set(_caps(entry)) for entry in devices.values()):
            toolset.add_function(composition)
    return toolset


# ----------------------------------------------------------------- chat requests
# Per-player conversation memory, kept as pydantic-ai's own message objects so it can go straight
# back in as message_history. Only replaced after a run succeeds, so a failed request leaves the
# player's memory exactly as it was.
histories: dict[str, list[ModelMessage]] = {}
HISTORY_LIMIT = 40  # messages (requests + responses) kept per player
# The hand-rolled loop capped tool rounds at 12 per request; the same spend guard, as a UsageLimits.
REQUEST_LIMITS = UsageLimits(request_limit=12)


def _starts_turn(message: ModelMessage) -> bool:
    """True for the request that opens a turn: the one carrying the player's prompt."""
    return isinstance(message, ModelRequest) and any(
        isinstance(part, UserPromptPart) for part in message.parts
    )


def trim_history(messages: list[ModelMessage], limit: int = HISTORY_LIMIT) -> list[ModelMessage]:
    """Drop whole oldest turns until at most `limit` messages remain.

    Cutting anywhere but a turn boundary would leave a tool_result without its tool_use, which the
    API rejects on the next run. A single turn is at most 2 * request_limit messages, so one turn
    longer than the cap cannot happen; it would be kept whole if it did.
    """
    if len(messages) <= limit:
        return list(messages)
    for index in range(len(messages) - limit, len(messages)):
        if _starts_turn(messages[index]):
            return list(messages[index:])
    return list(messages)


async def handle_request(user: str, text: str) -> None:
    """Run one chat request through the agent and remember the exchange for that player.

    The model speaks through the say tool inside the run; nothing is spoken here. Anything that
    escapes agent.run() (a bug, a usage limit, a tool that exhausted its retries) propagates to
    bridge.on_event's catch-all, and this player's history stays as it was.
    """
    log.info("request from %s: %s", user, text)
    result = await agent.run(
        f"[{user}] {text}",
        message_history=histories.get(user, []),
        toolsets=[build_toolset()],
        usage_limits=REQUEST_LIMITS,
    )
    histories[user] = trim_history(result.all_messages())
