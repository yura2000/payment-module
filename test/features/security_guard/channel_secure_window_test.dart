import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:payment_module/core/exceptions.dart';
import 'package:payment_module/features/security_guard/di.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';
import 'package:payment_module/native_bridge/native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel(NativeChannels.window);

  late GetIt getIt;
  late List<MethodCall> calls;

  setUp(() {
    getIt = GetIt.asNewInstance();
    registerSecurityModule(getIt); // no overrides: the real channel adapter
    calls = [];
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    return getIt.reset();
  });

  void nativeReplies(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
  }

  test('setSecure sends {secure} on the window channel', () async {
    nativeReplies((_) async => null);

    await getIt<SecureWindow>().setSecure(true);
    await getIt<SecureWindow>().setSecure(false);

    expect(calls.map((c) => c.method), ['setSecure', 'setSecure']);
    expect(calls.map((c) => c.arguments), [
      {'secure': true},
      {'secure': false},
    ]);
  });

  test('noActivity is a ServiceException', () async {
    nativeReplies((_) async => throw PlatformException(code: 'noActivity'));

    await expectLater(
      getIt<SecureWindow>().setSecure(true),
      throwsA(isA<ServiceException>()),
    );
  });

  test(
    'through the registered controller, noActivity is swallowed and resume re-asserts',
    () async {
      var attached = false;
      nativeReplies((_) async {
        if (!attached) throw PlatformException(code: 'noActivity');
        return null;
      });
      final controller = getIt<SecureWindowController>();

      await controller.acquire();
      attached = true;
      await controller.onResumed();

      expect(calls.map((c) => c.arguments), [
        {'secure': true},
        {'secure': true},
      ]);
    },
  );
}
