import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/money.dart';
import 'package:payment_module/features/payment/payment.dart';

void main() {
  test('formats a two-decimal currency from its minor unit', () {
    expect(
      formatMoney(const Money(amountMinor: 4200, currency: 'USD')),
      r'$42.00',
    );
  });

  test('keeps sub-unit precision', () {
    expect(
      formatMoney(const Money(amountMinor: 4299, currency: 'USD')),
      r'$42.99',
    );
  });

  test('formats a zero-decimal currency without inventing decimals', () {
    expect(formatMoney(const Money(amountMinor: 4200, currency: 'JPY')), '¥4,200');
  });

  test('groups thousands', () {
    expect(
      formatMoney(const Money(amountMinor: 123456789, currency: 'USD')),
      r'$1,234,567.89',
    );
  });
}
