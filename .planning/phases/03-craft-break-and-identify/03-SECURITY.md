---
phase: "03"
slug: "craft-break-and-identify"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-09-08"
---

# Phase 03 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Local player crafting/breaking → world state | The only runtime inputs on this phase's path are a local player's own crafting-grid contents and block-break action, both constructed in-process by vanilla | Player-local game state only |
| `src/main/generated/data` / `assets` → shipped mod jar | Data-generation output (recipe, loot table, advancement, translations) is packaged as data-pack/resource-pack content and loaded by the game at world/resource load | Build-time-generated JSON, no runtime input |
| Mod data pack → Minecraft recipe/loot/translation registries | Generated JSON is parsed by vanilla's own data-pack loader into the recipe manager, loot table registry, and translation table | Build-time-generated JSON, no untrusted runtime parsing |
| Generated translation data → rendered tooltip text | Strings authored at build time cross into text the game draws on screen for the local player | Author-authored constant strings, no interpolation |
| Local player hover → block hover-text method | The only runtime input is the local player's own mouse position over their own inventory slot | Player-local input only |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-03-01 | Tampering | `src/main/generated/data/**` — datagen output committed and shipped in the jar | low | mitigate | 03-01 Task 2 proves reproducibility (delete `src/main/generated`, regenerate, diff byte-for-byte) and asserts no hand-authored data-pack JSON is tracked under `src/main/resources/data`. Verified directly: `git ls-files src/main/resources/data` returns empty. | closed |
| T-03-02 | Spoofing | Recipe id and loot table id under `jollyalchemy-transit-report:` | low | accept | Namespaced by the mod id, unique per Fabric Loader; same-namespace collision fails loudly at datagen via the duplicate-recipe check. Private single-developer server with a controlled mod set. | closed (accepted) |
| T-03-03 | Elevation of privilege | The crafting recipe as an item-acquisition path | low | accept | A crafting recipe is game balance, not authorization — any player who can open a crafting grid can already obtain any craftable item. The deliberate one-dirt cost is a recorded testing convenience (REQUIREMENTS.md). | closed (accepted) |
| T-03-04 | Denial of service | Recipe matching and loot resolution on the crafting/breaking path | low | accept | One-ingredient shapeless recipe and one-entry loot pool are the cheapest shapes either subsystem supports; no per-tick allocation, no loop, no I/O. | closed (accepted) |
| T-03-05 | Information disclosure | — (03-01 scope) | low | accept | No attack surface introduced: no socket, no runtime file read beyond vanilla's own data-pack load, no untrusted text parsing, no world-save persistence. | closed (accepted) |
| T-03-06 | Repudiation | — (03-01 scope) | low | accept | No attack surface introduced: crafting/breaking have no actor, transaction, or audit requirement this mod adds. | closed (accepted) |
| T-03-07 | Tampering | `src/main/generated/assets/.../lang/en_us.json` — generated content committed and shipped | low | mitigate | 03-02 Task 1 asserts the regenerated file's exact key set and byte-exact tooltip values, and asserts no hand-authored language file is tracked under `src/main/resources/assets`. Verified directly: `git ls-files src/main/resources/assets/jollyalchemy-transit-report/lang` returns empty. | closed |
| T-03-08 | Spoofing | Tooltip text as a channel that appears to speak for the game | low | accept | Both strings are build-time constants with no runtime interpolation and no player-supplied input path. The right-click-refresh promise is a sequencing note (Phase 10), not a security property. | closed (accepted) |
| T-03-09 | Information disclosure | `docs/DEV.md` — tracked content pushed to a public remote | low | mitigate | 03-02 Task 2 asserts the file carries no absolute filesystem path and no local username. Verified directly: `grep -Eq "C:\\\\Users\|/c/Users\|nneib" docs/DEV.md` exits 1 (not found). | closed |
| T-03-10 | Denial of service | The hover-text override on the tooltip-build path | low | accept | Allocates two text components per hover-frame, no I/O, no loop, no lookup beyond translation-key resolution the game already performs for the item name. | closed (accepted) |
| T-03-11 | Elevation of privilege | — (03-02 scope) | low | accept | No attack surface introduced: a tooltip grants no capability and is rendered client-side for the player already holding the item. | closed (accepted) |
| T-03-12 | Repudiation | — (03-02 scope) | low | accept | No attack surface introduced: displaying text has no actor, transaction, or audit requirement this mod adds. | closed (accepted) |
| T-03-SC | Tampering | Package-manager installs (supply chain) | low | accept | Neither plan ran npm/pip/cargo install or added a new Gradle coordinate; `gradle.properties` pins untouched. 03-RESEARCH.md §Package Legitimacy Audit records the gate as not applicable. | closed (accepted) |

*Status: open · closed · open — below {block_on} threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on (`high`) count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

No `high` or `critical` threat exists in this register. `threats_open: 0` under `security_block_on: high`.

ASVS L1 categories V2 (authentication), V3 (session management), V4 (access control), V5 (input validation), and V6 (cryptography) have no applicable control in this phase: the entire surface is build-time-generated data-pack/resource-pack JSON, two datagen provider classes, one hover-text override reading two constant keys, and a Markdown developer guide. Nothing opens a socket, parses untrusted runtime data, or crosses a trust boundary the local player is not already on both sides of. The project's real threat surface (HTTP fetch, PNG decode, config-file parsing) begins at Phase 5 (API-05, CFG-03) and Phase 6.

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-03-01 | T-03-02, T-03-03, T-03-04, T-03-05, T-03-06, T-03-08, T-03-10, T-03-11, T-03-12, T-03-SC | All `low` severity, private single-developer server with a controlled mod set and no network/untrusted-input surface in this phase. See per-threat mitigation column above for individual rationale. | Phase author (plan-time threat model) | 2026-09-08 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-09-08 | 13 | 13 | 0 | gsd-execute-phase orchestrator (short-circuit path: threats_open=0, register authored at plan time, ASVS L1 — verified mitigation evidence directly rather than spawning gsd-security-auditor, per secure-phase.md §3) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-09-08
