# 04. 120 Hz rendering on Android with Flutter 3.44

Type: research
Status: resolved
Blocked by: —
Part of: ../map.md

## Question

Does a Flutter 3.44 (Impeller) app on Android render at the display's maximum refresh rate by default, or does it need a nudge (`flutter_displaymode`, `Window.preferredDisplayModeId`, `Surface.setFrameRate`)? Which device families cap Flutter at 60 Hz? How do we *measure* the achieved frame rate and frame budget (DevTools performance view, `SchedulerBinding.addTimingsCallback`, `adb shell dumpsys SurfaceFlinger --latency`, `adb shell dumpsys gfxinfo`)?

**Deliverable**: yes/no + the minimal nudge if needed + the measurement recipe the performance proof will use.

**Decisions waiting on this**: ticket 15 (spec performance section). Ticket 09 (scan visual) benefits but is not blocked.

## Answer

**Resolved 2026-09-16 by a research agent.** Findings: `docs/research/120hz-android.md` on branch `research/120hz-android`. Engine-source-verified (`vsync_waiter_android.cc`, `VsyncWaiter.java`), desk research only — nothing run on hardware.

**Answer: not guaranteed.** Impeller renders at whatever rate the display is in; the Android embedding *follows* the OS-chosen mode and never requests a higher one (unchanged in 3.44). Several OEM families (Xiaomi/HyperOS, Poco, Samsung, OnePlus, Nothing) hold third-party apps at 60 Hz; open flutter/flutter issues #160952, #192600, #151067, #157851.

**Decision for the spec**
1. **Nudge, don't assume.** Request the highest refresh-rate mode at the current resolution via `WindowManager.LayoutParams.preferredDisplayModeId` (API 23+, gate-free at minSdk 26) once at startup, plus `android:appCategory` in the manifest (API 26+) as a hedge against OEM game-optimiser heuristics (causal chain is community-sourced — UNVERIFIED). *Adjustment to the agent's recommendation*: implement this as a method on our own in-app window channel rather than adding the `flutter_displaymode` plugin — same call, no third-party dependency, and it belongs with the other window concerns. Keep `flutter_displaymode`'s source as the reference implementation. → sub-question for ticket 10.
2. **Time-based animation is already refresh-rate-agnostic**; only the per-frame budget changes. The performance assertion reads the live `Display.refreshRate` (`dart:ui`) and asserts against `1000 / refreshRate` ms — never a hardcoded 16 ms or 8 ms.
3. **Automated proof**: `IntegrationTestWidgetsFlutterBinding.watchPerformance()` around the scan animation for a fixed window while the BLoC emits progress at 10 Hz; assert `buildDuration`/`rasterDuration` percentiles under the computed budget. Cross-check on device with `adb shell dumpsys display` (active mode — ground truth) and `dumpsys gfxinfo <pkg> framestats`.
4. Validate the nudge empirically on a real 120 Hz device from one of the flagged OEM families before the spec's performance section claims anything; ticket 09 (scan prototype) is the natural place.

**Caveats carried**: no combination of app-side calls overrides an OEM power mode or a user's per-app cap; DevTools' jank threshold may not adapt to 120 Hz (verify); `dumpsys` field semantics are informally documented.
