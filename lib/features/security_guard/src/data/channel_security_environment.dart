import 'package:flutter/services.dart';

import '../../../../native_bridge/native_bridge.dart';
import '../domain/security_environment.dart';
import '../domain/security_posture.dart';
import 'posture_snapshot_codec.dart';

/// [SecurityEnvironment] over `security.environment` (docs/architecture.md §8, §9). [posture] is
/// one shared broadcast stream: the native side registers its API 35+ recorder callback while it
/// has a listener and replays the latest snapshot to each new one. A malformed snapshot arrives as
/// a [TransportException] stream error.
class ChannelSecurityEnvironment implements SecurityEnvironment {
  static const _methods = MethodChannel(NativeChannels.securityEnvironment);
  static const _events = EventChannel(NativeChannels.securityEnvironmentEvents);

  @override
  late final Stream<SecurityPosture> posture = _events
      .receiveBroadcastStream()
      .map(decodePostureSnapshot);

  @override
  Future<void> assess() async {
    await invokeNative(_methods, 'assess');
  }
}
