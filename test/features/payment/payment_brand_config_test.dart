import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/features/payment/payment.dart';

void main() {
  test('is a BrandFeatureConfig, so feature<T>() can find it', () {
    const config = PaymentBrandConfig(
      ctaLabel: 'Pay now',
      sections: [SummarySection(), PayButtonSection()],
    );
    expect(config, isA<BrandFeatureConfig>());
  });

  test('carries the Brand copy and section order verbatim', () {
    const config = PaymentBrandConfig(
      ctaLabel: 'Confirm payment',
      sections: [SummarySection(), BillBreakdownSection(), PayButtonSection()],
    );

    expect(config.ctaLabel, 'Confirm payment');
    expect(config.sections, [
      isA<SummarySection>(),
      isA<BillBreakdownSection>(),
      isA<PayButtonSection>(),
    ]);
  });

  test('a CustomSection carries a builder and a non-empty debug label', () {
    final section = CustomSection(
      (context, payment) => const Text('brand-specific'),
      debugLabel: 'loyalty-points',
    );

    expect(section.debugLabel, 'loyalty-points');
    expect(section, isA<PaymentSection>());
  });

  test('the section hierarchy is exhaustively switchable', () {
    String name(PaymentSection section) => switch (section) {
      SummarySection() => 'summary',
      PromoBannerSection() => 'promo',
      BillBreakdownSection() => 'breakdown',
      PayButtonSection() => 'pay',
      CustomSection(:final debugLabel) => debugLabel,
    };

    expect(name(const SummarySection()), 'summary');
    expect(name(const PromoBannerSection()), 'promo');
    expect(name(const BillBreakdownSection()), 'breakdown');
    expect(name(const PayButtonSection()), 'pay');
    expect(
      name(CustomSection((_, _) => const SizedBox.shrink(), debugLabel: 'x')),
      'x',
    );
  });
}
