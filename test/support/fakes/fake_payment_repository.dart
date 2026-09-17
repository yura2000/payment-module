import 'dart:async';

import 'package:payment_module/features/payment/payment.dart';

/// A scripted [PaymentRepository] for tests. `load()` doesn't resolve until [completeWith] or
/// [completeWithError] is called, so a test can control exactly when the Payment arrives
/// relative to other events (e.g. the scan timer).
///
/// `Completer.sync()`, not the default `Completer()`: this fake is typically constructed in a
/// `setUp()` — which runs outside `testWidgets`'s FakeAsync zone — and a plain `Completer`
/// captures that zone at construction, so `tester.pump()` inside the test body never flushes the
/// microtask that resumes an `await load()` suspended on it. `.sync()` delivers to the listener
/// immediately, in the completing call's own zone, sidestepping the mismatch entirely.
class FakePaymentRepository implements PaymentRepository {
  final _completer = Completer<Payment>.sync();

  @override
  Future<Payment> load() => _completer.future;

  void completeWith(Payment payment) => _completer.complete(payment);

  void completeWithError(Object error) => _completer.completeError(error);
}
