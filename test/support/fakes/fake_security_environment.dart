import 'dart:async';

import 'package:payment_module/features/security_guard/security_guard.dart';

/// A scripted [SecurityEnvironment] for tests. Push postures via [pushPosture]; [assess] only
/// records that it was called — push a posture separately to simulate its result arriving.
class FakeSecurityEnvironment implements SecurityEnvironment {
  final _controller = StreamController<SecurityPosture>.broadcast();
  int assessCallCount = 0;

  @override
  Future<void> assess() async {
    assessCallCount++;
  }

  @override
  Stream<SecurityPosture> get posture => _controller.stream;

  void pushPosture(SecurityPosture posture) => _controller.add(posture);

  Future<void> dispose() => _controller.close();
}
