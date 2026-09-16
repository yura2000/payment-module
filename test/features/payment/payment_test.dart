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
      LineItem(
        description: 'Monthly service',
        amount: Money(amountMinor: 3200, currency: 'USD'),
      ),
      LineItem(
        description: 'Usage overage',
        amount: Money(amountMinor: 1000, currency: 'USD'),
      ),
    ];

    test('two payments with the same fields are equal', () {
      expect(
        const Payment(
          reference: 'PAY-1',
          amount: amount,
          payee: 'Acme',
          lineItems: lineItems,
        ),
        equals(
          const Payment(
            reference: 'PAY-1',
            amount: amount,
            payee: 'Acme',
            lineItems: lineItems,
          ),
        ),
      );
    });

    test('payments with different references are not equal', () {
      expect(
        const Payment(
          reference: 'PAY-1',
          amount: amount,
          payee: 'Acme',
          lineItems: lineItems,
        ),
        isNot(
          equals(
            const Payment(
              reference: 'PAY-2',
              amount: amount,
              payee: 'Acme',
              lineItems: lineItems,
            ),
          ),
        ),
      );
    });
  });
}
