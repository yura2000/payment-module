import 'package:flutter/material.dart';

import 'brand_config.dart';
import 'brand_tokens.dart';

ThemeData buildBrandTheme(BrandConfig brand) {
  final tokens = brand.tokens;
  final colorScheme = ColorScheme.fromSeed(seedColor: tokens.seed).copyWith(secondary: tokens.accent);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens.radius));
  return ThemeData(
    colorScheme: colorScheme,
    visualDensity: tokens.density,
    cardTheme: CardThemeData(shape: shape, margin: EdgeInsets.zero),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: shape,
        padding: EdgeInsets.symmetric(horizontal: tokens.spacing * 1.5, vertical: tokens.spacing),
      ),
    ),
    extensions: [tokens],
  );
}

extension BrandTokensX on BuildContext {
  BrandTokens get tokens => Theme.of(this).extension<BrandTokens>()!;
}
