import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

import '../../support/fakes/fake_secure_window.dart';

void main() {
  testWidgets('mounting the scope acquires the Secure Window', (tester) async {
    final window = FakeSecureWindow();
    final controller = SecureWindowController(window);

    await tester.pumpWidget(
      SecureSessionScope(
        controller: controller,
        child: const SizedBox.shrink(),
      ),
    );

    expect(window.calls, [true]);
  });

  testWidgets('unmounting the scope releases the Secure Window', (
    tester,
  ) async {
    final window = FakeSecureWindow();
    final controller = SecureWindowController(window);

    await tester.pumpWidget(
      SecureSessionScope(
        controller: controller,
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());

    expect(window.calls, [true, false]);
  });

  testWidgets(
    'a second SecureSessionScope over the same controller acquires but does not toggle',
    (tester) async {
      final window = FakeSecureWindow();
      final controller = SecureWindowController(window);

      await tester.pumpWidget(
        SecureSessionScope(
          controller: controller,
          child: SecureSessionScope(
            controller: controller,
            child: const SizedBox.shrink(),
          ),
        ),
      );

      expect(window.calls, [true]); // one setSecure(true) call, not two
    },
  );
}
