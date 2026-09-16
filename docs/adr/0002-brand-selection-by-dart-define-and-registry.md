---
status: accepted
date: 2026-09-16
---
# Brand is selected by `--dart-define=BRAND` through a registry, paired 1:1 with an Android product flavor

Each Android product flavor ships exactly one Brand and is named after it (Brand = Flavor). The Dart side reads `const String.fromEnvironment('BRAND')` once at startup and resolves it through `BrandRegistry`; a debug-only assertion checks it against the native `BuildConfig.FLAVOR` so the two knobs cannot drift, and a parametrised `make apk BRAND=<id>` keeps them together. We chose this over per-brand entrypoints (`main_retail.dart` — type-safe, but still two knobs and no registry for tests to iterate) and over `flutter_flavorizr`.

## Consequences

- The registry is the single source of truth per-brand tests (goldens, completeness) iterate; adding a brand is one file, one registry line, one Gradle flavor block.
- There is no runtime brand switching, including in debug builds; the demo deliverable is two APKs.
