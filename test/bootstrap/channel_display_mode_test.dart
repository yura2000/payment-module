import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/bootstrap/channel_display_mode.dart';
import 'package:payment_module/core/exceptions.dart';
import 'package:payment_module/native_bridge/native_bridge.dart';

import '../support/contract_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(NativeChannels.window);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void nativeReplies(Future<Object?> Function(MethodCall call) handler) =>
      messenger.setMockMethodCallHandler(channel, handler);

  test('decodes preferHighRefreshRate.result', () async {
    nativeReplies((call) async {
      expect(call.method, 'preferHighRefreshRate');
      return contractFixture('preferHighRefreshRate.result');
    });

    expect(
      await ChannelDisplayMode().preferHighRefreshRate(),
      const DisplayModePreference(refreshRate: 120, modeId: 2),
    );
  });

  test('no mode to prefer is null', () async {
    nativeReplies((_) async => null);

    expect(await ChannelDisplayMode().preferHighRefreshRate(), isNull);
  });

  test('noActivity is a ServiceException', () async {
    nativeReplies((_) async => throw PlatformException(code: 'noActivity'));

    await expectLater(
      ChannelDisplayMode().preferHighRefreshRate(),
      throwsA(isA<ServiceException>()),
    );
  });
}
