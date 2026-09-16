import 'package:equatable/equatable.dart';

/// Why a Payment Job failed. See CONTEXT.md → Payment Failure.
enum PaymentFailure { declined, timedOut, serviceUnavailable }

/// Proof of a succeeded Payment Job. See CONTEXT.md → Receipt.
class PaymentReceipt extends Equatable {
  const PaymentReceipt({required this.reference, required this.completedAt});

  final String reference;
  final DateTime completedAt;

  @override
  List<Object?> get props => [reference, completedAt];
}

/// The state of a Payment Job as it's simulated by the Android foreground service and reported
/// to the flow bloc. See CONTEXT.md → Payment Job, docs/architecture.md §5.
sealed class PaymentJobProgress extends Equatable {
  const PaymentJobProgress();
}

final class Running extends PaymentJobProgress {
  const Running(this.percent);
  final int percent;
  @override
  List<Object?> get props => [percent];
}

final class Succeeded extends PaymentJobProgress {
  const Succeeded(this.receipt);
  final PaymentReceipt receipt;
  @override
  List<Object?> get props => [receipt];
}

final class Failed extends PaymentJobProgress {
  const Failed(this.failure);
  final PaymentFailure failure;
  @override
  List<Object?> get props => [failure];
}
