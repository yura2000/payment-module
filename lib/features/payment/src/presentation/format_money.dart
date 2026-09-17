import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../../../../core/money.dart';

/// Renders a [Money] for display. The scale between the minor unit and the major one is a
/// property of the currency (USD 2 digits, JPY 0), so it comes from the formatter rather than a
/// hard-coded 100. See docs/architecture.md §5.
String formatMoney(Money money) {
  final format = NumberFormat.simpleCurrency(name: money.currency);
  final digits = format.decimalDigits ?? 2;
  return format.format(money.amountMinor / math.pow(10, digits));
}
