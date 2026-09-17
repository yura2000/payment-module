import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/core/brand_id.dart';
import 'package:payment_module/core/money.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/payment/di.dart';
import 'package:payment_module/features/payment/payment.dart';
import 'package:payment_module/features/security_guard/di.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

import '../../support/fakes/fake_payment_processor.dart';
import '../../support/fakes/fake_payment_repository.dart';
import '../../support/fakes/fake_secure_window.dart';
import '../../support/fakes/fake_security_environment.dart';

const _scanDuration = Duration(milliseconds: 20);
const _transitionDuration = Duration(milliseconds: 350);
// A phase-change assertion needs to pump *past* the cross-fade, not exactly to it — the
// AnimatedSwitcher's outgoing entry only flips to "dismissed" (and gets removed) on the tick that
// crosses its duration, not the one that lands exactly on it.
const _settlePastTransition = Duration(milliseconds: 400);

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

final _clearPosture = SecurityPosture(const [
  ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
  ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
]);

final _rootedPosture = SecurityPosture(const [
  ThreatAssessment(kind: ThreatKind.rooted, result: Detected()),
  ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
]);

PosturePolicy _blockingPolicy() => PosturePolicy(
  onDetected: {
    ThreatKind.rooted: DetectedResponse.block,
    ThreatKind.screenRecording: DetectedResponse.warn,
  },
  onUnavailable: {
    ThreatKind.rooted: UnavailableResponse.allow,
    ThreatKind.screenRecording: UnavailableResponse.allow,
  },
);

BrandConfig _brand({
  List<PaymentSection> sections = const [
    PromoBannerSection(),
    SummarySection(),
    PayButtonSection(),
  ],
  String ctaLabel = 'Pay now',
  Duration transitionDuration = _transitionDuration,
}) => BrandConfig(
  id: const BrandId('test'),
  displayName: 'Test Brand',
  tokens: BrandTokens(
    seed: const Color(0xFFE65100),
    accent: const Color(0xFFFFB300),
    radius: 20,
    density: VisualDensity.comfortable,
    spacing: 16,
    scanMinDuration: _scanDuration,
    headlineWeight: FontWeight.w700,
    transitionDuration: transitionDuration,
  ),
  features: [
    PaymentBrandConfig(ctaLabel: ctaLabel, sections: sections),
    SecurityBrandConfig(policy: _blockingPolicy()),
  ],
);

void main() {
  late FakePaymentRepository repository;
  late FakePaymentProcessor processor;
  late FakeSecurityEnvironment environment;
  late FakeSecureWindow window;

  setUp(() async {
    repository = FakePaymentRepository();
    processor = FakePaymentProcessor();
    environment = FakeSecurityEnvironment();
    window = FakeSecureWindow();

    await GetIt.I.reset();
    registerSecurityModule(GetIt.I, environment: environment, window: window);
    registerPaymentModule(
      GetIt.I,
      repository: repository,
      processor: processor,
    );
  });

  tearDown(() async {
    await processor.dispose();
    await environment.dispose();
    await GetIt.I.reset();
  });

  Future<void> pumpPage(WidgetTester tester, {BrandConfig? brand}) async {
    final config = brand ?? _brand();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBrandTheme(config),
        home: BrandScope(brand: config, child: const PaymentConfirmationPage()),
      ),
    );
    await tester.pump();
  }

  /// Gets past the Scan phase: resolve the load, let the real scan timer elapse, then push the
  /// posture. `SecurityPostureCubit` is a lazily-created `BlocProvider` that nothing reads until
  /// a widget built in the AwaitingConfirmation phase (`_PostureBannerSlot`/`_PayButtonSlot`)
  /// first builds — so pushing the posture any earlier lands on a broadcast stream nobody has
  /// subscribed to yet, and it is silently dropped.
  Future<void> reachAwaitingConfirmation(
    WidgetTester tester, {
    SecurityPosture? posture,
  }) async {
    repository.completeWith(_payment);
    await tester.pump(_scanDuration * 2);
    await tester.pump();
    // Lets the Scanning → AwaitingConfirmation cross-fade finish, so the Scan phase's content is
    // actually gone rather than still fading out underneath.
    await tester.pump(_settlePastTransition);
    await tester.pump();
    environment.pushPosture(posture ?? _clearPosture);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('opens on the Scan phase with the scan animating', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.byType(SecurityScanView), findsOneWidget);
    expect(find.byType(PayButton), findsNothing);
  });

  testWidgets('cross-fades between phases at the Brand transitionDuration', (
    tester,
  ) async {
    await pumpPage(
      tester,
      brand: _brand(transitionDuration: const Duration(milliseconds: 90)),
    );

    final switcher = tester.widget<AnimatedSwitcher>(
      find.byType(AnimatedSwitcher),
    );
    expect(switcher.duration, const Duration(milliseconds: 90));
  });

  testWidgets(
    'the outgoing phase is still in the tree mid-transition, and gone once it settles',
    (tester) async {
      await pumpPage(tester);
      repository.completeWith(_payment);
      await tester.pump(_scanDuration * 2);
      await tester.pump(); // the phase switches; the cross-fade just started

      expect(find.byType(SecurityScanView), findsOneWidget);

      await tester.pump(_settlePastTransition);
      await tester
          .pump(); // flushes the AnimatedSwitcher's own post-fade cleanup
      expect(find.byType(SecurityScanView), findsNothing);
    },
  );

  testWidgets(
    'holds the Secure Window while mounted and releases it on dispose',
    (tester) async {
      await pumpPage(tester);
      expect(window.calls, [true]);

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      expect(window.calls, [true, false]);
    },
  );

  testWidgets(
    'renders the Brand sections in the Brand order once confirmation is awaited',
    (tester) async {
      await pumpPage(tester);
      await reachAwaitingConfirmation(tester);

      expect(find.byType(SecurityScanView), findsNothing);

      final promo = tester.getTopLeft(find.byType(PromoBanner)).dy;
      final summary = tester.getTopLeft(find.byType(SummaryCard)).dy;
      final pay = tester.getTopLeft(find.byType(PayButton)).dy;
      expect(promo, lessThan(summary));
      expect(summary, lessThan(pay));
    },
  );

  testWidgets(
    'a different Brand order renders in that order, with no code change',
    (tester) async {
      await pumpPage(
        tester,
        brand: _brand(
          ctaLabel: 'Confirm payment',
          sections: const [
            SummarySection(),
            BillBreakdownSection(),
            PayButtonSection(),
          ],
        ),
      );
      await reachAwaitingConfirmation(tester);

      expect(find.byType(PromoBanner), findsNothing);
      expect(find.byType(BillBreakdown), findsOneWidget);
      expect(find.text('Confirm payment'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(SummaryCard)).dy,
        lessThan(tester.getTopLeft(find.byType(BillBreakdown)).dy),
      );
    },
  );

  testWidgets('renders a CustomSection a Brand supplies, unchanged', (
    tester,
  ) async {
    await pumpPage(
      tester,
      brand: _brand(
        sections: [
          const SummarySection(),
          CustomSection(
            (context, payment) => Text('loyalty ${payment.reference}'),
            debugLabel: 'loyalty',
          ),
          const PayButtonSection(),
        ],
      ),
    );
    await reachAwaitingConfirmation(tester);

    expect(find.text('loyalty PAY-DEMO-0001'), findsOneWidget);
  });

  testWidgets('the CTA says it is checking until the first assessment lands', (
    tester,
  ) async {
    await pumpPage(tester);
    repository.completeWith(_payment);
    await tester.pump(_scanDuration * 2);
    await tester.pump();

    expect(find.text('Checking…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets(
    'a clear posture enables the CTA, and tapping it starts the Payment Job',
    (tester) async {
      await pumpPage(tester);
      await reachAwaitingConfirmation(tester);

      expect(find.text('Pay now'), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(processor.startCallCount, 1);
      expect(processor.lastStartedPayment, _payment);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    },
  );

  testWidgets('a blocking posture shows the banner and keeps the CTA inert', (
    tester,
  ) async {
    await pumpPage(tester);
    await reachAwaitingConfirmation(tester, posture: _rootedPosture);

    expect(find.byType(PostureBanner), findsOneWidget);
    expect(find.textContaining('blocked'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    expect(processor.startCallCount, 0);
  });

  testWidgets('progress updates while processing, and back is blocked', (
    tester,
  ) async {
    await pumpPage(tester);
    await reachAwaitingConfirmation(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    processor.pushProgress(const Running(40));
    await tester.pump();

    expect(find.textContaining('40%'), findsOneWidget);
    // Flutter 3.44 instantiates the page's PopScope as PopScope<dynamic>, not PopScope<Object?>
    // — the plan itself calls this out as a plausible SDK-version difference to fix in the test.
    expect(
      tester.widget<PopScope<dynamic>>(find.byType(PopScope<dynamic>)).canPop,
      isFalse,
    );
  });

  testWidgets('a succeeded job shows the receipt and no retry', (tester) async {
    await pumpPage(tester);
    await reachAwaitingConfirmation(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    processor.pushProgress(
      Succeeded(
        PaymentReceipt(
          reference: 'PAY-DEMO-0001',
          completedAt: DateTime.utc(2026, 9, 17, 8, 30),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ResultView), findsOneWidget);
    expect(find.textContaining('complete'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a failed job offers retry, which returns to awaiting confirmation', (
    tester,
  ) async {
    await pumpPage(tester);
    await reachAwaitingConfirmation(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    processor.pushProgress(const Failed(PaymentFailure.declined));
    await tester.pump();
    // Both ResultView's headline ("Payment declined") and its detail text mention "declined" —
    // that redundancy is intentional plan copy, not a bug (see Task 8's ResultView fix).
    expect(find.textContaining('declined'), findsWidgets);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    // Lets the Completed → AwaitingConfirmation cross-fade finish, so ResultView is actually gone
    // rather than still fading out underneath.
    await tester.pump(_settlePastTransition);
    await tester.pump();

    expect(find.byType(ResultView), findsNothing);
    expect(find.text('Pay now'), findsOneWidget);
  });

  testWidgets(
    'a posture that degrades while the job runs does not stop it, and shows as a caveat',
    (tester) async {
      await pumpPage(tester);
      await reachAwaitingConfirmation(tester);
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      // Degrade mid-job: the flow bloc never subscribed to posture, so nothing interrupts it (§7).
      // Two pumps: one delivers the broadcast-stream posture event and emits the cubit's new
      // state, the next actually rebuilds the widget that reads it (see reachAwaitingConfirmation).
      environment.pushPosture(
        SecurityPosture(const [
          ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
          ThreatAssessment(
            kind: ThreatKind.screenRecording,
            result: Detected(),
          ),
        ]),
      );
      await tester.pump();
      await tester.pump();
      processor.pushProgress(
        Succeeded(
          PaymentReceipt(
            reference: 'PAY-DEMO-0001',
            completedAt: DateTime.utc(2026, 9, 17, 8, 30),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      // Lets the Processing → Completed cross-fade finish — otherwise the outgoing Processing
      // phase's own PostureBanner is still in the tree alongside ResultView's, and "recording"
      // matches twice.
      await tester.pump(_settlePastTransition);
      await tester.pump();

      expect(find.textContaining('complete'), findsOneWidget);
      expect(find.textContaining('recording'), findsOneWidget);
    },
  );

  testWidgets('returning to the screen re-runs the one-shot checks', (
    tester,
  ) async {
    await pumpPage(tester);
    await reachAwaitingConfirmation(tester);
    final before = environment.assessCallCount;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(environment.assessCallCount, greaterThan(before));
  });
}
