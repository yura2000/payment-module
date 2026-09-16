import '../../../../core/exceptions.dart';
import '../../../../core/threat.dart';
import '../../../../native_bridge/native_bridge.dart';
import '../domain/security_posture.dart';
import '../domain/threat_assessment.dart';

/// Decodes one `security.environment/events` payload (docs/architecture.md §9) into a
/// [SecurityPosture]. `assessedAt` is on the wire for diagnostics only; the domain doesn't carry it.
SecurityPosture decodePostureSnapshot(Object? payload) {
  final assessments = [
    for (final item in WireMap(payload).list('assessments'))
      _decodeAssessment(WireMap(item)),
  ];
  // SecurityPosture only asserts this in debug builds; a release build must not accept it either.
  final kinds = assessments.map((a) => a.kind).toSet();
  if (kinds.length != assessments.length ||
      kinds.length != ThreatKind.values.length) {
    throw TransportException(
      'Expected one assessment per ThreatKind, got ${assessments.map((a) => a.kind).toList()}',
    );
  }
  return SecurityPosture(assessments);
}

ThreatAssessment _decodeAssessment(WireMap wire) => ThreatAssessment(
  kind: wire.enumByName('kind', ThreatKind.values),
  result: switch (wire.string('result')) {
    'detected' => const Detected(),
    'clear' => const Clear(),
    'unavailable' => Unavailable(
      wire.enumByName('reason', UnavailableReason.values),
    ),
    final other => throw TransportException(
      'Unknown assessment result "$other"',
    ),
  },
);
