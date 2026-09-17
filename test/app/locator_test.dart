import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:payment_module/app/locator.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/brands/registry.dart';
import 'package:payment_module/core/brand_id.dart';
import 'package:payment_module/features/payment/payment.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

void main() {
  late GetIt locator;

  setUp(() => locator = GetIt.asNewInstance());
  tearDown(() => locator.reset());

  test('registers the Brand it was given', () {
    final brand = brandRegistry.byId(const BrandId('utility'));
    setupLocator(brand, locator: locator);

    expect(locator<BrandConfig>(), same(brand));
  });

  test('registers both features\' ports', () {
    setupLocator(brandRegistry.byId(const BrandId('retail')), locator: locator);

    expect(locator<PaymentRepository>(), isA<InMemoryPaymentRepository>());
    expect(locator.isRegistered<PaymentProcessor>(), isTrue);
    expect(locator.isRegistered<SecurityEnvironment>(), isTrue);
    expect(locator.isRegistered<SecureWindow>(), isTrue);
    expect(locator.isRegistered<SecureWindowController>(), isTrue);
  });

  test('the ports are lazy — registering does not touch the platform', () {
    setupLocator(brandRegistry.byId(const BrandId('retail')), locator: locator);

    // Resolving the channel-backed adapters would be fine too (their constructors don't call
    // the platform), but this asserts the registration itself is inert.
    expect(locator<BrandConfig>().id.value, 'retail');
  });
}
