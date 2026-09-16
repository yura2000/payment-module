import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/payment_job_progress.dart';
import '../domain/payment_processor.dart';
import '../domain/payment_repository.dart';
import 'payment_confirmation_event.dart';
import 'payment_confirmation_state.dart';

/// Drives the payment confirmation flow: load, scan, confirm, process. Talks to
/// `PaymentRepository` and `PaymentProcessor` directly — no use case, see
/// docs/adr/0005-use-cases-only-where-logic-lives.md. Never subscribes to Security Posture; the
/// one posture fact it needs arrives inside `PayPressed`. See docs/architecture.md §7, §7.1.
class PaymentConfirmationBloc
    extends Bloc<PaymentConfirmationEvent, PaymentConfirmationState> {
  PaymentConfirmationBloc(
    this._repository,
    this._processor, {
    required this.scanMinDuration,
  }) : super(const PaymentConfirmationState.initial()) {
    on<Started>(_onStarted);
    on<PaymentLoaded>(_onPaymentLoaded);
    on<ScanTimerElapsed>(_onScanTimerElapsed);
    on<PayPressed>(_onPayPressed);
    on<JobProgressed>(_onJobProgressed);
    on<RetryPressed>(_onRetryPressed);
  }

  final PaymentRepository _repository;
  final PaymentProcessor _processor;
  final Duration scanMinDuration;

  Timer? _scanTimer;
  StreamSubscription<PaymentJobProgress>? _jobSubscription;

  Future<void> _onStarted(
    Started event,
    Emitter<PaymentConfirmationState> emit,
  ) async {
    final inFlight = await _processor.inFlight();
    if (isClosed) {
      return; // bloc closed while suspended on inFlight() — don't touch it further
    }
    if (inFlight != null) {
      await _listenToJob(inFlight);
      return;
    }
    _scanTimer = Timer(scanMinDuration, () => add(const ScanTimerElapsed()));
    // repository.load() failing isn't in §7.1's table — InMemoryPaymentRepository, the only
    // adapter this seam has today, cannot fail to load — so it's left to the bloc's default
    // error handling rather than given speculative handling here.
    final payment = await _repository.load();
    if (isClosed) {
      return; // bloc closed while suspended on load() — add() would throw
    }
    add(PaymentLoaded(payment));
  }

  void _onPaymentLoaded(
    PaymentLoaded event,
    Emitter<PaymentConfirmationState> emit,
  ) {
    emit(state.copyWith(payment: event.payment));
  }

  void _onScanTimerElapsed(
    ScanTimerElapsed event,
    Emitter<PaymentConfirmationState> emit,
  ) {
    if (state.phase is! Scanning) return;
    emit(state.copyWith(phase: const AwaitingConfirmation()));
  }

  Future<void> _onPayPressed(
    PayPressed event,
    Emitter<PaymentConfirmationState> emit,
  ) async {
    final payment = state.payment;
    if (state.phase is! AwaitingConfirmation ||
        payment == null ||
        event.verdict.isBlocked) {
      return; // ignored: double-tap, blocked posture, or not yet loaded
    }
    emit(state.copyWith(phase: const Processing(0)));
    try {
      await _listenToJob(_processor.start(payment));
    } catch (_) {
      emit(
        state.copyWith(
          phase: const Completed(Failed(PaymentFailure.serviceUnavailable)),
        ),
      );
    }
  }

  void _onJobProgressed(
    JobProgressed event,
    Emitter<PaymentConfirmationState> emit,
  ) {
    switch (event.progress) {
      case Running(:final percent):
        emit(state.copyWith(phase: Processing(percent)));
      case Succeeded() || Failed():
        emit(state.copyWith(phase: Completed(event.progress)));
    }
  }

  void _onRetryPressed(
    RetryPressed event,
    Emitter<PaymentConfirmationState> emit,
  ) {
    final phase = state.phase;
    if (phase is Completed && phase.outcome is Failed) {
      emit(state.copyWith(phase: const AwaitingConfirmation()));
    }
  }

  Future<void> _listenToJob(Stream<PaymentJobProgress> stream) async {
    await _jobSubscription?.cancel();
    // Guards both call sites (the re-attach path in _onStarted and the fresh-start path in
    // _onPayPressed): if close() ran while we were suspended on the cancel() above, don't create
    // a new subscription that would outlive close() and call add() on a closed bloc.
    if (isClosed) return;
    _jobSubscription = stream.listen(
      (progress) => add(JobProgressed(progress)),
    );
  }

  @override
  Future<void> close() {
    _scanTimer?.cancel();
    unawaited(_jobSubscription?.cancel());
    return super.close();
  }
}
