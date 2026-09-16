import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';

import '../native_bridge/native_bridge.dart';

/// The display mode the app asked Android for. A request, not a guarantee: OEM power modes and
/// user caps can still hold the display at 60 Hz (docs/architecture.md §12.2).
class DisplayModePreference extends Equatable {
  const DisplayModePreference({
    required this.refreshRate,
    required this.modeId,
  });

  final double refreshRate;
  final int modeId;

  @override
  List<Object?> get props => [refreshRate, modeId];
}

/// `window · preferHighRefreshRate`. Composition-root infrastructure, not a domain port — it
/// shares the `window` channel with `security_guard`'s `ChannelSecureWindow`.
class ChannelDisplayMode {
  static const _channel = MethodChannel(NativeChannels.window);

  /// `null` when the display offers no mode at its current resolution.
  Future<DisplayModePreference?> preferHighRefreshRate() async {
    final reply = await invokeNative(_channel, 'preferHighRefreshRate');
    if (reply == null) return null;
    final wire = WireMap(reply);
    return DisplayModePreference(
      refreshRate: wire.decimal('refreshRate'),
      modeId: wire.integer('modeId'),
    );
  }
}
