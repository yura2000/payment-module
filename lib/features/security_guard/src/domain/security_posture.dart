import 'package:equatable/equatable.dart';

import '../../../../core/threat.dart';
import 'threat_assessment.dart';

/// How a Security Posture is classified once every Threat has been assessed. See CONTEXT.md →
/// Security Posture.
enum SecurityClassification { secure, compromised, unverified }

/// The outcome of assessing the device environment: one Threat Assessment per kind of Threat.
/// See CONTEXT.md → Security Posture.
class SecurityPosture extends Equatable {
  SecurityPosture(Iterable<ThreatAssessment> assessments)
    : assessments = List.unmodifiable(assessments) {
    final kinds = assessments.map((a) => a.kind).toSet();
    assert(
      kinds.length == assessments.length,
      'Duplicate ThreatKind in SecurityPosture',
    );
    assert(
      kinds.containsAll(ThreatKind.values),
      'SecurityPosture is missing an assessment for '
      '${ThreatKind.values.where((k) => !kinds.contains(k))}',
    );
  }

  final List<ThreatAssessment> assessments;

  AssessmentResult resultFor(ThreatKind kind) =>
      assessments.firstWhere((a) => a.kind == kind).result;

  /// Secure — every check clear. Compromised — any Threat detected. Unverified — none detected,
  /// but at least one check could not run.
  SecurityClassification get classification {
    if (assessments.any((a) => a.result is Detected)) {
      return SecurityClassification.compromised;
    }
    if (assessments.any((a) => a.result is Unavailable)) {
      return SecurityClassification.unverified;
    }
    return SecurityClassification.secure;
  }

  @override
  List<Object?> get props => [assessments];
}
