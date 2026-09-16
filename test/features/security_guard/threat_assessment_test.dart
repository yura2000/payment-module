import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

void main() {
  group('AssessmentResult', () {
    test('two Detected results are equal', () {
      expect(const Detected(), equals(const Detected()));
    });

    test('two Clear results are equal', () {
      expect(const Clear(), equals(const Clear()));
    });

    test('two Unavailable results with the same reason are equal', () {
      expect(
        const Unavailable(UnavailableReason.apiLevel),
        equals(const Unavailable(UnavailableReason.apiLevel)),
      );
    });

    test('Unavailable results with different reasons are not equal', () {
      expect(
        const Unavailable(UnavailableReason.apiLevel),
        isNot(equals(const Unavailable(UnavailableReason.error))),
      );
    });
  });

  group('ThreatAssessment', () {
    test('two assessments with the same kind and result are equal', () {
      const a = ThreatAssessment(kind: ThreatKind.rooted, result: Clear());
      const b = ThreatAssessment(kind: ThreatKind.rooted, result: Clear());
      expect(a, equals(b));
    });

    test(
      'assessments with different kinds are not equal even with the same result',
      () {
        const a = ThreatAssessment(kind: ThreatKind.rooted, result: Clear());
        const b = ThreatAssessment(
          kind: ThreatKind.screenRecording,
          result: Clear(),
        );
        expect(a, isNot(equals(b)));
      },
    );
  });
}
