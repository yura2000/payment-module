import 'package:equatable/equatable.dart';

import '../../../security_guard/security_guard.dart' show PolicyVerdict;
import '../domain/payment.dart';
import '../domain/payment_job_progress.dart';

/// Events `PaymentConfirmationBloc` handles. See docs/architecture.md §7.1.
sealed class PaymentConfirmationEvent extends Equatable {
  const PaymentConfirmationEvent();
}

/// From the page: the screen has mounted.
final class Started extends PaymentConfirmationEvent {
  const Started();
  @override
  List<Object?> get props => const [];
}

/// From the page: the user tapped Pay. Carries the live Policy Verdict from
/// `SecurityPostureCubit` — the one fact this bloc needs about Security Posture, without
/// subscribing to it. See docs/architecture.md §7.
final class PayPressed extends PaymentConfirmationEvent {
  const PayPressed(this.verdict);
  final PolicyVerdict verdict;
  @override
  List<Object?> get props => [verdict];
}

/// From the page: the user tapped Retry after a failed Payment Job.
final class RetryPressed extends PaymentConfirmationEvent {
  const RetryPressed();
  @override
  List<Object?> get props => const [];
}

/// Internal: `PaymentRepository.load()` resolved.
final class PaymentLoaded extends PaymentConfirmationEvent {
  const PaymentLoaded(this.payment);
  final Payment payment;
  @override
  List<Object?> get props => [payment];
}

/// Internal: the Brand's minimum Security Scan duration has elapsed.
final class ScanTimerElapsed extends PaymentConfirmationEvent {
  const ScanTimerElapsed();
  @override
  List<Object?> get props => const [];
}

/// Internal: the Payment Job (fresh or re-attached) reported progress.
final class JobProgressed extends PaymentConfirmationEvent {
  const JobProgressed(this.progress);
  final PaymentJobProgress progress;
  @override
  List<Object?> get props => [progress];
}
