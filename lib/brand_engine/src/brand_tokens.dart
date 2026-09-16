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
  });

  final Color seed;
  final Color accent;
  final double radius;
  final VisualDensity density;
  final double spacing;
  final Duration scanMinDuration;

  bool get isDense => density == VisualDensity.compact;

  @override
  BrandTokens copyWith({
    Color? seed,
    Color? accent,
    double? radius,
    VisualDensity? density,
    double? spacing,
    Duration? scanMinDuration,
  }) {
    return BrandTokens(
      seed: seed ?? this.seed,
      accent: accent ?? this.accent,
      radius: radius ?? this.radius,
      density: density ?? this.density,
      spacing: spacing ?? this.spacing,
      scanMinDuration: scanMinDuration ?? this.scanMinDuration,
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
    );
  }
}
