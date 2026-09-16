import 'package:equatable/equatable.dart';

import '../domain/policy_verdict.dart';
import '../domain/security_posture.dart';

/// State of [SecurityPostureCubit]. See docs/architecture.md §7.2.
class PostureState extends Equatable {
  const PostureState({this.posture, this.verdict});

  const PostureState.initial() : this();

  final SecurityPosture? posture;
  final PolicyVerdict? verdict;

  bool get hasFirstAssessment => posture != null;

  PostureState copyWith({SecurityPosture? posture, PolicyVerdict? verdict}) =>
      PostureState(
        posture: posture ?? this.posture,
        verdict: verdict ?? this.verdict,
      );

  @override
  List<Object?> get props => [posture, verdict];
}
