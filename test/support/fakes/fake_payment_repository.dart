import 'dart:async';

import 'package:payment_module/features/payment/payment.dart';

/// A scripted [PaymentRepository] for tests. `load()` doesn't resolve until [completeWith] or
/// [completeWithError] is called, so a test can control exactly when the Payment arrives
/// relative to other events (e.g. the scan timer).
class FakePaymentRepository implements PaymentRepository {
  final _completer = Completer<Payment>();

  @override
  Future<Payment> load() => _completer.future;

  void completeWith(Payment payment) => _completer.complete(payment);

  void completeWithError(Object error) => _completer.completeError(error);
}
