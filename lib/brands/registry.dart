import '../brand_engine/brand_engine.dart';
import 'retail.dart';
import 'utility.dart';

/// Every Brand this binary ships. Adding a Brand is one file plus one line here plus one Gradle
/// flavor — docs/architecture.md §13.
final brandRegistry = BrandRegistry([retailBrand, utilityBrand]);
