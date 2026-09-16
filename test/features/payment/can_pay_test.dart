import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/money.dart';
import 'package:payment_module/core/threat.dart';
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
  const unblockedVerdict = PolicyVerdict(
    blockers: {},
    warnings: {},
    notices: {},
  );
  const blockedVerdict = PolicyVerdict(
    blockers: {ThreatKind.rooted},
    warnings: {},
    notices: {},
  );

  test(
    'true when awaiting confirmation, payment loaded, assessed, and not blocked',
    () {
      final flow = const PaymentConfirmationState(
        payment: payment,
        phase: AwaitingConfirmation(),
      );
      final state = PostureState(posture: posture, verdict: unblockedVerdict);
      expect(canPay(flow, state), isTrue);
    },
  );

  test('false during Scanning', () {
    final flow = const PaymentConfirmationState(
      payment: payment,
      phase: Scanning(),
    );
    final state = PostureState(posture: posture, verdict: unblockedVerdict);
    expect(canPay(flow, state), isFalse);
  });

  test('false during Processing', () {
    final flow = const PaymentConfirmationState(
      payment: payment,
      phase: Processing(50),
    );
    final state = PostureState(posture: posture, verdict: unblockedVerdict);
    expect(canPay(flow, state), isFalse);
  });

  test('false when the payment has not loaded', () {
    const flow = PaymentConfirmationState(phase: AwaitingConfirmation());
    final state = PostureState(posture: posture, verdict: unblockedVerdict);
    expect(canPay(flow, state), isFalse);
  });

  test('false before the first assessment arrives', () {
    const flow = PaymentConfirmationState(
      payment: payment,
      phase: AwaitingConfirmation(),
    );
    const state = PostureState.initial();
    expect(canPay(flow, state), isFalse);
  });

  test('false when the verdict is blocked', () {
    const flow = PaymentConfirmationState(
      payment: payment,
      phase: AwaitingConfirmation(),
    );
    final state = PostureState(posture: posture, verdict: blockedVerdict);
    expect(canPay(flow, state), isFalse);
  });
}
