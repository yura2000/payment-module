import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/core/brand_id.dart';

void main() {
  final brand = BrandConfig(
    id: const BrandId('test'),
    displayName: 'Test Brand',
    tokens: const BrandTokens(
      seed: Colors.blue,
      accent: Colors.orange,
      radius: 8,
      density: VisualDensity.standard,
      spacing: 12,
      scanMinDuration: Duration(milliseconds: 1500),
    ),
    features: const [],
  );

  testWidgets('BrandScope.of returns the brand passed to the nearest ancestor scope', (tester) async {
    late BrandConfig read;
    await tester.pumpWidget(
      BrandScope(
        brand: brand,
        child: Builder(
          builder: (context) {
            read = BrandScope.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(read, same(brand));
  });
}
