import 'package:get_it/get_it.dart';

import 'security_guard.dart';
import 'src/data/channel_secure_window.dart';
import 'src/data/channel_security_environment.dart';

/// Registers `security_guard`'s ports — the channel adapters unless [environment]/[window]
/// override them (tests pass fakes) — and the ref-counted [SecureWindowController] every secure
/// route shares. All lazy singletons (docs/architecture.md §4, §11).
void registerSecurityModule(
  GetIt getIt, {
  SecurityEnvironment? environment,
  SecureWindow? window,
}) {
  getIt
    ..registerLazySingleton<SecurityEnvironment>(
      () => environment ?? ChannelSecurityEnvironment(),
    )
    ..registerLazySingleton<SecureWindow>(() => window ?? ChannelSecureWindow())
    ..registerLazySingleton<SecureWindowController>(
      () => SecureWindowController(getIt<SecureWindow>()),
    );
}
