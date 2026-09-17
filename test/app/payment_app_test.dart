import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:payment_module/app/payment_app.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/brands/registry.dart';
import 'package:payment_module/core/brand_id.dart';
import 'package:payment_module/features/payment/di.dart';
import 'package:payment_module/features/payment/payment.dart';
import 'package:payment_module/features/security_guard/di.dart';

import '../support/fakes/fake_payment_processor.dart';
import '../support/fakes/fake_payment_repository.dart';
import '../support/fakes/fake_secure_window.dart';
import '../support/fakes/fake_security_environment.dart';

void main() {
  late FakePaymentProcessor processor;
  late FakeSecurityEnvironment environment;

  setUp(() async {
    processor = FakePaymentProcessor();
    environment = FakeSecurityEnvironment();
    await GetIt.I.reset();
    // setupLocator would register the channel adapters; the page only needs the ports to exist,
    // so register fakes directly and keep this test off the platform.
    GetIt.I.registerSingleton<BrandConfig>(
      brandRegistry.byId(const BrandId('retail')),
    );
    registerSecurityModule(
      GetIt.I,
      environment: environment,
      window: FakeSecureWindow(),
    );
    registerPaymentModule(
      GetIt.I,
      repository: FakePaymentRepository(),
      processor: processor,
    );
  });

  tearDown(() async {
    await processor.dispose();
    await environment.dispose();
    await GetIt.I.reset();
  });

  testWidgets('builds the Brand theme and puts the Brand in scope above the page', (tester) async {
    final brand = brandRegistry.byId(const BrandId('retail'));
    await tester.pumpWidget(PaymentApp(brand: brand));
    await tester.pump();

    expect(find.byType(PaymentConfirmationPage), findsOneWidget);

    final context = tester.element(find.byType(PaymentConfirmationPage));
    expect(BrandScope.of(context), same(brand));
    expect(Theme.of(context).extension<BrandTokens>(), same(brand.tokens));
    expect(find.text('Retail Shop'), findsOneWidget); // the AppBar title
  });

  testWidgets('a different Brand themes and titles the same widget tree', (tester) async {
    final brand = brandRegistry.byId(const BrandId('utility'));
    GetIt.I.unregister<BrandConfig>();
    GetIt.I.registerSingleton<BrandConfig>(brand);

    await tester.pumpWidget(PaymentApp(brand: brand));
    await tester.pump();

    expect(find.text('Utility Pay'), findsOneWidget);
    final context = tester.element(find.byType(PaymentConfirmationPage));
    expect(Theme.of(context).visualDensity, VisualDensity.compact);
  });
}
