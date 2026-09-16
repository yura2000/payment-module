import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/exceptions.dart';
import 'package:payment_module/core/money.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/payment/payment.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

import '../../support/fakes/fake_payment_processor.dart';
import '../../support/fakes/fake_payment_repository.dart';

const testScanDuration = Duration(milliseconds: 10);

const testPayment = Payment(
  reference: 'PAY-TEST-0001',
  amount: Money(amountMinor: 4200, currency: 'USD'),
  payee: 'Acme Utilities',
  lineItems: [],
);

const unblockedVerdict = PolicyVerdict(blockers: {}, warnings: {}, notices: {});
const blockedVerdict = PolicyVerdict(
  blockers: {ThreatKind.rooted},
  warnings: {},
  notices: {},
);

final testReceipt = PaymentReceipt(reference: 'PAY-TEST-0001', completedAt: DateTime.utc(2026, 9, 16));

void main() {
  late FakePaymentRepository repository;
  late FakePaymentProcessor processor;

  setUp(() {
    repository = FakePaymentRepository();
    processor = FakePaymentProcessor();
  });

  tearDown(() => processor.dispose());

  PaymentConfirmationBloc buildBloc() =>
      PaymentConfirmationBloc(repository, processor, scanMinDuration: testScanDuration);

  group('Started — cold entry', () {
    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'no in-flight job: loads the payment and stays in Scanning',
      build: () {
        repository.completeWith(testPayment);
        return buildBloc();
      },
      act: (bloc) => bloc.add(const Started()),
      expect: () => [
        const PaymentConfirmationState(payment: testPayment, phase: Scanning()),
      ],
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'in-flight job running: goes straight to Processing, skipping Scanning',
      build: () {
        processor.inFlightStream = Stream.value(const Running(40));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const Started()),
      expect: () => [
        const PaymentConfirmationState(phase: Processing(40)),
      ],
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'in-flight job already succeeded: goes straight to Completed',
      build: () {
        processor.inFlightStream = Stream.value(Succeeded(testReceipt));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const Started()),
      expect: () => [
        PaymentConfirmationState(phase: Completed(Succeeded(testReceipt))),
      ],
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'in-flight job already failed: goes straight to Completed',
      build: () {
        processor.inFlightStream = Stream.value(const Failed(PaymentFailure.declined));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const Started()),
      expect: () => [
        const PaymentConfirmationState(phase: Completed(Failed(PaymentFailure.declined))),
      ],
    );
  });

  group('Scanning', () {
    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'PaymentLoaded sets the payment and stays in Scanning',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(phase: Scanning()),
      act: (bloc) => bloc.add(const PaymentLoaded(testPayment)),
      expect: () => [
        const PaymentConfirmationState(payment: testPayment, phase: Scanning()),
      ],
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'ScanTimerElapsed moves to AwaitingConfirmation',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(payment: testPayment, phase: Scanning()),
      act: (bloc) => bloc.add(const ScanTimerElapsed()),
      expect: () => [
        const PaymentConfirmationState(payment: testPayment, phase: AwaitingConfirmation()),
      ],
    );
  });

  group('AwaitingConfirmation', () {
    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'a payment that finishes loading after the scan timer still gets set (slow load)',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(phase: AwaitingConfirmation()),
      act: (bloc) => bloc.add(const PaymentLoaded(testPayment)),
      expect: () => [
        const PaymentConfirmationState(payment: testPayment, phase: AwaitingConfirmation()),
      ],
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'PayPressed with an unblocked verdict and a loaded payment starts the job',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(payment: testPayment, phase: AwaitingConfirmation()),
      act: (bloc) => bloc.add(const PayPressed(unblockedVerdict)),
      expect: () => [
        const PaymentConfirmationState(payment: testPayment, phase: Processing(0)),
      ],
      verify: (_) {
        expect(processor.startCallCount, 1);
        expect(processor.lastStartedPayment, testPayment);
      },
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'PayPressed with a blocked verdict is ignored',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(payment: testPayment, phase: AwaitingConfirmation()),
      act: (bloc) => bloc.add(const PayPressed(blockedVerdict)),
      expect: () => <PaymentConfirmationState>[],
      verify: (_) => expect(processor.startCallCount, 0),
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'PayPressed before the payment has loaded is ignored',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(phase: AwaitingConfirmation()),
      act: (bloc) => bloc.add(const PayPressed(unblockedVerdict)),
      expect: () => <PaymentConfirmationState>[],
      verify: (_) => expect(processor.startCallCount, 0),
    );
  });

  group('Processing', () {
    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'JobProgressed(Running) updates the percent',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(payment: testPayment, phase: Processing(0)),
      act: (bloc) => bloc.add(const JobProgressed(Running(55))),
      expect: () => [
        const PaymentConfirmationState(payment: testPayment, phase: Processing(55)),
      ],
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'JobProgressed(Succeeded) moves to Completed',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(payment: testPayment, phase: Processing(90)),
      act: (bloc) => bloc.add(JobProgressed(Succeeded(testReceipt))),
      expect: () => [
        PaymentConfirmationState(payment: testPayment, phase: Completed(Succeeded(testReceipt))),
      ],
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'JobProgressed(Failed) moves to Completed',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(payment: testPayment, phase: Processing(60)),
      act: (bloc) => bloc.add(const JobProgressed(Failed(PaymentFailure.declined))),
      expect: () => [
        const PaymentConfirmationState(
          payment: testPayment,
          phase: Completed(Failed(PaymentFailure.declined)),
        ),
      ],
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'PayPressed while Processing is ignored (double-tap, or "back")',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(payment: testPayment, phase: Processing(40)),
      act: (bloc) => bloc.add(const PayPressed(unblockedVerdict)),
      expect: () => <PaymentConfirmationState>[],
      verify: (_) => expect(processor.startCallCount, 0),
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'processor.start() throwing moves Processing straight to Completed(Failed(serviceUnavailable))',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(payment: testPayment, phase: AwaitingConfirmation()),
      act: (bloc) {
        processor.startError = const ServiceException('no Activity attached');
        bloc.add(const PayPressed(unblockedVerdict));
      },
      expect: () => [
        const PaymentConfirmationState(payment: testPayment, phase: Processing(0)),
        const PaymentConfirmationState(
          payment: testPayment,
          phase: Completed(Failed(PaymentFailure.serviceUnavailable)),
        ),
      ],
    );
  });

  group('Completed', () {
    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'RetryPressed after a failed job returns to AwaitingConfirmation',
      build: buildBloc,
      seed: () => const PaymentConfirmationState(
        payment: testPayment,
        phase: Completed(Failed(PaymentFailure.declined)),
      ),
      act: (bloc) => bloc.add(const RetryPressed()),
      expect: () => [
        const PaymentConfirmationState(payment: testPayment, phase: AwaitingConfirmation()),
      ],
    );

    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'RetryPressed after a succeeded job is ignored — terminal until pop',
      build: buildBloc,
      seed: () => PaymentConfirmationState(
        payment: testPayment,
        phase: Completed(Succeeded(testReceipt)),
      ),
      act: (bloc) => bloc.add(const RetryPressed()),
      expect: () => <PaymentConfirmationState>[],
    );
  });

  group('wiring', () {
    blocTest<PaymentConfirmationBloc, PaymentConfirmationState>(
      'the scan timer really fires after scanMinDuration, not just as a reducer',
      build: buildBloc, // repository never completes — isolates the timer from PaymentLoaded
      act: (bloc) => bloc.add(const Started()),
      wait: testScanDuration * 3,
      expect: () => [
        const PaymentConfirmationState(phase: AwaitingConfirmation()),
      ],
    );
  });

  test('close() cancels an active job subscription', () async {
    repository.completeWith(testPayment);
    final bloc = buildBloc();
    bloc.add(const Started());
    await Future<void>.delayed(Duration.zero);
    bloc.add(const ScanTimerElapsed());
    await Future<void>.delayed(Duration.zero);
    bloc.add(const PayPressed(unblockedVerdict));
    await Future<void>.delayed(Duration.zero);

    expect(processor.hasActiveListener, isTrue);
    await bloc.close();
    expect(processor.hasActiveListener, isFalse);
  });

  test(
    'close() while Started is still suspended on repository.load() does not throw or leak',
    () async {
      // repository.load() only resolves once completeWith() is called — a genuine suspension
      // point — so this reliably catches _onStarted still awaiting when close() runs, rather
      // than racing a fast microtask.
      final bloc = buildBloc();
      bloc.add(const Started());
      // Let the handler run past the (fast) processor.inFlight() check and suspend on load().
      await Future<void>.delayed(Duration.zero);
      await bloc.close();

      // Resolving the load now must not throw. Before the fix, the still-suspended handler
      // would call add(PaymentLoaded(...)) on the already-closed bloc and throw
      // "Bad state: Cannot add new events after calling close".
      repository.completeWith(testPayment);
      await Future<void>.delayed(Duration.zero);

      expect(processor.hasActiveListener, isFalse);
    },
  );

  test(
    'close() while Started is still suspended on a null-resolving processor.inFlight() '
    'does not throw',
    () async {
      // The sibling of the "in-flight processor.inFlight()" test below, but for the *common*
      // case: no job in flight, inFlight() resolves to null. Without the isClosed guard right
      // after `await _processor.inFlight()`, execution would fall through past close() to create
      // _scanTimer — a Timer close() never gets the chance to cancel, since it's assigned after
      // close() already ran. When that orphaned Timer later fires, it calls
      // add(const ScanTimerElapsed()) on the already-closed bloc and throws
      // "Bad state: Cannot add new events after calling close". holdInFlight()/releaseInFlight()
      // give this a genuine, Completer-backed suspension point on inFlight() — mirroring
      // FakePaymentRepository's completeWith() — so the race is deterministic rather than
      // hoping to beat a fast microtask.
      processor.holdInFlight();
      final bloc = buildBloc();

      bloc.add(const Started());
      await Future<void>.delayed(Duration.zero); // let the handler reach and suspend on inFlight()
      await bloc.close();

      // Resolving inFlight() now (to null, the no-job-in-flight case) must not throw, and must
      // not leave a live _scanTimer behind to fire later and call add() on the closed bloc.
      processor.releaseInFlight(null);
      await Future<void>.delayed(testScanDuration * 3);
    },
  );

  test(
    'close() while Started is still suspended on an in-flight processor.inFlight() '
    'does not throw or leak a subscription',
    () async {
      // A never-completing Completer-backed stream stands in for a job that's still running —
      // start() on it is never called, so hasActiveListener below tracks whether _listenToJob
      // ever subscribed to it after close().
      final inFlightController = StreamController<PaymentJobProgress>.broadcast();
      processor.inFlightStream = inFlightController.stream;
      final bloc = buildBloc();

      bloc.add(const Started());
      await bloc.close();
      // Flush whatever microtasks the still-suspended handler needed to resume and (before the
      // fix) reach `_jobSubscription = stream.listen(...)` past close().
      await Future<void>.delayed(Duration.zero);

      expect(inFlightController.hasListener, isFalse);
      await inFlightController.close();
    },
  );

  test(
    "close() fired immediately after PayPressed doesn't throw or leak a subscription "
    "(approximates the race on _onPayPressed's job-subscribe path)",
    () async {
      // The guard this exercises lives inside _listenToJob, at `await _jobSubscription?.cancel()`
      // — the one suspension point on _onPayPressed's path (start() itself is synchronous; even
      // with no prior subscription, `await null` still yields one microtask before _listenToJob
      // continues to `stream.listen(...)`). Landing close() deterministically inside that single
      // microtask gap would need clock-control machinery this codebase doesn't otherwise use
      // (fake_async's FakeAsync, or a controllable Completer-backed onCancel on the fake
      // processor's StreamController). Short of that, firing close() back-to-back with the
      // triggering event — no await in between — is the closest deterministic approximation
      // available: it maximizes the chance the handler is still mid-_listenToJob when close()
      // runs. Whether or not that exact interleaving is hit on a given run, the assertion below
      // must hold either way — that's what the isClosed guard (and close()'s own
      // unawaited(_jobSubscription?.cancel())) is for — so this is a real regression net for
      // that call site even though it cannot force the race on demand.
      repository.completeWith(testPayment);
      final bloc = buildBloc();
      bloc.add(const Started());
      await Future<void>.delayed(Duration.zero);
      bloc.add(const ScanTimerElapsed());
      await Future<void>.delayed(Duration.zero);
      // Now in AwaitingConfirmation with a loaded payment.

      bloc.add(const PayPressed(unblockedVerdict));
      await bloc.close(); // no await between add() and close()

      await Future<void>.delayed(Duration.zero);

      expect(processor.hasActiveListener, isFalse);
    },
  );
}
