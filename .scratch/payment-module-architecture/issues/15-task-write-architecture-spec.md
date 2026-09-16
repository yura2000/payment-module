# 15. Write docs/architecture.md + ADRs

Type: task
Status: resolved
Blocked by: 01, 02, 03, 04, 05, 06, 07, 08, 09, 10, 11, 12, 13, 14
Part of: ../map.md

## Question

Produce the destination: `docs/architecture.md` (package map + dependency graph; per-package interfaces from 13; layer rules + enforcement from 05; repo layout from 06; flavor recipe from 14; native channel contract from 10; lifecycles from 11 and 12; state machine from 07; performance design + proof from 09 and 04; test strategy), ADRs in `docs/adr/` (candidates: Pub-workspace modularisation; dart-define + registry flavor selection with drift assertion; hand-written channels over Pigeon; Android-only with no fallback adapters), and a final pass over `CONTEXT.md`.

**Deliverable**: the committed documents. Then the map is complete and implementation planning (`/writing-plans`) can start.

**Inputs from resolved research** (each ticket's `## Answer` holds the detail; the findings live on `research/<slug>` branches — decide in this ticket whether to merge `docs/research/` into `main` or link the branches)
- 01 root detection · 02 screen-recorder detection · 04 120 Hz · 05 `import_lint` (+ architecture-test fallback) · 06 Pub workspace (+ `.gitignore` `pubspec.lock` fix, per-member test loop, scaffold smoke tests).
- 07 state machine (verbatim tables) · 10 channel contract (verbatim; manifest entries; Kotlin layout; `contract/fixtures/`; evidence for the "hand-written channels over Pigeon" ADR).
- 12 transport + lifecycle (sequence, class table, 13-scenario table verbatim; process-death limitation stated; Intent-extras test hooks).
- 11 Secure Window (invariants + scenario table verbatim; launch-gap reasoning; "one lifetime, two owners").
- 08 brand slots (engine + section shapes verbatim; A/S/B as considered alternatives; prototype pointer `prototype/brand-slots`).
- 13 package seams (listing verbatim; the use-case rule; `testing.dart` convention; ADR candidate "use cases only where logic lives").
- 14 add-a-brand recipe + guard (verbatim as the spec's "Adding a brand" section; AI Insight Report pointers listed on the ticket).
- 09 scan visual (SecurityScanView / RadarPainter shapes; canary isolation test as the Optimization proof; motion rule; reduced motion; runner-up).

## Answer

**Resolved 2026-09-16 (task; documents written, awaiting the user's review).** The destination is reached.

### Produced
- `docs/architecture.md` — 17 sections, ~630 lines: purpose/scope · principles · repository layout & workspace mechanics · layer rules (`import_lint` config) · per-package interfaces (verbatim from ticket 13) · domain model + ports (corrected for ADR-0005) · white-label engine (shapes from ticket 08, brand values) · state machine (verbatim table from ticket 07, addenda folded in) · security posture assessment · channel contract (verbatim from ticket 10) · Payment Job service (sequence, classes, 13 scenarios from ticket 12) · Secure Window (invariants + scenarios from ticket 11) · scan visual & performance (ticket 09 shapes, ticket 04 recipe, canary proof numbers) · adding a brand (ticket 14 recipe + guard) · testing strategy · build/run/demo · decision index with rejected alternatives · known limitations.
- `docs/adr/0001` Pub workspace, one package per module · `0002` brand selection by `--dart-define` + registry, 1:1 with flavors · `0003` hand-written channels over Pigeon · `0004` Android only, no fallback adapters · `0005` use cases only where logic lives.
- `docs/research/*.md` — the six research findings copied from their throwaway `research/*` branches onto `main` (the spec cites them; branches are not a durable home).
- `CONTEXT.md` — final pass: consistent with the spec; no changes needed (21 terms).

### Decisions made while writing
- Research findings live in `docs/research/` on `main`; prototypes stay on their branches (`prototype/brand-slots`, `prototype/security-scan`) and are referenced by name — throwaway code does not enter `main`.
- The spec is the *final* text: ticket-level addenda (terminal `inFlight` → `Completed`; collaborators after the use-case collapse) are folded in, not appended.

### Not done here (deliberately)
- No commit: nothing in this effort has been committed to `main` on the user's instruction so far. Recommended first commit: `CONTEXT.md`, `docs/`, `.scratch/` (paper trail for the AI Insight Report), optionally `.claude/launch.json`.
- `.gitignore` still ignores `pubspec.lock` — the scaffold step removes that line (spec §3.1).
- The AI Insight Report and prompt log are out of the map (Notes); ticket 14 lists the material.

### Next
Implementation planning from `docs/architecture.md` (`/writing-plans`), beginning with the scaffold and its smoke tests (§3.2, §3.3, §17).
