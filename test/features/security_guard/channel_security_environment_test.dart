import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:payment_module/core/exceptions.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/security_guard/di.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';
import 'package:payment_module/native_bridge/native_bridge.dart';

import '../../support/contract_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methods = MethodChannel(NativeChannels.securityEnvironment);
  const events = EventChannel(NativeChannels.securityEnvironmentEvents);

  late GetIt getIt;
  late SecurityEnvironment environment;

  setUp(() {
    getIt = GetIt.asNewInstance();
    registerSecurityModule(getIt); // no overrides: the real channel adapter
    environment = getIt<SecurityEnvironment>();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockStreamHandler(events, null);
    return getIt.reset();
  });

  void nativeEmits(List<Object?> payloads, {void Function()? onCancel}) {
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (_, sink) => payloads.forEach(sink.success),
        onCancel: (_) => onCancel?.call(),
      ),
    );
  }

  group('assess', () {
    test('invokes assess on the security.environment channel', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(methods, (call) async {
        calls.add(call);
        return null;
      });

      await environment.assess();

      expect(calls.single.method, 'assess');
    });

    test('with no native handler is a ClientException', () async {
      await expectLater(environment.assess(), throwsA(isA<ClientException>()));
    });
  });

  group('posture', () {
    for (final (fixture, expected) in [
      (
        'posture.secure',
        SecurityPosture(const [
          ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
          ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
        ]),
      ),
      (
        'posture.compromised-rooted',
        SecurityPosture(const [
          ThreatAssessment(kind: ThreatKind.rooted, result: Detected()),
          ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
        ]),
      ),
      (
        'posture.unverified-api34',
        SecurityPosture(const [
          ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
          ThreatAssessment(
            kind: ThreatKind.screenRecording,
            result: Unavailable(UnavailableReason.apiLevel),
          ),
        ]),
      ),
    ]) {
      test('decodes $fixture', () async {
        nativeEmits([contractFixture(fixture)]);

        expect(await environment.posture.first, expected);
      });
    }

    test('an unknown assessment result is a TransportException', () async {
      nativeEmits([
        {
          'assessments': [
            {'kind': 'rooted', 'result': 'maybe'},
            {'kind': 'screenRecording', 'result': 'clear'},
          ],
          'assessedAt': 1758000000000,
        },
      ]);

      await expectLater(
        environment.posture.first,
        throwsA(isA<TransportException>()),
      );
    });

    test('a snapshot missing a ThreatKind is a TransportException', () async {
      nativeEmits([
        {
          'assessments': [
            {'kind': 'rooted', 'result': 'clear'},
          ],
          'assessedAt': 1758000000000,
        },
      ]);

      await expectLater(
        environment.posture.first,
        throwsA(isA<TransportException>()),
      );
    });

    test('the last listener cancelling cancels the native stream', () async {
      var cancelled = false;
      nativeEmits([
        contractFixture('posture.secure'),
      ], onCancel: () => cancelled = true);

      await environment.posture.first;
      await Future<void>.delayed(Duration.zero);

      expect(cancelled, isTrue);
    });
  });
}
