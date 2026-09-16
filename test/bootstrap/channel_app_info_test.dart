import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/bootstrap/channel_app_info.dart';
import 'package:payment_module/core/exceptions.dart';
import 'package:payment_module/native_bridge/native_bridge.dart';

import '../support/contract_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(NativeChannels.app);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('decodes buildInfo.retail', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'buildInfo');
      return contractFixture('buildInfo.retail');
    });

    expect(
      await ChannelAppInfo().buildInfo(),
      const BuildInfo(
        flavor: 'retail',
        applicationId: 'dev.test.payment.retail',
        versionName: '0.1.0',
        versionCode: 1,
        sdkInt: 36,
      ),
    );
  });

  test('a mistyped field is a TransportException', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {...contractFixture('buildInfo.retail'), 'versionCode': '1'},
    );

    await expectLater(
      ChannelAppInfo().buildInfo(),
      throwsA(isA<TransportException>()),
    );
  });
}
