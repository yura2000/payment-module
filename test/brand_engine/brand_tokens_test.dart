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
}
