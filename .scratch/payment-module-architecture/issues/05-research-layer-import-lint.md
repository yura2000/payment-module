# 05. Cross-layer import enforcement inside a package

Type: research
Status: resolved
Blocked by: —
Part of: ../map.md

## Question

Package walls (Pub workspace) enforce feature boundaries. Inside `security_guard` and `payment`, the `domain/data/presentation` folders still need a mechanical rule: `domain` imports nothing from `data`, `presentation` or `package:flutter`; `presentation` never imports `data`.

On Dart 3.12 / Flutter 3.44, which tool does this with the least ceremony: `import_lint`, a small `custom_lint` rule, DCM/`dart_code_linter` banned imports, or simply `src/` privacy + barrel exports (`lib/payment.dart` exporting only domain + presentation + `registerPaymentModule`)? Check maintenance status and analyzer-plugin compatibility with Dart 3.12 (the new analyzer plugin system).

**Deliverable**: recommendation + config snippet.

**Decision waiting on this**: ticket 15 (spec layer-rules section).

## Answer

**Resolved 2026-09-16 by a research agent.** Findings: `docs/research/layer-import-lint.md` on branch `research/layer-import-lint`. Config shapes verified against vendor docs, **not executed** (no packages exist yet).

**Decision**: `import_lint` 2.0.0 per feature package.
- Built on Dart's first-party analyzer-plugin system (`analysis_server_plugin`, Dart ≥ 3.10; 3.12.2 satisfies it). Pure-YAML rules (`target` / `from` / `except` globs) in `analysis_options.yaml`, runs inside `dart analyze` / `flutter analyze` and the IDE. Rules per package: `domain` ↛ `data`, `domain` ↛ `presentation`, `domain` ↛ `package:flutter`, `presentation` ↛ `data`.
- Rejected: `custom_lint` (rides the *legacy* plugin system, deprecated at Dart 3.13.2 per dart-lang/sdk #64188 — a dead end); DCM `avoid-banned-imports` (most expressive, but a paid, closed, separate binary outside `dart analyze`); barrels/`src/` privacy alone (`implementation_imports` only fires *across* packages — confirmed on dart.dev).
- **Verify at scaffold time**: add one deliberately violating file per layer and confirm the plugin reports it; the glob dialect (`**.dart` vs `**/*.dart`) is UNVERIFIED. Watch `import_lint`'s `analyzer ^12.1.0` pin against build_runner/mocktail tooling (open issue #46).
- **Zero-dependency fallback** (my addition): if the plugin misbehaves on Dart 3.12, a package-local architecture test — a unit test that walks `lib/src/**` and regex-checks `import` lines against the same four rules — enforces the identical policy in `flutter test` with no analyzer coupling. Cheap enough that ticket 15 should include it regardless as belt-and-braces for CI.
- Bus-factor note for the spec: `import_lint` is a small two-maintainer package; acceptable for this repo, worth a line in the ADR/spec.

## Addendum (2026-09-16, after map completion)
With a single package (ADR-0001) `import_lint` now also carries the **module walls**: `core` Flutter-free and dependency-free, `brand_engine` blind to features, `features/payment` may use `features/security_guard` only through its barrel, no reverse dependency. Final rule set in spec §3.3; the architecture-test fallback covers the same rules.
