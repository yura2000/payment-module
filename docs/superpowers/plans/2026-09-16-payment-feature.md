# payment Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `payment` feature's domain model, ports, `PaymentConfirmationBloc` (the full flow machine, §7.1's transition table, against fakes), the `canPay` derived display rule, and `registerPaymentModule` — no native (Kotlin) adapter, no page or section widgets, no brand wiring yet. This is also what finally makes `security_guard_via_barrel` and `no_reverse_dependency` — wired into `analysis_options.yaml` since Plan 2 but inert because `lib/features/payment/` didn't exist — verifiable.

**Architecture:** Third of five implementation plans (Plan 1: workspace/core/brand_engine, done; Plan 2: security_guard, done — `develop` at commit `8dd6b49`). `payment` depends on `core`, `brand_engine`, and `security_guard` — through `security_guard`'s barrel only, never its `src/`, which is exactly the rule `security_guard_via_barrel` enforces. Per `docs/adr/0005-use-cases-only-where-logic-lives.md`, `PaymentConfirmationBloc` talks to `PaymentRepository` and `PaymentProcessor` directly — there is no use case in this feature, unlike `security_guard`'s one (`WatchPostureVerdict`). The bloc never subscribes to Security Posture; the one posture fact it needs (a `PolicyVerdict`) arrives inside the `PayPressed` event, so the two features' presentation layers stay mutually unaware — see `docs/architecture.md` §7's "two blocs, split on the feature seam". `docs/architecture.md` §5, §7, §7.1 are the source of truth for every shape below; `CONTEXT.md` for every domain term.

**Tech Stack:** Flutter 3.44.6 / Dart 3.12 via FVM. No new dependencies — `equatable`, `flutter_bloc`, `get_it`, `bloc_test` were all added in Plan 2 and already cover everything this plan needs (confirmed against the current `pubspec.yaml`).

**Carry-forward from Plans 1–2** (apply automatically, don't re-derive): the lint command is `dart analyze --fatal-infos`, never `flutter analyze`; every `import_lint` rule needs an explicit `except: []`; both feature-pair rules already exist in `analysis_options.yaml` (added by Plan 2 Task 1, ahead of need) — this plan verifies them, it does not add them.

**Reference:** `docs/architecture.md` §4 (module interfaces — `features/payment`'s exact export list), §5 (domain model), §5.1 (ports), §7 (the two-bloc split and why), §7.1 (`PaymentConfirmationBloc`'s full transition table). `docs/adr/0005-use-cases-only-where-logic-lives.md` for why this feature has no use case at all.

**Scope boundary — what this plan does NOT build:** `ChannelPaymentProcessor`, `JobSnapshotCodec` (the real Kotlin-backed adapter and its wire codec — native-bridge plan; no channel exists yet). `PaymentConfirmationPage`, the `PaymentSection` hierarchy (`SummarySection`, `PromoBannerSection`, `BillBreakdownSection`, `PayButtonSection`, `CustomSection`), `PaymentBrandConfig` (composition-root plan — these need real `BrandConfig` instances, `BuildContext`, and money formatting via `intl`, none of which this plan has a reason to add yet). This plan's success criterion: `flutter test` passes with `payment`'s domain model, both ports, `PaymentConfirmationBloc` (every row of §7.1), and `canPay` fully covered against fakes, and both feature-pair lint rules are verified firing.

---

## File structure

```
lib/features/payment/
├── payment.dart                              # new — barrel, grown incrementally across Tasks 1–9
├── di.dart                                   # new — registerPaymentModule
└── src/
    ├── domain/
    │   ├── payment_job_progress.dart         # new — PaymentFailure, PaymentReceipt, PaymentJobProgress (Running|Succeeded|Failed)
    │   ├── payment.dart                      # new — LineItem, Payment
    │   ├── payment_repository.dart           # new — port
    │   └── payment_processor.dart            # new — port
    ├── data/
    │   └── in_memory_payment_repository.dart # new — the demo production adapter (§2 principle 2)
    └── presentation/
        ├── payment_confirmation_state.dart   # new — PaymentPhase (Scanning|AwaitingConfirmation|Processing|Completed), PaymentConfirmationState
        ├── payment_confirmation_event.dart   # new — Started, PayPressed, RetryPressed, PaymentLoaded, ScanTimerElapsed, JobProgressed
        ├── payment_confirmation_bloc.dart    # new — the flow machine, §7.1
        └── can_pay.dart                      # new — canPay(flow, posture), imports security_guard via its barrel

test/
├── support/fakes/
│   ├── fake_payment_repository.dart          # new
│   └── fake_payment_processor.dart           # new
└── features/payment/
    ├── payment_job_progress_test.dart        # new
    ├── payment_test.dart                     # new
    ├── in_memory_payment_repository_test.dart # new
    ├── payment_confirmation_state_test.dart  # new
    ├── payment_confirmation_event_test.dart  # new
    ├── payment_confirmation_bloc_test.dart   # new — every row of §7.1
    ├── can_pay_test.dart                     # new
    └── di_test.dart                          # new

docs/verification/
└── 2026-09-16-payment-lint-verification.md   # new — Task 10's audit note
```

`PaymentFailure`, `PaymentReceipt`, and `PaymentJobProgress` are folded into one file (Task 1) — `PaymentJobProgress.Succeeded` wraps `PaymentReceipt` and `.Failed` wraps `PaymentFailure`, so the three change together (`codebase-design`: files that change together live together). Same reasoning folds `Payment` and `LineItem` into one file (Task 2), and `PaymentPhase` into `PaymentConfirmationState`'s file (Task 6) rather than the events' file — `PaymentPhase` is part of the *state* shape, not a message.

---

### Task 1: `PaymentFailure`, `PaymentReceipt`, `PaymentJobProgress`

**Files:**
- Create: `lib/features/payment/payment.dart` (barrel — created here, grown through Task 9)
- Create: `lib/features/payment/src/domain/payment_job_progress.dart`
- Test: `test/features/payment/payment_job_progress_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/features/payment/payment.dart';

void main() {
  group('PaymentReceipt', () {
    test('two receipts with the same reference and completion time are equal', () {
      final completedAt = DateTime.utc(2026, 9, 16, 12);
      expect(
        PaymentReceipt(reference: 'PAY-1', completedAt: completedAt),
        equals(PaymentReceipt(reference: 'PAY-1', completedAt: completedAt)),
      );
    });

    test('receipts with different references are not equal', () {
      final completedAt = DateTime.utc(2026, 9, 16, 12);
      expect(
        PaymentReceipt(reference: 'PAY-1', completedAt: completedAt),
        isNot(equals(PaymentReceipt(reference: 'PAY-2', completedAt: completedAt))),
      );
    });
  });

  group('PaymentJobProgress', () {
    test('two Running values with the same percent are equal', () {
      expect(const Running(40), equals(const Running(40)));
    });

    test('Running values with different percents are not equal', () {
      expect(const Running(40), isNot(equals(const Running(41))));
    });

    test('two Succeeded values with the same receipt are equal', () {
      final receipt = PaymentReceipt(reference: 'PAY-1', completedAt: DateTime.utc(2026, 9, 16));
      expect(Succeeded(receipt), equals(Succeeded(receipt)));
    });

    test('two Failed values with the same failure are equal', () {
      expect(
        const Failed(PaymentFailure.declined),
        equals(const Failed(PaymentFailure.declined)),
      );
    });

    test('Failed values with different failures are not equal', () {
      expect(
        const Failed(PaymentFailure.declined),
        isNot(equals(const Failed(PaymentFailure.timedOut))),
      );
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/payment_job_progress_test.dart`
Expected: FAIL to compile — `Target of URI doesn't exist: 'package:payment_module/features/payment/payment.dart'`

- [ ] **Step 3: Implement**

```dart
// lib/features/payment/src/domain/payment_job_progress.dart
import 'package:equatable/equatable.dart';

/// Why a Payment Job failed. See CONTEXT.md → Payment Failure.
enum PaymentFailure { declined, timedOut, serviceUnavailable }

/// Proof of a succeeded Payment Job. See CONTEXT.md → Receipt.
class PaymentReceipt extends Equatable {
  const PaymentReceipt({required this.reference, required this.completedAt});

  final String reference;
  final DateTime completedAt;

  @override
  List<Object?> get props => [reference, completedAt];
}

/// The state of a Payment Job as it's simulated by the Android foreground service and reported
/// to the flow bloc. See CONTEXT.md → Payment Job, docs/architecture.md §5.
sealed class PaymentJobProgress extends Equatable {
  const PaymentJobProgress();
}

final class Running extends PaymentJobProgress {
  const Running(this.percent);
  final int percent;
  @override
  List<Object?> get props => [percent];
}

final class Succeeded extends PaymentJobProgress {
  const Succeeded(this.receipt);
  final PaymentReceipt receipt;
  @override
  List<Object?> get props => [receipt];
}

final class Failed extends PaymentJobProgress {
  const Failed(this.failure);
  final PaymentFailure failure;
  @override
  List<Object?> get props => [failure];
}
```

```dart
// lib/features/payment/payment.dart
export 'src/domain/payment_job_progress.dart';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/payment_job_progress_test.dart`
Expected: `00:00 +7: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/payment test/features/payment/payment_job_progress_test.dart
git commit -m "feat(payment): add PaymentFailure, PaymentReceipt, PaymentJobProgress"
```

---

### Task 2: `Payment` and `LineItem`

**Files:**
- Create: `lib/features/payment/src/domain/payment.dart`
- Modify: `lib/features/payment/payment.dart` (add one export line)
- Test: `test/features/payment/payment_test.dart`

The channel contract's `payment.job · start` args (`docs/architecture.md` §9) are `{reference, amountMinor, currency, payee}` — sourced from the `Payment` itself, so `Payment` carries its own `reference` (the demo/backend-assigned id passed to `PaymentProcessor.start`), separate from `PaymentReceipt.reference` (assigned on success).

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/money.dart';
import 'package:payment_module/features/payment/payment.dart';

void main() {
  group('LineItem', () {
    test('two line items with the same description and amount are equal', () {
      const amount = Money(amountMinor: 1000, currency: 'USD');
      expect(
        const LineItem(description: 'Usage', amount: amount),
        equals(const LineItem(description: 'Usage', amount: amount)),
      );
    });
  });

  group('Payment', () {
    const amount = Money(amountMinor: 4200, currency: 'USD');
    const lineItems = [
      LineItem(description: 'Monthly service', amount: Money(amountMinor: 3200, currency: 'USD')),
      LineItem(description: 'Usage overage', amount: Money(amountMinor: 1000, currency: 'USD')),
    ];

    test('two payments with the same fields are equal', () {
      expect(
        const Payment(reference: 'PAY-1', amount: amount, payee: 'Acme', lineItems: lineItems),
        equals(const Payment(reference: 'PAY-1', amount: amount, payee: 'Acme', lineItems: lineItems)),
      );
    });

    test('payments with different references are not equal', () {
      expect(
        const Payment(reference: 'PAY-1', amount: amount, payee: 'Acme', lineItems: lineItems),
        isNot(equals(
          const Payment(reference: 'PAY-2', amount: amount, payee: 'Acme', lineItems: lineItems),
        )),
      );
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/payment_test.dart`
Expected: FAIL to compile — `Undefined class 'LineItem'`

- [ ] **Step 3: Implement**

```dart
// lib/features/payment/src/domain/payment.dart
import 'package:equatable/equatable.dart';

import '../../../../core/money.dart';

/// One priced component of a Payment. Every Brand's Payment has them; only some Brands show
/// them. See CONTEXT.md → Line Item.
class LineItem extends Equatable {
  const LineItem({required this.description, required this.amount});

  final String description;
  final Money amount;

  @override
  List<Object?> get props => [description, amount];
}

/// The transaction awaiting confirmation. See CONTEXT.md → Payment.
class Payment extends Equatable {
  const Payment({
    required this.reference,
    required this.amount,
    required this.payee,
    required this.lineItems,
  });

  final String reference;
  final Money amount;
  final String payee;
  final List<LineItem> lineItems;

  @override
  List<Object?> get props => [reference, amount, payee, lineItems];
}
```

```dart
// lib/features/payment/payment.dart
export 'src/domain/payment.dart';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/payment_test.dart`
Expected: `00:00 +3: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/payment test/features/payment/payment_test.dart
git commit -m "feat(payment): add Payment and LineItem"
```

---

### Task 3: `PaymentRepository` port and its fake

**Files:**
- Create: `lib/features/payment/src/domain/payment_repository.dart`
- Create: `test/support/fakes/fake_payment_repository.dart`
- Modify: `lib/features/payment/payment.dart` (add one export line)

This task has no `payment`-specific test of its own — the port is an `abstract class` (nothing to unit test), and the fake is exercised by Task 8's bloc tests. Both are needed together because the fake is written directly against the port's shape (same shape as Plan 2 Tasks 5–6).

The fake uses a `Completer` rather than resolving immediately: §7.1's "AwaitingConfirmation | PaymentLoaded | — | same | payment set (slow load)" row means a test must be able to control *when* `load()` resolves relative to the scan timer, not just what it resolves to.

- [ ] **Step 1: Implement the port**

```dart
// lib/features/payment/src/domain/payment_repository.dart
import 'payment.dart';

/// Loads the Payment awaiting confirmation. The one seam with a single production adapter today
/// (`InMemoryPaymentRepository`, demo data) — the backend a real product would have. See
/// docs/architecture.md §2 principle 2, §5.1.
abstract class PaymentRepository {
  Future<Payment> load();
}
```

```dart
// lib/features/payment/payment.dart — add this line
export 'src/domain/payment_repository.dart';
```

- [ ] **Step 2: Implement the fake**

```dart
// test/support/fakes/fake_payment_repository.dart
import 'dart:async';

import 'package:payment_module/features/payment/payment.dart';

/// A scripted [PaymentRepository] for tests. `load()` doesn't resolve until [completeWith] or
/// [completeWithError] is called, so a test can control exactly when the Payment arrives
/// relative to other events (e.g. the scan timer).
class FakePaymentRepository implements PaymentRepository {
  final _completer = Completer<Payment>();

  @override
  Future<Payment> load() => _completer.future;

  void completeWith(Payment payment) => _completer.complete(payment);

  void completeWithError(Object error) => _completer.completeError(error);
}
```

- [ ] **Step 3: Verify the workspace still compiles and analyzes clean**

Run: `~/fvm/versions/3.44.6/bin/flutter analyze` then `~/fvm/versions/3.44.6/bin/dart analyze --fatal-infos`
Expected: both `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/payment test/support/fakes/fake_payment_repository.dart
git commit -m "feat(payment): add PaymentRepository port and its fake"
```

---

### Task 4: `PaymentProcessor` port and its fake

**Files:**
- Create: `lib/features/payment/src/domain/payment_processor.dart`
- Create: `test/support/fakes/fake_payment_processor.dart`
- Modify: `lib/features/payment/payment.dart` (add one export line)

Same shape as Task 3 — no test of its own; exercised by Task 8's bloc tests.

- [ ] **Step 1: Implement the port**

```dart
// lib/features/payment/src/domain/payment_processor.dart
import 'payment.dart';
import 'payment_job_progress.dart';

/// Starts a Payment Job and reports its progress; finds one already running (the app was
/// reopened mid-job). See docs/architecture.md §5.1, §10.
abstract class PaymentProcessor {
  Stream<PaymentJobProgress> start(Payment payment);
  Future<Stream<PaymentJobProgress>?> inFlight();
}
```

```dart
// lib/features/payment/payment.dart — add this line
export 'src/domain/payment_processor.dart';
```

- [ ] **Step 2: Implement the fake**

```dart
// test/support/fakes/fake_payment_processor.dart
import 'dart:async';

import 'package:payment_module/features/payment/payment.dart';

/// A scripted [PaymentProcessor] for tests. Push progress for a started job via [pushProgress];
/// set [inFlightStream] before `start()`/`inFlight()` is called to script a re-attach scenario;
/// set [startError] to make the next `start()` throw once (then reset itself).
class FakePaymentProcessor implements PaymentProcessor {
  final _controller = StreamController<PaymentJobProgress>.broadcast();

  int startCallCount = 0;
  Payment? lastStartedPayment;
  Object? startError;
  Stream<PaymentJobProgress>? inFlightStream;

  bool get hasActiveListener => _controller.hasListener;

  @override
  Stream<PaymentJobProgress> start(Payment payment) {
    startCallCount++;
    lastStartedPayment = payment;
    if (startError != null) {
      final error = startError!;
      startError = null;
      throw error;
    }
    return _controller.stream;
  }

  void pushProgress(PaymentJobProgress progress) => _controller.add(progress);

  @override
  Future<Stream<PaymentJobProgress>?> inFlight() async => inFlightStream;

  Future<void> dispose() => _controller.close();
}
```

- [ ] **Step 3: Verify**

Run: `~/fvm/versions/3.44.6/bin/flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/payment test/support/fakes/fake_payment_processor.dart
git commit -m "feat(payment): add PaymentProcessor port and its fake"
```

---

### Task 5: `InMemoryPaymentRepository`

**Files:**
- Create: `lib/features/payment/src/data/in_memory_payment_repository.dart`
- Modify: `lib/features/payment/payment.dart` (add one export line)
- Test: `test/features/payment/in_memory_payment_repository_test.dart`

The demo production adapter — `docs/architecture.md` §2 principle 2 and §5.1 are explicit that this seam has a real, non-fake adapter today, unlike every native-backed port. `amountMinor` deliberately does **not** end `99` (`docs/architecture.md` §5's decline rule: "the simulation declines deterministically when `amountMinor % 100 == 99`") — a demo payment that always declines would be a poor demo default.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/features/payment/payment.dart';

void main() {
  test('load() returns a demo Payment whose line items sum to its amount', () async {
    final repository = InMemoryPaymentRepository();
    final payment = await repository.load();

    expect(payment.reference, isNotEmpty);
    expect(payment.payee, isNotEmpty);
    expect(payment.lineItems, isNotEmpty);
    expect(payment.amount.currency, payment.lineItems.first.amount.currency);

    final lineItemTotal = payment.lineItems.fold<int>(
      0,
      (sum, item) => sum + item.amount.amountMinor,
    );
    expect(lineItemTotal, payment.amount.amountMinor);
    expect(payment.amount.amountMinor % 100, isNot(99));
  });

  test('load() returns the same demo Payment on every call', () async {
    final repository = InMemoryPaymentRepository();
    expect(await repository.load(), await repository.load());
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/in_memory_payment_repository_test.dart`
Expected: FAIL to compile — `Undefined class 'InMemoryPaymentRepository'`

- [ ] **Step 3: Implement**

```dart
// lib/features/payment/src/data/in_memory_payment_repository.dart
import '../../../../core/money.dart';
import '../domain/payment.dart';
import '../domain/payment_repository.dart';

const _demoPayment = Payment(
  reference: 'PAY-DEMO-0001',
  amount: Money(amountMinor: 4200, currency: 'USD'),
  payee: 'Acme Utilities',
  lineItems: [
    LineItem(
      description: 'Monthly service',
      amount: Money(amountMinor: 3200, currency: 'USD'),
    ),
    LineItem(
      description: 'Usage overage',
      amount: Money(amountMinor: 1000, currency: 'USD'),
    ),
  ],
);

/// The demo backend: a single, fixed Payment. Stands in for the real backend a product would
/// have — see docs/architecture.md §2 principle 2. No failure mode: an in-memory constant cannot
/// fail to load.
class InMemoryPaymentRepository implements PaymentRepository {
  @override
  Future<Payment> load() async => _demoPayment;
}
```

```dart
// lib/features/payment/payment.dart — add this line
export 'src/data/in_memory_payment_repository.dart';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/in_memory_payment_repository_test.dart`
Expected: `00:00 +2: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/payment test/features/payment/in_memory_payment_repository_test.dart
git commit -m "feat(payment): add InMemoryPaymentRepository"
```

---

### Task 6: `PaymentPhase` and `PaymentConfirmationState`

**Files:**
- Create: `lib/features/payment/src/presentation/payment_confirmation_state.dart`
- Modify: `lib/features/payment/payment.dart` (add one export line)
- Test: `test/features/payment/payment_confirmation_state_test.dart`

`PaymentPhase` is the sealed `Scanning | AwaitingConfirmation | Processing(percent) | Completed(outcome)` from `docs/architecture.md` §7.1. `Completed.outcome` is typed `PaymentJobProgress` but is only ever `Succeeded` or `Failed` in practice (never `Running`) — the table never produces a `Completed` state from anything but a terminal `JobProgressed`; this is documented on the constructor rather than asserted, matching how lightly the rest of this codebase polices "can't happen" states (e.g. `SecureWindowController` doesn't assert `_count` can't go negative from unbalanced calls beyond one debug assert).

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/features/payment/payment.dart';

void main() {
  group('PaymentPhase', () {
    test('two Processing values with the same percent are equal', () {
      expect(const Processing(40), equals(const Processing(40)));
    });

    test('two Completed values with the same outcome are equal', () {
      expect(
        const Completed(Failed(PaymentFailure.declined)),
        equals(const Completed(Failed(PaymentFailure.declined))),
      );
    });

    test('Scanning and AwaitingConfirmation are not equal', () {
      expect(const Scanning(), isNot(equals(const AwaitingConfirmation())));
    });
  });

  group('PaymentConfirmationState', () {
    test('initial state has no payment and phase Scanning', () {
      const state = PaymentConfirmationState.initial();
      expect(state.payment, isNull);
      expect(state.phase, isA<Scanning>());
    });

    test('copyWith replaces phase and preserves payment when not given', () {
      const payment = Payment(
        reference: 'PAY-1',
        amount: Money(amountMinor: 100, currency: 'USD'),
        payee: 'Acme',
        lineItems: [],
      );
      const state = PaymentConfirmationState(payment: payment, phase: Scanning());
      final next = state.copyWith(phase: const AwaitingConfirmation());
      expect(next.payment, payment);
      expect(next.phase, isA<AwaitingConfirmation>());
    });

    test('copyWith replaces payment and preserves phase when not given', () {
      const payment = Payment(
        reference: 'PAY-1',
        amount: Money(amountMinor: 100, currency: 'USD'),
        payee: 'Acme',
        lineItems: [],
      );
      const state = PaymentConfirmationState(phase: AwaitingConfirmation());
      final next = state.copyWith(payment: payment);
      expect(next.payment, payment);
      expect(next.phase, isA<AwaitingConfirmation>());
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/payment_confirmation_state_test.dart`
Expected: FAIL to compile — `Undefined class 'Scanning'`

- [ ] **Step 3: Implement**

```dart
// lib/features/payment/src/presentation/payment_confirmation_state.dart
import 'package:equatable/equatable.dart';

import '../domain/payment.dart';
import '../domain/payment_job_progress.dart';

/// The phase of the payment confirmation flow. See docs/architecture.md §7.1.
sealed class PaymentPhase extends Equatable {
  const PaymentPhase();
}

final class Scanning extends PaymentPhase {
  const Scanning();
  @override
  List<Object?> get props => const [];
}

final class AwaitingConfirmation extends PaymentPhase {
  const AwaitingConfirmation();
  @override
  List<Object?> get props => const [];
}

final class Processing extends PaymentPhase {
  const Processing(this.percent);
  final int percent;
  @override
  List<Object?> get props => [percent];
}

/// [outcome] is always `Succeeded` or `Failed` in practice — this phase is only ever reached
/// from a terminal `JobProgressed`. Typed as `PaymentJobProgress` rather than a narrower union
/// because that's the type the bloc already has in hand at the one call site that constructs it.
final class Completed extends PaymentPhase {
  const Completed(this.outcome);
  final PaymentJobProgress outcome;
  @override
  List<Object?> get props => [outcome];
}

/// State of [PaymentConfirmationBloc]. See docs/architecture.md §7.1.
class PaymentConfirmationState extends Equatable {
  const PaymentConfirmationState({this.payment, this.phase = const Scanning()});

  const PaymentConfirmationState.initial() : this();

  final Payment? payment;
  final PaymentPhase phase;

  PaymentConfirmationState copyWith({Payment? payment, PaymentPhase? phase}) =>
      PaymentConfirmationState(
        payment: payment ?? this.payment,
        phase: phase ?? this.phase,
      );

  @override
  List<Object?> get props => [payment, phase];
}
```

```dart
// lib/features/payment/payment.dart — add this line
export 'src/presentation/payment_confirmation_state.dart';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/payment_confirmation_state_test.dart`
Expected: `00:00 +6: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/payment test/features/payment/payment_confirmation_state_test.dart
git commit -m "feat(payment): add PaymentPhase and PaymentConfirmationState"
```

---

### Task 7: `PaymentConfirmationEvent` hierarchy

**Files:**
- Create: `lib/features/payment/src/presentation/payment_confirmation_event.dart`
- Modify: `lib/features/payment/payment.dart` (add one export line)
- Test: `test/features/payment/payment_confirmation_event_test.dart`

Events from the page: `Started`, `PayPressed(verdict)`, `RetryPressed`; internal, added by the bloc itself: `PaymentLoaded`, `ScanTimerElapsed`, `JobProgressed`. `PayPressed.verdict` is a `PolicyVerdict` — `security_guard`'s type, imported through its barrel; this is the one place `payment` touches `security_guard` at all.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/features/payment/payment.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

void main() {
  const verdict = PolicyVerdict(blockers: {}, warnings: {}, notices: {});

  test('two PayPressed events with the same verdict are equal', () {
    expect(const PayPressed(verdict), equals(const PayPressed(verdict)));
  });

  test('two PaymentLoaded events with the same payment are equal', () {
    const payment = Payment(
      reference: 'PAY-1',
      amount: Money(amountMinor: 100, currency: 'USD'),
      payee: 'Acme',
      lineItems: [],
    );
    expect(const PaymentLoaded(payment), equals(const PaymentLoaded(payment)));
  });

  test('two JobProgressed events with the same progress are equal', () {
    expect(const JobProgressed(Running(10)), equals(const JobProgressed(Running(10))));
  });

  test('Started, RetryPressed, and ScanTimerElapsed are each equal to themselves', () {
    expect(const Started(), equals(const Started()));
    expect(const RetryPressed(), equals(const RetryPressed()));
    expect(const ScanTimerElapsed(), equals(const ScanTimerElapsed()));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/payment_confirmation_event_test.dart`
Expected: FAIL to compile — `Undefined class 'PayPressed'`

- [ ] **Step 3: Implement**

```dart
// lib/features/payment/src/presentation/payment_confirmation_event.dart
import 'package:equatable/equatable.dart';

import '../../../security_guard/security_guard.dart' show PolicyVerdict;
import '../domain/payment.dart';
import '../domain/payment_job_progress.dart';

/// Events [PaymentConfirmationBloc] handles. See docs/architecture.md §7.1.
sealed class PaymentConfirmationEvent extends Equatable {
  const PaymentConfirmationEvent();
}

/// From the page: the screen has mounted.
final class Started extends PaymentConfirmationEvent {
  const Started();
  @override
  List<Object?> get props => const [];
}

/// From the page: the user tapped Pay. Carries the live Policy Verdict from
/// `SecurityPostureCubit` — the one fact this bloc needs about Security Posture, without
/// subscribing to it. See docs/architecture.md §7.
final class PayPressed extends PaymentConfirmationEvent {
  const PayPressed(this.verdict);
  final PolicyVerdict verdict;
  @override
  List<Object?> get props => [verdict];
}

/// From the page: the user tapped Retry after a failed Payment Job.
final class RetryPressed extends PaymentConfirmationEvent {
  const RetryPressed();
  @override
  List<Object?> get props => const [];
}

/// Internal: `PaymentRepository.load()` resolved.
final class PaymentLoaded extends PaymentConfirmationEvent {
  const PaymentLoaded(this.payment);
  final Payment payment;
  @override
  List<Object?> get props => [payment];
}

/// Internal: the Brand's minimum Security Scan duration has elapsed.
final class ScanTimerElapsed extends PaymentConfirmationEvent {
  const ScanTimerElapsed();
  @override
  List<Object?> get props => const [];
}

/// Internal: the Payment Job (fresh or re-attached) reported progress.
final class JobProgressed extends PaymentConfirmationEvent {
  const JobProgressed(this.progress);
  final PaymentJobProgress progress;
  @override
  List<Object?> get props => [progress];
}
```

```dart
// lib/features/payment/payment.dart — add this line
export 'src/presentation/payment_confirmation_event.dart';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/payment_confirmation_event_test.dart`
Expected: `00:00 +4: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/payment test/features/payment/payment_confirmation_event_test.dart
git commit -m "feat(payment): add PaymentConfirmationEvent hierarchy"
```

---

### Task 8: `PaymentConfirmationBloc`

**Files:**
- Create: `lib/features/payment/src/presentation/payment_confirmation_bloc.dart`
- Modify: `lib/features/payment/payment.dart` (add one export line)
- Test: `test/features/payment/payment_confirmation_bloc_test.dart`

The biggest task in this plan — one class implementing every row of §7.1's table. **Testing strategy**: most rows are tested with `blocTest`'s `seed:` parameter, which starts the bloc directly in the phase a row cares about and fires exactly one event — this tests each `(phase, event)` reducer step in isolation, matching the table's own shape, and is fast and deterministic (no waiting on real timers). Only three things need a bloc actually driven from construction via `Started`: the three branches of the initial row (no in-flight / in-flight running / in-flight terminal), one integration test that the real scan timer is wired to `scanMinDuration` at all (everything else uses `seed:` to skip it), and the `close()` cleanup test. A short `testScanDuration` (10 ms) keeps that one real-timer test fast.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/exceptions.dart';
import 'package:payment_module/core/money.dart';
import 'package:payment_module/features/payment/payment.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

import '../../support/fakes/fake_payment_processor.dart';
import '../../support/fakes/fake_payment_repository.dart';

const testScanDuration = Duration(milliseconds: 10);

const testPayment = Payment(
  reference: 'PAY-TEST-0001',
  amount: Money(amountMinor: 4200, currency: 'USD'),
  payee: 'Acme Utilities',
  lineItems: [],
);

const unblockedVerdict = PolicyVerdict(blockers: {}, warnings: {}, notices: {});
const blockedVerdict = PolicyVerdict(
  blockers: {ThreatKind.rooted},
  warnings: {},
  notices: {},
);

final testReceipt = PaymentReceipt(reference: 'PAY-TEST-0001', completedAt: DateTime.utc(2026, 9, 16));

void main() {
  late FakePaymentRepository repository;
  late FakePaymentProcessor processor;

  setUp(() {
    repository = FakePaymentRepository();
    processor = FakePaymentProcessor();
  });

  tearDown(() => processor.dispose());

  PaymentConfirmationBloc buildBloc() =>
      PaymentConfirmationBloc(repository, processor, scanMinDuration: testScanDuration);

  group('Started — cold entry', () {
    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'no in-flight job: loads the payment and stays in Scanning',
      build: () {
        repository.completeWith(testPayment);
        return buildBloc();
      },
      act: (bloc) => bloc.add(const Started()),
      expect: () => [
        const PaymentConfirmationState(payment: testPayment, phase: Scanning()),
      ],
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'in-flight job running: goes straight to Processing, skipping Scanning',
      build: () {
        processor.inFlightStream = Stream.value(const Running(40));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const Started()),
      expect: () => [
        const PaymentConfirmationState(phase: Processing(40)),
      ],
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'in-flight job already succeeded: goes straight to Completed',
      build: () {
        processor.inFlightStream = Stream.value(Succeeded(testReceipt));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const Started()),
      expect: () => [
        PaymentConfirmationState(phase: Completed(Succeeded(testReceipt))),
      ],
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'in-flight job already failed: goes straight to Completed',
      build: () {
        processor.inFlightStream = Stream.value(const Failed(PaymentFailure.declined));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const Started()),
      expect: () => [
        const PaymentConfirmationState(phase: Completed(Failed(PaymentFailure.declined))),
      ],
    );
  });

  group('Scanning', () {
    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'PaymentLoaded sets the payment and stays in Scanning',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(phase: Scanning()),
      act: (bloc) => bloc.add(const PaymentLoaded(testPayment)),
      expect: () => [
        const PaymentConfirmationState(payment: testPayment, phase: Scanning()),
      ],
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'ScanTimerElapsed moves to AwaitingConfirmation',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(payment: testPayment, phase: Scanning()),
      act: (bloc) => bloc.add(const ScanTimerElapsed()),
      expect: () => [
        const PaymentConfirmationState(payment: testPayment, phase: AwaitingConfirmation()),
      ],
    );
  });

  group('AwaitingConfirmation', () {
    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'a payment that finishes loading after the scan timer still gets set (slow load)',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(phase: AwaitingConfirmation()),
      act: (bloc) => bloc.add(const PaymentLoaded(testPayment)),
      expect: () => [
        const PaymentConfirmationState(payment: testPayment, phase: AwaitingConfirmation()),
      ],
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'PayPressed with an unblocked verdict and a loaded payment starts the job',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(payment: testPayment, phase: AwaitingConfirmation()),
      act: (bloc) => bloc.add(const PayPressed(unblockedVerdict)),
      expect: () => [
        const PaymentConfirmationState(payment: testPayment, phase: Processing(0)),
      ],
      verify: (_) {
        expect(processor.startCallCount, 1);
        expect(processor.lastStartedPayment, testPayment);
      },
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'PayPressed with a blocked verdict is ignored',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(payment: testPayment, phase: AwaitingConfirmation()),
      act: (bloc) => bloc.add(const PayPressed(blockedVerdict)),
      expect: () => <PaymentConfirmationState>[],
      verify: (_) => expect(processor.startCallCount, 0),
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'PayPressed before the payment has loaded is ignored',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(phase: AwaitingConfirmation()),
      act: (bloc) => bloc.add(const PayPressed(unblockedVerdict)),
      expect: () => <PaymentConfirmationState>[],
      verify: (_) => expect(processor.startCallCount, 0),
    );
  });

  group('Processing', () {
    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'JobProgressed(Running) updates the percent',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(payment: testPayment, phase: Processing(0)),
      act: (bloc) => bloc.add(const JobProgressed(Running(55))),
      expect: () => [
        const PaymentConfirmationState(payment: testPayment, phase: Processing(55)),
      ],
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'JobProgressed(Succeeded) moves to Completed',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(payment: testPayment, phase: Processing(90)),
      act: (bloc) => bloc.add(JobProgressed(Succeeded(testReceipt))),
      expect: () => [
        PaymentConfirmationState(payment: testPayment, phase: Completed(Succeeded(testReceipt))),
      ],
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'JobProgressed(Failed) moves to Completed',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(payment: testPayment, phase: Processing(60)),
      act: (bloc) => bloc.add(const JobProgressed(Failed(PaymentFailure.declined))),
      expect: () => [
        const PaymentConfirmationState(
          payment: testPayment,
          phase: Completed(Failed(PaymentFailure.declined)),
        ),
      ],
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'PayPressed while Processing is ignored (double-tap, or "back")',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(payment: testPayment, phase: Processing(40)),
      act: (bloc) => bloc.add(const PayPressed(unblockedVerdict)),
      expect: () => <PaymentConfirmationState>[],
      verify: (_) => expect(processor.startCallCount, 0),
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'processor.start() throwing moves Processing straight to Completed(Failed(serviceUnavailable))',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(payment: testPayment, phase: AwaitingConfirmation()),
      act: (bloc) {
        processor.startError = const ServiceException('no Activity attached');
        bloc.add(const PayPressed(unblockedVerdict));
      },
      expect: () => [
        const PaymentConfirmationState(payment: testPayment, phase: Processing(0)),
        const PaymentConfirmationState(
          payment: testPayment,
          phase: Completed(Failed(PaymentFailure.serviceUnavailable)),
        ),
      ],
    );
  });

  group('Completed', () {
    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'RetryPressed after a failed job returns to AwaitingConfirmation',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(
        payment: testPayment,
        phase: Completed(Failed(PaymentFailure.declined)),
      ),
      act: (bloc) => bloc.add(const RetryPressed()),
      expect: () => [
        const PaymentConfirmationState(payment: testPayment, phase: AwaitingConfirmation()),
      ],
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'RetryPressed after a succeeded job is ignored — terminal until pop',
      build: buildBloc,
      seed: () => PaymentConfirmationState(
        payment: testPayment,
        phase: Completed(Succeeded(testReceipt)),
      ),
      act: (bloc) => bloc.add(const RetryPressed()),
      expect: () => <PaymentConfirmationState>[],
    );
  });

  group('wiring', () {
    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'the scan timer really fires after scanMinDuration, not just as a reducer',
      build: buildBloc, // repository never completes — isolates the timer from PaymentLoaded
      act: (bloc) => bloc.add(const Started()),
      wait: testScanDuration * 3,
      expect: () => [
        const PaymentConfirmationState(phase: AwaitingConfirmation()),
      ],
    );
  });

  test('close() cancels an active job subscription', () async {
    repository.completeWith(testPayment);
    final bloc = buildBloc();
    bloc.add(const Started());
    await Future<void>.delayed(Duration.zero);
    bloc.add(const ScanTimerElapsed());
    await Future<void>.delayed(Duration.zero);
    bloc.add(const PayPressed(unblockedVerdict));
    await Future<void>.delayed(Duration.zero);

    expect(processor.hasActiveListener, isTrue);
    await bloc.close();
    expect(processor.hasActiveListener, isFalse);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/payment_confirmation_bloc_test.dart`
Expected: FAIL to compile — `Undefined class 'PaymentConfirmationBloc'`

- [ ] **Step 3: Implement**

```dart
// lib/features/payment/src/presentation/payment_confirmation_bloc.dart
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/payment_job_progress.dart';
import '../domain/payment_processor.dart';
import '../domain/payment_repository.dart';
import 'payment_confirmation_event.dart';
import 'payment_confirmation_state.dart';

/// Drives the payment confirmation flow: load, scan, confirm, process. Talks to
/// [PaymentRepository] and [PaymentProcessor] directly — no use case, see
/// docs/adr/0005-use-cases-only-where-logic-lives.md. Never subscribes to Security Posture; the
/// one posture fact it needs arrives inside [PayPressed]. See docs/architecture.md §7, §7.1.
class PaymentConfirmationBloc
    extends Bloc<PaymentConfirmationEvent, PaymentConfirmationState> {
  PaymentConfirmationBloc(
    this._repository,
    this._processor, {
    required this.scanMinDuration,
  }) : super(const PaymentConfirmationState.initial()) {
    on<Started>(_onStarted);
    on<PaymentLoaded>(_onPaymentLoaded);
    on<ScanTimerElapsed>(_onScanTimerElapsed);
    on<PayPressed>(_onPayPressed);
    on<JobProgressed>(_onJobProgressed);
    on<RetryPressed>(_onRetryPressed);
  }

  final PaymentRepository _repository;
  final PaymentProcessor _processor;
  final Duration scanMinDuration;

  Timer? _scanTimer;
  StreamSubscription<PaymentJobProgress>? _jobSubscription;

  Future<void> _onStarted(
    Started event,
    Emitter<PaymentConfirmationState> emit,
  ) async {
    final inFlight = await _processor.inFlight();
    if (inFlight != null) {
      await _listenToJob(inFlight);
      return;
    }
    _scanTimer = Timer(scanMinDuration, () => add(const ScanTimerElapsed()));
    // repository.load() failing isn't in §7.1's table — InMemoryPaymentRepository, the only
    // adapter this seam has today, cannot fail to load — so it's left to the bloc's default
    // error handling rather than given speculative handling here.
    final payment = await _repository.load();
    add(PaymentLoaded(payment));
  }

  void _onPaymentLoaded(
    PaymentLoaded event,
    Emitter<PaymentConfirmationState> emit,
  ) {
    emit(state.copyWith(payment: event.payment));
  }

  void _onScanTimerElapsed(
    ScanTimerElapsed event,
    Emitter<PaymentConfirmationState> emit,
  ) {
    if (state.phase is! Scanning) return;
    emit(state.copyWith(phase: const AwaitingConfirmation()));
  }

  Future<void> _onPayPressed(
    PayPressed event,
    Emitter<PaymentConfirmationState> emit,
  ) async {
    final payment = state.payment;
    if (state.phase is! AwaitingConfirmation ||
        payment == null ||
        event.verdict.isBlocked) {
      return; // ignored: double-tap, blocked posture, or not yet loaded
    }
    emit(state.copyWith(phase: const Processing(0)));
    try {
      await _listenToJob(_processor.start(payment));
    } catch (_) {
      emit(
        state.copyWith(
          phase: const Completed(Failed(PaymentFailure.serviceUnavailable)),
        ),
      );
    }
  }

  void _onJobProgressed(
    JobProgressed event,
    Emitter<PaymentConfirmationState> emit,
  ) {
    switch (event.progress) {
      case Running(:final percent):
        emit(state.copyWith(phase: Processing(percent)));
      case Succeeded() || Failed():
        emit(state.copyWith(phase: Completed(event.progress)));
    }
  }

  void _onRetryPressed(
    RetryPressed event,
    Emitter<PaymentConfirmationState> emit,
  ) {
    final phase = state.phase;
    if (phase is Completed && phase.outcome is Failed) {
      emit(state.copyWith(phase: const AwaitingConfirmation()));
    }
  }

  Future<void> _listenToJob(Stream<PaymentJobProgress> stream) async {
    await _jobSubscription?.cancel();
    _jobSubscription = stream.listen((progress) => add(JobProgressed(progress)));
  }

  @override
  Future<void> close() {
    _scanTimer?.cancel();
    unawaited(_jobSubscription?.cancel());
    return super.close();
  }
}
```

```dart
// lib/features/payment/payment.dart — add this line
export 'src/presentation/payment_confirmation_bloc.dart';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/payment_confirmation_bloc_test.dart`
Expected: `00:00 +19: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/payment test/features/payment/payment_confirmation_bloc_test.dart
git commit -m "feat(payment): add PaymentConfirmationBloc"
```

---

### Task 9: `canPay` — the derived display rule

**Files:**
- Create: `lib/features/payment/src/presentation/can_pay.dart`
- Modify: `lib/features/payment/payment.dart` (add one export line)
- Test: `test/features/payment/can_pay_test.dart`

The one derived display rule this plan builds (`docs/architecture.md` §7): `canPay(flow, posture) = flow.phase is AwaitingConfirmation ∧ flow.payment ≠ null ∧ posture.hasFirstAssessment ∧ ¬posture.verdict.isBlocked`. A pure function, unit-tested on its own, imported by the page in the composition-root plan for the Pay button's enabled state. Its second parameter, `PostureState`, is `security_guard`'s cubit state — imported through the barrel, so this is the second (and last, for this plan) place `security_guard_via_barrel` is exercised.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/money.dart';
import 'package:payment_module/features/payment/payment.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

void main() {
  const payment = Payment(
    reference: 'PAY-1',
    amount: Money(amountMinor: 100, currency: 'USD'),
    payee: 'Acme',
    lineItems: [],
  );
  final posture = SecurityPosture(const [
    ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
    ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
  ]);
  const unblockedVerdict = PolicyVerdict(blockers: {}, warnings: {}, notices: {});
  const blockedVerdict = PolicyVerdict(blockers: {ThreatKind.rooted}, warnings: {}, notices: {});

  test('true when awaiting confirmation, payment loaded, assessed, and not blocked', () {
    final flow = const PaymentConfirmationState(payment: payment, phase: AwaitingConfirmation());
    final state = PostureState(posture: posture, verdict: unblockedVerdict);
    expect(canPay(flow, state), isTrue);
  });

  test('false during Scanning', () {
    final flow = const PaymentConfirmationState(payment: payment, phase: Scanning());
    final state = PostureState(posture: posture, verdict: unblockedVerdict);
    expect(canPay(flow, state), isFalse);
  });

  test('false during Processing', () {
    final flow = const PaymentConfirmationState(payment: payment, phase: Processing(50));
    final state = PostureState(posture: posture, verdict: unblockedVerdict);
    expect(canPay(flow, state), isFalse);
  });

  test('false when the payment has not loaded', () {
    const flow = PaymentConfirmationState(phase: AwaitingConfirmation());
    final state = PostureState(posture: posture, verdict: unblockedVerdict);
    expect(canPay(flow, state), isFalse);
  });

  test('false before the first assessment arrives', () {
    const flow = PaymentConfirmationState(payment: payment, phase: AwaitingConfirmation());
    const state = PostureState.initial();
    expect(canPay(flow, state), isFalse);
  });

  test('false when the verdict is blocked', () {
    const flow = PaymentConfirmationState(payment: payment, phase: AwaitingConfirmation());
    final state = PostureState(posture: posture, verdict: blockedVerdict);
    expect(canPay(flow, state), isFalse);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/can_pay_test.dart`
Expected: FAIL to compile — `Undefined name 'canPay'`

- [ ] **Step 3: Implement**

```dart
// lib/features/payment/src/presentation/can_pay.dart
import '../../../security_guard/security_guard.dart' show PostureState;
import 'payment_confirmation_state.dart';

/// Whether the Pay button is enabled: the flow is awaiting confirmation with a loaded Payment,
/// and the Security Posture has been assessed at least once and doesn't block. See
/// docs/architecture.md §7.
bool canPay(PaymentConfirmationState flow, PostureState posture) =>
    flow.phase is AwaitingConfirmation &&
    flow.payment != null &&
    posture.hasFirstAssessment &&
    !(posture.verdict?.isBlocked ?? false);
```

```dart
// lib/features/payment/payment.dart — add this line
export 'src/presentation/can_pay.dart';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/can_pay_test.dart`
Expected: `00:00 +6: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/payment test/features/payment/can_pay_test.dart
git commit -m "feat(payment): add canPay"
```

---

### Task 10: `registerPaymentModule`; full barrel review; verify both feature-pair lint rules; full suite

**Files:**
- Create: `lib/features/payment/di.dart`
- Test: `test/features/payment/di_test.dart`
- Create: `docs/verification/2026-09-16-payment-lint-verification.md`
- Temporarily modify, then revert: one file per lint rule being verified

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:payment_module/features/payment/di.dart';
import 'package:payment_module/features/payment/payment.dart';

import '../../support/fakes/fake_payment_processor.dart';
import '../../support/fakes/fake_payment_repository.dart';

void main() {
  late GetIt getIt;

  setUp(() => getIt = GetIt.asNewInstance());
  tearDown(() => getIt.reset());

  test('registers the given fakes as the PaymentRepository and PaymentProcessor singletons', () {
    final repository = FakePaymentRepository();
    final processor = FakePaymentProcessor();

    registerPaymentModule(getIt, repository: repository, processor: processor);

    expect(getIt<PaymentRepository>(), same(repository));
    expect(getIt<PaymentProcessor>(), same(processor));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/di_test.dart`
Expected: FAIL to compile — `Target of URI doesn't exist: 'package:payment_module/features/payment/di.dart'`

- [ ] **Step 3: Implement**

```dart
// lib/features/payment/di.dart
import 'package:get_it/get_it.dart';

import 'payment.dart';

/// Registers `payment`'s ports with [getIt]. Pass [repository]/[processor] to override with
/// fakes in tests. The composition root's real registration (the channel-backed
/// `ChannelPaymentProcessor`; `InMemoryPaymentRepository` is already real) is added by the
/// native-bridge implementation plan; until then this only registers what it's given.
void registerPaymentModule(
  GetIt getIt, {
  PaymentRepository? repository,
  PaymentProcessor? processor,
}) {
  if (repository != null) {
    getIt.registerSingleton<PaymentRepository>(repository);
  }
  if (processor != null) {
    getIt.registerSingleton<PaymentProcessor>(processor);
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/di_test.dart`
Expected: `00:00 +1: All tests passed!`

- [ ] **Step 5: Verify `security_guard_via_barrel` and `no_reverse_dependency`, using `dart analyze` (Plan 1's finding — `flutter analyze` will not show these)**

Both rules were added to `analysis_options.yaml` in Plan 2 Task 1 but stayed inert until `lib/features/payment/` existed. For each pair below: make the edit, run `~/fvm/versions/3.44.6/bin/dart analyze --fatal-infos`, confirm the named rule appears in the output, then revert the edit.

- `security_guard_via_barrel`: temporarily change the import in `lib/features/payment/src/presentation/can_pay.dart` from `'../../../security_guard/security_guard.dart' show PostureState;` to `'../../../security_guard/src/presentation/posture_state.dart';` (a direct `src/` import, bypassing the barrel). Expected: `security_guard_via_barrel` reported.
- `no_reverse_dependency`: temporarily add `import '../../../payment/payment.dart';` to `lib/features/security_guard/src/domain/security_posture.dart` (the file doesn't need to use anything from it — `import_lint` matches the literal import string against the glob, not on usage). Expected: `no_reverse_dependency` reported.

- [ ] **Step 6: Confirm the workspace is clean again**

Run: `~/fvm/versions/3.44.6/bin/dart analyze --fatal-infos`
Expected: `No issues found!`

- [ ] **Step 7: Run the full test suite**

Run: `~/fvm/versions/3.44.6/bin/flutter test`
Expected: all tests pass — every test from Plans 1–2 plus every test written in Tasks 1–10 of this plan. Count the actual total from the test runner's own summary line rather than trusting an arithmetic estimate.

- [ ] **Step 8: Check formatting**

Run: `~/fvm/versions/3.44.6/bin/dart format --set-exit-if-changed lib test`
Expected: exit code 0; if not, run `dart format lib test` and re-check.

- [ ] **Step 9: Record the verification**

```markdown
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
- Full suite: `flutter test` — <ACTUAL COUNT from Step 7> tests passing.
- `payment` is feature-complete against fakes: domain model, both ports, `PaymentConfirmationBloc`
  covering every row of §7.1, `canPay`, and `registerPaymentModule`. `InMemoryPaymentRepository`
  is a real (non-fake) adapter — the one production adapter this plan ships. No channel adapter,
  page, section widgets, or brand wiring exist yet — those are the native-bridge and
  composition-root plans.
```

(Fill in `<ACTUAL COUNT from Step 7>` with the real number the test runner reported — do not estimate it.)

- [ ] **Step 10: Commit**

```bash
git add lib/features/payment test/features/payment/di_test.dart docs/verification/2026-09-16-payment-lint-verification.md
git commit -m "feat(payment): add registerPaymentModule; verify security_guard_via_barrel and no_reverse_dependency; full suite green"
```

---

## Self-review

**Spec coverage** (against `docs/architecture.md` §4's `features/payment` listing, §5, §7, §7.1): domain — `Payment`, `LineItem` ✓ (Task 2), `PaymentJobProgress`, `PaymentFailure`, `PaymentReceipt` ✓ (Task 1), ports `PaymentRepository`, `PaymentProcessor` ✓ (Tasks 3–4) · use case — deliberately none, per ADR-0005 ✓ (stated in the header, not built) · presentation — `PaymentConfirmationBloc` covering every row of §7.1's table ✓ (Task 8), `canPay` ✓ (Task 9) · data — `InMemoryPaymentRepository`, the one production adapter this seam has ✓ (Task 5) · registration `registerPaymentModule` ✓ (Task 10) · fakes `FakePaymentRepository`, `FakePaymentProcessor` ✓ (Tasks 3–4) · both feature-pair lint rules verified, discharging the deferral Plan 2 recorded ✓ (Task 10). Deliberately deferred, named as such in the Scope Boundary: `ChannelPaymentProcessor`, `JobSnapshotCodec` (native-bridge plan), `PaymentConfirmationPage`, `PaymentSection`/`CustomSection`, `PaymentBrandConfig` (composition-root plan — need real `BrandConfig` and `BuildContext`).

**Placeholder scan:** no `TBD`/`TODO`/"add error handling"/"similar to Task N" — every code step shows complete code. `registerPaymentModule`'s doc comment states what it doesn't yet do (register `ChannelPaymentProcessor`) and why (native-bridge plan's job), a scope note rather than an unfinished implementation. `_onStarted`'s comment about `repository.load()` not being caught states why (the table doesn't specify it; the one adapter this seam has can't fail) rather than leaving a silent gap. Step 9's `<ACTUAL COUNT>` is an explicit instruction to fill in a real, run-verified number.

**Type consistency:** `PaymentPhase.Completed.outcome` is typed `PaymentJobProgress` (not a narrower `Succeeded | Failed` union) consistently across Tasks 6, 8, and 9 — matches the type the bloc actually holds at its one construction site (`Completed(event.progress)` in `_onJobProgressed`). `PayPressed.verdict` and `canPay`'s second parameter are both `security_guard` types imported via the barrel throughout, never `src/`. `scanMinDuration` is a plain `Duration` constructor parameter on `PaymentConfirmationBloc`, not a `BrandTokens` field read internally — keeps the bloc's dependency on `brand_engine` to zero even though the DAG would permit it, and keeps `bloc_test` in Task 8 free of any Brand setup.
