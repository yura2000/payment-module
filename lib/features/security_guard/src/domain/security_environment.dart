import 'security_posture.dart';

/// Assesses the device's Security Posture. One source of truth: [assess] re-runs the one-shot
/// checks and pushes a snapshot onto [posture]; a live signal (the API 35+ screen-recorder
/// callback) pushes its own transitions independently. See docs/architecture.md §5.1, §8.
abstract class SecurityEnvironment {
  Future<void> assess();
  Stream<SecurityPosture> get posture;
}
