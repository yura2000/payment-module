# 13. Package seams

Type: grilling
Status: resolved
Blocked by: 07, 08, 10, 12
Part of: ../map.md

## Question

Using the `codebase-design` vocabulary, fix the **interface** of each package — what its barrel exports and therefore what tests exercise: `core`, `brand_engine`, `security_guard`, `payment`, `app`. For each: the seam (public types/functions), the adapters behind it (channel adapter, in-memory repository, test doubles), what stays in `src/`, and the registration function shape (`registerXModule(GetIt)`). Apply the deletion test to anything that looks like a pass-through; prefer fewer, deeper modules.

**Deliverable**: per-package interface listing for the spec.

**Inputs from resolved tickets**
- Ticket 07: provisional placement of domain types, ports (`SecurityEnvironment`, `SecureWindow`, `PaymentProcessor`, `PaymentRepository`) and use cases — confirm or move.
- Ticket 10: adapters `ChannelSecurityEnvironment`, `ChannelWindow` (also exposes `preferHighRefreshRate` for `app` bootstrap — infrastructure, not a domain port), `ChannelPaymentProcessor`, `ChannelAppInfo`; decide which package exports what (`security_guard` exports `SecureWindow` + `SecurityEnvironment` ports and their channel adapters via `registerSecurityModule`; where `ChannelAppInfo`/`BuildInfo` live — `app` or `core`).
- Ticket 12: `PaymentProcessor { Stream<PaymentJobProgress> start(Payment); Future<Stream<PaymentJobProgress>?> inFlight() }` is the port shape the adapter implements; `PaymentJobNotifications` and `PaymentJobStateHolder` are Kotlin-internal seams (unit-tested, not exported).
- Ticket 11: `security_guard` exports `SecureSessionScope` and `SecureWindowController` (presentation) plus the `SecureWindow` port; `ChannelWindow` (and its `preferHighRefreshRate` for `app` bootstrap) is a `src/` adapter surfaced only through `registerSecurityModule`.
- Ticket 08: exports fixed by the prototype — `brand_engine`: `BrandFeatureConfig`, `BrandTokens`, `BrandConfig` (+ `feature<T>()`), `BrandScope`, `buildBrandTheme`, the `context.tokens` extension; `payment`: the sealed `PaymentSection` hierarchy incl. `CustomSection`, `PaymentBrandConfig` (presentation layer); `security_guard`: `SecurityBrandConfig` (domain layer). Concrete brands + `BrandRegistry` live in `app/lib/brands/`.

## Answer

**Resolved 2026-09-16 (grilling, 1 round; all recommendations accepted).** Vocabulary: `codebase-design` (module / interface / seam / adapter / deletion test).

### Decisions
1. **`BrandId` is `extension type BrandId(String value)`** in `core`: open set, zero-cost, no shared-package edit per brand, and nothing can `switch` over brands exhaustively. (The prototype's enum was expedient, not the design.)
2. **Use cases collapsed to where logic lives** (revises ticket 07/Q12's "one use case per operation"). Deleted as pure delegation with a single caller: `LoadPayment`, `ConfirmPayment`, `FindInFlightJob`, `WatchSecurityPosture`. The BLoC uses `PaymentRepository` and `PaymentProcessor` directly. One deep use case remains on the security side: `WatchPostureVerdict(environment, policy) → Stream<PostureUpdate(posture, verdict)>` — owns the `assess()` kick-off, stream merge, `distinct`, and policy evaluation; `evaluatePosturePolicy(policy, posture)` is its pure internal seam, exported for unit tests. **Spec rule**: *a use case exists only where a decision or orchestration lives; delegation is not a reason.* (AI Insight Report entry: an earlier round proposed five wrappers; the deletion test removed four.)
3. **Bootstrap adapters belong to `app`**: `app/lib/bootstrap/ChannelDisplayMode` (`preferHighRefreshRate`) and `ChannelAppInfo` (`buildInfo`) talk to the `window` / `app` channels; `security_guard` keeps only `ChannelSecureWindow` (`setSecure`). Two Dart classes over one Kotlin channel name is fine.
4. **Private BLoC, public fakes.** `PaymentConfirmationBloc` + state stay in `src/`; `app`'s goldens drive the real BLoC through `PaymentConfirmationPage` with scripted fakes (test through the interface). Fakes ship via second entrypoints `package:security_guard/testing.dart` and `package:payment/testing.dart`. Registration is a plain function per package with named overrides: `registerSecurityModule(GetIt, {SecurityEnvironment? environment, SecureWindow? window})`, `registerPaymentModule(GetIt, {PaymentRepository? repository, PaymentProcessor? processor})`. No `FeatureModule` interface.
5. **Money**: `core` holds `Money(amountMinor, currency)` as data; formatting via `intl` `NumberFormat.simpleCurrency` in `payment/presentation`.
6. **`SecurityScanView` and `PostureBanner(verdict)` live in `security_guard/presentation`**; `PaymentConfirmationPage` composes them (`payment → security_guard` domain + presentation, allowed by the settled cross-package rule).

### Per-package interface listing (for the spec, verbatim)
```
core  (pure Dart)
  exports   BrandId (extension type) · Money · ThreatKind · PosturePolicy (+ DetectedResponse, UnavailableResponse)
            sealed AppException → ServiceException | ClientException | TransportException
  adapters  none (in-process)                     tests  value semantics only

brand_engine  (Flutter)
  exports   BrandFeatureConfig · BrandTokens (ThemeExtension) · BrandConfig + feature<T>() · BrandRegistry (type: all, byId)
            BrandScope · buildBrandTheme · BuildContext.tokens
  src       colour-scheme / shape / density builders      adapters  none
  tests     feature<T>() failure modes · token→ThemeData mapping · registry lookup
  deletion  passes: theme building + scope + lookup would reappear in every feature

security_guard  (Flutter)
  domain    ThreatAssessment · AssessmentResult · SecurityPosture · PolicyVerdict · PostureUpdate · SecurityBrandConfig
            ports  SecurityEnvironment { assess(); posture }   SecureWindow { setSecure(bool) }
            use case  WatchPostureVerdict(environment, policy) → Stream<PostureUpdate>   pure fn  evaluatePosturePolicy
  presentation  SecureSessionScope · SecureWindowController · SecurityScanView · PostureBanner
  registration  registerSecurityModule(getIt, {environment, window})
  testing.dart  FakeSecurityEnvironment (scripted postures) · FakeSecureWindow (records calls)
  src       ChannelSecurityEnvironment · ChannelSecureWindow · PostureSnapshotCodec · painter internals
  seams     SecurityEnvironment: Channel + Fake ✓ real · SecureWindow: Channel + Fake ✓ real
  tests     use case via fake env · controller scenarios (11) · channel contract tests + fixtures

payment  (Flutter)
  domain    Payment · LineItem · PaymentJobProgress · PaymentFailure · PaymentReceipt
            ports  PaymentRepository { load() }   PaymentProcessor { start(Payment); inFlight() }
  presentation  PaymentConfirmationPage · sealed PaymentSection (Summary | PromoBanner | BillBreakdown | PayButton | Custom) · PaymentBrandConfig
  registration  registerPaymentModule(getIt, {repository, processor})
  testing.dart  FakePaymentProcessor (scripted progress, inFlight control) · FakePaymentRepository
  src       PaymentConfirmationBloc + events/state · InMemoryPaymentRepository (demo Payment) · ChannelPaymentProcessor · JobSnapshotCodec
            section widgets · money formatting (intl)
  seams     PaymentProcessor: Channel + Fake ✓ real · PaymentRepository: InMemory + Fake — kept for the architecture's sake
            (a real backend is the second production adapter this seam exists for); stated as such in the spec
  tests     bloc_test through fakes (07's table) · page widget tests · channel contract tests + fixtures

app  (Flutter application)
  lib       main.dart → bootstrap(): BRAND dart-define → BrandRegistry → setupLocator(brand) → preferHighRefreshRate → debug drift assertion → runApp
            PaymentApp (MaterialApp + BrandScope + PaymentConfirmationPage) · brands/{retail, utility, registry}.dart
            locator.dart (setupLocator → brand singletons, registerSecurityModule, registerPaymentModule) · bootstrap/{ChannelDisplayMode, ChannelAppInfo}.dart
  android   Kotlin per ticket 10
  tests     per-brand goldens from the registry (fakes) · completeness test (14) · integration_test/perf_test.dart (watchPerformance) · contract fixtures at contract/fixtures/
```

### Consequences pushed
- Ticket 07: addendum — the BLoC's collaborators are `PaymentRepository`, `PaymentProcessor`, `WatchPostureVerdict` (not the five use cases); the state machine itself is unchanged.
- Ticket 14: `BrandId` is a string extension type — the recipe's registry line is `BrandConfig(id: BrandId('acme'), …)`; the completeness test also asserts ids are unique and match Gradle flavor names.
- Ticket 15: listing verbatim; the use-case rule; `testing.dart` convention; ADR candidate "use cases only where logic lives" (deviation from textbook Clean Architecture — hard to reverse socially, surprising, real trade-off).
- Map Notes: the "Errors & model" row's "explicit callable use cases, one per operation" is superseded by this ticket.

## Addendum (2026-09-16, after map completion)
Layout revised at the user's request: **single application package, feature-first** (ADR-0001). The interfaces above are unchanged; paths move — `packages/core` → `lib/core`, `packages/brand_engine` → `lib/brand_engine` (barrel + `src/`), `packages/<feature>` → `lib/features/<feature>` (barrel + `src/{domain,data,presentation}` + `di.dart`), `app` → `lib/app` + `lib/brands` + `lib/bootstrap`; `package:<feature>/testing.dart` → `test/support/fakes/`. Module walls (the DAG, barrel-only access) are now `import_lint` rules alongside the layer rules. The spec §4 carries the final listing.

## Addendum (2026-09-16, #2)
`security_guard/presentation` additionally exports `SecurityPostureCubit`; `payment`'s `src/` gains the derived display rules (`canPay` etc.). See spec §4.
