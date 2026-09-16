import 'package:equatable/equatable.dart';

import '../../../../core/threat.dart';

/// Why a Threat's check could not run. See CONTEXT.md → Threat Assessment.
enum UnavailableReason { apiLevel, error }

/// The result of checking for one kind of Threat: detected, clear, or unavailable when the check
/// cannot run on this device. See CONTEXT.md → Threat Assessment.
sealed class AssessmentResult extends Equatable {
  const AssessmentResult();
}

final class Detected extends AssessmentResult {
  const Detected();
  @override
  List<Object?> get props => const [];
}

final class Clear extends AssessmentResult {
  const Clear();
  @override
  List<Object?> get props => const [];
}

final class Unavailable extends AssessmentResult {
  const Unavailable(this.reason);
  final UnavailableReason reason;
  @override
  List<Object?> get props => [reason];
}

/// The result of checking for one kind of Threat. See CONTEXT.md → Threat Assessment.
class ThreatAssessment extends Equatable {
  const ThreatAssessment({required this.kind, required this.result});

  final ThreatKind kind;
  final AssessmentResult result;

  @override
  List<Object?> get props => [kind, result];
}
