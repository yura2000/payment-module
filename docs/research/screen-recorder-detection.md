# Screen-recorder detection across API levels (26-36)

## Question

How can an Android app detect an *active* screen recorder on API 26-36? Specifically: the mechanics
of the API 35 `WindowManager.addScreenRecordingCallback` path (permission, threading, initial
return value, interaction with `FLAG_SECURE`, scope), and what — if anything — is available as a
fallback below API 35.

## Short answer

API 35+ (`WindowManager.addScreenRecordingCallback`) is the only official signal: gated by the
`normal` (install-time, no runtime prompt) permission `DETECT_SCREEN_RECORDING`; the callback runs on
whatever `Executor` you supply; its return value is a live, synchronous *current*-state query, not a
stub; and it fires for **any** app's MediaProjection session (system recorder, 3rd-party, screen-share)
— confirmed via AOSP source, not limited to the built-in recorder. It still fires while the app's own
window has `FLAG_SECURE` set (source-verified; contrasts with the sibling screenshot-detection API,
which explicitly doesn't fire under `FLAG_SECURE`). Below API 35, no official signal exists — other
apps' MediaProjection sessions sit behind a `signature`, `@hide` permission — and every fallback
investigated (known-package heuristics, `DisplayManager` virtual displays, foreground-service
enumeration) is unreliable or non-functional. The Security Posture model needs an explicit `unknown`
state for API 26-34, not a default to Secure.

## Findings

### 1. Primary path: `WindowManager.addScreenRecordingCallback` (API 35+)

Officially introduced in Android 15 and documented on the Android 15 features page:

> "Android 15 adds support for apps to detect that they are being recorded. A callback is invoked
> whenever the app transitions between being visible or invisible within a screen recording. An app
> is considered visible if activities owned by the registering process's UID are being recorded."
> — [Android 15 features & APIs](https://developer.android.com/about/versions/15/features#screen-recording-detection)

The official sample from that page:

```kotlin
val mCallback = Consumer<Int> { state ->
    if (state == SCREEN_RECORDING_STATE_VISIBLE) { /* being recorded */ } else { /* not */ }
}
override fun onStart() {
    super.onStart()
    val initialState = windowManager.addScreenRecordingCallback(mainExecutor, mCallback)
    mCallback.accept(initialState)
}
override fun onStop() {
    super.onStop()
    windowManager.removeScreenRecordingCallback(mCallback)
}
```

This is **not** a targetSdk-gated behavior change — it does not appear on the
[Android 15](https://developer.android.com/about/versions/15/behavior-changes-15) or
[Android 16](https://developer.android.com/about/versions/16/behavior-changes-16) "behavior changes"
pages (checked directly; absent from both), nor on the
[Android 16 features page](https://developer.android.com/about/versions/16/features) — it is a plain
new API gated only by device API level, unchanged from 15 to 16. It is `@FlaggedApi`-gated in AOSP by
`com.android.window.flags.screen_recording_callbacks`, a Trunk-Stable flag that is on in shipping
Android 15+ builds.

Everything below is read directly from the AOSP `frameworks/base` tree at `master`. cs.android.com
itself is a JS-rendered UI the fetch tooling used here cannot render; the content was pulled via the
read-only GitHub mirror (`github.com/aosp-mirror/platform_frameworks_base`), which mirrors the same
`android.googlesource.com/platform/frameworks/base` source cs.android.com indexes — the cs.android.com
permalinks below point at the same lines.

**Permission — `DETECT_SCREEN_RECORDING`, `normal`, declared, not requested.**
Declared in `core/res/AndroidManifest.xml`:

```xml
<!-- Allows an application to get notified when it is being recorded.
     <p>Protection level: normal
     @FlaggedApi("com.android.window.flags.screen_recording_callbacks") -->
<permission android:name="android.permission.DETECT_SCREEN_RECORDING"
            android:protectionLevel="normal"
            android:featureFlag="com.android.window.flags.screen_recording_callbacks" />
```
[core/res/AndroidManifest.xml;l=2825](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/core/res/AndroidManifest.xml;l=2825)

`normal` means install-time grant: `<uses-permission android:name="android.permission.DETECT_SCREEN_RECORDING" />`
is sufficient, the system grants it automatically at install, and there is no `requestPermissions()`
runtime flow — per the general normal-vs-dangerous distinction in the
[permissions overview](https://developer.android.com/guide/topics/permissions/overview) ("Normal
permissions... are automatically granted when the user installs your app... classified as
install-time permissions, not runtime permissions"). The API itself is additionally marked
`@RequiresPermission(permission.DETECT_SCREEN_RECORDING)` on both `addScreenRecordingCallback` and
`removeScreenRecordingCallback`:
[WindowManager.java;l=6719](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/core/java/android/view/WindowManager.java;l=6719).

**Threading — whatever `Executor` you pass; the framework does not force a thread.**
The interface signature takes a `@CallbackExecutor Executor` plus a `Consumer<Integer>`
([WindowManager.java;l=6721](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/core/java/android/view/WindowManager.java;l=6721)).
The actual dispatch, in the process-wide singleton that backs every registration, is:

```java
callbacks.add(() -> executor.execute(() -> callback.accept(state)));
```
[ScreenRecordingCallbacks.java;l=122-144](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/core/java/android/view/ScreenRecordingCallbacks.java;l=122)
(`notifyCallbacks`). So: pass `context.mainExecutor` (as the official sample does) and the callback
runs on the main thread; pass a background `Executor` and it runs there. Nothing about the API forces
main-thread delivery — that is purely the caller's choice, made once, when registering. This matches
this project's stated convention (hop every emission to the main thread before crossing the channel)
if the Kotlin handler supplies a main-thread executor here rather than relying on the framework.

**Initial return value — a live, synchronous query of current state, not a placeholder.**
`addScreenRecordingCallback` returns `@ScreenRecordingState int`, and per the javadoc: "@return the
current screen recording state"
([WindowManager.java;l=6715](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/core/java/android/view/WindowManager.java;l=6715)).
Tracing the implementation confirms this is not a stub/default value: the first registration in a
process makes a blocking Binder call to `WindowManagerService.registerScreenRecordingCallback`, whose
return value (`visibleInScreenRecording`) becomes the state returned to the caller:

```java
boolean visibleInScreenRecording =
        getWindowManagerService().registerScreenRecordingCallback(mCallbackNotifier);
mState = visibleInScreenRecording ? SCREEN_RECORDING_STATE_VISIBLE : SCREEN_RECORDING_STATE_NOT_VISIBLE;
...
return mState;
```
[ScreenRecordingCallbacks.java;l=90-104](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/core/java/android/view/ScreenRecordingCallbacks.java;l=90).
Server-side, that Binder call resolves synchronously against the *current* window hierarchy
([WindowManagerService.java;l=10395](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/services/core/java/com/android/server/wm/WindowManagerService.java;l=10395)
→ `ScreenRecordingCallbackController.register()`,
[ScreenRecordingCallbackController.java;l=131-153](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/services/core/java/com/android/server/wm/ScreenRecordingCallbackController.java;l=131)).
Practical implication: the `Consumer` you register is **not** itself invoked for the initial state —
per the official sample, you must manually feed the method's return value into your own handler
(`mCallback.accept(initialState)`); only *subsequent transitions* arrive through the callback.

**Scope — any MediaProjection session, not just the built-in Screen Recorder.**
This is the most consequential finding for the ticket's "system recorder only or any MediaProjection"
question, and it's unambiguous from source. `ScreenRecordingCallbackController` does not special-case
any particular app; it registers as a system-wide **MediaProjection watcher**:

```java
mediaProjectionInfo = mediaProjectionManager.addCallback(new MediaProjectionWatcherCallback());
...
private void onScreenRecordingStart(MediaProjectionInfo mediaProjectionInfo) {
    setRecordedWindowContainer(mediaProjectionInfo);
    dispatchCallbacks(getRecordedUids(), true /* visibleInScreenRecording*/);
}
```
[ScreenRecordingCallbackController.java;l=104-190](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/services/core/java/com/android/server/wm/ScreenRecordingCallbackController.java;l=104).

`IMediaProjectionWatcherCallback.onStart`/`onStop` fire for **every** `MediaProjection` session on the
device, regardless of which app created it — the AOSP Quick Settings "Screen Record" tile is itself
just a privileged `MediaProjection` client, and so is any third-party recorder, screen-share, casting,
or remote-support app that goes through `MediaProjectionManager.createScreenCaptureIntent()` with user
consent. Visibility is then computed per-UID by walking the recorded window container for activities
belonging to that UID
([ScreenRecordingCallbackController.java;l=224-238](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/services/core/java/com/android/server/wm/ScreenRecordingCallbackController.java;l=224),
`uidHasRecordedActivity`). It does **not** detect non-`MediaProjection` capture: `adb shell
screenrecord` captures directly via `SurfaceComposerClient::createVirtualDisplay()`/`mirrorDisplay()`
in native code and never touches `MediaProjectionManager` at all (confirmed — zero references to
`MediaProjection` in
[screenrecord.cpp](https://android.googlesource.com/platform/frameworks/av/+/master/cmds/screenrecord/screenrecord.cpp),
which instead uses `SurfaceComposerClient` throughout, e.g. `createVirtualDisplay`/`mirrorDisplay`
around lines 370-390). This is a real gap worth knowing for a demo (see Recommendation).

**Interaction with `FLAG_SECURE` — the callback still fires; `FLAG_SECURE` does not suppress it.**
Nothing in `uidHasRecordedActivity`/`getRecordedUids`
([ScreenRecordingCallbackController.java;l=224-253](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/services/core/java/com/android/server/wm/ScreenRecordingCallbackController.java;l=224))
inspects `FLAG_SECURE` or any window flag — visibility is purely "does this UID own a
`isVisibleRequested()` activity inside the recorded window container." This is not spelled out in
prose docs for this specific API, but it is strongly corroborated by a documented **contrast** with
its sibling screenshot-detection API (`Activity.registerScreenCaptureCallback`, API 34,
`DETECT_SCREEN_CAPTURE` permission — a related but distinct feature, easy to confuse with this one).
That sibling's javadoc explicitly carves out the FLAG_SECURE case, which the recording callback's
javadoc conspicuously does not:

```java
/**
 * Called when one of the monitored activities is captured.
 * This is not invoked if the activity window
 * has {@link WindowManager.LayoutParams#FLAG_SECURE} set.
 */
void onScreenCaptured();
```
[Activity.java;l=9935-9945](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/core/java/android/app/Activity.java;l=9935).

That asymmetry makes sense architecturally: a screenshot attempt on a `FLAG_SECURE` window is blocked
outright by the OS (nothing was captured, so there's nothing to report), whereas a screen *recording*
in progress keeps running — `FLAG_SECURE` only blanks that window's composited layer to black for the
duration, at the SurfaceFlinger/compositor level — so the WindowManager-level "is this UID part of the
recorded hierarchy" check has no reason to change. Treat "still fires under FLAG_SECURE" as
source-verified, not prose-documented.

### 2. Below API 35 (26-34): no official signal exists

**Other apps' `MediaProjection` sessions are not observable — confirmed, not just absent from docs.**
The exact mechanism the API-35 callback uses internally
(`IMediaProjectionManager.addCallback(IMediaProjectionWatcherCallback)`) is `@hide` and gated by
`MANAGE_MEDIA_PROJECTION`:

```aidl
@EnforcePermission("MANAGE_MEDIA_PROJECTION")
@JavaPassthrough(annotation = "@android.annotation.RequiresPermission(android.Manifest.permission.MANAGE_MEDIA_PROJECTION)")
MediaProjectionInfo addCallback(IMediaProjectionWatcherCallback callback);
```
[IMediaProjectionManager.aidl](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/media/java/android/media/projection/IMediaProjectionManager.aidl)
(package `android.media.projection`, `{@hide}` at the top of the file).

```xml
<!-- @hide This is not a third-party API (intended for system apps). -->
<permission android:name="android.permission.MANAGE_MEDIA_PROJECTION"
    android:protectionLevel="signature" />
```
[core/res/AndroidManifest.xml;l=7377](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/core/res/AndroidManifest.xml;l=7377).

`signature` + `@hide` + an explicit "not a third-party API" comment is about as definitive as AOSP
gets: no app outside the platform signing key can watch other apps' MediaProjection sessions, on any
API level, before or after 35 — apps only ever get the narrow, mediated `VISIBLE`/`NOT_VISIBLE` signal
that API 35 exposes for *themselves*, never a raw feed.

**Fallback: known recorder package names.** Requires declaring each candidate package (or the
`QUERY_ALL_PACKAGES` permission) in `<queries>` once the app targets API 30+, per the official package
visibility docs:

> "Android 11 (API level 30) or higher... To view other packages, declare your app's need for
> increased package visibility using the `<queries>` element... Google Play considers the list of
> installed apps to be personal and sensitive user data."
> — [Package visibility filtering on Android](https://developer.android.com/training/package-visibility)

This is at best a weak, install-time signal (`PackageManager.getPackageInfo()` tells you the package is
*installed*, never that it is *actively recording right now*), it can't reach the built-in Screen
Recorder (it isn't a separately queryable third-party package on most OEM builds), it requires an
externally-maintained package-name list, and it telegraphs intent in the manifest. Not a Threat signal
on its own merits — see Recommendation.

**Fallback: `DisplayManager.getDisplays()` virtual displays — investigated and effectively dead.**
Two independent, compounding reasons, both confirmed directly in AOSP source:

1. The official capture guide's own sample only sets `VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR`, not
   `VIRTUAL_DISPLAY_FLAG_PUBLIC` ([Capture the contents of a screen](https://developer.android.com/guide/topics/large-screens/media-projection)),
   which per `DisplayManager`'s own javadoc means the resulting virtual display is **private**:
   > "When this flag is not set, the virtual display is private... the only processes that are allowed
   > to enumerate or interact with the private display are those that have the same UID as the
   > application that originally created the private virtual display..."
   [DisplayManager.java;l=199-237](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/core/java/android/hardware/display/DisplayManager.java;l=199)
   (`VIRTUAL_DISPLAY_FLAG_PUBLIC` javadoc).
2. That "only the owning UID" rule is enforced server-side, not client-side, so it can't be worked
   around: `LogicalDisplayMapper.getDisplayIdsLocked(callingUid, ...)` filters every display through
   `DisplayInfo.hasAccess(callingUid)`
   ([LogicalDisplayMapper.java;l=332-348](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/services/core/java/com/android/server/display/LogicalDisplayMapper.java;l=332)),
   which resolves to:
   ```java
   public static boolean hasAccess(int uid, int flags, int ownerUid, int displayId) {
       return (flags & Display.FLAG_PRIVATE) == 0
               || uid == ownerUid || uid == Process.SYSTEM_UID || uid == 0
               || DisplayManagerGlobal.getInstance().isUidPresentOnDisplay(uid, displayId);
   }
   ```
   [Display.java;l=2053-2059](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/core/java/android/view/Display.java;l=2053).
   A recorder app's capture display simply will not appear in another app's `getDisplays()` result at
   all. And even for a display that *did* enumerate, `Display.getOwnerUid()`/`getOwnerPackageName()`
   are themselves `@hide`
   ([Display.java;l=847-866](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/core/java/android/view/Display.java;l=847)) —
   not part of the public SDK, so a normal app has no supported way to read them regardless.

**Fallback: enumerating other apps' foreground services — dead since API 26, this project's own
minSdk.** `ActivityManager.getRunningServices()`:

```java
/**
 * @deprecated As of {@link android.os.Build.VERSION_CODES#O}, this method
 * is no longer available to third party applications.  For backwards compatibility,
 * it will still return the caller's own services.
 */
@Deprecated
public List<RunningServiceInfo> getRunningServices(int maxNum)
```
[ActivityManager.java;l=3348-3360](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/core/java/android/app/ActivityManager.java;l=3348).
Since API 26 — this project's `minSdk` — it can only ever return the caller's own services. There is
no supported way to see whether some other app is running a `mediaProjection`-typed foreground service.
(A `NotificationListenerService` could in principle observe another app's persistent recording
notification, but that requires a separate, broad, user-granted, Play-scrutinized permission
unrelated to this feature — not a proportionate fallback for this use case.)

## Recommendation

**Tiered contract, with `unknown` as a first-class third state — not a variant of Secure or
Compromised:**

| API level | Signal | Native-side state |
|---|---|---|
| 35+ (Android 15/16) | `WindowManager.addScreenRecordingCallback` | `visible` / `notVisible`, event-driven, live |
| 26-34 | none official; no fallback investigated here is reliable enough to assert a Threat | `unknown` |

Do not spend effort wiring the known-package-name or `DisplayManager` fallbacks into the Threat
determination: the package-name approach only proves "installed," not "recording," and misses the
built-in recorder entirely; the `DisplayManager` approach is architecturally blocked (private virtual
displays are invisible cross-UID, owner identity is `@hide`); foreground-service enumeration has been
cross-app-blind since this project's own minSdk. Reporting a false "not recording" on API 26-34 is
worse for a payment Security Posture than admitting `unknown` — a confident negative you can't back up
is a bigger liability than an honest "can't tell." This directly answers the open decision: yes, the
Security Posture domain model needs a third `unknown` state distinct from Secure and
Compromised-by-Threat, not just for API<35 devices but transiently on 35+ too (the brief window before
the first `addScreenRecordingCallback` registration resolves).

**What detection is *for*, given `FLAG_SECURE` already blanks the recording:** prevention and
detection operate at different layers and serve different purposes. `FLAG_SECURE` (Secure Window) is a
compositor-level guarantee that no *pixels* leak, enforced independent of whether the app knows it's
being recorded. `addScreenRecordingCallback` is an app-level *signal* on top of that guarantee — and,
per the source above, it keeps firing even while `FLAG_SECURE` is blanking the frame. That combination
is what makes it useful: the app can react (show an explicit "recording detected, content hidden for
your security" banner instead of an unexplained black rectangle, log a risk/fraud event, step up
auth, or hard-block the flow per the Threat model) instead of just silently relying on the OS to blank
pixels. It is a business-logic/UX and defense-in-depth signal layered on top of a rendering guarantee,
not a replacement for it — the two are independent and both should stay on.

**Native channel contract sketch** (feeding the "decisions waiting on this"): a `MethodChannel` call
(e.g. `startScreenRecordingDetection`) that, on API 35+, calls `addScreenRecordingCallback` on
`Dispatchers.IO` (it is a blocking Binder round-trip per the source above), maps the returned int to
`{visible, notVisible}`, and returns that as the method result hopped to the main thread; on API <35 it
returns `unknown` immediately, no registration attempted. A paired `EventChannel` streams subsequent
`visible`/`notVisible` transitions only on API 35+ — supply `ContextCompat.getMainExecutor(context)` (or
equivalent) as the `Executor` so the framework callback already lands on the main thread before the
`EventSink` is invoked, consistent with this project's "every emission hopped to the main thread"
convention; on API <35 the channel simply never emits (or emits a single `unknown` and stays silent).
Remove the callback (`removeScreenRecordingCallback`) when the observing screen stops, mirroring the
official `onStart`/`onStop` sample.

**What a demo can visibly show (API 35+ device/emulator required for the positive case):**
1. Open a demo screen with `FLAG_SECURE` set; start the on-device Quick Settings **"Screen Record"**
   tile (or any app using `MediaProjectionManager.createScreenCaptureIntent()`, e.g. a video-call
   screen-share) → show the in-app banner appearing from the `SCREEN_RECORDING_STATE_VISIBLE`
   callback, *and*, side by side, the resulting recording/share showing a black rectangle where the
   app is — visibly proving detection and prevention are two independent, simultaneous layers.
2. Stop the recording → show the transition back to `notVisible`.
3. Re-run the same demo using `adb shell screenrecord` instead of the Quick Settings tile → show that
   **no** callback fires, concretely demonstrating the API's real boundary (MediaProjection-based
   capture only) so stakeholders don't overestimate coverage.
4. Run the same screen on an API <35 emulator (e.g. API 28 or 34) → show the channel surfacing
   `unknown` explicitly, distinguishing "confirmed not recording" from "can't tell," which is the crux
   of the Security Posture decision this research feeds.

## Open questions / caveats

- FLAG_SECURE not suppressing the API-35 callback is verified by reading the implementation
  (`ScreenRecordingCallbackController`) and by contrast with the sibling `ScreenCaptureCallback`
  javadoc, but no Google prose doc says this outright for `addScreenRecordingCallback` specifically —
  worth a throwaway-branch spike to confirm empirically on a real API 35+ device before relying on it
  for the Threat determination.
- Coverage is scoped to `MediaProjection`-based capture. Non-MediaProjection paths (`adb shell
  screenrecord`, and by the same architectural logic likely also OEM/vendor screen-mirroring or
  assistive/accessibility-based capture that doesn't go through `MediaProjectionManager`) are
  UNVERIFIED beyond the one case checked (`screenrecord.cpp`) and should be assumed undetected unless
  proven otherwise for a specific OEM.
- Whether any OEM ships a modified `ScreenRecordingCallbackController`-equivalent that also covers
  non-MediaProjection recorders is UNVERIFIED — this research covers AOSP only, per the ticket's
  primary-source scope.
- The `com.android.window.flags.screen_recording_callbacks` Trunk-Stable flag was not independently
  confirmed enabled on every API 35/36 OEM build (only reasoned from it shipping as a documented,
  public feature since Android 15 GA) — worth a device-farm smoke check if the demo is high-stakes.
- `DETECT_SCREEN_CAPTURE` / `Activity.registerScreenCaptureCallback` (API 34, screenshot detection) is
  a distinct, adjacent feature, not screen-recording detection — flagged here only to prevent the two
  being conflated when the native channel contract is designed.

## Sources

Official (developer.android.com):
- [Android 15 features & APIs — screen recording detection](https://developer.android.com/about/versions/15/features#screen-recording-detection)
- [Behavior changes: apps targeting Android 15](https://developer.android.com/about/versions/15/behavior-changes-15) (checked: no mention)
- [Behavior changes: apps targeting Android 16](https://developer.android.com/about/versions/16/behavior-changes-16) (checked: no mention)
- [Android 16 features & APIs](https://developer.android.com/about/versions/16/features) (checked: no mention/no change)
- [Permissions overview — normal vs. dangerous](https://developer.android.com/guide/topics/permissions/overview)
- [Package visibility filtering on Android](https://developer.android.com/training/package-visibility)
- [Capture the contents of a screen (MediaProjection guide)](https://developer.android.com/guide/topics/large-screens/media-projection)
- [Foreground service types are required (Android 14 behavior change)](https://developer.android.com/about/versions/14/changes/fgs-types-required)

AOSP source, `frameworks/base` and `frameworks/av` at `master` (cs.android.com permalinks; content
retrieved via the read-only GitHub mirror `github.com/aosp-mirror/platform_frameworks_base` and
`platform_frameworks_av`, which mirror the same `android.googlesource.com` trees cs.android.com
indexes):
- [WindowManager.java](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/core/java/android/view/WindowManager.java;l=6650) — `SCREEN_RECORDING_STATE_*`, `addScreenRecordingCallback`/`removeScreenRecordingCallback` javadoc + `@RequiresPermission`
- [WindowManagerImpl.java](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/core/java/android/view/WindowManagerImpl.java;l=595) — client-side entry point
- [ScreenRecordingCallbacks.java](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/core/java/android/view/ScreenRecordingCallbacks.java) — Executor dispatch, synchronous initial-state query
- [WindowManagerService.java](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/services/core/java/com/android/server/wm/WindowManagerService.java;l=10395) — `registerScreenRecordingCallback`/`unregisterScreenRecordingCallback` binder entry points
- [ScreenRecordingCallbackController.java](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/services/core/java/com/android/server/wm/ScreenRecordingCallbackController.java) — MediaProjection-watcher-based implementation; per-UID visibility logic; no `FLAG_SECURE` check
- [core/res/AndroidManifest.xml](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/core/res/AndroidManifest.xml;l=2812) — `DETECT_SCREEN_RECORDING` (normal), `DETECT_SCREEN_CAPTURE` (normal), `MANAGE_MEDIA_PROJECTION` (signature, `@hide`)
- [IMediaProjectionManager.aidl](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/media/java/android/media/projection/IMediaProjectionManager.aidl) — `@hide`, `MANAGE_MEDIA_PROJECTION`-gated watcher registration
- [Display.java](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/core/java/android/view/Display.java;l=2053) — `FLAG_PRIVATE`, `hasAccess()`, `getOwnerUid()`/`getOwnerPackageName()` (`@hide`)
- [DisplayInfo.java](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/core/java/android/view/DisplayInfo.java;l=877) — `hasAccess()` delegate
- [LogicalDisplayMapper.java](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/services/core/java/com/android/server/display/LogicalDisplayMapper.java;l=332) — per-UID display enumeration filter
- [DisplayManager.java](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/core/java/android/hardware/display/DisplayManager.java;l=199) — `VIRTUAL_DISPLAY_FLAG_PUBLIC`/private-by-default javadoc
- [ActivityManager.java](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/core/java/android/app/ActivityManager.java;l=3342) — `getRunningServices()` deprecation, own-services-only since API 26
- [Activity.java](https://cs.android.com/android/platform/superproject/+/master:frameworks/base/core/java/android/app/Activity.java;l=9935) — sibling `ScreenCaptureCallback`/`registerScreenCaptureCallback` (API 34, `DETECT_SCREEN_CAPTURE`), explicit `FLAG_SECURE` suppression contrast
- [screenrecord.cpp](https://android.googlesource.com/platform/frameworks/av/+/master/cmds/screenrecord/screenrecord.cpp) — confirms `adb shell screenrecord` bypasses `MediaProjection` entirely (native `SurfaceComposerClient` capture path)
