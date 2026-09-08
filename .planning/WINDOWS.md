---
schema_version: 1
open_count: 1
waived_count: 0
fixed_count: 0
total_count: 1
last_updated: 2026-09-08T07:23:13.285Z
---

# Broken Windows Ledger

> Cross-phase defect register. With `workflow.windows_enforce` enabled, `/gsd-ship` blocks while `open_count > 0`.
> Waive with `gsd-tools windows waive <id> "<reason>"` (reason required).
> Mark fixed with `gsd-tools windows fixed <id>`.

| id | phase | kind | file | line | description | status | reason | recorded_at | resolved_at |
|----|-------|------|------|------|-------------|--------|--------|-------------|-------------|
| 1 | 01 | deviation | 01-01-PLAN.md |  | Task 2 step 1 (confirm mod name on Mods screen) was unsatisfiable as written: Fabric ships no in-game mod list. User approved adding Mod Menu as a dev-only (modLocalRuntime) dependency to satisfy D-04's Mods-screen verification. | open |  | 2026-09-08T07:23:13.285Z |  |

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
  }
]
````
