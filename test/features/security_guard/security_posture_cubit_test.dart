import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

import '../../support/fakes/fake_security_environment.dart';

void main() {
  late FakeSecurityEnvironment environment;
  late PosturePolicy policy;

  setUp(() {
    environment = FakeSecurityEnvironment();
    policy = PosturePolicy(
      onDetected: {
        ThreatKind.rooted: DetectedResponse.block,
        ThreatKind.screenRecording: DetectedResponse.warn,
      },
      onUnavailable: {
        ThreatKind.rooted: UnavailableResponse.allow,
        ThreatKind.screenRecording: UnavailableResponse.allow,
      },
    );
  });

  tearDown(() => environment.dispose());

  test('the initial state has no posture and hasFirstAssessment is false', () {
    final cubit = SecurityPostureCubit(environment, policy);
    expect(cubit.state.posture, isNull);
    expect(cubit.state.hasFirstAssessment, isFalse);
    cubit.close();
  });

  test('subscribing triggers assess() on the environment', () {
    final cubit = SecurityPostureCubit(environment, policy);
    expect(environment.assessCallCount, 1);
    cubit.close();
  });

  blocTest<SecurityPostureCubit, PostureState>(
    'emits a state with hasFirstAssessment true after the first posture arrives',
    build: () => SecurityPostureCubit(environment, policy),
    act: (cubit) => environment.pushPosture(
      SecurityPosture(const [
        ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
        ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
      ]),
    ),
    expect: () => [
      isA<PostureState>().having(
        (s) => s.hasFirstAssessment,
        'hasFirstAssessment',
        isTrue,
      ),
    ],
  );

  test('onResumed() calls assess() again', () {
    final cubit = SecurityPostureCubit(environment, policy);
    expect(environment.assessCallCount, 1);
    cubit.onResumed();
    expect(environment.assessCallCount, 2);
    cubit.close();
  });
}
