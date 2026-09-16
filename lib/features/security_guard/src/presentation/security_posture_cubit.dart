import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/threat.dart';
import '../domain/policy_verdict.dart' show PostureUpdate;
import '../domain/security_environment.dart';
import '../domain/watch_posture_verdict.dart';
import 'posture_state.dart';

/// Subscribes to [WatchPostureVerdict] for as long as the payment screen is mounted; re-runs the
/// one-shot checks on resume. Thin by design — its value is the seam and its reuse by any future
/// secure screen, not logic. See docs/architecture.md §7.2.
class SecurityPostureCubit extends Cubit<PostureState> {
  SecurityPostureCubit(SecurityEnvironment environment, PosturePolicy policy)
    : _environment = environment,
      super(const PostureState.initial()) {
    _subscription = WatchPostureVerdict(
      environment,
      policy,
    )().listen(_onUpdate);
  }

  final SecurityEnvironment _environment;
  late final StreamSubscription<PostureUpdate> _subscription;

  void _onUpdate(PostureUpdate update) {
    emit(state.copyWith(posture: update.posture, verdict: update.verdict));
  }

  /// Called by the page's `AppLifecycleListener` when the app resumes.
  void onResumed() {
    unawaited(_environment.assess());
  }

  @override
  Future<void> close() {
    unawaited(_subscription.cancel());
    return super.close();
  }
}
