import 'package:get_it/get_it.dart';

import 'security_guard.dart';
import 'src/data/channel_secure_window.dart';

/// Registers `security_guard`'s ports — the channel adapter unless [window] overrides it (tests
/// pass fakes) — and the ref-counted [SecureWindowController] every secure route shares. All lazy
/// singletons (docs/architecture.md §4, §11). [environment] is only registered when given until
/// its channel adapter exists.
void registerSecurityModule(
  GetIt getIt, {
  SecurityEnvironment? environment,
  SecureWindow? window,
}) {
  if (environment != null) {
    getIt.registerSingleton<SecurityEnvironment>(environment);
  }
  getIt
    ..registerLazySingleton<SecureWindow>(() => window ?? ChannelSecureWindow())
    ..registerLazySingleton<SecureWindowController>(
      () => SecureWindowController(getIt<SecureWindow>()),
    );
}
