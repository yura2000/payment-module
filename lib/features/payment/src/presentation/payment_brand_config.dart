import 'package:flutter/widgets.dart';

import '../../../../brand_engine/brand_engine.dart';
import '../domain/payment.dart';

/// Builds a Brand-supplied section. `payment` calls it and renders whatever comes back without
/// knowing what it is.
typedef SectionBuilder = Widget Function(BuildContext context, Payment payment);

/// A building block of the payment screen that a Brand orders. Sealed so the page's switch stays
/// exhaustive over everything `payment` knows how to draw, with [CustomSection] as the escape
/// hatch for content `payment` has never heard of. See CONTEXT.md → Section,
/// docs/architecture.md §6 (a closed enum and fixed slots were both rejected there).
sealed class PaymentSection {
  const PaymentSection();
}

final class SummarySection extends PaymentSection {
  const SummarySection();
}

final class PromoBannerSection extends PaymentSection {
  const PromoBannerSection();
}

final class BillBreakdownSection extends PaymentSection {
  const BillBreakdownSection();
}

final class PayButtonSection extends PaymentSection {
  const PayButtonSection();
}

/// Brand-supplied; `payment` renders it blind. [debugLabel] exists so the completeness guard and
/// any error message can name the section without calling the builder.
final class CustomSection extends PaymentSection {
  const CustomSection(this.builder, {required this.debugLabel});

  final SectionBuilder builder;
  final String debugLabel;
}

/// A Brand's slice of payment configuration: its call-to-action copy and the order of its
/// Sections. Looked up with `BrandConfig.feature<PaymentBrandConfig>()`. See
/// docs/architecture.md §6.
class PaymentBrandConfig extends BrandFeatureConfig {
  const PaymentBrandConfig({required this.ctaLabel, required this.sections});

  final String ctaLabel;
  final List<PaymentSection> sections;
}
