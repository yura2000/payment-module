# 07. Payment state machine

Type: grilling
Status: resolved
Blocked by: —
Part of: ../map.md

## Question

Define the state machine that drives the Payment Confirmation flow and who owns which part.

- Domain vocabulary: `SecurityPosture` (secure / compromised(threats) / unknown?), `PaymentJobProgress` (queued / running(percent) / succeeded / failed(reason)), how `PosturePolicy` is applied (use case or pure function), which of these live in `core` vs the feature domains.
- BLoC shape: one `PaymentBloc` vs a `SecurityBloc` + `PaymentBloc` composed by the page. Events (opened, resumed, postureAssessed, payTapped, progressChanged, jobFinished) and states (scanning, ready, blocked(reasons), warned(reasons), processing(percent), succeeded, failed).
- Scenarios to stress: posture degrades while processing (map rule: job completes, result shows warning); app backgrounded mid-job and resumed; job fails at 60 %; scan finishes before the animation's minimum display time; double-tap on Pay; back navigation during processing.

**Deliverable**: the state/event table, the one-vs-two-Blocs decision, and the type placement. Update `CONTEXT.md` for any new term.

**Inputs from resolved research**
- Ticket 02 (screen recorder): below API 35 there is no signal at all, so "Secure" cannot be asserted for that Threat — Security Posture needs a third state. Decide its shape here: whole-posture `Unknown`, or per-threat assessment (`detected | clear | unavailable`) with the posture derived from the set (recommended starting point: per-threat, because root detection *can* still say "clear" on API < 35 while recorder detection cannot). Decide how each Posture Policy treats `unavailable` (Retail: proceed with a notice? Utility: block?). On API 35+ the recorder signal is a **live callback**: the posture can change while the screen is open → the machine needs a `postureChanged` event from a stream, not just entry + resume. Update `CONTEXT.md` (Security Posture, Security Scan) once settled.
- Ticket 01 (root): root detection is a one-shot ≥2-signal heuristic, re-run on entry/resume; it has no `unavailable` case.

## Answer

**Resolved 2026-09-16 (grilling, 2 rounds, all recommendations accepted).**

### Decisions
1. **Security Posture is per-threat.** `ThreatAssessment(kind, result)` with `result ∈ {detected, clear, unavailable(reason: apiLevel | error)}`; `SecurityPosture` wraps the set and derives a classification: **Secure** (all clear) · **Compromised** (any detected) · **Unverified** (none detected, ≥ 1 unavailable). Rationale: root detection can say "clear" on every API level, recorder detection cannot below API 35 — only per-threat results keep that information.
2. **Posture Policy** gains an `unavailable` verb: per `ThreatKind`, `onDetected: block | warn` and `onUnavailable: allow | notice`. Brand values — Retail: rooted→block, screenRecording→warn, unavailable→**allow**. Utility: both→block, unavailable→**notice**. Never block on "can't tell": the Secure Window already *prevents* recording; detection is defence-in-depth.
3. **Payment Job vocabulary**: `PaymentJobProgress = Running(percent) | Succeeded(PaymentReceipt) | Failed(PaymentFailure)`; `PaymentFailure = declined | timedOut | serviceUnavailable`; `PaymentReceipt(reference, completedAt)`. No `Queued`, **no cancel** (out of scope). The simulation declines deterministically (amount cents == 99) so the demo can show failure.
4. **One BLoC**: `PaymentConfirmationBloc` in `payment/presentation`, composing `WatchSecurityPosture`, `EvaluatePosturePolicy`, `LoadPayment`, `ConfirmPayment`. A separate `SecurityPostureBloc` failed the deletion test. The scan animation is driven by its own `AnimationController` and only reads the phase.
5. **Composite state with a sealed phase**: `{ payment?, posture, verdict, phase }`, `ConfirmationPhase = Scanning | AwaitingConfirmation | Processing(progress) | Completed(outcome)`; `canPay ⇔ phase is AwaitingConfirmation ∧ ¬verdict.isBlocked ∧ payment ≠ null`. Posture/verdict update in any phase.
6. **Scan phase** lasts at least the brand motion token `scanMinDuration` (Retail ≈ 2.0 s, Utility ≈ 1.2 s) and ends when both the first assessment and the timer have arrived. Re-assessment on resume is **silent** (no second Scan).
7. **Guards**: `PayPressed` ignored unless `canPay`; back blocked (`PopScope(canPop: false)`) only while `Processing`.
8. **Retry** in scope: `RetryPressed` on `Completed(Failed)` → `AwaitingConfirmation` (verdict re-evaluated).
9. **Placement** (provisional until ticket 13): `core` — `ThreatKind`, `PosturePolicy` (data), `Money`, `BrandId`, exceptions. `security_guard/domain` — `ThreatAssessment`, `SecurityPosture`, `PolicyVerdict`, port `SecurityEnvironment`, use cases `WatchSecurityPosture`, `EvaluatePosturePolicy`. `payment/domain` — `Payment`, `LineItem`, `PaymentJobProgress`, `PaymentFailure`, `PaymentReceipt`, `PaymentRepository` (in-memory), port `PaymentProcessor` (native), use cases `LoadPayment`, `ConfirmPayment`. Ports are named by role (`PaymentProcessor`, not `*Service` — the Kotlin class is `PaymentJobService`).
10. **Result is a phase of the same route** (result *view*, not page): no BLoC sharing across routes; the Secure Window is held until the user pops the flow.
11. Brand `onUnavailable` values as in (2): Retail `allow`, Utility `notice` — a visible behavioural difference between brands on API ≤ 34 devices.

### Domain values
```
core            ThreatKind = rooted | screenRecording
                PosturePolicy { onDetected: {ThreatKind → block | warn}, onUnavailable: {ThreatKind → allow | notice} }
security_guard  AssessmentResult = detected | clear | unavailable(reason: apiLevel | error)
                ThreatAssessment(kind, result)
                SecurityPosture { assessments } → Secure | Compromised | Unverified
                PolicyVerdict { blockers, warnings, notices : Set<ThreatKind>; isBlocked ⇔ blockers ≠ ∅ }
payment         Payment { amount: Money, payee, lineItems }
                PaymentJobProgress = Running(percent) | Succeeded(PaymentReceipt) | Failed(PaymentFailure)
                PaymentFailure = declined | timedOut | serviceUnavailable
                PaymentReceipt(reference, completedAt)
```

### Ports and use cases (shapes provisional until ticket 13)
```
SecurityEnvironment { Future<void> assess(); Stream<SecurityPosture> get posture }
   — one source of truth: assess() re-runs the one-shot checks and pushes; the recorder callback pushes on its own (API 35+)
WatchSecurityPosture()        → Stream<SecurityPosture>      (subscribes, triggers the first assess())
EvaluatePosturePolicy(policy) → PolicyVerdict               (pure)
LoadPayment()                 → Future<Payment>
ConfirmPayment(payment)       → Stream<PaymentJobProgress>   (starts the job; throws ServiceException if it cannot start)
PaymentProcessor.inFlight     → Stream<PaymentJobProgress>?  (relaunch re-attach; mechanism = ticket 12)
```
Adapter rule: a `PlatformException` during a check becomes `unavailable(error)` for that threat — never an exception into the BLoC.

### `PaymentConfirmationBloc`
State `{ payment?, posture, verdict, phase }`. Events from the page: `Started`, `Resumed` (AppLifecycleListener), `PayPressed`, `RetryPressed`; internal: `PostureChanged`, `PaymentLoaded`, `ScanTimerElapsed`, `JobProgressed`.

| Phase | Event | Guard | → Phase | Effects |
|---|---|---|---|---|
| *(initial)* | `Started` | no in-flight job | `Scanning` | `WatchSecurityPosture`, `LoadPayment`, start `scanMinDuration` timer |
| *(initial)* | `Started` | in-flight job | `Processing(progress)` | `WatchSecurityPosture`, subscribe to the job — no Scan phase |
| `Scanning` | `PostureChanged` / `ScanTimerElapsed` | other still pending | `Scanning` | update posture/verdict |
| `Scanning` | *(both arrived)* | — | `AwaitingConfirmation` | — |
| `AwaitingConfirmation` | `PostureChanged` | — | same | verdict re-evaluated → CTA/banner |
| `AwaitingConfirmation` | `PayPressed` | `canPay` | `Processing(Running 0)` | `ConfirmPayment` |
| `AwaitingConfirmation` | `PayPressed` | `¬canPay` | same | ignored |
| `Processing` | `JobProgressed(Running p)` | — | `Processing(p)` | — |
| `Processing` | `JobProgressed(Succeeded r \| Failed f)` | — | `Completed(outcome)` | — |
| `Processing` | `PostureChanged` | — | same | verdict updated; job continues |
| `Processing` | `PayPressed` / back | — | same | ignored / `PopScope(canPop: false)` |
| `Processing` | `ConfirmPayment` throws | — | `Completed(Failed serviceUnavailable)` | exception → value at the BLoC boundary |
| `Completed(Failed)` | `RetryPressed` | — | `AwaitingConfirmation` | verdict re-evaluated |
| `Completed(Succeeded)` | — | terminal until pop | — | result view shows verdict caveats |
| *any* | `Resumed` | — | same | `assess()` — silent |

Scenarios covered: degrade while processing · backgrounded mid-job (job survives; process death → in-flight row) · fails at 60 % → retry · scan finishes before the timer · double-tap · back during processing.

### Consequences pushed
- `CONTEXT.md`: Security Posture (three classifications), Threat Assessment, Policy Verdict, Posture Policy (unavailable verb), Security Scan (once; silent re-assessment), Receipt, Payment Failure, Result View.
- Ticket 10: wire vocabulary for per-threat results and job progress/failures; `assess()` + posture stream shape; in-flight job query.
- Ticket 11: result is the same route → Secure Window held until pop; back blocked only in `Processing`.
- Ticket 12: `inFlight` re-attach is a requirement; cancel is out of scope.
- Tickets 08/09/15: `scanMinDuration` is a brand motion token.
- Map: retry graduated from the fog (decided); cancelling a Payment Job added to Out of scope.

## Addendum (from ticket 12, 2026-09-16)
`Started` when `PaymentProcessor.inFlight` reports a **terminal** snapshot (the job finished while the app was away) → enter `Completed(outcome)` directly — the Result View — not `Processing`. The in-flight row stands for `running` snapshots.

## Addendum (from ticket 13, 2026-09-16)
Collaborators revised: `PaymentConfirmationBloc` depends on `PaymentRepository`, `PaymentProcessor` and the single deep use case `WatchPostureVerdict` (posture + verdict stream). `LoadPayment`, `ConfirmPayment`, `FindInFlightJob`, `WatchSecurityPosture` and the `EvaluatePosturePolicy` class are gone (pure delegation; `evaluatePosturePolicy` survives as a pure function inside the use case). Events, states and transitions are unchanged.

## Addendum (2026-09-16, after map completion — revision of decisions 4 and 5)
At the user's request the single composite bloc is split into **two units on the feature seam**: `SecurityPostureCubit` (`security_guard/presentation`; subscribes to `WatchPostureVerdict`, `onResumed()` → `assess()`; state `{posture?, verdict?, hasFirstAssessment}`) and a **posture-free** `PaymentConfirmationBloc` (`payment/presentation`; state `{payment?, phase}`; events `Started`, `PayPressed(verdict)`, `RetryPressed`, `PaymentLoaded`, `ScanTimerElapsed`, `JobProgressed`). Cross-concern rules are pure derived functions in the page (`canPay(flow, posture)`; banners and the Result-View caveat read the cubit); no `BlocListener` relays. `PayPressed` carries the verdict so the machine still guards against a blocked posture. Rule change: **Scanning ends on the `scanMinDuration` timer alone**; the CTA waits separately for `hasFirstAssessment`. Degrade-mid-job and retry-re-evaluates now fall out of the split instead of being coded. Final tables in spec §7.1–7.2. The `SecurityPostureCubit`'s justification is separation and reuse, not depth — stated as such.
