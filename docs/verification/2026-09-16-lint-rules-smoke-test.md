# Lint rules smoke test — 2026-09-16

Verified against `docs/architecture.md` §3.3 and the unverified findings in
`docs/research/layer-import-lint.md`.

- `import_lint` 2.0.0 loads under Dart 3.12, but two real issues surfaced during verification,
  both now resolved:
  1. Each rule in `analysis_options.yaml` requires an `except: []` key (a `List<String>`,
     even if empty) — `import_lint`'s `Rule.fromMap` throws `ArgumentException` without it.
     This was missing from Task 1's original config. The crash was silently swallowed by
     `flutter analyze`'s LSP-based analysis path, so `flutter analyze` reported "No issues
     found!" throughout Tasks 1–9 even though the plugin had never run a single check.
     Fixed by adding `except: []` to all three rules.
  2. Even after that fix, `flutter analyze` **still never surfaces `import_lint` diagnostics**.
     `flutter analyze` launches `dart language-server` (Dart's LSP-mode server), and
     `import_lint`'s analyzer-plugin protocol only works under the classic `analysis_server`
     that plain `dart analyze` uses. `dart analyze` correctly reports plugin diagnostics;
     `flutter analyze` does not, regardless of the `except` fix.
  - **Resolution:** `dart analyze` (not `flutter analyze`) is the verified command for
    `import_lint` enforcement in this project. This should be reflected in any future
    documentation or CI wiring for the module-wall/layer lint rules (`docs/architecture.md`
    §3.3 currently doesn't call this out — worth a follow-up doc update).
- `core_is_flutter_free`: confirmed firing under `dart analyze` — a `package:flutter/material.dart`
  import in `lib/core/money.dart` was reported as an `import_lint` error, then reverted.
- `core_depends_on_nothing`: confirmed firing under `dart analyze` — a
  `package:payment_module/brand_engine/...` import in `lib/core/money.dart` was reported as an
  `import_lint` error, then reverted.
- `engine_knows_no_features` and the feature-to-feature rules (§3.3) are **not yet verifiable**
  — `lib/features/` does not exist. Verify these in the next implementation plan
  (security_guard + payment), immediately after the first feature module is created — using
  `dart analyze`, per the finding above.
- Full suite: `flutter test` — 21 tests passing across `core` and `brand_engine`.
