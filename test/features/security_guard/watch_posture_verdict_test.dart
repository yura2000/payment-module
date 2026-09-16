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

  test('calling triggers assess() on the environment', () {
    final subscription = WatchPostureVerdict(
      environment,
      policy,
    )().listen((_) {});
    expect(environment.assessCallCount, 1);
    subscription.cancel();
  });

  test(
    'emits a PostureUpdate with the policy applied, for every posture pushed',
    () async {
      final updates = <PostureUpdate>[];
      final subscription = WatchPostureVerdict(
        environment,
        policy,
      )().listen(updates.add);

      final compromised = SecurityPosture(const [
        ThreatAssessment(kind: ThreatKind.rooted, result: Detected()),
        ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
      ]);
      environment.pushPosture(compromised);
      await Future<void>.delayed(Duration.zero);

      expect(updates, hasLength(1));
      expect(updates.single.posture, compromised);
      expect(updates.single.verdict.blockers, {ThreatKind.rooted});

      await subscription.cancel();
    },
  );

  test(
    'does not re-emit for a posture identical to the last one (distinct)',
    () async {
      final updates = <PostureUpdate>[];
      final subscription = WatchPostureVerdict(
        environment,
        policy,
      )().listen(updates.add);

      SecurityPosture clear() => SecurityPosture(const [
        ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
        ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
      ]);
      environment.pushPosture(clear());
      environment.pushPosture(clear());
      await Future<void>.delayed(Duration.zero);

      expect(updates, hasLength(1));

      await subscription.cancel();
    },
  );
}
