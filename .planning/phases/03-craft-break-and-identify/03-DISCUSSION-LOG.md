# Phase 3: Craft, Break, and Identify - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-08
**Phase:** 3-Craft, Break, and Identify
**Areas discussed:** Tooltip wording & tone

---

## Gray Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Tooltip wording & tone | Exact wording open for BLOCK-06's refresh-hint line; plain/functional vs. Human Design-flavored | ✓ |
| Placeholder-recipe acknowledgment | Should the tooltip/name hint the single-dirt recipe is a dev placeholder, or read as a normal finished recipe? | |
| Loot table edge cases | Confirm default (any tool, drops itself, no Silk Touch distinction), or anything else (explosion/fire behavior)? | |

**User's choice:** Tooltip wording & tone only.

---

## Tooltip Wording & Tone

**Q1 — Overall tone**

| Option | Description | Selected |
|--------|-------------|----------|
| Plain & functional | States only what right-click does, no flavor | |
| Light Human Design flavor | One functional line + a short italic flavor line drawing on the recipe rationale | ✓ |
| You decide | Claude picks based on the block's presentation | |

**User's choice:** Light Human Design flavor.

**Q2 — Flavor direction**

| Option | Description | Selected |
|--------|-------------|----------|
| Time/transit themed | Leans on the "Clock at center" recipe rationale | ✓ |
| Distance/echo themed | Leans on the Echo Shard rationale (something distant arriving) | |
| Divination/bodygraph themed | Leans on the nine-centers framing | |
| Other | Freeform | |

**User's choice:** Time/transit themed.

**Q3 — Exact flavor line**

| Option | Description | Selected |
|--------|-------------|----------|
| "A window into the moment." | Short, evocative, ties to Clock-at-center without being literal | |
| "What the sky is doing, right now." | More concrete imagery, still time-themed | ✓ |
| "Time is the only ingredient that matters." | Directly echoes the recipe rationale text | |
| Other | Freeform | |

**User's choice:** "What the sky is doing, right now."

**Q4 — Functional line wording and line order**

| Option | Description | Selected |
|--------|-------------|----------|
| "Right-click to refresh." — functional first, flavor below | Matches vanilla's info-first, flavor-second convention (compass, clock) | ✓ |
| "Right-click to refresh." — flavor first, functional below | Description-then-mechanic layout | |
| Other | Different wording or order | |

**User's choice:** "Right-click to refresh." — functional line first, flavor line below.

**Notes:** Final tooltip: line 1 (plain) "Right-click to refresh.", line 2 (italic) "What the sky is doing, right now." Recorded as D-01/D-02 in CONTEXT.md.

---

## Claude's Discretion

- Recipe/loot table datagen provider placement (both go into the single existing `fabric-datagen` entrypoint class alongside the model/language providers — no separate common entrypoint exists).
- Recipe unlock criterion (`has(Items.DIRT)` or equivalent — trivial, not user-facing).
- Loot table shape (standard self-drop, matching Phase 2's D-10 "no special tool required" — not revisited since the "Loot table edge cases" area was not selected).
- Whether the single-dirt recipe should read as a placeholder to the player — not selected for discussion; defaults to reading as a normal, finished recipe with no in-game meta commentary.

## Deferred Ideas

None — discussion stayed within phase scope. "Placeholder-recipe acknowledgment" and "Loot table edge cases" were offered as gray areas but not selected; they are not deferred to a future phase, just not discussed (see Claude's Discretion above for the defaults in force).
