import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/core/brand_id.dart';

class _FakeFeatureA extends BrandFeatureConfig {
  const _FakeFeatureA(this.value);
  final String value;
}

class _FakeFeatureB extends BrandFeatureConfig {
  const _FakeFeatureB();
}

BrandConfig _brand(List<BrandFeatureConfig> features) => BrandConfig(
  id: const BrandId('test'),
  displayName: 'Test Brand',
  tokens: const BrandTokens(
    seed: Colors.blue,
    accent: Colors.orange,
    radius: 8,
    density: VisualDensity.standard,
    spacing: 12,
    scanMinDuration: Duration(milliseconds: 1500),
    headlineWeight: FontWeight.w700,
    transitionDuration: Duration(milliseconds: 350),
  ),
  features: features,
);

void main() {
  group('BrandConfig.feature<T>()', () {
    test('returns the single config of the requested type', () {
      final brand = _brand([const _FakeFeatureA('x'), const _FakeFeatureB()]);
      expect(brand.feature<_FakeFeatureA>().value, 'x');
      expect(brand.feature<_FakeFeatureB>(), isA<_FakeFeatureB>());
    });

    test(
      'throws StateError when no config of the requested type is present',
      () {
        final brand = _brand([const _FakeFeatureB()]);
        expect(() => brand.feature<_FakeFeatureA>(), throwsStateError);
      },
    );

    test(
      'throws when more than one config of the requested type is present',
      () {
        final brand = _brand([
          const _FakeFeatureA('x'),
          const _FakeFeatureA('y'),
        ]);
        expect(() => brand.feature<_FakeFeatureA>(), throwsStateError);
      },
    );
  });
}
