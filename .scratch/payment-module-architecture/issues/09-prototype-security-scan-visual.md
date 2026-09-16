# 09. Security Scan visual

Type: prototype
Status: resolved
Blocked by: —
Part of: ../map.md

## Question

Prototype the CustomPainter visual: pulsating radar (sweep + rings + blips) vs sine-wave scanner vs both, brand-tokenised — the *same* painter driven by different tokens (Retail warm/rounded/fluid, Utility navy/sharp/dense), or a per-brand painter chosen by config?

Constraints already settled: `repaint:` listenable, preallocated Paints, tokens read once, time-based maths, `RepaintBoundary`, placed outside the `BlocBuilder` subtree. Measure: repaint rainbow shows only the scan repainting; frame times on a real device (ticket 04's recipe if available).

**Deliverable**: the chosen visual, its token inputs, and the isolation proof; prototype captured on a throwaway branch with a pointer here.

**Inputs from resolved tickets**
- Ticket 07: the Scan phase lasts at least the brand motion token `scanMinDuration` (Retail ≈ 2.0 s, Utility ≈ 1.2 s) and ends on a phase change, so the visual must loop seamlessly and stop cleanly at any point — no "must finish the sweep" coupling. Ticket 04: request the high-refresh display mode before measuring.
- Ticket 08: the painter reads `BrandTokens` — `seed`, `accent`, `radius`, `density`, `spacing`, `scanMinDuration` — via `context.tokens`; the prototype's `brand_engine.dart` on `prototype/brand-slots` can be copied as the starting point.

## Answer

**Resolved 2026-09-16 (prototype, UI branch / sub-shape B; verdict accepted in one round).**

**Asset**: branch `prototype/security-scan`, path `prototypes/security_scan/` (throwaway Flutter web app; README has the run command; `flutter test` runs the isolation measurement). Three visuals (`?variant=R|W|G`) × two brands (`?brand=retail|utility`), each visual a single token-driven `CustomPainter`; a canary painter in the page layer counts page repaints; toggles for the `RepaintBoundary` and the repaint rainbow.

### Verdict
1. **Visual: radar** (`RadarPainter`) — rings that pulse (fluid brand) or stay static (dense brand), a rotating gradient sweep (wide/soft vs narrow/sharp), fading blips (round vs square), centre dot. Runner-up named in the spec: the grid shield (strongest security metaphor, ~260 draw calls/frame). Waveform rejected (reads as audio; low contrast on Utility).
2. **One painter, no `scanStyle` config.** Brand variation comes from `BrandTokens` only; the prototype's `ScanStyle` enum was the variant switch, not a proposal. A future brand wanting a different visual pays for a painter *and* a config knob then, not now.
3. **Token inputs**: `seed`, `accent`, `density` (`isDense` → ring count 4/3, stroke width, sweep angle, blip shape), `scanMinDuration`. `radius`/`spacing` unused by the radar. **Motion rule: one full sweep == `scanMinDuration`** — the Scan phase always shows ≥ 1 complete cycle and can stop at any phase boundary cleanly.
4. **Isolation proof**: primary = the **canary widget test** as prototyped, moved into `security_guard`'s suite — pump 60 animation frames → scan paints 60, page-layer paints **0**; 10 emissions → page-layer paints 10; control with the boundary removed → 60. Deterministic, CI, no device. Secondary = ticket 04's on-device `watchPerformance()` integration test for frame timing against the live refresh rate. Repaint rainbow stays a dev-time tool.
5. **Reduced motion** (fog graduated): when `MediaQuery.disableAnimationsOf(context)` is true, `SecurityScanView` stops the controller at a fixed phase (static frame); the Scan phase still lasts `scanMinDuration` — the duration is the assessment's rule, not the animation's.

### Evidence
- Screenshots (all six) show each brand reading as itself from tokens alone; no per-brand painter anywhere.
- `flutter test` on the prototype: all 3 visuals × 2 brands → `60 / 0 / 10`; control → `60 / 60 / 10`.
- Constraints honoured in every painter: `super(repaint: progress)` (frames never rebuild widgets), Paints and shaders preallocated in the constructor (sweep gradient built once, the canvas is rotated per frame), tokens read once, `shouldRepaint` false unless tokens change, time-based maths via `controller.value`, `Path` reused.

### Shapes for the spec
```dart
// security_guard/presentation
class SecurityScanView extends StatefulWidget {                  // const-constructible; no style parameter
  const SecurityScanView({super.key, this.size = const Size(280, 200)});
}
// State: AnimationController(vsync, duration: tokens.scanMinDuration)..repeat();
//        tokens read in didChangeDependencies (rebuild painter only when tokens change);
//        MediaQuery.disableAnimationsOf(context) → controller.stop() at value 0.25;
//        build: RepaintBoundary(child: CustomPaint(size, painter: RadarPainter(tokens: tokens, progress: controller)))

class RadarPainter extends CustomPainter {                      // src/, not exported
  RadarPainter({required this.tokens, required Animation<double> progress}) : …preallocated Paints…, super(repaint: progress);
  @override bool shouldRepaint(RadarPainter old) => old.tokens != tokens;
}
```

### Consequences pushed
- Ticket 15: the shapes above; the canary test as the "Optimization" requirement's proof; the motion rule; reduced-motion behaviour; runner-up noted.
- Map fog: reduced-motion item graduated (decided here).
