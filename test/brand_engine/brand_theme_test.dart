import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/core/brand_id.dart';

void main() {
  final brand = BrandConfig(
    id: const BrandId('test'),
    displayName: 'Test Brand',
    tokens: const BrandTokens(
      seed: Color(0xFF0D2B4E),
      accent: Color(0xFF5C6B7A),
      radius: 4,
      density: VisualDensity.compact,
      spacing: 8,
      scanMinDuration: Duration(milliseconds: 1200),
      headlineWeight: FontWeight.w700,
    ),
    features: const [],
  );

  test('buildBrandTheme carries the BrandTokens as a ThemeExtension', () {
    final theme = buildBrandTheme(brand);
    expect(theme.extension<BrandTokens>(), same(brand.tokens));
  });

  test('buildBrandTheme applies the token density', () {
    final theme = buildBrandTheme(brand);
    expect(theme.visualDensity, VisualDensity.compact);
  });

  testWidgets('context.tokens reads the BrandTokens from the nearest Theme', (
    tester,
  ) async {
    late BrandTokens read;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBrandTheme(brand),
        home: Builder(
          builder: (context) {
            read = context.tokens;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(read, same(brand.tokens));
  });
}
