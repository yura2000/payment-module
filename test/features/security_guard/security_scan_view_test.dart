import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

const _retailTokens = BrandTokens(
  seed: Color(0xFFE65100),
  accent: Color(0xFFFFB300),
  radius: 20,
  density: VisualDensity.comfortable,
  spacing: 16,
  scanMinDuration: Duration(milliseconds: 2000),
  headlineWeight: FontWeight.w700,
);

const _utilityTokens = BrandTokens(
  seed: Color(0xFF0D2B4E),
  accent: Color(0xFF5C6B7A),
  radius: 4,
  density: VisualDensity.compact,
  spacing: 8,
  scanMinDuration: Duration(milliseconds: 1200),
  headlineWeight: FontWeight.w500,
);

Widget _host(BrandTokens tokens, {bool disableAnimations = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: disableAnimations),
  child: MaterialApp(
    theme: ThemeData(extensions: [tokens]),
    home: const Scaffold(body: Center(child: SecurityScanView())),
  ),
);

void main() {
  testWidgets('wraps its CustomPaint in a RepaintBoundary', (tester) async {
    await tester.pumpWidget(_host(_retailTokens));

    final boundary = find.ancestor(
      of: find.byType(CustomPaint).last,
      matching: find.byType(RepaintBoundary),
    );
    expect(boundary, findsWidgets);
  });

  testWidgets('one animation cycle lasts the Brand scanMinDuration', (tester) async {
    await tester.pumpWidget(_host(_utilityTokens));

    final state = tester.state<SecurityScanViewState>(find.byType(SecurityScanView));
    expect(state.controller.duration, const Duration(milliseconds: 1200));
    expect(state.controller.isAnimating, isTrue);
  });

  testWidgets('re-reads the duration when the Brand tokens change', (tester) async {
    await tester.pumpWidget(_host(_retailTokens));
    await tester.pumpWidget(_host(_utilityTokens));

    final state = tester.state<SecurityScanViewState>(find.byType(SecurityScanView));
    expect(state.controller.duration, const Duration(milliseconds: 1200));
  });

  testWidgets('holds a fixed phase instead of animating when animations are disabled', (tester) async {
    await tester.pumpWidget(_host(_retailTokens, disableAnimations: true));

    final state = tester.state<SecurityScanViewState>(find.byType(SecurityScanView));
    expect(state.controller.isAnimating, isFalse);
    expect(state.controller.value, 0.25);
  });

  testWidgets('renders at the size it was given', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [_retailTokens]),
        home: const Scaffold(
          body: Center(child: SecurityScanView(size: Size(120, 90))),
        ),
      ),
    );

    expect(tester.getSize(find.byType(SecurityScanView)), const Size(120, 90));
  });
}
