import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/money.dart';

void main() {
  group('Money', () {
    test('two Money values with the same amount and currency are equal', () {
      const a = Money(amountMinor: 1050, currency: 'EUR');
      const b = Money(amountMinor: 1050, currency: 'EUR');
      expect(a, equals(b));
    });

    test(
      'adding two Money values in the same currency sums the minor units',
      () {
        const a = Money(amountMinor: 1000, currency: 'EUR');
        const b = Money(amountMinor: 250, currency: 'EUR');
        expect(a + b, equals(const Money(amountMinor: 1250, currency: 'EUR')));
      },
    );

    test('adding Money values in different currencies asserts', () {
      const a = Money(amountMinor: 1000, currency: 'EUR');
      const b = Money(amountMinor: 250, currency: 'USD');
      expect(() => a + b, throwsA(isA<AssertionError>()));
    });
  });
}
