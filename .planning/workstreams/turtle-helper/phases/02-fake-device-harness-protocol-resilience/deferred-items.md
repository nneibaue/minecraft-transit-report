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
