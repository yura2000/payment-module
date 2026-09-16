import 'package:get_it/get_it.dart';

import 'payment.dart';

/// Registers `payment`'s ports with [getIt]. Pass [repository]/[processor] to override with
/// fakes in tests. The composition root's real registration (the channel-backed
/// `ChannelPaymentProcessor`; `InMemoryPaymentRepository` is already real) is added by the
/// native-bridge implementation plan; until then this only registers what it's given.
void registerPaymentModule(
  GetIt getIt, {
  PaymentRepository? repository,
  PaymentProcessor? processor,
}) {
  if (repository != null) {
    getIt.registerSingleton<PaymentRepository>(repository);
  }
  if (processor != null) {
    getIt.registerSingleton<PaymentProcessor>(processor);
  }
}
