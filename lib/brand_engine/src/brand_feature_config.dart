/// Marker for per-feature brand configuration. Features define subclasses of this; the engine
/// never sees the concrete types — it looks them up by type. See docs/architecture.md §6.
abstract class BrandFeatureConfig {
  const BrandFeatureConfig();
}
