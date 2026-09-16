import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';

import '../native_bridge/native_bridge.dart';

/// What the native build is: the `app · buildInfo` reply (docs/architecture.md §9). The bootstrap
/// asserts [flavor] equals its `BRAND` dart-define in debug builds (§6).
class BuildInfo extends Equatable {
  const BuildInfo({
    required this.flavor,
    required this.applicationId,
    required this.versionName,
    required this.versionCode,
    required this.sdkInt,
  });

  final String flavor;
  final String applicationId;
  final String versionName;
  final int versionCode;
  final int sdkInt;

  @override
  List<Object?> get props => [
    flavor,
    applicationId,
    versionName,
    versionCode,
    sdkInt,
  ];
}

/// Reads [BuildInfo] over `app`. Composition-root infrastructure, not a domain port.
class ChannelAppInfo {
  static const _channel = MethodChannel(NativeChannels.app);

  Future<BuildInfo> buildInfo() async {
    final wire = WireMap(await invokeNative(_channel, 'buildInfo'));
    return BuildInfo(
      flavor: wire.string('flavor'),
      applicationId: wire.string('applicationId'),
      versionName: wire.string('versionName'),
      versionCode: wire.integer('versionCode'),
      sdkInt: wire.integer('sdkInt'),
    );
  }
}
