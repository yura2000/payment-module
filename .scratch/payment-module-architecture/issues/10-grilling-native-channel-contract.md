# 10. Native channel contract

Type: grilling
Status: resolved
Blocked by: 01, 02, 03, 07
Part of: ../map.md

## Question

Specify the three `MethodChannel`s + one `EventChannel` exactly: names, methods, argument/return payloads (typed keys, codec), `PlatformException.code` vocabulary (`unavailable`, `permissionDenied`, `alreadyRunning`, …), which calls are idempotent, the threading guarantee statement, and the Dart adapters' mapping to `ServiceException` / `TransportException` vs posture/progress values. Include the `BuildConfig.FLAVOR` == `BRAND` drift-check call.

**Deliverable**: the contract table that goes verbatim into the spec, plus the Dart interface each adapter implements.

**Inputs from resolved research**
- Ticket 01 (root detection): the handler returns `Threat.ROOTED` on a ≥2-signal threshold. Decide here whether the `assessPosture` payload is only `{posture, threats}` or also carries a diagnostic `signals: ["su_binary", …]` array (support/triage, threshold tuning) — and if so whether Dart ever acts on it or only logs it. Every package name the handler checks needs a `<queries>` entry in the manifest; list them in the contract so the manifest and the Kotlin constant list stay in sync.
- Ticket 02 (screen recorder): the environment channel needs (a) request/response `assessPosture` and (b) an **event stream** of posture changes (API 35+ `addScreenRecordingCallback` transitions); `unknown`/`unavailable` is a wire value below API 35. `DETECT_SCREEN_RECORDING` is a normal manifest permission. Register/unregister the callback tied to the observing screen's lifetime (ties into ticket 11). Keep `DETECT_SCREEN_CAPTURE` (screenshot detection, API 34) out of the contract unless deliberately added.
- Ticket 04 (120 Hz): add a `preferHighRefreshRate` (or similar) method to the window channel that sets `WindowManager.LayoutParams.preferredDisplayModeId` to the highest-rate mode at the current resolution (API 23+, gate-free) — decide whether the window channel is `security.window` or a general `window` channel now that it carries a non-security concern. Reference implementation: `flutter_displaymode`'s Kotlin.
- Ticket 03 (FGS): `startJob` is only valid from the foreground; decide how notification permission enters the contract (a `requestNotificationPermission` method on the job channel vs. handled natively inside `startJob` with the result reported on the progress stream). Error codes: `alreadyRunning`, `timedOut` (from `onTimeout`).
- Ticket 07 (state machine): the Dart port is `SecurityEnvironment { Future<void> assess(); Stream<SecurityPosture> get posture }` — one source of truth — so the environment channel likely becomes `assess` (fire-and-forget or ack) + an EventChannel that emits the **full per-threat posture** on every change: wire values per `ThreatKind` ∈ `{rooted, screenRecording}` → `{detected, clear, unavailable(reason: apiLevel|error)}`. Job channel: progress wire values `running(percent) | succeeded(reference, completedAt) | failed(declined|timedOut|serviceUnavailable)`; plus a way to query the **in-flight job** on (re)attach (`currentJob` method or replay on subscribe — ticket 12 decides). No cancel method.

## Answer

**Resolved 2026-09-16 (grilling, 2 rounds; all recommendations accepted; prefix `dev.test.payment` supplied by the user).** Supersedes charting's "three MethodChannels + one EventChannel": research 02 (live recorder callback) and ticket 07 (`assess()` + posture stream) require a second event stream.

### Decisions
1. **Prefix / Kotlin root**: `dev.test.payment` (flavors append `.retail` / `.utility` to the applicationId).
2. **Topology**: four `MethodChannel`s + two `EventChannel`s, one handler class per concern owning both its method and event channel — `SecurityEnvironmentHandler`, `WindowHandler` (channel renamed `window`: it carries `preferHighRefreshRate`), `PaymentJobHandler`, `AppInfoHandler`.
3. **Environment semantics**: `assess()` returns an ack; posture arrives only on the event stream (single source of truth). Stream is replay-1; `onListen` registers the API 35+ recorder callback, `onCancel` unregisters → subscription lifetime = observing screen lifetime. Concurrent `assess()` coalesce. A throwing check → that threat `unavailable(error)`; `assess` never raises.
4. **Diagnostics stay off the wire**: fired root signals are logged at debug level in Kotlin; the payload carries only `kind` / `result` / `reason`.
5. **Notification permission**: dedicated `ensureNotificationPermission()` called by the Dart adapter inside `PaymentProcessor.start()`; the domain is unaware; the outcome never gates the job. Kotlin requests via `ActivityCompat.requestPermissions`, resolves the pending `Result` from `MainActivity.onRequestPermissionsResult`. Prompts at most once per process; a denial is remembered.
6. **`start` payload** is minimal: `{reference, amountMinor, currency, payee}` → `{jobId}`. Decline rule reads `amountMinor % 100 == 99`.
7. **Error mapping**: exceptions for the unexpected, values for the expected (table below).
8. **Registration**: `ChannelRegistry` owns the `CoroutineScope` (`SupervisorJob + Dispatchers.Main.immediate`) and the four handlers; `MainActivity` delegates exactly `configureFlutterEngine` → `register`, `cleanUpFlutterEngine` → `dispose`, `onRequestPermissionsResult` → `onPermissionResult`. Handlers receive the Activity via a `() -> Activity?` provider.
9. **Shared fixtures** in `contract/fixtures/*.json`, consumed by Dart contract tests and Kotlin JVM payload-builder tests.
10. `current()` is kept alongside replay-1 (a fresh BLoC needs a synchronous "is there a job?"); the job stream stays open after a terminal state (the Dart adapter completes its per-job stream).

### Contract — `dev.test.payment`
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

### Consequences pushed
- Ticket 11: posture subscription and Secure Window share one lifecycle owner; `setSecure` idempotent; `noActivity` is transient → re-assert on resume.
- Ticket 12: `PaymentJobStateHolder` (process-wide `MutableStateFlow<JobSnapshot?>`) backs both `current()` and replay-1; `ensureNotificationPermission` precedes `start`; `serviceStartFailed` is a value.
- Ticket 13: adapter names/placement above; `preferHighRefreshRate` is infrastructure used by `app`, not a domain port.
- Ticket 15: manifest entries, Kotlin layout, fixtures directory; the contract is the evidence for the "hand-written channels over Pigeon" ADR. Map Notes' native-bridge row updated to 4 + 2 channels, no cancel.
