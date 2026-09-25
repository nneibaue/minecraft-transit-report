# Phase 02 — Deferred Items

Out-of-scope discoveries logged during execution. Not fixed here (scope boundary); pick up in a
later plan or milestone.

## From plan 02-02 (bridge resilience)

- **`bridge.py` `handler()` fires `asyncio.create_task(on_event(dev_id, msg))` without keeping a
  reference.** Pre-existing (Phase 1 starter). asyncio only holds weak references to tasks, so a
  long-running `on_event` (it awaits the model call) can in principle be garbage-collected
  mid-flight and log "Task was destroyed but it is pending". Fix is a module-level
  `background_tasks: set[asyncio.Task[None]]` with `task.add_done_callback(background_tasks.discard)`.
  Natural home: plan 02-05/02-06 when `agent.handle_request` is rewritten, since that is the
  awaited call inside the task.
  status: resolved
  **02-06 fix:** `bridge.py` now has a module-level `background_tasks: set[asyncio.Task[None]]`;
  `handler()` adds each event task and discards it on completion. Covered by
  `tests/test_bridge_resilience.py::test_event_task_is_held_until_it_finishes`.

## From plan 02-04 (paid devices-question run, pre-swap)

- **`harness/scenarios.py` `devices_question` passes on any `say` cmd, including the bridge's error
  fallback.** Observed 2026-09-24 21:02: the API returned 400 (account out of credit), `bridge.py`
  line ~220 sent `say("Sorry <user>, something went wrong: BadRequestError")`, and the harness still
  printed `PASS: devices-question` because lines 260-264 only check that a `say` frame arrived and
  print its text. Fix: fail the scenario when the say text starts with `Sorry` / contains
  `something went wrong` (or better, when it does not name a connected device id). Natural home:
  plan 02-07 (the post-swap re-run touches this scenario) or the phase code-review pass. Not fixed
  here: 02-04's `files_modified` is empty by design.
  status: resolved
  **02-07 fix (commit 0b9cbea):** `harness/scenarios.py` gained `is_error_fallback()` (matches
  `bridge.on_event`'s `Sorry <user>, something went wrong: <ErrorName>` shape, which is unchanged
  by the pydantic-ai swap because `agent.handle_request` lets exceptions propagate to that
  handler); the `devices-question` chat branch now fails (exit 1) on an empty say text or the
  fallback. Covered by `tests/test_harness_scenarios.py` (5 TAP checks, including the verbatim
  21:02 fallback text and the successful 21:09 answer). The "names a connected device id"
  variant was not adopted: the chat process cannot know a worker is connected, and the transcript
  prints the say text for the human read.
- **Model `say` call used `"to": null`** in the successful run, so the answer went to broadcast
  instead of the asking player. Carry into plan 02-05's typed Pydantic AI `say` tool: make `to`
  required, or default it to the requesting player.
  status: resolved
  **02-05 decision:** `SayArgs.to` stays `str | None = None` (null accepted, meaning broadcast) so the
  post-swap wire matches the 02-04 transcript for 02-07's like-for-like comparison; the prompt still
  opens with `[<player>]`, so the model can whisper by name when it chooses to. Revisit after 02-07.

## From plan 02-05 (agent core on pydantic-ai)

- Pre-existing mypy error in tests/test_bridge_resilience.py:112 (`handler.emit = records.append` needs `# type: ignore[method-assign, assignment]`; mypy 1.14 reports the assignment code, the ignore only covers method-assign)
  status: resolved
  **Found during:** 02-05 Task 1 (running `uv run mypy bridge/ tests/ harness/`); not caused by this plan, left for 02-06's cleanup pass alongside the bridge.py formatting debt.
  **02-06 fix:** ignore widened to `[method-assign, assignment]`; `uv run mypy bridge/ harness/ tests/` is clean. The bridge.py formatting debt (`ruff format --check`) was cleared in the same pass as a formatting-only `style(02-06)` commit.
- pydantic-ai prints a one-time observability banner to stderr on the first agent run when Logfire is not configured; set `PYDANTIC_AI_NO_BANNER=1` (e.g. in .env.example or bridge.py) before 02-07 reads the bridge log
  status: resolved
  **Found during:** 02-05 Task 2 prototype; cosmetic, bridge.py is out of this plan's scope.
  **02-06 fix:** `agent.configure()` sets `pydantic_ai.BANNER_ENABLED = False` (the switch the installed 2.46.0 documents in `pydantic_ai/__init__.py`; `PYDANTIC_AI_NO_BANNER` is its env-var twin) before the Agent is built, so no env var or `.env.example` entry is needed. Covered by `tests/test_agent_composition.py::test_configure_turns_off_the_pydantic_ai_first_run_banner`.

## From plan 02-07 (post-swap paid run)

- **`agent.handle_request` dropped the model's answer when it came back as plain text instead of a
  `say` call.** Observed 2026-09-24 22:17 (claude-haiku-4-5, HEAD 2fb724d): two model round trips
  (`list_devices`, then the answer as text), no `say` cmd to the chat device, no log line, and the
  chat harness timed out after 30 s (`FAIL: devices-question - harness-chat: no list_devices or say
  cmd within 30s`). The pre-swap loop (53d57eb) relied on the model always ending with `say()`; an
  `Agent[None, str]` invites a plain-text final answer, so the swap made this likely, not rare.
  status: resolved
  **02-07 fix (Rule 1 deviation, commits d107778 RED / bcff617 GREEN):** `handle_request` inspects
  `result.new_messages()` for a `say` `ToolReturnPart`; with none, and a non-blank `result.output`,
  it whispers the output to the requesting player through `say_in_chat` and never repeats an answer
  the model already spoke. The final output is logged either way (200 chars). The instructions now
  also say "Answer through say(), not as plain text: players only read game chat" beside the
  carried-over "exactly one say()" rule. Covered by `tests/test_agent.py` tests 24-26 (the 22:17
  shape whispered to the asker and logged; the 21:09 say shape not duplicated; a whitespace-only
  output speaks nothing). The paid `devices-question` scenario still needs a re-run to close 02-07.
