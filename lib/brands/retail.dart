import 'package:flutter/material.dart';

import '../brand_engine/brand_engine.dart';
import '../core/brand_id.dart';
import '../core/threat.dart';
import '../features/payment/payment.dart';
import '../features/security_guard/security_guard.dart';

/// "Brand A (Retail Shop)": warm palette, rounded, fluid, shows the Promo Banner, and warns
/// rather than blocks on an active screen recorder. Values from docs/architecture.md §6.
///
/// `final`, not `const`: `PosturePolicy` cannot be a constant (it copies its maps unmodifiable
/// and asserts ThreatKind coverage), so nothing containing one can be either.
final retailBrand = BrandConfig(
  id: const BrandId('retail'),
  displayName: 'Retail Shop',
  tokens: const BrandTokens(
    seed: Color(0xFFE65100),
    accent: Color(0xFFFFB300),
    radius: 20,
    density: VisualDensity.comfortable,
    spacing: 16,
    scanMinDuration: Duration(milliseconds: 2000),
    headlineWeight: FontWeight.w700,
    transitionDuration: Duration(milliseconds: 350),
  ),
  features: [
    const PaymentBrandConfig(
      ctaLabel: 'Pay now',
      sections: [PromoBannerSection(), SummarySection(), PayButtonSection()],
    ),
    SecurityBrandConfig(
      policy: PosturePolicy(
        onDetected: {
          ThreatKind.rooted: DetectedResponse.block,
          ThreatKind.screenRecording: DetectedResponse.warn,
        },
        onUnavailable: {
          ThreatKind.rooted: UnavailableResponse.allow,
          ThreatKind.screenRecording: UnavailableResponse.allow,
        },
      ),
    ),
  ],
);
