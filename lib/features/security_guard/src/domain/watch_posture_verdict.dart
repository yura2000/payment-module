import 'dart:async';

import '../../../../core/threat.dart';
import 'policy_verdict.dart';
import 'security_environment.dart';

/// Subscribes to the Security Environment, applies a Brand's Posture Policy to every Security
/// Posture it reports, and triggers the first assessment. The one use case in `security_guard` —
/// see docs/adr/0005-use-cases-only-where-logic-lives.md.
class WatchPostureVerdict {
  WatchPostureVerdict(this._environment, this._policy);

  final SecurityEnvironment _environment;
  final PosturePolicy _policy;

  Stream<PostureUpdate> call() {
    unawaited(_environment.assess());
    return _environment.posture
        .map(
          (posture) => PostureUpdate(
            posture: posture,
            verdict: evaluatePosturePolicy(_policy, posture),
          ),
        )
        .distinct();
  }
}
