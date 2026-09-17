import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../brand_engine/brand_engine.dart';

/// The Security Scan visual: pulsing rings (fluid Brands) or static ones (dense Brands), a
/// rotating gradient sweep, fading blips, a centre dot. One painter — every Brand difference
/// comes from [BrandTokens], never from Brand identity (docs/architecture.md §2 principle 5,
/// §12.1). Ported from the `prototype/security-scan` branch, whose isolation measurements §12.3
/// records (60 animation frames → 0 page-layer repaints).
///
/// Frames arrive through `super(repaint: progress)`, so an animating scan never rebuilds a
/// widget; [shouldRepaint] is false unless the tokens themselves change. Every `Paint` and the
/// sweep shader are built once, here, and the canvas is rotated per frame instead.
class RadarPainter extends CustomPainter {
  RadarPainter({required this.tokens, required Animation<double> progress})
    : _progress = progress,
      rings = tokens.isDense ? 4 : 3,
      _ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = tokens.isDense ? 1.0 : 2.0
        ..color = tokens.seed.withValues(alpha: 0.35),
      _cross = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = tokens.seed.withValues(alpha: 0.18),
      _sweep = Paint()
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: tokens.isDense ? math.pi / 4 : math.pi / 2.2,
          colors: [
            tokens.seed.withValues(alpha: 0),
            tokens.seed.withValues(alpha: 0.55),
          ],
        ).createShader(const Rect.fromLTWH(-1, -1, 2, 2)),
      _edge = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = tokens.isDense ? 1.5 : 3.0
        ..color = tokens.accent,
      _blip = Paint()..color = tokens.accent,
      _center = Paint()..color = tokens.seed,
      super(repaint: progress);

  final BrandTokens tokens;
  final Animation<double> _progress;
  final int rings;
  final Paint _ring, _cross, _sweep, _edge, _blip, _center;

  /// Fixed (angle, radius fraction) pairs — a Brand changes how blips look, not where they are.
  static const _blips = [(0.4, 0.55), (2.1, 0.8), (4.4, 0.35)];

  @override
  void paint(Canvas canvas, Size size) {
    final t = _progress.value; // 0..1 per cycle, ticker-driven
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;

    for (var i = 1; i <= rings; i++) {
      final pulse = tokens.isDense
          ? 0.0
          : 3 * math.sin((t + i / rings) * 2 * math.pi);
      canvas.drawCircle(c, r * i / rings + pulse, _ring);
    }
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx + r, c.dy), _cross);
    canvas.drawLine(Offset(c.dx, c.dy - r), Offset(c.dx, c.dy + r), _cross);

    final angle = t * 2 * math.pi;
    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate(angle)
      ..scale(r)
      ..drawArc(
        const Rect.fromLTWH(-1, -1, 2, 2),
        0,
        tokens.isDense ? math.pi / 4 : math.pi / 2.2,
        true,
        _sweep,
      )
      ..restore();
    canvas.drawLine(
      c,
      c + Offset(math.cos(angle) * r, math.sin(angle) * r),
      _edge,
    );

    for (final (a, f) in _blips) {
      var delta = (angle - a) % (2 * math.pi);
      if (delta < 0) delta += 2 * math.pi;
      final alpha = (1 - delta / (2 * math.pi)).clamp(0.0, 1.0);
      _blip.color = tokens.accent.withValues(alpha: alpha);
      final p = c + Offset(math.cos(a) * r * f, math.sin(a) * r * f);
      if (tokens.isDense) {
        canvas.drawRect(
          Rect.fromCenter(center: p, width: 5, height: 5),
          _blip,
        );
      } else {
        canvas.drawCircle(p, 4 + 2 * alpha, _blip);
      }
    }
    canvas.drawCircle(c, tokens.isDense ? 2 : 4, _center);
  }

  @override
  bool shouldRepaint(RadarPainter old) => old.tokens != tokens;
}
