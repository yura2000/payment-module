---
status: accepted
date: 2026-09-16
---
# Use cases exist only where a decision or orchestration lives

Textbook Clean Architecture puts a use-case class between every BLoC and every port. Applying the deletion test to the first design showed four of five use cases were one-line delegations with a single caller (`LoadPayment`, `ConfirmPayment`, `FindInFlightJob`, `WatchSecurityPosture`); deleting them made nothing reappear anywhere. We removed them: `PaymentConfirmationBloc` uses the `PaymentRepository` and `PaymentProcessor` ports directly, and the one use case that carries logic — `WatchPostureVerdict`, which kicks off assessment, merges the posture stream and applies the brand's Posture Policy — stays. The rule for new code: a use case must own a decision or an orchestration; delegation is not a reason to exist.

## Consequences

- Fewer files and a BLoC whose collaborators are the ports themselves; tests drive it through scripted fakes of those ports.
- A reader expecting a use case per operation will find this deliberate, not forgotten.
