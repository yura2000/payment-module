# security_guard lint verification — 2026-09-17

Verified against `docs/architecture.md` §3.3, §4, §5, §7.2, §8, §11.

- `domain_no_flutter`, `domain_no_presentation`, `presentation_no_data`, `domain_no_data`: each
  confirmed firing under `dart analyze --fatal-infos` (temporary violation added, rule name
  observed in the output, reverted).
- `security_guard_via_barrel`, `no_reverse_dependency`: **not yet verifiable** —
  `lib/features/payment/` does not exist. Verify in the payment feature's implementation plan,
  immediately after `features/payment` is created.
- Full suite: `flutter test` — 57 tests passing.
- `security_guard` is feature-complete against fakes: domain model, both ports, the one use
  case, `SecurityPostureCubit`, `SecureWindowController`, `SecureSessionScope`, and
  `registerSecurityModule`. No native adapter exists yet — that's the native-bridge plan.
