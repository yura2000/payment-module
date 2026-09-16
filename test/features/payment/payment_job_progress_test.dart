import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/features/payment/payment.dart';

void main() {
  group('PaymentReceipt', () {
    test(
      'two receipts with the same reference and completion time are equal',
      () {
        final completedAt = DateTime.utc(2026, 9, 16, 12);
        expect(
          PaymentReceipt(reference: 'PAY-1', completedAt: completedAt),
          equals(PaymentReceipt(reference: 'PAY-1', completedAt: completedAt)),
        );
      },
    );

    test('receipts with different references are not equal', () {
      final completedAt = DateTime.utc(2026, 9, 16, 12);
      expect(
        PaymentReceipt(reference: 'PAY-1', completedAt: completedAt),
        isNot(
          equals(PaymentReceipt(reference: 'PAY-2', completedAt: completedAt)),
        ),
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
      final receipt = PaymentReceipt(
        reference: 'PAY-1',
        completedAt: DateTime.utc(2026, 9, 16),
      );
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
