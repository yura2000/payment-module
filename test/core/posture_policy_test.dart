import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/threat.dart';

void main() {
  group('PosturePolicy', () {
    test(
      'constructs when every ThreatKind has both a detected and unavailable response',
      () {
        final policy = PosturePolicy(
          onDetected: {
            ThreatKind.rooted: DetectedResponse.block,
            ThreatKind.screenRecording: DetectedResponse.warn,
          },
          onUnavailable: {
            ThreatKind.rooted: UnavailableResponse.allow,
            ThreatKind.screenRecording: UnavailableResponse.notice,
          },
        );

        expect(policy.onDetected[ThreatKind.rooted], DetectedResponse.block);
        expect(
          policy.onUnavailable[ThreatKind.screenRecording],
          UnavailableResponse.notice,
        );
      },
    );

    test('asserts when a ThreatKind is missing from onDetected', () {
      expect(
        () => PosturePolicy(
          onDetected: {ThreatKind.rooted: DetectedResponse.block},
          onUnavailable: {
            ThreatKind.rooted: UnavailableResponse.allow,
            ThreatKind.screenRecording: UnavailableResponse.notice,
          },
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('asserts when a ThreatKind is missing from onUnavailable', () {
      expect(
        () => PosturePolicy(
          onDetected: {
            ThreatKind.rooted: DetectedResponse.block,
            ThreatKind.screenRecording: DetectedResponse.warn,
          },
          onUnavailable: {ThreatKind.rooted: UnavailableResponse.allow},
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
