import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

void main() {
  group('SecurityPosture.classification', () {
    test('is secure when every assessment is clear', () {
      final posture = SecurityPosture(const [
        ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
        ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
      ]);
      expect(posture.classification, SecurityClassification.secure);
    });

    test(
      'is compromised when any assessment is detected, even if another is unavailable',
      () {
        final posture = SecurityPosture(const [
          ThreatAssessment(kind: ThreatKind.rooted, result: Detected()),
          ThreatAssessment(
            kind: ThreatKind.screenRecording,
            result: Unavailable(UnavailableReason.apiLevel),
          ),
        ]);
        expect(posture.classification, SecurityClassification.compromised);
      },
    );

    test(
      'is unverified when none are detected but at least one is unavailable',
      () {
        final posture = SecurityPosture(const [
          ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
          ThreatAssessment(
            kind: ThreatKind.screenRecording,
            result: Unavailable(UnavailableReason.apiLevel),
          ),
        ]);
        expect(posture.classification, SecurityClassification.unverified);
      },
    );
  });

  test('resultFor returns the assessment result for the requested kind', () {
    final posture = SecurityPosture(const [
      ThreatAssessment(kind: ThreatKind.rooted, result: Detected()),
      ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
    ]);
    expect(posture.resultFor(ThreatKind.rooted), const Detected());
    expect(posture.resultFor(ThreatKind.screenRecording), const Clear());
  });

  test('asserts when a ThreatKind is missing', () {
    expect(
      () => SecurityPosture(const [
        ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
      ]),
      throwsA(isA<AssertionError>()),
    );
  });

  test('asserts on a duplicate ThreatKind', () {
    expect(
      () => SecurityPosture(const [
        ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
        ThreatAssessment(kind: ThreatKind.rooted, result: Detected()),
        ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
      ]),
      throwsA(isA<AssertionError>()),
    );
  });

  test('two postures with the same assessments are equal', () {
    SecurityPosture build() => SecurityPosture(const [
      ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
      ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
    ]);
    expect(build(), equals(build()));
  });
}
