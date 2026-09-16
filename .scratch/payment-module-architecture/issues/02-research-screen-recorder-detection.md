# 02. Screen-recorder detection across API levels

Type: research
Status: resolved
Blocked by: —
Part of: ../map.md

## Question

How can the app detect an *active* screen recorder on API 26–36?

Primary path: API 35 `WindowManager.addScreenRecordingCallback` / `SCREEN_RECORDING_STATE_VISIBLE`, the `DETECT_SCREEN_RECORDING` permission (normal or runtime?), threading of the callback, and its behaviour when the window already has FLAG_SECURE. Below 35: is there any official signal (MediaProjection sessions aren't observable by other apps); what fallbacks exist (known recorder packages / foreground services, `DisplayManager` virtual displays) and how reliable they are.

**Deliverable**: a tiered approach with an explicit `unknown` state on unsupported API levels, how it interacts with the Secure Window, and what the demo can show.

**Decisions waiting on this**: ticket 10 (channel contract), ticket 07 (whether `SecurityPosture` needs an `unknown` Threat state — update `CONTEXT.md` if so).

## Answer

**Resolved 2026-09-16 by a research agent.** Findings: `docs/research/screen-recorder-detection.md` on branch `research/screen-recorder-detection` (`git show research/screen-recorder-detection:docs/research/screen-recorder-detection.md`). AOSP-source-verified.

**Decision**: tiered detection with an honest third state.

| API | Signal | Native state |
|---|---|---|
| 35+ | `WindowManager.addScreenRecordingCallback` — fires for **any** MediaProjection session (system recorder, 3rd-party, screen-share); keeps firing while our window has `FLAG_SECURE` | `visible` / `notVisible`, event-driven |
| 26–34 | none official (other apps' MediaProjection sits behind a signature `@hide` permission); every fallback (known packages, `DisplayManager` virtual displays, FGS enumeration) is unreliable or blocked → **do not wire any of them** | `unknown` |

- `DETECT_SCREEN_RECORDING` is a **normal** permission (manifest only, no runtime prompt).
- Registration is a blocking Binder round-trip → `Dispatchers.IO`; pass `ContextCompat.getMainExecutor(context)` as the callback `Executor` so events already land on main before the `EventSink`. Unregister with `removeScreenRecordingCallback` when the observing screen stops.
- The callback's return value is the live current state (use it for the initial posture); subsequent transitions stream. → The posture is **live**, not only re-assessed on resume.
- `adb shell screenrecord` bypasses MediaProjection entirely → no callback (and FLAG_SECURE blanks it anyway). `DETECT_SCREEN_CAPTURE` / `registerScreenCaptureCallback` (API 34) is *screenshot* detection, a different feature — don't conflate in the contract.
- Why detect at all when FLAG_SECURE already blanks pixels: prevention (compositor guarantee) and detection (app-level signal) are independent layers; detection lets the app explain the black rectangle, apply the Posture Policy, and log the event.

**Domain impact → ticket 07**: Security Posture needs a third state distinct from Secure and Compromised. Shape to decide there: whole-posture `Unknown` vs per-threat assessment (`detected | clear | unavailable`) with posture derived. Also on API 35+ there is a transient unknown before the first callback registration resolves. `CONTEXT.md` (Security Posture, Security Scan) must be updated when 07 settles it.

**Contract impact → ticket 10**: the environment channel needs an event stream (posture changes), not just a request/response; `unknown` is a wire value for API < 35.

**Demo guidance** (map Notes): positive recorder case needs an API 35+ device/emulator and the Quick Settings *Screen Record* tile (or any screen-share app); show the callback banner side by side with the black rectangle in the recording. An API < 35 emulator shows `unknown` explicitly. Recording the *deliverable video* itself: FLAG_SECURE blanks `adb screenrecord` and MediaProjection recorders — plan to record via the emulator's host-side recorder or an external camera (UNVERIFIED for the emulator recorder; test early).

**Caveats carried**: FLAG_SECURE-doesn't-suppress-callback is source-verified but not stated in prose docs — worth a quick spike on a real API 35+ device; non-MediaProjection OEM capture paths are undetectable; the `screen_recording_callbacks` trunk-stable flag was not confirmed on every OEM build.
