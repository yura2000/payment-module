import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/features/payment/payment.dart';

void main() {
  test(
    'load() returns a demo Payment whose line items sum to its amount',
    () async {
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
    },
  );

  test('load() returns the same demo Payment on every call', () async {
    final repository = InMemoryPaymentRepository();
    expect(await repository.load(), await repository.load());
  });
}
