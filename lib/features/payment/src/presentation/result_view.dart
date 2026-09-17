import 'package:flutter/material.dart';

import '../../../../brand_engine/brand_engine.dart';
import '../../../security_guard/security_guard.dart'
    show PolicyVerdict, PostureBanner;
import '../domain/payment_job_progress.dart';

/// What the payment screen shows once the Payment Job has completed — a phase of the same route,
/// never a separate page, which is what keeps the Secure Window held until the user leaves
/// (CONTEXT.md → Result View, docs/architecture.md §11.1). Retry is offered for a failure only:
/// the state table transitions out of `Completed` on `RetryPressed` from a failure alone.
///
/// [verdict] is the live Policy Verdict; if the posture degraded while the job ran, the caveat
/// rides along here (§7) drawn by the same [PostureBanner] the confirmation view uses.
class ResultView extends StatelessWidget {
  const ResultView({
    super.key,
    required this.outcome,
    required this.onRetry,
    this.verdict,
  });

  final PaymentJobProgress outcome;
  final VoidCallback onRetry;
  final PolicyVerdict? verdict;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final (icon, color, headline, detail) = switch (outcome) {
      Succeeded(:final receipt) => (
        Icons.check_circle,
        scheme.primary,
        'Payment complete',
        'Receipt ${receipt.reference} · ${_time(receipt.completedAt)}',
      ),
      Failed(:final failure) => (
        Icons.error_outline,
        scheme.error,
        _failureHeadline(failure),
        _failureDetail(failure),
      ),
      // `Running` never reaches the Completed phase — the state table only builds it from a
      // terminal JobProgressed — but the switch must be exhaustive over the sealed hierarchy.
      Running() => (
        Icons.hourglass_empty,
        scheme.outline,
        'Still processing',
        'This payment has not finished yet.',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PostureBanner(verdict: verdict),
        Card(
          child: Padding(
            padding: EdgeInsets.all(tokens.spacing * 1.25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 40),
                SizedBox(height: tokens.spacing),
                Text(
                  headline,
                  style: text.headlineSmall?.copyWith(
                    fontWeight: tokens.headlineWeight,
                  ),
                ),
                SizedBox(height: tokens.spacing / 2),
                Text(detail, style: text.bodyMedium),
                if (outcome is Failed) ...[
                  SizedBox(height: tokens.spacing),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _failureHeadline(PaymentFailure failure) => switch (failure) {
    PaymentFailure.declined => 'Payment declined',
    PaymentFailure.timedOut => 'Payment timed out',
    PaymentFailure.serviceUnavailable => 'Payment not processed',
  };

  static String _failureDetail(PaymentFailure failure) => switch (failure) {
    PaymentFailure.declined =>
      'The payment was declined. Nothing has been charged.',
    PaymentFailure.timedOut =>
      'Processing took too long and was stopped. Nothing has been charged.',
    PaymentFailure.serviceUnavailable =>
      'The payment service could not be reached. Nothing has been charged.',
  };

  /// Local wall-clock time, to the minute — enough to identify the receipt without pulling in
  /// date-format configuration the architecture never asked for.
  static String _time(DateTime completedAt) {
    final local = completedAt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
