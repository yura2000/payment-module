# Composition root verification — 2026-09-17

Plan: `docs/superpowers/plans/2026-09-17-composition-root.md`. Verified against
`docs/architecture.md` §3.1, §3.3, §4, §6, §7, §11, §12.1, §12.2, §13, §14, §15.

## Commands

- `dart analyze --fatal-infos` — No issues found!
- `flutter test` — 238 tests passing
- `dart format --set-exit-if-changed lib test integration_test` — Formatted 111 files (0 changed)
- `flutter build apk --debug --flavor retail --dart-define=BRAND=retail` — yes
- `flutter build apk --debug --flavor utility --dart-define=BRAND=utility` — yes

## What the guards proved

- `test/architecture_test.dart` — the module-boundary rules are read from `analysis_options.yaml`
  and checked against every file under `lib/`. Confirmed non-vacuous: a temporary
  `no_reverse_dependency` violation was added, observed failing, and reverted.
- `test/brands/brand_registry_test.dart` — 21 assertions across both Brands: configs resolve,
  ids are slugs, one Summary and one Pay Button each, policies cover every `ThreatKind`, themes
  carry their tokens.

## Corrections folded back into docs/architecture.md

- §13 row 1: Brands are `final`, not `const` — `PosturePolicy` cannot be a constant.
- §6: the Brand table gained `headlineWeight` (Retail w700 / Utility w500) and `displayName`.

## Deliberately not built, at the user's explicit request (docs/superpowers/plans/2026-09-17-composition-root.md, Scope boundary)

- The canary isolation test — the deterministic, non-device proof that the Security Scan never
  repaints the page layer. `prototype/security-scan` measured it (60 frames → 0 page-layer
  repaints) but that proof was not carried forward as a shipped test.
- The on-device `integration_test/perf_test.dart` — the frame-budget measurement.
- The flavor↔registry guard — nothing mechanically catches a Gradle flavor renamed without
  updating `lib/brands/registry.dart`, or the reverse. The manual APK builds in this plan's Task
  14 are the only thing standing in for it today.
- Per-brand goldens — no reference images exist; `make goldens` runs and correctly finds nothing.

If any of these matter later, this plan's own task history has a fully designed version of each —
re-adding one does not require redesigning it.

## Still open

- Everything in §17 remains as the prior plan left it; this plan added no new limitation beyond
  the four deferrals just listed.
