# Phase 2: Fake Device Harness & Protocol Resilience - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-22 (discussion ran 2026-09-20 to 2026-09-22)
**Phase:** 2-fake-device-harness-protocol-resilience
**Areas discussed:** Harness driving model, Pydantic AI rewrite: order and shape, Drop and reconnect rules, Proof format and spend guard

---

## Harness driving model

### How is the harness driven from the terminal?

| Option | Description | Selected |
|--------|-------------|----------|
| Scripted scenarios by flag (Recommended) | `uv run harness --role chat --scenario devices-question`; deterministic, repeatable, drop and reconnect become scenario steps | ✓ |
| Interactive REPL | A prompt for `chat`, `drop`, `reconnect`, `result`; good for poking, proofs hard to repeat | |
| Both: scenarios plus --repl | Named scenarios plus a `--repl` mode; more code, REPL useful again in Phase 4 | |

**User's choice:** Scripted scenarios by flag

### One fake device per process, or can one harness process play several devices at once?

| Option | Description | Selected |
|--------|-------------|----------|
| One process per role, two terminals (Recommended) | Matches `--role chat\|worker`; bridge log is where the sides interleave | ✓ |
| One process can host both roles | Two websockets in one process; single terminal shows the whole conversation | |
| Both supported | Two-terminal default plus optional multi-role mode | |

**User's choice:** One process per role, two terminals

### What does the fake worker announce in its hello, and which commands does it answer with canned results?

| Option | Description | Selected |
|--------|-------------|----------|
| Mirror client.lua on a computer (Recommended) | Role `computer` with client.lua's caps; `status` shaped like `tools.status`; other listed tools canned; anything else the same unknown-tool error; `--turtle` adds movement caps | ✓ |
| Canned result for every DEVICE_TOOL | Role `turtle`, every bridge tool advertised and answered (research §1.4) | |
| status only | Advertise and answer only `status` | |

**User's choice:** Mirror client.lua on a computer
**Notes:** After the thin-Lua decision below, "client.lua's caps" means the primitive set.

### How should the harness print the wire traffic it sends and receives?

| Option | Description | Selected |
|--------|-------------|----------|
| One line per message with direction (Recommended) | Timestamp, device id, arrow, compact JSON as sent | ✓ |
| Pretty-printed JSON blocks | Indented JSON per message | |
| Compact lines plus a --verbose pretty mode | Compact by default, flag for indented | |

**User's choice:** One line per message with direction

---

## Pydantic AI rewrite: order and shape

### When does the Pydantic AI swap of agent.py happen relative to the harness work?

| Option | Description | Selected |
|--------|-------------|----------|
| Harness and fixes first, swap last (Recommended) | Build harness and disconnect fixes on today's loop, swap as final plan, re-run the devices question; two paid calls | ✓ |
| Swap first, then the harness | One paid run, but first paid run debugs harness and new loop together | |
| Harness first, paid run only after the swap | One paid call; old loop never exercised end to end | |

**User's choice:** Harness and fixes first, swap last

### How do the device tools get exposed to the Pydantic AI agent?

| Option | Description | Selected |
|--------|-------------|----------|
| Custom toolset from the JSON schemas (Recommended) | One `AbstractToolset` from the existing `DEVICE_TOOLS` dicts, `call_tool` forwards over `send_cmd` | |
| Typed Python functions per tool | Each tool an `@agent.tool` function with Pydantic argument models; JSON dicts go away | ✓ (with extension) |
| You decide | Researcher confirms, planner picks | |

**User's choice:** Free text: leaning to typed Python functions, wants the Lua side as thin as possible because Lua is harder to maintain than Python; asked for thoughts.
**Notes:** Claude explained that neither option shrinks the Lua by itself; what shrinks it is moving composition (the sort loop, rules) into Python while Lua keeps primitives, and that typed functions are the shape that allows this. Claude recommended recording the direction now and keeping existing tools as one-to-one forwards this phase, flagging that moving Lua logic widens Phase 2 beyond the roadmap's "no Lua touched" framing. User replied "lets do them both now. throw fable at it": typed functions AND the composition move happen in this phase; do not scale the work down. Recorded as the author's decision over the scope caution. User also noted that Python agents may later return Lua with loops and that client-side updates will be needed because only the bridge is version controlled; both captured as deferred capabilities.

### With the sorting rules moving off the device, where do they persist?

| Option | Description | Selected |
|--------|-------------|----------|
| Bridge-side JSON file, one global set (Recommended) | Git-ignored `rules.json` beside `.env`; rule tools become local tools | ✓ |
| Bridge-side, keyed per device | Same file keyed by device id | |
| Still on the device | Keep `rules.json` on the computer, add read/write file primitives | |

**User's choice:** Bridge-side JSON file, one global set

### Which tools does the model see on a given run?

| Option | Description | Selected |
|--------|-------------|----------|
| Only what connected devices advertise (Recommended) | Toolset from registry caps at request time plus local tools; compositions only when their primitives are present | ✓ |
| Full tool list every run | Always offer everything; missing-device calls return today's error | |
| You decide | Planner picks after researcher confirms pydantic-ai filtering | |

**User's choice:** Only what connected devices advertise
**Notes:** User first asked what "connected devices" meant; Claude explained it is the bridge's registry of devices that completed hello with an open socket, each carrying a `caps` list, and re-presented the options.

---

## Drop and reconnect rules

### When a device drops while one of its commands is in flight, what happens to that command?

| Option | Description | Selected |
|--------|-------------|----------|
| Fail it the moment the socket closes (Recommended) | Handler cleanup resolves that device's pending futures with a disconnected error; needs per-device cid tracking | ✓ |
| Let it ride out the timeout | Only catch send-side `ConnectionClosed`; in-flight waits the full `CMD_TIMEOUT` | |
| You decide | Planner picks after researcher checks websockets 17 close behaviour | |

**User's choice:** Fail it the moment the socket closes

### A device reconnects with the same id while its old socket is still in the registry. What wins?

| Option | Description | Selected |
|--------|-------------|----------|
| New connection replaces the old (Recommended) | New hello overwrites, bridge closes stale socket, old cleanup checks identity (fixes WR-01) | ✓ |
| Reject the new hello until the old socket dies | Close second connection with 4003; ping timeout clears stale entry | |
| You decide | Planner picks | |

**User's choice:** New connection replaces the old

### A connected device sends something the handler cannot use. What does the bridge do?

| Option | Description | Selected |
|--------|-------------|----------|
| Log and ignore, keep the connection (Recommended) | One warning with device id and truncated payload; fixes WR-02 | ✓ |
| Close the connection with a code | Close with 4002 and let the Lua reconnect | |
| You decide | Planner picks; handler must not raise out of the loop | |

**User's choice:** Log and ignore, keep the connection

### Which open findings from the Phase 1 code review get closed in this phase?

| Option | Description | Selected |
|--------|-------------|----------|
| The protocol-facing ones: CR-01, WR-01, WR-02 (Recommended) | CR-01 one line plus an empty-token scenario case; WR-01 and WR-02 are the decisions above; WR-03 disappears with the swap | ✓ |
| Everything in the review | Also WR-04 and IN-01 through IN-04 | |
| CR-01 only | Close the token hole, leave WR-01 and WR-02 as follow-ups | |

**User's choice:** The protocol-facing ones: CR-01, WR-01, WR-02

---

## Proof format and spend guard

### How does a scenario report that it passed?

| Option | Description | Selected |
|--------|-------------|----------|
| Expectation steps and an exit code (Recommended) | `expect` steps with receive timeouts; exit 0 or 1 with a one-line verdict; wire log still prints | ✓ |
| Wire log only, verified by eye | Print traffic and stop | |
| Exit code, plus a run-all command | Same plus a `--all` runner | |

**User's choice:** Expectation steps and an exit code

### How does the harness make sure only the intended scenario spends an API call?

| Option | Description | Selected |
|--------|-------------|----------|
| Named paid scenario plus a --spend flag (Recommended) | Only the devices-question scenario emits an allowed-player `$robot` event, and the harness refuses to send one without `--spend` | ✓ |
| Named scenario only | Running the scenario is the consent | |
| Flag only | Any scenario may include `$robot` events, all gated by `--spend` | |

**User's choice:** Named paid scenario plus a --spend flag
**Notes:** The first presentation of this question was interrupted by the user; re-asked once on "continue" and answered.

### Is the current generic rejected-connection log line enough for the wrong-token proof?

| Option | Description | Selected |
|--------|-------------|----------|
| Distinguish the reasons and name the device (Recommended) | Separate lines for bad token (with claimed id), no hello within 10 s, stale socket replaced; token never logged | ✓ |
| Keep the current line | Close code alone distinguishes on the harness side | |
| You decide | Planner picks wording; no secret in logs | |

**User's choice:** Distinguish the reasons and name the device

### How much of the harness gets documented in this phase?

| Option | Description | Selected |
|--------|-------------|----------|
| Short README section plus CLAUDE.md dev-loop line (Recommended) | README "Harness" section; CLAUDE.md dev-loop line and thin-Lua architecture note; Phase 5 extends | ✓ |
| Module docstring only, README waits | `--help` and docstring only until Phase 5 | |
| Full README rewrite now | Pull DOC-01 and DOC-02 forward | |

**User's choice:** Short README section plus CLAUDE.md dev-loop line

---

## Claude's Discretion

- Harness location and packaging, `[project.scripts]` entry, scenario definition format (no YAML dependency)
- Exact Lua primitive names and signatures after the rewrite, and canned result shapes
- Pending-future bookkeeping structure for the fail-fast disconnect
- How a typed tool targets a device when several are connected
- Per-player history mechanism under Pydantic AI
- Startup model check once `anthropic` is transitive
- Log wording, exit codes beyond 0 and 1, `sort_chest` push batching

## Deferred Ideas

- Over-the-wire Lua updates from the bridge (only the bridge is version controlled)
- Agent-generated Lua routines so a turtle grows its own skills (`run_lua` / `ALLOW_EVAL`, off in v1.0)
- Multi-role harness process and REPL mode (possible Phase 4 debugging aid)
- Run-all-scenarios command (v1.1 TEST-02 territory)
- Per-device rule sets
- Review items WR-04, IN-01 through IN-04
- CHORE-01 first chore, where thin-Lua is applied to something proven in game
