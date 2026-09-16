import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/brand_id.dart';

void main() {
  test('two BrandId values wrapping the same string are equal', () {
    expect(const BrandId('retail'), equals(const BrandId('retail')));
  });

  test('BrandId values wrapping different strings are not equal', () {
    expect(const BrandId('retail'), isNot(equals(const BrandId('utility'))));
  });

  test('BrandId.value exposes the wrapped string', () {
    expect(const BrandId('acme').value, 'acme');
  });
}
