import 'dart:developer';

import 'package:flutter/services.dart';

import '../../../../core/exceptions.dart';
import '../../../../native_bridge/native_bridge.dart';
import '../domain/payment.dart';
import '../domain/payment_job_progress.dart';
import '../domain/payment_processor.dart';
import 'job_snapshot_codec.dart';

/// [PaymentProcessor] over `payment.job` (docs/architecture.md §9, §10). A job's progress is the
/// shared, replay-1 event stream filtered to its `jobId`, completing after the first terminal
/// snapshot. Failures before the job exists arrive as stream errors — except `serviceStartFailed`,
/// which is an expected outcome and arrives as the value `Failed(serviceUnavailable)`.
class ChannelPaymentProcessor implements PaymentProcessor {
  static const _methods = MethodChannel(NativeChannels.paymentJob);
  static const _eventChannel = EventChannel(NativeChannels.paymentJobEvents);

  late final Stream<Object?> _events = _eventChannel.receiveBroadcastStream();

  @override
  Stream<PaymentJobProgress> start(Payment payment) async* {
    await _ensureNotificationPermission();
    final String jobId;
    try {
      final reply = await invokeNative(
        _methods,
        'start',
        arguments: encodeStartArgs(payment),
      );
      jobId = WireMap(reply).string('jobId');
    } on ServiceException {
      // `start`'s only ServiceException is serviceStartFailed (§9).
      yield const Failed(PaymentFailure.serviceUnavailable);
      return;
    }
    yield* _progressOf(jobId);
  }

  @override
  Future<Stream<PaymentJobProgress>?> inFlight() async {
    final reply = await invokeNative(_methods, 'current');
    if (reply == null) return null;
    final snapshot = decodeJobSnapshot(reply);
    return switch (snapshot.progress) {
      Running() => _progressOf(snapshot.jobId),
      final terminal => Stream.value(terminal),
    };
  }

  /// Asks for POST_NOTIFICATIONS without a timeout — it waits on the user — and never gates the
  /// job: the outcome, or a failure to ask, is only logged (§10).
  Future<void> _ensureNotificationPermission() async {
    try {
      final outcome = await invokeNative(
        _methods,
        'ensureNotificationPermission',
        timeout: null,
      );
      log('POST_NOTIFICATIONS: $outcome', name: 'payment.job');
    } on AppException catch (error) {
      log('POST_NOTIFICATIONS not requested: $error', name: 'payment.job');
    }
  }

  Stream<PaymentJobProgress> _progressOf(String jobId) async* {
    await for (final payload in _events) {
      final snapshot = decodeJobSnapshot(payload);
      if (snapshot.jobId != jobId) continue;
      yield snapshot.progress;
      if (snapshot.progress is! Running) return;
    }
  }
}
