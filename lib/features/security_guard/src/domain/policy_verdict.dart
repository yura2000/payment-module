import 'package:equatable/equatable.dart';

import '../../../../core/threat.dart';
import 'security_posture.dart';
import 'threat_assessment.dart';

/// The result of applying a Posture Policy to a Security Posture: which Threats block the
/// payment, which only warn, and which checks deserve a notice. See CONTEXT.md → Policy Verdict.
class PolicyVerdict extends Equatable {
  const PolicyVerdict({
    required this.blockers,
    required this.warnings,
    required this.notices,
  });

  final Set<ThreatKind> blockers;
  final Set<ThreatKind> warnings;
  final Set<ThreatKind> notices;

  bool get isBlocked => blockers.isNotEmpty;

  @override
  List<Object?> get props => [blockers, warnings, notices];
}

/// Applies [policy] to [posture]. Pure — the internal seam of `WatchPostureVerdict`, exported so
/// it can be unit-tested directly. See docs/architecture.md §5.1 and
/// docs/adr/0005-use-cases-only-where-logic-lives.md.
PolicyVerdict evaluatePosturePolicy(
  PosturePolicy policy,
  SecurityPosture posture,
) {
  final blockers = <ThreatKind>{};
  final warnings = <ThreatKind>{};
  final notices = <ThreatKind>{};

  for (final assessment in posture.assessments) {
    switch (assessment.result) {
      case Detected():
        switch (policy.onDetected[assessment.kind]!) {
          case DetectedResponse.block:
            blockers.add(assessment.kind);
          case DetectedResponse.warn:
            warnings.add(assessment.kind);
        }
      case Clear():
        break;
      case Unavailable():
        switch (policy.onUnavailable[assessment.kind]!) {
          case UnavailableResponse.notice:
            notices.add(assessment.kind);
          case UnavailableResponse.allow:
            break;
        }
    }
  }

  return PolicyVerdict(
    blockers: blockers,
    warnings: warnings,
    notices: notices,
  );
}

/// A Security Posture paired with the Policy Verdict derived from it — what `WatchPostureVerdict`
/// streams.
class PostureUpdate extends Equatable {
  const PostureUpdate({required this.posture, required this.verdict});

  final SecurityPosture posture;
  final PolicyVerdict verdict;

  @override
  List<Object?> get props => [posture, verdict];
}
