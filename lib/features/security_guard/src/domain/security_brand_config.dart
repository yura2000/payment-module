import '../../../../brand_engine/brand_engine.dart';
import '../../../../core/threat.dart';

/// A Brand's slice of security configuration: its Posture Policy. See docs/architecture.md §6.
class SecurityBrandConfig extends BrandFeatureConfig {
  const SecurityBrandConfig({required this.policy});
  final PosturePolicy policy;
}
