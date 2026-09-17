import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/core/money.dart';
import 'package:payment_module/features/payment/payment.dart';

const _tokens = BrandTokens(
  seed: Color(0xFFE65100),
  accent: Color(0xFFFFB300),
  radius: 20,
  density: VisualDensity.comfortable,
  spacing: 16,
  scanMinDuration: Duration(milliseconds: 2000),
  headlineWeight: FontWeight.w700,
);

const _payment = Payment(
  reference: 'PAY-DEMO-0001',
  amount: Money(amountMinor: 4200, currency: 'USD'),
  payee: 'Acme Utilities',
  lineItems: [
    LineItem(
      description: 'Monthly service',
      amount: Money(amountMinor: 3200, currency: 'USD'),
    ),
    LineItem(
      description: 'Usage overage',
      amount: Money(amountMinor: 1000, currency: 'USD'),
    ),
  ],
);

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: ThemeData(extensions: const [_tokens]),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  group('SummaryCard', () {
    testWidgets('shows the formatted amount, the payee and the reference', (
      tester,
    ) async {
      await _pump(tester, const SummaryCard(payment: _payment));

      expect(find.text(r'$42.00'), findsOneWidget);
      expect(find.textContaining('Acme Utilities'), findsOneWidget);
      expect(find.textContaining('PAY-DEMO-0001'), findsOneWidget);
    });

    testWidgets('renders the amount at the Brand headline weight', (
      tester,
    ) async {
      await _pump(tester, const SummaryCard(payment: _payment));

      final amount = tester.widget<Text>(find.text(r'$42.00'));
      expect(amount.style?.fontWeight, FontWeight.w700);
    });
  });

  group('BillBreakdown', () {
    testWidgets('lists every line item with its amount, plus a total', (
      tester,
    ) async {
      await _pump(tester, const BillBreakdown(payment: _payment));

      expect(find.text('Monthly service'), findsOneWidget);
      expect(find.text(r'$32.00'), findsOneWidget);
      expect(find.text('Usage overage'), findsOneWidget);
      expect(find.text(r'$10.00'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text(r'$42.00'), findsOneWidget);
    });
  });

  group('PromoBanner', () {
    testWidgets('renders promotional copy without touching the amount', (
      tester,
    ) async {
      await _pump(tester, const PromoBanner());

      expect(find.byIcon(Icons.local_offer), findsOneWidget);
      expect(find.textContaining(r'$'), findsNothing);
    });
  });

  group('PayButton', () {
    testWidgets('uses the Brand call-to-action copy and fires when enabled', (
      tester,
    ) async {
      var taps = 0;
      await _pump(
        tester,
        PayButton(label: 'Pay now', enabled: true, onPressed: () => taps++),
      );

      expect(find.text('Pay now'), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      expect(taps, 1);
    });

    testWidgets('is inert when disabled', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        PayButton(label: 'Pay now', enabled: false, onPressed: () => taps++),
      );

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets(
      'says it is still checking when the label is the checking one',
      (tester) async {
        await _pump(
          tester,
          const PayButton(label: 'Checking…', enabled: false, onPressed: null),
        );

        expect(find.text('Checking…'), findsOneWidget);
      },
    );
  });
}
