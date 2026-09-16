import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/money.dart';
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
