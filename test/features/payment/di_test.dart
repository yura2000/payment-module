import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:payment_module/features/payment/di.dart';
import 'package:payment_module/features/payment/payment.dart';

import '../../support/fakes/fake_payment_processor.dart';
import '../../support/fakes/fake_payment_repository.dart';

void main() {
  late GetIt getIt;

  setUp(() => getIt = GetIt.asNewInstance());
  tearDown(() => getIt.reset());

  test(
    'registers the given fakes as the PaymentRepository and PaymentProcessor singletons',
    () {
      final repository = FakePaymentRepository();
      final processor = FakePaymentProcessor();

      registerPaymentModule(
        getIt,
        repository: repository,
        processor: processor,
      );

      expect(getIt<PaymentRepository>(), same(repository));
      expect(getIt<PaymentProcessor>(), same(processor));
    },
  );
}
