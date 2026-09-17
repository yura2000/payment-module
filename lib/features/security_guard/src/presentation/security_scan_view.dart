import 'package:flutter/material.dart';

import '../../../../brand_engine/brand_engine.dart';
import 'radar_painter.dart';

/// The Security Scan animation. Const-constructible and free of Brand identity — it reads
/// `BrandTokens` from the Theme, so the same widget is the Retail and the Utility scan
/// (docs/architecture.md §12.1). One full sweep lasts `tokens.scanMinDuration`, so the Scan
/// phase always shows at least one complete cycle.
///
/// The `RepaintBoundary` here is what keeps an animating scan from repainting the page layer —
/// the property `prototype/security-scan`'s isolation measurement proved (§12.3(1)); this plan
/// does not carry that measurement forward as a test, at the user's request.
class SecurityScanView extends StatefulWidget {
  const SecurityScanView({super.key, this.size = const Size(280, 200)});

  final Size size;

  @override
  State<SecurityScanView> createState() => SecurityScanViewState();
}

/// Public only so widget tests can assert on [controller] without importing `src/`.
class SecurityScanViewState extends State<SecurityScanView>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  BrandTokens? _tokens;
  RadarPainter? _painter;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tokens = context.tokens;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (tokens != _tokens) {
      _tokens = tokens;
      _painter = RadarPainter(tokens: tokens, progress: controller);
      controller.duration = tokens.scanMinDuration;
    }
    // Reduced motion: hold a fixed phase — a static radar — while the Scan phase still lasts
    // the Brand's minimum duration (§12.1).
    if (reduceMotion) {
      controller
        ..stop()
        ..value = 0.25;
    } else if (!controller.isAnimating) {
      controller.repeat();
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(size: widget.size, painter: _painter),
  );
}
