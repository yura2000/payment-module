import 'dart:developer';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:payment_module/bootstrap/channel_app_info.dart';
import 'package:payment_module/bootstrap/channel_display_mode.dart';
import 'package:payment_module/core/money.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/payment/di.dart';
import 'package:payment_module/features/payment/payment.dart';
import 'package:payment_module/features/security_guard/di.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

/// On-device smoke test of the real Kotlin bridge: every channel of docs/architecture.md §9, end to
/// end. Not part of `flutter test`, which only runs test/. `flutter test` uninstalls the app when
/// it finishes, so install and pre-grant POST_NOTIFICATIONS before every run — otherwise the job
/// waits on the system permission prompt:
///
///     flutter build apk --debug --flavor retail
///     adb install -r build/app/outputs/flutter-apk/app-retail-debug.apk
///     adb shell pm grant dev.test.payment.retail android.permission.POST_NOTIFICATIONS
///     flutter test integration_test/native_bridge_test.dart --flavor retail -d <device-id>
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final getIt = GetIt.instance;

  setUpAll(() {
    registerSecurityModule(getIt);
    registerPaymentModule(getIt);
  });

  Payment payment(int amountMinor) => Payment(
    reference: 'PAY-IT-$amountMinor',
    amount: Money(amountMinor: amountMinor, currency: 'USD'),
    payee: 'Integration Test',
    lineItems: const [],
  );

  testWidgets('app · buildInfo reports the retail flavor', (tester) async {
    final info = await ChannelAppInfo().buildInfo();

    expect(info.flavor, 'retail');
    expect(info.applicationId, 'dev.test.payment.retail');
    expect(info.sdkInt, greaterThanOrEqualTo(26));
  });

  testWidgets('window · preferHighRefreshRate names a mode', (tester) async {
    final preference = await ChannelDisplayMode().preferHighRefreshRate();
    log('preferHighRefreshRate: $preference', name: 'native_bridge_test');

    expect(preference!.refreshRate, greaterThan(0));
  });

  testWidgets('window · setSecure sets and clears the flag', (tester) async {
    await getIt<SecureWindow>().setSecure(true);
    await getIt<SecureWindow>().setSecure(false);
  });

  testWidgets('security.environment publishes one assessment per threat', (
    tester,
  ) async {
    final environment = getIt<SecurityEnvironment>();
    final firstPosture = environment.posture.first;
    await environment.assess();

    final posture = await firstPosture.timeout(const Duration(seconds: 10));
    log(
      'posture: ${posture.classification} $posture',
      name: 'native_bridge_test',
    );

    expect(
      posture.assessments.map((a) => a.kind).toSet(),
      ThreatKind.values.toSet(),
    );
  });

  testWidgets('payment.job runs an approved payment to Succeeded', (
    tester,
  ) async {
    final processor = getIt<PaymentProcessor>();

    final progress = await processor
        .start(payment(4200))
        .toList()
        .timeout(const Duration(seconds: 20));

    expect(progress.first, isA<Running>());
    expect(
      progress.whereType<Running>().map((r) => r.percent),
      everyElement(lessThan(100)),
    );
    expect(
      progress.last,
      isA<Succeeded>().having(
        (s) => s.receipt.reference,
        'reference',
        'PAY-IT-4200',
      ),
    );
    // The terminal snapshot was delivered on the stream, so nothing is left in flight.
    expect(await processor.inFlight(), isNull);
  });

  testWidgets('payment.job declines an amount ending in 99 at 60 %', (
    tester,
  ) async {
    final processor = getIt<PaymentProcessor>();

    final progress = await processor
        .start(payment(4299))
        .toList()
        .timeout(const Duration(seconds: 20));

    expect(progress.last, const Failed(PaymentFailure.declined));
    expect(
      progress.whereType<Running>().map((r) => r.percent),
      everyElement(lessThan(60)),
    );
  });

  testWidgets('payment.job re-attaches to a running job through current', (
    tester,
  ) async {
    final processor = getIt<PaymentProcessor>();
    final started = processor.start(payment(4200));
    // Take the first snapshot only, then let go of the stream — as a disposed engine would.
    expect(await started.first, isA<Running>());

    final inFlight = await processor.inFlight();

    expect(inFlight, isNotNull);
    final rest = await inFlight!.toList().timeout(const Duration(seconds: 20));
    expect(rest.last, isA<Succeeded>());
  });
}
