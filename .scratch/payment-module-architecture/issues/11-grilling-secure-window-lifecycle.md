# 11. Secure Window lifecycle

Type: grilling
Status: resolved
Blocked by: 10
Part of: ../map.md

## Question

How is FLAG_SECURE held exactly while a payment screen is visible? A `SecureWindow` widget (initState/dispose) wrapping each payment page + a ref-counted `SecureWindowController` in `security_guard` (stacked pages, dialogs, transitions don't flicker) vs a `RouteObserver`. Re-assert on `AppLifecycleState.resumed`; behaviour on Activity recreation (config change): Kotlin stateless with Dart re-asserting, or Kotlin persists? Does the result page stay secure; drop on pop?

**Deliverable**: the mechanism, its invariants, and the scenarios it is tested against.

**Inputs from resolved tickets**
- Ticket 07: the result is a **view of the same route**, so the Secure Window is held from page open until the user pops the flow — no route change on completion. Back is blocked (`PopScope`) only while `Processing`, so pops happen from `AwaitingConfirmation` or `Completed`. The recorder callback registration (ticket 02) has the same lifetime as the Secure Window — consider one lifecycle owner for both.
- Ticket 10: `window.setSecure({secure})` is idempotent; `noActivity` is transient (config change) → re-assert on resume. The posture event subscription (`security.environment/events`) registers/unregisters the recorder callback on listen/cancel — decide here whether one presentation-layer owner (e.g. a `SecureSessionScope` widget) drives both `setSecure` and the posture subscription for the page's lifetime.
- Ticket 12: the job subscription belongs to the BLoC (per-job stream, completes on a terminal state); the posture subscription + Secure Window belong to the page's lifetime — two owners, don't merge them. `configChanges` in the template means Activity recreation is not a case to design for; `noActivity` remains a defensive mapping only.

## Answer

**Resolved 2026-09-16 (grilling, 1 round; all recommendations accepted).**

### Decisions
1. **Mechanism**: `SecureSessionScope` (`StatefulWidget`, `security_guard/presentation`) wraps the payment page's content — `initState` → `controller.acquire()`, `dispose` → `controller.release()`. Behind it a **ref-counted** `SecureWindowController` (lazy singleton, `security_guard/presentation`) over the `SecureWindow` domain port: `setSecure(true)` only on 0→1, `setSecure(false)` only on 1→0. `RouteObserver` rejected (per-route registration; misbehaves with dialogs and nested navigators). Stacked secure routes are safe because routes below stay mounted; dialogs need nothing.
2. **Ownership**: the *route* is the single lifetime owner; two objects share it — the scope (window flag) and the `PaymentConfirmationBloc` (posture subscription → recorder callback via the adapter's `onListen`). Not merged: the widget would have to know the BLoC, coupling `security_guard` to `payment`. Spec wording: "one lifetime, two owners".
3. **Resume and errors**: the controller owns an `AppLifecycleListener`; on `resumed`, if `count > 0`, re-assert `setSecure(true)` (idempotent). A `ServiceException` from `acquire` (transient `noActivity`) is logged and retried on resume, never surfaced. The page keeps its own `AppLifecycleListener` for the BLoC's `Resumed` event.
4. **Kotlin is stateless**: `WindowHandler.setSecure` → `window.addFlags(FLAG_SECURE)` / `clearFlags`; Dart is the single source of truth. Process death restarts Dart, which re-acquires on the first frame.
5. **Launch gap accepted**: `acquire()` is async from `initState`; the Android embedding shows the launch theme until Flutter's first frame and the platform message is handled within the same vsync window, so nothing sensitive is exposed. Secure-by-default in `onCreate` rejected for a one-route module (dead release path; reads as global). Revisit only if a non-secure route (dev-only brand picker, fog) ever exists.

### Invariants
(i) the flag is set whenever `count > 0` and cleared whenever `count == 0`; (ii) the Result View is part of the same route (ticket 07), so it stays secure until pop; (iii) `release` on the last scope is the only path that clears the flag; (iv) `PopScope(canPop: false)` during `Processing` is the BLoC/page's rule — the scope never blocks navigation.

### Scenarios (widget tests against a recording fake `SecureWindow`)
| # | Scenario | Expected calls |
|---|---|---|
| 1 | Page mounted | `setSecure(true)` × 1 |
| 2 | Dialog shown / dismissed over the page | none |
| 3 | Second secure route pushed, then popped | none, none |
| 4 | App paused → resumed with the page mounted | `setSecure(true)` × 1 (re-assert) |
| 5 | Job completes → Result View | none (same route) |
| 6 | Pop the flow | `setSecure(false)` × 1 |
| 7 | `acquire` throws `ServiceException` | swallowed + logged; next resume → `setSecure(true)` |
| 8 | Back pressed during `Processing` | blocked by `PopScope`; scope untouched |

Plus one `TestDefaultBinaryMessengerBinding` contract test for the `window` channel (`setSecure` args; `noActivity` → `ServiceException`).

### Consequences pushed
- Ticket 13: `security_guard` exports `SecureSessionScope` + `SecureWindowController` (presentation) and the `SecureWindow` port; `ChannelWindow` stays in `src/`.
- Ticket 15: invariants + scenario table verbatim; the launch-gap reasoning; "one lifetime, two owners".

## Addendum (2026-09-16)
"One lifetime, two owners" now names `SecureSessionScope` and `SecurityPostureCubit` (the cubit owns the posture subscription after the two-bloc split).
