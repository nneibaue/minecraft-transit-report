---
phase: 03-local-server-setup
verified: 2026-09-25T11:36:12Z
status: passed
score: 5/5 must-haves verified
covered_files:
  - ".planning/workstreams/turtle-helper/REQUIREMENTS.md"
  - ".planning/workstreams/turtle-helper/phases/03-local-server-setup/03-01-PLAN.md"
  - ".planning/workstreams/turtle-helper/phases/03-local-server-setup/03-01-SUMMARY.md"
  - ".planning/workstreams/turtle-helper/phases/03-local-server-setup/03-02-PLAN.md"
  - ".planning/workstreams/turtle-helper/phases/03-local-server-setup/03-02-SUMMARY.md"
  - ".planning/workstreams/turtle-helper/phases/03-local-server-setup/03-03-PLAN.md"
  - ".planning/workstreams/turtle-helper/phases/03-local-server-setup/03-03-SUMMARY.md"
  - ".planning/workstreams/turtle-helper/phases/03-local-server-setup/03-04-PLAN.md"
  - ".planning/workstreams/turtle-helper/phases/03-local-server-setup/03-04-SUMMARY.md"
  - ".planning/workstreams/turtle-helper/phases/03-local-server-setup/03-05-PLAN.md"
  - ".planning/workstreams/turtle-helper/phases/03-local-server-setup/03-05-SUMMARY.md"
  - ".planning/workstreams/turtle-helper/phases/03-local-server-setup/03-06-PLAN.md"
  - ".planning/workstreams/turtle-helper/phases/03-local-server-setup/03-06-SUMMARY.md"
  - "turtle/turtle-helper/.env.example"
  - "turtle/turtle-helper/CLAUDE.md"
  - "turtle/turtle-helper/README.md"
  - "turtle/turtle-helper/base/chat.lua"
  - "turtle/turtle-helper/bridge/settings.py"
  - "turtle/turtle-helper/deploy/__init__.py"
  - "turtle/turtle-helper/deploy/launcher.py"
  - "turtle/turtle-helper/deploy/rules.py"
  - "turtle/turtle-helper/deploy/server_state.py"
  - "turtle/turtle-helper/install.lua"
  - "turtle/turtle-helper/pyproject.toml"
  - "turtle/turtle-helper/startup.lua"
  - "turtle/turtle-helper/tests/test_deploy_rules.py"
  - "turtle/turtle-helper/tests/test_device_lua.py"
  - "turtle/turtle-helper/turtle/client.lua"
covered_digest: "v1:sha256:2fefa7998645ae7175113ca6f6205d2d6182234441b350442aac7843061c3547"
behavior_unverified: 0
overrides_applied: 0
---

# Phase 3: Local Server Setup Verification Report

**Phase Goal:** The dedicated ATM9 server accepts local websocket connections from the bridge and hosts each device's Lua, token, and startup script directly on disk, so real devices have somewhere to run in the next phase.
**Verified:** 2026-09-25T11:36:12Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Phase 3 success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `computercraft-server.toml` carries a `127.0.0.1` allow rule before the `$private` deny; survives a restart; in-game smoke check succeeds | ✓ VERIFIED | Live file: allow rule at line 114 (`host = "127.0.0.1"` / `action = "allow"`), `$private` at line 118 — confirmed by direct read of the real `<SERVER_DIR>/world/serverconfig/computercraft-server.toml`. 03-03-SUMMARY.md records the restart proof (byte-identical toml before/after a real `run.bat` restart, md5 unchanged). 03-05-SUMMARY.md records the real in-game smoke check text (`table: 3c9a6ef1 nil` / `false Domain not permitted` / `false Could not connect`), reproduced verbatim in README.md's "#### Smoke check" section (confirmed by grep). |
| 2 | Devices get their Lua, token and startup script on disk via one placement path, confirmed against the running server | ✓ VERIFIED | Live folder `<SERVER_DIR>/world/computercraft/computer/0/` holds `chat.lua`, `client.lua`, `startup.lua`, `secret.txt`, `bridge.txt` — confirmed by direct `ls`. `chat.lua`/`client.lua` on disk are byte-identical to `origin/main` (diff run, no output). The developer `uv run deploy` path was deliberately removed (D-19, author-authorized 2026-09-25, recorded in 03-CONTEXT.md and reflected in REQUIREMENTS.md's reworded SRV-02): the sole remaining path is the in-game `install.lua` (`wget run`) plus `startup.lua`'s boot-time update. `git grep` for `uv run deploy` / `_marker` / `developer shortcut` across `turtle/turtle-helper` (excluding the one test that asserts their absence) returns no matches. Note: ROADMAP's original criterion-2 wording ("no GitHub push or pastebin step") describes the pre-amendment design; D-14..D-19 (author-authorized, documented in 03-CONTEXT.md, and reflected in REQUIREMENTS.md's SRV-02 reword) superseded it with the GitHub-`main` + `wget run` install path captured in criterion 5. This is a recorded, intentional pivot, not a gap. |
| 3 | Each device's folder holds its own `secret.txt` with only the token; token appears nowhere else | ✓ VERIFIED | Live `computer/0/secret.txt` compared in-process against `Settings().bridge_token` — equal. Token-isolation scans (re-run by this verifier): zero hits in tracked/untracked-unignored repo files, zero hits in full `git log --all -p` history. 03-05-SUMMARY.md's live-server scan (335 world files, 21 server logs incl. UTF-16LE and `.gz`) found the token in exactly one place: `computercraft/computer/0/secret.txt`. |
| 4 | Each device's `startup.lua` launches `chat` or `client`; a reboot brings it back on its own | ✓ VERIFIED | Live `startup.lua` on device A begins `-- startup.lua : turtle-helper boot...` and ends with the `peripheral.find("chatBox")` role check. `tests/test_device_lua.py#test_startup_updates_then_detects_role` (10/10 passing) pins this. 03-05-SUMMARY.md records the real reboot: boot lines `chat.lua up to date` / `client.lua up to date` / `connected to bridge`, and the bridge log `device connected: device-0 (chat) caps=['say']`. |
| 5 | A fresh computer installed with only the `wget run` line and the typed token connects after `reboot`; a later push to `main` plus `reboot` updates its Lua with no PC-side step | ✓ VERIFIED | `install.lua` (live-reviewed, 124 lines) implements the masked one-time token prompt, Enter-keeps-default URL prompt, and all-or-nothing validated downloads exactly as D-14/D-15/D-17 specify; `tests/test_device_lua.py` pins the no-print-token and pinned-URL invariants (10/10 passing). 03-05-SUMMARY.md records device A's real install (`wget run` line, masked token, Enter, `reboot`) and connection. 03-06-SUMMARY.md records the push-and-reboot update proof: device A's on-disk `chat.lua`/`client.lua` became byte-identical to the new `origin/main` and differ from the pre-payload blob, with mtimes advancing only for those two files at the reboot — reproduced independently by this verifier's live read (`diff` against `origin/main` → identical). |

**Score:** 5/5 truths verified (0 present-but-behavior-unverified)

### Requirements Coverage

| Requirement | Source Plan(s) | Description | Status | Evidence |
|---|---|---|---|---|
| SRV-01 | 03-01, 03-02, 03-03, 03-05, 03-06 | Allow rule, ordering, restart survival, in-game smoke check | ✓ SATISFIED | Live toml read; 03-03/03-05 SUMMARYs; README "#### Smoke check" |
| SRV-02 | 03-01, 03-02, 03-04, 03-05, 03-06 | On-disk placement via the single in-game install path, folder path confirmed, no second path | ✓ SATISFIED | Live `computer/0/` folder; D-19 removal confirmed by `git grep`; `git ls-files`/`deploy/` package inspection |
| SRV-03 | 03-01, 03-04, 03-05, 03-06 | Token lives only in per-device `secret.txt` | ✓ SATISFIED | In-process token comparison; repo/history scan (this verifier + 03-05/03-06 SUMMARYs) |
| SRV-04 | 03-01, 03-04, 03-05, 03-06 | `startup.lua` relaunches role program on reboot | ✓ SATISFIED | Live `startup.lua` content; `test_device_lua.py`; 03-05 boot evidence |
| SRV-05 | 03-04, 03-05, 03-06 | Non-technical admin installs with one `wget run` line + token; push+reboot is the whole update path | ✓ SATISFIED | `install.lua`/`startup.lua` review; 03-05 install proof; 03-06 update-path proof (independently re-checked) |

No orphaned requirements: REQUIREMENTS.md's Phase 3 row (SRV-01..05) matches exactly what the six plans' frontmatter declare. LOOP-01..05 and RESIL-01/02/DOC-01/02 belong to later phases (4/5) and are out of this phase's scope.

### Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `turtle/turtle-helper/startup.lua` | boot-time update + role launch, no marker branch (D-19) | ✓ VERIFIED | Present, git-tracked, 47 lines, no `_marker` reference, parses under Lua 5.2, matches live device copy's header |
| `turtle/turtle-helper/install.lua` | one-line in-game installer | ✓ VERIFIED | Present, git-tracked, implements banner/foreign-startup guard/download/token/URL/write flow exactly as specified |
| `turtle/turtle-helper/base/chat.lua`, `turtle/turtle-helper/turtle/client.lua` | IPv4 fallback, `bridge.txt` override, no `localhost`, install.lua-referencing Setup comments | ✓ VERIFIED | Both git-tracked, byte-identical to the live device's copies, parse under Lua 5.2 |
| `turtle/turtle-helper/deploy/rules.py`, `server_state.py`, `launcher.py`, `__init__.py` | kept host-side helpers (Phase 6) | ✓ VERIFIED | Present; `deploy.py` correctly absent (D-19); `launcher.py` defines its own `REPO_ROOT` |
| `turtle/turtle-helper/tests/test_deploy_rules.py`, `tests/test_device_lua.py` | TAP tests covering rules/probe/launcher and device-Lua invariants | ✓ VERIFIED | 10/10 and 10/10 passing (re-run by this verifier) |
| `turtle/turtle-helper/README.md`, `CLAUDE.md`, `.env.example` | single-path admin recipe, D-19-consistent docs | ✓ VERIFIED | All required strings present (`README_RECIPE_OK`/`DOCS_D19_OK` checks re-run and passing); no stale developer-path references |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `install.lua` / `startup.lua` | `raw.githubusercontent.com/.../main/turtle/turtle-helper/` | pinned `BASE` constant, identical in both files | ✓ WIRED | `test_startup_and_install_pin_the_same_raw_base` passes; live device's fetched files match `origin/main` blob hashes |
| `README.md` "Setup > 2. In game" | `install.lua`'s actual prompts/output | text taken from 03-05-SUMMARY.md's observed strings | ✓ WIRED | `Domain not permitted` / `Could not connect` / wget line / `#### Updating` / `#### Smoke check` all present verbatim in README.md |
| `startup.lua` update loop | device's local `chat.lua`/`client.lua` | validated `fetch()` → `fs.open(name, "wb")` only after status/header/compile checks | ✓ WIRED | Live device A's files changed exactly at the push-triggered reboot and match `origin/main`; unchanged files (`secret.txt`, `bridge.txt`) kept their pre-reboot mtimes |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| All six dependency-free test suites pass | `uv run python tests/test_*.py` (each) | 79/79 tests, `# fail 0` across all 6 files | ✓ PASS |
| Lint/type cleanliness | `uv run ruff check bridge/ harness/ deploy/ tests/` / `uv run mypy bridge/ harness/ deploy/` | "All checks passed!" / "Success: no issues found in 12 source files" | ✓ PASS |
| All four device Lua files are syntactically valid | `luaparse` (Lua 5.2) over `base/chat.lua`, `turtle/client.lua`, `startup.lua`, `install.lua` | `LUA_PARSE_OK` | ✓ PASS |
| No debt markers left in phase-touched files | `grep -nE "TBD|FIXME|XXX|TODO|HACK|PLACEHOLDER"` over Lua/deploy/docs files | no matches | ✓ PASS |
| Live server allow rule / folder layout / token isolation | direct read of `<SERVER_DIR>/world/...` (read-only) | rule present and ordered correctly; `computer/0/` matches expected file set; token isolated to `secret.txt` | ✓ PASS |

### Anti-Patterns Found

None. No debt-marker comments, no stub returns, no hardcoded-empty data paths in any phase-touched file.

### Human Verification Required

None. The two items in 03-05/03-06 that were originally operator-reported without a verbatim paste (device A's post-push boot lines / bridge "device connected" line, and the skipped optional offline-fallback reboot) are, per this verification run's scope instructions, treated as already human-verified through the SUMMARY's recorded operator confirmation plus the independently-reproducible on-disk evidence (byte/mtime comparison against `origin/main`), which this verifier re-ran and confirmed directly against the live server.

### Gaps Summary

No gaps. All five ROADMAP success criteria and all five SRV requirements (SRV-01..05) are independently confirmed against the live dedicated server, the repository, and the full automated test/lint/type suite — not merely against SUMMARY.md's narrative. The one wording mismatch (ROADMAP criterion 2's "no GitHub push" language vs. the actual, author-authorized D-14..D-19 pivot to a GitHub-`main` + `wget run` install path) is a stale-roadmap-text issue, explicitly recorded and reworded in REQUIREMENTS.md's SRV-02, and does not reflect any missing functionality.

---

_Verified: 2026-09-25T11:36:12Z_
_Verifier: Claude (gsd-verifier)_
