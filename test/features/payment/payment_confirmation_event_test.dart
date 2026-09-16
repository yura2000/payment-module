import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/money.dart';
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
