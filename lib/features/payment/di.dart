import 'package:get_it/get_it.dart';

import 'payment.dart';
import 'src/data/channel_payment_processor.dart';

/// Registers `payment`'s ports as lazy singletons: the in-memory demo repository and the channel
/// processor, unless [repository]/[processor] override them (tests pass fakes). See
/// docs/architecture.md §4.
void registerPaymentModule(
  GetIt getIt, {
  PaymentRepository? repository,
  PaymentProcessor? processor,
}) {
  getIt
    ..registerLazySingleton<PaymentRepository>(
      () => repository ?? InMemoryPaymentRepository(),
    )
    ..registerLazySingleton<PaymentProcessor>(
      () => processor ?? ChannelPaymentProcessor(),
    );
}
