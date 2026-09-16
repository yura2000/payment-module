import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:payment_module/features/security_guard/di.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

import '../../support/fakes/fake_secure_window.dart';
import '../../support/fakes/fake_security_environment.dart';

void main() {
  late GetIt getIt;

  setUp(() => getIt = GetIt.asNewInstance());
  tearDown(() => getIt.reset());

  test(
    'registers the given fakes as the SecurityEnvironment and SecureWindow singletons',
    () {
      final environment = FakeSecurityEnvironment();
      final window = FakeSecureWindow();

      registerSecurityModule(getIt, environment: environment, window: window);

      expect(getIt<SecurityEnvironment>(), same(environment));
      expect(getIt<SecureWindow>(), same(window));
    },
  );
}
