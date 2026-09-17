import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Visual and motion values a Brand supplies that ThemeData cannot express on its own. Delivered
/// to the widget tree as a ThemeExtension — read via `context.tokens`. See CONTEXT.md → Brand Token.
class BrandTokens extends ThemeExtension<BrandTokens> {
  const BrandTokens({
    required this.seed,
    required this.accent,
    required this.radius,
    required this.density,
    required this.spacing,
    required this.scanMinDuration,
    required this.headlineWeight,
  });

  final Color seed;
  final Color accent;
  final double radius;
  final VisualDensity density;
  final double spacing;
  final Duration scanMinDuration;

  /// Weight for the amount and other headline text — part of a Brand's voice, and not
  /// expressible through `ThemeData` alone without fixing the whole text theme.
  final FontWeight headlineWeight;

  bool get isDense => density == VisualDensity.compact;

  @override
  BrandTokens copyWith({
    Color? seed,
    Color? accent,
    double? radius,
    VisualDensity? density,
    double? spacing,
    Duration? scanMinDuration,
    FontWeight? headlineWeight,
  }) {
    return BrandTokens(
      seed: seed ?? this.seed,
      accent: accent ?? this.accent,
      radius: radius ?? this.radius,
      density: density ?? this.density,
      spacing: spacing ?? this.spacing,
      scanMinDuration: scanMinDuration ?? this.scanMinDuration,
      headlineWeight: headlineWeight ?? this.headlineWeight,
    );
  }

  @override
  BrandTokens lerp(ThemeExtension<BrandTokens>? other, double t) {
    if (other is! BrandTokens) return this;
    return BrandTokens(
      seed: Color.lerp(seed, other.seed, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      radius: lerpDouble(radius, other.radius, t)!,
      density: t < 0.5 ? density : other.density,
      spacing: lerpDouble(spacing, other.spacing, t)!,
      scanMinDuration: t < 0.5 ? scanMinDuration : other.scanMinDuration,
      headlineWeight: FontWeight.lerp(headlineWeight, other.headlineWeight, t)!,
    );
  }
}
