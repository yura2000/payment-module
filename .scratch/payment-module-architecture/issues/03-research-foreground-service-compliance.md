# 03. Foreground Service compliance on targetSdk 36

Type: research
Status: resolved
Blocked by: —
Part of: ../map.md

## Question

For a simulated Payment Job (a few seconds, progress 0→100 %) in a Foreground Service on targetSdk 36 / minSdk 26:

- Which `foregroundServiceType` (`shortService` vs `dataSync` vs other) and the exact manifest permissions per type (`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_*`).
- `POST_NOTIFICATIONS` runtime permission (API 33+): who asks, what happens if denied — does the FGS still run, is the notification just hidden?
- `startForegroundService` → `startForeground` deadline; Android 15 `dataSync` 6-hour limit, `shortService` 3-minute limit and their timeout callbacks.
- Android 16 progress-centric notifications (`Notification.ProgressStyle`): worth using for "modern API compliance" or plain `setProgress`?
- Notification channel importance for a progress notification.
- Flutter 3.44 Android template: AGP/Kotlin versions, anything the manifest merger needs.

**Deliverable**: recommended type + manifest snippet + lifecycle rules (start, update, `stopForeground`, `stopSelf`) + permission strategy.

**Decisions waiting on this**: ticket 12 (transport + lifecycle), ticket 10 (channel contract).

## Answer

**Resolved 2026-09-16 by a research agent.** Findings: `docs/research/foreground-service-compliance.md` on branch `research/foreground-service-compliance` (developer.android.com + Flutter `flutter_tools` source at the 3.44.0 tag).

**Decision**: `foregroundServiceType="shortService"`.
- Fits a multi-second job inside its ~3-minute cap and needs **no typed permission** — only `FOREGROUND_SERVICE` (normal). `dataSync` rejected: wrong semantics (upload/backup/sync), needs `FOREGROUND_SERVICE_DATA_SYNC`, 6 h / rolling 24 h cap on API 35+.
- `POST_NOTIFICATIONS` (runtime, API 33+) is **not coupled to FGS start**: if denied the service still starts and completes, the notification is just hidden from the shade. Request it contextually when the user taps Pay; never gate the job on the grant. In-app progress (EventChannel) stays authoritative.
- Manifest: `<uses-permission FOREGROUND_SERVICE/>`, `<uses-permission POST_NOTIFICATIONS/>`, `<service android:name=".PaymentJobService" android:exported="false" android:foregroundServiceType="shortService"/>`. Flutter 3.44's template manifest has no placeholders/`tools:node` overrides — plain edit.
- Lifecycle rules: start from the foreground Activity via `ContextCompat.startForegroundService` (unrestricted path); in `onStartCommand` call `ServiceCompat.startForeground(id, notification, SDK_INT >= 34 ? FOREGROUND_SERVICE_TYPE_SHORT_SERVICE : 0)` **within 5 s** (else `ForegroundServiceDidNotStartInTimeException`); update progress with `NotificationManager.notify` (don't re-call `startForeground`); on completion `stopForeground(STOP_FOREGROUND_REMOVE)` + `stopSelf()`; override `onTimeout` as a safety net → `stopSelf()` (API 34 one-arg overload; API 35 added the two-arg `onTimeout(startId, fgsType)` — verify its default delegates).
- Notification: channel `IMPORTANCE_LOW` (silent, still visible in status bar/shade), `setOngoing(true)`, `setProgress(100, pct, false)`. Android 16 `Notification.ProgressStyle` is for long milestone journeys — optional, not compliance; "promoted"/Live Updates surface UNVERIFIED against primary docs — don't build on it.
- Toolchain facts: Flutter 3.44 template → **AGP 9.0.1, Kotlin 2.3.20**, compileSdk/targetSdk 36, template minSdk 24 (we override to 26). Read at the 3.44.0 tag, not 3.44.6 — re-check on scaffold.

**Downstream**: ticket 12 — the job runs to completion even if the Activity/engine dies (started, not bound); stay far inside the 3-minute cap; `onTimeout` is the abort path; notification permission is a UX nicety, not a precondition. Ticket 10 — the job channel needs a `notificationPermission` state or the Dart side asks via the same channel before `startJob`.
