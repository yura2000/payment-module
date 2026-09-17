import '../../core/brand_id.dart';
import 'brand_config.dart';

/// Every Brand the binary knows, in declaration order. `bootstrap()` resolves the `BRAND`
/// dart-define through [byId]; the completeness guard iterates [all]. One instance lives in
/// `lib/brands/registry.dart` — `final`, not `const`, because the Brands it holds aren't
/// (see the Brands task). See docs/architecture.md §4, §6, §13.
class BrandRegistry {
  const BrandRegistry(this.all);

  final List<BrandConfig> all;

  Iterable<String> get ids => all.map((brand) => brand.id.value);

  /// Throws [StateError] naming the unknown id when nothing matches — a mistyped `BRAND`
  /// dart-define should fail loudly at startup, not fall back to some default Brand.
  BrandConfig byId(BrandId id) {
    for (final brand in all) {
      if (brand.id.value == id.value) return brand;
    }
    throw StateError('Unknown BRAND "${id.value}" — registered: ${ids.join(', ')}');
  }
}
