import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

import '../../support/fakes/fake_secure_window.dart';

void main() {
  late FakeSecureWindow window;
  late SecureWindowController controller;

  setUp(() {
    window = FakeSecureWindow();
    controller = SecureWindowController(window);
  });

  test(
    'the first acquire() sets the flag; a second, nested acquire() does not call again',
    () async {
      await controller.acquire();
      await controller.acquire();
      expect(window.calls, [true]);
    },
  );

  test(
    'release() only clears the flag once the count returns to zero',
    () async {
      await controller.acquire();
      await controller.acquire();
      await controller.release();
      expect(window.calls, [
        true,
      ]); // still held — one acquire is still outstanding
      await controller.release();
      expect(window.calls, [true, false]);
    },
  );

  test('release() without a matching acquire() asserts', () async {
    expect(() => controller.release(), throwsA(isA<AssertionError>()));
  });

  test('onResumed() re-asserts the flag while held', () async {
    await controller.acquire();
    await controller.onResumed();
    expect(window.calls, [true, true]);
  });

  test('onResumed() does nothing while not held', () async {
    await controller.onResumed();
    expect(window.calls, isEmpty);
  });

  test(
    'a thrown error from setSecure during acquire() is swallowed, not rethrown',
    () async {
      window.errorToThrow = Exception('no activity attached');
      await controller.acquire(); // must not throw
      expect(
        window.calls,
        isEmpty,
      ); // the call that threw is not recorded as succeeded
    },
  );
}
