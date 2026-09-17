import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/brand_id.dart';
import 'package:payment_module/main.dart';

void main() {
  test('resolves a known BRAND to its Brand', () {
    expect(resolveBrand('utility').id, const BrandId('utility'));
    expect(resolveBrand('retail').displayName, 'Retail Shop');
  });

  test('a missing BRAND fails loudly, naming how to pass it', () {
    expect(
      () => resolveBrand(''),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('BRAND'), contains('make run')),
        ),
      ),
    );
  });

  test('an unknown BRAND fails loudly, naming the registered Brands', () {
    expect(
      () => resolveBrand('acme'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('acme'), contains('retail'), contains('utility')),
        ),
      ),
    );
  });
}
