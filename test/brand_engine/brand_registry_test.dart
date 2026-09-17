import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/core/brand_id.dart';

const _tokens = BrandTokens(
  seed: Color(0xFFE65100),
  accent: Color(0xFFFFB300),
  radius: 20,
  density: VisualDensity.comfortable,
  spacing: 16,
  scanMinDuration: Duration(milliseconds: 2000),
  headlineWeight: FontWeight.w700,
  transitionDuration: Duration(milliseconds: 350),
);

const _first = BrandConfig(
  id: BrandId('first'),
  displayName: 'First',
  tokens: _tokens,
  features: [],
);
const _second = BrandConfig(
  id: BrandId('second'),
  displayName: 'Second',
  tokens: _tokens,
  features: [],
);

void main() {
  const registry = BrandRegistry([_first, _second]);

  test('all exposes the Brands in declaration order', () {
    expect(registry.all, [_first, _second]);
  });

  test('byId returns the Brand with that id', () {
    expect(registry.byId(const BrandId('second')), same(_second));
  });

  test('byId throws a StateError naming the unknown id and the known ones', () {
    expect(
      () => registry.byId(const BrandId('missing')),
      throwsA(
        isA<StateError>()
            .having((e) => e.message, 'message', contains('missing'))
            .having((e) => e.message, 'message', contains('first')),
      ),
    );
  });

  test('ids lists every registered id', () {
    expect(registry.ids, ['first', 'second']);
  });
}
