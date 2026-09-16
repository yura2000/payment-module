import 'dart:async';

import 'package:payment_module/features/payment/payment.dart';

/// A scripted [PaymentProcessor] for tests. Push progress for a started job via [pushProgress];
/// set [inFlightStream] before `start()`/`inFlight()` is called to script a re-attach scenario;
/// set [startError] to make the next `start()` throw once (then reset itself).
class FakePaymentProcessor implements PaymentProcessor {
  final _controller = StreamController<PaymentJobProgress>.broadcast();

  int startCallCount = 0;
  Payment? lastStartedPayment;
  Object? startError;
  Stream<PaymentJobProgress>? inFlightStream;

  bool get hasActiveListener => _controller.hasListener;

  @override
  Stream<PaymentJobProgress> start(Payment payment) {
    startCallCount++;
    lastStartedPayment = payment;
    if (startError != null) {
      final error = startError!;
      startError = null;
      throw error;
    }
    return _controller.stream;
  }

  void pushProgress(PaymentJobProgress progress) => _controller.add(progress);

  @override
  Future<Stream<PaymentJobProgress>?> inFlight() async => inFlightStream;

  Future<void> dispose() => _controller.close();
}
