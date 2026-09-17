import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/payment/payment.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

const _tokens = BrandTokens(
  seed: Color(0xFFE65100),
  accent: Color(0xFFFFB300),
  radius: 20,
  density: VisualDensity.comfortable,
  spacing: 16,
  scanMinDuration: Duration(milliseconds: 2000),
  headlineWeight: FontWeight.w700,
);

final _receipt = PaymentReceipt(
  reference: 'PAY-DEMO-0001',
  completedAt: DateTime.utc(2026, 9, 17, 8, 30),
);

Future<void> _pump(
  WidgetTester tester, {
  required PaymentJobProgress outcome,
  PolicyVerdict? verdict,
  VoidCallback? onRetry,
}) => tester.pumpWidget(
  MaterialApp(
    theme: ThemeData(extensions: const [_tokens]),
    home: Scaffold(
      body: SingleChildScrollView(
        child: ResultView(
          outcome: outcome,
          verdict: verdict,
          onRetry: onRetry ?? () {},
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('a success shows the receipt reference and offers no retry', (
    tester,
  ) async {
    await _pump(tester, outcome: Succeeded(_receipt));

    expect(find.textContaining('complete'), findsOneWidget);
    expect(find.textContaining('PAY-DEMO-0001'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a declined payment says so and offers retry', (tester) async {
    var retries = 0;
    await _pump(
      tester,
      outcome: const Failed(PaymentFailure.declined),
      onRetry: () => retries++,
    );

    // Both the headline ("Payment declined") and the detail text mention "declined" — that
    // redundancy is intentional plan copy, not a bug.
    expect(find.textContaining('declined'), findsWidgets);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
  });

  testWidgets(
    'a timeout and an unavailable processor each get their own wording',
    (tester) async {
      await _pump(tester, outcome: const Failed(PaymentFailure.timedOut));
      expect(find.textContaining('took too long'), findsOneWidget);

      await _pump(
        tester,
        outcome: const Failed(PaymentFailure.serviceUnavailable),
      );
      expect(find.textContaining('could not be reached'), findsOneWidget);
    },
  );

  testWidgets('a posture caveat rides along with a success', (tester) async {
    await _pump(
      tester,
      outcome: Succeeded(_receipt),
      verdict: const PolicyVerdict(
        blockers: {},
        warnings: {ThreatKind.screenRecording},
        notices: {},
      ),
    );

    expect(find.byType(PostureBanner), findsOneWidget);
    expect(find.textContaining('recording'), findsOneWidget);
    expect(find.textContaining('complete'), findsOneWidget);
  });

  testWidgets('no caveat renders when the verdict is clear', (tester) async {
    await _pump(
      tester,
      outcome: Succeeded(_receipt),
      verdict: const PolicyVerdict(blockers: {}, warnings: {}, notices: {}),
    );

    expect(find.byType(Card), findsOneWidget); // the result card only
  });
}
