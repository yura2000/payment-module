# 120 Hz rendering on Android with Flutter 3.44

## Question

Does a Flutter 3.44 (Impeller) app on Android render at the display's maximum refresh rate (90/120 Hz) by default, or does it need a nudge (`flutter_displaymode`, `Window.preferredDisplayModeId`, `Surface.setFrameRate`, `WindowManager.LayoutParams.preferredRefreshRate`)? What does the Flutter engine itself do today? Which device families cap third-party apps at 60 Hz, and is that app-controllable? How do we measure achieved frame rate / frame budget for an automated performance proof?

## Short answer

- **Not guaranteed.** Impeller can *render* at 120 Hz, but the Android embedding only **follows** whatever refresh rate Android has already put the window's display in — it never asks Android for a higher one. Confirmed directly in engine source (`vsync_waiter_android.cc`, `VsyncWaiter.java`) and unchanged as of the 3.44.0 release notes (no relevant entries).
- Whether you get 120 Hz "for free" is entirely an OS/OEM default. Several Xiaomi/HyperOS, Poco, Samsung, OnePlus and Nothing devices hold Flutter apps at 60 Hz (flutter/flutter #160952, #192600, #151067, #157851 — all currently open/unresolved).
- **Minimal nudge**: `flutter_displaymode` → `FlutterDisplayMode.setHighRefreshRate()` in the root widget's `initState` (wraps `Window.setPreferredDisplayModeId`, needs API 23+ — no version gate needed at this project's minSdk 26) **plus** `android:appCategory` in the manifest (API 26+, also no gate needed) as a cheap defense against OEM "is this a game?" heuristics. Neither is guaranteed to beat a hard OEM/user power-mode override.
- **Measure with**: `integration_test`'s `IntegrationTestWidgetsFlutterBinding.watchPerformance()` (wraps `SchedulerBinding.addTimingsCallback` / `FrameTiming.buildDuration` / `rasterDuration`) for the in-test automated proof; cross-check on-device with `adb shell dumpsys gfxinfo <pkg> framestats`, `dumpsys SurfaceFlinger --latency`, and `dumpsys display` (ground truth for the active mode).

## Findings

### 1. What the Flutter engine actually does on Android today

The Android embedding's vsync handling is split across a native file and a Java file, both still present on `flutter/flutter` `master` (the engine repo was merged into the `flutter/flutter` monorepo under `engine/src/flutter/`):

- **`engine/src/flutter/shell/platform/android/vsync_waiter_android.cc`** keeps a process-global `static std::atomic_uint g_refresh_rate_ = 60;` and exposes a JNI entry point `OnUpdateRefreshRate(JNIEnv*, jclass, jfloat refresh_rate)` that overwrites it. The vsync callback computes the next frame's target time as `frame_time + 1e9 / g_refresh_rate_` nanoseconds — i.e. the engine's own frame-pacing target is driven entirely by whatever value Java last pushed into it, defaulting to 60 until told otherwise.
  Source: https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/android/vsync_waiter_android.cc
- **`engine/src/flutter/shell/platform/android/io/flutter/view/VsyncWaiter.java`** is what pushes that value. It registers a `DisplayManager.DisplayListener`, and on `onDisplayChanged`/init for `Display.DEFAULT_DISPLAY` it reads `Display.getRefreshRate()` and forwards it with `flutterJNI.setRefreshRateFPS(fps)`. It does **not** call `Surface.setFrameRate()`, does **not** set `WindowManager.LayoutParams.preferredDisplayModeId`, and does not otherwise request a display-mode change.
  Source: https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/android/io/flutter/view/VsyncWaiter.java
  This listener-based design traces back to `flutter/engine` PR #29800, "Listen for display refresh changes and report them correctly" (pre-monorepo-merge history): https://github.com/flutter/engine/pull/29800

**Conclusion from source**: the engine is *reactive*, not *proactive* — it will happily pace at 120 Hz the instant Android reports the display is running at 120 Hz, but it never lobbies Android to switch into that mode. This logic lives in the Android embedding layer, independent of the Skia/Impeller rendering backend, so switching to Impeller by itself changes nothing about this story.

This matches the flutter_displaymode package's own framing of itself as "a temporary fix... until this API gets added to Flutter engine itself" (see §3) — i.e. the package author's read of the engine is the same as the one derived here directly from source.
Source: https://pub.dev/packages/flutter_displaymode

### 2. Open engine/framework issues about 60 Hz caps

All of the following were checked directly and are open or closed-unresolved as of this research (Sept 2026):

| Issue | Status | Device(s) | Notes |
|---|---|---|---|
| [flutter/flutter#160952](https://github.com/flutter/flutter/issues/160952) "Frame rate is locked to 60FPS on some android devices" | **Open**, filed 2024-12-29 | Xiaomi Poco F5, Redmi, Infinix | Reporter notes `flutter_displaymode` "does not seem to work with the latest Flutter version"; labeled `triaged-android`, `team-android`, `P2`. No engine fix landed. |
| [flutter/flutter#192600](https://github.com/flutter/flutter/issues/192600) "[Android] Flutter apps capped at 60Hz on 120Hz displays due to missing android:appCategory" | Closed as duplicate of #160952 | Xiaomi/HyperOS, Poco, Samsung, OnePlus | Reporter's own investigation theorizes that Flutter's default manifest template omits `android:appCategory`, so OEM game-optimizer services (Xiaomi Game Turbo, Samsung Game Booster) misclassify the app as an unlisted game and apply an OS-level throttle. **This causal chain is the reporter's own analysis, not a confirmed statement from Flutter/Google/OEM engineers — treat as a plausible, community-sourced theory, not a verified root cause.** |
| [flutter/flutter#151067](https://github.com/flutter/flutter/issues/151067) "App inexplicably limited to 60Hz" | Closed, unresolved (stale/no response) | Nothing Phone 2a, Android 14 | Developer option "Force peak refresh rate" had no effect; forcing split-screen mode temporarily unlocked 120 Hz. |
| [flutter/flutter#157851](https://github.com/flutter/flutter/issues/157851) "Nothing Phone 1: my phone is 120hz but the app is running on 60hz" | Closed, unresolved (stale/no response) | Nothing Phone 1 | Native apps (Facebook, Instagram, YouTube) hit 120 Hz fine on the same device; Flutter apps did not. |
| [flutter/flutter#35162](https://github.com/flutter/flutter/issues/35162) "Frame rate is locked to 60FPS on devices with frame rate optimization" | Closed | OnePlus 7 Pro (90 Hz) | The original/oldest tracking issue; this is the issue `flutter_displaymode`'s own README cites as its reason to exist. |

The Flutter 3.44.0 release notes contain no entries for refresh rate, display mode, `setFrameRate`, 90 Hz or 120 Hz — i.e. nothing shipped in 3.44 changes this behavior.
Source: https://docs.flutter.dev/release/release-notes/release-notes-3.44.0

### 3. The nudge: `flutter_displaymode`

- Package: https://pub.dev/packages/flutter_displaymode (current version 0.7.0; maintained at https://github.com/ajinasokan/flutter_displaymode). Android-only, requires **"Marshmallow and above"**, i.e. **Android API 23+** — safely below this project's minSdk 26, so **no version gate is needed**.
- API: `FlutterDisplayMode.setHighRefreshRate()` / `setLowRefreshRate()` (convenience helpers) or `FlutterDisplayMode.setPreferredMode(mode)` for an explicit `DisplayMode`. `FlutterDisplayMode.supported` lists available modes; `FlutterDisplayMode.active` reports what's actually running (which can differ from what was requested — "It is up to the system to use this mode"). Internally this is a MethodChannel wrapper around the Android `Display.Mode` API and `Window`-level preferred-mode selection (the same mechanism as `WindowManager.LayoutParams.preferredDisplayModeId`, itself added in **API level 23**).
  Source: https://pub.dev/packages/flutter_displaymode
- Placement: the setting is per-session and the README instructs calling it from `initState()` of the root widget.
- Documented limitation: "ineffective on devices with LTPO panels" (and iOS ProMotion, not relevant to this Android-only app) — LTPO panels already range their refresh rate adaptively at the OS level, so there is often nothing to "force."
  Source: https://pub.dev/packages/flutter_displaymode
- Even with the package applied, it is not bulletproof against OEM behavior: e.g. https://github.com/ajinasokan/flutter_displaymode/issues/10 "[BUG] Not working on OnePlus 9 Pro" — consistent with §2/§4's OEM-override picture.

### 4. Modern alternative: `Surface.setFrameRate` and related Window APIs

Per the Android Developers Blog post announcing it, `Surface.setFrameRate()` (and NDK equivalents `ANativeWindow_setFrameRate()` / `ASurfaceTransaction_setFrameRate()`) is a capability introduced in **Android 11 (API 30)** that lets an app declare its *intended* frame rate and leaves the platform free to choose a compatible display mode (avoiding a visible mode-switch flicker, and coexisting better with other surfaces on screen than a hard mode-switch).
Source: https://android-developers.googleblog.com/2020/04/high-refresh-rate-rendering-on-android.html

Google's current Android media docs summarize the three related APIs and when to use each:

- **`Surface.setFrameRate()`** (API 30+) — recommended default; the platform "takes a number of factors into consideration" and does not guarantee the requested rate is honored.
- **`WindowManager.LayoutParams.preferredDisplayModeId`** (API 23+) — the older mechanism; still correct when you need to force a literal display-mode/resolution switch or when `setFrameRate()` isn't available (pre-Android-11).
- **`WindowManager.LayoutParams.preferredRefreshRate`** — legacy field; explicitly **ignored on any `Surface` that has called `setFrameRate()`**; current guidance is to prefer `setFrameRate()` where possible and treat this as a fallback only.

Source: https://developer.android.com/media/optimize/performance/frame-rate ; corroborated by https://source.android.com/docs/core/graphics/multiple-refresh-rate (Android 11+ two-tier model: `DisplayManager` sets policy/min-max range, `SurfaceFlinger` picks the actual rate within it).

**Practical read for this project**: with minSdk 26, `Surface.setFrameRate()` can't be relied on alone (needs a `Build.VERSION.SDK_INT >= 30` guard, and Flutter's Dart layer has no first-party binding to it — Flutter owns its own `Surface` via `FlutterSurfaceView`/`FlutterTextureView`, so calling this natively would mean custom Kotlin in `MainActivity` or a bespoke platform channel, not something `flutter_displaymode` does today). The `Window`/`Display.Mode`-based approach (`flutter_displaymode`, API 23+) is the one that actually covers the project's entire 26+ range with an off-the-shelf package, which is why it's the recommended minimal nudge over hand-rolling `setFrameRate`.

Separately, Android 15-QPR1 introduced a View-level "Adaptive Refresh Rate" (ARR) API (`View.setRequestedFrameRate()`, gated behind `Display.hasArrSupport()`) — this is newer, View-hierarchy-oriented, and not applicable to a `minSdk 26` app that also isn't using the classic Android View rendering path for its animated content.
Source: https://developer.android.com/develop/ui/views/animations/adaptive-refresh-rate

### 5. Device families known to cap third-party apps at 60 Hz, and app-controllability

- **Samsung (One UI)**: One UI 7's Game Booster lets a user manually pick 60/120 Hz (and finer FPS caps) per game; a separate Good Lock module, "Display Assistant," explicitly lets a user force *any* chosen app to 60 Hz regardless of device capability.
  Sources: https://www.sammobile.com/news/one-ui-7-refresh-rate-switch-feature-game-booster/ , https://www.sammobile.com/news/capping-app-refresh-rate-samsung-galaxy-phones/
  → This is a **user-controlled setting**, not something the app can read or override.
- **Xiaomi/HyperOS + Poco, OnePlus, Nothing**: flutter/flutter #160952, #192600, #151067, #157851 (table in §2) report Flutter apps specifically held at 60 Hz on these OEM skins, while native/other-framework apps on the *same device* reach 120 Hz. This points at a per-app OEM classification/allowlist mechanism (e.g. "is this a game / is this categorized") rather than a blanket hardware limitation — but the precise per-OEM mechanism is not publicly documented by Xiaomi/OnePlus/Nothing, so treat the specific mechanics (beyond what's visible in the linked issues) as **UNVERIFIED**.
- **App-controllability, in practice**: best-effort only. Setting `android:appCategory` (an official manifest attribute, introduced **API level 26** — a clean match for this project's minSdk — values include `game`, `productivity`, `social`, `image`, etc.) plus requesting a high refresh mode via `flutter_displaymode` is the community-reported mitigation, but it is **not guaranteed**: e.g. the OnePlus 9 Pro report against `flutter_displaymode` itself (§3) shows the OS can still win. There is no documented, official Android or Flutter API that unconditionally forces a refresh rate against an OEM power-mode policy or a user's own Battery Saver / per-app refresh-rate setting.
  Source (appCategory attribute + values): https://developer.android.com/guide/topics/manifest/application-element

### 6. Measurement recipe

**A. In-app / DevTools, for interactive development**
`docs.flutter.dev`'s Performance view shows paired UI-thread (build) and Raster-thread bars per frame, and flags a frame as janky once total time exceeds budget; Google's own guidance is to profile in **profile mode**, not debug ("Frame rendering times aren't indicative of release performance when running in debug mode"), and to enable "Track Widget Builds / Layouts / Paints" for root-causing a slow frame.
Source: https://docs.flutter.dev/tools/devtools/performance
Open question: the doc frames the target as "60 FPS on standard devices, 120 FPS on capable devices," but it was not possible to confirm from the fetched page whether the jank threshold line DevTools draws auto-adjusts to the device's *actual current* refresh rate (~8.3 ms at 120 Hz) or stays fixed at ~16 ms regardless — **flag as open/UNVERIFIED**, and don't rely on DevTools' red/not-red coloring alone to prove 120 Hz-budget compliance; use the programmatic route below for the actual pass/fail assertion.

**B. Programmatic frame timing, for the automated proof**
- `SchedulerBinding.addTimingsCallback` registers a `void Function(List<FrameTiming>)` callback; the engine delivers batches roughly once/second in release, more often in debug/profile. Multiple callbacks can be registered independently (unlike the lower-level `PlatformDispatcher.onReportTimings`), and overhead with an active callback is documented as roughly 0.01% CPU.
  Source: https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addTimingsCallback.html
- Each `dart:ui` `FrameTiming` exposes `buildDuration` (UI-thread build time), `rasterDuration` (raster-thread time), `totalSpan` (vsync-start to raster-finish), `vsyncOverhead` (time between the vsync signal and build actually starting), plus raster/picture cache size counters.
  Source: https://api.flutter.dev/flutter/dart-ui/FrameTiming-class.html
- `dart:ui`'s `Display` class exposes `refreshRate` (a `double`, "the refresh rate in FPS of this display"), reachable at runtime via the current view's `display` (e.g. `View.of(context).display.refreshRate` / `PlatformDispatcher.instance.views.first.display.refreshRate`). Use this to compute the *actual* per-frame budget at test time (`1000 / refreshRate` ms) instead of hardcoding 16.6 ms — the same time-based `AnimationController.repeat()` painter should be checked against ~8.3 ms when the device is confirmed running at 120 Hz, and ~16.6 ms when it's only at 60 Hz.
  Source: https://api.flutter.dev/flutter/dart-ui/Display-class.html
- **This is the piece that most directly answers "how does an automated integration test assert the budget"**: `integration_test`'s `IntegrationTestWidgetsFlutterBinding.watchPerformance(action, {reportKey = 'performance'})` is the first-party helper built exactly for this. It waits ~2 s to flush stale engine timing data, registers a timings callback, runs your `action` (e.g. pump the `CustomPainter` animation while the BLoC emits progress at 10 Hz for N seconds), summarizes the collected `FrameTiming`s via `FrameTimingSummarizer`, and stores the summary in `reportData[reportKey]` for the test to assert against (average/worst/percentile build and raster times) or export as a CI artifact. It explicitly supersedes the deprecated `flutter_driver` `traceAction`/`TimelineSummary` pattern.
  Source: https://api.flutter.dev/flutter/package-integration_test_integration_test/IntegrationTestWidgetsFlutterBinding/watchPerformance.html

**C. Device-level ground truth, for cross-checking Flutter's self-reported numbers**
- `adb shell dumpsys gfxinfo <package> [framestats]` — current, officially documented Android tool; `gfxinfo` alone gives aggregate/jank-count performance info for the app's frames, `framestats` adds more granular recent-frame timing.
  Source: https://developer.android.com/tools/dumpsys
  Caveat (own inference, **UNVERIFIED against an explicit primary statement**): because Impeller/Flutter draws through its own `Surface` (`FlutterSurfaceView`/`FlutterTextureView`) rather than the classic Android `View` hierarchy, gfxinfo's per-View phase breakdown is unlikely to be meaningful for Flutter content specifically — treat its jank counters/timestamps as a coarse, OS-level cross-check rather than a full substitute for Flutter's own `FrameTiming` data.
- `adb shell dumpsys SurfaceFlinger --latency <window-name>` — prints the current refresh period followed by rows of raw present-timeline timestamps for the last ~128 frames of the named window, from which per-frame latency and the effective achieved cadence (60/90/120 Hz) can be computed independent of anything Flutter self-reports. This is long-standing, stable AOSP debug tooling; conceptual background on the underlying VSYNC/SurfaceFlinger pipeline is documented at https://source.android.com/docs/core/graphics/implement-vsync, but a current, dedicated Google doc page spelling out `--latency`'s exact column semantics could not be located (Android's older "Testing Display Performance" training doc that used to cover it appears retired) — **flag the precise output-format description as UNVERIFIED against a live primary source**, even though the command's existence and general behavior are well-established.
- `adb shell dumpsys display` — dumps `DisplayManagerService` state, including each display's supported modes and which mode is currently active (resolution + refresh rate) — use it to confirm what the OS actually granted the app's window at the moment of measurement (i.e., distinguish "Flutter isn't keeping up with 120 Hz" from "the OS never switched the display into a 120 Hz mode for this app at all"). Same caveat as `--latency`: well-established, stable tooling, but no single current official doc page enumerating its exact output was found — **flag as UNVERIFIED against a live primary source** for output-format specifics.

## Recommendation

1. **Ship the nudge, don't assume the default.** Add `flutter_displaymode` and call `FlutterDisplayMode.setHighRefreshRate()` once in the root widget's `initState` (API 23+ — no `Build.VERSION.SDK_INT` gate needed at minSdk 26). Add `android:appCategory="productivity"` (or whatever fits the app) to `AndroidManifest.xml` (API 26+ — also gate-free at this minSdk) as a low-cost hedge against OEM game-optimizer misclassification. Treat both as best-effort: per §4/§5, no combination of app-side calls is guaranteed to overturn an OEM power-mode policy or a user's own per-app refresh-rate cap.
2. **Design the spec's performance section around a measured, not assumed, refresh rate.** Because the project's animation is already time-based (`AnimationController.repeat()` driving a `CustomPainter` via `repaint:`, correct at any cadence), the *rendering* is refresh-rate-agnostic by construction — the only thing that changes is how tight the per-frame budget is. So the performance assertion should read the device's actual active refresh rate at test time (`Display.refreshRate`) and assert against `1000 / refreshRate` ms per frame, rather than hardcoding either 16 ms or 8 ms.
3. **Automated proof**: wrap the BLoC-driven `CustomPainter` animation in `IntegrationTestWidgetsFlutterBinding.watchPerformance()`, run it for a fixed window while the BLoC emits progress at 10 Hz, and assert `buildDuration`/`rasterDuration` percentiles from the resulting summary stay under the computed per-frame budget. Optionally cross-check the same run with `adb shell dumpsys gfxinfo <pkg> framestats` and `dumpsys display` in CI/manual device runs for an OS-level sanity check independent of the engine's self-reported numbers.
4. A CustomPainter prototype is worth building specifically to validate step 1 empirically on a real 120 Hz device the team has access to (ideally one of the OEM families flagged in §5) — the desk research above establishes the mechanism and the caveats, but only an on-device run of `dumpsys display` before/after applying the nudge will show whether it actually takes effect on that specific hardware.

## Open questions / caveats

- The `android:appCategory` → OEM-throttle causal chain (flutter/flutter#192600) is the issue reporter's own reverse-engineering, not a statement confirmed by Flutter, Google, or the OEMs involved. It's the best public explanation found, but should be verified empirically (see Recommendation §4) rather than trusted blindly.
- Whether DevTools' Performance-view jank threshold auto-adjusts to the display's actual active refresh rate (vs. a fixed ~16 ms line) could not be confirmed from the fetched documentation — verify directly in DevTools on a 120 Hz device before relying on its coloring for a 120 Hz claim.
- Exact column/field semantics of `adb shell dumpsys SurfaceFlinger --latency` and `adb shell dumpsys display` output could not be pinned to a current, official Google doc page (both appear to be long-lived but only informally documented AOSP debug surfaces at this time) — the behavior described above is corroborated by secondary/community sources and general AOSP VSYNC documentation, not a single authoritative reference page. Treat as reliable-by-long-standing-convention rather than contractually stable.
- Whether `gfxinfo`'s per-frame/per-View breakdown is meaningful for Impeller-rendered content (as opposed to just its aggregate jank counters) is this document's own inference from how Impeller composites its own `Surface`, not something an Android or Flutter doc states explicitly either way.
- Not verified on real hardware as part of this research: no device was available to actually run `dumpsys display` / `SurfaceFlinger --latency` against a build of this app; all of §1–§6 is desk research against source and docs, not an empirical reproduction.
- flutter/flutter#160952 (the main open tracking issue) had no visible Flutter-team engineering comment in what WebFetch could render (GitHub's issue page may lazy-load later comments); the "still open, no confirmed fix" conclusion is based on its open/closed state and the absence of any relevant change in the 3.44.0 release notes, not a maintainer's explicit "not fixed" statement.

## Sources

Flutter engine / framework / docs:
- https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/android/vsync_waiter_android.cc
- https://github.com/flutter/flutter/blob/master/engine/src/flutter/shell/platform/android/io/flutter/view/VsyncWaiter.java
- https://github.com/flutter/engine/pull/29800
- https://github.com/flutter/flutter/issues/192600
- https://github.com/flutter/flutter/issues/160952
- https://github.com/flutter/flutter/issues/151067
- https://github.com/flutter/flutter/issues/157851
- https://github.com/flutter/flutter/issues/35162
- https://docs.flutter.dev/release/release-notes/release-notes-3.44.0
- https://docs.flutter.dev/tools/devtools/performance
- https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addTimingsCallback.html
- https://api.flutter.dev/flutter/dart-ui/FrameTiming-class.html
- https://api.flutter.dev/flutter/dart-ui/Display-class.html
- https://api.flutter.dev/flutter/package-integration_test_integration_test/IntegrationTestWidgetsFlutterBinding/watchPerformance.html

pub.dev / packages:
- https://pub.dev/packages/flutter_displaymode
- https://github.com/ajinasokan/flutter_displaymode
- https://github.com/ajinasokan/flutter_displaymode/issues/10

Android:
- https://developer.android.com/media/optimize/performance/frame-rate
- https://source.android.com/docs/core/graphics/multiple-refresh-rate
- https://developer.android.com/develop/ui/views/animations/adaptive-refresh-rate
- https://android-developers.googleblog.com/2020/04/high-refresh-rate-rendering-on-android.html
- https://developer.android.com/guide/topics/manifest/application-element
- https://developer.android.com/tools/dumpsys
- https://source.android.com/docs/core/graphics/implement-vsync

OEM behavior (secondary, cited for device-family claims only):
- https://www.sammobile.com/news/one-ui-7-refresh-rate-switch-feature-game-booster/
- https://www.sammobile.com/news/capping-app-refresh-rate-samsung-galaxy-phones/
