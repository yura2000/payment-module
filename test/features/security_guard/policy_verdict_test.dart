import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

PosturePolicy _retailPolicy() => PosturePolicy(
  onDetected: {
    ThreatKind.rooted: DetectedResponse.block,
    ThreatKind.screenRecording: DetectedResponse.warn,
  },
  onUnavailable: {
    ThreatKind.rooted: UnavailableResponse.allow,
    ThreatKind.screenRecording: UnavailableResponse.allow,
  },
);

PosturePolicy _utilityPolicy() => PosturePolicy(
  onDetected: {
    ThreatKind.rooted: DetectedResponse.block,
    ThreatKind.screenRecording: DetectedResponse.block,
  },
  onUnavailable: {
    ThreatKind.rooted: UnavailableResponse.notice,
    ThreatKind.screenRecording: UnavailableResponse.notice,
  },
);

void main() {
  group('evaluatePosturePolicy', () {
    test('a fully clear posture produces an empty verdict', () {
      final posture = SecurityPosture(const [
        ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
        ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
      ]);
      final verdict = evaluatePosturePolicy(_retailPolicy(), posture);
      expect(verdict.blockers, isEmpty);
      expect(verdict.warnings, isEmpty);
      expect(verdict.notices, isEmpty);
      expect(verdict.isBlocked, isFalse);
    });

    test(
      'Retail policy: a detected root blocks, a detected recorder only warns',
      () {
        final posture = SecurityPosture(const [
          ThreatAssessment(kind: ThreatKind.rooted, result: Detected()),
          ThreatAssessment(
            kind: ThreatKind.screenRecording,
            result: Detected(),
          ),
        ]);
        final verdict = evaluatePosturePolicy(_retailPolicy(), posture);
        expect(verdict.blockers, {ThreatKind.rooted});
        expect(verdict.warnings, {ThreatKind.screenRecording});
        expect(verdict.isBlocked, isTrue);
      },
    );

    test(
      'Retail policy: an unavailable check is allowed silently — no notice, no block',
      () {
        final posture = SecurityPosture(const [
          ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
          ThreatAssessment(
            kind: ThreatKind.screenRecording,
            result: Unavailable(UnavailableReason.apiLevel),
          ),
        ]);
        final verdict = evaluatePosturePolicy(_retailPolicy(), posture);
        expect(verdict.blockers, isEmpty);
        expect(verdict.notices, isEmpty);
        expect(verdict.isBlocked, isFalse);
      },
    );

    test('Utility policy: an unavailable check produces a notice', () {
      final posture = SecurityPosture(const [
        ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
        ThreatAssessment(
          kind: ThreatKind.screenRecording,
          result: Unavailable(UnavailableReason.apiLevel),
        ),
      ]);
      final verdict = evaluatePosturePolicy(_utilityPolicy(), posture);
      expect(verdict.notices, {ThreatKind.screenRecording});
      expect(verdict.isBlocked, isFalse);
    });

    test('Utility policy: both Threat kinds block when detected', () {
      final posture = SecurityPosture(const [
        ThreatAssessment(kind: ThreatKind.rooted, result: Detected()),
        ThreatAssessment(kind: ThreatKind.screenRecording, result: Detected()),
      ]);
      final verdict = evaluatePosturePolicy(_utilityPolicy(), posture);
      expect(verdict.blockers, {ThreatKind.rooted, ThreatKind.screenRecording});
      expect(verdict.isBlocked, isTrue);
    });
  });

  test(
    'PostureUpdate bundles a posture and its verdict, with value equality',
    () {
      final posture = SecurityPosture(const [
        ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
        ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
      ]);
      final verdict = evaluatePosturePolicy(_retailPolicy(), posture);
      final a = PostureUpdate(posture: posture, verdict: verdict);
      final b = PostureUpdate(posture: posture, verdict: verdict);
      expect(a, equals(b));
    },
  );
}
