import 'package:flutter/material.dart';

import '../brand_engine/brand_engine.dart';
import '../core/brand_id.dart';
import '../core/threat.dart';
import '../features/payment/payment.dart';
import '../features/security_guard/security_guard.dart';

/// "Brand B (Utility Pay)": navy/slate, dense, sharp, shows the Bill Breakdown, blocks on either
/// Threat and asks for a notice when a check could not run. Values from docs/architecture.md §6.
final utilityBrand = BrandConfig(
  id: const BrandId('utility'),
  displayName: 'Utility Pay',
  tokens: const BrandTokens(
    seed: Color(0xFF0D2B4E),
    accent: Color(0xFF5C6B7A),
    radius: 4,
    density: VisualDensity.compact,
    spacing: 8,
    scanMinDuration: Duration(milliseconds: 1200),
    headlineWeight: FontWeight.w500,
  ),
  features: [
    const PaymentBrandConfig(
      ctaLabel: 'Confirm payment',
      sections: [SummarySection(), BillBreakdownSection(), PayButtonSection()],
    ),
    SecurityBrandConfig(
      policy: PosturePolicy(
        onDetected: {
          ThreatKind.rooted: DetectedResponse.block,
          ThreatKind.screenRecording: DetectedResponse.block,
        },
        onUnavailable: {
          ThreatKind.rooted: UnavailableResponse.notice,
          ThreatKind.screenRecording: UnavailableResponse.notice,
        },
      ),
    ),
  ],
);
