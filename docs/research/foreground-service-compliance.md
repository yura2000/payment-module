# Foreground Service compliance on targetSdk 36 (Payment Job)

## Question

For a simulated Payment Job (a few seconds long, progress 0→100%, persistent notification
with a progress bar) run in an Android Foreground Service on targetSdk 36 / minSdk 26:
which `foregroundServiceType` and manifest permissions apply; how does the
`POST_NOTIFICATIONS` runtime permission interact with FGS start/run; what are the
`startForegroundService`→`startForeground` deadline and the Android 15
`shortService`/`dataSync` timeouts; are Android 16 progress-centric/promoted notifications
relevant; what notification channel importance fits; and what do Flutter 3.44's Android
templates default to for AGP/Kotlin/SDK versions.

## Short answer

- Use **`shortService`** (`FOREGROUND_SERVICE_TYPE_SHORT_SERVICE`, added API 34): fits a
  multi-second job inside its ~3-minute cap, and needs **no typed permission** — only the
  base `FOREGROUND_SERVICE`. `dataSync` is the wrong fit (semantically for
  upload/download/backup/sync; needs `FOREGROUND_SERVICE_DATA_SYNC`; capped at 6h/24h on
  API 35+, over-provisioned for a few seconds of work).
- `POST_NOTIFICATIONS` is **not required to start or run** a FGS. If denied, the service
  still starts and completes; only the notification is hidden from the shade (still
  visible in Task Manager). No special "FGS-start exemption" exists because the two are
  simply not coupled.
- `startForeground()` must be called within **5 seconds** of `startForegroundService()` or
  the system raises `ForegroundServiceDidNotStartInTimeException` (ANR). `shortService`
  then gives **~3 minutes** from that call, `dataSync` gives **6 hours in a rolling 24h
  window** (API 35+); both call `onTimeout(int,int)` (API 34+) with a few seconds to
  `stopSelf()` before the system throws a fatal `RemoteServiceException`. Starting from a
  visible foreground Activity is unrestricted (explicit exemption to the API 31+
  background-start rules).
- Android 16's `Notification.ProgressStyle` targets long, milestone-based journeys
  (rideshare/delivery/navigation) and is optional, not a compliance requirement; for a
  few-second 0→100% job, plain `setProgress()` + `setOngoing(true)` is correct and
  sufficient. "Promoted"/Live Updates ongoing notifications could not be confirmed against
  a primary Android source this session — treat as UNVERIFIED.
- Use channel importance **`IMPORTANCE_LOW`**: silent, no heads-up, but still visible in
  the status bar/shade while the job runs.
- Flutter 3.44.0's Android app template resolves to **AGP 9.0.1**, **Kotlin 2.3.20**,
  `compileSdk`/`targetSdk` **36** (template default `minSdk` 24, overridden by this
  project's 26); the template `AndroidManifest.xml` has no merge placeholders or
  `tools:node` overrides, so adding a `<service>` and `<uses-permission>` entries is a
  plain, unencumbered edit.

## Findings

### 1. Foreground service type and permissions

The Foreground Service (FGS) types reference lists every type with its manifest constant
and required permission. Full table (abridged to what's relevant, plus the two candidates):

| Type | `foregroundServiceType` | Required permission | Runtime prerequisites |
|---|---|---|---|
| `shortService` | `shortService` | **None** (only base `FOREGROUND_SERVICE`) | None |
| `dataSync` | `dataSync` | `FOREGROUND_SERVICE_DATA_SYNC` | None |
| `mediaProcessing` | `mediaProcessing` | `FOREGROUND_SERVICE_MEDIA_PROCESSING` | None (6h/24h limit + `onTimeout`) |

`shortService`'s purpose, quoted: "Quickly finish critical work that cannot be interrupted
or postponed." It has no support for sticky services, cannot start further foreground
services, and "does not require certain declarations that other foreground service types
require" (i.e., no typed `FOREGROUND_SERVICE_*` permission) — confirmed independently by
two fetches of the types reference.
[Foreground service types](https://developer.android.com/develop/background-work/services/fg-service-types)

`shortService` (`FOREGROUND_SERVICE_TYPE_SHORT_SERVICE`) was added in **Android 14 (API
34)**, as part of Android 14 making FGS type declaration mandatory generally. It is *not*
an Android-15 addition — the Android 15 behavior-changes page has no mention of it as new;
it only adds the `dataSync` 6-hour limit (below).
[Foreground service types are required (Android 14)](https://developer.android.com/about/versions/14/changes/fgs-types-required)

Manifest declaration pattern (from the FGS "Declare" guide, generalized to `shortService`):

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>

<application ...>
    <service
        android:name=".PaymentJobService"
        android:foregroundServiceType="shortService"
        android:exported="false" />
</application>
```

The official example shown uses `mediaPlayback`/`camera` (`android:foregroundServiceType="camera"`
paired with `<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CAMERA"/>`);
`shortService` follows the identical `<service>`-attribute pattern but — per the types
reference above — omits the typed `<uses-permission>` line entirely.
[Declare foreground service types](https://developer.android.com/develop/background-work/services/fgs/declare)

Since minSdk is 26 (below API 34), the `ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE`
runtime constant must be version-gated (it doesn't exist pre-34); the `android:foregroundServiceType`
manifest XML attribute itself is inert (ignored) on older OS versions and safe to declare
unconditionally. `androidx.core.app.ServiceCompat.startForeground(service, id, notification, type)`
is the documented, version-safe way to pass the type — this is the exact pattern shown in
the official launch guide's own Kotlin sample, gating a type constant behind `Build.VERSION.SDK_INT`
and passing `0` below the type's minimum API:

```kotlin
ServiceCompat.startForeground(
    /* service = */ this,
    /* id = */ 100, // Cannot be 0
    /* notification = */ notification,
    /* foregroundServiceType = */
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE
    } else {
        0
    },
)
```
[Launch a foreground service](https://developer.android.com/develop/background-work/services/fgs/launch)

### 2. `POST_NOTIFICATIONS` (API 33+) and FGS start/run

Direct quote: "Apps don't need to request the `POST_NOTIFICATIONS` permission in order to
launch a foreground service. However, apps must include a notification when they start a
foreground service, just as they do on previous versions of Android."

And on denial: "on Android 13 (API level 33) or higher, if the user denies the notification
permission, they still see notices related to foreground services in the Task Manager but
don't see them in the notification drawer."

So: the FGS **starts and runs regardless** of the permission state; a denial only
suppresses the notification from the shade/lock screen, while the user can still find the
running-service indicator in the system Task Manager. There's no separate "FGS-start
exemption" concept needed because starting a FGS was never gated on this permission in the
first place — the two systems are independent. (The exemptions the page does list —
media-session notifications, self-managed `Notification.CallStyle` — are exemptions from
needing to *request* the permission at all for those notification categories; they don't
apply to a generic progress notification, which still should request the permission
normally, it just isn't blocked if the user says no.)
[Notification runtime permission](https://developer.android.com/develop/ui/views/notifications/notification-permission)

### 3. Timing deadlines and timeouts

**`startForegroundService()` → `startForeground()` deadline.** The service must call
`startForeground()` within **5 seconds** of the app calling `Context.startForegroundService()`,
or the system raises an ANR. The exact exception, quoted verbatim from the troubleshooting
guide:

```
android.app.RemoteServiceException$ForegroundServiceDidNotStartInTimeException:
    Context.startForegroundService() did not then call Service.startForeground()
```
[Troubleshoot foreground services](https://developer.android.com/develop/background-work/services/fgs/troubleshooting)

(The 5-second figure itself is stated across Android's services/ANR documentation; this
session confirmed the exact exception name/message via a direct primary-source fetch of
the troubleshooting page, and the "5 seconds" number via aggregated developer.android.com
search results rather than one single fully-quoted page — treat the number as
well-established but re-confirm verbatim if it becomes load-bearing for a compliance
sign-off.)

**`shortService` — 3-minute limit.** Quoted: the timeout period "begins from `Service.startForeground()`"
and runs "about three minutes." At expiry the system calls `Service.onTimeout(int, int)`
(API 34+); the service then has "a few seconds" to call `stopSelf()`/`stopForeground()`.
If it doesn't, the system raises an ANR with:

```
Fatal Exception: android.app.RemoteServiceException: "A foreground service of
    type FOREGROUND_SERVICE_TYPE_SHORT_SERVICE did not stop within its timeout:
    <component_name>"
```

Calling `startForeground()` again with the `shortService` type extends the timeout by
another 3 minutes, but only if the app is visible or otherwise satisfies a background-start
exemption.
[Foreground service types](https://developer.android.com/develop/background-work/services/fg-service-types) ·
[Troubleshoot foreground services](https://developer.android.com/develop/background-work/services/fgs/troubleshooting)

**`dataSync` — 6-hour limit (Android 15 / API 35+).** Quoted: "The system permits an app's
`dataSync` services to run for a total of 6 hours in a 24-hour period, after which the
system calls the running service's `Service.onTimeout(int, int)` method (introduced in
Android 15). At this time, the service has a few seconds to call `Service.stopSelf()`...
If the service does not call `Service.stopSelf()`, the system throws an internal
exception." The 6-hour budget resets to full "if the user brings the app to the
foreground." This limit and its `onTimeout` are new in Android 15 for apps **targeting**
API 35+.
[Behavior changes: Apps targeting Android 15](https://developer.android.com/about/versions/15/behavior-changes-15)

Both timeouts are moot for this feature (a job lasting a few seconds), but `onTimeout()`
is still worth implementing defensively as a safety net (see Recommendation).

**Background-start restrictions (API 31+) — foreground-Activity path.** Starting a FGS
while the app runs in the background is restricted to an explicit exemption list (visible-
Activity transition, notification/widget/bubble taps, high-priority FCM, exact alarms,
`BOOT_COMPLETED`-family broadcasts with Android 14+ type restrictions, `SYSTEM_ALERT_WINDOW`
+ Android 15+ also requiring a currently-visible overlay, device-owner/companion-device
cases, etc.); a disallowed attempt throws `ForegroundServiceStartNotAllowedException`.
Confirmed explicitly: starting while the app **has a visible Activity is not restricted at
all** — this falls under "your app transitions from a user-visible state, such as an
activity," the first exemption on the list. Since this feature starts the job from the
foreground payment Activity, this path is unrestricted and no exemption bookkeeping is
needed. No Android 16-specific changes to this restriction were found in the fetched
Android 16 behavior-changes page (its FGS-relevant content was thin — flag as an area to
revisit against the final Android 16 docs if this becomes load-bearing).
[Restrictions on starting a foreground service from the background](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start)

### 4. Android 16 progress-centric and "promoted" notifications

`Notification.ProgressStyle` (Android 16 / API 36) is a structured progress style for
"user-initiated, start-to-end journeys" — the docs' examples are rideshare, delivery, and
navigation, using `Segment`/`Point` lists to mark milestones along the journey, e.g.:

```kotlin
val ps = Notification.ProgressStyle()
    .setStyledByProgress(false)
    .setProgress(456)
    .setProgressTrackerIcon(Icon.createWithResource(appContext, R.drawable.ic_car_red))
    .setProgressSegments(listOf(
        Notification.ProgressStyle.Segment(41).setColor(Color.BLACK),
        Notification.ProgressStyle.Segment(552).setColor(Color.YELLOW),
    ))
    .setProgressPoints(listOf(
        Notification.ProgressStyle.Point(60).setColor(Color.RED),
    ))
```

Nothing in the fetched page states this is required for compliance or that existing plain-
progress notifications must migrate; it's presented as a new optional style. Given the
payment job is a single few-second 0→100% operation with no waypoints, it doesn't fit the
milestone/segment model this style is designed for.
[Progress-centric notifications](https://developer.android.com/about/versions/16/features/progress-centric-notifications)

"Promoted"/Live Updates ongoing notifications (a status-bar-chip/lock-screen surface for
ongoing notifications) are referenced only in passing by Android's notification best-
practices copy ("meet promoted visibility") without detail on this fetch, and this
session's attempts to reach a dedicated primary page 404'd twice
(`/develop/ui/views/notifications/promoted`, `/develop/ui/views/notifications/live-updates`).
Secondary sources (GitHub issue trackers for `flutter_local_notifications` and
`background_downloader`, and a third-party guide) describe a `POST_PROMOTED_NOTIFICATIONS`
manifest permission and eligibility rules (ongoing, `contentTitle` set, not colorized, no
custom content view), off by default. **This is UNVERIFIED against a primary Android
source in this session** — do not treat the permission name or eligibility rules as
confirmed until checked against `developer.android.com` directly.

**Recommendation for this feature:** plain `setProgress(100, percent, false)` +
`setOngoing(true)` is the correct, sufficient choice — it's simpler, has no milestone
semantics to misuse, and nothing in the verified sources makes `ProgressStyle` or promoted
notifications a compliance requirement for a FGS progress notification.

### 5. Notification channel importance

The channel importance table (quoted):

| User-visible importance | Constant (API 26+) | Behavior |
|---|---|---|
| Urgent | `IMPORTANCE_HIGH` | Sound + heads-up |
| High | `IMPORTANCE_DEFAULT` | Sound |
| Medium | `IMPORTANCE_LOW` | **No sound** |
| Low | `IMPORTANCE_MIN` | No sound, doesn't appear in status bar |
| None | `IMPORTANCE_NONE` | No sound, doesn't appear in status bar or shade |

For a persistent progress notification that must stay visible while making no sound,
**`IMPORTANCE_LOW`** is correct (`IMPORTANCE_MIN` would hide it from the status bar,
defeating the point of a visible progress indicator). Channel APIs require guarding with
`Build.VERSION.SDK_INT >= Build.VERSION_CODES.O` (API 26) — which is this project's
minSdk, so the channel can be created unconditionally without a version check.
[Notification channels](https://developer.android.com/develop/ui/views/notifications/channels)

### 6. Flutter 3.44 Android template defaults

Flutter's `settings.gradle.kts.tmpl` for the app template does **not** hardcode AGP/Kotlin
versions — it contains template placeholders substituted at `flutter create` time:

```kotlin
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "{{agpVersion}}" apply false
    id("org.jetbrains.kotlin.android") version "{{kotlinVersion}}" apply false
}
```
[`packages/flutter_tools/templates/app/android.tmpl/settings.gradle.kts.tmpl` @ 3.44.0](https://github.com/flutter/flutter/blob/3.44.0/packages/flutter_tools/templates/app/android.tmpl/settings.gradle.kts.tmpl)

The actual values are Dart constants in `flutter_tools`, read directly at the `3.44.0` tag
(commit `559ffa3f75e7402d65a8def9c28389a9b2e6fe42`):

```dart
const templateAndroidGradlePluginVersion = '9.0.1';
const templateAndroidGradlePluginVersionForModule = '9.0.1';
const templateKotlinGradlePluginVersion = '2.3.20';
const compileSdkVersionInt = 36;
const minSdkVersionInt = 24;
const targetSdkVersion = '36';
```
[`packages/flutter_tools/lib/src/android/gradle_utils.dart` @ 3.44.0](https://github.com/flutter/flutter/blob/3.44.0/packages/flutter_tools/lib/src/android/gradle_utils.dart#L43-L64)

So: **AGP 9.0.1, Kotlin 2.3.20, compileSdk 36, template-default minSdk 24, targetSdk 36**.
This project's minSdk 26 overrides the template default (24) — consistent with the
project's stated facts, no conflict, just noting the template's own default differs.

**Manifest merger:** the template's main manifest
(`packages/flutter_tools/templates/app/android.tmpl/app/src/main/AndroidManifest.xml.tmpl`)
declares only the `<application>`/`MainActivity` block, the `flutterEmbedding` meta-data,
and a `<queries>` block for `ACTION_PROCESS_TEXT`. There are no `tools:node` merge
overrides, no manifest placeholders (`${...}`) beyond `${applicationName}`, and no existing
`<service>` entries. Adding the Payment Job's `<service>` element inside `<application>`
and the `<uses-permission>` lines at the manifest root is therefore a plain, unencumbered
edit — standard Gradle manifest merging applies with nothing special to account for.
[`.../app/src/main/AndroidManifest.xml.tmpl` @ 3.44.0](https://github.com/flutter/flutter/blob/3.44.0/packages/flutter_tools/templates/app/android.tmpl/app/src/main/AndroidManifest.xml.tmpl)

## Recommendation

**Type:** `shortService`. **Manifest:**

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>

<application ...>
    <service
        android:name=".PaymentJobService"
        android:exported="false"
        android:foregroundServiceType="shortService" />
</application>
```

**Lifecycle:**

1. **Start** — from the foreground payment Activity (unrestricted path, confirmed above),
   call `ContextCompat.startForegroundService(context, intent)`.
2. Inside `onStartCommand()`, **within 5 seconds**, build the initial notification
   (channel `IMPORTANCE_LOW`, `setOngoing(true)`, `setProgress(100, 0, false)`, no sound)
   and call `ServiceCompat.startForeground(this, NOTIF_ID, notification, typeOrZero)`, where
   `typeOrZero` is `ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE` gated behind
   `SDK_INT >= 34`, else `0`.
3. **Update** — as the simulated job progresses, call
   `NotificationManager.notify(NOTIF_ID, updatedNotification)` with a new `setProgress(100, pct, false)`
   directly; do not re-call `startForeground()` for updates (that's only needed to extend/
   re-assert the type/timeout, unnecessary for a few-second job).
4. **Stop** — on completion (success or simulated failure), call
   `stopForeground(STOP_FOREGROUND_REMOVE)` then `stopSelf()` promptly, well inside the
   3-minute `shortService` budget.
5. Override `onTimeout(startId, type)` (API 34+) as a defensive safety net — call
   `stopSelf()` immediately if ever invoked, to avoid an ANR if the job unexpectedly stalls.

**Permission strategy:** declare `FOREGROUND_SERVICE` (normal, install-time) and
`POST_NOTIFICATIONS` (runtime, API 33+) in the manifest; request `POST_NOTIFICATIONS` from
the foreground Activity (e.g., contextually when the user initiates the payment) but do
**not** gate starting the service on the grant result — the FGS starts and completes either
way per Finding 2. If denied, the persistent progress notification simply won't be visible
in the shade; since this project's design already streams progress over an EventChannel to
in-app UI, the user-visible payment UI stays authoritative regardless of notification
permission state. No typed foreground-service permission is needed since `shortService`
carries none.

**Main caveat:** the "promoted"/Live Updates ongoing-notification behavior on Android 16
(Finding 4) could not be verified against a primary `developer.android.com` source this
session (both guessed URLs 404'd) — if a later decision wants to opt into that surface,
re-research it against primary docs before relying on the `POST_PROMOTED_NOTIFICATIONS`
permission name found only in secondary sources.

## Open questions / caveats

- **UNVERIFIED**: `POST_PROMOTED_NOTIFICATIONS` permission name and promoted-notification
  eligibility rules (ongoing, `contentTitle`, not colorized, no custom content view) — only
  found in secondary sources (GitHub issues, a third-party guide), not confirmed against a
  primary Android page in this session.
- The exact "5 seconds" figure for `startForegroundService()`→`startForeground()` was
  confirmed via aggregated developer.android.com search snippets and the primary-sourced
  exact exception name/message (via the troubleshooting page), not one single fully-quoted
  primary page stating "5 seconds" verbatim.
- Android 16 (API 36)-specific incremental changes to FGS background-start restrictions
  were not found beyond what Android 12/14/15 already establish; the fetched Android 16
  behavior-changes page's FGS-relevant content was thin (mostly links to feature pages) —
  worth a follow-up pass once Android 16 docs are more fully populated.
- Flutter template version numbers were read from `flutter_tools`' Dart source at the
  `3.44.0` tag rather than the project's exact `3.44.6` patch tag (patch releases do not
  typically change template default versions, but this was not independently re-verified
  at `3.44.6` specifically).

## Sources

- https://developer.android.com/develop/background-work/services/fg-service-types
- https://developer.android.com/develop/background-work/services/fgs/declare
- https://developer.android.com/develop/background-work/services/fgs/launch
- https://developer.android.com/develop/background-work/services/fgs/troubleshooting
- https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start
- https://developer.android.com/about/versions/14/changes/fgs-types-required
- https://developer.android.com/about/versions/15/behavior-changes-15
- https://developer.android.com/about/versions/16/behavior-changes-16
- https://developer.android.com/about/versions/16/features/progress-centric-notifications
- https://developer.android.com/develop/ui/views/notifications/notification-permission
- https://developer.android.com/develop/ui/views/notifications/channels
- https://github.com/flutter/flutter/blob/3.44.0/packages/flutter_tools/lib/src/android/gradle_utils.dart
- https://github.com/flutter/flutter/blob/3.44.0/packages/flutter_tools/templates/app/android.tmpl/settings.gradle.kts.tmpl
- https://github.com/flutter/flutter/blob/3.44.0/packages/flutter_tools/templates/app/android.tmpl/app/src/main/AndroidManifest.xml.tmpl
