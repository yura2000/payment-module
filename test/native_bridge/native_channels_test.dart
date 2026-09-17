import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/native_bridge/native_bridge.dart';

import '../support/contract_fixtures.dart';

void main() {
  test('channel names match contract/fixtures/channels.json', () {
    expect(contractFixture('channels'), {
      'securityEnvironment': NativeChannels.securityEnvironment,
      'securityEnvironmentEvents': NativeChannels.securityEnvironmentEvents,
      'window': NativeChannels.window,
      'paymentJob': NativeChannels.paymentJob,
      'paymentJobEvents': NativeChannels.paymentJobEvents,
      'app': NativeChannels.app,
    });
  });
}
