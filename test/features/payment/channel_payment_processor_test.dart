import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:payment_module/core/exceptions.dart';
import 'package:payment_module/core/money.dart';
import 'package:payment_module/features/payment/di.dart';
import 'package:payment_module/features/payment/payment.dart';
import 'package:payment_module/native_bridge/native_bridge.dart';

import '../../support/contract_fixtures.dart';

/// Matches contract/fixtures/start.args.json.
const fixturePayment = Payment(
  reference: 'PAY-DEMO-0001',
  amount: Money(amountMinor: 4200, currency: 'USD'),
  payee: 'Acme Utilities',
  lineItems: [],
);

final fixtureReceipt = PaymentReceipt(
  reference: 'PAY-DEMO-0001',
  completedAt: DateTime.fromMillisecondsSinceEpoch(1758000000000, isUtc: true),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methods = MethodChannel(NativeChannels.paymentJob);
  const events = EventChannel(NativeChannels.paymentJobEvents);

  late GetIt getIt;
  late PaymentProcessor processor;
  late List<MethodCall> calls;
  late int listens;

  setUp(() {
    getIt = GetIt.asNewInstance();
    registerPaymentModule(getIt); // no overrides: the real channel adapter
    processor = getIt<PaymentProcessor>();
    calls = [];
    listens = 0;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockStreamHandler(events, null);
    return getIt.reset();
  });

  /// Scripts `payment.job`: each method name maps to its reply (or a thrown PlatformException).
  void nativeReplies(Map<String, FutureOr<Object?> Function()> replies) {
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      return replies[call.method]!();
    });
  }

  void nativeEmits(List<Object?> payloads) {
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (_, sink) {
          listens++;
          payloads.forEach(sink.success);
        },
      ),
    );
  }

  Map<String, Object?> otherJob() => {
    'jobId': 'j-other',
    'state': 'running',
    'percent': 90,
  };

  group('start', () {
    test('asks for notification permission, starts the job with the payment, '
        "and follows only that job's snapshots to its terminal one", () async {
      nativeReplies({
        'ensureNotificationPermission': () => 'granted',
        'start': () => {'jobId': 'j-1'},
      });
      nativeEmits([
        contractFixture('job.running'),
        otherJob(),
        contractFixture('job.succeeded'),
        contractFixture('job.running'), // after the terminal one: never read
      ]);

      final progress = await processor.start(fixturePayment).toList();

      expect(calls.map((c) => c.method), [
        'ensureNotificationPermission',
        'start',
      ]);
      expect(calls.last.arguments, contractFixture('start.args'));
      expect(progress, [const Running(40), Succeeded(fixtureReceipt)]);
    });

    test('a failed permission request never gates the job', () async {
      nativeReplies({
        'ensureNotificationPermission': () =>
            throw PlatformException(code: 'noActivity'),
        'start': () => {'jobId': 'j-1'},
      });
      nativeEmits([contractFixture('job.failed-declined')]);

      final progress = await processor.start(fixturePayment).toList();

      expect(progress, [const Failed(PaymentFailure.declined)]);
    });

    testWidgets(
      'waits on the permission prompt for as long as the user takes',
      (tester) async {
        final answer = Completer<Object?>();
        nativeReplies({
          'ensureNotificationPermission': () => answer.future,
          'start': () => {'jobId': 'j-1'},
        });
        nativeEmits([contractFixture('job.succeeded')]);

        final progress = <PaymentJobProgress>[];
        processor.start(fixturePayment).listen(progress.add);
        await tester.pump(const Duration(minutes: 1));
        expect(calls.map((c) => c.method), ['ensureNotificationPermission']);

        answer.complete('denied');
        for (var i = 0; i < 5; i++) {
          await tester.pump();
        }

        expect(calls.map((c) => c.method).last, 'start');
        expect(progress, [Succeeded(fixtureReceipt)]);
      },
    );

    test(
      'serviceStartFailed is the value Failed(serviceUnavailable)',
      () async {
        nativeReplies({
          'ensureNotificationPermission': () => 'granted',
          'start': () => throw PlatformException(code: 'serviceStartFailed'),
        });

        final progress = await processor.start(fixturePayment).toList();

        expect(progress, [const Failed(PaymentFailure.serviceUnavailable)]);
        expect(listens, 0);
      },
    );

    test('alreadyRunning is a ClientException on the stream', () async {
      nativeReplies({
        'ensureNotificationPermission': () => 'granted',
        'start': () => throw PlatformException(code: 'alreadyRunning'),
      });

      await expectLater(
        processor.start(fixturePayment).toList(),
        throwsA(isA<ClientException>()),
      );
    });

    test(
      "a malformed snapshot is a TransportException on the job's stream",
      () async {
        nativeReplies({
          'ensureNotificationPermission': () => 'granted',
          'start': () => {'jobId': 'j-1'},
        });
        nativeEmits([
          {'jobId': 'j-1', 'state': 'failed', 'failure': 'lostInTheMail'},
        ]);

        await expectLater(
          processor.start(fixturePayment).toList(),
          throwsA(isA<TransportException>()),
        );
      },
    );

    test(
      'cancelling the job stream cancels the native subscription at once',
      () async {
        var cancelled = false;
        nativeReplies({
          'ensureNotificationPermission': () => 'granted',
          'start': () => {'jobId': 'j-1'},
        });
        messenger.setMockStreamHandler(
          events,
          MockStreamHandler.inline(
            onListen: (_, sink) => sink.success(contractFixture('job.running')),
            onCancel: (_) => cancelled = true,
          ),
        );

        final subscription = processor.start(fixturePayment).listen((_) {});
        await pumpEventQueue();
        // The job is still running natively; no further snapshot arrives.
        unawaited(subscription.cancel());
        await pumpEventQueue();

        expect(cancelled, isTrue);
      },
    );
  });

  group('inFlight', () {
    test('no job is null', () async {
      nativeReplies({'current': () => null});

      expect(await processor.inFlight(), isNull);
    });

    test(
      'a running job is its stream, from the replayed snapshot to the terminal one',
      () async {
        nativeReplies({'current': () => contractFixture('job.running')});
        nativeEmits([
          contractFixture('job.running'),
          contractFixture('job.failed-declined'),
        ]);

        final stream = await processor.inFlight();

        expect(await stream!.toList(), [
          const Running(40),
          const Failed(PaymentFailure.declined),
        ]);
      },
    );

    test('a terminal job is just its outcome, without subscribing', () async {
      nativeReplies({'current': () => contractFixture('job.failed-timedOut')});
      nativeEmits([]);

      final stream = await processor.inFlight();

      expect(await stream!.toList(), [const Failed(PaymentFailure.timedOut)]);
      expect(listens, 0);
    });

    test('an unknown state is a TransportException', () async {
      nativeReplies({
        'current': () => {'jobId': 'j-1', 'state': 'paused'},
      });

      await expectLater(
        processor.inFlight(),
        throwsA(isA<TransportException>()),
      );
    });

    test(
      "cancelling a running job's stream cancels the native subscription at once",
      () async {
        var cancelled = false;
        nativeReplies({'current': () => contractFixture('job.running')});
        messenger.setMockStreamHandler(
          events,
          MockStreamHandler.inline(
            onListen: (_, sink) => sink.success(contractFixture('job.running')),
            onCancel: (_) => cancelled = true,
          ),
        );

        final subscription = (await processor.inFlight())!.listen((_) {});
        await pumpEventQueue();
        unawaited(subscription.cancel());
        await pumpEventQueue();

        expect(cancelled, isTrue);
      },
    );
  });
}
