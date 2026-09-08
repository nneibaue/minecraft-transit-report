# API Coverage — Phase 01 Toolchain Verification

No external API integration: this phase only proves the local build/run loop (Gradle, Loom, the Fabric
dev client, and data generation) and integrates no external service — "Fabric API" is a compile-time
modding framework already on the classpath, not a network service, and the Human Design HTTP API is
first touched in Phase 5.

## Detector note

The deterministic detector was run at plan time over the Phase 1 scope (the ROADMAP section, with no
PLAN.md yet on disk) and returned `detected: false` with zero signals. It is recorded here anyway
because the finished plans necessarily discuss "Fabric API", "the datagen entrypoint", and "wiring the
provider", which is enough surface vocabulary to trip the same detector when it re-runs over the plan
bodies at seal time. This declaration is the reasoned answer to that re-run, not a matrix for an
integration that does not exist.

## What this phase actually touches

| Surface | Kind | Note |
|---|---|---|
| Gradle / Fabric Loom | local build tooling | Resolves already-pinned Maven coordinates; no runtime service call |
| Fabric API `0.92.12+1.20.1` | compile-time modding framework | `FabricLanguageProvider` is read from a jar in the local Gradle cache |
| Fabric dev client | local process | Launched by `./gradlew runClient`; no outbound application traffic from this mod |
| Fabric data generation | local build-time step | Writes static JSON into `src/main/generated` |

## Where the real API coverage decision belongs

The external Human Design transit API enters the project in **Phase 5** (CFG-01..05, API-01..05) and is
joined to the display in **Phase 7** (API-06, API-07). The capability matrix for that surface —
including whether a second chart endpoint is integrated or explicitly opted out (API-04 exists precisely
to keep that a one-method decision) — is that phase's to produce, against the endpoint contract, which
does not exist yet.
