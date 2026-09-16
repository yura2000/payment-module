# 14. "Add a 3rd brand" recipe + guard test

Type: grilling
Status: resolved
Blocked by: 08, 13
Part of: ../map.md

## Question

Write the exact recipe (files touched, in order) to add a hypothetical third brand, and the guard that keeps it honest: a test iterating `BrandRegistry` (goldens per brand; config completeness — every feature config present, every section renderable) and a check that every registry brand has a Gradle flavor and vice versa. Decide whether the recipe is a doc section, a `tool/new_brand.dart` generator, or both.

**Deliverable**: the recipe + guard design; this becomes the AI Insight Report's "how you structured the multi-tenant config" section.

**Inputs from resolved tickets**
- Ticket 08 (prototype): measured recipe = one `app/lib/brands/<brand>.dart` (a `const BrandConfig`) + one registry line + one Gradle flavor; a brand-unique section is a `CustomSection(builder)` in that same file, zero edits to `payment`. Guard = registry-driven completeness test (every brand has every required `BrandFeatureConfig`; every `CustomSection` has a `debugLabel`) + per-brand goldens from the registry + flavor↔registry drift check (ticket 10's `buildInfo`). Decide here whether the dev-only brand picker (fog) ships in debug builds for the demo video — the prototype's switcher shows it is one widget.
- Ticket 13: `BrandId` is `extension type BrandId(String value)` — a brand file declares `BrandConfig(id: BrandId('acme'), …)`; the completeness test additionally asserts unique ids and id == Gradle flavor name (via ticket 10's `buildInfo` in a debug assertion, and statically by parsing `app/android/app/build.gradle.kts` in a test or script — decide which).

## Answer

**Resolved 2026-09-16 (grilling, 1 round; all recommendations accepted).** Becomes the AI Insight Report's "how you structured the multi-tenant config" section and the spec's "Adding a brand" section.

### The recipe (for a hypothetical `acme`)
| # | File | Change |
|---|---|---|
| 1 | `app/lib/brands/acme.dart` *(new)* | `const acmeBrand = BrandConfig(id: BrandId('acme'), displayName: …, tokens: BrandTokens(…), features: [PaymentBrandConfig(ctaLabel, sections), SecurityBrandConfig(policy)])`; brand-unique sections via `CustomSection(builder)` in this file |
| 2 | `app/lib/brands/registry.dart` | one element added to `BrandRegistry([...])` |
| 3 | `app/android/app/build.gradle.kts` | one `create("acme") { dimension = "brand"; applicationIdSuffix = ".acme"; resValue("string", "app_name", "Acme Energy") }` block |
| 4 | `app/android/app/src/acme/res/mipmap-*/` *(optional)* | launcher icon; default icon otherwise |
| 5 | *(generated)* `app/test/golden/goldens/acme/*.png` | `flutter test --update-goldens --tags golden` in `app/`; the registry-driven golden test fails until the new brand's goldens exist and are reviewed |

Three mandatory edits, one optional, one generated. No script edits: the Makefile target is parametrised — `make apk BRAND=acme` → `flutter build apk --flavor $(BRAND) --dart-define=BRAND=$(BRAND)`.

### The guard
1. **`app/test/brands/brand_registry_test.dart`** iterating `brandRegistry.all`: `feature<PaymentBrandConfig>()` and `feature<SecurityBrandConfig>()` resolve; ids unique, non-empty, `[a-z][a-z0-9]*`; `displayName` non-empty; `sections` has exactly one `SummarySection` and one `PayButtonSection` (the single layout invariant `payment` imposes); every `CustomSection` has a non-empty `debugLabel`; `PosturePolicy` covers every `ThreatKind` (the constructor also asserts this in debug); `buildBrandTheme(brand)` succeeds with the `BrandTokens` extension present.
2. **Flavor ↔ registry**: a test regex-parses `productFlavors { create("…") }` from `app/android/app/build.gradle.kts` and asserts set-equality with registry ids; the runtime debug assertion `buildInfo().flavor == BRAND` (ticket 10) catches a mismatched build command. Scaling path, named in the spec: generate `brands.gradle.kts` from the registry once brands number in the dozens.
3. **Per-brand goldens** — `app/test/golden/payment_page_golden_test.dart`: each brand × six BLoC-driven states (Scanning · AwaitingConfirmation/Secure · AwaitingConfirmation/Unverified · Processing 40 % · Completed/Succeeded · Completed/Failed), pumping the real `PaymentConfirmationPage` with scripted fakes from `testing.dart`; `goldens/<brandId>/<state>.png`, phone viewport; tagged `golden`, executed in CI on Linux (platform-sensitive rendering).

### Decisions
- **Form**: a doc section whose every step is enforced by a failing test if skipped; **no `tool/new_brand.dart` generator** (a checklist the tests enforce cannot drift; a generator tracking the `BrandConfig` shape can).
- **Dev-only brand picker: out of scope.** Two flavor APKs are the deliverable; the invariant "Brand = Flavor" stays clean; the composition root never grows a debug-only `getIt.reset() + setupLocator(newBrand)` path.

### Pointers for the AI Insight Report (ticket 15)
- "How you structured the multi-tenant config": this ticket + ticket 08's engine shapes.
- "One instance where AI was sub-optimal and corrected": candidates — five pass-through use cases removed by the deletion test (ticket 13); the research agent's `flutter_displaymode` plugin replaced by ten lines of in-app Kotlin (ticket 04); the agent's "bump Dart to 3.13" suggestion, moot because Dart ships with Flutter (ticket 06).

## Addendum (2026-09-16, after map completion)
Paths after the single-package revision (ADR-0001): `lib/brands/acme.dart`, `lib/brands/registry.dart`, `android/app/build.gradle.kts`, `android/app/src/acme/res/…`, `test/golden/goldens/acme/`, `test/brands/brand_registry_test.dart`; commands run from the repo root. The recipe's step count and the guard are unchanged.
