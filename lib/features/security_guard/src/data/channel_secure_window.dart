import 'package:flutter/services.dart';

import '../../../../native_bridge/native_bridge.dart';
import '../domain/secure_window.dart';

/// [SecureWindow] over `window` (docs/architecture.md §9, §11). `noActivity` surfaces as a
/// transient `ServiceException`, which `SecureWindowController` swallows and retries on resume.
class ChannelSecureWindow implements SecureWindow {
  static const _channel = MethodChannel(NativeChannels.window);

  @override
  Future<void> setSecure(bool secure) async {
    await invokeNative(_channel, 'setSecure', arguments: {'secure': secure});
  }
}
