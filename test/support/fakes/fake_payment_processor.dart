import 'dart:async';

import 'package:payment_module/features/payment/payment.dart';

/// A scripted [PaymentProcessor] for tests. Push progress for a started job via [pushProgress];
/// set [inFlightStream] before `start()`/`inFlight()` is called to script a re-attach scenario;
/// set [startError] to make the next `start()` throw once (then reset itself); call
/// [holdInFlight] before `inFlight()` is called to make it not resolve until [releaseInFlight] —
/// mirrors [FakePaymentRepository]'s `completeWith`, for tests that need to suspend a bloc
/// mid-`await inFlight()` and race it against `close()`.
class FakePaymentProcessor implements PaymentProcessor {
  final _controller = StreamController<PaymentJobProgress>.broadcast();

  int startCallCount = 0;
  Payment? lastStartedPayment;
  Object? startError;
  Stream<PaymentJobProgress>? inFlightStream;

  Completer<Stream<PaymentJobProgress>?>? _heldInFlight;

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
  Future<Stream<PaymentJobProgress>?> inFlight() {
    final held = _heldInFlight;
    return held != null ? held.future : Future.value(inFlightStream);
  }

  /// Switches `inFlight()` into "held" mode: the next call won't resolve until
  /// [releaseInFlight] is called, instead of resolving promptly from [inFlightStream].
  void holdInFlight() => _heldInFlight = Completer<Stream<PaymentJobProgress>?>();

  /// Resolves a call to `inFlight()` made while held, with [value].
  void releaseInFlight(Stream<PaymentJobProgress>? value) =>
      _heldInFlight!.complete(value);

  Future<void> dispose() => _controller.close();
}
