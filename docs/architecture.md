# Payment Confirmation Module — Architecture

**Status**: approved architecture; implementation not started. Produced by the wayfinder map at
`.scratch/payment-module-architecture/` (fourteen resolved decision tickets; the map is complete as of 2026-09-16).
**Companions**: [`CONTEXT.md`](../CONTEXT.md) (the glossary — every capitalised term below is defined there),
[`docs/adr/`](adr/) (five decision records), [`docs/research/`](research/) (six primary-source findings),
and two throwaway prototypes on branches `prototype/brand-slots` and `prototype/security-scan`.

## 1. Purpose, scope, constraints

The module is a white-label **Payment Confirmation** screen for a multi-brand Android app, built to the brief in
`Flutter_interview_task 1.pdf`: (A) a configuration-driven multi-tenant engine with two Brands, (B) Android-native
security — root and screen-recorder detection over a `MethodChannel`, `FLAG_SECURE` while the payment screen is
visible, a foreground service with a progress notification simulating payment processing — and (C) a 60/120 FPS
`CustomPainter` animation that never repaints the rest of the tree.

| | |
|---|---|
| Brands | **Retail** (warm orange/gold, rounded, fluid, Promo Banner) and **Utility** (navy/slate, dense, sharp, Bill Breakdown). Brand = Flavor, 1:1, no runtime switching. |
| Platform | Android only. No iOS, no fallback adapters (ADR-0004). |
| Backend | None. The foreground service *is* the simulated processor; no HTTP client anywhere. |
| Toolchain | Flutter 3.44.6 / Dart 3.12.2 via FVM (`.fvmrc`), `compileSdk`/`targetSdk` 36, `minSdk` 26, AGP 9.0.1 / Kotlin 2.3.20 as the template ships them, Java 17. Kotlin package root `dev.test.payment`. |
| Out of scope | iOS; real backend; Play Integrity; runtime brand switching (also in debug); cancelling a Payment Job; a dev-only brand picker. |

## 2. Principles

1. **Strict Clean Architecture, feature-first, one application package.** Each feature is `lib/features/<name>/` with a
   barrel, a private `src/{domain, data, presentation}` and its own `di.dart`; module walls and layer rules are both
   enforced by `import_lint` and a regex architecture test (§3.3). Domain code never imports Flutter. Packages are the
   named scaling path, not the starting point (ADR-0001).
2. **Ports and adapters, two adapters per seam.** Every native port has a Kotlin-backed channel adapter and a scripted
   fake under `test/support/fakes/`. The one seam with a single production adapter
   (`PaymentRepository`, in-memory demo data) exists for the backend that a real product would have, and says so.
3. **Exceptions for the unexpected, values for the expected.** `ServiceException` / `ClientException` /
   `TransportException` are thrown by adapters and caught in the BLoC; a Compromised posture or a failed Payment Job is a
   sealed *value*.
4. **Use cases only where a decision or orchestration lives** (ADR-0005). Delegation is not a reason to exist.
5. **Configuration-driven UI, zero conditionals on brand identity.** `if` on a *configuration value* (a policy verb, a
   token) is allowed; `if (brand == retail)` is not, anywhere. `BrandId` is an open string type precisely so nothing
   can `switch` over it.
6. **Every native reply lands on the main thread**, enforced by two wrappers, not by discipline.
7. **The scan never repaints the page** — `RepaintBoundary` plus a `repaint:` listenable — and a test proves it with
   a number (§12.3).
8. **Honest posture.** When a check cannot run, the Security Posture is *Unverified*, never silently Secure.

## 3. Repository layout

### 3.1 Layout — one Flutter application package, feature-first

Dart package name `payment_module`; Android `applicationId` `dev.test.payment` (+ `.retail` / `.utility` per flavor).

```
payment-module/
├── pubspec.yaml · pubspec.lock (committed — remove `pubspec.lock` from .gitignore) · .fvmrc (3.44.6)
├── analysis_options.yaml        # import_lint rules: layers + module boundaries (§3.3)
├── Makefile                     # run/apk BRAND=<id> · test · goldens · analyze · format
├── CONTEXT.md · docs/{architecture.md, adr/, research/, ai/prompt-log.md}
├── contract/fixtures/*.json     # channel payload fixtures shared by Dart and Kotlin tests
├── lib/
│   ├── main.dart                # bootstrap(): BRAND → registry → setupLocator → preferHighRefreshRate → drift assertion → runApp
│   ├── app/                     # payment_app.dart (MaterialApp + BrandScope + PaymentConfirmationPage) · locator.dart (setupLocator)
│   ├── brands/                  # retail.dart · utility.dart · registry.dart   (one const BrandConfig per brand)
│   ├── bootstrap/               # channel_display_mode.dart · channel_app_info.dart (composition-root adapters)
│   ├── core/                    # Flutter-free shared kernel: brand_id, money, threat_kind, posture_policy, exceptions
│   ├── brand_engine/            # brand_engine.dart (barrel) · src/{brand_config, brand_tokens, brand_scope, brand_theme}.dart
│   └── features/
│       ├── security_guard/      # security_guard.dart (barrel) · di.dart (registerSecurityModule) · src/{domain, data, presentation}/
│       └── payment/             # payment.dart (barrel)        · di.dart (registerPaymentModule)  · src/{domain, data, presentation}/
├── android/app/src/main/kotlin/dev/test/payment/
│   ├── MainActivity.kt          # delegates configureFlutterEngine / cleanUpFlutterEngine / onRequestPermissionsResult
│   ├── bridge/                  # ChannelRegistry · MainThreadResult · MainThreadSink
│   ├── security/                # SecurityEnvironmentHandler · RootChecks · ScreenRecordingMonitor
│   ├── window/                  # WindowHandler
│   ├── payment/                 # PaymentJobHandler · PaymentJobService · PaymentJobStateHolder · PaymentJobNotifications
│   └── app/                     # AppInfoHandler
├── test/
│   ├── support/fakes/           # fake_security_environment · fake_secure_window · fake_payment_processor · fake_payment_repository
│   ├── architecture_test.dart   # regex import rules — belt-and-braces for §3.3
│   ├── core/ · brand_engine/ · features/{security_guard, payment}/   # mirror lib/
│   ├── brands/                  # registry completeness · flavor↔registry
│   └── golden/                  # per-brand goldens (tag: golden)
└── integration_test/perf_test.dart
```

**Modules and their dependency DAG** (lint-enforced, §3.3): `app / brands / bootstrap → *` · `features/payment → core,
brand_engine, features/security_guard` · `features/security_guard → core, brand_engine` · `brand_engine → core` ·
`core → (nothing, not even Flutter)`. A module is used **only through its barrel** (`features/security_guard/security_guard.dart`);
its `src/` is private to it. Every feature already has the shape of a package — barrel, `src/`, `di.dart` — so promoting
one to `packages/` later is a move plus a `pubspec.yaml`, with no code changes (ADR-0001 names the trigger; the mechanics
are in `docs/research/pub-workspace-flutter.md`).

### 3.2 Mechanics

A standard Flutter application: `fvm flutter pub get` once; `flutter run / build apk / test` from the root; the IDE needs
nothing special. `pubspec.lock` is committed (application). The `Makefile` exists only for the flavor + dart-define pairing
(§15), not to work around tooling. **`flutter analyze` is not the lint command** — see §3.3.

### 3.3 Boundaries: layers inside a feature, walls between modules

Both are the same mechanism: **`import_lint` 2.0.0** (first-party analyzer-plugin system, Dart ≥ 3.10) with path globs;
plus `test/architecture_test.dart`, which walks `lib/**` and regex-checks `import` lines against the same rules so CI
enforces the policy even if the plugin misbehaves (`custom_lint` rides the deprecated legacy plugin system; DCM is a paid
separate binary).

**Verified at scaffold time** (docs/verification/2026-09-16-lint-rules-smoke-test.md), three findings not in the original
research:

1. **The lint command is `dart analyze`, never `flutter analyze`.** `flutter analyze` runs Dart's LSP-mode
   `dart language-server`, which does not implement the analyzer-plugin protocol `import_lint` needs; it reports
   `No issues found!` even when a rule is violated. Plain `dart analyze` uses the classic `analysis_server` and correctly
   surfaces `import_lint` diagnostics. Every command in this document that needs the lint to actually run — `make analyze`
   (§15), CI — means `dart analyze`, not `flutter analyze`.
2. **Every rule needs an explicit `except: []`.** Without it, `import_lint`'s `Rule.fromMap` throws while parsing
   `analysis_options.yaml`; under `flutter analyze`'s LSP path that failure is silently swallowed (reports clean), which
   is how (1) above was masked for several tasks before being caught. The config below includes it.
3. **A configured `severity: error` still prints as `info`, and plain `dart analyze` exits 0 on an info-only diagnostic.**
   CI must run **`dart analyze --fatal-infos`** to actually fail the build on a boundary violation — confirmed: exit 0
   without the flag, exit 1 with it, for the identical lone diagnostic.

The glob dialect (`*`, `{a,b}`) is confirmed working (verification doc).

```yaml
# analysis_options.yaml
plugins:
  import_lint: ^2.0.0
import_lint:
  severity: error
  rules:
    # layers — every feature at once (except: [] is required on every rule — see above)
    domain_no_data:            { target: "package:payment_module/features/*/src/domain/**.dart",       from: "package:payment_module/features/*/src/data/**.dart",       except: [] }
    domain_no_presentation:    { target: "package:payment_module/features/*/src/domain/**.dart",       from: "package:payment_module/features/*/src/presentation/**.dart", except: [] }
    domain_no_flutter:         { target: "package:payment_module/features/*/src/domain/**.dart",       from: "package:flutter/**.dart",                                    except: [] }
    presentation_no_data:      { target: "package:payment_module/features/*/src/presentation/**.dart", from: "package:payment_module/features/*/src/data/**.dart",       except: [] }
    # module walls
    core_is_flutter_free:      { target: "package:payment_module/core/**.dart",         from: "package:flutter/**.dart",                                             except: [] }
    core_depends_on_nothing:   { target: "package:payment_module/core/**.dart",         from: "package:payment_module/{brand_engine,features,app,brands,bootstrap}/**.dart", except: [] }
    engine_knows_no_features:  { target: "package:payment_module/brand_engine/**.dart", from: "package:payment_module/{features,app,brands,bootstrap}/**.dart",             except: [] }
    security_guard_via_barrel: { target: "package:payment_module/features/payment/**.dart",        from: "package:payment_module/features/security_guard/src/**.dart", except: [] }
    no_reverse_dependency:     { target: "package:payment_module/features/security_guard/**.dart", from: "package:payment_module/features/payment/**.dart",           except: [] }
```

## 4. Module interfaces

The seam of each module — what its barrel exports and therefore what its tests exercise. Everything else stays under `src/`.
(`codebase-design` vocabulary: module, interface, seam, adapter; the deletion test was applied to every candidate.)

```
lib/core  (Flutter-free by lint)
  exports   BrandId (extension type) · Money · ThreatKind · PosturePolicy (+ DetectedResponse, UnavailableResponse)
            sealed AppException → ServiceException | ClientException | TransportException
  adapters  none (in-process)                     tests  value semantics only

lib/brand_engine  (barrel brand_engine.dart; internals under src/)
  exports   BrandFeatureConfig · BrandTokens (ThemeExtension) · BrandConfig + feature<T>() · BrandRegistry (type: all, byId)
            BrandScope · buildBrandTheme · BuildContext.tokens
  src       colour-scheme / shape / density builders      adapters  none
  tests     feature<T>() failure modes · token→ThemeData mapping · registry lookup
  deletion  passes: theme building + scope + lookup would reappear in every feature

lib/features/security_guard  (barrel security_guard.dart; src/{domain,data,presentation}; di.dart)
  domain    ThreatAssessment · AssessmentResult · SecurityPosture · PolicyVerdict · PostureUpdate · SecurityBrandConfig
            ports  SecurityEnvironment { assess(); posture }   SecureWindow { setSecure(bool) }
            use case  WatchPostureVerdict(environment, policy) → Stream<PostureUpdate>   pure fn  evaluatePosturePolicy
  presentation  SecurityPostureCubit · SecureSessionScope · SecureWindowController · SecurityScanView · PostureBanner
  registration  registerSecurityModule(getIt, {environment, window})
  src (private) ChannelSecurityEnvironment · ChannelSecureWindow · PostureSnapshotCodec · painter internals
  fakes     test/support/fakes: FakeSecurityEnvironment (scripted postures) · FakeSecureWindow (records calls)
  seams     SecurityEnvironment: Channel + Fake ✓ real · SecureWindow: Channel + Fake ✓ real
  tests     use case via fake env · SecurityPostureCubit via fake env · controller scenarios (§11.2) · channel contract tests + fixtures · canary isolation test (§12.3)

lib/features/payment  (barrel payment.dart; src/{domain,data,presentation}; di.dart)
  domain    Payment · LineItem · PaymentJobProgress · PaymentFailure · PaymentReceipt
            ports  PaymentRepository { load() }   PaymentProcessor { start(Payment); inFlight() }
  presentation  PaymentConfirmationPage · sealed PaymentSection (Summary | PromoBanner | BillBreakdown | PayButton | Custom) · PaymentBrandConfig
  registration  registerPaymentModule(getIt, {repository, processor})
  src (private) PaymentConfirmationBloc + events/state · canPay() and the other derived display rules · InMemoryPaymentRepository (demo Payment) · ChannelPaymentProcessor · JobSnapshotCodec
            section widgets · money formatting (intl)
  fakes     test/support/fakes: FakePaymentProcessor (scripted progress, inFlight control) · FakePaymentRepository
  seams     PaymentProcessor: Channel + Fake ✓ real · PaymentRepository: InMemory + Fake — kept for the architecture's sake
            (a real backend is the second production adapter this seam exists for); stated as such
  tests     bloc_test through fakes (§7.1) · derived-rule unit tests · page widget tests · channel contract tests + fixtures

lib/app · lib/brands · lib/bootstrap  (the composition root; the only code allowed to import everything)
  code      main.dart → bootstrap(): BRAND dart-define → BrandRegistry → setupLocator(brand) → preferHighRefreshRate → debug drift assertion → runApp
            app/payment_app.dart (MaterialApp + BrandScope + PaymentConfirmationPage) · brands/{retail, utility, registry}.dart
            app/locator.dart (setupLocator → brand singletons, registerSecurityModule, registerPaymentModule) · bootstrap/{channel_display_mode, channel_app_info}.dart
  android   Kotlin per §9
  tests     test/brands (registry completeness, flavor↔registry) · test/golden (per-brand goldens from the registry, fakes)
            test/architecture_test.dart · integration_test/perf_test.dart · contract fixtures at contract/fixtures/
```

Registration is a plain function per feature (`di.dart`, re-exported by the barrel) with named overrides for tests:
`registerSecurityModule(GetIt getIt, {SecurityEnvironment? environment, SecureWindow? window})` and
`registerPaymentModule(GetIt getIt, {PaymentRepository? repository, PaymentProcessor? processor})`; `lib/app/locator.dart`
registers the `BrandConfig` singleton first and then calls both. BLoCs are factories, adapters lazy singletons.

## 5. Domain model

The glossary in [`CONTEXT.md`](../CONTEXT.md) is canonical; this section fixes the *shapes*.

```
core            ThreatKind = rooted | screenRecording
                PosturePolicy { onDetected: {ThreatKind → block | warn}, onUnavailable: {ThreatKind → allow | notice} }
security_guard  AssessmentResult = detected | clear | unavailable(reason: apiLevel | error)
                ThreatAssessment(kind, result)
                SecurityPosture { assessments } → Secure | Compromised | Unverified
                PolicyVerdict { blockers, warnings, notices : Set<ThreatKind>; isBlocked ⇔ blockers ≠ ∅ }
payment         Payment { amount: Money, payee, lineItems }
                PaymentJobProgress = Running(percent) | Succeeded(PaymentReceipt) | Failed(PaymentFailure)
                PaymentFailure = declined | timedOut | serviceUnavailable
                PaymentReceipt(reference, completedAt)
```

- **Security Posture is per-threat.** `Secure` = every assessment clear; `Compromised` = any detected; **`Unverified`** = none
  detected but at least one check `unavailable` (API level, or the check itself failed). Root detection can say "clear" on
  every API level; screen-recorder detection cannot below API 35 — only per-threat results keep that information.
- **Posture Policy** carries two verbs per `ThreatKind`: `onDetected: block | warn`, `onUnavailable: allow | notice`.
  Retail: rooted→block, screenRecording→warn, unavailable→**allow**. Utility: both→block, unavailable→**notice**.
  Nobody blocks on "cannot tell": the Secure Window already prevents recording; detection is defence in depth.
- **Payment Job**: `Running(percent) | Succeeded(PaymentReceipt) | Failed(declined | timedOut | serviceUnavailable)`; no
  `Queued`, no cancel. The simulation declines deterministically when `amountMinor % 100 == 99`.
- `BrandId` is `extension type BrandId(String value)` — open, zero-cost, un-switchable. `Money(amountMinor, currency)` is
  data only; formatting uses `intl` in `payment/presentation`.

### 5.1 Ports and the one use case

```
security_guard  port      SecurityEnvironment { Future<void> assess(); Stream<SecurityPosture> get posture }
                          — one source of truth: assess() re-runs the one-shot checks and pushes a snapshot;
                            the API 35+ recorder callback pushes on its own
                port      SecureWindow { Future<void> setSecure(bool secure) }
                use case  WatchPostureVerdict(environment, policy) → Stream<PostureUpdate(posture, verdict)>
                          — kicks off assess(), merges the stream, distinct, applies the policy
                pure fn   evaluatePosturePolicy(policy, posture) → PolicyVerdict   (internal seam, exported for tests)

payment         port      PaymentRepository { Future<Payment> load() }
                port      PaymentProcessor { Stream<PaymentJobProgress> start(Payment); Future<Stream<PaymentJobProgress>?> inFlight() }
```
`PaymentConfirmationBloc` depends on `PaymentRepository` and `PaymentProcessor`; `SecurityPostureCubit` depends on `WatchPostureVerdict` — see ADR-0005: the one-line
use cases of the first design (`LoadPayment`, `ConfirmPayment`, `FindInFlightJob`, `WatchSecurityPosture`) were removed by the
deletion test. Adapter rule: a `PlatformException` raised by a check becomes `unavailable(error)` for *that* threat, never an
exception into the BLoC.

## 6. White-label engine

**Selection** (ADR-0002): Android `productFlavors { retail; utility }` (`applicationIdSuffix`, `app_name`, icon) paired with
`--dart-define=BRAND=<id>`, read once as a `const` and resolved through `BrandRegistry`; a debug assertion compares it with the
native `BuildConfig.FLAVOR` (`app · buildInfo`, §9); `make apk BRAND=<id>` keeps the two knobs together. Single `main.dart`.

**Shape**: `BrandConfig` = `id` + `displayName` + `BrandTokens` (visual + motion) + `List<BrandFeatureConfig>` looked up by
type — the `ThemeExtension` pattern applied to configuration, so `brand_engine` knows nothing about features and each
feature contributes its own config type (`PaymentBrandConfig` in `payment/presentation`, `SecurityBrandConfig` in
`security_guard/domain`). **Delivery**: `buildBrandTheme` → `ThemeData` (`ColorScheme.fromSeed`, shapes from `radius`,
`VisualDensity`, `PageTransitionsTheme`) + `BrandTokens` as a `ThemeExtension` for what `ThemeData` cannot express +
`BrandScope` (`InheritedWidget`) for the non-visual config.

**Sections, not conditionals** (prototype `prototype/brand-slots`, verdict in ticket 08): `PaymentBrandConfig.sections` is an
ordered list of a **sealed** `PaymentSection` hierarchy — known sections switched exhaustively, plus `CustomSection(builder)`
as the escape hatch a brand uses for a section `payment` has never heard of, defined in the brand's own file. A closed enum
(cannot express brand-unique content) and fixed-skeleton slots (cannot reorder) were rejected. There are **no capability
flags** today; if one appears it is a field on the owning feature's config, read via `feature<T>()`.

```dart
// brand_engine (knows nothing about features)
abstract class BrandFeatureConfig { const BrandFeatureConfig(); }
class BrandTokens extends ThemeExtension<BrandTokens> {   // seed, accent, radius, density, spacing, scanMinDuration, headlineWeight
  ... copyWith / lerp
}
class BrandConfig {
  const BrandConfig({required this.id, required this.displayName, required this.tokens, required this.features});
  final BrandId id; final String displayName; final BrandTokens tokens; final List<BrandFeatureConfig> features;
  T feature<T extends BrandFeatureConfig>() => features.whereType<T>().single;
}
class BrandScope extends InheritedWidget { static BrandConfig of(BuildContext context); }
ThemeData buildBrandTheme(BrandConfig brand);   // ColorScheme.fromSeed(tokens.seed) + shapes(radius) + VisualDensity + extensions: [tokens]
extension on BuildContext { BrandTokens get tokens => Theme.of(this).extension<BrandTokens>()!; }

// payment/presentation
sealed class PaymentSection { const PaymentSection(); }
final class SummarySection extends PaymentSection { const SummarySection(); }
final class PromoBannerSection extends PaymentSection { const PromoBannerSection(); }
final class BillBreakdownSection extends PaymentSection { const BillBreakdownSection(); }
final class PayButtonSection extends PaymentSection { const PayButtonSection(); }
final class CustomSection extends PaymentSection {          // brand-supplied; `payment` renders it blind
  const CustomSection(this.builder, {required this.debugLabel});
  final Widget Function(BuildContext, Payment) builder; final String debugLabel;
}
class PaymentBrandConfig extends BrandFeatureConfig { const PaymentBrandConfig({required this.ctaLabel, required this.sections}); ... }
// page: for (final s in cfg.sections) switch (s) { SummarySection() => ..., ..., CustomSection(:final builder) => builder(context, payment) }

// security_guard/domain
class SecurityBrandConfig extends BrandFeatureConfig { const SecurityBrandConfig({required this.policy}); final PosturePolicy policy; }

// lib/brands/<brand>.dart — one const BrandConfig per brand; lib/brands/registry.dart — const brands = [...]
```

**Brand values** (tokens are the *whole* brand difference — the prototypes confirmed no per-brand widget or painter is needed):

| | Retail | Utility |
|---|---|---|
| `seed` / `accent` | `#E65100` / `#FFB300` | `#0D2B4E` / `#5C6B7A` |
| `radius` · `density` · `spacing` | 20 · comfortable · 16 | 4 · compact · 8 |
| `scanMinDuration` | 2000 ms | 1200 ms |
| copy | "Pay now" | "Confirm payment" |
| sections | Promo Banner · Summary · Pay | Summary · Bill Breakdown · Pay |
| Posture Policy | rooted→block, recorder→warn, unavailable→allow | both→block, unavailable→notice |

## 7. Payment confirmation flow — two blocs, split on the feature seam

Two units, neither aware of the other. (The first design was one composite bloc owning posture as well; it was split after
review so that each unit stays simple and posture handling lives with the feature that owns the concept — ticket 07's addenda
record the change.)

- **`SecurityPostureCubit`** (`security_guard/presentation`) — subscribes to `WatchPostureVerdict`; state
  `PostureState { SecurityPosture? posture; PolicyVerdict? verdict; bool get hasFirstAssessment }`; `onResumed()` →
  `environment.assess()`. Thin by design: its value is the seam and its reuse by any future secure screen, not logic.
- **`PaymentConfirmationBloc`** (`payment/presentation`, private to the feature) — the flow machine below: payment load, the
  scan timer, the job. It never subscribes to posture; the one posture fact it needs arrives *inside an event*
  (`PayPressed(verdict)`), so the machine still guards against a blocked posture without knowing where verdicts come from.
- **Derived display rules** — pure functions in `payment/presentation`, unit-tested on their own:
  `canPay(flow, posture) = flow.phase is AwaitingConfirmation ∧ flow.payment ≠ null ∧ posture.hasFirstAssessment ∧
  ¬posture.verdict.isBlocked`; the CTA shows "checking…" while `!hasFirstAssessment`; `PostureBanner(verdict)` and the Result
  View's caveat read the cubit directly. **No `BlocListener` relays events between the two blocs.**

Consequences of the split: "posture degrades during processing → the job continues" and "retry re-evaluates the verdict" are no
longer rules to code — they fall out, because the flow bloc never listens to posture and the verdict is live in the cubit. One
rule is simplified: **Scanning ends on the `scanMinDuration` timer alone**; the CTA separately waits for the first assessment.
Observably identical in the normal case (assessment ≈ 100 ms ≪ 1.2 s) and better behaved if a check is slow.

### 7.1 `PaymentConfirmationBloc`

State `{ payment?, phase }` with sealed `phase = Scanning | AwaitingConfirmation | Processing(progress) | Completed(outcome)`.
Events from the page: `Started`, `PayPressed(verdict)`, `RetryPressed`; internal: `PaymentLoaded`, `ScanTimerElapsed`,
`JobProgressed`.

| Phase | Event | Guard | → Phase | Effects |
|---|---|---|---|---|
| *(initial)* | `Started` | no in-flight job | `Scanning` | `repository.load()`; start the `scanMinDuration` timer |
| *(initial)* | `Started` | in-flight job `running` | `Processing(progress)` | subscribe to the job — no Scan phase |
| *(initial)* | `Started` | in-flight job terminal | `Completed(outcome)` | Result View directly |
| `Scanning` | `PaymentLoaded` | — | `Scanning` | payment set |
| `Scanning` | `ScanTimerElapsed` | — | `AwaitingConfirmation` | — |
| `AwaitingConfirmation` | `PaymentLoaded` | — | same | payment set (slow load) |
| `AwaitingConfirmation` | `PayPressed(verdict)` | `payment ≠ null ∧ ¬verdict.isBlocked` | `Processing(Running 0)` | `processor.start(payment)` |
| `AwaitingConfirmation` | `PayPressed(verdict)` | otherwise | same | ignored (double-tap, blocked, not yet loaded) |
| `Processing` | `JobProgressed(Running p)` | — | `Processing(p)` | — |
| `Processing` | `JobProgressed(Succeeded r \| Failed f)` | — | `Completed(outcome)` | — |
| `Processing` | `PayPressed` / back | — | same | ignored / `PopScope(canPop: false)` |
| `Processing` | `processor.start` throws | — | `Completed(Failed serviceUnavailable)` | exception → value at the BLoC boundary |
| `Completed(Failed)` | `RetryPressed` | — | `AwaitingConfirmation` | — (the verdict is live in the cubit) |
| `Completed(Succeeded)` | — | terminal until pop | — | Result View shows the cubit's caveat if any |

### 7.2 `SecurityPostureCubit`

| Trigger | Effect |
|---|---|
| created (page mounted) | subscribe `WatchPostureVerdict` — the use case triggers the first `assess()` |
| `PostureUpdate(posture, verdict)` from the stream | `emit(PostureState(posture, verdict))`; `hasFirstAssessment` becomes true on the first update |
| `onResumed()` (page's `AppLifecycleListener`) | `environment.assess()` — silent re-run of the one-shot checks |
| closed (page disposed) | cancel the subscription → adapter `onCancel` unregisters the recorder callback |

Scenarios covered across the two units: degrade while processing (automatic) · backgrounded mid-job (job survives; cubit
re-assesses on resume) · fails at 60 % → retry · scan finishes before the timer (the CTA waits on `hasFirstAssessment`, the
phase does not) · double-tap · back during processing · in-flight re-attach (running and terminal).

## 8. Security posture assessment

Findings: `docs/research/root-detection.md`, `docs/research/screen-recorder-detection.md`.

- **Rooted** — hand-rolled in `RootChecks` (no RootBeer dependency: Apache-2.0 but a native `.so`, an OR-of-everything result
  and a documented false-positive record). Six signals — su binary on known paths · `which su` · `Build.TAGS` test-keys ·
  `ro.debuggable=1` / `ro.secure=0` via `getprop` · known root-manager packages (Magisk, SuperSU, KernelSU, classic su
  managers) · writable `/system` or `/vendor` in `/proc/mounts` — and **`detected` only when ≥ 2 fire**, absorbing the
  single-signal false positives. Everything but `Build.TAGS` blocks → `Dispatchers.IO`; process execs time out at 1 s.
  **`targetSdk 36` gate**: every package name checked needs a `<queries>` entry or the check silently sees nothing. Accepted
  trade-off: a hidden Magisk (repackaged app + DenyList) can drop below the threshold. Best-effort signal, not a security
  boundary — Play Integrity is the real attestation and is out of scope. Google APIs / AOSP emulator images are pre-rooted and
  test-key-signed by design and legitimately report Compromised.
- **Screen recording** — API 35+: `WindowManager.addScreenRecordingCallback` (normal permission `DETECT_SCREEN_RECORDING`;
  fires for *any* MediaProjection session; keeps firing while our window has `FLAG_SECURE`; registration is a blocking
  Binder call → IO; callbacks delivered on `ContextCompat.getMainExecutor`). Below API 35 there is **no official signal** and
  every fallback is unreliable or blocked → `unavailable(apiLevel)` in every snapshot; no fallbacks are wired. The
  callback's lifetime is the posture subscription's (register on `onListen`, unregister on `onCancel`). `adb shell
  screenrecord` bypasses MediaProjection and is not detected (FLAG_SECURE blanks it anyway).
- **Assessment flow**: `assess()` runs the one-shot checks (on entry and silently on resume) and pushes a snapshot; the
  recorder callback pushes transitions; `WatchPostureVerdict` applies the brand's policy and `SecurityPostureCubit` emits; the
  page re-derives `canPay` and the banners on every update. Degrades before Pay → policy re-applies; degrades during the job → the job completes and the
  Result View shows the caveat.

## 9. Native bridge — channel contract (ADR-0003)

**Codec** `StandardMethodCodec`; payloads `Map<String, Object?>`; enums lowerCamelCase strings; timestamps epoch millis (int64); money = `amountMinor` (int) + `currency` (ISO 4217).

**Threading guarantee**: every `Result.*` and `EventSink.*` call happens on the Android main thread, enforced by `MainThreadResult` / `MainThreadSink` wrappers that post via `Handler(Looper.getMainLooper())` when not already there; blocking work runs in `withContext(Dispatchers.IO)` inside the `ChannelRegistry` scope, cancelled in `cleanUpFlutterEngine`.

| Channel · method | Args | Returns | Idempotent | Errors (`code`) |
|---|---|---|---|---|
| `security.environment` · `assess` | — | `null` | yes; concurrent calls coalesce | none |
| `window` · `setSecure` | `{secure: bool}` | `null` | yes | `noActivity` |
| `window` · `preferHighRefreshRate` | — | `{refreshRate: double, modeId: int}` or `null` | yes | `noActivity` |
| `payment.job` · `ensureNotificationPermission` | — | `"granted" \| "denied" \| "notRequired"` | yes (one prompt per process) | `noActivity` |
| `payment.job` · `start` | `{reference: String, amountMinor: int, currency: String, payee: String}` | `{jobId: String}` | **no** | `alreadyRunning`, `serviceStartFailed` |
| `payment.job` · `current` | — | `JobSnapshot` or `null` | yes | — |
| `app` · `buildInfo` | — | `{flavor, applicationId, versionName, versionCode: int, sdkInt: int}` | yes | — |

Any method may raise `badArguments`.

**`security.environment/events`** — `PostureSnapshot`, replay-1; emitted after every completed `assess()` and on every recorder transition; `sink.error` never used.
```json
{ "assessments": [ { "kind": "rooted", "result": "clear" },
                   { "kind": "screenRecording", "result": "unavailable", "reason": "apiLevel" } ],
  "assessedAt": 1758000000000 }
```
`kind ∈ {rooted, screenRecording}` · `result ∈ {detected, clear, unavailable}` · `reason ∈ {apiLevel, error}` only with `unavailable`. Below API 35 `screenRecording` is always `unavailable(apiLevel)`.

**`payment.job/events`** — `JobSnapshot`, replay-1 (in-flight or last terminal since process start); stream stays open after a terminal state.
```json
{ "jobId": "j-1", "state": "running",   "percent": 40 }
{ "jobId": "j-1", "state": "succeeded", "reference": "PAY-…", "completedAt": 1758000000000 }
{ "jobId": "j-1", "state": "failed",    "failure": "declined" }
```
`state ∈ {running, succeeded, failed}` · `failure ∈ {declined, timedOut, serviceUnavailable}`.

**Wire → Dart**: `MissingPluginException`, `badArguments`, `alreadyRunning` → `ClientException` · malformed payload / unknown enum / no reply in 5 s (`ensureNotificationPermission` exempt) → `TransportException` · `noActivity` → `ServiceException` (transient; re-assert on resume) · `serviceStartFailed` → **value** `Failed(serviceUnavailable)` · `failure: timedOut` → value `Failed(timedOut)`.

**Dart adapters** (data layer; placement confirmed in ticket 13): `ChannelSecurityEnvironment implements SecurityEnvironment` · `ChannelWindow implements SecureWindow` (+ `preferHighRefreshRate`, used by `app` bootstrap only — infrastructure, not a domain port) · `ChannelPaymentProcessor implements PaymentProcessor` (`start()` = `ensureNotificationPermission` then `start`; per-job stream filtered by `jobId`; `inFlight` = `current()` + stream) · `ChannelAppInfo` → `BuildInfo` for the debug `flavor == BRAND` assertion.

**Manifest owned by this contract**: `DETECT_SCREEN_RECORDING` (normal) · `FOREGROUND_SERVICE` · `POST_NOTIFICATIONS` · `<service android:name=".payment.PaymentJobService" android:exported="false" android:foregroundServiceType="shortService"/>` · `<queries>` for `com.topjohnwu.magisk`, `eu.chainfire.supersu`, `com.noshufou.android.su`, `com.koushikdutta.superuser`, `me.weishu.kernelsu` — kept in sync with the Kotlin constant list by a fixture-driven test.

**Kotlin layout** `dev.test.payment/`: `MainActivity.kt` · `bridge/{ChannelRegistry, MainThreadResult, MainThreadSink}.kt` · `security/{SecurityEnvironmentHandler, RootChecks, ScreenRecordingMonitor}.kt` · `window/WindowHandler.kt` · `payment/{PaymentJobHandler, PaymentJobService, PaymentJobStateHolder}.kt` · `app/AppInfoHandler.kt`.

**Fixtures** `contract/fixtures/`: `posture.secure`, `posture.compromised-rooted`, `posture.unverified-api34`, `job.running`, `job.succeeded`, `job.failed-declined`, `job.failed-timedOut`, `start.args`, `buildInfo.retail`, `preferHighRefreshRate.result` (`.json`).

## 10. Payment Job service and its lifecycle

Findings: `docs/research/foreground-service-compliance.md`. **`foregroundServiceType="shortService"`** — fits a
multi-second job inside its ~3-minute cap and needs no typed permission (`dataSync` rejected: wrong semantics, typed
permission, 6 h / 24 h cap). `POST_NOTIFICATIONS` (runtime, API 33+) is **not coupled to starting the service**: if denied, the
job still runs and only the notification is hidden — it is requested contextually when the user taps Pay and never gates the
job. `startForeground` must be called within 5 s of `startForegroundService` (`ServiceCompat.startForeground(…,
SDK_INT ≥ 34 ? FOREGROUND_SERVICE_TYPE_SHORT_SERVICE : 0)`); progress updates go through `NotificationManager.notify`
(channel `IMPORTANCE_LOW`, `setOngoing(true)`, `setProgress`); completion updates the notification to a final, non-ongoing
state and calls `stopForeground(STOP_FOREGROUND_DETACH)` + `stopSelf()` so the outcome persists in the shade until dismissed.
`onTimeout(startId)` (API 34 overload; verify the API 35 two-arg default delegates) → `failed(timedOut)`; `onDestroy` while
running → `failed(serviceUnavailable)`. `START_NOT_STICKY`. Android 16 `Notification.ProgressStyle` is optional and not used.

State lives in `PaymentJobStateHolder`, a process-wide `object` with a `MutableStateFlow<JobSnapshot?>`; the service is the
sole writer (plus `tryStart`'s compare-and-set), the handler only reads. A terminal snapshot is kept until delivered once
(to a sink or via `current()`), then cleared. Notification tap = the launcher intent (`singleTop`); the root route's BLoC
re-attaches through `current()`.

### 10.1 Sequence — happy path

1. BLoC `PayPressed` (`canPay`) → `PaymentProcessor.start(payment)` (adapter `ChannelPaymentProcessor`).
2. Adapter: `ensureNotificationPermission()` (logged, never gates) → `start({reference, amountMinor, currency, payee})`.
3. `PaymentJobHandler` (main): validate → `holder.tryStart(jobId)` → `startForegroundService` → `{jobId}` via `MainThreadResult`.
4. Adapter subscribes `payment.job/events` → `onListen` collects `holder.state` on `Main.immediate` → replays `running(0)` → filtered by `jobId` → `Running(0)` → BLoC `Processing(0)`.
5. `PaymentJobService.onStartCommand`: extras → `IMPORTANCE_LOW` ongoing notification → `ServiceCompat.startForeground(NOTIF_ID, n, SDK_INT ≥ 34 ? SHORT_SERVICE : 0)` → ticker → `START_NOT_STICKY`.
6. Ticker: `holder.update(running(p))` + `notify(NOTIF_ID, n(p))` per tick; decline check at 60 %; `succeeded(reference, completedAt)` at 100 %.
7. Terminal: holder ← terminal → final notification → `stopForeground(STOP_FOREGROUND_DETACH)` → `stopSelf()` → `onDestroy` cancels the scope (terminal not overwritten).
8. Collector delivers the terminal → adapter completes the per-job stream → BLoC `Completed(outcome)` → holder marks delivered and clears.

**Threading**: handler methods and `startForegroundService` on main; ticker writes from `Default` (`StateFlow` is thread-safe); collector on `Main.immediate` so `MainThreadSink` is a no-op guard; `current()` reads on main.

### 10.2 Kotlin responsibilities

| Class | Owns |
|---|---|
| `PaymentJobStateHolder` (`object`) | `state: StateFlow<JobSnapshot?>` · `tryStart(jobId): Boolean` · `update(snapshot)` · delivered-once clearing |
| `PaymentJobHandler` | `start` / `current` / `ensureNotificationPermission` · stream handler (collect ↔ cancel) · pending permission `Result` fed by `onRequestPermissionsResult` |
| `PaymentJobService` | channel creation · `startForeground` · ticker · terminal handling · `onTimeout` · `onDestroy`-while-running |
| `PaymentJobNotifications` | pure builders for progress and final notifications (unit-testable) |

**Dart `ChannelPaymentProcessor`**: `start(payment)` → per-job stream = events `.where(jobId).map(parse)`, completing inclusively on a terminal state. `inFlight()` → `current()`: `null` → `null`; terminal → `Stream.value(parsed)`; running → the filtered stream (replay-1 supplies the current snapshot).

**Dart `ChannelPaymentProcessor`**: `start(payment)` calls `ensureNotificationPermission` (logged, never gating) then `start`, and
returns the events stream filtered by `jobId`, completing inclusively on a terminal state. `inFlight()` → `current()`: `null` →
`null`; terminal → `Stream.value(parsed)`; running → the filtered stream (replay-1 supplies the current snapshot).

### 10.3 Scenarios

| # | Scenario | Behaviour |
|---|---|---|
| 1 | Happy path | Sequence above; Result View in-app; detached "Payment complete" notification persists until dismissed |
| 2 | Declined (`cents == 99`) | `failed(declined)` at 60 %; "Payment declined" notification; `Completed(Failed)` → Retry |
| 3 | Home mid-job (paused, engine alive) | Ticker and notification continue; stream keeps delivering; return → UI already current |
| 4 | Leave the app mid-job (engine destroyed, process alive) | Collector disposed with the engine; job continues; notification reaches final state and detaches. Reopen (launcher / notification tap) → new engine → `Started` → `current()`: `running` → `Processing(p)`; undelivered terminal → `Completed(outcome)`; then cleared |
| 5 | Process killed mid-job | Service and holder gone; `START_NOT_STICKY`; relaunch → fresh confirmation. Documented limitation |
| 6 | `shortService` timeout | `onTimeout` → `failed(timedOut)`; final notification; detach; `stopSelf` |
| 7 | Service destroyed while running | `onDestroy` → `failed(serviceUnavailable)`; scope cancelled |
| 8 | `POST_NOTIFICATIONS` denied | Job runs; nothing in the shade; in-app progress and Result View unaffected |
| 9 | Double start | CAS fails → `alreadyRunning` → `ClientException` (unreachable via the BLoC guard) |
| 10 | `startForegroundService` throws | Holder reset → `serviceStartFailed` → value `Failed(serviceUnavailable)` → Retry |
| 11 | Posture degrades mid-job (API 35+) | Kotlin unaware; BLoC composes streams; job completes; Result View shows the caveat |
| 12 | Rotation / dark-mode toggle | Activity survives (template `configChanges`); nothing happens |
| 13 | Relaunch long after a delivered completion | Holder cleared → fresh confirmation, no stale result |

## 11. Secure Window

`SecureSessionScope` (`StatefulWidget`, `security_guard/presentation`) wraps the payment page's content — `initState` →
`acquire()`, `dispose` → `release()` — over a **ref-counted** `SecureWindowController` (lazy singleton) that calls the
`SecureWindow` port only on 0→1 and 1→0 transitions, so stacked secure routes and dialogs never toggle the flag. The
*route* is the single lifetime owner; two objects share it — the scope (window flag) and `SecurityPostureCubit`'s subscription
(recorder callback) — and they are deliberately not merged ("one lifetime, two owners"). The controller re-asserts on
`AppLifecycleState.resumed` when `count > 0`; a `ServiceException` from `acquire` is logged and retried on resume, never
surfaced. Kotlin is **stateless** (`addFlags` / `clearFlags`; Dart is the source of truth). The launch gap (an async
`acquire()` from `initState`) is accepted: the embedding shows the launch theme until Flutter's first frame, and the platform
message lands within the same vsync window; secure-by-default in `onCreate` was rejected for a one-route module.

### 11.1 Invariants

(i) the flag is set whenever `count > 0` and cleared whenever `count == 0`; (ii) the Result View is part of the same route (ticket 07), so it stays secure until pop; (iii) `release` on the last scope is the only path that clears the flag; (iv) `PopScope(canPop: false)` during `Processing` is the BLoC/page's rule — the scope never blocks navigation.

### 11.2 Scenarios

| # | Scenario | Expected calls |
|---|---|---|
| 1 | Page mounted | `setSecure(true)` × 1 |
| 2 | Dialog shown / dismissed over the page | none |
| 3 | Second secure route pushed, then popped | none, none |
| 4 | App paused → resumed with the page mounted | `setSecure(true)` × 1 (re-assert) |
| 5 | Job completes → Result View | none (same route) |
| 6 | Pop the flow | `setSecure(false)` × 1 |
| 7 | `acquire` throws `ServiceException` | swallowed + logged; next resume → `setSecure(true)` |
| 8 | Back pressed during `Processing` | blocked by `PopScope`; scope untouched |

Plus one `TestDefaultBinaryMessengerBinding` contract test for the `window` channel (`setSecure` args; `noActivity` → `ServiceException`).

## 12. Security Scan visual and rendering performance

### 12.1 The visual

**Radar** (`RadarPainter`, prototype `prototype/security-scan`): rings that pulse for the fluid brand and stay static for the
dense one, a rotating gradient sweep (wide/soft vs narrow/sharp), fading blips (round vs square), a centre dot. One painter,
no `scanStyle` configuration — all brand variation comes from `BrandTokens` (`seed`, `accent`, `density`, `scanMinDuration`).
**Motion rule: one full sweep == `scanMinDuration`**, so the Scan phase always shows at least one complete cycle and can stop at
any phase boundary. Runner-up, named for the record: a grid shield (strongest security metaphor, ~260 draw calls per frame).
Reduced motion (`MediaQuery.disableAnimationsOf`): the controller stops at a fixed phase — a static radar — while the Scan
phase still lasts `scanMinDuration`.

```dart
// security_guard/presentation
class SecurityScanView extends StatefulWidget {                  // const-constructible; no style parameter
  const SecurityScanView({super.key, this.size = const Size(280, 200)});
}
// State: AnimationController(vsync, duration: tokens.scanMinDuration)..repeat();
//        tokens read in didChangeDependencies (rebuild painter only when tokens change);
//        MediaQuery.disableAnimationsOf(context) → controller.stop() at value 0.25;
//        build: RepaintBoundary(child: CustomPaint(size, painter: RadarPainter(tokens: tokens, progress: controller)))

class RadarPainter extends CustomPainter {                      // src/, not exported
  RadarPainter({required this.tokens, required Animation<double> progress}) : …preallocated Paints…, super(repaint: progress);
  @override bool shouldRepaint(RadarPainter old) => old.tokens != tokens;
}
```

Painter discipline (all honoured in the prototype): `super(repaint: progress)` so frames never rebuild widgets; Paints and
shaders preallocated in the constructor (the sweep gradient is built once and the canvas rotated per frame); tokens read once;
`shouldRepaint` false unless tokens change; time-based maths via `controller.value`; `Path` objects reused; the
`RepaintBoundary(child: CustomPaint)` sits in a const-constructible widget *above* the `BlocBuilder` subtree.

### 12.2 Refresh rate (findings: `docs/research/120hz-android.md`)

Flutter follows whatever mode Android has put the display in and never asks for more; several OEM families hold third-party apps
at 60 Hz. At bootstrap the app calls `window · preferHighRefreshRate` (our own channel; `preferredDisplayModeId` to the highest
rate at the current resolution, API 23+, gate-free at `minSdk` 26) and declares `android:appCategory` in the manifest; both are
best-effort against OEM power modes and user caps. Because the animation is time-based, only the frame budget changes:
every assertion reads the live `Display.refreshRate` and uses `1000 / refreshRate` ms — never a hard-coded 16 or 8.

### 12.3 Proof

1. **Isolation — deterministic, CI.** The canary widget test from the prototype moves into `security_guard`: a trivial
   `CustomPaint` in the page layer counts page-layer repaints while the scan animates and a fake BLoC emits progress.
   Measured on the prototype for radar/waveform/grid × Retail/Utility: **60 animation frames → 60 scan paints, 0 page-layer
   paints; 10 emissions → 10 page-layer paints; control with the boundary removed → 60 page-layer paints.**
2. **Timing — on device.** `integration_test/perf_test.dart` wraps the scan in `IntegrationTestWidgetsFlutterBinding.watchPerformance()`
   for a fixed window while the BLoC emits progress at 10 Hz and asserts `buildDuration` / `rasterDuration` percentiles under the
   computed budget; cross-checked with `adb shell dumpsys display` (active mode) and `dumpsys gfxinfo <pkg> framestats`.
   Validate the nudge on a real 120 Hz device from a flagged OEM family before claiming it.
3. The repaint rainbow (`debugRepaintRainbowEnabled`) stays a dev-time tool, not a test.

## 13. Adding a brand

Measured on the prototype with a hypothetical third brand, *Acme Energy*, including a section `payment` had never heard of.

| # | File | Change |
|---|---|---|
| 1 | `lib/brands/acme.dart` *(new)* | `const acmeBrand = BrandConfig(id: BrandId('acme'), displayName: …, tokens: BrandTokens(…), features: [PaymentBrandConfig(ctaLabel, sections), SecurityBrandConfig(policy)])`; brand-unique sections via `CustomSection(builder)` in this file |
| 2 | `lib/brands/registry.dart` | one element added to `BrandRegistry([...])` |
| 3 | `android/app/build.gradle.kts` | one `create("acme") { dimension = "brand"; applicationIdSuffix = ".acme"; resValue("string", "app_name", "Acme Energy") }` block |
| 4 | `android/app/src/acme/res/mipmap-*/` *(optional)* | launcher icon; default icon otherwise |
| 5 | *(generated)* `test/golden/goldens/acme/*.png` | `flutter test --update-goldens --tags golden`; the registry-driven golden test fails until the new brand's goldens exist and are reviewed |

Three mandatory edits, one optional, one generated. No script edits: the Makefile target is parametrised — `make apk BRAND=acme` → `flutter build apk --flavor $(BRAND) --dart-define=BRAND=$(BRAND)`.

### 13.1 The guard

1. **`test/brands/brand_registry_test.dart`** iterating `brandRegistry.all`: `feature<PaymentBrandConfig>()` and `feature<SecurityBrandConfig>()` resolve; ids unique, non-empty, `[a-z][a-z0-9]*`; `displayName` non-empty; `sections` has exactly one `SummarySection` and one `PayButtonSection` (the single layout invariant `payment` imposes); every `CustomSection` has a non-empty `debugLabel`; `PosturePolicy` covers every `ThreatKind` (the constructor also asserts this in debug); `buildBrandTheme(brand)` succeeds with the `BrandTokens` extension present.
2. **Flavor ↔ registry**: a test regex-parses `productFlavors { create("…") }` from `android/app/build.gradle.kts` and asserts set-equality with registry ids; the runtime debug assertion `buildInfo().flavor == BRAND` (ticket 10) catches a mismatched build command. Scaling path, named in the spec: generate `brands.gradle.kts` from the registry once brands number in the dozens.
3. **Per-brand goldens** — `test/golden/payment_page_golden_test.dart`: each brand × six BLoC-driven states (Scanning · AwaitingConfirmation/Secure · AwaitingConfirmation/Unverified · Processing 40 % · Completed/Succeeded · Completed/Failed), pumping the real `PaymentConfirmationPage` with scripted fakes from `test/support/fakes/`; `goldens/<brandId>/<state>.png`, phone viewport; tagged `golden`, executed in CI on Linux (platform-sensitive rendering).

The recipe is a documentation section whose every step is enforced by a failing test if skipped; there is deliberately no
`tool/new_brand.dart` generator (a checklist the tests enforce cannot drift; a generator tracking the `BrandConfig` shape can).

## 14. Testing strategy

| Where | What | Doubles |
|---|---|---|
| `lib/core` | value semantics of `Money`, `PosturePolicy`, `BrandId` | — |
| `lib/brand_engine` | `feature<T>()` failure modes · token → `ThemeData` mapping · registry lookup | — |
| `features/security_guard` | `WatchPostureVerdict` ordering and policy application · `SecurityPostureCubit` (bloc_test) · `SecureWindowController` scenarios (§11.2) · channel contract tests via `TestDefaultBinaryMessengerBinding` + fixtures · the **canary isolation test** (§12.3) | `FakeSecurityEnvironment`, `FakeSecureWindow` (`test/support/fakes/`) |
| `features/payment` | `bloc_test` for every row of the §7.1 table · unit tests for `canPay` and the derived rules · page widget tests · channel contract tests + fixtures · `JobSnapshotCodec` | `FakePaymentProcessor`, `FakePaymentRepository` (`test/support/fakes/`) |
| composition root | registry completeness · flavor↔registry · per-brand goldens (`golden` tag, Linux CI) · `test/architecture_test.dart` · `integration_test/perf_test.dart` | the same fakes |
| Kotlin (JVM) | `MainThreadResult` / `MainThreadSink` hop to main · payload builders against `contract/fixtures/` · `PaymentJobNotifications` builders · `RootChecks` threshold logic with injected signals | no Robolectric, no instrumented tests |

Test doubles are scripted fakes, not mocks (`mocktail` where a mock is genuinely simpler). The `contract/fixtures/*.json`
files pin every message on both sides of the bridge. The architecture test (§3.3) and the completeness test (§13.1) are the
two "keep it honest" tests that fail when a convention is skipped.

## 15. Build, run, demo

```sh
make run BRAND=retail          # fvm flutter run  --flavor retail  --dart-define=BRAND=retail
make apk BRAND=utility         # fvm flutter build apk --flavor utility --dart-define=BRAND=utility
make test                      # fvm flutter test  (architecture test included; goldens excluded)
make goldens                   # fvm flutter test --tags golden --update-goldens
make analyze                    # dart analyze --fatal-infos  (NOT flutter analyze — see §3.3)
make format
```

Debug builds assert `buildInfo().flavor == BRAND` at startup. **Demo guidance**: for the Secure path use a *Google Play* AVD
system image (release keys, no root) or a real unrooted device — *Google APIs*/AOSP images are pre-rooted and test-key-signed
and legitimately show Compromised (say so on camera). The positive screen-recorder case needs an API 35+ device or emulator and
the Quick Settings *Screen Record* tile; an API ≤ 34 emulator shows the Unverified notice on Utility. Recording the deliverable
video: `FLAG_SECURE` blanks `adb screenrecord` and MediaProjection recorders — record via the emulator's host-side recorder or an
external camera (host-side recorder behaviour is unverified; test early).

## 16. Decision index and considered alternatives

| Decision | Chosen | Rejected | Record |
|---|---|---|---|
| Module boundaries | one application package, feature-first, lint-enforced walls | Pub-workspace packages (the named scaling path); Melos | ADR-0001 |
| Brand selection | `--dart-define` + registry + flavor, 1:1 | per-brand entrypoints; `flutter_flavorizr`; runtime switching | ADR-0002 |
| Native bridge | hand-written channels, 4 + 2 | Pigeon; one kitchen-sink channel | ADR-0003 |
| Platform scope | Android only, no fallback adapters | iOS; no-op adapters | ADR-0004 |
| Use cases | only where logic lives (one: `WatchPostureVerdict`) | one per operation | ADR-0005 |
| State management | BLoC — two units split on the feature seam (`PaymentConfirmationBloc`, `SecurityPostureCubit`), no bloc-to-bloc events | Riverpod; one composite bloc (first design); three or more units | ticket 07 |
| Errors / model | exception hierarchy + sealed values; `equatable`, no codegen | `Either`/`Result`; `freezed` | charting Q11–12 |
| Sections | sealed hierarchy + `CustomSection` | closed enum; slots; open objects without `sealed` | ticket 08 |
| Root detection | six hand-rolled signals, ≥ 2 threshold | RootBeer; Play Integrity | ticket 01 |
| Recorder detection | API 35 callback, `unavailable` below | package/DisplayManager/FGS heuristics | ticket 02 |
| Foreground service | `shortService`, detach-and-keep notification | `dataSync`; remove on completion; bound service | tickets 03, 12 |
| Refresh rate | own `window` channel method | `flutter_displaymode` plugin | ticket 04 |
| Layer lint | `import_lint` + architecture test | `custom_lint`; DCM; barrels only | ticket 05 |
| Scan visual | radar, one painter | grid shield; waveform; per-brand `scanStyle` | ticket 09 |
| Secure Window | scope widget + ref-counted controller, Dart-owned | `RouteObserver`; secure-by-default in `onCreate` | ticket 11 |
| Result | a phase of the same route | separate `PaymentResultPage` | ticket 07 |
| Adding a brand | doc recipe + tests | `tool/new_brand.dart`; flavors generated from the registry (scaling path) | ticket 14 |

Ticket answers live under `.scratch/payment-module-architecture/issues/`; each carries the full reasoning and the round-by-round
grilling that produced it.

## 17. Known limitations and open items

- **Process death loses an in-flight job** (`START_NOT_STICKY`) — a property of a *simulated* processor; a real one is
  server-authoritative behind the same `inFlight` seam.
- Screen-recorder detection is `unavailable` below API 35 by design; non-MediaProjection OEM capture paths are undetectable.
- The claim that `FLAG_SECURE` does not suppress `addScreenRecordingCallback` is verified from AOSP source, not prose docs —
  spike it on a real API 35+ device before relying on it for the demo.
- OEM power modes and user caps can hold the app at 60 Hz regardless of the nudge; measure, don't assume.
- `import_lint` is verified working (§3.3), but only via `dart analyze --fatal-infos` — `flutter analyze` silently never
  runs it. `flutter build apk --flavor retail|utility` remains on the scaffold's smoke-test list.
- Goldens are platform-sensitive: run under the `golden` tag on Linux CI.
- `onTimeout` overloads differ between API 34 and 35 — override the one-arg form and verify delegation.
- Emulator host-side recording of a `FLAG_SECURE` window is unverified.
- A CI matrix building both APKs is a nice-to-have left unspecified.

**Next step**: implementation planning from this document (`/writing-plans`), starting with the scaffold and its smoke tests.
