import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/exceptions.dart';
import 'package:payment_module/native_bridge/native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('test/native');

  void replyWith(Future<Object?> Function(MethodCall call) handler) =>
      messenger.setMockMethodCallHandler(channel, handler);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'passes the method and arguments through and returns the reply',
    () async {
      late MethodCall received;
      replyWith((call) async {
        received = call;
        return {'jobId': 'j-1'};
      });

      final reply = await invokeNative(channel, 'start', arguments: {'a': 1});

      expect(received.method, 'start');
      expect(received.arguments, {'a': 1});
      expect(reply, {'jobId': 'j-1'});
    },
  );

  for (final (code, type) in [
    ('noActivity', ServiceException),
    ('serviceStartFailed', ServiceException),
    ('badArguments', ClientException),
    ('alreadyRunning', ClientException),
    ('somethingNew', TransportException),
  ]) {
    test('error code $code becomes $type', () async {
      replyWith((_) async => throw PlatformException(code: code));

      await expectLater(
        invokeNative(channel, 'anything'),
        throwsA(isA<AppException>().having((e) => e.runtimeType, 'type', type)),
      );
    });
  }

  test('no native handler becomes ClientException', () async {
    await expectLater(
      invokeNative(channel, 'anything'),
      throwsA(isA<ClientException>()),
    );
  });

  testWidgets('no reply within 5 s becomes TransportException', (tester) async {
    final never = Completer<Object?>();
    replyWith((_) => never.future);

    Object? failure;
    unawaited(
      invokeNative(channel, 'anything').catchError((Object e) => failure = e),
    );
    await tester.pump(nativeReplyTimeout - const Duration(milliseconds: 1));
    expect(failure, isNull);
    await tester.pump(const Duration(milliseconds: 1));

    expect(failure, isA<TransportException>());
  });

  testWidgets('timeout: null waits for as long as the reply takes', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    replyWith((_) => pending.future);

    Object? reply;
    unawaited(
      invokeNative(channel, 'anything', timeout: null).then((r) => reply = r),
    );
    await tester.pump(const Duration(minutes: 1));
    pending.complete('granted');
    await tester.pump();

    expect(reply, 'granted');
  });
}
