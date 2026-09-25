---
schema_version: 1
open_count: 3
waived_count: 0
fixed_count: 0
total_count: 3
last_updated: 2026-09-25T04:15:47.938Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 01 | deviation | 01-01-PLAN.md |  | Task 2 step 1 (confirm mod name on Mods screen) was unsatisfiable as written: Fabric ships no in-game mod list. User approved adding Mod Menu as a dev-only (modLocalRuntime) dependency to satisfy D-04's Mods-screen verification. | open |  | 2026-09-08T07:23:13.285Z |  |
| 2 | 02 | deviation | turtle/turtle-helper/harness/scenarios.py |  | 02-03: devices-question gained a worker-role 60s hold branch (Rule 2) so the D-02 two-terminal recipe has a registered worker during the paid run | open |  | 2026-09-23T20:30:03.375Z |  |
| 3 | 02 | deviation | turtle/turtle-helper/harness/scenarios.py | 260 | devices-question passes on any say cmd, including the bridge's 'something went wrong' error fallback (false positive seen 2026-09-24 21:02); tighten in 02-07 | open |  | 2026-09-25T04:15:47.938Z |  |

````json
[
  {
    "id": 1,
    "kind": "deviation",
    "phase": "01",
    "file": "01-01-PLAN.md",
    "line": null,
    "description": "Task 2 step 1 (confirm mod name on Mods screen) was unsatisfiable as written: Fabric ships no in-game mod list. User approved adding Mod Menu as a dev-only (modLocalRuntime) dependency to satisfy D-04's Mods-screen verification.",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-08T07:23:13.285Z",
    "resolved_at": null
  },
  {
    "id": 2,
    "kind": "deviation",
    "phase": "02",
    "file": "turtle/turtle-helper/harness/scenarios.py",
    "line": null,
    "description": "02-03: devices-question gained a worker-role 60s hold branch (Rule 2) so the D-02 two-terminal recipe has a registered worker during the paid run",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-23T20:30:03.375Z",
    "resolved_at": null
  },
  {
    "id": 3,
    "kind": "deviation",
    "phase": "02",
    "file": "turtle/turtle-helper/harness/scenarios.py",
    "line": 260,
    "description": "devices-question passes on any say cmd, including the bridge's 'something went wrong' error fallback (false positive seen 2026-09-24 21:02); tighten in 02-07",
    "status": "open",
    "reason": "",
    "recorded_at": "2026-09-25T04:15:47.938Z",
    "resolved_at": null
  }
]
````
