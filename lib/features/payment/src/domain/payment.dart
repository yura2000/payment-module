import 'package:equatable/equatable.dart';

import '../../../../core/money.dart';

/// One priced component of a Payment. Every Brand's Payment has them; only some Brands show
/// them. See CONTEXT.md → Line Item.
class LineItem extends Equatable {
  const LineItem({required this.description, required this.amount});

  final String description;
  final Money amount;

  @override
  List<Object?> get props => [description, amount];
}

/// The transaction awaiting confirmation. See CONTEXT.md → Payment.
class Payment extends Equatable {
  const Payment({
    required this.reference,
    required this.amount,
    required this.payee,
    required this.lineItems,
  });

  final String reference;
  final Money amount;
  final String payee;
  final List<LineItem> lineItems;

  @override
  List<Object?> get props => [reference, amount, payee, lineItems];
}
