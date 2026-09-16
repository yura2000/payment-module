import 'package:get_it/get_it.dart';

import 'security_guard.dart';

/// Registers `security_guard`'s ports with [getIt]. Pass [environment]/[window] to override with
/// fakes in tests. The composition root's real registration (channel adapters) is added by the
/// native-bridge implementation plan; until then this only registers what it's given.
void registerSecurityModule(
  GetIt getIt, {
  SecurityEnvironment? environment,
  SecureWindow? window,
}) {
  if (environment != null) {
    getIt.registerSingleton<SecurityEnvironment>(environment);
  }
  if (window != null) {
    getIt.registerSingleton<SecureWindow>(window);
  }
}
