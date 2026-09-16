import '../../core/brand_id.dart';
import 'brand_feature_config.dart';
import 'brand_tokens.dart';

/// A white-label identity: palette, shape, density, motion, copy and per-feature configuration.
/// The unit the whole UI is configured by. One `const BrandConfig` per Brand, defined in
/// `lib/brands/`. See CONTEXT.md → Brand.
class BrandConfig {
  const BrandConfig({
    required this.id,
    required this.displayName,
    required this.tokens,
    required this.features,
  });

  final BrandId id;
  final String displayName;
  final BrandTokens tokens;
  final List<BrandFeatureConfig> features;

  /// Type-keyed lookup — the ThemeExtension pattern applied to configuration. Throws
  /// [StateError] if no config of type [T], or more than one, is present.
  T feature<T extends BrandFeatureConfig>() {
    final matches = features.whereType<T>();
    if (matches.isEmpty) {
      throw StateError('No $T registered for Brand "${id.value}"');
    }
    return matches.single;
  }
}
