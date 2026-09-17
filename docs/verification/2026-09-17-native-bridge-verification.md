# Native bridge verification — 2026-09-17

Verified against `docs/architecture.md` §8–§12 and §14, for Plan 4
(`docs/superpowers/plans/2026-09-17-native-android-bridge.md`).

## Results
- Dart: `flutter test` — 155 tests passing (109 before this plan; 44 planned + 2 added by a review fix).
- Lint: `dart analyze --fatal-infos` — no issues.
- Kotlin JVM: `./gradlew :app:testRetailDebugUnitTest` — 44 tests passing.
- Android lint (`lintRetailDebug`): 0 errors, 5 warnings.
- Both flavors build: `app-retail-debug.apk`, `app-utility-debug.apk`.
- On device: `integration_test/native_bridge_test.dart` — +7: All tests passed! on `emulator-5554`, API 37.

## Lint walls
- `native_bridge_via_barrel`: fires when a feature imports `native_bridge/src/` directly
  (temporary import in `channel_secure_window.dart`, rule name observed, reverted).
- `native_bridge_depends_on_core_only`: fires when `native_bridge` imports a feature
  (temporary import in `native_channels.dart`, rule name observed, reverted).

## Contract
- Every channel name and every payload in §9 is pinned by `contract/fixtures/`, read by both the
  Dart contract tests and the Kotlin JVM tests; the root-package list is pinned to the manifest's
  `<queries>` by `RootPackagesManifestTest`.
- `BuildConfig.FLAVOR` only exists once product flavors are defined, which is why the flavors
  landed in this plan rather than with the brand registry.

## Behaviour changed in earlier features
- `PaymentConfirmationBloc` now turns a failing job stream into `Completed(Failed(serviceUnavailable))`
  and a failing `inFlight()` into "no job in flight" — the channel adapter fails asynchronously, the
  fake did not.
- `registerSecurityModule` / `registerPaymentModule` register the real adapters by default and
  `SecureWindowController` as a lazy singleton; overrides still win.

## Changes beyond the plan (from code review)
- `ChannelPaymentProcessor._progressOf` is a stream-transformer chain instead of the plan's `async*`
  loop: a cancelled `await for` only notices at its next `yield`, so the native `payment.job/events`
  subscription (and the Kotlin collector) outlived a cancelled job stream. Two regression tests pin
  the immediate cancel.
- `DeviceRootSignals` force-kills a timed-out command (`destroyForcibly`), as
  `docs/research/root-detection.md` recommends.
- `ScreenRecordingMonitor.start()` keeps its `registered` flag truthful if re-registration throws.
- `PaymentJobService` documents why stopping with the newest start id is safe: a review raised a
  retry-during-teardown race, which main-thread message ordering makes unreachable.
- Declined review suggestions, with reasons: resolving pending permission replies on engine detach
  (the Dart isolate is gone with the engine); validating the start intent before `startForeground`
  (the 5 s rule requires `startForeground` first, and the code says so).

## Not verified here
- The positive screen-recorder case (needs the Quick Settings recorder on an API 35+ device) and
  `FLAG_SECURE` actually blanking a recording — both remain on §17's list.
- The `shortService` timeout path (`onTimeout`) — a 5 s job never reaches the ~3 min cap.
