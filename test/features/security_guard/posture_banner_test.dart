import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

const _tokens = BrandTokens(
  seed: Color(0xFF0D2B4E),
  accent: Color(0xFF5C6B7A),
  radius: 4,
  density: VisualDensity.compact,
  spacing: 8,
  scanMinDuration: Duration(milliseconds: 1200),
  headlineWeight: FontWeight.w500,
);

Future<void> _pump(WidgetTester tester, PolicyVerdict? verdict) => tester.pumpWidget(
  MaterialApp(
    theme: ThemeData(extensions: const [_tokens]),
    home: Scaffold(body: PostureBanner(verdict: verdict)),
  ),
);

void main() {
  test('nothing to report is nothing to show', () {
    expect(
      const PolicyVerdict(blockers: {}, warnings: {}, notices: {}).hasAnything,
      isFalse,
    );
  });

  testWidgets('renders nothing before the first assessment', (tester) async {
    await _pump(tester, null);
    expect(find.byType(SizedBox), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('renders nothing for a clear verdict', (tester) async {
    await _pump(tester, const PolicyVerdict(blockers: {}, warnings: {}, notices: {}));
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('a blocker names the Threat and says the payment is blocked', (tester) async {
    await _pump(
      tester,
      const PolicyVerdict(
        blockers: {ThreatKind.rooted},
        warnings: {},
        notices: {},
      ),
    );

    expect(find.textContaining('blocked', findRichText: true), findsOneWidget);
    expect(find.textContaining('rooted', findRichText: true), findsOneWidget);
    expect(find.byIcon(Icons.gpp_bad), findsOneWidget);
  });

  testWidgets('a warning names the Threat without blocking', (tester) async {
    await _pump(
      tester,
      const PolicyVerdict(
        blockers: {},
        warnings: {ThreatKind.screenRecording},
        notices: {},
      ),
    );

    expect(find.textContaining('recording', findRichText: true), findsOneWidget);
    expect(find.textContaining('blocked', findRichText: true), findsNothing);
    expect(find.byIcon(Icons.warning_amber), findsOneWidget);
  });

  testWidgets('a notice says the check could not run, not that anything was found', (tester) async {
    await _pump(
      tester,
      const PolicyVerdict(
        blockers: {},
        warnings: {},
        notices: {ThreatKind.screenRecording},
      ),
    );

    expect(find.textContaining('could not', findRichText: true), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });

  testWidgets('a blocker wins over a warning and a notice', (tester) async {
    await _pump(
      tester,
      const PolicyVerdict(
        blockers: {ThreatKind.rooted},
        warnings: {ThreatKind.screenRecording},
        notices: {ThreatKind.screenRecording},
      ),
    );

    expect(find.byType(Card), findsOneWidget);
    expect(find.byIcon(Icons.gpp_bad), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsNothing);
  });
}
