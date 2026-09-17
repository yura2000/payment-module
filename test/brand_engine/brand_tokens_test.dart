import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';

void main() {
  const tokens = BrandTokens(
    seed: Color(0xFFE65100),
    accent: Color(0xFFFFB300),
    radius: 20,
    density: VisualDensity.comfortable,
    spacing: 16,
    scanMinDuration: Duration(milliseconds: 2000),
    headlineWeight: FontWeight.w700,
  );

  test('isDense is true only for VisualDensity.compact', () {
    expect(tokens.isDense, isFalse);
    final dense = tokens.copyWith(density: VisualDensity.compact);
    expect(dense.isDense, isTrue);
  });

  test('copyWith overrides only the given fields', () {
    final copy = tokens.copyWith(radius: 4);
    expect(copy.radius, 4);
    expect(copy.seed, tokens.seed);
    expect(copy.scanMinDuration, tokens.scanMinDuration);
  });

  group('headlineWeight', () {
    const base = BrandTokens(
      seed: Color(0xFFE65100),
      accent: Color(0xFFFFB300),
      radius: 20,
      density: VisualDensity.comfortable,
      spacing: 16,
      scanMinDuration: Duration(milliseconds: 2000),
      headlineWeight: FontWeight.w700,
    );

    test(
      'copyWith replaces headlineWeight and preserves it when not given',
      () {
        expect(
          base.copyWith(headlineWeight: FontWeight.w500).headlineWeight,
          FontWeight.w500,
        );
        expect(base.copyWith(radius: 4).headlineWeight, FontWeight.w700);
      },
    );

    test('lerp interpolates headlineWeight towards the other tokens', () {
      final other = base.copyWith(headlineWeight: FontWeight.w300);
      expect(base.lerp(other, 0).headlineWeight, FontWeight.w700);
      expect(base.lerp(other, 1).headlineWeight, FontWeight.w300);
    });
  });
}
