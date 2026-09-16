import 'payment.dart';
import 'payment_job_progress.dart';

/// Starts a Payment Job and reports its progress; finds one already running (the app was
/// reopened mid-job). See docs/architecture.md §5.1, §10.
abstract class PaymentProcessor {
  Stream<PaymentJobProgress> start(Payment payment);
  Future<Stream<PaymentJobProgress>?> inFlight();
}
