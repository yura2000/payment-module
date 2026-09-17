import '../../../../core/exceptions.dart';
import '../../../../native_bridge/native_bridge.dart';
import '../domain/payment.dart';
import '../domain/payment_job_progress.dart';

/// One decoded `payment.job/events` payload (docs/architecture.md §9): which job, and how far.
class JobSnapshot {
  const JobSnapshot(this.jobId, this.progress);

  final String jobId;
  final PaymentJobProgress progress;
}

JobSnapshot decodeJobSnapshot(Object? payload) {
  final wire = WireMap(payload);
  final jobId = wire.string('jobId');
  return switch (wire.string('state')) {
    'running' => JobSnapshot(jobId, Running(wire.integer('percent'))),
    'succeeded' => JobSnapshot(
      jobId,
      Succeeded(
        PaymentReceipt(
          reference: wire.string('reference'),
          completedAt: DateTime.fromMillisecondsSinceEpoch(
            wire.integer('completedAt'),
            isUtc: true,
          ),
        ),
      ),
    ),
    'failed' => JobSnapshot(
      jobId,
      Failed(wire.enumByName('failure', PaymentFailure.values)),
    ),
    final other => throw TransportException('Unknown job state "$other"'),
  };
}

/// The `start` arguments (docs/architecture.md §9).
Map<String, Object?> encodeStartArgs(Payment payment) => {
  'reference': payment.reference,
  'amountMinor': payment.amount.amountMinor,
  'currency': payment.amount.currency,
  'payee': payment.payee,
};
