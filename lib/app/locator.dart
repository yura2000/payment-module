import 'package:get_it/get_it.dart';

import '../brand_engine/brand_engine.dart';
import '../features/payment/di.dart';
import '../features/security_guard/di.dart';

/// Wires the app: the active Brand first, then each feature's ports through its own `di.dart`
/// (docs/architecture.md §4). Pass [locator] to wire a fresh `GetIt` in a test; production uses
/// the shared instance, which is what `PaymentConfirmationPage` resolves from.
void setupLocator(BrandConfig brand, {GetIt? locator}) {
  final getIt = locator ?? GetIt.I;
  getIt.registerSingleton<BrandConfig>(brand);
  registerSecurityModule(getIt);
  registerPaymentModule(getIt);
}
