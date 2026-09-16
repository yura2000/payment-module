import 'package:flutter/widgets.dart';

import 'brand_config.dart';

/// Exposes the active Brand's non-visual configuration to the widget tree. Visual tokens travel
/// through ThemeData/BrandTokens instead — see `buildBrandTheme` and `context.tokens`.
class BrandScope extends InheritedWidget {
  const BrandScope({super.key, required this.brand, required super.child});

  final BrandConfig brand;

  static BrandConfig of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<BrandScope>();
    assert(scope != null, 'No BrandScope found in context');
    return scope!.brand;
  }

  @override
  bool updateShouldNotify(BrandScope oldWidget) => oldWidget.brand != brand;
}
