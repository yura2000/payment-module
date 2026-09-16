---
status: accepted
date: 2026-09-16
---
# Hand-written MethodChannels and EventChannels instead of Pigeon

The Android bridge (`dev.test.payment/*`: four `MethodChannel`s and two replay-1 `EventChannel`s) is hand-written, with one Kotlin handler class per concern and every `Result`/`EventSink` call forced onto the main thread by a single pair of wrappers (`MainThreadResult`, `MainThreadSink`). Pigeon would give type-safe generated code, but it hides exactly the mechanism this task evaluates — channel threading and payload discipline — and its contract could not be shown as a table in a spec. In a production codebase with many messages we would adopt Pigeon; here the contract is small, fixed in `docs/architecture.md` §9, and pinned by shared JSON fixtures consumed by both the Dart and Kotlin tests.

## Considered options

- Pigeon: rejected for this deliverable only, named as the scaling path.
- A single "kitchen-sink" channel: rejected; per-concern channels give each event stream a natural lifetime owner.
