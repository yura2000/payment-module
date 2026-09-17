import 'dart:async';

import 'package:flutter/services.dart';

import '../../core/exceptions.dart';

/// How long a native method may take to reply before the call fails (docs/architecture.md §9).
const nativeReplyTimeout = Duration(seconds: 5);

/// Invokes [method] on [channel] and translates every failure into the wire → Dart table of
/// docs/architecture.md §9: `noActivity`/`serviceStartFailed` → [ServiceException];
/// `badArguments`/`alreadyRunning`/no handler → [ClientException]; any other code or no reply
/// within [timeout] → [TransportException]. Pass `timeout: null` for a call that waits on the user.
/// Returns the raw reply — decode it with [WireMap].
Future<Object?> invokeNative(
  MethodChannel channel,
  String method, {
  Object? arguments,
  Duration? timeout = nativeReplyTimeout,
}) async {
  final call = '${channel.name}#$method';
  try {
    final reply = channel.invokeMethod<Object?>(method, arguments);
    return await (timeout == null ? reply : reply.timeout(timeout));
  } on PlatformException catch (error) {
    final detail = '$call failed with ${error.code}: ${error.message}';
    throw switch (error.code) {
      'noActivity' || 'serviceStartFailed' => ServiceException(detail),
      'badArguments' || 'alreadyRunning' => ClientException(detail),
      _ => TransportException(detail),
    };
  } on MissingPluginException {
    throw ClientException('$call has no native handler');
  } on TimeoutException {
    throw TransportException('$call did not reply within $timeout');
  }
}
