# API Coverage — Anthropic Python SDK (`anthropic` 1.7.0)

> Full coverage by default. Opt-outs are explicit, reasoned decisions.

Phase 1 touches the Anthropic API in two ways: it moves the existing `messages.create` tool-use
loop from the single-file starter into `bridge/agent.py` unchanged (no new capability), and it
adds a new, token-free `models.retrieve` startup check in `bridge/bridge.py` (D-08). Neither adds
a new Anthropic capability beyond those two; every other surface of the SDK is out of scope for
this small, single-key, single-user mod.

| capability | decision | reason |
|---|---|---|
| messages.create (single-turn / multi-turn with tool_use) | INTEGRATE | Existing starter behavior (D-14 keeps the hand-rolled loop this phase; Pydantic AI rewrite is Phase 2), moved unchanged into `bridge/agent.py` |
| messages.create (streaming) | OPT-OUT | not needed — chat replies are one short `say()` per task; no incremental UI to stream into |
| messages.create (prompt caching / `cache_control`) | OPT-OUT | not needed yet — per-player histories are short-lived and already bounded by `MAX_TURNS`; no repeated large system-prompt cost to amortize |
| messages.create (extended thinking / reasoning mode) | OPT-OUT | not needed — deterministic tool dispatch for a small, fixed tool set doesn't benefit from extended reasoning |
| messages.create (vision / image content blocks) | OPT-OUT | not applicable — the only input is Minecraft chat text |
| models.retrieve | INTEGRATE | new this phase (D-08): token-free startup check that the configured `MODEL` and `ANTHROPIC_API_KEY` are valid before the bridge starts serving |
| models.list | OPT-OUT | not needed — `MODEL` is a fixed Settings value (D-18 default `claude-sonnet-5`, override via env), never chosen at runtime from a list |
| messages.count_tokens | OPT-OUT | not needed — history trimming is already bounded by `MAX_TURNS`, not exact token counts |
| message batches (`messages.batches.*`) | OPT-OUT | not needed — every request is a single synchronous chat-triggered call, never bulk/offline processing |
| files (`files.*`) | OPT-OUT | not needed — no file uploads or document/vision inputs in this mod |
| completions (legacy Text Completions API) | OPT-OUT | deprecated legacy API; the tool-use loop uses the Messages API exclusively, per the existing starter and D-14 |
| admin / organization / usage APIs | OPT-OUT | not needed — this is a single personal API key with no org-level management surface |
