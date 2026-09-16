import 'payment.dart';

/// Loads the Payment awaiting confirmation. The one seam with a single production adapter today
/// (`InMemoryPaymentRepository`, demo data) — the backend a real product would have. See
/// docs/architecture.md §2 principle 2, §5.1.
abstract class PaymentRepository {
  Future<Payment> load();
}
