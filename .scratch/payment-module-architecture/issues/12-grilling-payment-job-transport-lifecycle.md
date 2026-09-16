# 12. Payment Job transport + service/engine lifecycle

Type: grilling
Status: resolved
Blocked by: 03, 10
Part of: ../map.md

## Question

Design how progress flows from the service to Flutter and what survives lifecycle events: service exposes `StateFlow<JobState>` (singleton or Binder) → `EventChannel` stream handler collects on Main → Dart `Stream<PaymentJobProgress>` replaying the current state on (re)subscribe. Started vs bound service. Activity/engine dies mid-job: job continues, notification stays, relaunch re-attaches and shows the current state. Completion → final notification + `stopSelf`. Cancel semantics (allowed? from the notification?).

**Deliverable**: sequence description, ownership of state, and the failure/lifecycle scenarios the spec lists.

**Inputs from resolved research**
- Ticket 03 (FGS): `shortService`, started (not bound) from the foreground Activity, `startForeground` within 5 s, progress via `NotificationManager.notify`, `stopForeground(STOP_FOREGROUND_REMOVE)` + `stopSelf()` on completion, `onTimeout` → abort path. The job survives Activity/engine death by construction; the open design question is only how Flutter re-attaches to the current state (StateFlow replay). `POST_NOTIFICATIONS` denial hides the notification but never stops the job.
- Ticket 02 (screen recorder): posture can change *during* the job on API 35+ — the map rule (job completes, result shows the warning) needs the posture stream and the progress stream composed in the BLoC, not in Kotlin.
- Ticket 07: **cancel is out of scope** — drop the cancel-semantics sub-question. `PaymentProcessor.inFlight` must let a fresh BLoC (after process death) enter `Processing(progress)` directly — replay of the current `JobState` on subscribe is the mechanism to design here. Failures on the wire: `declined | timedOut | serviceUnavailable`; the simulation declines when the amount's cents == 99.
- Ticket 10: wire shapes are fixed — `start` → `{jobId}`, `current()` → `JobSnapshot?`, `payment.job/events` replay-1 and open after terminal states. Design `PaymentJobStateHolder` (process-wide `MutableStateFlow<JobSnapshot?>`) as the single state the service writes and the handler reads for both `current()` and the sink; `serviceStartFailed` is reported as a `start` error (Dart maps it to `Failed(serviceUnavailable)`); `ensureNotificationPermission` runs before `start` in the Dart adapter. Progress cadence and the `onTimeout` → `failed(timedOut)` path are yours to specify.

## Answer

**Resolved 2026-09-16 (grilling, 2 rounds; all recommendations accepted).** Facts verified in the Flutter 3.44.6 template: `MainActivity` has `configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"` and `launchMode="singleTop"` — rotation and dark-mode toggles do not recreate the Activity; re-attach exists for "user left the app" (engine destroyed, process alive) and process death only.

### Decisions
1. **State owner**: `PaymentJobStateHolder`, a process-wide `object` with `MutableStateFlow<JobSnapshot?>`; the **service is the sole writer**, the handler only reads (`current()` = `state.value`; the sink = `state.filterNotNull().collect`). No `Binder` — the service is started, not bound.
2. **Start sequence**: handler validates → `tryStart(jobId)` compare-and-sets the holder from `null | terminal` to `running(0)` (else `alreadyRunning`) → `ContextCompat.startForegroundService(intent + extras: jobId, reference, amountMinor, currency, payee)` → `{jobId}`. A throw resets the holder and returns `serviceStartFailed`. Service: `startForeground` immediately in `onStartCommand`, `START_NOT_STICKY`.
3. **Cadence**: +5 % every 250 ms (≈ 5 s) on `Dispatchers.Default`; `amountMinor % 100 == 99` → `failed(declined)` at 60 %; duration/tick overridable via Intent extras for tests.
4. **Completion notification**: update to a final, non-ongoing state ("Payment complete" / "Payment declined") and `stopForeground(STOP_FOREGROUND_DETACH)` + `stopSelf()` — it persists until dismissed. One notification id throughout.
5. **Terminal retention = replay-until-delivered**: a terminal snapshot is kept until delivered once (emitted to an active sink *or* returned by `current()`), then cleared to `null`. No contract change.
6. **Notification tap**: launcher intent for `MainActivity` (`singleTop`); the root route's BLoC re-attaches via `current()`. No deep-link machinery. (Graduates the fog item.)
7. **Process death**: `START_NOT_STICKY`; the job is lost; relaunch sees `current() == null`. Documented as a limitation of a *simulated* processor — a real one is server-authoritative behind the same `inFlight` seam.
8. **Addendum to ticket 07**: `Started` with a **terminal** `current()` → `Completed(outcome)` directly (Result View), not `Processing`.
9. **Teardown writers**: `onTimeout(startId)` (API 34 overload) → `failed(timedOut)`, final notification, detach, `stopSelf`; `onDestroy` while `running` → `failed(serviceUnavailable)`, ticker scope cancelled. The ticker, `onTimeout` and `onDestroy` are the only writers besides `tryStart`.

### Sequence — happy path
1. BLoC `PayPressed` (`canPay`) → `ConfirmPayment(payment)` → `ChannelPaymentProcessor.start(payment)`.
2. Adapter: `ensureNotificationPermission()` (logged, never gates) → `start({reference, amountMinor, currency, payee})`.
3. `PaymentJobHandler` (main): validate → `holder.tryStart(jobId)` → `startForegroundService` → `{jobId}` via `MainThreadResult`.
4. Adapter subscribes `payment.job/events` → `onListen` collects `holder.state` on `Main.immediate` → replays `running(0)` → filtered by `jobId` → `Running(0)` → BLoC `Processing(0)`.
5. `PaymentJobService.onStartCommand`: extras → `IMPORTANCE_LOW` ongoing notification → `ServiceCompat.startForeground(NOTIF_ID, n, SDK_INT ≥ 34 ? SHORT_SERVICE : 0)` → ticker → `START_NOT_STICKY`.
6. Ticker: `holder.update(running(p))` + `notify(NOTIF_ID, n(p))` per tick; decline check at 60 %; `succeeded(reference, completedAt)` at 100 %.
7. Terminal: holder ← terminal → final notification → `stopForeground(STOP_FOREGROUND_DETACH)` → `stopSelf()` → `onDestroy` cancels the scope (terminal not overwritten).
8. Collector delivers the terminal → adapter completes the per-job stream → BLoC `Completed(outcome)` → holder marks delivered and clears.

**Threading**: handler methods and `startForegroundService` on main; ticker writes from `Default` (`StateFlow` is thread-safe); collector on `Main.immediate` so `MainThreadSink` is a no-op guard; `current()` reads on main.

### Kotlin responsibilities
| Class | Owns |
|---|---|
| `PaymentJobStateHolder` (`object`) | `state: StateFlow<JobSnapshot?>` · `tryStart(jobId): Boolean` · `update(snapshot)` · delivered-once clearing |
| `PaymentJobHandler` | `start` / `current` / `ensureNotificationPermission` · stream handler (collect ↔ cancel) · pending permission `Result` fed by `onRequestPermissionsResult` |
| `PaymentJobService` | channel creation · `startForeground` · ticker · terminal handling · `onTimeout` · `onDestroy`-while-running |
| `PaymentJobNotifications` | pure builders for progress and final notifications (unit-testable) |

**Dart `ChannelPaymentProcessor`**: `start(payment)` → per-job stream = events `.where(jobId).map(parse)`, completing inclusively on a terminal state. `inFlight()` → `current()`: `null` → `null`; terminal → `Stream.value(parsed)`; running → the filtered stream (replay-1 supplies the current snapshot).

### Scenario table
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

### Consequences pushed
- Ticket 07: addendum (terminal `current()` → `Completed`).
- Ticket 11: the Secure Window/posture owner and the job subscription are distinct lifetimes — the job stream lives with the BLoC, the posture subscription with the page.
- Ticket 13: `ChannelPaymentProcessor` shape (`start`, `inFlight`) is the `PaymentProcessor` port; `PaymentJobNotifications` is a Kotlin-side internal seam.
- Ticket 15: sequence + scenario table verbatim; process-death limitation in the spec; Intent-extras test hooks.
- Map: notification-tap fog item graduated (decided here).
