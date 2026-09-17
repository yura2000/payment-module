import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/brands/registry.dart';
import 'package:payment_module/core/brand_id.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/payment/payment.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

void main() {
  test('the registry is not empty', () {
    expect(brandRegistry.all, isNotEmpty);
  });

  test('ids are unique', () {
    final ids = brandRegistry.ids.toList();
    expect(ids.toSet(), hasLength(ids.length));
  });

  for (final brand in brandRegistry.all) {
    group('Brand "${brand.id.value}"', () {
      test('id is a lower-case slug', () {
        expect(brand.id.value, matches(RegExp(r'^[a-z][a-z0-9]*$')));
      });

      test('displayName is non-empty', () {
        expect(brand.displayName.trim(), isNotEmpty);
      });

      test('resolves a PaymentBrandConfig with non-empty CTA copy', () {
        final config = brand.feature<PaymentBrandConfig>();
        expect(config.ctaLabel.trim(), isNotEmpty);
      });

      test('has exactly one SummarySection and one PayButtonSection', () {
        final sections = brand.feature<PaymentBrandConfig>().sections;
        expect(sections.whereType<SummarySection>(), hasLength(1));
        expect(sections.whereType<PayButtonSection>(), hasLength(1));
      });

      test('every CustomSection carries a non-empty debugLabel', () {
        final sections = brand.feature<PaymentBrandConfig>().sections;
        for (final custom in sections.whereType<CustomSection>()) {
          expect(custom.debugLabel.trim(), isNotEmpty);
        }
      });

      test('resolves a SecurityBrandConfig whose policy covers every ThreatKind', () {
        final policy = brand.feature<SecurityBrandConfig>().policy;
        for (final kind in ThreatKind.values) {
          expect(policy.onDetected, contains(kind));
          expect(policy.onUnavailable, contains(kind));
        }
      });

      test('builds a theme that carries its BrandTokens', () {
        final theme = buildBrandTheme(brand);
        expect(theme.extension<BrandTokens>(), same(brand.tokens));
      });

      test('is reachable through byId', () {
        expect(brandRegistry.byId(brand.id), same(brand));
      });
    });
  }

  test('Retail and Utility are both registered', () {
    expect(brandRegistry.ids, containsAll(['retail', 'utility']));
  });

  test('the two Brands differ in more than identity — tokens are the whole difference', () {
    final retail = brandRegistry.byId(const BrandId('retail'));
    final utility = brandRegistry.byId(const BrandId('utility'));

    expect(retail.tokens.seed, isNot(utility.tokens.seed));
    expect(retail.tokens.radius, isNot(utility.tokens.radius));
    expect(retail.tokens.scanMinDuration, isNot(utility.tokens.scanMinDuration));
    expect(
      retail.feature<PaymentBrandConfig>().ctaLabel,
      isNot(utility.feature<PaymentBrandConfig>().ctaLabel),
    );
  });
}
