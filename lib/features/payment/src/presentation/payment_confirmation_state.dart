import 'package:equatable/equatable.dart';

import '../domain/payment.dart';
import '../domain/payment_job_progress.dart';

/// The phase of the payment confirmation flow. See docs/architecture.md §7.1.
sealed class PaymentPhase extends Equatable {
  const PaymentPhase();
}

final class Scanning extends PaymentPhase {
  const Scanning();
  @override
  List<Object?> get props => const [];
}

final class AwaitingConfirmation extends PaymentPhase {
  const AwaitingConfirmation();
  @override
  List<Object?> get props => const [];
}

final class Processing extends PaymentPhase {
  const Processing(this.percent);
  final int percent;
  @override
  List<Object?> get props => [percent];
}

/// [outcome] is always `Succeeded` or `Failed` in practice — this phase is only ever reached
/// from a terminal `JobProgressed`. Typed as `PaymentJobProgress` rather than a narrower union
/// because that's the type the bloc already has in hand at the one call site that constructs it.
final class Completed extends PaymentPhase {
  const Completed(this.outcome);
  final PaymentJobProgress outcome;
  @override
  List<Object?> get props => [outcome];
}

/// State of `PaymentConfirmationBloc` (added in a later task). See docs/architecture.md §7.1.
class PaymentConfirmationState extends Equatable {
  const PaymentConfirmationState({this.payment, this.phase = const Scanning()});

  const PaymentConfirmationState.initial() : this();

  final Payment? payment;
  final PaymentPhase phase;

  PaymentConfirmationState copyWith({Payment? payment, PaymentPhase? phase}) =>
      PaymentConfirmationState(
        payment: payment ?? this.payment,
        phase: phase ?? this.phase,
      );

  @override
  List<Object?> get props => [payment, phase];
}
