# Native Android Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the whole native channel contract of `docs/architecture.md` §9 on both sides — the Kotlin handlers (security environment with root checks and the API 35+ recorder callback, window, the `shortService` Payment Job foreground service, app info), the Dart channel adapters behind the `SecurityEnvironment`, `SecureWindow` and `PaymentProcessor` ports, and the two bootstrap adapters — and make `registerSecurityModule` / `registerPaymentModule` register the real adapters by default.

**Architecture:** Fourth of five implementation plans (Plan 1: workspace/core/brand_engine; Plan 2: security_guard; Plan 3: payment — all done, `develop` at `974c11f`). Plans 2–3 built every port and tested it against fakes; this plan adds the second adapter of each native seam (ADR-0004): hand-written `MethodChannel`s/`EventChannel`s (ADR-0003) pinned on both sides by shared JSON fixtures in `contract/fixtures/`. The shared Dart channel plumbing (channel names, the timeout + error-code translation, typed payload reading) lives in a new leaf module `lib/native_bridge/`, because three modules need it and `core` must stay Flutter-free. Kotlin keeps its logic in pure, JVM-tested classes (payload builders, the root-signal threshold, the job state holder, the job simulation, notification specs) and keeps the Android-bound shells (handlers, service, renderer) thin. The plan ends with an on-device integration test that drives every channel through the real Dart adapters.

**Tech Stack:** Flutter 3.44.6 / Dart 3.12 via FVM; Kotlin 2.3.20, AGP 9.0.1, Java 17, `compileSdk`/`targetSdk` 36, `minSdk` 26. New Android dependencies: `androidx.core:core-ktx:1.17.0`, `org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2`; test-only `junit:junit:4.13.2`, `org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0`. New Dart dev dependency: `integration_test` (SDK). Every version here was compiled and run while writing this plan.

**Carry-forward from Plans 1–3** (apply automatically, don't re-derive): the lint command is `dart analyze --fatal-infos`, never `flutter analyze`; every `import_lint` rule needs an explicit `except: []`; tests import a module's barrel (or its `di.dart`), never its `src/`.

**Reference:** `docs/architecture.md` §8 (security posture assessment), §9 (the channel contract — the source of truth for every name, payload and error code below), §10 (Payment Job service and lifecycle, including the scenario table), §11 (Secure Window), §12.2 (refresh rate), §14 (testing strategy). `docs/adr/0003-hand-written-channels-over-pigeon.md`, `docs/adr/0004-android-only-no-fallback-adapters.md`. Research: `docs/research/root-detection.md`, `docs/research/screen-recorder-detection.md`, `docs/research/foreground-service-compliance.md`, `docs/research/120hz-android.md`. `CONTEXT.md` for every domain term.

**Scope boundary — what this plan does NOT build:** `lib/main.dart`'s real `bootstrap()`, `lib/app/` (`PaymentApp`, `setupLocator`), `lib/brands/` (the two `BrandConfig`s and the registry), the debug `flavor == BRAND` assertion, the `Makefile`, `PaymentConfirmationPage` and its sections, `SecurityScanView`/`PostureBanner`, goldens, `test/architecture_test.dart`, the flavor↔registry test, `integration_test/perf_test.dart` — all Plan 5 (composition root). This plan adds the Android product flavors (see decision 3 below) but not their Dart counterparts. Success criterion: `flutter test` passes (109 existing + 44 new = 153), `dart analyze --fatal-infos` is clean, `./gradlew :app:testRetailDebugUnitTest` passes (44 JVM tests), `lintRetailDebug` reports 0 errors, both flavors build, and `integration_test/native_bridge_test.dart` passes 7/7 on a device.

### Decisions this plan makes beyond `docs/architecture.md`

Each was forced by something discovered while writing and running this plan's code. Task 22 folds them back into the architecture document.

1. **New leaf module `lib/native_bridge/`** (`NativeChannels`, `invokeNative`, `WireMap`), used by `features/security_guard`, `features/payment` and `bootstrap` through its barrel. `core` cannot hold it (`PlatformException` is Flutter); copying the timeout and error mapping into five adapters would be the alternative. Two new lint rules keep it a leaf: `native_bridge_depends_on_core_only`, `native_bridge_via_barrel`.
2. **`contract/fixtures/channels.json`** pins the six channel names on both sides, next to the ten payload fixtures §9 lists.
3. **The Android product flavors (`retail`, `utility`) land here, not in Plan 5.** `BuildConfig.FLAVOR` does not exist until flavors are defined (confirmed: `Unresolved reference 'FLAVOR'`), and `app · buildInfo` must return it. From Task 11 on, every `flutter run`/`flutter build` needs `--flavor retail` or `--flavor utility`.
4. **`minSdk = 26` is set explicitly.** The template's `flutter.minSdkVersion` is 24, not the 26 in §1; the notification channel and `Process.waitFor(timeout)` are used without version gates on the basis of 26.
5. **`assess` acks as soon as an assessment is running** (a new one or the one in progress), and a posture snapshot is only published once both halves are known: the first root assessment, and the recorder state. This keeps the ack well under the 5 s reply timeout, even though the root checks run up to three 1 s shell commands.
6. **`PaymentConfirmationBloc` is hardened for the real adapter** (Task 8). The fake throws from `start()` synchronously; the channel adapter starts the job asynchronously, so it fails *through the stream*. A failing job stream now becomes `Completed(Failed(serviceUnavailable))`, the same exception-to-value rule as §7.1's "`processor.start` throws" row. A failing `inFlight()` is treated as "no job in flight".
7. **`PaymentJobStateHolder` is a class with one process-wide `shared` instance**, not a Kotlin `object`, so each JVM test gets a fresh one.
8. **Notification content is plain data** (`NotificationSpec`, JVM-tested) and is rendered by a separate Android-only `NotificationRenderer`.
9. **Both `onTimeout` overloads are overridden** (API 34's one-arg, API 35's two-arg) and do the same thing. This closes §17's "verify delegation" item without relying on either OS version's dispatch.
10. **The service stops with `stopSelf(lastStartId)`**, never a bare `stopSelf()`. Otherwise a Retry that starts a new job while the previous instance is still winding down can be dropped, leaving the UI at `Processing(0)`.
11. **An on-device integration test** (`integration_test/native_bridge_test.dart`) drives every channel through the real adapters. It is not part of `flutter test`. §14's "no instrumented tests" still holds for Kotlin classes.
12. **Channel adapters stay private in `src/data/`.** Tests reach them the way the app will: `registerSecurityModule(getIt)` / `registerPaymentModule(getIt)` with no overrides, then `getIt<Port>()`.
13. **`registerSecurityModule` also registers the ref-counted `SecureWindowController`** as a lazy singleton (§11).
14. **Kotlin JVM tests parse fixtures with `kotlinx-serialization-json`.** `org.json` is shadowed by `android.jar`'s stubbed copy on the unit-test classpath.

---

## Before you start

Implement on a feature branch in a worktree, as Plans 1–3 were. This document is committed on `develop` first, so the worktree has it:

```bash
git worktree add .worktrees/native-bridge -b implement/native-bridge develop
cp android/local.properties android/gradlew .worktrees/native-bridge/android/
cp android/gradle/wrapper/gradle-wrapper.jar .worktrees/native-bridge/android/gradle/wrapper/
cd .worktrees/native-bridge
~/fvm/versions/3.44.6/bin/flutter pub get
```

The three copied files are git-ignored (`android/.gitignore`), so a fresh worktree lacks them, and Gradle cannot run without them. Every path and command below is relative to the worktree root.

Confirm the baseline: `~/fvm/versions/3.44.6/bin/flutter test` ends with `+109: All tests passed!`.

**Commands used throughout** (shorthand in the steps):

| Shorthand | Command |
|---|---|
| `flutter test X` | `~/fvm/versions/3.44.6/bin/flutter test X` |
| `dart analyze` | `~/fvm/versions/3.44.6/bin/dart analyze --fatal-infos` |
| `dart format` | `~/fvm/versions/3.44.6/bin/dart format lib test integration_test` |
| `kotlin tests` | `(cd android && ./gradlew :app:testRetailDebugUnitTest --console=plain)` |
| `kotlin compile` | `(cd android && ./gradlew :app:compileRetailDebugKotlin --console=plain)` |
| `adb` | `~/Library/Android/sdk/platform-tools/adb` |

Kotlin test output (configured in Task 11) prints one `Class > test name PASSED` / `FAILED` line per test. A Kotlin compile error prints `e: file:///…/File.kt:LINE:COL message` and `BUILD FAILED`.

---

## File structure

```
contract/fixtures/                                   # new — shared by Dart and Kotlin tests
├── channels.json                                    # the six channel names
├── posture.secure.json · posture.compromised-rooted.json · posture.unverified-api34.json
├── job.running.json · job.succeeded.json · job.failed-declined.json · job.failed-timedOut.json
├── start.args.json · buildInfo.retail.json · preferHighRefreshRate.result.json

lib/
├── native_bridge/                                   # new module — Flutter channel plumbing, depends on core only
│   ├── native_bridge.dart                           # barrel
│   └── src/
│       ├── native_channels.dart                     # NativeChannels — the six names
│       ├── invoke_native.dart                       # invokeNative, nativeReplyTimeout — §9's wire → Dart table
│       └── wire_map.dart                            # WireMap — typed payload reads, TransportException on mismatch
├── bootstrap/                                       # new — composition-root adapters (used by Plan 5's bootstrap())
│   ├── channel_app_info.dart                        # BuildInfo, ChannelAppInfo
│   └── channel_display_mode.dart                    # DisplayModePreference, ChannelDisplayMode
└── features/
    ├── security_guard/
    │   ├── di.dart                                  # modified — real adapters by default + SecureWindowController
    │   └── src/data/                                # new
    │       ├── channel_secure_window.dart
    │       ├── channel_security_environment.dart
    │       └── posture_snapshot_codec.dart
    └── payment/
        ├── di.dart                                  # modified — real adapters by default
        └── src/
            ├── data/
            │   ├── channel_payment_processor.dart   # new
            │   └── job_snapshot_codec.dart          # new
            └── presentation/payment_confirmation_bloc.dart   # modified — stream errors, failing inFlight()

test/
├── support/
│   ├── contract_fixtures.dart                       # new — contractFixture(name)
│   └── fakes/fake_payment_processor.dart            # modified — pushError, inFlightError
├── native_bridge/{native_channels,wire_map,invoke_native}_test.dart          # new
├── bootstrap/{channel_app_info,channel_display_mode}_test.dart               # new
└── features/
    ├── security_guard/{channel_secure_window,channel_security_environment}_test.dart   # new
    ├── security_guard/di_test.dart                  # modified
    └── payment/{channel_payment_processor_test.dart (new), di_test.dart, payment_confirmation_bloc_test.dart}

integration_test/native_bridge_test.dart             # new — on-device, not part of `flutter test`

android/app/
├── build.gradle.kts                                 # modified — minSdk 26, flavors, buildConfig, deps, JVM test wiring
└── src/
    ├── main/
    │   ├── AndroidManifest.xml                      # modified — permissions, service, <queries>, label, appCategory
    │   ├── res/drawable/ic_stat_payment.xml         # new — notification small icon
    │   └── kotlin/dev/test/payment/
    │       ├── MainActivity.kt                      # modified — delegates to ChannelRegistry
    │       ├── bridge/
    │       │   ├── Channels.kt                      # ChannelNames, ErrorCodes, ChannelHandler
    │       │   ├── ChannelRegistry.kt
    │       │   ├── MainThread.kt                    # MainThread, AndroidMainThread
    │       │   ├── MainThreadResult.kt
    │       │   └── MainThreadSink.kt
    │       ├── security/
    │       │   ├── PostureSnapshot.kt               # AssessmentResult, UnavailableReason, PostureSnapshot
    │       │   ├── RootChecks.kt                    # RootSignal, RootAssessment, RootChecks (pure)
    │       │   ├── DeviceRootSignals.kt             # the six real signals
    │       │   ├── ScreenRecordingMonitor.kt        # API 35+ callback wrapper
    │       │   └── SecurityEnvironmentHandler.kt
    │       ├── window/
    │       │   ├── DisplayModes.kt                  # DisplayModeOption, DisplayModes (pure)
    │       │   └── WindowHandler.kt
    │       ├── payment/
    │       │   ├── JobSnapshot.kt                   # PaymentFailure, JobSnapshot
    │       │   ├── StartArgs.kt
    │       │   ├── PaymentJobStateHolder.kt
    │       │   ├── PaymentJobSimulation.kt
    │       │   ├── PaymentJobNotifications.kt       # NotificationSpec, PaymentJobNotifications (pure)
    │       │   ├── NotificationRenderer.kt
    │       │   ├── PaymentJobService.kt
    │       │   └── PaymentJobHandler.kt
    │       └── app/AppInfoHandler.kt                # BuildInfo, AppInfoHandler
    └── test/kotlin/dev/test/payment/
        ├── ContractFixtures.kt
        ├── bridge/{ChannelNamesTest, MainThreadWrappersTest}.kt
        ├── security/{PostureSnapshotTest, RootChecksTest, RootPackagesManifestTest}.kt
        ├── window/DisplayModesTest.kt
        ├── app/BuildInfoTest.kt
        └── payment/{JobSnapshotTest, StartArgsTest, PaymentJobStateHolderTest, PaymentJobSimulationTest, PaymentJobNotificationsTest}.kt

docs/architecture.md                                 # modified — Task 22 folds the decisions above back in
docs/verification/2026-09-17-native-bridge-verification.md   # new — Task 22's audit note
```

The §9 Kotlin layout gains eight files beyond the ones it names: `Channels.kt`, `MainThread.kt`, `DeviceRootSignals.kt`, `DisplayModes.kt`, and on the payment side `JobSnapshot.kt`, `StartArgs.kt`, `PaymentJobSimulation.kt`, `NotificationRenderer.kt`. Each exists so the logic next to it can be JVM-tested without Robolectric: the pure half goes in one file, and the half that touches Android goes in another.

---

## Part A — Dart side

### Task 1: Shared contract fixtures

**Files:**
- Create: the eleven files under `contract/fixtures/`

- [ ] **Step 1: Write the fixtures**

`contract/fixtures/channels.json`:
```json
{
  "securityEnvironment": "dev.test.payment/security.environment",
  "securityEnvironmentEvents": "dev.test.payment/security.environment/events",
  "window": "dev.test.payment/window",
  "paymentJob": "dev.test.payment/payment.job",
  "paymentJobEvents": "dev.test.payment/payment.job/events",
  "app": "dev.test.payment/app"
}
```

`contract/fixtures/posture.secure.json`:
```json
{
  "assessments": [
    { "kind": "rooted", "result": "clear" },
    { "kind": "screenRecording", "result": "clear" }
  ],
  "assessedAt": 1758000000000
}
```

`contract/fixtures/posture.compromised-rooted.json`:
```json
{
  "assessments": [
    { "kind": "rooted", "result": "detected" },
    { "kind": "screenRecording", "result": "clear" }
  ],
  "assessedAt": 1758000000000
}
```

`contract/fixtures/posture.unverified-api34.json`:
```json
{
  "assessments": [
    { "kind": "rooted", "result": "clear" },
    { "kind": "screenRecording", "result": "unavailable", "reason": "apiLevel" }
  ],
  "assessedAt": 1758000000000
}
```

`contract/fixtures/job.running.json`:
```json
{ "jobId": "j-1", "state": "running", "percent": 40 }
```

`contract/fixtures/job.succeeded.json`:
```json
{ "jobId": "j-1", "state": "succeeded", "reference": "PAY-DEMO-0001", "completedAt": 1758000000000 }
```

`contract/fixtures/job.failed-declined.json`:
```json
{ "jobId": "j-1", "state": "failed", "failure": "declined" }
```

`contract/fixtures/job.failed-timedOut.json`:
```json
{ "jobId": "j-1", "state": "failed", "failure": "timedOut" }
```

`contract/fixtures/start.args.json`:
```json
{ "reference": "PAY-DEMO-0001", "amountMinor": 4200, "currency": "USD", "payee": "Acme Utilities" }
```

`contract/fixtures/buildInfo.retail.json`:
```json
{ "flavor": "retail", "applicationId": "dev.test.payment.retail", "versionName": "0.1.0", "versionCode": 1, "sdkInt": 36 }
```

`contract/fixtures/preferHighRefreshRate.result.json` (the `.0` matters: Dart's `jsonDecode` and Kotlin both read it as a double):
```json
{ "refreshRate": 120.0, "modeId": 2 }
```

Keys carry no `null`s: a `clear`/`detected` assessment has no `reason` key at all, which is what both sides produce.

- [ ] **Step 2: Check every file parses**

Run: `for f in contract/fixtures/*.json; do python3 -m json.tool "$f" > /dev/null || echo "BAD $f"; done; ls contract/fixtures | wc -l`
Expected: no `BAD` lines; `11`.

- [ ] **Step 3: Commit**

```bash
git add contract
git commit -m "test(contract): add the shared channel payload fixtures"
```

---

### Task 2: `native_bridge` module — channel names and its lint walls

**Files:**
- Create: `test/support/contract_fixtures.dart`, `test/native_bridge/native_channels_test.dart`
- Create: `lib/native_bridge/native_bridge.dart` (barrel, grown in Tasks 3–4), `lib/native_bridge/src/native_channels.dart`
- Modify: `analysis_options.yaml`

- [ ] **Step 1: Write the fixture loader and the failing test**

`test/support/contract_fixtures.dart`:
```dart
import 'dart:convert';
import 'dart:io';

/// Loads `contract/fixtures/<name>.json` — the same files the Kotlin JVM tests read, so both sides
/// of the bridge are pinned to one set of payloads (docs/architecture.md §9, §14).
Map<String, Object?> contractFixture(String name) =>
    jsonDecode(File('contract/fixtures/$name.json').readAsStringSync())
        as Map<String, Object?>;
```

(`flutter test` runs with the package root as the working directory, so the relative path resolves.)

`test/native_bridge/native_channels_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/native_bridge/native_bridge.dart';

import '../support/contract_fixtures.dart';

void main() {
  test('channel names match contract/fixtures/channels.json', () {
    expect(contractFixture('channels'), {
      'securityEnvironment': NativeChannels.securityEnvironment,
      'securityEnvironmentEvents': NativeChannels.securityEnvironmentEvents,
      'window': NativeChannels.window,
      'paymentJob': NativeChannels.paymentJob,
      'paymentJobEvents': NativeChannels.paymentJobEvents,
      'app': NativeChannels.app,
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/native_bridge/native_channels_test.dart`
Expected: FAIL to compile — `Error when reading 'lib/native_bridge/native_bridge.dart': No such file or directory`.

- [ ] **Step 3: Implement**

`lib/native_bridge/src/native_channels.dart`:
```dart
/// The six channel names of docs/architecture.md §9 (ADR-0003: four method channels, two event
/// channels). Mirrors Kotlin's `ChannelNames`; both sides are pinned to
/// contract/fixtures/channels.json by a test.
abstract final class NativeChannels {
  static const _prefix = 'dev.test.payment';
  static const securityEnvironment = '$_prefix/security.environment';
  static const securityEnvironmentEvents =
      '$_prefix/security.environment/events';
  static const window = '$_prefix/window';
  static const paymentJob = '$_prefix/payment.job';
  static const paymentJobEvents = '$_prefix/payment.job/events';
  static const app = '$_prefix/app';
}
```

`lib/native_bridge/native_bridge.dart` (Tasks 3 and 4 add one line each — keep the exports alphabetical):
```dart
export 'src/native_channels.dart';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/native_bridge/native_channels_test.dart`
Expected: `+1: All tests passed!`

- [ ] **Step 5: Add the module walls to `analysis_options.yaml`**

Under `import_lint: rules:`, replace the `core_depends_on_nothing` and `engine_knows_no_features` rules with these four (the first two gain `native_bridge` in their `from` glob; the last two are new):

```yaml
    core_depends_on_nothing:
      target: "package:payment_module/core/**.dart"
      from: "package:payment_module/{brand_engine,native_bridge,features,app,brands,bootstrap}/**.dart"
      except: []
    engine_knows_no_features:
      target: "package:payment_module/brand_engine/**.dart"
      from: "package:payment_module/{native_bridge,features,app,brands,bootstrap}/**.dart"
      except: []
    native_bridge_depends_on_core_only:
      target: "package:payment_module/native_bridge/**.dart"
      from: "package:payment_module/{brand_engine,features,app,brands,bootstrap}/**.dart"
      except: []
    native_bridge_via_barrel:
      target: "package:payment_module/{features,bootstrap}/**.dart"
      from: "package:payment_module/native_bridge/src/**.dart"
      except: []
```

Leave every other rule untouched. The resulting DAG: `features/*`, `bootstrap` → `native_bridge` → `core`. Task 10 checks that both new rules fire; nothing imports `native_bridge` from a feature yet.

- [ ] **Step 6: Analyze**

Run: `dart analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add analysis_options.yaml lib/native_bridge test/support/contract_fixtures.dart test/native_bridge
git commit -m "feat(native_bridge): add NativeChannels and the module's lint walls"
```

---

### Task 3: `WireMap` — typed payload reads

**Files:**
- Create: `lib/native_bridge/src/wire_map.dart`
- Modify: `lib/native_bridge/native_bridge.dart`
- Test: `test/native_bridge/wire_map_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/exceptions.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/native_bridge/native_bridge.dart';

void main() {
  final wire = WireMap(<Object?, Object?>{
    'name': 'retail',
    'count': 3,
    'rate': 120,
    'items': [1, 2],
    'kind': 'screenRecording',
  });

  test('reads typed values', () {
    expect(wire.string('name'), 'retail');
    expect(wire.integer('count'), 3);
    expect(wire.decimal('rate'), 120.0);
    expect(wire.list('items'), [1, 2]);
    expect(
      wire.enumByName('kind', ThreatKind.values),
      ThreatKind.screenRecording,
    );
  });

  test('a payload that is not a map is a TransportException', () {
    expect(() => WireMap('nope'), throwsA(isA<TransportException>()));
    expect(() => WireMap(null), throwsA(isA<TransportException>()));
  });

  test('a missing or mistyped key is a TransportException', () {
    expect(() => wire.string('missing'), throwsA(isA<TransportException>()));
    expect(() => wire.integer('name'), throwsA(isA<TransportException>()));
  });

  test('an unknown enum name is a TransportException', () {
    expect(
      () => wire.enumByName('name', ThreatKind.values),
      throwsA(isA<TransportException>()),
    );
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/native_bridge/wire_map_test.dart`
Expected: FAIL to compile — `The function 'WireMap' isn't defined` (or `Method not found: 'WireMap'`).

- [ ] **Step 3: Implement**

`lib/native_bridge/src/wire_map.dart`:
```dart
import '../../core/exceptions.dart';

/// A decoded channel payload, read with type checks. Anything that doesn't match the contract of
/// docs/architecture.md §9 — not a map, a missing or mistyped key, an unknown enum name — throws
/// [TransportException].
final class WireMap {
  WireMap(Object? payload)
    : _map = payload is Map<Object?, Object?>
          ? payload
          : throw TransportException(
              'Expected a map payload, got ${payload.runtimeType}',
            );

  final Map<Object?, Object?> _map;

  String string(String key) => _read<String>(key);

  int integer(String key) => _read<int>(key);

  double decimal(String key) => _read<num>(key).toDouble();

  List<Object?> list(String key) => _read<List<Object?>>(key);

  /// The enum value whose `name` is the string at [key] — wire enums are lowerCamelCase names.
  T enumByName<T extends Enum>(String key, List<T> values) {
    final name = string(key);
    return values.asNameMap()[name] ??
        (throw TransportException('Unknown value "$name" for "$key"'));
  }

  T _read<T>(String key) {
    final value = _map[key];
    if (value is T) return value;
    throw TransportException(
      'Expected "$key" to be $T, got ${value.runtimeType}',
    );
  }
}
```

Every wire enum in §9 (`rooted`, `screenRecording`, `apiLevel`, `error`, `declined`, `timedOut`, `serviceUnavailable`) is spelled exactly like the Dart enum value's `name`, which is why `enumByName` needs no mapping table.

`lib/native_bridge/native_bridge.dart`:
```dart
export 'src/native_channels.dart';
export 'src/wire_map.dart';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/native_bridge/wire_map_test.dart`
Expected: `+4: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/native_bridge test/native_bridge/wire_map_test.dart
git commit -m "feat(native_bridge): add WireMap"
```

---

### Task 4: `invokeNative` — timeout and §9's error vocabulary

**Files:**
- Create: `lib/native_bridge/src/invoke_native.dart`
- Modify: `lib/native_bridge/native_bridge.dart`
- Test: `test/native_bridge/invoke_native_test.dart`

- [ ] **Step 1: Write the failing test**

The two timing tests use `testWidgets`, whose `tester.pump(duration)` advances a fake clock, so the 5 s timeout is tested without waiting 5 s.

```dart
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/exceptions.dart';
import 'package:payment_module/native_bridge/native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('test/native');

  void replyWith(Future<Object?> Function(MethodCall call) handler) =>
      messenger.setMockMethodCallHandler(channel, handler);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'passes the method and arguments through and returns the reply',
    () async {
      late MethodCall received;
      replyWith((call) async {
        received = call;
        return {'jobId': 'j-1'};
      });

      final reply = await invokeNative(channel, 'start', arguments: {'a': 1});

      expect(received.method, 'start');
      expect(received.arguments, {'a': 1});
      expect(reply, {'jobId': 'j-1'});
    },
  );

  for (final (code, type) in [
    ('noActivity', ServiceException),
    ('serviceStartFailed', ServiceException),
    ('badArguments', ClientException),
    ('alreadyRunning', ClientException),
    ('somethingNew', TransportException),
  ]) {
    test('error code $code becomes $type', () async {
      replyWith((_) async => throw PlatformException(code: code));

      await expectLater(
        invokeNative(channel, 'anything'),
        throwsA(isA<AppException>().having((e) => e.runtimeType, 'type', type)),
      );
    });
  }

  test('no native handler becomes ClientException', () async {
    await expectLater(
      invokeNative(channel, 'anything'),
      throwsA(isA<ClientException>()),
    );
  });

  testWidgets('no reply within 5 s becomes TransportException', (tester) async {
    final never = Completer<Object?>();
    replyWith((_) => never.future);

    Object? failure;
    unawaited(
      invokeNative(channel, 'anything').catchError((Object e) => failure = e),
    );
    await tester.pump(nativeReplyTimeout - const Duration(milliseconds: 1));
    expect(failure, isNull);
    await tester.pump(const Duration(milliseconds: 1));

    expect(failure, isA<TransportException>());
  });

  testWidgets('timeout: null waits for as long as the reply takes', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    replyWith((_) => pending.future);

    Object? reply;
    unawaited(
      invokeNative(channel, 'anything', timeout: null).then((r) => reply = r),
    );
    await tester.pump(const Duration(minutes: 1));
    pending.complete('granted');
    await tester.pump();

    expect(reply, 'granted');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/native_bridge/invoke_native_test.dart`
Expected: FAIL to compile — `invokeNative` and `nativeReplyTimeout` are not defined.

- [ ] **Step 3: Implement**

`lib/native_bridge/src/invoke_native.dart`:
```dart
import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/exceptions.dart';

/// How long a native method may take to reply before the call fails (docs/architecture.md §9).
const nativeReplyTimeout = Duration(seconds: 5);

/// Invokes [method] on [channel] and translates every failure into the wire → Dart table of
/// docs/architecture.md §9: `noActivity`/`serviceStartFailed` → [ServiceException];
/// `badArguments`/`alreadyRunning`/no handler → [ClientException]; any other code or no reply
/// within [timeout] → [TransportException]. Pass `timeout: null` for a call that waits on the user.
/// Returns the raw reply — decode it with [WireMap].
Future<Object?> invokeNative(
  MethodChannel channel,
  String method, {
  Object? arguments,
  Duration? timeout = nativeReplyTimeout,
}) async {
  final call = '${channel.name}#$method';
  try {
    final reply = channel.invokeMethod<Object?>(method, arguments);
    return await (timeout == null ? reply : reply.timeout(timeout));
  } on PlatformException catch (error) {
    final detail = '$call failed with ${error.code}: ${error.message}';
    throw switch (error.code) {
      'noActivity' || 'serviceStartFailed' => ServiceException(detail),
      'badArguments' || 'alreadyRunning' => ClientException(detail),
      _ => TransportException(detail),
    };
  } on MissingPluginException {
    throw ClientException('$call has no native handler');
  } on TimeoutException {
    throw TransportException('$call did not reply within $timeout');
  }
}
```

`serviceStartFailed` becomes a `ServiceException` here. §9 makes it a *value*; `ChannelPaymentProcessor` (Task 7) turns it into one, because `start` raises no other `ServiceException`.

`lib/native_bridge/native_bridge.dart`:
```dart
export 'src/invoke_native.dart';
export 'src/native_channels.dart';
export 'src/wire_map.dart';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/native_bridge`
Expected: `+14: All tests passed!` (1 + 4 + 9)

- [ ] **Step 5: Commit**

```bash
git add lib/native_bridge test/native_bridge/invoke_native_test.dart
git commit -m "feat(native_bridge): add invokeNative with the reply timeout and error mapping"
```

---

### Task 5: `ChannelSecureWindow` and its registration

**Files:**
- Create: `lib/features/security_guard/src/data/channel_secure_window.dart`
- Modify: `lib/features/security_guard/di.dart`
- Test: `test/features/security_guard/channel_secure_window_test.dart`, `test/features/security_guard/di_test.dart`

- [ ] **Step 1: Write the failing tests**

`test/features/security_guard/channel_secure_window_test.dart`:
```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:payment_module/core/exceptions.dart';
import 'package:payment_module/features/security_guard/di.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';
import 'package:payment_module/native_bridge/native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(NativeChannels.window);

  late GetIt getIt;
  late List<MethodCall> calls;

  setUp(() {
    getIt = GetIt.asNewInstance();
    registerSecurityModule(getIt); // no overrides: the real channel adapter
    calls = [];
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    return getIt.reset();
  });

  void nativeReplies(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  test('setSecure sends {secure} on the window channel', () async {
    nativeReplies((_) async => null);

    await getIt<SecureWindow>().setSecure(true);
    await getIt<SecureWindow>().setSecure(false);

    expect(calls.map((c) => c.method), ['setSecure', 'setSecure']);
    expect(calls.map((c) => c.arguments), [
      {'secure': true},
      {'secure': false},
    ]);
  });

  test('noActivity is a ServiceException', () async {
    nativeReplies((_) async => throw PlatformException(code: 'noActivity'));

    await expectLater(
      getIt<SecureWindow>().setSecure(true),
      throwsA(isA<ServiceException>()),
    );
  });

  test(
    'through the registered controller, noActivity is swallowed and resume re-asserts',
    () async {
      var attached = false;
      nativeReplies((_) async {
        if (!attached) throw PlatformException(code: 'noActivity');
        return null;
      });
      final controller = getIt<SecureWindowController>();

      await controller.acquire();
      attached = true;
      await controller.onResumed();

      expect(calls.map((c) => c.arguments), [
        {'secure': true},
        {'secure': true},
      ]);
    },
  );
}
```

(Compare `method` and `arguments` separately. A record like `(c.method, c.arguments)` compares its map field by identity, not by content, so that assertion would always fail.)

In `test/features/security_guard/di_test.dart`, add this test after the existing one, inside `main()`:
```dart
  test(
    'registers one SecureWindowController, over the registered SecureWindow',
    () async {
      final window = FakeSecureWindow();
      registerSecurityModule(
        getIt,
        environment: FakeSecurityEnvironment(),
        window: window,
      );

      final controller = getIt<SecureWindowController>();
      await controller.acquire();

      expect(getIt<SecureWindowController>(), same(controller));
      expect(window.calls, [true]);
    },
  );
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/security_guard/channel_secure_window_test.dart test/features/security_guard/di_test.dart`
Expected: FAIL — `Bad state: GetIt: Object/factory with type SecureWindow is not registered inside GetIt` (and the same for `SecureWindowController`). The existing di test still passes.

- [ ] **Step 3: Implement**

`lib/features/security_guard/src/data/channel_secure_window.dart`:
```dart
import 'package:flutter/services.dart';

import '../../../../native_bridge/native_bridge.dart';
import '../domain/secure_window.dart';

/// [SecureWindow] over `window` (docs/architecture.md §9, §11). `noActivity` surfaces as a
/// transient `ServiceException`, which `SecureWindowController` swallows and retries on resume.
class ChannelSecureWindow implements SecureWindow {
  static const _channel = MethodChannel(NativeChannels.window);

  @override
  Future<void> setSecure(bool secure) async {
    await invokeNative(_channel, 'setSecure', arguments: {'secure': secure});
  }
}
```

`lib/features/security_guard/di.dart` — replace the whole file. The environment keeps its old "only if given" registration until Task 6 adds its channel adapter:
```dart
import 'package:get_it/get_it.dart';

import 'security_guard.dart';
import 'src/data/channel_secure_window.dart';

/// Registers `security_guard`'s ports — the channel adapter unless [window] overrides it (tests
/// pass fakes) — and the ref-counted [SecureWindowController] every secure route shares. All lazy
/// singletons (docs/architecture.md §4, §11). [environment] is only registered when given until
/// its channel adapter exists.
void registerSecurityModule(
  GetIt getIt, {
  SecurityEnvironment? environment,
  SecureWindow? window,
}) {
  if (environment != null) {
    getIt.registerSingleton<SecurityEnvironment>(environment);
  }
  getIt
    ..registerLazySingleton<SecureWindow>(() => window ?? ChannelSecureWindow())
    ..registerLazySingleton<SecureWindowController>(
      () => SecureWindowController(getIt<SecureWindow>()),
    );
}
```

`di.dart` sits at the feature root, not in `presentation/`, so importing `src/data/` is allowed (`presentation_no_data` targets only `src/presentation/**`).

- [ ] **Step 4: Run them to verify they pass**

Run: `flutter test test/features/security_guard/channel_secure_window_test.dart test/features/security_guard/di_test.dart`
Expected: `+5: All tests passed!`

- [ ] **Step 5: Analyze and commit**

Run: `dart analyze` — Expected: `No issues found!`

```bash
git add lib/features/security_guard test/features/security_guard
git commit -m "feat(security_guard): add ChannelSecureWindow; register it and SecureWindowController by default"
```

---

### Task 6: `ChannelSecurityEnvironment` and `PostureSnapshotCodec`

**Files:**
- Create: `lib/features/security_guard/src/data/posture_snapshot_codec.dart`, `lib/features/security_guard/src/data/channel_security_environment.dart`
- Modify: `lib/features/security_guard/di.dart`
- Test: `test/features/security_guard/channel_security_environment_test.dart`

- [ ] **Step 1: Write the failing test**

`MockStreamHandler.inline` plays the Kotlin side of an `EventChannel`: `onListen` runs when the Dart stream gets its first listener, `onCancel` when the last one leaves.

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:payment_module/core/exceptions.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/security_guard/di.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';
import 'package:payment_module/native_bridge/native_bridge.dart';

import '../../support/contract_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methods = MethodChannel(NativeChannels.securityEnvironment);
  const events = EventChannel(NativeChannels.securityEnvironmentEvents);

  late GetIt getIt;
  late SecurityEnvironment environment;

  setUp(() {
    getIt = GetIt.asNewInstance();
    registerSecurityModule(getIt); // no overrides: the real channel adapter
    environment = getIt<SecurityEnvironment>();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockStreamHandler(events, null);
    return getIt.reset();
  });

  void nativeEmits(List<Object?> payloads, {void Function()? onCancel}) {
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (_, sink) => payloads.forEach(sink.success),
        onCancel: (_) => onCancel?.call(),
      ),
    );
  }

  group('assess', () {
    test('invokes assess on the security.environment channel', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(methods, (call) async {
        calls.add(call);
        return null;
      });

      await environment.assess();

      expect(calls.single.method, 'assess');
    });

    test('with no native handler is a ClientException', () async {
      await expectLater(environment.assess(), throwsA(isA<ClientException>()));
    });
  });

  group('posture', () {
    for (final (fixture, expected) in [
      (
        'posture.secure',
        SecurityPosture(const [
          ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
          ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
        ]),
      ),
      (
        'posture.compromised-rooted',
        SecurityPosture(const [
          ThreatAssessment(kind: ThreatKind.rooted, result: Detected()),
          ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
        ]),
      ),
      (
        'posture.unverified-api34',
        SecurityPosture(const [
          ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
          ThreatAssessment(
            kind: ThreatKind.screenRecording,
            result: Unavailable(UnavailableReason.apiLevel),
          ),
        ]),
      ),
    ]) {
      test('decodes $fixture', () async {
        nativeEmits([contractFixture(fixture)]);

        expect(await environment.posture.first, expected);
      });
    }

    test('an unknown assessment result is a TransportException', () async {
      nativeEmits([
        {
          'assessments': [
            {'kind': 'rooted', 'result': 'maybe'},
            {'kind': 'screenRecording', 'result': 'clear'},
          ],
          'assessedAt': 1758000000000,
        },
      ]);

      await expectLater(
        environment.posture.first,
        throwsA(isA<TransportException>()),
      );
    });

    test('a snapshot missing a ThreatKind is a TransportException', () async {
      nativeEmits([
        {
          'assessments': [
            {'kind': 'rooted', 'result': 'clear'},
          ],
          'assessedAt': 1758000000000,
        },
      ]);

      await expectLater(
        environment.posture.first,
        throwsA(isA<TransportException>()),
      );
    });

    test('the last listener cancelling cancels the native stream', () async {
      var cancelled = false;
      nativeEmits([
        contractFixture('posture.secure'),
      ], onCancel: () => cancelled = true);

      await environment.posture.first;
      await Future<void>.delayed(Duration.zero);

      expect(cancelled, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/features/security_guard/channel_security_environment_test.dart`
Expected: FAIL — every test errors in `setUp` with `Bad state: GetIt: Object/factory with type SecurityEnvironment is not registered inside GetIt`.

- [ ] **Step 3: Implement the codec**

`lib/features/security_guard/src/data/posture_snapshot_codec.dart`:
```dart
import '../../../../core/exceptions.dart';
import '../../../../core/threat.dart';
import '../../../../native_bridge/native_bridge.dart';
import '../domain/security_posture.dart';
import '../domain/threat_assessment.dart';

/// Decodes one `security.environment/events` payload (docs/architecture.md §9) into a
/// [SecurityPosture]. `assessedAt` is on the wire for diagnostics only; the domain doesn't carry it.
SecurityPosture decodePostureSnapshot(Object? payload) {
  final assessments = [
    for (final item in WireMap(payload).list('assessments'))
      _decodeAssessment(WireMap(item)),
  ];
  // SecurityPosture only asserts this in debug builds; a release build must not accept it either.
  final kinds = assessments.map((a) => a.kind).toSet();
  if (kinds.length != assessments.length ||
      kinds.length != ThreatKind.values.length) {
    throw TransportException(
      'Expected one assessment per ThreatKind, got ${assessments.map((a) => a.kind).toList()}',
    );
  }
  return SecurityPosture(assessments);
}

ThreatAssessment _decodeAssessment(WireMap wire) => ThreatAssessment(
  kind: wire.enumByName('kind', ThreatKind.values),
  result: switch (wire.string('result')) {
    'detected' => const Detected(),
    'clear' => const Clear(),
    'unavailable' => Unavailable(
      wire.enumByName('reason', UnavailableReason.values),
    ),
    final other => throw TransportException(
      'Unknown assessment result "$other"',
    ),
  },
);
```

- [ ] **Step 4: Implement the adapter**

`lib/features/security_guard/src/data/channel_security_environment.dart`:
```dart
import 'package:flutter/services.dart';

import '../../../../native_bridge/native_bridge.dart';
import '../domain/security_environment.dart';
import '../domain/security_posture.dart';
import 'posture_snapshot_codec.dart';

/// [SecurityEnvironment] over `security.environment` (docs/architecture.md §8, §9). [posture] is
/// one shared broadcast stream: the native side registers its API 35+ recorder callback while it
/// has a listener and replays the latest snapshot to each new one. A malformed snapshot arrives as
/// a [TransportException] stream error.
class ChannelSecurityEnvironment implements SecurityEnvironment {
  static const _methods = MethodChannel(NativeChannels.securityEnvironment);
  static const _events = EventChannel(NativeChannels.securityEnvironmentEvents);

  @override
  late final Stream<SecurityPosture> posture = _events
      .receiveBroadcastStream()
      .map(decodePostureSnapshot);

  @override
  Future<void> assess() async {
    await invokeNative(_methods, 'assess');
  }
}
```

One cached stream per adapter matters. Flutter's `EventChannel` allows one platform-side listener per channel, and a second `receiveBroadcastStream()` listen would cancel the first on the Kotlin side.

- [ ] **Step 5: Register it by default**

`lib/features/security_guard/di.dart` — replace the whole file:
```dart
import 'package:get_it/get_it.dart';

import 'security_guard.dart';
import 'src/data/channel_secure_window.dart';
import 'src/data/channel_security_environment.dart';

/// Registers `security_guard`'s ports — the channel adapters unless [environment]/[window]
/// override them (tests pass fakes) — and the ref-counted [SecureWindowController] every secure
/// route shares. All lazy singletons (docs/architecture.md §4, §11).
void registerSecurityModule(
  GetIt getIt, {
  SecurityEnvironment? environment,
  SecureWindow? window,
}) {
  getIt
    ..registerLazySingleton<SecurityEnvironment>(
      () => environment ?? ChannelSecurityEnvironment(),
    )
    ..registerLazySingleton<SecureWindow>(() => window ?? ChannelSecureWindow())
    ..registerLazySingleton<SecureWindowController>(
      () => SecureWindowController(getIt<SecureWindow>()),
    );
}
```

- [ ] **Step 6: Run the security_guard tests**

Run: `flutter test test/features/security_guard`
Expected: `All tests passed!`. The new file contributes 8 tests; the existing di test still passes, since the lazy singleton returns the given fake.

- [ ] **Step 7: Analyze and commit**

Run: `dart analyze` — Expected: `No issues found!`

```bash
git add lib/features/security_guard test/features/security_guard/channel_security_environment_test.dart
git commit -m "feat(security_guard): add ChannelSecurityEnvironment and PostureSnapshotCodec"
```

---

### Task 7: `ChannelPaymentProcessor`, `JobSnapshotCodec` and their registration

**Files:**
- Create: `lib/features/payment/src/data/job_snapshot_codec.dart`, `lib/features/payment/src/data/channel_payment_processor.dart`
- Modify: `lib/features/payment/di.dart`
- Test: `test/features/payment/channel_payment_processor_test.dart`, `test/features/payment/di_test.dart`

- [ ] **Step 1: Write the failing tests**

`test/features/payment/channel_payment_processor_test.dart`:
```dart
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:payment_module/core/exceptions.dart';
import 'package:payment_module/core/money.dart';
import 'package:payment_module/features/payment/di.dart';
import 'package:payment_module/features/payment/payment.dart';
import 'package:payment_module/native_bridge/native_bridge.dart';

import '../../support/contract_fixtures.dart';

/// Matches contract/fixtures/start.args.json.
const fixturePayment = Payment(
  reference: 'PAY-DEMO-0001',
  amount: Money(amountMinor: 4200, currency: 'USD'),
  payee: 'Acme Utilities',
  lineItems: [],
);

final fixtureReceipt = PaymentReceipt(
  reference: 'PAY-DEMO-0001',
  completedAt: DateTime.fromMillisecondsSinceEpoch(1758000000000, isUtc: true),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methods = MethodChannel(NativeChannels.paymentJob);
  const events = EventChannel(NativeChannels.paymentJobEvents);

  late GetIt getIt;
  late PaymentProcessor processor;
  late List<MethodCall> calls;
  late int listens;

  setUp(() {
    getIt = GetIt.asNewInstance();
    registerPaymentModule(getIt); // no overrides: the real channel adapter
    processor = getIt<PaymentProcessor>();
    calls = [];
    listens = 0;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockStreamHandler(events, null);
    return getIt.reset();
  });

  /// Scripts `payment.job`: each method name maps to its reply (or a thrown PlatformException).
  void nativeReplies(Map<String, FutureOr<Object?> Function()> replies) {
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      return replies[call.method]!();
    });
  }

  void nativeEmits(List<Object?> payloads) {
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (_, sink) {
          listens++;
          payloads.forEach(sink.success);
        },
      ),
    );
  }

  Map<String, Object?> otherJob() => {
    'jobId': 'j-other',
    'state': 'running',
    'percent': 90,
  };

  group('start', () {
    test('asks for notification permission, starts the job with the payment, '
        "and follows only that job's snapshots to its terminal one", () async {
      nativeReplies({
        'ensureNotificationPermission': () => 'granted',
        'start': () => {'jobId': 'j-1'},
      });
      nativeEmits([
        contractFixture('job.running'),
        otherJob(),
        contractFixture('job.succeeded'),
        contractFixture('job.running'), // after the terminal one: never read
      ]);

      final progress = await processor.start(fixturePayment).toList();

      expect(calls.map((c) => c.method), [
        'ensureNotificationPermission',
        'start',
      ]);
      expect(calls.last.arguments, contractFixture('start.args'));
      expect(progress, [const Running(40), Succeeded(fixtureReceipt)]);
    });

    test('a failed permission request never gates the job', () async {
      nativeReplies({
        'ensureNotificationPermission': () =>
            throw PlatformException(code: 'noActivity'),
        'start': () => {'jobId': 'j-1'},
      });
      nativeEmits([contractFixture('job.failed-declined')]);

      final progress = await processor.start(fixturePayment).toList();

      expect(progress, [const Failed(PaymentFailure.declined)]);
    });

    testWidgets(
      'waits on the permission prompt for as long as the user takes',
      (tester) async {
        final answer = Completer<Object?>();
        nativeReplies({
          'ensureNotificationPermission': () => answer.future,
          'start': () => {'jobId': 'j-1'},
        });
        nativeEmits([contractFixture('job.succeeded')]);

        final progress = <PaymentJobProgress>[];
        processor.start(fixturePayment).listen(progress.add);
        await tester.pump(const Duration(minutes: 1));
        expect(calls.map((c) => c.method), ['ensureNotificationPermission']);

        answer.complete('denied');
        for (var i = 0; i < 5; i++) {
          await tester.pump();
        }

        expect(calls.map((c) => c.method).last, 'start');
        expect(progress, [Succeeded(fixtureReceipt)]);
      },
    );

    test(
      'serviceStartFailed is the value Failed(serviceUnavailable)',
      () async {
        nativeReplies({
          'ensureNotificationPermission': () => 'granted',
          'start': () => throw PlatformException(code: 'serviceStartFailed'),
        });

        final progress = await processor.start(fixturePayment).toList();

        expect(progress, [const Failed(PaymentFailure.serviceUnavailable)]);
        expect(listens, 0);
      },
    );

    test('alreadyRunning is a ClientException on the stream', () async {
      nativeReplies({
        'ensureNotificationPermission': () => 'granted',
        'start': () => throw PlatformException(code: 'alreadyRunning'),
      });

      await expectLater(
        processor.start(fixturePayment).toList(),
        throwsA(isA<ClientException>()),
      );
    });

    test(
      "a malformed snapshot is a TransportException on the job's stream",
      () async {
        nativeReplies({
          'ensureNotificationPermission': () => 'granted',
          'start': () => {'jobId': 'j-1'},
        });
        nativeEmits([
          {'jobId': 'j-1', 'state': 'failed', 'failure': 'lostInTheMail'},
        ]);

        await expectLater(
          processor.start(fixturePayment).toList(),
          throwsA(isA<TransportException>()),
        );
      },
    );
  });

  group('inFlight', () {
    test('no job is null', () async {
      nativeReplies({'current': () => null});

      expect(await processor.inFlight(), isNull);
    });

    test(
      'a running job is its stream, from the replayed snapshot to the terminal one',
      () async {
        nativeReplies({'current': () => contractFixture('job.running')});
        nativeEmits([
          contractFixture('job.running'),
          contractFixture('job.failed-declined'),
        ]);

        final stream = await processor.inFlight();

        expect(await stream!.toList(), [
          const Running(40),
          const Failed(PaymentFailure.declined),
        ]);
      },
    );

    test('a terminal job is just its outcome, without subscribing', () async {
      nativeReplies({'current': () => contractFixture('job.failed-timedOut')});
      nativeEmits([]);

      final stream = await processor.inFlight();

      expect(await stream!.toList(), [const Failed(PaymentFailure.timedOut)]);
      expect(listens, 0);
    });

    test('an unknown state is a TransportException', () async {
      nativeReplies({
        'current': () => {'jobId': 'j-1', 'state': 'paused'},
      });

      await expectLater(
        processor.inFlight(),
        throwsA(isA<TransportException>()),
      );
    });
  });
}
```

The permission test does not `await` the job stream. Inside `testWidgets`, a future that needs the fake clock to advance never completes by itself, so the test pumps and then checks what was collected.

In `test/features/payment/di_test.dart`, add this test after the existing one, inside `main()`:
```dart
  test('without overrides, the repository is the in-memory demo', () {
    registerPaymentModule(getIt);

    expect(getIt<PaymentRepository>(), isA<InMemoryPaymentRepository>());
    expect(getIt<PaymentRepository>(), same(getIt<PaymentRepository>()));
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/payment/channel_payment_processor_test.dart test/features/payment/di_test.dart`
Expected: FAIL — `Bad state: GetIt: Object/factory with type PaymentProcessor is not registered inside GetIt` (and `PaymentRepository` for the di test).

- [ ] **Step 3: Implement the codec**

`lib/features/payment/src/data/job_snapshot_codec.dart`:
```dart
import '../../../../core/exceptions.dart';
import '../../../../native_bridge/native_bridge.dart';
import '../domain/payment.dart';
import '../domain/payment_job_progress.dart';

/// One decoded `payment.job/events` payload (docs/architecture.md §9): which job, and how far.
class JobSnapshot {
  const JobSnapshot(this.jobId, this.progress);

  final String jobId;
  final PaymentJobProgress progress;
}

JobSnapshot decodeJobSnapshot(Object? payload) {
  final wire = WireMap(payload);
  final jobId = wire.string('jobId');
  return switch (wire.string('state')) {
    'running' => JobSnapshot(jobId, Running(wire.integer('percent'))),
    'succeeded' => JobSnapshot(
      jobId,
      Succeeded(
        PaymentReceipt(
          reference: wire.string('reference'),
          completedAt: DateTime.fromMillisecondsSinceEpoch(
            wire.integer('completedAt'),
            isUtc: true,
          ),
        ),
      ),
    ),
    'failed' => JobSnapshot(
      jobId,
      Failed(wire.enumByName('failure', PaymentFailure.values)),
    ),
    final other => throw TransportException('Unknown job state "$other"'),
  };
}

/// The `start` arguments (docs/architecture.md §9).
Map<String, Object?> encodeStartArgs(Payment payment) => {
  'reference': payment.reference,
  'amountMinor': payment.amount.amountMinor,
  'currency': payment.amount.currency,
  'payee': payment.payee,
};
```

- [ ] **Step 4: Implement the adapter**

`lib/features/payment/src/data/channel_payment_processor.dart`:
```dart
import 'dart:developer';

import 'package:flutter/services.dart';

import '../../../../core/exceptions.dart';
import '../../../../native_bridge/native_bridge.dart';
import '../domain/payment.dart';
import '../domain/payment_job_progress.dart';
import '../domain/payment_processor.dart';
import 'job_snapshot_codec.dart';

/// [PaymentProcessor] over `payment.job` (docs/architecture.md §9, §10). A job's progress is the
/// shared, replay-1 event stream filtered to its `jobId`, completing after the first terminal
/// snapshot. Failures before the job exists arrive as stream errors — except `serviceStartFailed`,
/// which is an expected outcome and arrives as the value `Failed(serviceUnavailable)`.
class ChannelPaymentProcessor implements PaymentProcessor {
  static const _methods = MethodChannel(NativeChannels.paymentJob);
  static const _eventChannel = EventChannel(NativeChannels.paymentJobEvents);

  late final Stream<Object?> _events = _eventChannel.receiveBroadcastStream();

  @override
  Stream<PaymentJobProgress> start(Payment payment) async* {
    await _ensureNotificationPermission();
    final String jobId;
    try {
      final reply = await invokeNative(
        _methods,
        'start',
        arguments: encodeStartArgs(payment),
      );
      jobId = WireMap(reply).string('jobId');
    } on ServiceException {
      // `start`'s only ServiceException is serviceStartFailed (§9).
      yield const Failed(PaymentFailure.serviceUnavailable);
      return;
    }
    yield* _progressOf(jobId);
  }

  @override
  Future<Stream<PaymentJobProgress>?> inFlight() async {
    final reply = await invokeNative(_methods, 'current');
    if (reply == null) return null;
    final snapshot = decodeJobSnapshot(reply);
    return switch (snapshot.progress) {
      Running() => _progressOf(snapshot.jobId),
      final terminal => Stream.value(terminal),
    };
  }

  /// Asks for POST_NOTIFICATIONS without a timeout — it waits on the user — and never gates the
  /// job: the outcome, or a failure to ask, is only logged (§10).
  Future<void> _ensureNotificationPermission() async {
    try {
      final outcome = await invokeNative(
        _methods,
        'ensureNotificationPermission',
        timeout: null,
      );
      log('POST_NOTIFICATIONS: $outcome', name: 'payment.job');
    } on AppException catch (error) {
      log('POST_NOTIFICATIONS not requested: $error', name: 'payment.job');
    }
  }

  Stream<PaymentJobProgress> _progressOf(String jobId) async* {
    await for (final payload in _events) {
      final snapshot = decodeJobSnapshot(payload);
      if (snapshot.jobId != jobId) continue;
      yield snapshot.progress;
      if (snapshot.progress is! Running) return;
    }
  }
}
```

Leaving `_progressOf` (on `return`, or when the listener cancels) cancels the events subscription, and with it the Kotlin collector. A decode error ends the per-job stream with that error, which Task 8 turns into `Completed(Failed(serviceUnavailable))`.

- [ ] **Step 5: Register both ports by default**

`lib/features/payment/di.dart` — replace the whole file:
```dart
import 'package:get_it/get_it.dart';

import 'payment.dart';
import 'src/data/channel_payment_processor.dart';

/// Registers `payment`'s ports as lazy singletons: the in-memory demo repository and the channel
/// processor, unless [repository]/[processor] override them (tests pass fakes). See
/// docs/architecture.md §4.
void registerPaymentModule(
  GetIt getIt, {
  PaymentRepository? repository,
  PaymentProcessor? processor,
}) {
  getIt
    ..registerLazySingleton<PaymentRepository>(
      () => repository ?? InMemoryPaymentRepository(),
    )
    ..registerLazySingleton<PaymentProcessor>(
      () => processor ?? ChannelPaymentProcessor(),
    );
}
```

- [ ] **Step 6: Run them to verify they pass**

Run: `flutter test test/features/payment/channel_payment_processor_test.dart test/features/payment/di_test.dart`
Expected: `+12: All tests passed!` (10 + 2)

- [ ] **Step 7: Analyze and commit**

Run: `dart analyze` — Expected: `No issues found!`

```bash
git add lib/features/payment test/features/payment/channel_payment_processor_test.dart test/features/payment/di_test.dart
git commit -m "feat(payment): add ChannelPaymentProcessor and JobSnapshotCodec; register real adapters by default"
```

---

### Task 8: Harden `PaymentConfirmationBloc` for the real processor

The fake processor throws from `start()` synchronously. `ChannelPaymentProcessor.start()` is an `async*` stream, so the same failures (`alreadyRunning`, a timeout, a malformed snapshot) reach the bloc as *stream errors*, which `_listenToJob` does not handle today. The flow would then stay in `Processing(0)` forever. The same applies to `inFlight()`, whose `current()` call can time out.

**Files:**
- Modify: `test/support/fakes/fake_payment_processor.dart`, `test/features/payment/payment_confirmation_bloc_test.dart`, `lib/features/payment/src/presentation/payment_confirmation_bloc.dart`

- [ ] **Step 1: Let the fake fail asynchronously**

In `test/support/fakes/fake_payment_processor.dart`:

Replace the first three lines of the class doc comment:
```dart
/// A scripted [PaymentProcessor] for tests. Push progress for a started job via [pushProgress];
/// set [inFlightStream] before `start()`/`inFlight()` is called to script a re-attach scenario;
/// set [startError] to make the next `start()` throw once (then reset itself); call
```
with:
```dart
/// A scripted [PaymentProcessor] for tests. Push progress for a started job via [pushProgress], or
/// fail its stream via [pushError]; set [inFlightStream] before `start()`/`inFlight()` is called
/// to script a re-attach scenario, or [inFlightError] to make `inFlight()` fail instead;
/// set [startError] to make the next `start()` throw once (then reset itself); call
```

After the field `Stream<PaymentJobProgress>? inFlightStream;` add:
```dart
  Object? inFlightError;
```

After `void pushProgress(PaymentJobProgress progress) => _controller.add(progress);` add:
```dart

  void pushError(Object error) => _controller.addError(error);
```

Replace the body of `inFlight()`:
```dart
    final held = _heldInFlight;
    return held != null ? held.future : Future.value(inFlightStream);
```
with:
```dart
    final held = _heldInFlight;
    if (held != null) return held.future;
    final error = inFlightError;
    return error != null ? Future.error(error) : Future.value(inFlightStream);
```

- [ ] **Step 2: Write the two failing bloc tests**

In `test/features/payment/payment_confirmation_bloc_test.dart` (which already imports `package:payment_module/core/exceptions.dart`):

At the end of `group('Started — cold entry', ...)`, after the `'in-flight job already failed: goes straight to Completed'` test, add:
```dart
    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'in-flight query failing is treated as no in-flight job: loads the payment and scans',
      build: () {
        processor.inFlightError = const TransportException('no reply in 5 s');
        repository.completeWith(testPayment);
        return buildBloc();
      },
      act: (bloc) => bloc.add(const Started()),
      expect: () => [
        const PaymentConfirmationState(payment: testPayment, phase: Scanning()),
      ],
    );
```

At the end of `group('Processing', ...)`, after the `'processor.start() throwing moves Processing straight to Completed(Failed(serviceUnavailable))'` test, add:
```dart
    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'the job stream failing moves Processing to Completed(Failed(serviceUnavailable))',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(
        payment: testPayment,
        phase: AwaitingConfirmation(),
      ),
      act: (bloc) async {
        bloc.add(const PayPressed(unblockedVerdict));
        await Future<void>.delayed(Duration.zero);
        processor.pushError(const TransportException('malformed snapshot'));
      },
      expect: () => [
        const PaymentConfirmationState(
          payment: testPayment,
          phase: Processing(0),
        ),
        const PaymentConfirmationState(
          payment: testPayment,
          phase: Completed(Failed(PaymentFailure.serviceUnavailable)),
        ),
      ],
    );
```

- [ ] **Step 3: Run them to verify they fail**

Run: `flutter test test/features/payment/payment_confirmation_bloc_test.dart`
Expected: `Some tests failed.` — exactly the two new tests, reporting `TransportException: no reply in 5 s` and `TransportException: malformed snapshot` as uncaught.

- [ ] **Step 4: Implement**

In `lib/features/payment/src/presentation/payment_confirmation_bloc.dart`:

Add the import after `import 'package:flutter_bloc/flutter_bloc.dart';` (blank line between package and relative imports, as the file already has):
```dart
import '../../../../core/exceptions.dart';
```

In `_onStarted`, replace:
```dart
    final inFlight = await _processor.inFlight();
```
with:
```dart
    final inFlight = await _inFlightOrNull();
```

Replace the whole `_listenToJob` method with these two methods:
```dart
  /// A failed in-flight query (no reply, malformed reply) is treated as "no job": starting fresh
  /// is safe, because the processor refuses a second job, which surfaces as a retryable failure.
  Future<Stream<PaymentJobProgress>?> _inFlightOrNull() async {
    try {
      return await _processor.inFlight();
    } on AppException {
      return null;
    }
  }

  Future<void> _listenToJob(Stream<PaymentJobProgress> stream) async {
    await _jobSubscription?.cancel();
    // Guards both call sites (the re-attach path in _onStarted and the fresh-start path in
    // _onPayPressed): if close() ran while we were suspended on the cancel() above, don't create
    // a new subscription that would outlive close() and call add() on a closed bloc.
    if (isClosed) return;
    _jobSubscription = stream.listen(
      (progress) => add(JobProgressed(progress)),
      // The port returns a Stream, so it can also fail through the stream (the channel adapter
      // starts the job asynchronously). Same rule as a synchronous throw: exception → value (§7.1).
      onError: (Object _) =>
          add(const JobProgressed(Failed(PaymentFailure.serviceUnavailable))),
      cancelOnError: true,
    );
  }
```

- [ ] **Step 5: Run the payment tests**

Run: `flutter test test/features/payment`
Expected: `All tests passed!`, with the bloc test file now at 25 tests.

- [ ] **Step 6: Analyze, format and commit**

Run: `dart analyze` — Expected: `No issues found!`
Run: `dart format` — then `git diff --stat` shows only the files this task touched.

```bash
git add lib/features/payment test/support/fakes/fake_payment_processor.dart test/features/payment/payment_confirmation_bloc_test.dart
git commit -m "fix(payment): turn job-stream errors and a failing inFlight() into values in PaymentConfirmationBloc"
```

---

### Task 9: Bootstrap adapters — `ChannelAppInfo` and `ChannelDisplayMode`

Composition-root infrastructure (§4, §12.2). Plan 5's `bootstrap()` calls them; this plan builds and contract-tests them.

**Files:**
- Create: `lib/bootstrap/channel_app_info.dart`, `lib/bootstrap/channel_display_mode.dart`
- Test: `test/bootstrap/channel_app_info_test.dart`, `test/bootstrap/channel_display_mode_test.dart`

- [ ] **Step 1: Write the failing tests**

`test/bootstrap/channel_app_info_test.dart`:
```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/bootstrap/channel_app_info.dart';
import 'package:payment_module/core/exceptions.dart';
import 'package:payment_module/native_bridge/native_bridge.dart';

import '../support/contract_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(NativeChannels.app);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('decodes buildInfo.retail', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'buildInfo');
      return contractFixture('buildInfo.retail');
    });

    expect(
      await ChannelAppInfo().buildInfo(),
      const BuildInfo(
        flavor: 'retail',
        applicationId: 'dev.test.payment.retail',
        versionName: '0.1.0',
        versionCode: 1,
        sdkInt: 36,
      ),
    );
  });

  test('a mistyped field is a TransportException', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {...contractFixture('buildInfo.retail'), 'versionCode': '1'},
    );

    await expectLater(
      ChannelAppInfo().buildInfo(),
      throwsA(isA<TransportException>()),
    );
  });
}
```

`test/bootstrap/channel_display_mode_test.dart`:
```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/bootstrap/channel_display_mode.dart';
import 'package:payment_module/core/exceptions.dart';
import 'package:payment_module/native_bridge/native_bridge.dart';

import '../support/contract_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(NativeChannels.window);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void nativeReplies(Future<Object?> Function(MethodCall call) handler) =>
      messenger.setMockMethodCallHandler(channel, handler);

  test('decodes preferHighRefreshRate.result', () async {
    nativeReplies((call) async {
      expect(call.method, 'preferHighRefreshRate');
      return contractFixture('preferHighRefreshRate.result');
    });

    expect(
      await ChannelDisplayMode().preferHighRefreshRate(),
      const DisplayModePreference(refreshRate: 120, modeId: 2),
    );
  });

  test('no mode to prefer is null', () async {
    nativeReplies((_) async => null);

    expect(await ChannelDisplayMode().preferHighRefreshRate(), isNull);
  });

  test('noActivity is a ServiceException', () async {
    nativeReplies((_) async => throw PlatformException(code: 'noActivity'));

    await expectLater(
      ChannelDisplayMode().preferHighRefreshRate(),
      throwsA(isA<ServiceException>()),
    );
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/bootstrap`
Expected: FAIL to compile — `Error when reading 'lib/bootstrap/channel_app_info.dart': No such file or directory` (and the same for `channel_display_mode.dart`).

- [ ] **Step 3: Implement**

`lib/bootstrap/channel_app_info.dart`:
```dart
import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';

import '../native_bridge/native_bridge.dart';

/// What the native build is: the `app · buildInfo` reply (docs/architecture.md §9). The bootstrap
/// asserts [flavor] equals its `BRAND` dart-define in debug builds (§6).
class BuildInfo extends Equatable {
  const BuildInfo({
    required this.flavor,
    required this.applicationId,
    required this.versionName,
    required this.versionCode,
    required this.sdkInt,
  });

  final String flavor;
  final String applicationId;
  final String versionName;
  final int versionCode;
  final int sdkInt;

  @override
  List<Object?> get props => [
    flavor,
    applicationId,
    versionName,
    versionCode,
    sdkInt,
  ];
}

/// Reads [BuildInfo] over `app`. Composition-root infrastructure, not a domain port.
class ChannelAppInfo {
  static const _channel = MethodChannel(NativeChannels.app);

  Future<BuildInfo> buildInfo() async {
    final wire = WireMap(await invokeNative(_channel, 'buildInfo'));
    return BuildInfo(
      flavor: wire.string('flavor'),
      applicationId: wire.string('applicationId'),
      versionName: wire.string('versionName'),
      versionCode: wire.integer('versionCode'),
      sdkInt: wire.integer('sdkInt'),
    );
  }
}
```

`lib/bootstrap/channel_display_mode.dart`:
```dart
import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';

import '../native_bridge/native_bridge.dart';

/// The display mode the app asked Android for. A request, not a guarantee: OEM power modes and
/// user caps can still hold the display at 60 Hz (docs/architecture.md §12.2).
class DisplayModePreference extends Equatable {
  const DisplayModePreference({
    required this.refreshRate,
    required this.modeId,
  });

  final double refreshRate;
  final int modeId;

  @override
  List<Object?> get props => [refreshRate, modeId];
}

/// `window · preferHighRefreshRate`. Composition-root infrastructure, not a domain port — it
/// shares the `window` channel with `security_guard`'s `ChannelSecureWindow`.
class ChannelDisplayMode {
  static const _channel = MethodChannel(NativeChannels.window);

  /// `null` when the display offers no mode at its current resolution.
  Future<DisplayModePreference?> preferHighRefreshRate() async {
    final reply = await invokeNative(_channel, 'preferHighRefreshRate');
    if (reply == null) return null;
    final wire = WireMap(reply);
    return DisplayModePreference(
      refreshRate: wire.decimal('refreshRate'),
      modeId: wire.integer('modeId'),
    );
  }
}
```

- [ ] **Step 4: Run them to verify they pass**

Run: `flutter test test/bootstrap`
Expected: `+5: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/bootstrap test/bootstrap
git commit -m "feat(bootstrap): add ChannelAppInfo and ChannelDisplayMode"
```

---

### Task 10: Dart-side checkpoint — the new lint walls fire, suite green

**Files:**
- Temporarily modify, then revert: one file per rule

- [ ] **Step 1: Verify `native_bridge_via_barrel`**

Temporarily add this line under the existing imports of `lib/features/security_guard/src/data/channel_secure_window.dart`:
```dart
import '../../../../native_bridge/src/wire_map.dart';
```
Run: `dart analyze`
Expected: an `import_lint` diagnostic naming `native_bridge_via_barrel` on that line. Revert with `git checkout lib/features/security_guard/src/data/channel_secure_window.dart`.

- [ ] **Step 2: Verify `native_bridge_depends_on_core_only`**

Temporarily add this line at the top of `lib/native_bridge/src/native_channels.dart`:
```dart
import '../../features/payment/payment.dart';
```
Run: `dart analyze`
Expected: an `import_lint` diagnostic naming `native_bridge_depends_on_core_only`. Revert with `git checkout lib/native_bridge/src/native_channels.dart`.

- [ ] **Step 3: Confirm the tree is clean and green**

Run: `dart analyze` — Expected: `No issues found!`
Run: `flutter test` — Expected: `+153: All tests passed!` (109 before this plan + 44). Read the count off the runner's summary line; do not add it up by hand.
Run: `~/fvm/versions/3.44.6/bin/dart format --set-exit-if-changed lib test` — Expected: `Formatted N files (0 changed)`, exit code 0. If files changed, commit them as `style: dart format`.

No commit otherwise — the Dart side is done. Record the two rule observations for Task 22's verification note.

---

## Part B — Kotlin side

Package root `dev.test.payment`; main sources under `android/app/src/main/kotlin/dev/test/payment/`, JVM tests under `android/app/src/test/kotlin/dev/test/payment/`. Paths below are shortened to `kotlin/…` and `test-kotlin/…` respectively.

### Task 11: Android build configuration — minSdk 26, flavors, dependencies, JVM test wiring

**Files:**
- Modify: `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Replace `android/app/build.gradle.kts`**

```kotlin
plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.test.payment"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        // AppInfoHandler reads BuildConfig.FLAVOR / VERSION_NAME / VERSION_CODE (docs/architecture.md §9).
        buildConfig = true
        // The flavors below set app_name with resValue.
        resValues = true
    }

    defaultConfig {
        applicationId = "dev.test.payment"
        // docs/architecture.md §1: minSdk 26 — the notification channel and Process.waitFor(timeout)
        // are used without version gates on that basis.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Brand = Flavor, 1:1 (docs/architecture.md §6, ADR-0002). Adding a brand adds one block (§13).
    flavorDimensions += "brand"
    productFlavors {
        create("retail") {
            dimension = "brand"
            applicationIdSuffix = ".retail"
            resValue("string", "app_name", "Retail Shop")
        }
        create("utility") {
            dimension = "brand"
            applicationIdSuffix = ".utility"
            resValue("string", "app_name", "Utility Pay")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.17.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")

    testImplementation("junit:junit:4.13.2")
    // Parses contract/fixtures/*.json in JVM tests. Not org.json: android.jar's stubbed copy shadows it.
    testImplementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
}

// JVM tests read the shared channel fixtures and the manifest from the repo, not from test resources,
// so Dart and Kotlin pin the same files (docs/architecture.md §9, §14).
val contractFixtures: File = rootProject.file("../contract/fixtures").canonicalFile
val mainManifest: File = file("src/main/AndroidManifest.xml")
tasks.withType<Test>().configureEach {
    systemProperty("contract.fixtures", contractFixtures.path)
    systemProperty("main.manifest", mainManifest.path)
    inputs.dir(contractFixtures)
    inputs.file(mainManifest)
    testLogging {
        events("passed", "skipped", "failed")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}
```

What changed from the template: `minSdk` (was `flutter.minSdkVersion`, i.e. 24), `buildFeatures`, the flavors, `dependencies`, and the test wiring. The template's `applicationId` TODO comment is gone because the id is settled. The release-signing TODO stays: it is the template's and out of scope.

- [ ] **Step 2: Use the flavor's app name as the launcher label**

In `android/app/src/main/AndroidManifest.xml`, replace `android:label="payment"` with `android:label="@string/app_name"`.

- [ ] **Step 3: Verify the JVM test task runs (no tests yet)**

Run: `kotlin tests`
Expected: `> Task :app:testRetailDebugUnitTest NO-SOURCE` and `BUILD SUCCESSFUL`.

- [ ] **Step 4: Verify both flavors build**

Run: `~/fvm/versions/3.44.6/bin/flutter build apk --debug --flavor retail`
Expected: `✓ Built build/app/outputs/flutter-apk/app-retail-debug.apk`
Run: `~/fvm/versions/3.44.6/bin/flutter build apk --debug --flavor utility`
Expected: `✓ Built build/app/outputs/flutter-apk/app-utility-debug.apk`

From here on, `flutter run` and `flutter build` need `--flavor`. Plan 5's `Makefile` pairs the flag with `--dart-define=BRAND`.

- [ ] **Step 5: Commit**

```bash
git add android/app/build.gradle.kts android/app/src/main/AndroidManifest.xml
git commit -m "build(android): minSdk 26, retail/utility flavors, BuildConfig, bridge dependencies, JVM test wiring"
```

---

### Task 12: Kotlin fixture loader and channel names

**Files:**
- Create: `test-kotlin/ContractFixtures.kt`, `test-kotlin/bridge/ChannelNamesTest.kt`
- Create: `kotlin/bridge/Channels.kt`

- [ ] **Step 1: Write the fixture loader**

`test-kotlin/ContractFixtures.kt`:
```kotlin
package dev.test.payment

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File

/**
 * Reads contract/fixtures/<name>.json — the same files the Dart contract tests read — into plain
 * Kotlin values, numbers widened to Long/Double so they compare equal to a channel payload after
 * [normalized].
 */
object ContractFixtures {
    private val directory = File(System.getProperty("contract.fixtures") ?: error("Run through Gradle: contract.fixtures is unset"))

    fun load(name: String): Any? = Json.parseToJsonElement(File(directory, "$name.json").readText()).toPlain()

    /** Widens Int→Long and Float→Double throughout, so a payload map compares equal to [load]'s output. */
    fun normalized(value: Any?): Any? =
        when (value) {
            is Int -> value.toLong()
            is Float -> value.toDouble()
            is Map<*, *> -> value.entries.associate { (key, item) -> key to normalized(item) }
            is List<*> -> value.map(::normalized)
            else -> value
        }

    private fun JsonElement.toPlain(): Any? =
        when (this) {
            JsonNull -> null
            is JsonObject -> entries.associate { (key, item) -> key to item.toPlain() }
            is JsonArray -> map { it.toPlain() }
            is JsonPrimitive ->
                if (isString) content else content.toBooleanStrictOrNull() ?: content.toLongOrNull() ?: content.toDouble()
        }
}
```

- [ ] **Step 2: Write the failing test**

`test-kotlin/bridge/ChannelNamesTest.kt`:
```kotlin
package dev.test.payment.bridge

import dev.test.payment.ContractFixtures
import org.junit.Assert.assertEquals
import org.junit.Test

class ChannelNamesTest {
    @Test
    fun `channel names match contract fixtures`() {
        assertEquals(
            ContractFixtures.load("channels"),
            mapOf(
                "securityEnvironment" to ChannelNames.SECURITY_ENVIRONMENT,
                "securityEnvironmentEvents" to ChannelNames.SECURITY_ENVIRONMENT_EVENTS,
                "window" to ChannelNames.WINDOW,
                "paymentJob" to ChannelNames.PAYMENT_JOB,
                "paymentJobEvents" to ChannelNames.PAYMENT_JOB_EVENTS,
                "app" to ChannelNames.APP,
            ),
        )
    }
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `kotlin tests`
Expected: `e: …ChannelNamesTest.kt… Unresolved reference 'ChannelNames'.` and `BUILD FAILED`.

- [ ] **Step 4: Implement**

`kotlin/bridge/Channels.kt`:
```kotlin
package dev.test.payment.bridge

import io.flutter.plugin.common.BinaryMessenger

/**
 * The six channel names of docs/architecture.md §9 (ADR-0003: four method channels, two event
 * channels). Pinned against contract/fixtures/channels.json by a JVM test; the Dart side pins the
 * same file.
 */
object ChannelNames {
    private const val PREFIX = "dev.test.payment"
    const val SECURITY_ENVIRONMENT = "$PREFIX/security.environment"
    const val SECURITY_ENVIRONMENT_EVENTS = "$PREFIX/security.environment/events"
    const val WINDOW = "$PREFIX/window"
    const val PAYMENT_JOB = "$PREFIX/payment.job"
    const val PAYMENT_JOB_EVENTS = "$PREFIX/payment.job/events"
    const val APP = "$PREFIX/app"
}

/** The error codes of docs/architecture.md §9. */
object ErrorCodes {
    const val BAD_ARGUMENTS = "badArguments"
    const val NO_ACTIVITY = "noActivity"
    const val ALREADY_RUNNING = "alreadyRunning"
    const val SERVICE_START_FAILED = "serviceStartFailed"
}

/** One concern's channels (method + optional event channel), attached for one engine's lifetime. */
interface ChannelHandler {
    fun attach(messenger: BinaryMessenger)

    fun detach()
}
```

- [ ] **Step 5: Run it to verify it passes**

Run: `kotlin tests`
Expected: `ChannelNamesTest > channel names match contract fixtures PASSED`, `BUILD SUCCESSFUL`.

- [ ] **Step 6: Commit**

```bash
git add android/app/src
git commit -m "feat(android): add ChannelNames, ErrorCodes, ChannelHandler and the JVM fixture loader"
```

---

### Task 13: `MainThreadResult` and `MainThreadSink`

The threading guarantee of §9: every `Result`/`EventSink` call happens on the main thread. The JVM has no `Looper`, so "the main thread" sits behind a two-member interface that tests replace.

**Files:**
- Create: `kotlin/bridge/MainThread.kt`, `kotlin/bridge/MainThreadResult.kt`, `kotlin/bridge/MainThreadSink.kt`
- Test: `test-kotlin/bridge/MainThreadWrappersTest.kt`

- [ ] **Step 1: Write the failing test**

```kotlin
package dev.test.payment.bridge

import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Test

class MainThreadWrappersTest {
    private class FakeMainThread(override var isCurrent: Boolean) : MainThread {
        val posted = mutableListOf<() -> Unit>()

        override fun post(block: () -> Unit) {
            posted += block
        }

        fun drain() {
            posted.toList().forEach { it() }
            posted.clear()
        }
    }

    private class RecordingResult : MethodChannel.Result {
        val calls = mutableListOf<String>()

        override fun success(result: Any?) {
            calls += "success($result)"
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            calls += "error($errorCode)"
        }

        override fun notImplemented() {
            calls += "notImplemented"
        }
    }

    private class RecordingSink : EventChannel.EventSink {
        val calls = mutableListOf<String>()

        override fun success(event: Any?) {
            calls += "success($event)"
        }

        override fun error(errorCode: String?, errorMessage: String?, errorDetails: Any?) {
            calls += "error($errorCode)"
        }

        override fun endOfStream() {
            calls += "endOfStream"
        }
    }

    @Test
    fun `result replies inline when already on the main thread`() {
        val delegate = RecordingResult()
        val result = MainThreadResult(delegate, FakeMainThread(isCurrent = true))

        result.success(1)
        result.error("noActivity", null, null)
        result.notImplemented()

        assertEquals(listOf("success(1)", "error(noActivity)", "notImplemented"), delegate.calls)
    }

    @Test
    fun `result posts to the main thread when called from another thread`() {
        val delegate = RecordingResult()
        val mainThread = FakeMainThread(isCurrent = false)
        val result = MainThreadResult(delegate, mainThread)

        result.success("x")
        assertEquals(emptyList<String>(), delegate.calls)

        mainThread.drain()
        assertEquals(listOf("success(x)"), delegate.calls)
    }

    @Test
    fun `sink emits inline on the main thread and posts otherwise`() {
        val delegate = RecordingSink()
        val mainThread = FakeMainThread(isCurrent = true)
        val sink = MainThreadSink(delegate, mainThread)

        sink.success("a")
        mainThread.isCurrent = false
        sink.success("b")
        sink.endOfStream()
        assertEquals(listOf("success(a)"), delegate.calls)

        mainThread.drain()
        assertEquals(listOf("success(a)", "success(b)", "endOfStream"), delegate.calls)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `kotlin tests`
Expected: `e: …MainThreadWrappersTest.kt… Unresolved reference 'MainThread'.` (and `MainThreadResult`, `MainThreadSink`), `BUILD FAILED`.

- [ ] **Step 3: Implement**

`kotlin/bridge/MainThread.kt`:
```kotlin
package dev.test.payment.bridge

import android.os.Handler
import android.os.Looper

/**
 * The Android main thread, behind an interface so [MainThreadResult] and [MainThreadSink] can be
 * unit-tested on the JVM, where there is no Looper.
 */
interface MainThread {
    val isCurrent: Boolean

    fun post(block: () -> Unit)
}

object AndroidMainThread : MainThread {
    private val handler by lazy { Handler(Looper.getMainLooper()) }

    override val isCurrent: Boolean
        get() = Looper.myLooper() == Looper.getMainLooper()

    override fun post(block: () -> Unit) {
        handler.post(block)
    }
}

/** Runs [block] inline when already on the main thread, otherwise posts it there. */
internal fun MainThread.execute(block: () -> Unit) {
    if (isCurrent) block() else post(block)
}
```

`kotlin/bridge/MainThreadResult.kt`:
```kotlin
package dev.test.payment.bridge

import io.flutter.plugin.common.MethodChannel

/**
 * A [MethodChannel.Result] that always replies on the main thread — the threading guarantee of
 * docs/architecture.md §9, enforced here rather than by discipline at every call site.
 */
class MainThreadResult(
    private val delegate: MethodChannel.Result,
    private val mainThread: MainThread = AndroidMainThread,
) : MethodChannel.Result {
    override fun success(result: Any?) = mainThread.execute { delegate.success(result) }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) =
        mainThread.execute { delegate.error(errorCode, errorMessage, errorDetails) }

    override fun notImplemented() = mainThread.execute { delegate.notImplemented() }
}
```

`kotlin/bridge/MainThreadSink.kt`:
```kotlin
package dev.test.payment.bridge

import io.flutter.plugin.common.EventChannel

/**
 * An [EventChannel.EventSink] that always emits on the main thread — the event-stream half of the
 * threading guarantee in docs/architecture.md §9.
 */
class MainThreadSink(
    private val delegate: EventChannel.EventSink,
    private val mainThread: MainThread = AndroidMainThread,
) : EventChannel.EventSink {
    override fun success(event: Any?) = mainThread.execute { delegate.success(event) }

    override fun error(errorCode: String?, errorMessage: String?, errorDetails: Any?) =
        mainThread.execute { delegate.error(errorCode, errorMessage, errorDetails) }

    override fun endOfStream() = mainThread.execute { delegate.endOfStream() }
}
```

(The helper is named `execute`, not `run`, so it can't be confused with Kotlin's stdlib `run`.)

- [ ] **Step 4: Run it to verify it passes**

Run: `kotlin tests`
Expected: three `MainThreadWrappersTest > … PASSED` lines plus the channel-names test, `BUILD SUCCESSFUL`.

- [ ] **Step 5: Commit**

```bash
git add android/app/src
git commit -m "feat(android): add MainThreadResult and MainThreadSink"
```

---

### Task 14: Posture snapshot, root-signal threshold, manifest `<queries>`

**Files:**
- Create: `kotlin/security/PostureSnapshot.kt`, `kotlin/security/RootChecks.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Test: `test-kotlin/security/PostureSnapshotTest.kt`, `test-kotlin/security/RootChecksTest.kt`, `test-kotlin/security/RootPackagesManifestTest.kt`

- [ ] **Step 1: Write the failing tests**

`test-kotlin/security/PostureSnapshotTest.kt`:
```kotlin
package dev.test.payment.security

import dev.test.payment.ContractFixtures
import org.junit.Assert.assertEquals
import org.junit.Test

class PostureSnapshotTest {
    private val assessedAt = 1758000000000L

    @Test
    fun `secure snapshot matches posture_secure fixture`() {
        val snapshot = PostureSnapshot(AssessmentResult.Clear, AssessmentResult.Clear, assessedAt)
        assertEquals(ContractFixtures.load("posture.secure"), ContractFixtures.normalized(snapshot.toWire()))
    }

    @Test
    fun `rooted snapshot matches posture_compromised-rooted fixture`() {
        val snapshot = PostureSnapshot(AssessmentResult.Detected, AssessmentResult.Clear, assessedAt)
        assertEquals(ContractFixtures.load("posture.compromised-rooted"), ContractFixtures.normalized(snapshot.toWire()))
    }

    @Test
    fun `below API 35 snapshot matches posture_unverified-api34 fixture`() {
        val snapshot =
            PostureSnapshot(
                rooted = AssessmentResult.Clear,
                screenRecording = AssessmentResult.Unavailable(UnavailableReason.API_LEVEL),
                assessedAt = assessedAt,
            )
        assertEquals(ContractFixtures.load("posture.unverified-api34"), ContractFixtures.normalized(snapshot.toWire()))
    }
}
```

`test-kotlin/security/RootChecksTest.kt`:
```kotlin
package dev.test.payment.security

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RootChecksTest {
    private fun fires(name: String) = RootSignal(name) { true }

    private fun quiet(name: String) = RootSignal(name) { false }

    private fun throws(name: String) = RootSignal(name) { throw SecurityException("denied") }

    @Test
    fun `no signal fired is clear`() {
        val outcome = RootChecks(listOf(quiet("a"), quiet("b"))).run()
        assertEquals(AssessmentResult.Clear, outcome.result)
    }

    @Test
    fun `one signal alone is below the threshold and stays clear`() {
        val outcome = RootChecks(listOf(fires("a"), quiet("b"), quiet("c"))).run()
        assertEquals(AssessmentResult.Clear, outcome.result)
        assertEquals(listOf("a"), outcome.fired)
    }

    @Test
    fun `two signals reach the threshold and are detected`() {
        val outcome = RootChecks(listOf(fires("a"), quiet("b"), fires("c"))).run()
        assertEquals(AssessmentResult.Detected, outcome.result)
        assertEquals(listOf("a", "c"), outcome.fired)
    }

    @Test
    fun `a signal that throws below the threshold is unavailable(error), never clear`() {
        val outcome = RootChecks(listOf(fires("a"), throws("b"), quiet("c"))).run()
        assertEquals(AssessmentResult.Unavailable(UnavailableReason.ERROR), outcome.result)
        assertEquals(listOf("b"), outcome.failed)
    }

    @Test
    fun `a signal that throws does not mask a detection`() {
        val outcome = RootChecks(listOf(fires("a"), throws("b"), fires("c"))).run()
        assertEquals(AssessmentResult.Detected, outcome.result)
    }

    @Test
    fun `read-write system and vendor mounts are writable`() {
        assertTrue(RootChecks.isWritableSystemMount("/dev/block/dm-0 /system ext4 rw,seclabel,relatime 0 0"))
        assertTrue(RootChecks.isWritableSystemMount("/dev/block/dm-2 /vendor ext4 rw 0 0"))
    }

    @Test
    fun `read-only, nested and malformed mounts are not`() {
        assertFalse(RootChecks.isWritableSystemMount("/dev/block/dm-0 /system ext4 ro,seclabel,relatime 0 0"))
        assertFalse(RootChecks.isWritableSystemMount("tmpfs /system/etc tmpfs rw 0 0"))
        assertFalse(RootChecks.isWritableSystemMount("/dev/root /system"))
    }
}
```

`test-kotlin/security/RootPackagesManifestTest.kt`:
```kotlin
package dev.test.payment.security

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

class RootPackagesManifestTest {
    @Test
    fun `every root package has a manifest queries entry and vice versa`() {
        val manifest = File(System.getProperty("main.manifest") ?: error("Run through Gradle: main.manifest is unset")).readText()
        val queried = Regex("""<package\s+android:name="([^"]+)"""").findAll(manifest).map { it.groupValues[1] }.toSet()
        assertEquals(RootChecks.ROOT_PACKAGES.toSet(), queried)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `kotlin tests`
Expected: `Unresolved reference` errors for `PostureSnapshot`, `AssessmentResult`, `RootChecks`, `RootSignal`; `BUILD FAILED`.

- [ ] **Step 3: Implement the wire model**

`kotlin/security/PostureSnapshot.kt`:
```kotlin
package dev.test.payment.security

/** The `result` of one Threat Assessment on the wire (docs/architecture.md §9). */
sealed interface AssessmentResult {
    data object Detected : AssessmentResult

    data object Clear : AssessmentResult

    data class Unavailable(val reason: UnavailableReason) : AssessmentResult
}

enum class UnavailableReason(val wire: String) {
    API_LEVEL("apiLevel"),
    ERROR("error"),
}

/** One `security.environment/events` payload: an assessment per Threat kind, and when it was taken. */
data class PostureSnapshot(
    val rooted: AssessmentResult,
    val screenRecording: AssessmentResult,
    val assessedAt: Long,
) {
    fun toWire(): Map<String, Any?> =
        mapOf(
            "assessments" to listOf(assessment("rooted", rooted), assessment("screenRecording", screenRecording)),
            "assessedAt" to assessedAt,
        )

    private fun assessment(kind: String, result: AssessmentResult): Map<String, Any?> =
        when (result) {
            AssessmentResult.Detected -> mapOf("kind" to kind, "result" to "detected")
            AssessmentResult.Clear -> mapOf("kind" to kind, "result" to "clear")
            is AssessmentResult.Unavailable ->
                mapOf("kind" to kind, "result" to "unavailable", "reason" to result.reason.wire)
        }
}
```

- [ ] **Step 4: Implement the threshold**

`kotlin/security/RootChecks.kt`:
```kotlin
package dev.test.payment.security

/** One independent root indicator. [fired] may block (disk, process, Binder) and may throw. */
class RootSignal(val name: String, val fired: () -> Boolean)

/** What [RootChecks.run] found: the wire result, plus the signal names for debug logging only. */
data class RootAssessment(
    val result: AssessmentResult,
    val fired: List<String>,
    val failed: List<String>,
)

/**
 * The Rooted Threat Assessment: six hand-rolled signals, `detected` only when at least
 * [THRESHOLD] fire, which absorbs the single-signal false positives documented in
 * docs/research/root-detection.md. A signal that throws could not run: unless the threshold is
 * already met, the result is then `unavailable(error)` — never a silent `clear`
 * (docs/architecture.md §2 principle 8). Blocking — call on `Dispatchers.IO`.
 */
class RootChecks(private val signals: List<RootSignal>) {
    fun run(): RootAssessment {
        val fired = mutableListOf<String>()
        val failed = mutableListOf<String>()
        for (signal in signals) {
            try {
                if (signal.fired()) fired += signal.name
            } catch (e: Exception) {
                failed += signal.name
            }
        }
        val result =
            when {
                fired.size >= THRESHOLD -> AssessmentResult.Detected
                failed.isNotEmpty() -> AssessmentResult.Unavailable(UnavailableReason.ERROR)
                else -> AssessmentResult.Clear
            }
        return RootAssessment(result, fired, failed)
    }

    companion object {
        const val THRESHOLD = 2

        /** Root-manager packages. Each needs a `<queries>` entry in AndroidManifest.xml (targetSdk 36). */
        val ROOT_PACKAGES =
            listOf(
                "com.topjohnwu.magisk",
                "eu.chainfire.supersu",
                "com.noshufou.android.su",
                "com.koushikdutta.superuser",
                "me.weishu.kernelsu",
            )

        private val WRITABLE_CHECK_MOUNT_POINTS = setOf("/system", "/vendor")

        /** Whether one `/proc/mounts` line mounts `/system` or `/vendor` read-write. */
        fun isWritableSystemMount(line: String): Boolean {
            val fields = line.trim().split(Regex("\\s+"))
            if (fields.size < 4) return false
            return fields[1] in WRITABLE_CHECK_MOUNT_POINTS && "rw" in fields[3].split(",")
        }
    }
}
```

- [ ] **Step 5: Run the tests — the manifest test is the one still red**

Run: `kotlin tests`
Expected: every `PostureSnapshotTest` and `RootChecksTest` line `PASSED`; `RootPackagesManifestTest > every root package has a manifest queries entry and vice versa FAILED` with `expected:<[com.topjohnwu.magisk, …]> but was:<[]>`; `BUILD FAILED`.

- [ ] **Step 6: Declare the package queries**

In `android/app/src/main/AndroidManifest.xml`, inside the existing `<queries>` element, after its `<intent>…</intent>` block, add:
```xml
        <!-- Root-manager packages checked by RootChecks.ROOT_PACKAGES (targetSdk 36 package
             visibility). Kept in sync by RootPackagesManifestTest. -->
        <package android:name="com.topjohnwu.magisk"/>
        <package android:name="eu.chainfire.supersu"/>
        <package android:name="com.noshufou.android.su"/>
        <package android:name="com.koushikdutta.superuser"/>
        <package android:name="me.weishu.kernelsu"/>
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `kotlin tests`
Expected: 15 `PASSED` lines (1 + 3 + 3 + 7 + 1), `BUILD SUCCESSFUL`.

- [ ] **Step 8: Commit**

```bash
git add android/app/src
git commit -m "feat(android): add PostureSnapshot and the RootChecks threshold; declare root-package queries"
```

---

### Task 15: `SecurityEnvironmentHandler`, the device root signals, the recorder monitor

These three classes are Android-bound, so they get no JVM tests (§14: no Robolectric). The logic they depend on is already tested (Task 14), and Task 21 exercises them on a device.

**Files:**
- Create: `kotlin/security/DeviceRootSignals.kt`, `kotlin/security/ScreenRecordingMonitor.kt`, `kotlin/security/SecurityEnvironmentHandler.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: The six device signals**

`kotlin/security/DeviceRootSignals.kt`:
```kotlin
package dev.test.payment.security

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

/** The six real root signals of docs/architecture.md §8. Not unit-tested: every one touches the device. */
internal object DeviceRootSignals {
    private const val COMMAND_TIMEOUT_MS = 1_000L
    private val SU_DIRECTORIES =
        listOf(
            "/system/bin", "/system/xbin", "/sbin", "/system_ext/bin", "/system/bin/failsafe",
            "/data/local/xbin", "/data/local/bin", "/data/local", "/su/bin",
        )

    fun all(context: Context): List<RootSignal> =
        listOf(
            RootSignal("suBinary") { SU_DIRECTORIES.any { File(it, "su").exists() } },
            RootSignal("whichSu") { runCommand("which", "su").isNotBlank() },
            RootSignal("testKeys") { Build.TAGS?.contains("test-keys") == true },
            RootSignal("dangerousProps") {
                runCommand("getprop", "ro.debuggable").trim() == "1" || runCommand("getprop", "ro.secure").trim() == "0"
            },
            RootSignal("rootPackage") { RootChecks.ROOT_PACKAGES.any { isInstalled(context, it) } },
            RootSignal("writableSystem") {
                File("/proc/mounts").useLines { lines -> lines.any(RootChecks::isWritableSystemMount) }
            },
        )

    private fun isInstalled(context: Context, packageName: String): Boolean =
        try {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(packageName, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }

    /** Runs a short command and returns its output; throws if it does not finish in time. */
    private fun runCommand(vararg command: String): String {
        val process = ProcessBuilder(*command).redirectErrorStream(true).start()
        try {
            if (!process.waitFor(COMMAND_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                throw IOException("${command.joinToString(" ")} timed out")
            }
            return process.inputStream.bufferedReader().use { it.readText() }
        } finally {
            process.destroy()
        }
    }
}
```

Two differences from `docs/research/root-detection.md`'s sketch are deliberate:
- The props are read one at a time (`getprop ro.debuggable`), not as a full `getprop` dump. The output stays tiny, so waiting for the process before reading its output cannot deadlock on a full pipe.
- A timed-out command *throws*. That counts as "could not run" (`unavailable(error)`), not as "didn't fire".

- [ ] **Step 2: The API 35+ recorder monitor**

`kotlin/security/ScreenRecordingMonitor.kt`:
```kotlin
package dev.test.payment.security

import android.content.Context
import android.os.Build
import android.view.WindowManager
import androidx.annotation.RequiresApi
import androidx.annotation.WorkerThread
import androidx.core.content.ContextCompat
import java.util.function.Consumer

/**
 * The API 35+ screen-recording signal (`WindowManager.addScreenRecordingCallback`). Both calls
 * are blocking Binder round-trips — call them off the main thread. Changes are delivered on the
 * main thread (docs/architecture.md §8).
 */
interface ScreenRecordingMonitor {
    /** Registers the callback and returns whether this app is being recorded right now. */
    @WorkerThread
    fun start(): Boolean

    @WorkerThread
    fun stop()

    companion object {
        /** `null` below API 35, where there is no official signal. */
        fun create(context: Context, onChange: (recording: Boolean) -> Unit): ScreenRecordingMonitor? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
                Api35ScreenRecordingMonitor(context, onChange)
            } else {
                null
            }
    }
}

@RequiresApi(Build.VERSION_CODES.VANILLA_ICE_CREAM)
private class Api35ScreenRecordingMonitor(
    context: Context,
    onChange: (Boolean) -> Unit,
) : ScreenRecordingMonitor {
    private val windowManager = context.getSystemService(WindowManager::class.java)
    private val mainExecutor = ContextCompat.getMainExecutor(context)
    private val callback =
        Consumer<Int> { state -> onChange(state == WindowManager.SCREEN_RECORDING_STATE_VISIBLE) }
    private var registered = false

    @Synchronized
    override fun start(): Boolean {
        if (registered) windowManager.removeScreenRecordingCallback(callback)
        val state = windowManager.addScreenRecordingCallback(mainExecutor, callback)
        registered = true
        return state == WindowManager.SCREEN_RECORDING_STATE_VISIBLE
    }

    @Synchronized
    override fun stop() {
        if (!registered) return
        windowManager.removeScreenRecordingCallback(callback)
        registered = false
    }
}
```

The interface-plus-private-implementation shape keeps callers free of `@RequiresApi` (Android lint would flag every call otherwise); the SDK check lives once, in `create`. The callback is registered through the *application* context: the API reports recording of any activity in the registering process's UID.

- [ ] **Step 3: The handler**

`kotlin/security/SecurityEnvironmentHandler.kt`:
```kotlin
package dev.test.payment.security

import android.content.Context
import android.util.Log
import dev.test.payment.bridge.ChannelHandler
import dev.test.payment.bridge.ChannelNames
import dev.test.payment.bridge.MainThreadResult
import dev.test.payment.bridge.MainThreadSink
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * `security.environment` + `security.environment/events` (docs/architecture.md §8, §9).
 *
 * `assess` acks as soon as an assessment is running — a new one, or the one already in progress
 * (concurrent calls coalesce); the snapshot follows on the event stream, the single source of
 * truth. The stream is replay-1. Listening registers the API 35+ recorder callback and cancelling
 * unregisters it, so the callback lives exactly as long as the observing screen's subscription.
 * A snapshot is only published once both halves are known: the first root assessment, and the
 * recorder state (fixed `unavailable(apiLevel)` below API 35). All state is touched on the main
 * thread only — `scope` runs on `Dispatchers.Main.immediate`.
 */
class SecurityEnvironmentHandler(
    context: Context,
    private val scope: CoroutineScope,
    private val rootChecks: RootChecks = RootChecks(DeviceRootSignals.all(context)),
) : ChannelHandler, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val recordingMonitor = ScreenRecordingMonitor.create(context, ::onRecordingChanged)

    // Registration calls run one at a time, in order, so listen → cancel → listen can't interleave.
    private val monitorDispatcher = Dispatchers.IO.limitedParallelism(1)

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var sink: EventChannel.EventSink? = null
    private var listening = false
    private var assessment: Job? = null
    private var rooted: AssessmentResult? = null
    private var screenRecording: AssessmentResult? =
        if (recordingMonitor == null) AssessmentResult.Unavailable(UnavailableReason.API_LEVEL) else null
    private var lastSnapshot: PostureSnapshot? = null

    override fun attach(messenger: BinaryMessenger) {
        methodChannel = MethodChannel(messenger, ChannelNames.SECURITY_ENVIRONMENT).also { it.setMethodCallHandler(this) }
        eventChannel = EventChannel(messenger, ChannelNames.SECURITY_ENVIRONMENT_EVENTS).also { it.setStreamHandler(this) }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun detach() {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        sink = null
        listening = false
        // The engine's scope is being cancelled; the unregister call must still run.
        recordingMonitor?.let { monitor -> GlobalScope.launch(monitorDispatcher) { monitor.stop() } }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val reply = MainThreadResult(result)
        when (call.method) {
            "assess" -> {
                assess()
                reply.success(null)
            }
            else -> reply.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val mainSink = MainThreadSink(events)
        sink = mainSink
        listening = true
        lastSnapshot?.let { mainSink.success(it.toWire()) }
        val monitor = recordingMonitor ?: return
        scope.launch {
            val recording = withContext(monitorDispatcher) { runCatching { monitor.start() } }
            if (!listening) return@launch
            screenRecording =
                recording.fold(
                    onSuccess = { if (it) AssessmentResult.Detected else AssessmentResult.Clear },
                    onFailure = { AssessmentResult.Unavailable(UnavailableReason.ERROR) },
                )
            publish()
        }
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        listening = false
        val monitor = recordingMonitor ?: return
        screenRecording = null
        scope.launch(monitorDispatcher) { runCatching { monitor.stop() } }
    }

    private fun assess() {
        if (assessment?.isActive == true) return
        assessment =
            scope.launch {
                val outcome = withContext(Dispatchers.IO) { rootChecks.run() }
                if (outcome.fired.isNotEmpty() || outcome.failed.isNotEmpty()) {
                    Log.d(TAG, "Root signals fired=${outcome.fired} failed=${outcome.failed}")
                }
                rooted = outcome.result
                publish()
            }
    }

    private fun onRecordingChanged(recording: Boolean) {
        if (!listening) return
        screenRecording = if (recording) AssessmentResult.Detected else AssessmentResult.Clear
        publish()
    }

    private fun publish() {
        val snapshot =
            PostureSnapshot(
                rooted = rooted ?: return,
                screenRecording = screenRecording ?: return,
                assessedAt = System.currentTimeMillis(),
            )
        lastSnapshot = snapshot
        sink?.success(snapshot.toWire())
    }

    private companion object {
        const val TAG = "SecurityEnvironment"
    }
}
```

Fired signal names are logged at debug level only. They never go on the wire (ticket 10, decision 4).

- [ ] **Step 4: Declare the recorder permission**

In `android/app/src/main/AndroidManifest.xml`, directly after the opening `<manifest …>` tag, add:
```xml
    <!-- Owned by the native channel contract, docs/architecture.md §9. -->
    <uses-permission android:name="android.permission.DETECT_SCREEN_RECORDING"/>
```

(A `normal` permission, granted at install. `addScreenRecordingCallback` requires it.)

- [ ] **Step 5: Compile and re-run the JVM tests**

Run: `kotlin compile`
Expected: `BUILD SUCCESSFUL` with no `e:` lines and no `w:` lines pointing at `kotlin/dev/test/payment/`.
Run: `kotlin tests`
Expected: the same 15 `PASSED` lines, `BUILD SUCCESSFUL`.

- [ ] **Step 6: Commit**

```bash
git add android/app/src
git commit -m "feat(android): add SecurityEnvironmentHandler with device root signals and the API 35 recorder monitor"
```

---

### Task 16: `window` and `app` handlers

**Files:**
- Create: `kotlin/window/DisplayModes.kt`, `kotlin/window/WindowHandler.kt`, `kotlin/app/AppInfoHandler.kt`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Test: `test-kotlin/window/DisplayModesTest.kt`, `test-kotlin/app/BuildInfoTest.kt`

- [ ] **Step 1: Write the failing tests**

`test-kotlin/window/DisplayModesTest.kt`:
```kotlin
package dev.test.payment.window

import dev.test.payment.ContractFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DisplayModesTest {
    private val current60 = DisplayModeOption(modeId = 1, width = 1080, height = 2400, refreshRate = 60f)
    private val native120 = DisplayModeOption(modeId = 2, width = 1080, height = 2400, refreshRate = 120f)
    private val native90 = DisplayModeOption(modeId = 3, width = 1080, height = 2400, refreshRate = 90f)
    private val highRes144 = DisplayModeOption(modeId = 4, width = 1440, height = 3200, refreshRate = 144f)

    @Test
    fun `picks the highest rate at the current resolution, never switching resolution`() {
        val choice = DisplayModes.highestRefreshRate(listOf(current60, native120, native90, highRes144), current60)
        assertEquals(native120, choice)
    }

    @Test
    fun `no mode at the current resolution means no preference`() {
        assertNull(DisplayModes.highestRefreshRate(listOf(highRes144), current60))
    }

    @Test
    fun `the reply matches preferHighRefreshRate_result fixture`() {
        assertEquals(ContractFixtures.load("preferHighRefreshRate.result"), ContractFixtures.normalized(native120.toWire()))
    }
}
```

`test-kotlin/app/BuildInfoTest.kt`:
```kotlin
package dev.test.payment.app

import dev.test.payment.ContractFixtures
import org.junit.Assert.assertEquals
import org.junit.Test

class BuildInfoTest {
    @Test
    fun `the reply matches buildInfo_retail fixture`() {
        val info =
            BuildInfo(
                flavor = "retail",
                applicationId = "dev.test.payment.retail",
                versionName = "0.1.0",
                versionCode = 1,
                sdkInt = 36,
            )
        assertEquals(ContractFixtures.load("buildInfo.retail"), ContractFixtures.normalized(info.toWire()))
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `kotlin tests`
Expected: `Unresolved reference` for `DisplayModeOption`, `DisplayModes`, `BuildInfo`; `BUILD FAILED`.

- [ ] **Step 3: Implement the display-mode choice**

`kotlin/window/DisplayModes.kt`:
```kotlin
package dev.test.payment.window

/** One `Display.Mode`, reduced to what the choice needs. */
data class DisplayModeOption(
    val modeId: Int,
    val width: Int,
    val height: Int,
    val refreshRate: Float,
) {
    /** The `preferHighRefreshRate` reply (docs/architecture.md §9). */
    fun toWire(): Map<String, Any?> = mapOf("refreshRate" to refreshRate.toDouble(), "modeId" to modeId)
}

object DisplayModes {
    /** The highest-refresh-rate mode at the current resolution — never a resolution switch. */
    fun highestRefreshRate(
        supported: List<DisplayModeOption>,
        current: DisplayModeOption,
    ): DisplayModeOption? =
        supported
            .filter { it.width == current.width && it.height == current.height }
            .maxByOrNull { it.refreshRate }
}
```

(`refreshRate.toDouble()` — send a `Double`, so the Dart side always decodes a `double`.)

- [ ] **Step 4: Implement the `app` handler**

`kotlin/app/AppInfoHandler.kt`:
```kotlin
package dev.test.payment.app

import android.content.Context
import android.os.Build
import dev.test.payment.BuildConfig
import dev.test.payment.bridge.ChannelHandler
import dev.test.payment.bridge.ChannelNames
import dev.test.payment.bridge.MainThreadResult
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** The `buildInfo` reply: what the Dart bootstrap compares with its `BRAND` dart-define. */
data class BuildInfo(
    val flavor: String,
    val applicationId: String,
    val versionName: String,
    val versionCode: Int,
    val sdkInt: Int,
) {
    fun toWire(): Map<String, Any?> =
        mapOf(
            "flavor" to flavor,
            "applicationId" to applicationId,
            "versionName" to versionName,
            "versionCode" to versionCode,
            "sdkInt" to sdkInt,
        )
}

/** `app` (docs/architecture.md §6, §9). */
class AppInfoHandler(private val context: Context) : ChannelHandler, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null

    override fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, ChannelNames.APP).also { it.setMethodCallHandler(this) }
    }

    override fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val reply = MainThreadResult(result)
        when (call.method) {
            "buildInfo" ->
                reply.success(
                    BuildInfo(
                        flavor = BuildConfig.FLAVOR,
                        applicationId = context.packageName,
                        versionName = BuildConfig.VERSION_NAME,
                        versionCode = BuildConfig.VERSION_CODE,
                        sdkInt = Build.VERSION.SDK_INT,
                    ).toWire(),
                )
            else -> reply.notImplemented()
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `kotlin tests`
Expected: 19 `PASSED` lines, `BUILD SUCCESSFUL`.

- [ ] **Step 6: Implement the `window` handler**

`kotlin/window/WindowHandler.kt`:
```kotlin
package dev.test.payment.window

import android.app.Activity
import android.view.Display
import android.view.WindowManager
import androidx.core.content.ContextCompat
import dev.test.payment.bridge.ChannelHandler
import dev.test.payment.bridge.ChannelNames
import dev.test.payment.bridge.ErrorCodes
import dev.test.payment.bridge.MainThreadResult
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `window` (docs/architecture.md §9, §11, §12.2). Stateless: Dart owns the Secure Window's
 * lifetime and re-asserts it on resume, so this only adds or clears `FLAG_SECURE`.
 */
class WindowHandler(private val activity: () -> Activity?) : ChannelHandler, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null

    override fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, ChannelNames.WINDOW).also { it.setMethodCallHandler(this) }
    }

    override fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val reply = MainThreadResult(result)
        when (call.method) {
            "setSecure" -> setSecure(call, reply)
            "preferHighRefreshRate" -> preferHighRefreshRate(reply)
            else -> reply.notImplemented()
        }
    }

    private fun setSecure(call: MethodCall, reply: MethodChannel.Result) {
        val secure =
            (call.arguments as? Map<*, *>)?.get("secure") as? Boolean
                ?: return reply.error(ErrorCodes.BAD_ARGUMENTS, "setSecure expects {secure: bool}", null)
        val window = activity()?.window ?: return reply.error(ErrorCodes.NO_ACTIVITY, "No Activity attached", null)
        if (secure) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        reply.success(null)
    }

    private fun preferHighRefreshRate(reply: MethodChannel.Result) {
        val activity = activity() ?: return reply.error(ErrorCodes.NO_ACTIVITY, "No Activity attached", null)
        val display = ContextCompat.getDisplayOrDefault(activity)
        val choice =
            DisplayModes.highestRefreshRate(
                supported = display.supportedModes.map { it.toOption() },
                current = display.mode.toOption(),
            ) ?: return reply.success(null)
        val window = activity.window
        window.attributes = window.attributes.apply { preferredDisplayModeId = choice.modeId }
        reply.success(choice.toWire())
    }

    private fun Display.Mode.toOption() = DisplayModeOption(modeId, physicalWidth, physicalHeight, refreshRate)
}
```

- [ ] **Step 7: Declare the app category (§12.2's OEM-heuristic hedge)**

In `android/app/src/main/AndroidManifest.xml`, add `android:appCategory="productivity"` to the `<application>` element, after `android:icon="@mipmap/ic_launcher"`.

- [ ] **Step 8: Compile and commit**

Run: `kotlin compile` — Expected: `BUILD SUCCESSFUL`, no `e:` lines.

```bash
git add android/app/src
git commit -m "feat(android): add WindowHandler (secure flag, preferred display mode) and AppInfoHandler"
```

---

### Task 17: Payment Job wire model, start arguments, state holder

**Files:**
- Create: `kotlin/payment/JobSnapshot.kt`, `kotlin/payment/StartArgs.kt`, `kotlin/payment/PaymentJobStateHolder.kt`
- Test: `test-kotlin/payment/JobSnapshotTest.kt`, `test-kotlin/payment/StartArgsTest.kt`, `test-kotlin/payment/PaymentJobStateHolderTest.kt`

- [ ] **Step 1: Write the failing tests**

`test-kotlin/payment/JobSnapshotTest.kt`:
```kotlin
package dev.test.payment.payment

import dev.test.payment.ContractFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class JobSnapshotTest {
    private fun assertMatches(fixture: String, snapshot: JobSnapshot) =
        assertEquals(ContractFixtures.load(fixture), ContractFixtures.normalized(snapshot.toWire()))

    @Test
    fun `running matches job_running fixture`() = assertMatches("job.running", JobSnapshot.Running("j-1", 40))

    @Test
    fun `succeeded matches job_succeeded fixture`() =
        assertMatches("job.succeeded", JobSnapshot.Succeeded("j-1", "PAY-DEMO-0001", 1758000000000L))

    @Test
    fun `declined matches job_failed-declined fixture`() =
        assertMatches("job.failed-declined", JobSnapshot.Failed("j-1", PaymentFailure.DECLINED))

    @Test
    fun `timed out matches job_failed-timedOut fixture`() =
        assertMatches("job.failed-timedOut", JobSnapshot.Failed("j-1", PaymentFailure.TIMED_OUT))

    @Test
    fun `only running is non-terminal`() {
        assertFalse(JobSnapshot.Running("j-1", 100).isTerminal)
        assertTrue(JobSnapshot.Succeeded("j-1", "r", 0).isTerminal)
        assertTrue(JobSnapshot.Failed("j-1", PaymentFailure.DECLINED).isTerminal)
    }
}
```

`test-kotlin/payment/StartArgsTest.kt`:
```kotlin
package dev.test.payment.payment

import dev.test.payment.ContractFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StartArgsTest {
    @Test
    fun `parses start_args fixture`() {
        assertEquals(
            StartArgs(reference = "PAY-DEMO-0001", amountMinor = 4200, currency = "USD", payee = "Acme Utilities"),
            StartArgs.fromWire(ContractFixtures.load("start.args")),
        )
    }

    @Test
    fun `accepts amountMinor as an Integer, as the codec sends small Dart ints`() {
        val args = mapOf("reference" to "r", "amountMinor" to 4299, "currency" to "USD", "payee" to "p")
        assertEquals(4299L, StartArgs.fromWire(args)?.amountMinor)
    }

    @Test
    fun `rejects a missing or mistyped field`() {
        assertNull(StartArgs.fromWire(mapOf("reference" to "r", "currency" to "USD", "payee" to "p")))
        assertNull(StartArgs.fromWire(mapOf("reference" to "r", "amountMinor" to "42", "currency" to "USD", "payee" to "p")))
        assertNull(StartArgs.fromWire(null))
    }
}
```

`test-kotlin/payment/PaymentJobStateHolderTest.kt`:
```kotlin
package dev.test.payment.payment

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PaymentJobStateHolderTest {
    private val holder = PaymentJobStateHolder()

    @Test
    fun `tryStart claims an idle holder as running(0)`() {
        assertTrue(holder.tryStart("j-1"))
        assertEquals(JobSnapshot.Running("j-1", 0), holder.state.value)
    }

    @Test
    fun `tryStart is refused while a job is running`() {
        holder.tryStart("j-1")
        assertFalse(holder.tryStart("j-2"))
        assertEquals(JobSnapshot.Running("j-1", 0), holder.state.value)
    }

    @Test
    fun `tryStart replaces an undelivered terminal snapshot`() {
        holder.tryStart("j-1")
        holder.advance(JobSnapshot.Failed("j-1", PaymentFailure.DECLINED))
        assertTrue(holder.tryStart("j-2"))
        assertEquals(JobSnapshot.Running("j-2", 0), holder.state.value)
    }

    @Test
    fun `advance moves the running job forward`() {
        holder.tryStart("j-1")
        assertTrue(holder.advance(JobSnapshot.Running("j-1", 40)))
        assertEquals(JobSnapshot.Running("j-1", 40), holder.state.value)
    }

    @Test
    fun `advance never overwrites a terminal snapshot`() {
        holder.tryStart("j-1")
        holder.advance(JobSnapshot.Succeeded("j-1", "PAY-1", 1L))
        assertFalse(holder.advance(JobSnapshot.Failed("j-1", PaymentFailure.SERVICE_UNAVAILABLE)))
        assertEquals(JobSnapshot.Succeeded("j-1", "PAY-1", 1L), holder.state.value)
    }

    @Test
    fun `advance ignores another job's snapshot`() {
        holder.tryStart("j-1")
        assertFalse(holder.advance(JobSnapshot.Running("j-other", 50)))
    }

    @Test
    fun `abandon undoes tryStart`() {
        holder.tryStart("j-1")
        holder.abandon("j-1")
        assertNull(holder.state.value)
    }

    @Test
    fun `current returns a running job and keeps it`() {
        holder.tryStart("j-1")
        assertEquals(JobSnapshot.Running("j-1", 0), holder.current())
        assertEquals(JobSnapshot.Running("j-1", 0), holder.state.value)
    }

    @Test
    fun `current delivers a terminal snapshot once, then the holder is clear`() {
        holder.tryStart("j-1")
        holder.advance(JobSnapshot.Failed("j-1", PaymentFailure.DECLINED))
        assertEquals(JobSnapshot.Failed("j-1", PaymentFailure.DECLINED), holder.current())
        assertNull(holder.current())
    }

    @Test
    fun `markDelivered clears only the terminal snapshot it was given`() {
        holder.tryStart("j-1")
        holder.markDelivered(JobSnapshot.Running("j-1", 0))
        assertEquals(JobSnapshot.Running("j-1", 0), holder.state.value)

        val done = JobSnapshot.Succeeded("j-1", "PAY-1", 1L)
        holder.advance(done)
        holder.markDelivered(done)
        assertNull(holder.state.value)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `kotlin tests`
Expected: `Unresolved reference` for `JobSnapshot`, `PaymentFailure`, `StartArgs`, `PaymentJobStateHolder`; `BUILD FAILED`.

- [ ] **Step 3: Implement the wire model**

`kotlin/payment/JobSnapshot.kt`:
```kotlin
package dev.test.payment.payment

enum class PaymentFailure(val wire: String) {
    DECLINED("declined"),
    TIMED_OUT("timedOut"),
    SERVICE_UNAVAILABLE("serviceUnavailable"),
}

/** One `payment.job/events` payload, and the value `current` returns (docs/architecture.md §9). */
sealed interface JobSnapshot {
    val jobId: String
    val isTerminal: Boolean get() = this !is Running

    data class Running(override val jobId: String, val percent: Int) : JobSnapshot

    data class Succeeded(override val jobId: String, val reference: String, val completedAt: Long) : JobSnapshot

    data class Failed(override val jobId: String, val failure: PaymentFailure) : JobSnapshot

    fun toWire(): Map<String, Any?> =
        when (this) {
            is Running -> mapOf("jobId" to jobId, "state" to "running", "percent" to percent)
            is Succeeded ->
                mapOf("jobId" to jobId, "state" to "succeeded", "reference" to reference, "completedAt" to completedAt)
            is Failed -> mapOf("jobId" to jobId, "state" to "failed", "failure" to failure.wire)
        }
}
```

- [ ] **Step 4: Implement the start arguments**

`kotlin/payment/StartArgs.kt`:
```kotlin
package dev.test.payment.payment

import android.content.Intent

/** The `start` arguments (docs/architecture.md §9), also carried to the service as Intent extras. */
data class StartArgs(
    val reference: String,
    val amountMinor: Long,
    val currency: String,
    val payee: String,
) {
    fun writeTo(intent: Intent): Intent =
        intent
            .putExtra(EXTRA_REFERENCE, reference)
            .putExtra(EXTRA_AMOUNT_MINOR, amountMinor)
            .putExtra(EXTRA_CURRENCY, currency)
            .putExtra(EXTRA_PAYEE, payee)

    companion object {
        private const val EXTRA_REFERENCE = "dev.test.payment.extra.REFERENCE"
        private const val EXTRA_AMOUNT_MINOR = "dev.test.payment.extra.AMOUNT_MINOR"
        private const val EXTRA_CURRENCY = "dev.test.payment.extra.CURRENCY"
        private const val EXTRA_PAYEE = "dev.test.payment.extra.PAYEE"

        /** `null` unless [arguments] is a map with all four fields of the right types. */
        fun fromWire(arguments: Any?): StartArgs? {
            val map = arguments as? Map<*, *> ?: return null
            return StartArgs(
                reference = map["reference"] as? String ?: return null,
                // The codec sends a Dart int as Integer or Long depending on its magnitude.
                amountMinor = (map["amountMinor"] as? Number)?.toLong() ?: return null,
                currency = map["currency"] as? String ?: return null,
                payee = map["payee"] as? String ?: return null,
            )
        }

        fun readFrom(intent: Intent): StartArgs? {
            if (!intent.hasExtra(EXTRA_AMOUNT_MINOR)) return null
            return StartArgs(
                reference = intent.getStringExtra(EXTRA_REFERENCE) ?: return null,
                amountMinor = intent.getLongExtra(EXTRA_AMOUNT_MINOR, 0),
                currency = intent.getStringExtra(EXTRA_CURRENCY) ?: return null,
                payee = intent.getStringExtra(EXTRA_PAYEE) ?: return null,
            )
        }
    }
}
```

(`writeTo`/`readFrom` touch `Intent` and are only called on a device. The JVM tests use `fromWire` alone.)

- [ ] **Step 5: Implement the state holder**

`kotlin/payment/PaymentJobStateHolder.kt`:
```kotlin
package dev.test.payment.payment

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The Payment Job's state, for the whole process (docs/architecture.md §10). The service is its
 * only writer after [tryStart]; the channel handler only reads, and clears a terminal snapshot
 * once it has been delivered. [shared] is the process-wide instance; the class is instantiable so
 * JVM tests get a fresh one each.
 */
class PaymentJobStateHolder {
    private val mutableState = MutableStateFlow<JobSnapshot?>(null)
    val state: StateFlow<JobSnapshot?> = mutableState.asStateFlow()

    /** Claims the holder for [jobId] as `running(0)` unless a job is already running. */
    fun tryStart(jobId: String): Boolean {
        while (true) {
            val current = mutableState.value
            if (current is JobSnapshot.Running) return false
            if (mutableState.compareAndSet(current, JobSnapshot.Running(jobId, 0))) return true
        }
    }

    /**
     * Moves the running job [JobSnapshot.jobId] forward to [snapshot]. Refused — returns false —
     * once that job has left `running`, so a terminal snapshot is never overwritten.
     */
    fun advance(snapshot: JobSnapshot): Boolean {
        while (true) {
            val current = mutableState.value
            if (current !is JobSnapshot.Running || current.jobId != snapshot.jobId) return false
            if (mutableState.compareAndSet(current, snapshot)) return true
        }
    }

    /** Undoes [tryStart] when the service could not be started. */
    fun abandon(jobId: String) {
        mutableState.compareAndSet(JobSnapshot.Running(jobId, 0), null)
    }

    /** The `current` reply. Reading a terminal snapshot delivers it, which clears it. */
    fun current(): JobSnapshot? = mutableState.value?.also { if (it.isTerminal) markDelivered(it) }

    /** Clears [snapshot] if it is still the current, terminal state — replay-until-delivered. */
    fun markDelivered(snapshot: JobSnapshot) {
        if (snapshot.isTerminal) mutableState.compareAndSet(snapshot, null)
    }

    companion object {
        val shared = PaymentJobStateHolder()
    }
}
```

`MutableStateFlow.compareAndSet` compares with `equals`. That is safe here: every snapshot is a data class, and a job's snapshots never repeat a value.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `kotlin tests`
Expected: 37 `PASSED` lines (19 + 5 + 3 + 10), `BUILD SUCCESSFUL`.

- [ ] **Step 7: Commit**

```bash
git add android/app/src
git commit -m "feat(android): add JobSnapshot, StartArgs and PaymentJobStateHolder"
```

---

### Task 18: Job simulation and notification specs

**Files:**
- Create: `kotlin/payment/PaymentJobSimulation.kt`, `kotlin/payment/PaymentJobNotifications.kt`
- Test: `test-kotlin/payment/PaymentJobSimulationTest.kt`, `test-kotlin/payment/PaymentJobNotificationsTest.kt`

- [ ] **Step 1: Write the failing tests**

`test-kotlin/payment/PaymentJobSimulationTest.kt`:
```kotlin
package dev.test.payment.payment

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PaymentJobSimulationTest {
    private val approved = StartArgs("PAY-1", amountMinor = 4200, currency = "USD", payee = "Acme")
    private val declined = approved.copy(amountMinor = 4299)
    private val now = { 1758000000000L }

    @Test
    fun `only amounts ending in 99 minor units are declined`() {
        assertTrue(PaymentJobSimulation.declines(99))
        assertTrue(PaymentJobSimulation.declines(4299))
        assertFalse(PaymentJobSimulation.declines(4200))
        assertFalse(PaymentJobSimulation.declines(9900))
    }

    @Test
    fun `an approved job runs until 100 then succeeds with the payment reference`() {
        assertEquals(JobSnapshot.Running("j", 95), PaymentJobSimulation.snapshotAt("j", approved, 95, now))
        assertEquals(
            JobSnapshot.Succeeded("j", "PAY-1", 1758000000000L),
            PaymentJobSimulation.snapshotAt("j", approved, 100, now),
        )
    }

    @Test
    fun `a declined job runs until 60 then fails as declined`() {
        assertEquals(JobSnapshot.Running("j", 55), PaymentJobSimulation.snapshotAt("j", declined, 55, now))
        assertEquals(
            JobSnapshot.Failed("j", PaymentFailure.DECLINED),
            PaymentJobSimulation.snapshotAt("j", declined, 60, now),
        )
    }

    @Test
    fun `the whole job takes 20 ticks of 250 ms`() {
        assertEquals(5_000L, (100 / PaymentJobSimulation.STEP_PERCENT) * PaymentJobSimulation.TICK_MS)
    }
}
```

`test-kotlin/payment/PaymentJobNotificationsTest.kt`:
```kotlin
package dev.test.payment.payment

import org.junit.Assert.assertEquals
import org.junit.Test

class PaymentJobNotificationsTest {
    @Test
    fun `a running job is an ongoing progress notification`() {
        assertEquals(
            NotificationSpec("Processing payment", "40%", progressPercent = 40, ongoing = true),
            PaymentJobNotifications.specFor(JobSnapshot.Running("j", 40)),
        )
    }

    @Test
    fun `success is a dismissible notification with the reference and no progress bar`() {
        assertEquals(
            NotificationSpec("Payment complete", "Reference PAY-1", progressPercent = null, ongoing = false),
            PaymentJobNotifications.specFor(JobSnapshot.Succeeded("j", "PAY-1", 0)),
        )
    }

    @Test
    fun `each failure has its own dismissible title`() {
        val titles =
            PaymentFailure.entries.map { PaymentJobNotifications.specFor(JobSnapshot.Failed("j", it)) }
        assertEquals(
            listOf("Payment declined", "Payment timed out", "Payment could not be processed"),
            titles.map { it.title },
        )
        titles.forEach {
            assertEquals(null, it.progressPercent)
            assertEquals(false, it.ongoing)
        }
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `kotlin tests`
Expected: `Unresolved reference` for `PaymentJobSimulation`, `NotificationSpec`, `PaymentJobNotifications`; `BUILD FAILED`.

- [ ] **Step 3: Implement**

`kotlin/payment/PaymentJobSimulation.kt`:
```kotlin
package dev.test.payment.payment

/**
 * The simulated processor (docs/architecture.md §5, §10): +5 % every 250 ms; an amount whose minor
 * units end in 99 is declined at 60 %; anything else succeeds at 100 %.
 */
object PaymentJobSimulation {
    const val TICK_MS = 250L
    const val STEP_PERCENT = 5
    const val DECLINE_AT_PERCENT = 60

    fun declines(amountMinor: Long): Boolean = amountMinor % 100 == 99L

    /** The snapshot once the job has reached [percent]. */
    fun snapshotAt(
        jobId: String,
        args: StartArgs,
        percent: Int,
        now: () -> Long,
    ): JobSnapshot =
        when {
            declines(args.amountMinor) && percent >= DECLINE_AT_PERCENT ->
                JobSnapshot.Failed(jobId, PaymentFailure.DECLINED)
            percent >= 100 -> JobSnapshot.Succeeded(jobId, args.reference, now())
            else -> JobSnapshot.Running(jobId, percent)
        }
}
```

The receipt reference is the Payment's own reference. The terminal snapshot *replaces* the 60 %/100 % progress update rather than following it. That keeps the service at four notification updates per second, under Android's rate limit, which silently drops notification updates beyond roughly five per second.

`kotlin/payment/PaymentJobNotifications.kt`:
```kotlin
package dev.test.payment.payment

/** What the Payment Job notification shows — plain data, so it is unit-testable on the JVM. */
data class NotificationSpec(
    val title: String,
    val text: String,
    /** `null` hides the progress bar. */
    val progressPercent: Int?,
    val ongoing: Boolean,
)

/** Pure builders for the progress and final notifications (docs/architecture.md §10.2). */
object PaymentJobNotifications {
    const val CHANNEL_ID = "payment_job"
    const val NOTIFICATION_ID = 4201

    fun progress(percent: Int): NotificationSpec =
        NotificationSpec("Processing payment", "$percent%", percent, ongoing = true)

    fun specFor(snapshot: JobSnapshot): NotificationSpec =
        when (snapshot) {
            is JobSnapshot.Running -> progress(snapshot.percent)
            is JobSnapshot.Succeeded ->
                NotificationSpec("Payment complete", "Reference ${snapshot.reference}", null, ongoing = false)
            is JobSnapshot.Failed ->
                NotificationSpec(titleFor(snapshot.failure), "Open the app to try again", null, ongoing = false)
        }

    private fun titleFor(failure: PaymentFailure): String =
        when (failure) {
            PaymentFailure.DECLINED -> "Payment declined"
            PaymentFailure.TIMED_OUT -> "Payment timed out"
            PaymentFailure.SERVICE_UNAVAILABLE -> "Payment could not be processed"
        }
}
```

The notification copy is not brand-specific: nothing in §6 asks for it, and the launcher label already carries the brand. Adding per-brand copy later means adding resources, not changing code.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `kotlin tests`
Expected: 44 `PASSED` lines, `BUILD SUCCESSFUL`. That is every JVM test this plan adds.

- [ ] **Step 5: Commit**

```bash
git add android/app/src
git commit -m "feat(android): add the Payment Job simulation and notification specs"
```

---

### Task 19: `PaymentJobService`, its notification renderer, `PaymentJobHandler`

Android-bound, so no JVM tests. Task 21 runs approved, declined and re-attached jobs through it on a device.

**Files:**
- Create: `kotlin/payment/NotificationRenderer.kt`, `kotlin/payment/PaymentJobService.kt`, `kotlin/payment/PaymentJobHandler.kt`, `android/app/src/main/res/drawable/ic_stat_payment.xml`
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: The notification icon**

`android/app/src/main/res/drawable/ic_stat_payment.xml` (status-bar icons must be monochrome; the launcher icon is not):
```xml
<?xml version="1.0" encoding="utf-8"?>
<!-- Payment Job notification small icon (Material "credit_card", Apache-2.0). Status-bar icons must be monochrome. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M20,4H4C2.89,4 2,4.89 2,6v12c0,1.11 0.89,2 2,2h16c1.11,0 2,-0.89 2,-2V6C22,4.89 21.11,4 20,4zM20,18H4v-6h16V18zM20,8H4V6h16V8z" />
</vector>
```

- [ ] **Step 2: The renderer**

`kotlin/payment/NotificationRenderer.kt`:
```kotlin
package dev.test.payment.payment

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import androidx.core.app.NotificationCompat
import dev.test.payment.R

/** Turns a [NotificationSpec] into a real notification. Android-only; not unit-tested. */
internal class NotificationRenderer(private val context: Context) {
    private val manager = context.getSystemService(NotificationManager::class.java)

    /** `IMPORTANCE_LOW`: silent, no heads-up, still in the status bar. minSdk 26 — no version gate. */
    fun ensureChannel() {
        manager.createNotificationChannel(
            NotificationChannel(
                PaymentJobNotifications.CHANNEL_ID,
                "Payment processing",
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }

    fun render(spec: NotificationSpec): Notification =
        NotificationCompat.Builder(context, PaymentJobNotifications.CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_payment)
            .setContentTitle(spec.title)
            .setContentText(spec.text)
            .setOngoing(spec.ongoing)
            .setAutoCancel(!spec.ongoing)
            .setOnlyAlertOnce(true)
            .setContentIntent(launchIntent())
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .apply { spec.progressPercent?.let { setProgress(100, it, false) } }
            .build()

    /** Silently dropped by the system when POST_NOTIFICATIONS is denied — the job is unaffected. */
    fun show(spec: NotificationSpec) {
        manager.notify(PaymentJobNotifications.NOTIFICATION_ID, render(spec))
    }

    /** Tapping opens the app; the root route re-attaches through `current` (§10). */
    private fun launchIntent(): PendingIntent? =
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            PendingIntent.getActivity(
                context,
                0,
                it,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }
}
```

The platform `NotificationManager` is used, not `NotificationManagerCompat`. The compat `notify` is annotated `@RequiresPermission(POST_NOTIFICATIONS)` and would trip Android lint, but a denied permission is a supported state here (§10, scenario 8).

- [ ] **Step 3: The service**

`kotlin/payment/PaymentJobService.kt`:
```kotlin
package dev.test.payment.payment

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The simulated Payment Job, as a `shortService` foreground service (docs/architecture.md §10).
 * Started, never bound. Writes every snapshot to [PaymentJobStateHolder]; the three teardown
 * writers — the ticker's terminal tick, [onTimeout], [onDestroy] — all go through
 * [PaymentJobStateHolder.advance], so whichever lands first wins and the others are no-ops.
 * Stops with the latest start id, so a retry that starts a new job while this instance is still
 * winding down is not dropped.
 */
class PaymentJobService : Service() {
    private val holder = PaymentJobStateHolder.shared
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private lateinit var notifications: NotificationRenderer
    /** The job this instance is ticking; `null` once it has finished. Main thread only. */
    private var jobId: String? = null
    private var lastStartId = 0

    override fun onCreate() {
        super.onCreate()
        notifications = NotificationRenderer(this)
        notifications.ensureChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        lastStartId = startId
        // startForeground must run within 5 s of startForegroundService, whatever happens next.
        ServiceCompat.startForeground(
            this,
            PaymentJobNotifications.NOTIFICATION_ID,
            notifications.render(PaymentJobNotifications.progress(0)),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE
            } else {
                0
            },
        )
        val newJobId = intent?.getStringExtra(EXTRA_JOB_ID)
        val args = intent?.let(StartArgs::readFrom)
        when {
            // The holder admits one running job at a time, so a ticking instance never gets a second.
            jobId != null -> Unit
            newJobId != null && args != null -> {
                jobId = newJobId
                scope.launch { tick(newJobId, args) }
            }
            else -> stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    /** API 34's `shortService` timeout. */
    override fun onTimeout(startId: Int) = timedOut()

    /** API 35+'s typed timeout; overridden too so the outcome doesn't depend on which one the OS calls. */
    override fun onTimeout(startId: Int, fgsType: Int) = timedOut()

    override fun onDestroy() {
        jobId?.let { holder.advance(JobSnapshot.Failed(it, PaymentFailure.SERVICE_UNAVAILABLE)) }
        scope.cancel()
        super.onDestroy()
    }

    private suspend fun tick(jobId: String, args: StartArgs) {
        var percent = 0
        while (true) {
            delay(PaymentJobSimulation.TICK_MS)
            percent += PaymentJobSimulation.STEP_PERCENT
            val snapshot = PaymentJobSimulation.snapshotAt(jobId, args, percent, System::currentTimeMillis)
            if (!holder.advance(snapshot)) return
            if (snapshot.isTerminal) {
                withContext(Dispatchers.Main) { finish(snapshot) }
                return
            }
            notifications.show(PaymentJobNotifications.specFor(snapshot))
        }
    }

    private fun timedOut() {
        val snapshot = jobId?.let { JobSnapshot.Failed(it, PaymentFailure.TIMED_OUT) }
        if (snapshot != null && holder.advance(snapshot)) finish(snapshot) else stopSelf(lastStartId)
    }

    /** Final notification, detached so it outlives the service, then stop. */
    private fun finish(snapshot: JobSnapshot) {
        notifications.show(PaymentJobNotifications.specFor(snapshot))
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_DETACH)
        jobId = null
        stopSelf(lastStartId)
    }

    companion object {
        private const val EXTRA_JOB_ID = "dev.test.payment.extra.JOB_ID"

        fun intent(context: Context, jobId: String, args: StartArgs): Intent =
            args.writeTo(Intent(context, PaymentJobService::class.java).putExtra(EXTRA_JOB_ID, jobId))
    }
}
```

Checked against §10.3's scenario table:
- 1 and 2: the ticker runs to its terminal snapshot, then `finish` posts the final notification and detaches it.
- 6: `timedOut` handles the `shortService` timeout.
- 7: `onDestroy` while a job is still ticking writes `failed(serviceUnavailable)`.
- 9: the holder's `tryStart` refuses a second job.
- 10: handled in the handler below.
- 13: `markDelivered` clears the delivered terminal snapshot.

- [ ] **Step 4: The handler**

`kotlin/payment/PaymentJobHandler.kt`:
```kotlin
package dev.test.payment.payment

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import dev.test.payment.bridge.ChannelHandler
import dev.test.payment.bridge.ChannelNames
import dev.test.payment.bridge.ErrorCodes
import dev.test.payment.bridge.MainThreadResult
import dev.test.payment.bridge.MainThreadSink
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * `payment.job` + `payment.job/events` (docs/architecture.md §9, §10). Reads
 * [PaymentJobStateHolder]; writes it only through `tryStart`/`abandon` and delivered-once
 * clearing. The event stream is replay-1: a new listener gets the current snapshot first, and a
 * terminal snapshot is cleared once it has been emitted.
 */
class PaymentJobHandler(
    private val context: Context,
    private val activity: () -> Activity?,
    private val scope: CoroutineScope,
    private val holder: PaymentJobStateHolder = PaymentJobStateHolder.shared,
) : ChannelHandler, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var collector: Job? = null
    private val pendingPermissionReplies = mutableListOf<MethodChannel.Result>()

    override fun attach(messenger: BinaryMessenger) {
        methodChannel = MethodChannel(messenger, ChannelNames.PAYMENT_JOB).also { it.setMethodCallHandler(this) }
        eventChannel = EventChannel(messenger, ChannelNames.PAYMENT_JOB_EVENTS).also { it.setStreamHandler(this) }
    }

    override fun detach() {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        collector?.cancel()
        collector = null
        pendingPermissionReplies.clear()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val reply = MainThreadResult(result)
        when (call.method) {
            "ensureNotificationPermission" -> ensureNotificationPermission(reply)
            "start" -> start(call, reply)
            "current" -> reply.success(holder.current()?.toWire())
            else -> reply.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val sink = MainThreadSink(events)
        collector?.cancel()
        collector =
            scope.launch {
                holder.state.filterNotNull().collect { snapshot ->
                    sink.success(snapshot.toWire())
                    holder.markDelivered(snapshot)
                }
            }
    }

    override fun onCancel(arguments: Any?) {
        collector?.cancel()
        collector = null
    }

    /** Fed by `MainActivity.onRequestPermissionsResult`. Returns whether the request was ours. */
    fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return false
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        pendingPermissionReplies.forEach { it.success(if (granted) GRANTED else DENIED) }
        pendingPermissionReplies.clear()
        return true
    }

    private fun ensureNotificationPermission(reply: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return reply.success(NOT_REQUIRED)
        val permission = Manifest.permission.POST_NOTIFICATIONS
        if (ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED) {
            return reply.success(GRANTED)
        }
        if (pendingPermissionReplies.isNotEmpty()) {
            pendingPermissionReplies += reply
            return
        }
        // One prompt per process: a denial is remembered, never re-asked.
        if (promptedThisProcess) return reply.success(DENIED)
        val activity = activity() ?: return reply.error(ErrorCodes.NO_ACTIVITY, "No Activity to ask from", null)
        promptedThisProcess = true
        pendingPermissionReplies += reply
        ActivityCompat.requestPermissions(activity, arrayOf(permission), NOTIFICATION_PERMISSION_REQUEST)
    }

    private fun start(call: MethodCall, reply: MethodChannel.Result) {
        val args =
            StartArgs.fromWire(call.arguments)
                ?: return reply.error(
                    ErrorCodes.BAD_ARGUMENTS,
                    "start expects {reference, amountMinor, currency, payee}",
                    null,
                )
        val jobId = "j-${UUID.randomUUID()}"
        if (!holder.tryStart(jobId)) {
            return reply.error(ErrorCodes.ALREADY_RUNNING, "A Payment Job is already running", null)
        }
        try {
            ContextCompat.startForegroundService(context, PaymentJobService.intent(context, jobId, args))
        } catch (e: RuntimeException) {
            // IllegalStateException (incl. ForegroundServiceStartNotAllowedException) or SecurityException.
            holder.abandon(jobId)
            return reply.error(ErrorCodes.SERVICE_START_FAILED, e.message, null)
        }
        reply.success(mapOf("jobId" to jobId))
    }

    private companion object {
        const val NOTIFICATION_PERMISSION_REQUEST = 4202
        const val GRANTED = "granted"
        const val DENIED = "denied"
        const val NOT_REQUIRED = "notRequired"

        @Volatile
        var promptedThisProcess = false
    }
}
```

`promptedThisProcess` lives in the companion because a handler is per engine, while "one prompt per process" (§9) outlives an engine. The collector runs on the registry's `Dispatchers.Main.immediate` scope, so `MainThreadSink` never actually posts. It is still there, so the threading guarantee doesn't depend on which scope the collector happens to use.

- [ ] **Step 5: Declare the service and its permissions**

In `android/app/src/main/AndroidManifest.xml`:

After the `DETECT_SCREEN_RECORDING` line (Task 15), add:
```xml
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

Inside `<application>`, after the closing `</activity>` tag and before the `flutterEmbedding` comment, add:
```xml
        <!-- The simulated Payment Job, docs/architecture.md §10. -->
        <service
            android:name=".payment.PaymentJobService"
            android:exported="false"
            android:foregroundServiceType="shortService"/>
```

`shortService` needs no typed `FOREGROUND_SERVICE_*` permission (`docs/research/foreground-service-compliance.md`).

- [ ] **Step 6: Compile and commit**

Run: `kotlin compile` — Expected: `BUILD SUCCESSFUL`, no `e:` lines.

```bash
git add android/app/src
git commit -m "feat(android): add PaymentJobService, its notification renderer and PaymentJobHandler"
```

---

### Task 20: `ChannelRegistry`, `MainActivity`, full Android verification

**Files:**
- Create: `kotlin/bridge/ChannelRegistry.kt`
- Modify: `kotlin/MainActivity.kt`

- [ ] **Step 1: The registry**

`kotlin/bridge/ChannelRegistry.kt`:
```kotlin
package dev.test.payment.bridge

import android.app.Activity
import android.content.Context
import dev.test.payment.app.AppInfoHandler
import dev.test.payment.payment.PaymentJobHandler
import dev.test.payment.security.SecurityEnvironmentHandler
import dev.test.payment.window.WindowHandler
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

/**
 * Owns the four channel handlers and the coroutine scope their work runs in, for one Flutter
 * engine. `MainActivity` delegates to exactly [register], [dispose] and [onPermissionResult]
 * (docs/architecture.md §9).
 */
class ChannelRegistry(context: Context, activity: () -> Activity?) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val paymentJob = PaymentJobHandler(context, activity, scope)
    private val handlers: List<ChannelHandler> =
        listOf(
            SecurityEnvironmentHandler(context, scope),
            WindowHandler(activity),
            paymentJob,
            AppInfoHandler(context),
        )

    fun register(messenger: BinaryMessenger) = handlers.forEach { it.attach(messenger) }

    fun dispose() {
        handlers.forEach { it.detach() }
        scope.cancel()
    }

    fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean =
        paymentJob.onPermissionResult(requestCode, grantResults)
}
```

- [ ] **Step 2: Wire it into `MainActivity`**

Replace `kotlin/MainActivity.kt`:
```kotlin
package dev.test.payment

import dev.test.payment.bridge.ChannelRegistry
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var channels: ChannelRegistry? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channels =
            ChannelRegistry(applicationContext) { takeUnless { it.isFinishing || it.isDestroyed } }
                .also { it.register(flutterEngine.dartExecutor.binaryMessenger) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channels?.dispose()
        channels = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        channels?.onPermissionResult(requestCode, grantResults)
    }
}
```

Handlers get the application context, plus a provider that returns the Activity only while it is alive. A handler never holds the Activity itself, and a call after `onDestroy` gets `noActivity`.

- [ ] **Step 3: Check the manifest reads exactly like this**

`android/app/src/main/AndroidManifest.xml`:
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Owned by the native channel contract, docs/architecture.md §9. -->
    <uses-permission android:name="android.permission.DETECT_SCREEN_RECORDING"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>

    <application
        android:label="@string/app_name"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:appCategory="productivity">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <!-- Specifies an Android theme to apply to this Activity as soon as
                 the Android process has started. This theme is visible to the user
                 while the Flutter UI initializes. After that, this theme continues
                 to determine the Window background behind the Flutter UI. -->
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <!-- The simulated Payment Job, docs/architecture.md §10. -->
        <service
            android:name=".payment.PaymentJobService"
            android:exported="false"
            android:foregroundServiceType="shortService"/>
        <!-- Don't delete the meta-data below.
             This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <!-- Required to query activities that can process text, see:
         https://developer.android.com/training/package-visibility and
         https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT.

         In particular, this is used by the Flutter engine in io.flutter.plugin.text.ProcessTextPlugin. -->
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
        <!-- Root-manager packages checked by RootChecks.ROOT_PACKAGES (targetSdk 36 package
             visibility). Kept in sync by RootPackagesManifestTest. -->
        <package android:name="com.topjohnwu.magisk"/>
        <package android:name="eu.chainfire.supersu"/>
        <package android:name="com.noshufou.android.su"/>
        <package android:name="com.koushikdutta.superuser"/>
        <package android:name="me.weishu.kernelsu"/>
    </queries>
</manifest>
```

If it differs, fix it to match.

- [ ] **Step 4: Run every JVM test, forcing a re-run**

Run: `(cd android && ./gradlew :app:testRetailDebugUnitTest --rerun-tasks --console=plain) | grep -c PASSED`
Expected: `44`. Then run `kotlin tests` again and confirm no `FAILED` line and `BUILD SUCCESSFUL`.

- [ ] **Step 5: Android lint**

Run: `(cd android && ./gradlew :app:lintRetailDebug --console=plain)`
Then: `tail -1 build/app/reports/lint-results-retailDebug.txt`
Expected: `0 errors, N warnings`. The warnings are "newer version available" notices and the template's `drawable-v21` folder being obsolete at minSdk 26. None point at `kotlin/dev/test/payment/`. The report sits under the repo-root `build/` because `android/build.gradle.kts` redirects Gradle's build directory there.

- [ ] **Step 6: Both flavors build**

Run: `~/fvm/versions/3.44.6/bin/flutter build apk --debug --flavor retail` — Expected: `✓ Built build/app/outputs/flutter-apk/app-retail-debug.apk`
Run: `~/fvm/versions/3.44.6/bin/flutter build apk --debug --flavor utility` — Expected: `✓ Built build/app/outputs/flutter-apk/app-utility-debug.apk`

- [ ] **Step 7: Commit**

```bash
git add android/app/src
git commit -m "feat(android): register the channel handlers from MainActivity via ChannelRegistry"
```

---

## Part C — End to end

### Task 21: On-device bridge smoke test

The JVM tests cover the pure Kotlin, and the Dart contract tests cover the adapters against mocked channels. This test is the only place the two sides actually talk: real `MethodChannel`s, the real foreground service, the real window flag.

**Files:**
- Modify: `pubspec.yaml`, `pubspec.lock` (via `pub add`)
- Create: `integration_test/native_bridge_test.dart`

- [ ] **Step 1: Add the `integration_test` dev dependency**

Run: `~/fvm/versions/3.44.6/bin/flutter pub add 'dev:integration_test:{"sdk":"flutter"}'`
Expected: `pubspec.yaml`'s `dev_dependencies` gains:
```yaml
  integration_test:
    sdk: flutter
```
(`flutter pub add --dev integration_test --sdk=flutter` is rejected by this pub version; the `dev:` prefix form above is the one that works.)

- [ ] **Step 2: Write the test**

`integration_test/native_bridge_test.dart`:
```dart
import 'dart:developer';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:payment_module/bootstrap/channel_app_info.dart';
import 'package:payment_module/bootstrap/channel_display_mode.dart';
import 'package:payment_module/core/money.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/payment/di.dart';
import 'package:payment_module/features/payment/payment.dart';
import 'package:payment_module/features/security_guard/di.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

/// On-device smoke test of the real Kotlin bridge: every channel of docs/architecture.md §9, end to
/// end. Not part of `flutter test`, which only runs test/. `flutter test` uninstalls the app when
/// it finishes, so install and pre-grant POST_NOTIFICATIONS before every run — otherwise the job
/// waits on the system permission prompt:
///
///     flutter build apk --debug --flavor retail
///     adb install -r build/app/outputs/flutter-apk/app-retail-debug.apk
///     adb shell pm grant dev.test.payment.retail android.permission.POST_NOTIFICATIONS
///     flutter test integration_test/native_bridge_test.dart --flavor retail -d <device-id>
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final getIt = GetIt.instance;

  setUpAll(() {
    registerSecurityModule(getIt);
    registerPaymentModule(getIt);
  });

  Payment payment(int amountMinor) => Payment(
    reference: 'PAY-IT-$amountMinor',
    amount: Money(amountMinor: amountMinor, currency: 'USD'),
    payee: 'Integration Test',
    lineItems: const [],
  );

  testWidgets('app · buildInfo reports the retail flavor', (tester) async {
    final info = await ChannelAppInfo().buildInfo();

    expect(info.flavor, 'retail');
    expect(info.applicationId, 'dev.test.payment.retail');
    expect(info.sdkInt, greaterThanOrEqualTo(26));
  });

  testWidgets('window · preferHighRefreshRate names a mode', (tester) async {
    final preference = await ChannelDisplayMode().preferHighRefreshRate();
    log('preferHighRefreshRate: $preference', name: 'native_bridge_test');

    expect(preference!.refreshRate, greaterThan(0));
  });

  testWidgets('window · setSecure sets and clears the flag', (tester) async {
    await getIt<SecureWindow>().setSecure(true);
    await getIt<SecureWindow>().setSecure(false);
  });

  testWidgets('security.environment publishes one assessment per threat', (
    tester,
  ) async {
    final environment = getIt<SecurityEnvironment>();
    final firstPosture = environment.posture.first;
    await environment.assess();

    final posture = await firstPosture.timeout(const Duration(seconds: 10));
    log(
      'posture: ${posture.classification} $posture',
      name: 'native_bridge_test',
    );

    expect(
      posture.assessments.map((a) => a.kind).toSet(),
      ThreatKind.values.toSet(),
    );
  });

  testWidgets('payment.job runs an approved payment to Succeeded', (
    tester,
  ) async {
    final processor = getIt<PaymentProcessor>();

    final progress = await processor
        .start(payment(4200))
        .toList()
        .timeout(const Duration(seconds: 20));

    expect(progress.first, isA<Running>());
    expect(
      progress.whereType<Running>().map((r) => r.percent),
      everyElement(lessThan(100)),
    );
    expect(
      progress.last,
      isA<Succeeded>().having(
        (s) => s.receipt.reference,
        'reference',
        'PAY-IT-4200',
      ),
    );
    // The terminal snapshot was delivered on the stream, so nothing is left in flight.
    expect(await processor.inFlight(), isNull);
  });

  testWidgets('payment.job declines an amount ending in 99 at 60 %', (
    tester,
  ) async {
    final processor = getIt<PaymentProcessor>();

    final progress = await processor
        .start(payment(4299))
        .toList()
        .timeout(const Duration(seconds: 20));

    expect(progress.last, const Failed(PaymentFailure.declined));
    expect(
      progress.whereType<Running>().map((r) => r.percent),
      everyElement(lessThan(60)),
    );
  });

  testWidgets('payment.job re-attaches to a running job through current', (
    tester,
  ) async {
    final processor = getIt<PaymentProcessor>();
    final started = processor.start(payment(4200));
    // Take the first snapshot only, then let go of the stream — as a disposed engine would.
    expect(await started.first, isA<Running>());

    final inFlight = await processor.inFlight();

    expect(inFlight, isNotNull);
    final rest = await inFlight!.toList().timeout(const Duration(seconds: 20));
    expect(rest.last, isA<Succeeded>());
  });
}
```

The tests do not assert the posture's *classification*: an emulator may legitimately be Compromised or Unverified (§15). The test logs it instead. The three payment tests run back to back on purpose. That is exactly the "retry while the previous service instance winds down" case decision 10 guards against.

- [ ] **Step 3: Analyze**

Run: `dart analyze` — Expected: `No issues found!` (the analyzer covers `integration_test/` too).

- [ ] **Step 4: Get a device**

Run: `adb devices`
Expected: at least one line ending in `device`, e.g. `emulator-5554	device`. If there is none, list emulators with `~/Library/Android/sdk/emulator/emulator -list-avds`, start one in the background with `~/Library/Android/sdk/emulator/emulator -avd <name>`, and wait with `adb wait-for-device`. Use its id as `<device-id>` below, and note its API level: `adb -s <device-id> shell getprop ro.build.version.sdk`.

- [ ] **Step 5: Install and pre-grant, then run**

`flutter test` installs over an existing install (keeping granted permissions) and uninstalls when it finishes, so these four commands go together every time:

```bash
~/fvm/versions/3.44.6/bin/flutter build apk --debug --flavor retail
~/Library/Android/sdk/platform-tools/adb -s <device-id> install -r build/app/outputs/flutter-apk/app-retail-debug.apk
~/Library/Android/sdk/platform-tools/adb -s <device-id> shell pm grant dev.test.payment.retail android.permission.POST_NOTIFICATIONS
~/fvm/versions/3.44.6/bin/flutter test integration_test/native_bridge_test.dart --flavor retail -d <device-id>
```

(On API ≤ 32, `POST_NOTIFICATIONS` is not a runtime permission: skip the `pm grant` line, since it errors and isn't needed. The handler returns `notRequired`.)

Expected: seven test lines and `+7: All tests passed!`, taking about 15 s. The three payment tests take about 5 s, 3 s and 5 s.

If a payment test hangs until its 20 s timeout, the permission prompt is showing on the device: the grant didn't stick. Repeat the four commands. A `MissingPluginException`-flavoured `ClientException` means a channel name drifted, and Tasks 2 and 12 should have caught that.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock integration_test
git commit -m "test(integration): add the on-device native bridge smoke test"
```

---

### Task 22: Fold the decisions back into the architecture; final verification

**Files:**
- Modify: `docs/architecture.md`
- Create: `docs/verification/2026-09-17-native-bridge-verification.md`

- [ ] **Step 1: Update `docs/architecture.md`**

Apply each replacement below with an exact-match edit. Every **old** block appears in the file verbatim, once.

**1. Status line.** Old:
```text
**Status**: approved architecture; implementation not started. Produced by the wayfinder map at
```
New:
```text
**Status**: approved architecture; Plans 1–4 of five implemented (`docs/superpowers/plans/`). Produced by the wayfinder map at
```

**2. §3.1 layout block.** Seven one-line replacements and one insertion:

| Old line | New line |
|---|---|
| `├── contract/fixtures/*.json     # channel payload fixtures shared by Dart and Kotlin tests` | `├── contract/fixtures/*.json     # channel names + payload fixtures shared by Dart and Kotlin tests` |
| `│   ├── bridge/                  # ChannelRegistry · MainThreadResult · MainThreadSink` | `│   ├── bridge/                  # Channels (names, error codes, ChannelHandler) · ChannelRegistry · MainThread · MainThreadResult · MainThreadSink` |
| `│   ├── security/                # SecurityEnvironmentHandler · RootChecks · ScreenRecordingMonitor` | `│   ├── security/                # SecurityEnvironmentHandler · PostureSnapshot · RootChecks · DeviceRootSignals · ScreenRecordingMonitor` |
| `│   ├── window/                  # WindowHandler` | `│   ├── window/                  # WindowHandler · DisplayModes` |
| `│   ├── payment/                 # PaymentJobHandler · PaymentJobService · PaymentJobStateHolder · PaymentJobNotifications` | `│   ├── payment/                 # PaymentJobHandler · PaymentJobService · PaymentJobStateHolder · JobSnapshot · StartArgs · PaymentJobSimulation · PaymentJobNotifications · NotificationRenderer` |
| `│   ├── support/fakes/           # fake_security_environment · fake_secure_window · fake_payment_processor · fake_payment_repository` | `│   ├── support/                 # contract_fixtures.dart · fakes/{fake_security_environment, fake_secure_window, fake_payment_processor, fake_payment_repository}` |
| `│   ├── core/ · brand_engine/ · features/{security_guard, payment}/   # mirror lib/` | `│   ├── core/ · brand_engine/ · native_bridge/ · bootstrap/ · features/{security_guard, payment}/   # mirror lib/` |
| `└── integration_test/perf_test.dart` | `└── integration_test/            # perf_test.dart · native_bridge_test.dart (on-device bridge smoke test)` |

Insert, directly after the line that starts `│   ├── core/                    # Flutter-free shared kernel`:
```text
│   ├── native_bridge/           # native_bridge.dart (barrel) · src/{native_channels, invoke_native, wire_map}.dart — channel plumbing (Flutter), depends on core only
```

**3. §3.1 DAG paragraph.** Old:
```text
**Modules and their dependency DAG** (lint-enforced, §3.3): `app / brands / bootstrap → *` · `features/payment → core,
brand_engine, features/security_guard` · `features/security_guard → core, brand_engine` · `brand_engine → core` ·
`core → (nothing, not even Flutter)`.
```
New:
```text
**Modules and their dependency DAG** (lint-enforced, §3.3): `app / brands / bootstrap → *` · `features/payment → core,
brand_engine, native_bridge, features/security_guard` · `features/security_guard → core, brand_engine, native_bridge` ·
`native_bridge → core` · `brand_engine → core` · `core → (nothing, not even Flutter)`.
```

**4. §3.3 yaml block.** Replace the two lines starting `    core_depends_on_nothing:` and `    engine_knows_no_features:` with:
```text
    core_depends_on_nothing:   { target: "package:payment_module/core/**.dart",         from: "package:payment_module/{brand_engine,native_bridge,features,app,brands,bootstrap}/**.dart", except: [] }
    engine_knows_no_features:  { target: "package:payment_module/brand_engine/**.dart", from: "package:payment_module/{native_bridge,features,app,brands,bootstrap}/**.dart",             except: [] }
    native_bridge_depends_on_core_only: { target: "package:payment_module/native_bridge/**.dart", from: "package:payment_module/{brand_engine,features,app,brands,bootstrap}/**.dart", except: [] }
    native_bridge_via_barrel:  { target: "package:payment_module/{features,bootstrap}/**.dart", from: "package:payment_module/native_bridge/src/**.dart", except: [] }
```

**5. §4.** After the `lib/brand_engine` block's last line (`  deletion  passes: theme building + scope + lookup would reappear in every feature`) and the blank line after it, insert this block followed by a blank line:
```text
lib/native_bridge  (barrel native_bridge.dart; internals under src/; Flutter, depends on core only)
  exports   NativeChannels (the six §9 names) · invokeNative + nativeReplyTimeout (§9's wire → Dart table) · WireMap (typed payload reads)
  adapters  none — the plumbing the channel adapters in security_guard, payment and bootstrap share
  tests     names vs contract/fixtures/channels.json · error-code and timeout mapping · WireMap failure modes
  deletion  passes: the timeout + error mapping would be copied into five adapters; core cannot hold it (Flutter-free)
```
In the `lib/features/security_guard` block, old:
```text
  registration  registerSecurityModule(getIt, {environment, window})
```
New:
```text
  registration  registerSecurityModule(getIt, {environment, window}) — channel adapters by default, + SecureWindowController
```

**6. §9 Dart adapters.** Old (one line):
```text
**Dart adapters** (data layer; placement confirmed in ticket 13): `ChannelSecurityEnvironment implements SecurityEnvironment` · `ChannelWindow implements SecureWindow` (+ `preferHighRefreshRate`, used by `app` bootstrap only — infrastructure, not a domain port) · `ChannelPaymentProcessor implements PaymentProcessor` (`start()` = `ensureNotificationPermission` then `start`; per-job stream filtered by `jobId`; `inFlight` = `current()` + stream) · `ChannelAppInfo` → `BuildInfo` for the debug `flavor == BRAND` assertion.
```
New:
```text
**Dart adapters** (data layer; placement confirmed in ticket 13; all built on `lib/native_bridge`): `ChannelSecurityEnvironment implements SecurityEnvironment` · `ChannelSecureWindow implements SecureWindow` · `ChannelPaymentProcessor implements PaymentProcessor` (`start()` = `ensureNotificationPermission` then `start`; per-job stream filtered by `jobId`; `inFlight` = `current()` + stream) · in `lib/bootstrap` (infrastructure, not domain ports): `ChannelDisplayMode` (`window · preferHighRefreshRate`) and `ChannelAppInfo` → `BuildInfo` for the debug `flavor == BRAND` assertion. `assess` acks as soon as an assessment is running; a snapshot is published once the root result and the recorder state are both known.
```

**7. §9 Kotlin layout.** Old (one line):
```text
**Kotlin layout** `dev.test.payment/`: `MainActivity.kt` · `bridge/{ChannelRegistry, MainThreadResult, MainThreadSink}.kt` · `security/{SecurityEnvironmentHandler, RootChecks, ScreenRecordingMonitor}.kt` · `window/WindowHandler.kt` · `payment/{PaymentJobHandler, PaymentJobService, PaymentJobStateHolder}.kt` · `app/AppInfoHandler.kt`.
```
New:
```text
**Kotlin layout** `dev.test.payment/`: `MainActivity.kt` · `bridge/{Channels, ChannelRegistry, MainThread, MainThreadResult, MainThreadSink}.kt` · `security/{SecurityEnvironmentHandler, PostureSnapshot, RootChecks, DeviceRootSignals, ScreenRecordingMonitor}.kt` · `window/{WindowHandler, DisplayModes}.kt` · `payment/{PaymentJobHandler, PaymentJobService, PaymentJobStateHolder, JobSnapshot, StartArgs, PaymentJobSimulation, PaymentJobNotifications, NotificationRenderer}.kt` · `app/AppInfoHandler.kt`. The pure halves (payload builders, the root threshold, the state holder, the simulation, notification specs) are JVM-tested; the Android-bound halves are exercised on a device.
```

**8. §9 fixtures.** Old:
```text
**Fixtures** `contract/fixtures/`: `posture.secure`,
```
New:
```text
**Fixtures** `contract/fixtures/`: `channels` (the six names), `posture.secure`,
```

**9. §10 completion.** Old:
```text
state and calls `stopForeground(STOP_FOREGROUND_DETACH)` + `stopSelf()` so the outcome persists in the shade until dismissed.
```
New:
```text
state and calls `stopForeground(STOP_FOREGROUND_DETACH)` + `stopSelf(lastStartId)` (never a bare `stopSelf()`, which could drop a retry's start) so the outcome persists in the shade until dismissed.
```

**10. §10 timeout.** Old:
```text
`onTimeout(startId)` (API 34 overload; verify the API 35 two-arg default delegates) → `failed(timedOut)`; `onDestroy` while
```
New:
```text
`onTimeout(startId)` (API 34) and `onTimeout(startId, fgsType)` (API 35) are both overridden → `failed(timedOut)`; `onDestroy` while
```

**11. §10.2 table row.** Old:
```text
| `PaymentJobStateHolder` (`object`) |
```
New:
```text
| `PaymentJobStateHolder` (class; one process-wide `shared` instance) |
```

**12. §10.2 duplicate paragraph.** §10.2 has two consecutive paragraphs that start with ``**Dart `ChannelPaymentProcessor`**:``. Delete the first, shorter one and the blank line after it. It is this line:
```text
**Dart `ChannelPaymentProcessor`**: `start(payment)` → per-job stream = events `.where(jobId).map(parse)`, completing inclusively on a terminal state. `inFlight()` → `current()`: `null` → `null`; terminal → `Stream.value(parsed)`; running → the filtered stream (replay-1 supplies the current snapshot).
```

**13. §14 Kotlin row.** Old (one line):
```text
| Kotlin (JVM) | `MainThreadResult` / `MainThreadSink` hop to main · payload builders against `contract/fixtures/` · `PaymentJobNotifications` builders · `RootChecks` threshold logic with injected signals | no Robolectric, no instrumented tests |
```
New (two lines):
```text
| Kotlin (JVM) | `MainThreadResult` / `MainThreadSink` hop to main · channel names and payload builders against `contract/fixtures/` · `PaymentJobNotifications` specs · `RootChecks` threshold with injected signals and the `/proc/mounts` parser · `<queries>` ↔ `RootChecks.ROOT_PACKAGES` · `PaymentJobStateHolder` · `PaymentJobSimulation` · `DisplayModes` choice | no Robolectric, no instrumented tests |
| device | `integration_test/native_bridge_test.dart`: every channel through the real Dart adapters and Kotlin handlers (flavor, refresh rate, secure flag, posture, approved / declined / re-attached jobs) | none — a real device or emulator, `POST_NOTIFICATIONS` pre-granted |
```

**14. §17, two items.** Old:
```text
  runs it. `flutter build apk --flavor retail|utility` remains on the scaffold's smoke-test list.
```
New:
```text
  runs it. `flutter build apk --flavor retail|utility` builds both flavors (verified in Plan 4).
```
Old:
```text
- `onTimeout` overloads differ between API 34 and 35 — override the one-arg form and verify delegation.
```
New:
```text
- `onTimeout` overloads differ between API 34 and 35 — both are overridden with the same body (Plan 4), so neither OS version's dispatch matters.
```

Then check: `grep -nE 'ChannelWindow |implementation not started|verify delegation|remains on the scaffold' docs/architecture.md` — Expected: no output.

- [ ] **Step 2: Final verification — run everything, record real numbers**

Run each and note its result:
1. `flutter test` → Expected: `+153: All tests passed!`
2. `dart analyze` → Expected: `No issues found!`
3. `~/fvm/versions/3.44.6/bin/dart format --set-exit-if-changed lib test integration_test` → Expected: exit code 0.
4. `(cd android && ./gradlew :app:testRetailDebugUnitTest --rerun-tasks --console=plain) | grep -c PASSED` → Expected: `44`, and no `FAILED`.
5. `tail -1 build/app/reports/lint-results-retailDebug.txt` (from Task 20) → Expected: `0 errors, …`.
6. The Task 21 on-device result (`+7`), with the device id and API level.

- [ ] **Step 3: Write the verification note**

`docs/verification/2026-09-17-native-bridge-verification.md` — fill every `<…>` with the real value from Step 2. Do not estimate any of them.

```markdown
# Native bridge verification — 2026-09-17

Verified against `docs/architecture.md` §8–§12 and §14, for Plan 4
(`docs/superpowers/plans/2026-09-17-native-android-bridge.md`).

## Results
- Dart: `flutter test` — <ACTUAL COUNT> tests passing (109 before this plan).
- Lint: `dart analyze --fatal-infos` — no issues.
- Kotlin JVM: `./gradlew :app:testRetailDebugUnitTest` — <ACTUAL COUNT> tests passing.
- Android lint (`lintRetailDebug`): <ACTUAL "N errors, M warnings" LINE>.
- Both flavors build: `app-retail-debug.apk`, `app-utility-debug.apk`.
- On device: `integration_test/native_bridge_test.dart` — <ACTUAL RESULT> on <DEVICE ID>, API <API LEVEL>.

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

## Not verified here
- The positive screen-recorder case (needs the Quick Settings recorder on an API 35+ device) and
  `FLAG_SECURE` actually blanking a recording — both remain on §17's list.
- The `shortService` timeout path (`onTimeout`) — a 5 s job never reaches the ~3 min cap.
```

- [ ] **Step 4: Commit**

```bash
git add docs/architecture.md docs/verification/2026-09-17-native-bridge-verification.md
git commit -m "docs: fold Plan 4's bridge decisions back into the architecture; record verification"
```

---

## Self-review

**Spec coverage** (against `docs/architecture.md` §8–§12 and §14):
- §9 channel table, every row:
  - `security.environment · assess`: Tasks 6, 15.
  - `window · setSecure`: Tasks 5, 16.
  - `window · preferHighRefreshRate`: Tasks 9, 16.
  - `payment.job · ensureNotificationPermission / start / current`: Tasks 7, 19.
  - `app · buildInfo`: Tasks 9, 16.
  - Both event channels, replay-1: Tasks 6, 7, 15, 19.
  - `badArguments`: Tasks 16, 19.
  - Wire → Dart mapping, including `serviceStartFailed` as a value and the `ensureNotificationPermission` timeout exemption: Tasks 4, 7.
- §9 threading guarantee (`MainThreadResult` / `MainThreadSink`, IO work inside the `ChannelRegistry` scope, cancelled in `cleanUpFlutterEngine`): Tasks 13, 15, 20.
- §9 manifest (both permissions, the service, the five `<queries>` kept in sync by a test): Tasks 14, 15, 19. §12.2's `appCategory`: Task 16.
- §9 fixtures, all ten plus `channels`: Task 1.
- §8:
  - Six root signals with the ≥ 2 threshold, `unavailable(error)` on a failed check, commands with 1 s timeouts on IO: Tasks 14, 15.
  - Recorder callback on API 35+, registered on listen and unregistered on cancel, `unavailable(apiLevel)` below: Task 15.
- §10:
  - `shortService`; `startForeground` first; `IMPORTANCE_LOW` progress; final notification detached; `START_NOT_STICKY`.
  - `onTimeout` → `timedOut`; `onDestroy` while running → `serviceUnavailable`.
  - Holder with CAS start and delivered-once clearing; decline at 60 % when `amountMinor % 100 == 99`; notification tap = launcher intent.
  - Tasks 17–19.
  - §10.3's scenarios 1, 2, 4, 6, 7, 8, 9, 10 and 13 each map to named code (Task 19's note). Scenarios 1, 2 and 4 also run on a device (Task 21). Scenarios 3, 5, 11 and 12 need no code: they follow from the started-service and `configChanges` design, or from the two-bloc split.
- §11: `ChannelSecureWindow`; Kotlin stays stateless; `noActivity` is transient and swallowed by the controller, which re-asserts on resume (Task 5). The controller is registered as a lazy singleton.
- §4 registration: `registerSecurityModule` / `registerPaymentModule` default to the real adapters, overrides still win (Tasks 5–7).
- §14 Kotlin JVM list (wrappers, payload builders vs fixtures, notification builders, root threshold): Tasks 12–18.
- Deliberately deferred to Plan 5, and named in the scope boundary: `bootstrap()` and its drift assertion, brands, registry, page, goldens, `Makefile`, architecture test, perf test.

**Placeholder scan:** no `TBD`/`TODO`/"handle errors"/"similar to Task N". Every code step shows complete code. The one `TODO` that appears is the Flutter template's existing release-signing comment in `build.gradle.kts`, kept verbatim and out of scope. The `<…>` markers in Task 22's verification note and Task 21's `<device-id>` are explicit fill-in-with-the-real-value instructions, not unfinished design.

**Type and name consistency:**
- Channel names: `NativeChannels.*` (Dart) and `ChannelNames.*` (Kotlin) are both pinned to `channels.json`.
- Wire enum spellings: `rooted`, `screenRecording`, `apiLevel`, `error`, `declined`, `timedOut`, `serviceUnavailable`, `running`, `succeeded`, `failed`, `detected`, `clear`, `unavailable`. They match between the Dart enums (`enumByName`), the Kotlin `wire` strings, and the fixtures.
- `JobSnapshot` exists on both sides on purpose, each private to its side: Dart's in `payment/src/data`, Kotlin's in `dev.test.payment.payment`.
- `invokeNative`'s `timeout: null` is used only for `ensureNotificationPermission`.
- `PaymentJobStateHolder.shared` is used by both the service and the handler.
- `PaymentJobNotifications.progress(0)` is the service's first notification.
- `StartArgs.fromWire` is used by the handler; `readFrom`/`writeTo` by the service.
- `RootChecks.ROOT_PACKAGES` is used by `DeviceRootSignals` and `RootPackagesManifestTest`.
- `ErrorCodes.*` values equal the codes `invokeNative` switches on.
- Test counts, all taken from actual runs of this plan's code:
  - Dart: 14 in `native_bridge`, 5 in `bootstrap`, 8 + 3 + 1 in `security_guard`, 10 + 1 + 2 in `payment`. That is 44 new tests, 153 in total.
  - Kotlin: 1 + 3 + 11 + 4 + 18 + 7 = 44.
