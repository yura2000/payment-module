/// An amount of money in a currency's minor unit (e.g. cents), never a floating-point value.
/// See CONTEXT.md → Payment.
class Money {
  const Money({required this.amountMinor, required this.currency});

  final int amountMinor;
  final String currency;

  Money operator +(Money other) {
    assert(
      currency == other.currency,
      'Cannot add $currency to ${other.currency}',
    );
    return Money(
      amountMinor: amountMinor + other.amountMinor,
      currency: currency,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      other.amountMinor == amountMinor &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(amountMinor, currency);

  @override
  String toString() => 'Money($amountMinor, $currency)';
}
