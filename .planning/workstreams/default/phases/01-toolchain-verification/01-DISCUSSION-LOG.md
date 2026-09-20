# Phase 1: Toolchain Verification - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-07
**Phase:** 1-Toolchain Verification
**Areas discussed:** How runClient gets verified, Template leftovers
**Areas offered but not selected:** Datagen with nothing to generate, Settling the client=true question

---

## Area Selection (first pass)

Four gray areas were offered. The user answered with free text instead of selecting:

> "hmm. I have minecraft installed on my computer. are there any verifications we can skip to just me testing it in game? You'll have to walk me through how to install the mod into the game"

**Resolution:** A misconception was cleared up rather than a decision made — `./gradlew runClient` *is* testing it in game; it launches a real, playable Minecraft 1.20.1 window. There was no separate automated harness to skip. The genuine choice was reframed as dev client (Path A) vs. installing a built jar into the real launcher (Path B).

| Option | Description | Selected |
|--------|-------------|----------|
| Path A — dev client | One Gradle command opens a real Minecraft window; code changes picked up on next launch, no install step | ✓ |
| Path B — installed Minecraft | Build jar, install Fabric Loader, download Fabric API, copy jars to `.minecraft/mods/`, launch profile — repeated on every code change | |
| Both | A as the working loop, plus a one-time B walkthrough | |

**User's choice:** Path A.
**Notes:** Path B was not rejected on merit — it was recognised as a distribution concern for the private server rather than a verification concern. Captured as a deferred idea.

---

## Asset Reuse (user-initiated question)

> "but can it use the assets I already have? I have 1.20.1 installed in my computer"

Not a multiple-choice question — answered by checking disk.

**Finding:** Loom already holds its own complete copy. `~/.gradle/caches/fabric-loom/assets` is 629 MB with all 256 object subdirs and index `1.20.1-5.json`; `%APPDATA%/.minecraft/assets` is 629 MB with index `5.json`. The download had already happened during the earlier research session, so there was no cost left to avoid.

**Outcome:** Recommended against pointing Loom at `.minecraft/assets` — it would reclaim already-spent disk in exchange for a nonstandard config that fails confusingly (silent missing sounds/text). Accepted. Recorded as D-02, and the disk-reclaim idea kept as a deferred item.

**Side effects of the check:** three further findings surfaced that reshaped the phase — `runClient` had never completed a launch, `runDatagen` had run but written nothing, and JDK 26 is the only JDK on the machine.

---

## How runClient Gets Verified

### Question 1 — How should the launch actually happen?

| Option | Description | Selected |
|--------|-------------|----------|
| I launch, you watch | Claude starts runClient in the background and tails the log; user watches the window and confirms what's on screen | ✓ |
| You run it yourself | User runs it in their own terminal and reports back; Claude blind to the log unless pasted | |
| I launch, log is the proof | Claude greps the log for mod-loaded and exceptions; user doesn't have to watch | |

**User's choice:** I launch, you watch.
**Notes:** Chosen over the log-only option because nothing in the log confirms the window actually rendered a playable game.

### Question 2 — How far into the game should verification go?

| Option | Description | Selected |
|--------|-------------|----------|
| Main menu + creative world | Confirm mod on Mods screen, then create a creative superflat world and stand in it | ✓ |
| Main menu only | Mod appears on the Mods screen at the title screen; satisfies TOOL-01 as literally written | |
| World plus a full look around | Fly around, open creative inventory and search tabs | |

**User's choice:** Main menu + creative world.
**Notes:** Main-menu-only would let a client that crashes on world load pass the phase. The full look-around was rejected as having no target — no block exists until Phase 2. The created world is kept as the reusable dev test world.

### Question 3 — How should we handle the JDK 26 risk?

Context given before the question: JDK 26 is the only JDK on the machine, and `./gradlew build` succeeding proves nothing about it, since `options.release = 17` means the daemon emits Java 17 bytecode without ever running Minecraft.

| Option | Description | Selected |
|--------|-------------|----------|
| Try 26, hard stop on JDK smell | Launch on 26 first; if it fails on module access / LWJGL natives / Mixin reflection, install JDK 21 immediately rather than debugging | ✓ |
| Install JDK 21 first, pin it | Remove the unknown up front, at the cost of a download before seeing the game | |
| Stay on 26, debug whatever comes | Keeps one JDK on the machine; risks an open-ended debugging session | |

**User's choice:** Try 26, hard stop on JDK smell.
**Notes:** The stop condition was agreed in advance deliberately, so it isn't a judgement call made mid-failure.

### Question 4 — Should the dev-loop commands be written down, and where?

| Option | Description | Selected |
|--------|-------------|----------|
| `docs/DEV.md` in the repo | Dev client, datagen, JDK requirement, and later the real-install walkthrough; lives with the code | ✓ |
| Add to CLAUDE.md | Always loaded for Claude, less useful as a human reference, and the file is already long | |
| Just the phase SUMMARY | Nothing new in the repo; commands buried in planning artifacts | |
| Don't write it down yet | Defer docs until there's an actual install story | |

**User's choice:** `docs/DEV.md`.
**Notes:** Directly responsive to the user's opening request to be walked through running the mod — this is where that walkthrough persists.

---

## Template Leftovers

A correction was issued before this area: the earlier framing claimed the example mixins "still run and log on startup". They do not — both have empty method bodies and log nothing. This changed the area from "remove noise" to "remove inert code".

### Question 1 — What happens to the example mixins?

| Option | Description | Selected |
|--------|-------------|----------|
| Delete them now | Remove both classes and empty the mixins.json arrays; a future startup mixin error is then unambiguously ours | ✓ |
| Leave them entirely | Strict "no source change in a sanity-check phase"; clean in Phase 2 | |
| Delete after the launch passes | Verify on the untouched template first for a known-good baseline, then delete and relaunch | |

**User's choice:** Delete them now.

### Question 2 — What should the mod's display name be?

Framing: the Mods screen is the artifact this phase uses as proof, and it currently shows the raw mod id.

| Option | Description | Selected |
|--------|-------------|----------|
| Human Design Transit Display | Matches PROJECT.md's project title; keeps planning docs and in-game name in sync | ✓ |
| Jolly Alchemy Transit Report | Readable expansion of the existing mod id | |
| Transit Report | Short and neutral; drops both the Human Design context and the Jolly Alchemy naming | |

**User's choice:** Human Design Transit Display.

### Question 3 — How far do we take the rest of the metadata?

Context given: the git remote is real (`github.com/nneibaue/minecraft-transit-report`), and the CC0 `LICENSE` file is actually present, so `"license": "CC0-1.0"` is currently consistent rather than a leftover lie.

| Option | Description | Selected |
|--------|-------------|----------|
| Real values, keep CC0 | Real description, authors, and GitHub sources URL; drop the fake fabricmc.net homepage; leave license and LICENSE alone | ✓ |
| Real values, switch to All Rights Reserved | Same, plus change license to ARR and replace the LICENSE file | |
| Description and author only | Smallest edit; leaves FabricMC example-mod URLs in the metadata | |

**User's choice:** Real values, keep CC0.
**Notes:** Licensing was recognised as a distribution question, not a verification one, and deferred.

---

## Claude's Discretion

The user declined to discuss two of the four offered areas, leaving them to Claude's judgement. Both were resolved in CONTEXT.md as D-12 and D-13:

- **Datagen with nothing to generate (TOOL-02).** Register a `FabricLanguageProvider` — the only provider needing no block, item, or model, so it pulls nothing forward from Phase 2, and not throwaway since GEN-05 needs it in Phase 3. Without some provider, `runDatagen` exits 0 while writing zero files, so TOOL-02 is unsatisfiable as written.
- **Settling `client = true` (TOOL-03).** Diff the task list with and without the flag, then diff generated output once a provider exists; drop to bare `configureDataGeneration()` only if there is no observable difference. Flagged explicitly: do not remove it blind, because `splitEnvironmentSourceSets()` is in use and the datagen entrypoint lives in the client source set — the flag may be what makes that source set visible to datagen.

Also noted in CONTEXT.md: `research/STACK.md` §1.4 and `research/PITFALLS.md` Pitfall 2 disagree about this flag. Both can be true — configuration-time acceptance is not runtime effect. To be resolved by observation, not by picking a document.

## Deferred Ideas

- **Path B — install the built mod into real Minecraft** (build jar → Fabric Loader installer → Fabric API `0.92.12+1.20.1` → `%APPDATA%\.minecraft\mods\` → `fabric-loader-1.20.1` profile). Explicitly requested by the user; belongs to the private-server distribution milestone. Lands in `docs/DEV.md` when that arrives.
- **Licensing decision (CC0 vs. All Rights Reserved).** Surfaced during metadata cleanup, deferred by D-10.
- **Reclaiming the duplicated 629 MB of Minecraft assets** by pointing Loom at `.minecraft/assets`. Rejected by D-02 as poor risk-for-reward; revisit only under real disk pressure.
