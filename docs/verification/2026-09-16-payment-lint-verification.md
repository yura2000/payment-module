# payment lint verification — 2026-09-16

Verified against `docs/architecture.md` §3.3, §4, §5, §7, §7.1.

- `security_guard_via_barrel`: confirmed firing when `payment` code imports `security_guard`'s
  `src/` directly instead of its barrel (temporary violation added to `can_pay.dart`, rule name
  observed in the output, reverted). This is also verified honestly in the passing codebase —
  both real touch points (`PayPressed.verdict`'s `PolicyVerdict`, `canPay`'s `PostureState`)
  import through `security_guard/security_guard.dart`.
- `no_reverse_dependency`: confirmed firing when `security_guard` code imports anything from
  `features/payment` (temporary violation added to `security_posture.dart`, rule name observed
  in the output, reverted). `security_guard` genuinely imports nothing from `payment` in the
  passing codebase — the dependency only ever runs one way.
- Both rules were inert from Plan 2 (added ahead of need, `features/payment` didn't exist) until
  this plan; deferred verification promised in Plan 2's own verification note is now discharged.
- Full suite: `flutter test` — 109 tests passing.
- `payment` is feature-complete against fakes: domain model, both ports, `PaymentConfirmationBloc`
  covering every row of §7.1, `canPay`, and `registerPaymentModule`. `InMemoryPaymentRepository`
  is a real (non-fake) adapter — the one production adapter this plan ships. No channel adapter,
  page, section widgets, or brand wiring exist yet — those are the native-bridge and
  composition-root plans.
