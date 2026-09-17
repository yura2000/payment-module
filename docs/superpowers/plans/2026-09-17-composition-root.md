# Composition Root Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Assemble the app. Everything Plans 1–4 deliberately deferred to "the composition root": the Security Scan visual, the payment page and its Brand-ordered Sections, the two Brands and their registry, DI wiring, `bootstrap()`, the two "keep it honest" guard tests, per-brand goldens, the on-device perf test, and the `Makefile`. After this plan `make run BRAND=retail` shows the real screen.

**Architecture:** Last of five plans. Plans 1–4 are merged; this branch starts at `65926ba` (native-bridge merge) with **155 tests passing**. Everything below is already specified in `docs/architecture.md` — this plan adds no new design surface: no `BrandTokens` field beyond the seven §6 names, no `PaymentSection` variant beyond §6's five, no `import_lint` rule beyond §3.3's eleven, no `Makefile` target beyond §15's six. Where the spec is silent (UI copy, exact widget structure, `headlineWeight` values) this plan picks the smallest reasonable thing and **says so inline**; silence is not licence to invent configuration.

**Tech Stack:** Flutter 3.44.6 / Dart 3.12 via FVM. One new dependency: `intl` (money formatting — §5 stores `amountMinor` + `currency`, and rendering that needs a real currency formatter that knows JPY has no decimal digits). Two dev dependencies promoted from transitive to explicit: `yaml` and `glob`, which `test/architecture_test.dart` uses to read §3.3's rules out of `analysis_options.yaml` rather than restating them. Android is untouched — flavors, channels and the foreground service all shipped with Plan 4.

**Carry-forward from Plans 1–4** (apply automatically, don't re-derive):
- The lint command is `dart analyze --fatal-infos`, never `flutter analyze` (§3.3 finding 1 and 3).
- Every `import_lint` rule needs an explicit `except: []`.
- Tests import a module through its barrel or its `di.dart`, never its `src/`.
- Every `flutter run` / `build` / `drive` needs `--flavor retail|utility` **and** `--dart-define=BRAND=<same>`.
- `~/fvm/versions/3.44.6/bin/flutter` and `~/fvm/versions/3.44.6/bin/dart` are the exact binaries (confirmed present).

**Reference:** `docs/architecture.md` §2 (principle 5: zero conditionals on Brand identity), §3.1/§3.3 (layout, the eleven lint walls), §4 (module interfaces and registration), §6 (the white-label engine, the `PaymentSection` code block, the Brand values table), §7 (two blocs, `canPay`), §11 (Secure Window), §12 (the Radar, refresh rate, the two proofs), §13/§13.1 (adding a Brand and its three guards), §14 (testing), §15 (the six `Makefile` targets). `CONTEXT.md` for every capitalised term. `docs/adr/0002` for Brand selection.

**Prototypes are primary sources for *technique*, not shape.** `prototype/security-scan` holds a validated `RadarPainter` and the isolation measurement; `prototype/brand-slots` holds the section widgets and the sealed-variant page. Port their bodies; drop their prototype scaffolding (global paint counters, `ScanStyle`, `isolate` toggles, `sectionsA`/`sectionsC` triple-variant configs, the `id`/`displayName` fields their throwaway `BrandTokens` carried).

**Scope boundary — what this plan does NOT build:** iOS anything; a real backend; runtime Brand switching or a debug Brand picker; per-flavor launcher icons (§13 row 4, explicitly optional); `docs/ai/prompt-log.md` and the AI Insight Report (deliverables, not code); a CI workflow file. Goldens **are** in scope (§13.1.3) but their reference PNGs are generated on this machine — §13.1.3's "executed in CI on Linux" stays unsatisfied until a CI matrix exists, and Task 17 says so in the committed note.

---

## File structure

```
lib/
├── main.dart                                       # MODIFY — replace the placeholder with bootstrap()
├── app/                                            # NEW directory
│   ├── locator.dart                                # setupLocator(brand)
│   └── payment_app.dart                            # PaymentApp (MaterialApp + BrandScope + the page)
├── brands/                                         # NEW directory
│   ├── retail.dart                                 # const retailBrand
│   ├── utility.dart                                # const utilityBrand
│   └── registry.dart                               # const brandRegistry
├── brand_engine/
│   ├── brand_engine.dart                           # MODIFY — export brand_registry.dart
│   └── src/
│       ├── brand_tokens.dart                       # MODIFY — add headlineWeight (copyWith + lerp)
│       └── brand_registry.dart                      # NEW — BrandRegistry(all, byId)
└── features/
    ├── security_guard/
    │   ├── security_guard.dart                     # MODIFY — export the two new widgets
    │   └── src/presentation/
    │       ├── radar_painter.dart                  # NEW — ported from prototype/security-scan, not exported
    │       ├── security_scan_view.dart             # NEW — exported
    │       └── posture_banner.dart                 # NEW — exported
    └── payment/
        ├── payment.dart                            # MODIFY — export config, sections, page
        └── src/presentation/
            ├── format_money.dart                   # NEW — formatMoney(Money)
            ├── payment_brand_config.dart           # NEW — PaymentBrandConfig + sealed PaymentSection
            ├── section_widgets.dart                # NEW — SummaryCard · PromoBanner · BillBreakdown · PayButton
            ├── result_view.dart                    # NEW — the Completed phase's view
            └── payment_confirmation_page.dart      # NEW — the screen; wires both blocs

test/
├── architecture_test.dart                          # NEW — §3.3's belt-and-braces regex walker
├── brand_engine/brand_registry_test.dart           # NEW
├── brands/
│   ├── brand_registry_test.dart                    # NEW — §13.1(1), the completeness guard
│   └── flavor_registry_test.dart                   # NEW — §13.1(2), flavors ↔ registry
├── app/locator_test.dart                           # NEW
├── features/
│   ├── security_guard/
│   │   ├── scan_isolation_test.dart                # NEW — §12.3(1), the canary
│   │   ├── security_scan_view_test.dart            # NEW
│   │   └── posture_banner_test.dart                # NEW
│   └── payment/
│       ├── format_money_test.dart                  # NEW
│       ├── payment_brand_config_test.dart          # NEW
│       ├── section_widgets_test.dart               # NEW
│       ├── result_view_test.dart                   # NEW
│       └── payment_confirmation_page_test.dart     # NEW
└── golden/
    ├── payment_page_golden_test.dart               # NEW — §13.1(3), tagged `golden`
    └── goldens/{retail,utility}/*.png              # GENERATED

integration_test/perf_test.dart                     # NEW — §12.3(2)
Makefile                                            # NEW — §15's six targets
README.md                                           # MODIFY — replace the Flutter template text
docs/verification/2026-09-17-composition-root-verification.md   # NEW — Task 20's audit note
```

Three grouping calls worth stating, since a reader could reasonably have split differently. `payment_brand_config.dart` holds both `PaymentBrandConfig` and the sealed `PaymentSection` hierarchy: a section variant and the config that orders it change together, and §6's own code block presents them as one unit. `section_widgets.dart` holds all four known section widgets: each is ~25 lines of leaf `Widget build`, they share the tokens-and-text-theme idiom, and four one-widget files would be noise. `radar_painter.dart` stays out of the barrel (§12.1: "src/, not exported") — the page needs `SecurityScanView`, never the painter.

---

### Task 1: Add `intl`; promote `yaml` and `glob` to explicit dev dependencies

**Files:**
- Modify: `pubspec.yaml`

`intl` is genuinely new (not in `pubspec.lock` today). `yaml` and `glob` are already resolved as transitive dependencies of `import_lint`, but Task 16's test imports them directly, and importing a package you don't declare is exactly what `depend_on_referenced_packages` flags.

- [ ] **Step 1: Add the dependencies**

```bash
~/fvm/versions/3.44.6/bin/flutter pub add intl
~/fvm/versions/3.44.6/bin/flutter pub add --dev yaml glob
```

Let `pub add` resolve the versions — `intl` in particular is version-constrained by the Flutter SDK, so a hand-written constraint can be wrong in a way that only shows up on the next SDK bump.

- [ ] **Step 2: Verify the workspace still analyzes and tests clean**

Run: `~/fvm/versions/3.44.6/bin/dart analyze --fatal-infos && ~/fvm/versions/3.44.6/bin/flutter test`
Expected: `No issues found!` and `155` tests passing — the same baseline as before, since nothing imports the new packages yet.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add intl; declare yaml and glob for the architecture test"
```

---

### Task 2: `BrandTokens` gains `headlineWeight`

**Files:**
- Modify: `lib/brand_engine/src/brand_tokens.dart`
- Test: `test/brand_engine/brand_tokens_test.dart` (exists — add to it)

§6's `BrandTokens` comment lists seven values: `seed, accent, radius, density, spacing, scanMinDuration, headlineWeight`. Six exist; `headlineWeight` doesn't, and both prototype section widgets use it (`style: ...copyWith(fontWeight: t.headlineWeight)`). Add it now so Task 7's widgets have it.

**Values are a plan-level choice** — §6's Brand table doesn't give them. Retail (fluid, warm, promotional) gets `FontWeight.w700`; Utility (dense, sharp, institutional) gets `FontWeight.w500`. Set in Task 11's Brand files, not here.

- [ ] **Step 1: Write the failing tests**

Append inside the existing `main()` in `test/brand_engine/brand_tokens_test.dart`:

```dart
  group('headlineWeight', () {
    const base = BrandTokens(
      seed: Color(0xFFE65100),
      accent: Color(0xFFFFB300),
      radius: 20,
      density: VisualDensity.comfortable,
      spacing: 16,
      scanMinDuration: Duration(milliseconds: 2000),
      headlineWeight: FontWeight.w700,
    );

    test('copyWith replaces headlineWeight and preserves it when not given', () {
      expect(base.copyWith(headlineWeight: FontWeight.w500).headlineWeight, FontWeight.w500);
      expect(base.copyWith(radius: 4).headlineWeight, FontWeight.w700);
    });

    test('lerp interpolates headlineWeight towards the other tokens', () {
      final other = base.copyWith(headlineWeight: FontWeight.w300);
      expect(base.lerp(other, 0).headlineWeight, FontWeight.w700);
      expect(base.lerp(other, 1).headlineWeight, FontWeight.w300);
    });
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/brand_engine/brand_tokens_test.dart`
Expected: FAIL to compile — `No named parameter with the name 'headlineWeight'`

- [ ] **Step 3: Implement**

Four edits to `lib/brand_engine/src/brand_tokens.dart`:

1. Add `required this.headlineWeight,` as the last constructor parameter.
2. Add the field after `scanMinDuration`:

```dart
  /// Weight for the amount and other headline text — part of a Brand's voice, and not
  /// expressible through `ThemeData` alone without fixing the whole text theme.
  final FontWeight headlineWeight;
```

3. Add to `copyWith`'s parameter list `FontWeight? headlineWeight,` and to its returned `BrandTokens`:

```dart
      headlineWeight: headlineWeight ?? this.headlineWeight,
```

4. Add to `lerp`'s returned `BrandTokens`:

```dart
      headlineWeight: FontWeight.lerp(headlineWeight, other.headlineWeight, t)!,
```

Update the class doc comment's value list if it enumerates them.

- [ ] **Step 4: Run the whole suite — every existing `BrandTokens(...)` literal now needs the new argument**

Run: `~/fvm/versions/3.44.6/bin/flutter test`
Expected: compile errors in any test that constructs `BrandTokens` (at minimum `test/brand_engine/brand_theme_test.dart` and `test/brand_engine/brand_tokens_test.dart`). Add `headlineWeight: FontWeight.w700` to each such literal, then re-run until `All tests passed!`. Count the total from the runner; it should still be 155 plus the 2 added here.

- [ ] **Step 5: Verify lint**

Run: `~/fvm/versions/3.44.6/bin/dart analyze --fatal-infos`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/brand_engine test/brand_engine
git commit -m "feat(brand_engine): add BrandTokens.headlineWeight"
```

---

### Task 3: `BrandRegistry`

**Files:**
- Create: `lib/brand_engine/src/brand_registry.dart`
- Modify: `lib/brand_engine/brand_engine.dart` (add one export line)
- Test: `test/brand_engine/brand_registry_test.dart`

§4 lists `BrandRegistry (type: all, byId)` among `brand_engine`'s exports. It's the lookup `bootstrap()` runs the `BRAND` dart-define through. Two members, no more: `all` for the guard tests and the goldens to iterate, `byId` for bootstrap.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/core/brand_id.dart';

const _tokens = BrandTokens(
  seed: Color(0xFFE65100),
  accent: Color(0xFFFFB300),
  radius: 20,
  density: VisualDensity.comfortable,
  spacing: 16,
  scanMinDuration: Duration(milliseconds: 2000),
  headlineWeight: FontWeight.w700,
);

const _first = BrandConfig(
  id: BrandId('first'),
  displayName: 'First',
  tokens: _tokens,
  features: [],
);
const _second = BrandConfig(
  id: BrandId('second'),
  displayName: 'Second',
  tokens: _tokens,
  features: [],
);

void main() {
  const registry = BrandRegistry([_first, _second]);

  test('all exposes the Brands in declaration order', () {
    expect(registry.all, [_first, _second]);
  });

  test('byId returns the Brand with that id', () {
    expect(registry.byId(const BrandId('second')), same(_second));
  });

  test('byId throws a StateError naming the unknown id and the known ones', () {
    expect(
      () => registry.byId(const BrandId('missing')),
      throwsA(
        isA<StateError>()
            .having((e) => e.message, 'message', contains('missing'))
            .having((e) => e.message, 'message', contains('first')),
      ),
    );
  });

  test('ids lists every registered id', () {
    expect(registry.ids, ['first', 'second']);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/brand_engine/brand_registry_test.dart`
Expected: FAIL to compile — `Undefined class 'BrandRegistry'`

- [ ] **Step 3: Implement**

```dart
// lib/brand_engine/src/brand_registry.dart
import '../../core/brand_id.dart';
import 'brand_config.dart';

/// Every Brand the binary knows, in declaration order. `bootstrap()` resolves the `BRAND`
/// dart-define through [byId]; the guard tests and the goldens iterate [all]. One `const`
/// instance lives in `lib/brands/registry.dart`. See docs/architecture.md §4, §6, §13.
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
```

```dart
// lib/brand_engine/brand_engine.dart — add this line
export 'src/brand_registry.dart';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/brand_engine/brand_registry_test.dart`
Expected: `00:00 +4: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/brand_engine test/brand_engine/brand_registry_test.dart
git commit -m "feat(brand_engine): add BrandRegistry"
```

---

### Task 4: `formatMoney`

**Files:**
- Create: `lib/features/payment/src/presentation/format_money.dart`
- Modify: `lib/features/payment/payment.dart` (add one export line)
- Test: `test/features/payment/format_money_test.dart`

§5 keeps `Money` as data only and says "formatting uses `intl` in `payment/presentation`". The one subtlety worth a function instead of an inline `/ 100`: the minor-unit scale is per-currency — USD has 2 decimal digits, JPY has 0 — and `intl`'s formatter already knows which, so ask it rather than hard-coding a divisor.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/money.dart';
import 'package:payment_module/features/payment/payment.dart';

void main() {
  test('formats a two-decimal currency from its minor unit', () {
    expect(
      formatMoney(const Money(amountMinor: 4200, currency: 'USD')),
      r'$42.00',
    );
  });

  test('keeps sub-unit precision', () {
    expect(
      formatMoney(const Money(amountMinor: 4299, currency: 'USD')),
      r'$42.99',
    );
  });

  test('formats a zero-decimal currency without inventing decimals', () {
    expect(formatMoney(const Money(amountMinor: 4200, currency: 'JPY')), '¥4,200');
  });

  test('groups thousands', () {
    expect(
      formatMoney(const Money(amountMinor: 123456789, currency: 'USD')),
      r'$1,234,567.89',
    );
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/format_money_test.dart`
Expected: FAIL to compile — `Undefined name 'formatMoney'`

- [ ] **Step 3: Implement**

```dart
// lib/features/payment/src/presentation/format_money.dart
import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../../../../core/money.dart';

/// Renders a [Money] for display. The scale between the minor unit and the major one is a
/// property of the currency (USD 2 digits, JPY 0), so it comes from the formatter rather than a
/// hard-coded 100. See docs/architecture.md §5.
String formatMoney(Money money) {
  final format = NumberFormat.simpleCurrency(name: money.currency);
  final digits = format.decimalDigits ?? 2;
  return format.format(money.amountMinor / math.pow(10, digits));
}
```

```dart
// lib/features/payment/payment.dart — add this line
export 'src/presentation/format_money.dart';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/format_money_test.dart`
Expected: `00:00 +4: All tests passed!`

If a currency symbol differs from the expected string (`intl` renders `simpleCurrency` per locale data, and the default locale in a test binding is `en_US`), fix the **test's expectation** to whatever `intl` actually produces for that currency — don't reshape the implementation to force a symbol. Paste the actual value into the expectation and move on.

- [ ] **Step 5: Commit**

```bash
git add lib/features/payment test/features/payment/format_money_test.dart
git commit -m "feat(payment): add formatMoney"
```

---

### Task 5: `RadarPainter` and `SecurityScanView`

**Files:**
- Create: `lib/features/security_guard/src/presentation/radar_painter.dart`
- Create: `lib/features/security_guard/src/presentation/security_scan_view.dart`
- Modify: `lib/features/security_guard/security_guard.dart` (add one export line — the view only, never the painter)
- Test: `test/features/security_guard/security_scan_view_test.dart`

Ported from `prototype/security-scan` (`lib/painters/radar_painter.dart`, `lib/scan_view.dart`), which §12.1 settled as the chosen visual. Three prototype-only things are dropped: the global `scanPaints++` counter (`counters.dart`), the `ScanStyle` enum and the `style` parameter (§12.1: "no `scanStyle` configuration"), and the `isolate` toggle (§12.1: the boundary is unconditional). Everything else — ring count, pulse, sweep angles, blip shapes, preallocated `Paint`s, `super(repaint: progress)`, `shouldRepaint` — is the prototype's validated code unchanged.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

const _retailTokens = BrandTokens(
  seed: Color(0xFFE65100),
  accent: Color(0xFFFFB300),
  radius: 20,
  density: VisualDensity.comfortable,
  spacing: 16,
  scanMinDuration: Duration(milliseconds: 2000),
  headlineWeight: FontWeight.w700,
);

const _utilityTokens = BrandTokens(
  seed: Color(0xFF0D2B4E),
  accent: Color(0xFF5C6B7A),
  radius: 4,
  density: VisualDensity.compact,
  spacing: 8,
  scanMinDuration: Duration(milliseconds: 1200),
  headlineWeight: FontWeight.w500,
);

Widget _host(BrandTokens tokens, {bool disableAnimations = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: disableAnimations),
  child: MaterialApp(
    theme: ThemeData(extensions: [tokens]),
    home: const Scaffold(body: Center(child: SecurityScanView())),
  ),
);

void main() {
  testWidgets('wraps its CustomPaint in a RepaintBoundary', (tester) async {
    await tester.pumpWidget(_host(_retailTokens));

    final boundary = find.ancestor(
      of: find.byType(CustomPaint).last,
      matching: find.byType(RepaintBoundary),
    );
    expect(boundary, findsWidgets);
  });

  testWidgets('one animation cycle lasts the Brand scanMinDuration', (tester) async {
    await tester.pumpWidget(_host(_utilityTokens));

    final state = tester.state<SecurityScanViewState>(find.byType(SecurityScanView));
    expect(state.controller.duration, const Duration(milliseconds: 1200));
    expect(state.controller.isAnimating, isTrue);
  });

  testWidgets('re-reads the duration when the Brand tokens change', (tester) async {
    await tester.pumpWidget(_host(_retailTokens));
    await tester.pumpWidget(_host(_utilityTokens));

    final state = tester.state<SecurityScanViewState>(find.byType(SecurityScanView));
    expect(state.controller.duration, const Duration(milliseconds: 1200));
  });

  testWidgets('holds a fixed phase instead of animating when animations are disabled', (tester) async {
    await tester.pumpWidget(_host(_retailTokens, disableAnimations: true));

    final state = tester.state<SecurityScanViewState>(find.byType(SecurityScanView));
    expect(state.controller.isAnimating, isFalse);
    expect(state.controller.value, 0.25);
  });

  testWidgets('renders at the size it was given', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [_retailTokens]),
        home: const Scaffold(
          body: Center(child: SecurityScanView(size: Size(120, 90))),
        ),
      ),
    );

    expect(tester.getSize(find.byType(SecurityScanView)), const Size(120, 90));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/security_guard/security_scan_view_test.dart`
Expected: FAIL to compile — `Undefined class 'SecurityScanView'`

- [ ] **Step 3: Implement the painter**

```dart
// lib/features/security_guard/src/presentation/radar_painter.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../brand_engine/brand_engine.dart';

/// The Security Scan visual: pulsing rings (fluid Brands) or static ones (dense Brands), a
/// rotating gradient sweep, fading blips, a centre dot. One painter — every Brand difference
/// comes from [BrandTokens], never from Brand identity (docs/architecture.md §2 principle 5,
/// §12.1). Ported from the `prototype/security-scan` branch, whose measurements §12.3 records.
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
```

- [ ] **Step 4: Implement the view**

`State` is public (`SecurityScanViewState`) purely so the tests above can read `controller` without reaching into `src/`; that is the whole reason, and the doc comment says so.

```dart
// lib/features/security_guard/src/presentation/security_scan_view.dart
import 'package:flutter/material.dart';

import '../../../../brand_engine/brand_engine.dart';
import 'radar_painter.dart';

/// The Security Scan animation. Const-constructible and free of Brand identity — it reads
/// `BrandTokens` from the Theme, so the same widget is the Retail and the Utility scan
/// (docs/architecture.md §12.1). One full sweep lasts `tokens.scanMinDuration`, so the Scan
/// phase always shows at least one complete cycle.
///
/// The `RepaintBoundary` here is what keeps an animating scan from repainting the page layer;
/// `test/features/security_guard/scan_isolation_test.dart` measures that claim (§12.3).
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
```

```dart
// lib/features/security_guard/security_guard.dart — add this line
export 'src/presentation/security_scan_view.dart';
```

- [ ] **Step 5: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/security_guard/security_scan_view_test.dart`
Expected: `00:00 +5: All tests passed!`

- [ ] **Step 6: Verify lint**

Run: `~/fvm/versions/3.44.6/bin/dart analyze --fatal-infos`
Expected: `No issues found!` — in particular no `presentation_no_data` or `domain_no_flutter` violation, since both new files sit in `presentation/` and import only `brand_engine` and Flutter.

- [ ] **Step 7: Commit**

```bash
git add lib/features/security_guard test/features/security_guard/security_scan_view_test.dart
git commit -m "feat(security_guard): add RadarPainter and SecurityScanView"
```

---

### Task 6: The canary isolation test — §12.3's first proof

**Files:**
- Test: `test/features/security_guard/scan_isolation_test.dart`

§12.3(1) is a *number*, not a vibe: the scan paints once per animation frame, the page layer paints zero times for those frames, and a control without the boundary paints the page layer every frame. The prototype measured 60/0/60 for radar × Retail/Utility.

One design decision, stated because it's the crux of this task. The production `RadarPainter` carries **no paint counter** — instrumenting shipped code to make a test possible is backwards. So the test measures the *mechanism* with its own counting painters — a `_CountingScanPainter` driven by `super(repaint:)` exactly as `RadarPainter` is, and a `_CanaryPainter` in the page layer — and separately asserts that the real `SecurityScanView` puts a `RepaintBoundary` above its `CustomPaint` and drives it from an animation. Together those two halves prove what §12.3 claims about the real widget; the counting half alone can also express the control case (no boundary), which the real widget deliberately cannot.

- [ ] **Step 1: Write the test**

```dart
// The §12.3(1) proof: an animating, repaint-listenable-driven CustomPaint inside a
// RepaintBoundary paints every frame without repainting the page layer around it — and the same
// tree without the boundary repaints the page layer on every single frame.
//
// The counters live in these test-local painters, never in RadarPainter: production code
// shouldn't carry instrumentation. Task 5's widget test pins the other half of the claim — that
// the real SecurityScanView is this exact structure (RepaintBoundary + CustomPaint + a running
// AnimationController).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

int _scanPaints = 0;
int _canaryPaints = 0;

/// Stands in for [RadarPainter]: same contract — frames arrive through `repaint`, never through
/// rebuilds, and `shouldRepaint` is false.
class _CountingScanPainter extends CustomPainter {
  _CountingScanPainter(Animation<double> progress) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    _scanPaints++;
  }

  @override
  bool shouldRepaint(_CountingScanPainter old) => false;
}

/// Lives in the page layer, outside the boundary. Flutter repaints everything in a layer
/// together, so this painter's count *is* the page layer's repaint count.
class _CanaryPainter extends CustomPainter {
  const _CanaryPainter(this.progressLabel);

  final int progressLabel;

  @override
  void paint(Canvas canvas, Size size) {
    _canaryPaints++;
  }

  @override
  bool shouldRepaint(_CanaryPainter old) => old.progressLabel != progressLabel;
}

const _tokens = BrandTokens(
  seed: Color(0xFFE65100),
  accent: Color(0xFFFFB300),
  radius: 20,
  density: VisualDensity.comfortable,
  spacing: 16,
  scanMinDuration: Duration(milliseconds: 2000),
  headlineWeight: FontWeight.w700,
);

/// The page shape under test: a scan (optionally isolated) plus a page-layer canary that
/// repaints whenever the fake BLoC emits.
class _Harness extends StatefulWidget {
  const _Harness({required this.isolate, required this.progress});

  final bool isolate;
  final ValueNotifier<int> progress;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scan = CustomPaint(
      size: const Size(280, 200),
      painter: _CountingScanPainter(_controller),
    );
    return Column(
      children: [
        widget.isolate ? RepaintBoundary(child: scan) : scan,
        ValueListenableBuilder<int>(
          valueListenable: widget.progress,
          builder: (context, value, _) => CustomPaint(
            size: const Size(40, 40),
            painter: _CanaryPainter(value),
          ),
        ),
      ],
    );
  }
}

Future<({int scan, int canaryDuringAnimation, int canaryDuringEmissions})>
_measure(
  WidgetTester tester, {
  required bool isolate,
  int frames = 60,
  int emissions = 10,
}) async {
  final progress = ValueNotifier<int>(0);
  addTearDown(progress.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(extensions: const [_tokens]),
      home: Scaffold(body: _Harness(isolate: isolate, progress: progress)),
    ),
  );
  await tester.pump(); // settle the first frame

  final scan0 = _scanPaints;
  final canary0 = _canaryPaints;
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  final scan = _scanPaints - scan0;
  final canaryDuringAnimation = _canaryPaints - canary0;

  final canary1 = _canaryPaints;
  for (var i = 0; i < emissions; i++) {
    progress.value++;
    await tester.pump(const Duration(milliseconds: 100));
  }
  final canaryDuringEmissions = _canaryPaints - canary1;

  return (
    scan: scan,
    canaryDuringAnimation: canaryDuringAnimation,
    canaryDuringEmissions: canaryDuringEmissions,
  );
}

void main() {
  setUp(() {
    _scanPaints = 0;
    _canaryPaints = 0;
  });

  testWidgets('an isolated scan paints every frame and never repaints the page layer', (
    tester,
  ) async {
    final result = await _measure(tester, isolate: true);

    expect(result.scan, 60, reason: 'the scan must paint once per animation frame');
    expect(
      result.canaryDuringAnimation,
      0,
      reason: 'the animation must not repaint the page layer',
    );
    expect(
      result.canaryDuringEmissions,
      10,
      reason: 'the page layer must still repaint when the flow state changes',
    );
  });

  testWidgets('control: without the boundary every animation frame repaints the page layer', (
    tester,
  ) async {
    final result = await _measure(tester, isolate: false);

    expect(result.scan, 60);
    expect(
      result.canaryDuringAnimation,
      60,
      reason: 'control: this is what the RepaintBoundary is preventing',
    );
  });

  testWidgets('the real SecurityScanView is the isolated structure this test measures', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [_tokens]),
        home: const Scaffold(body: SecurityScanView()),
      ),
    );

    final paint = find.descendant(
      of: find.byType(SecurityScanView),
      matching: find.byType(CustomPaint),
    );
    expect(
      find.ancestor(of: paint.last, matching: find.byType(RepaintBoundary)),
      findsWidgets,
      reason: 'the scan CustomPaint must sit inside a RepaintBoundary',
    );

    final state = tester.state<SecurityScanViewState>(
      find.byType(SecurityScanView),
    );
    expect(
      state.controller.isAnimating,
      isTrue,
      reason: 'frames must come from a running controller, i.e. from `repaint`',
    );
  });
}
```

- [ ] **Step 2: Run it**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/security_guard/scan_isolation_test.dart`
Expected: `00:00 +3: All tests passed!`

If the frame counts are off by one (61 instead of 60, say), the extra paint is the settle pump and the fix is the *baseline*, not the assertion: capture `scan0`/`canary0` after the extra `await tester.pump()` that caused it. Do not change `60` to a range or delete the assertion — a number that can't be pinned down is not a proof, and if you genuinely cannot make it deterministic, stop and report that rather than loosening it.

- [ ] **Step 3: Commit**

```bash
git add test/features/security_guard/scan_isolation_test.dart
git commit -m "test(security_guard): prove the scan never repaints the page layer"
```

---

### Task 7: `PostureBanner`

**Files:**
- Create: `lib/features/security_guard/src/presentation/posture_banner.dart`
- Modify: `lib/features/security_guard/security_guard.dart` (add one export line)
- Test: `test/features/security_guard/posture_banner_test.dart`

§7 writes it as `PostureBanner(verdict)` — a dumb presentational widget handed a `PolicyVerdict`, not one that reaches for a cubit. That keeps it golden-testable and lets Task 9's Result View reuse it for the "caveat" §7 mentions, instead of duplicating the copy.

Precedence when a verdict carries several kinds of trouble at once: **blockers beat warnings beat notices**, and only the winning band renders. Showing three stacked banners for one posture would be noise, and the blocker is the only one that changes what the user can do.

The copy below is this plan's invention — the architecture document specifies the *behaviour* (block / warn / notice) and never the wording. It is deliberately plain and names the Threat without jargon.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

const _tokens = BrandTokens(
  seed: Color(0xFF0D2B4E),
  accent: Color(0xFF5C6B7A),
  radius: 4,
  density: VisualDensity.compact,
  spacing: 8,
  scanMinDuration: Duration(milliseconds: 1200),
  headlineWeight: FontWeight.w500,
);

Future<void> _pump(WidgetTester tester, PolicyVerdict? verdict) => tester.pumpWidget(
  MaterialApp(
    theme: ThemeData(extensions: const [_tokens]),
    home: Scaffold(body: PostureBanner(verdict: verdict)),
  ),
);

void main() {
  test('nothing to report is nothing to show', () {
    expect(
      const PolicyVerdict(blockers: {}, warnings: {}, notices: {}).hasAnything,
      isFalse,
    );
  });

  testWidgets('renders nothing before the first assessment', (tester) async {
    await _pump(tester, null);
    expect(find.byType(SizedBox), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('renders nothing for a clear verdict', (tester) async {
    await _pump(tester, const PolicyVerdict(blockers: {}, warnings: {}, notices: {}));
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('a blocker names the Threat and says the payment is blocked', (tester) async {
    await _pump(
      tester,
      const PolicyVerdict(
        blockers: {ThreatKind.rooted},
        warnings: {},
        notices: {},
      ),
    );

    expect(find.textContaining('blocked', findRichText: true), findsOneWidget);
    expect(find.textContaining('rooted', findRichText: true), findsOneWidget);
    expect(find.byIcon(Icons.gpp_bad), findsOneWidget);
  });

  testWidgets('a warning names the Threat without blocking', (tester) async {
    await _pump(
      tester,
      const PolicyVerdict(
        blockers: {},
        warnings: {ThreatKind.screenRecording},
        notices: {},
      ),
    );

    expect(find.textContaining('recording', findRichText: true), findsOneWidget);
    expect(find.textContaining('blocked', findRichText: true), findsNothing);
    expect(find.byIcon(Icons.warning_amber), findsOneWidget);
  });

  testWidgets('a notice says the check could not run, not that anything was found', (tester) async {
    await _pump(
      tester,
      const PolicyVerdict(
        blockers: {},
        warnings: {},
        notices: {ThreatKind.screenRecording},
      ),
    );

    expect(find.textContaining('could not', findRichText: true), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });

  testWidgets('a blocker wins over a warning and a notice', (tester) async {
    await _pump(
      tester,
      const PolicyVerdict(
        blockers: {ThreatKind.rooted},
        warnings: {ThreatKind.screenRecording},
        notices: {ThreatKind.screenRecording},
      ),
    );

    expect(find.byType(Card), findsOneWidget);
    expect(find.byIcon(Icons.gpp_bad), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsNothing);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/security_guard/posture_banner_test.dart`
Expected: FAIL to compile — `Undefined class 'PostureBanner'` (and `hasAnything` isn't defined on `PolicyVerdict` yet either).

- [ ] **Step 3: Add `hasAnything` to `PolicyVerdict`**

In `lib/features/security_guard/src/domain/policy_verdict.dart`, next to `isBlocked`:

```dart
  /// Whether this verdict has anything at all to tell the user. `isBlocked` answers "may the
  /// payment proceed"; this answers "is there a banner to draw".
  bool get hasAnything =>
      blockers.isNotEmpty || warnings.isNotEmpty || notices.isNotEmpty;
```

- [ ] **Step 4: Implement the banner**

```dart
// lib/features/security_guard/src/presentation/posture_banner.dart
import 'package:flutter/material.dart';

import '../../../../brand_engine/brand_engine.dart';
import '../../../../core/threat.dart';
import '../domain/policy_verdict.dart';

/// Tells the user what the Policy Verdict found, in the Brand's shape. A dumb widget: it is
/// handed a verdict rather than reading `SecurityPostureCubit`, so the page owns the
/// subscription and this stays reusable — the Result View draws it as its caveat
/// (docs/architecture.md §7). [verdict] is null until the first assessment lands.
///
/// Blockers beat warnings beat notices, and only the winning band renders: one posture, one
/// banner. Nothing renders when there is nothing to say.
class PostureBanner extends StatelessWidget {
  const PostureBanner({super.key, required this.verdict});

  final PolicyVerdict? verdict;

  @override
  Widget build(BuildContext context) {
    final verdict = this.verdict;
    if (verdict == null || !verdict.hasAnything) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final (icon, background, foreground, message) = switch (verdict) {
      PolicyVerdict(blockers: final kinds) when kinds.isNotEmpty => (
        Icons.gpp_bad,
        scheme.errorContainer,
        scheme.onErrorContainer,
        'Payment blocked — ${_detected(kinds)}.',
      ),
      PolicyVerdict(warnings: final kinds) when kinds.isNotEmpty => (
        Icons.warning_amber,
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        'Heads up — ${_detected(kinds)}. You can still continue.',
      ),
      PolicyVerdict(notices: final kinds) => (
        Icons.info_outline,
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        '${_unavailable(kinds)}.',
      ),
    };

    final spacing = context.tokens.spacing;
    return Card(
      color: background,
      child: Padding(
        padding: EdgeInsets.all(spacing),
        child: Row(
          children: [
            Icon(icon, color: foreground),
            SizedBox(width: spacing),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _detected(Set<ThreatKind> kinds) =>
      kinds.map(_detectedLabel).join(' and ');

  static String _unavailable(Set<ThreatKind> kinds) =>
      kinds.map(_unavailableLabel).join('; ');

  static String _detectedLabel(ThreatKind kind) => switch (kind) {
    ThreatKind.rooted => 'this device appears to be rooted',
    ThreatKind.screenRecording => 'screen recording is active',
  };

  static String _unavailableLabel(ThreatKind kind) => switch (kind) {
    ThreatKind.rooted => 'Root detection could not run on this device',
    ThreatKind.screenRecording =>
      'Screen-recording protection could not be verified on this Android version',
  };
}
```

```dart
// lib/features/security_guard/security_guard.dart — add this line
export 'src/presentation/posture_banner.dart';
```

- [ ] **Step 5: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/security_guard/posture_banner_test.dart`
Expected: `00:00 +7: All tests passed!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/security_guard test/features/security_guard/posture_banner_test.dart
git commit -m "feat(security_guard): add PostureBanner"
```

---

### Task 8: `PaymentBrandConfig`, the sealed `PaymentSection`, and the four section widgets

**Files:**
- Create: `lib/features/payment/src/presentation/payment_brand_config.dart`
- Create: `lib/features/payment/src/presentation/section_widgets.dart`
- Modify: `lib/features/payment/payment.dart` (add two export lines)
- Test: `test/features/payment/payment_brand_config_test.dart`
- Test: `test/features/payment/section_widgets_test.dart`

§6's code block fixes both shapes exactly — five `PaymentSection` variants, `PaymentBrandConfig(ctaLabel, sections)` — so there is nothing to design here beyond the widget bodies, which come from `prototype/brand-slots` (`lib/payment/widgets.dart`). The prototype's `label`/`amountMinor` fields become the real `LineItem.description` and `Money`, formatted through Task 4's `formatMoney`.

`CustomSection` is the escape hatch a Brand uses for a section `payment` has never heard of. It is not exercised by Retail or Utility (§6's table gives both only known sections) — Task 12's guard test covers it with a synthetic Brand instead, which is the honest place for it.

- [ ] **Step 1: Write the failing tests for the config**

```dart
// test/features/payment/payment_brand_config_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/features/payment/payment.dart';

void main() {
  test('is a BrandFeatureConfig, so feature<T>() can find it', () {
    const config = PaymentBrandConfig(
      ctaLabel: 'Pay now',
      sections: [SummarySection(), PayButtonSection()],
    );
    expect(config, isA<BrandFeatureConfig>());
  });

  test('carries the Brand copy and section order verbatim', () {
    const config = PaymentBrandConfig(
      ctaLabel: 'Confirm payment',
      sections: [
        SummarySection(),
        BillBreakdownSection(),
        PayButtonSection(),
      ],
    );

    expect(config.ctaLabel, 'Confirm payment');
    expect(config.sections, [
      isA<SummarySection>(),
      isA<BillBreakdownSection>(),
      isA<PayButtonSection>(),
    ]);
  });

  test('a CustomSection carries a builder and a non-empty debug label', () {
    final section = CustomSection(
      (context, payment) => const Text('brand-specific'),
      debugLabel: 'loyalty-points',
    );

    expect(section.debugLabel, 'loyalty-points');
    expect(section, isA<PaymentSection>());
  });

  test('the section hierarchy is exhaustively switchable', () {
    String name(PaymentSection section) => switch (section) {
      SummarySection() => 'summary',
      PromoBannerSection() => 'promo',
      BillBreakdownSection() => 'breakdown',
      PayButtonSection() => 'pay',
      CustomSection(:final debugLabel) => debugLabel,
    };

    expect(name(const SummarySection()), 'summary');
    expect(name(const PromoBannerSection()), 'promo');
    expect(name(const BillBreakdownSection()), 'breakdown');
    expect(name(const PayButtonSection()), 'pay');
    expect(
      name(CustomSection((_, _) => const SizedBox.shrink(), debugLabel: 'x')),
      'x',
    );
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/payment_brand_config_test.dart`
Expected: FAIL to compile — `Undefined class 'PaymentBrandConfig'`

- [ ] **Step 3: Implement the config and sections**

```dart
// lib/features/payment/src/presentation/payment_brand_config.dart
import 'package:flutter/widgets.dart';

import '../../../../brand_engine/brand_engine.dart';
import '../domain/payment.dart';

/// Builds a Brand-supplied section. `payment` calls it and renders whatever comes back without
/// knowing what it is.
typedef SectionBuilder = Widget Function(BuildContext context, Payment payment);

/// A building block of the payment screen that a Brand orders. Sealed so the page's switch stays
/// exhaustive over everything `payment` knows how to draw, with [CustomSection] as the escape
/// hatch for content `payment` has never heard of. See CONTEXT.md → Section,
/// docs/architecture.md §6 (a closed enum and fixed slots were both rejected there).
sealed class PaymentSection {
  const PaymentSection();
}

final class SummarySection extends PaymentSection {
  const SummarySection();
}

final class PromoBannerSection extends PaymentSection {
  const PromoBannerSection();
}

final class BillBreakdownSection extends PaymentSection {
  const BillBreakdownSection();
}

final class PayButtonSection extends PaymentSection {
  const PayButtonSection();
}

/// Brand-supplied; `payment` renders it blind. [debugLabel] exists so the completeness guard and
/// any error message can name the section without calling the builder.
final class CustomSection extends PaymentSection {
  const CustomSection(this.builder, {required this.debugLabel});

  final SectionBuilder builder;
  final String debugLabel;
}

/// A Brand's slice of payment configuration: its call-to-action copy and the order of its
/// Sections. Looked up with `BrandConfig.feature<PaymentBrandConfig>()`. See
/// docs/architecture.md §6.
class PaymentBrandConfig extends BrandFeatureConfig {
  const PaymentBrandConfig({required this.ctaLabel, required this.sections});

  final String ctaLabel;
  final List<PaymentSection> sections;
}
```

```dart
// lib/features/payment/payment.dart — add this line
export 'src/presentation/payment_brand_config.dart';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/payment_brand_config_test.dart`
Expected: `00:00 +4: All tests passed!`

- [ ] **Step 5: Write the failing tests for the section widgets**

```dart
// test/features/payment/section_widgets_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/core/money.dart';
import 'package:payment_module/features/payment/payment.dart';

const _tokens = BrandTokens(
  seed: Color(0xFFE65100),
  accent: Color(0xFFFFB300),
  radius: 20,
  density: VisualDensity.comfortable,
  spacing: 16,
  scanMinDuration: Duration(milliseconds: 2000),
  headlineWeight: FontWeight.w700,
);

const _payment = Payment(
  reference: 'PAY-DEMO-0001',
  amount: Money(amountMinor: 4200, currency: 'USD'),
  payee: 'Acme Utilities',
  lineItems: [
    LineItem(
      description: 'Monthly service',
      amount: Money(amountMinor: 3200, currency: 'USD'),
    ),
    LineItem(
      description: 'Usage overage',
      amount: Money(amountMinor: 1000, currency: 'USD'),
    ),
  ],
);

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: ThemeData(extensions: const [_tokens]),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  group('SummaryCard', () {
    testWidgets('shows the formatted amount, the payee and the reference', (tester) async {
      await _pump(tester, const SummaryCard(payment: _payment));

      expect(find.text(r'$42.00'), findsOneWidget);
      expect(find.textContaining('Acme Utilities'), findsOneWidget);
      expect(find.textContaining('PAY-DEMO-0001'), findsOneWidget);
    });

    testWidgets('renders the amount at the Brand headline weight', (tester) async {
      await _pump(tester, const SummaryCard(payment: _payment));

      final amount = tester.widget<Text>(find.text(r'$42.00'));
      expect(amount.style?.fontWeight, FontWeight.w700);
    });
  });

  group('BillBreakdown', () {
    testWidgets('lists every line item with its amount, plus a total', (tester) async {
      await _pump(tester, const BillBreakdown(payment: _payment));

      expect(find.text('Monthly service'), findsOneWidget);
      expect(find.text(r'$32.00'), findsOneWidget);
      expect(find.text('Usage overage'), findsOneWidget);
      expect(find.text(r'$10.00'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text(r'$42.00'), findsOneWidget);
    });
  });

  group('PromoBanner', () {
    testWidgets('renders promotional copy without touching the amount', (tester) async {
      await _pump(tester, const PromoBanner());

      expect(find.byIcon(Icons.local_offer), findsOneWidget);
      expect(find.textContaining(r'$'), findsNothing);
    });
  });

  group('PayButton', () {
    testWidgets('uses the Brand call-to-action copy and fires when enabled', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        PayButton(label: 'Pay now', enabled: true, onPressed: () => taps++),
      );

      expect(find.text('Pay now'), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      expect(taps, 1);
    });

    testWidgets('is inert when disabled', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        PayButton(label: 'Pay now', enabled: false, onPressed: () => taps++),
      );

      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('says it is still checking when the label is the checking one', (tester) async {
      await _pump(
        tester,
        const PayButton(label: 'Checking…', enabled: false, onPressed: null),
      );

      expect(find.text('Checking…'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 6: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/section_widgets_test.dart`
Expected: FAIL to compile — `Undefined class 'SummaryCard'`

- [ ] **Step 7: Implement the section widgets**

```dart
// lib/features/payment/src/presentation/section_widgets.dart
import 'package:flutter/material.dart';

import '../../../../brand_engine/brand_engine.dart';
import '../domain/payment.dart';
import 'format_money.dart';

/// The Payment's headline: what is owed, to whom, under which reference. Reads Brand tokens for
/// its shape and weight; it never asks which Brand is active (docs/architecture.md §2
/// principle 5).
class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.payment});

  final Payment payment;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing * 1.25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Amount due', style: text.labelLarge),
            Text(
              formatMoney(payment.amount),
              style: text.displaySmall?.copyWith(
                fontWeight: tokens.headlineWeight,
              ),
            ),
            SizedBox(height: tokens.spacing / 2),
            Text(
              'To ${payment.payee} · ${payment.reference}',
              style: text.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Retail's Brand feature: promotional content. Purely visual — it never changes the amount
/// (CONTEXT.md → Promo Banner).
class PromoBanner extends StatelessWidget {
  const PromoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(tokens.spacing * 1.25),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.radius),
        gradient: LinearGradient(colors: [scheme.primary, scheme.secondary]),
      ),
      child: Row(
        children: [
          Icon(Icons.local_offer, color: scheme.onPrimary),
          SizedBox(width: tokens.spacing),
          Expanded(
            child: Text(
              'Member offer · earn points on this payment',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.onPrimary,
                fontWeight: tokens.headlineWeight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Utility's Brand feature: the Payment's Line Items itemised, with a total that is the
/// Payment's own amount rather than a re-derived sum (CONTEXT.md → Bill Breakdown).
class BillBreakdown extends StatelessWidget {
  const BillBreakdown({super.key, required this.payment});

  final Payment payment;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Bill breakdown', style: text.titleSmall),
            ),
            const Divider(),
            for (final item in payment.lineItems)
              Padding(
                padding: EdgeInsets.symmetric(vertical: tokens.spacing / 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(item.description, style: text.bodyMedium),
                    ),
                    Text(formatMoney(item.amount), style: text.bodyMedium),
                  ],
                ),
              ),
            const Divider(),
            Row(
              children: [
                Expanded(child: Text('Total', style: text.titleSmall)),
                Text(formatMoney(payment.amount), style: text.titleSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The call to action. Its copy is Brand configuration ([label]); whether it is live is the
/// `canPay` derived rule's answer, computed by the page (docs/architecture.md §7).
class PayButton extends StatelessWidget {
  const PayButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: const Icon(Icons.lock),
      label: Text(label),
    ),
  );
}
```

```dart
// lib/features/payment/payment.dart — add this line
export 'src/presentation/section_widgets.dart';
```

- [ ] **Step 8: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/section_widgets_test.dart`
Expected: `00:00 +7: All tests passed!`

If `find.text(r'$42.00')` matches two widgets in the `BillBreakdown` test (the total and, on some formatter locales, a line item), make the expectation `findsWidgets` for the total only after confirming by eye which widgets matched — don't delete the assertion.

- [ ] **Step 9: Verify lint and commit**

Run: `~/fvm/versions/3.44.6/bin/dart analyze --fatal-infos`
Expected: `No issues found!`

```bash
git add lib/features/payment test/features/payment/payment_brand_config_test.dart test/features/payment/section_widgets_test.dart
git commit -m "feat(payment): add PaymentBrandConfig, the sealed PaymentSection, and the section widgets"
```

---

### Task 9: `ResultView`

**Files:**
- Create: `lib/features/payment/src/presentation/result_view.dart`
- Modify: `lib/features/payment/payment.dart` (add one export line)
- Test: `test/features/payment/result_view_test.dart`

The `Completed` phase's face. A state of the same route, never a separate page (CONTEXT.md → Result View, §11.1(ii) — that is what keeps the Secure Window held until the user leaves). It takes the terminal `PaymentJobProgress` and, per §7, draws the posture caveat by reusing Task 7's `PostureBanner` rather than inventing second copy for the same facts.

Retry is offered for a failure and not for a success — §7.1's table has `RetryPressed` transition only from `Completed(Failed)`.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/payment/payment.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

const _tokens = BrandTokens(
  seed: Color(0xFFE65100),
  accent: Color(0xFFFFB300),
  radius: 20,
  density: VisualDensity.comfortable,
  spacing: 16,
  scanMinDuration: Duration(milliseconds: 2000),
  headlineWeight: FontWeight.w700,
);

final _receipt = PaymentReceipt(
  reference: 'PAY-DEMO-0001',
  completedAt: DateTime.utc(2026, 9, 17, 8, 30),
);

Future<void> _pump(
  WidgetTester tester, {
  required PaymentJobProgress outcome,
  PolicyVerdict? verdict,
  VoidCallback? onRetry,
}) => tester.pumpWidget(
  MaterialApp(
    theme: ThemeData(extensions: const [_tokens]),
    home: Scaffold(
      body: SingleChildScrollView(
        child: ResultView(
          outcome: outcome,
          verdict: verdict,
          onRetry: onRetry ?? () {},
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('a success shows the receipt reference and offers no retry', (tester) async {
    await _pump(tester, outcome: Succeeded(_receipt));

    expect(find.textContaining('complete'), findsOneWidget);
    expect(find.textContaining('PAY-DEMO-0001'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a declined payment says so and offers retry', (tester) async {
    var retries = 0;
    await _pump(
      tester,
      outcome: const Failed(PaymentFailure.declined),
      onRetry: () => retries++,
    );

    expect(find.textContaining('declined'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
  });

  testWidgets('a timeout and an unavailable processor each get their own wording', (tester) async {
    await _pump(tester, outcome: const Failed(PaymentFailure.timedOut));
    expect(find.textContaining('took too long'), findsOneWidget);

    await _pump(tester, outcome: const Failed(PaymentFailure.serviceUnavailable));
    expect(find.textContaining('could not be reached'), findsOneWidget);
  });

  testWidgets('a posture caveat rides along with a success', (tester) async {
    await _pump(
      tester,
      outcome: Succeeded(_receipt),
      verdict: const PolicyVerdict(
        blockers: {},
        warnings: {ThreatKind.screenRecording},
        notices: {},
      ),
    );

    expect(find.byType(PostureBanner), findsOneWidget);
    expect(find.textContaining('recording'), findsOneWidget);
    expect(find.textContaining('complete'), findsOneWidget);
  });

  testWidgets('no caveat renders when the verdict is clear', (tester) async {
    await _pump(
      tester,
      outcome: Succeeded(_receipt),
      verdict: const PolicyVerdict(blockers: {}, warnings: {}, notices: {}),
    );

    expect(find.byType(Card), findsOneWidget); // the result card only
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/result_view_test.dart`
Expected: FAIL to compile — `Undefined class 'ResultView'`

- [ ] **Step 3: Implement**

```dart
// lib/features/payment/src/presentation/result_view.dart
import 'package:flutter/material.dart';

import '../../../../brand_engine/brand_engine.dart';
import '../../../security_guard/security_guard.dart'
    show PolicyVerdict, PostureBanner;
import '../domain/payment_job_progress.dart';

/// What the payment screen shows once the Payment Job has completed — a phase of the same route,
/// never a separate page, which is what keeps the Secure Window held until the user leaves
/// (CONTEXT.md → Result View, docs/architecture.md §11.1). Retry is offered for a failure only:
/// §7.1's table transitions out of `Completed` on `RetryPressed` from a failure alone.
///
/// [verdict] is the live Policy Verdict; if the posture degraded while the job ran, the caveat
/// rides along here (§7) drawn by the same [PostureBanner] the confirmation view uses.
class ResultView extends StatelessWidget {
  const ResultView({
    super.key,
    required this.outcome,
    required this.onRetry,
    this.verdict,
  });

  final PaymentJobProgress outcome;
  final VoidCallback onRetry;
  final PolicyVerdict? verdict;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final (icon, color, headline, detail) = switch (outcome) {
      Succeeded(:final receipt) => (
        Icons.check_circle,
        scheme.primary,
        'Payment complete',
        'Receipt ${receipt.reference} · ${_time(receipt.completedAt)}',
      ),
      Failed(:final failure) => (
        Icons.error_outline,
        scheme.error,
        _failureHeadline(failure),
        _failureDetail(failure),
      ),
      // `Running` never reaches the Completed phase — §7.1 only builds it from a terminal
      // JobProgressed — but the switch must be exhaustive over the sealed hierarchy.
      Running() => (
        Icons.hourglass_empty,
        scheme.outline,
        'Still processing',
        'This payment has not finished yet.',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PostureBanner(verdict: verdict),
        Card(
          child: Padding(
            padding: EdgeInsets.all(tokens.spacing * 1.25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 40),
                SizedBox(height: tokens.spacing),
                Text(
                  headline,
                  style: text.headlineSmall?.copyWith(
                    fontWeight: tokens.headlineWeight,
                  ),
                ),
                SizedBox(height: tokens.spacing / 2),
                Text(detail, style: text.bodyMedium),
                if (outcome is Failed) ...[
                  SizedBox(height: tokens.spacing),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _failureHeadline(PaymentFailure failure) => switch (failure) {
    PaymentFailure.declined => 'Payment declined',
    PaymentFailure.timedOut => 'Payment timed out',
    PaymentFailure.serviceUnavailable => 'Payment not processed',
  };

  static String _failureDetail(PaymentFailure failure) => switch (failure) {
    PaymentFailure.declined =>
      'The payment was declined. Nothing has been charged.',
    PaymentFailure.timedOut =>
      'Processing took too long and was stopped. Nothing has been charged.',
    PaymentFailure.serviceUnavailable =>
      'The payment service could not be reached. Nothing has been charged.',
  };

  /// Local wall-clock time, to the minute — enough to identify the receipt without pulling in
  /// date-format configuration the architecture never asked for.
  static String _time(DateTime completedAt) {
    final local = completedAt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
```

```dart
// lib/features/payment/payment.dart — add this line
export 'src/presentation/result_view.dart';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/result_view_test.dart`
Expected: `00:00 +5: All tests passed!`

- [ ] **Step 5: Verify lint**

Run: `~/fvm/versions/3.44.6/bin/dart analyze --fatal-infos`
Expected: `No issues found!` — note this file imports `security_guard`'s **barrel**, which is what `security_guard_via_barrel` requires; a direct `src/` import would fire it.

- [ ] **Step 6: Commit**

```bash
git add lib/features/payment test/features/payment/result_view_test.dart
git commit -m "feat(payment): add ResultView"
```

---

### Task 10: `PaymentConfirmationPage`

**Files:**
- Create: `lib/features/payment/src/presentation/payment_confirmation_page.dart`
- Modify: `lib/features/payment/payment.dart` (add one export line)

The screen. It is the only place the two blocs of §7 meet, and it meets them the way §7 insists: **no `BlocListener` relaying events between them**. The flow bloc is built with the Brand's `scanMinDuration`; the posture cubit with the Brand's `PosturePolicy`; the one fact that crosses travels inside `PayPressed(verdict)`, read from the cubit at the moment of the tap.

Four structural decisions, each with its reason:

1. **Ports come from `GetIt.I`, the two blocs are built here, not registered.** §4 says "BLoCs are factories", but both need Brand-scoped arguments that only exist once there's a `BuildContext` inside `BrandScope` — a `GetIt` factory has no context. So `registerSecurityModule`/`registerPaymentModule` register the *ports* (they already do), and this page composes the blocs from them. That keeps Task 14's `setupLocator` free of widget concerns.
2. **`_ScanPhaseView` is `const`.** §12.1 wants the `RepaintBoundary(child: CustomPaint)` inside "a const-constructible widget *above* the `BlocBuilder` subtree". Returning the identical `const _ScanPhaseView()` instance on every build means Flutter's element for it sees an unchanged widget and skips rebuilding the subtree entirely — so a `PaymentLoaded` emission during the Scan phase cannot rebuild the animating scan. That is the mechanism the spec is pointing at, achieved without hoisting the scan outside the phase it belongs to.
3. **`PopScope(canPop: ...)` wraps the `Scaffold`, not the route.** §11.1(iv) makes back-blocking during `Processing` the page's rule and explicitly not the Secure Window scope's.
4. **`SecureSessionScope` sits above both blocs' provider subtree but inside the page**, so the flag's lifetime is the page's lifetime (§11), and the Result View — a phase, not a route — stays inside it.

- [ ] **Step 1: Implement**

```dart
// lib/features/payment/src/presentation/payment_confirmation_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../brand_engine/brand_engine.dart';
import '../../../security_guard/security_guard.dart';
import '../domain/payment.dart';
import '../domain/payment_job_progress.dart';
import '../domain/payment_processor.dart';
import '../domain/payment_repository.dart';
import 'can_pay.dart';
import 'payment_brand_config.dart';
import 'payment_confirmation_bloc.dart';
import 'payment_confirmation_event.dart';
import 'payment_confirmation_state.dart';
import 'result_view.dart';
import 'section_widgets.dart';

/// The Payment Confirmation screen. Builds the two units of docs/architecture.md §7 — the flow
/// bloc and the posture cubit — from the ports in the locator plus this Brand's configuration,
/// and holds the Secure Window for as long as it is mounted (§11).
///
/// The two blocs never talk to each other: the only posture fact the flow needs rides inside
/// `PayPressed(verdict)`, and every cross-concern rule is the pure `canPay` function (§7).
class PaymentConfirmationPage extends StatelessWidget {
  const PaymentConfirmationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final brand = BrandScope.of(context);
    final locator = GetIt.I;
    return MultiBlocProvider(
      providers: [
        BlocProvider<SecurityPostureCubit>(
          create: (_) => SecurityPostureCubit(
            locator<SecurityEnvironment>(),
            brand.feature<SecurityBrandConfig>().policy,
          ),
        ),
        BlocProvider<PaymentConfirmationBloc>(
          create: (_) => PaymentConfirmationBloc(
            locator<PaymentRepository>(),
            locator<PaymentProcessor>(),
            scanMinDuration: brand.tokens.scanMinDuration,
          )..add(const Started()),
        ),
      ],
      child: SecureSessionScope(
        controller: locator<SecureWindowController>(),
        child: const _PaymentConfirmationView(),
      ),
    );
  }
}

class _PaymentConfirmationView extends StatefulWidget {
  const _PaymentConfirmationView();

  @override
  State<_PaymentConfirmationView> createState() =>
      _PaymentConfirmationViewState();
}

class _PaymentConfirmationViewState extends State<_PaymentConfirmationView> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // §7.2: coming back to the screen silently re-runs the one-shot checks. The scope beside us
    // re-asserts the window flag on the same signal — one lifetime, two owners (§11).
    _lifecycle = AppLifecycleListener(
      onResume: () => context.read<SecurityPostureCubit>().onResumed(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = BrandScope.of(context);
    final config = brand.feature<PaymentBrandConfig>();
    final spacing = context.tokens.spacing;

    return BlocBuilder<PaymentConfirmationBloc, PaymentConfirmationState>(
      builder: (context, flow) => PopScope(
        // §11.1(iv): the page blocks back while the Payment Job runs; the Secure Window scope
        // never blocks navigation.
        canPop: flow.phase is! Processing,
        child: Scaffold(
          appBar: AppBar(title: Text(brand.displayName)),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: ListView(
                  padding: EdgeInsets.all(spacing),
                  children: _bodyFor(context, flow, config, spacing),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _bodyFor(
    BuildContext context,
    PaymentConfirmationState flow,
    PaymentBrandConfig config,
    double spacing,
  ) {
    switch (flow.phase) {
      case Scanning():
        // A const instance: an emission during the Scan phase hands the element the same widget
        // and the animating scan is never rebuilt (§12.1).
        return const [_ScanPhaseView()];

      case AwaitingConfirmation():
        return [
          const _PostureBannerSlot(),
          for (final section in config.sections) ...[
            SizedBox(height: spacing),
            _sectionWidget(context, section, flow.payment, config.ctaLabel),
          ],
        ];

      case Processing(:final percent):
        return [
          const _PostureBannerSlot(),
          if (flow.payment case final payment?) ...[
            SizedBox(height: spacing),
            SummaryCard(payment: payment),
          ],
          SizedBox(height: spacing * 2),
          LinearProgressIndicator(value: percent / 100),
          SizedBox(height: spacing),
          Text('Processing payment… $percent%', textAlign: TextAlign.center),
        ];

      case Completed(:final outcome):
        return [
          SizedBox(height: spacing),
          _ResultSlot(outcome: outcome),
        ];
    }
  }

  Widget _sectionWidget(
    BuildContext context,
    PaymentSection section,
    Payment? payment,
    String ctaLabel,
  ) => switch (section) {
    // A Payment that hasn't loaded yet leaves its Sections empty rather than showing a spinner
    // per Section; the Scan phase has already covered that wait in the normal case (§7).
    SummarySection() => payment == null
        ? const SizedBox.shrink()
        : SummaryCard(payment: payment),
    PromoBannerSection() => const PromoBanner(),
    BillBreakdownSection() => payment == null
        ? const SizedBox.shrink()
        : BillBreakdown(payment: payment),
    PayButtonSection() => _PayButtonSlot(ctaLabel: ctaLabel),
    CustomSection(:final builder) => payment == null
        ? const SizedBox.shrink()
        : builder(context, payment),
  };
}

/// The scan, isolated. Const so a flow emission cannot rebuild it (§12.1).
class _ScanPhaseView extends StatelessWidget {
  const _ScanPhaseView();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      SizedBox(height: 32),
      SecurityScanView(),
      SizedBox(height: 24),
      Text('Checking this device…', textAlign: TextAlign.center),
    ],
  );
}

/// Draws the Policy Verdict. Watches the cubit only — no relay through the flow bloc (§7).
class _PostureBannerSlot extends StatelessWidget {
  const _PostureBannerSlot();

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<SecurityPostureCubit, PostureState>(
        builder: (context, posture) => PostureBanner(verdict: posture.verdict),
      );
}

/// The one place both states are read at once — and it reads them through the pure `canPay`
/// rule rather than re-deriving the condition inline (§7).
class _PayButtonSlot extends StatelessWidget {
  const _PayButtonSlot({required this.ctaLabel});

  final String ctaLabel;

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<PaymentConfirmationBloc>().state;
    final posture = context.watch<SecurityPostureCubit>().state;
    final verdict = posture.verdict;

    return PayButton(
      // §7: the CTA says it is still checking until the first assessment lands.
      label: posture.hasFirstAssessment ? ctaLabel : 'Checking…',
      enabled: canPay(flow, posture),
      onPressed: verdict == null
          ? null
          : () => context.read<PaymentConfirmationBloc>().add(
              PayPressed(verdict),
            ),
    );
  }
}

class _ResultSlot extends StatelessWidget {
  const _ResultSlot({required this.outcome});

  final PaymentJobProgress outcome;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<SecurityPostureCubit, PostureState>(
        builder: (context, posture) => ResultView(
          outcome: outcome,
          verdict: posture.verdict,
          onRetry: () => context.read<PaymentConfirmationBloc>().add(
            const RetryPressed(),
          ),
        ),
      );
}
```

```dart
// lib/features/payment/payment.dart — add this line
export 'src/presentation/payment_confirmation_page.dart';
```

- [ ] **Step 2: Verify it compiles and lints clean**

Run: `~/fvm/versions/3.44.6/bin/dart analyze --fatal-infos`
Expected: `No issues found!` The page imports `security_guard`'s barrel (never its `src/`) and no `data/` file, so neither `security_guard_via_barrel` nor `presentation_no_data` fires.

Run: `~/fvm/versions/3.44.6/bin/flutter test`
Expected: still `All tests passed!` — nothing exercises the page yet; Task 11 does that.

- [ ] **Step 3: Commit**

```bash
git add lib/features/payment
git commit -m "feat(payment): add PaymentConfirmationPage"
```

---

### Task 11: `PaymentConfirmationPage` widget tests

**Files:**
- Test: `test/features/payment/payment_confirmation_page_test.dart`

§14 asks for "page widget tests" on `features/payment`. These drive the real page with the real `di.dart` registrations and the scripted fakes from `test/support/fakes/`, so they exercise the locator wiring too.

The tests build their own Brands rather than importing `lib/brands/` — that doesn't exist until Task 12, and a page test that depends on shipping Brand values would fail for the wrong reason when someone re-tunes Retail's copy.

- [ ] **Step 1: Write the tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/core/brand_id.dart';
import 'package:payment_module/core/money.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/payment/di.dart';
import 'package:payment_module/features/payment/payment.dart';
import 'package:payment_module/features/security_guard/di.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

import '../../support/fakes/fake_payment_processor.dart';
import '../../support/fakes/fake_payment_repository.dart';
import '../../support/fakes/fake_secure_window.dart';
import '../../support/fakes/fake_security_environment.dart';

const _scanDuration = Duration(milliseconds: 20);

const _payment = Payment(
  reference: 'PAY-DEMO-0001',
  amount: Money(amountMinor: 4200, currency: 'USD'),
  payee: 'Acme Utilities',
  lineItems: [
    LineItem(
      description: 'Monthly service',
      amount: Money(amountMinor: 3200, currency: 'USD'),
    ),
    LineItem(
      description: 'Usage overage',
      amount: Money(amountMinor: 1000, currency: 'USD'),
    ),
  ],
);

final _clearPosture = SecurityPosture(const [
  ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
  ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
]);

final _rootedPosture = SecurityPosture(const [
  ThreatAssessment(kind: ThreatKind.rooted, result: Detected()),
  ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
]);

PosturePolicy _blockingPolicy() => PosturePolicy(
  onDetected: {
    ThreatKind.rooted: DetectedResponse.block,
    ThreatKind.screenRecording: DetectedResponse.warn,
  },
  onUnavailable: {
    ThreatKind.rooted: UnavailableResponse.allow,
    ThreatKind.screenRecording: UnavailableResponse.allow,
  },
);

BrandConfig _brand({
  List<PaymentSection> sections = const [
    PromoBannerSection(),
    SummarySection(),
    PayButtonSection(),
  ],
  String ctaLabel = 'Pay now',
}) => BrandConfig(
  id: const BrandId('test'),
  displayName: 'Test Brand',
  tokens: const BrandTokens(
    seed: Color(0xFFE65100),
    accent: Color(0xFFFFB300),
    radius: 20,
    density: VisualDensity.comfortable,
    spacing: 16,
    scanMinDuration: _scanDuration,
    headlineWeight: FontWeight.w700,
  ),
  features: [
    PaymentBrandConfig(ctaLabel: ctaLabel, sections: sections),
    SecurityBrandConfig(policy: _blockingPolicy()),
  ],
);

void main() {
  late FakePaymentRepository repository;
  late FakePaymentProcessor processor;
  late FakeSecurityEnvironment environment;
  late FakeSecureWindow window;

  setUp(() {
    repository = FakePaymentRepository();
    processor = FakePaymentProcessor();
    environment = FakeSecurityEnvironment();
    window = FakeSecureWindow();

    GetIt.I.reset();
    registerSecurityModule(GetIt.I, environment: environment, window: window);
    registerPaymentModule(GetIt.I, repository: repository, processor: processor);
  });

  tearDown(() async {
    await processor.dispose();
    await environment.dispose();
    await GetIt.I.reset();
  });

  Future<void> pumpPage(WidgetTester tester, {BrandConfig? brand}) async {
    final config = brand ?? _brand();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildBrandTheme(config),
        home: BrandScope(
          brand: config,
          child: const PaymentConfirmationPage(),
        ),
      ),
    );
    await tester.pump();
  }

  /// Gets past the Scan phase: resolve the load, let the real scan timer elapse.
  Future<void> reachAwaitingConfirmation(
    WidgetTester tester, {
    SecurityPosture? posture,
  }) async {
    repository.completeWith(_payment);
    environment.pushPosture(posture ?? _clearPosture);
    await tester.pump(_scanDuration * 2);
    await tester.pump();
  }

  testWidgets('opens on the Scan phase with the scan animating', (tester) async {
    await pumpPage(tester);

    expect(find.byType(SecurityScanView), findsOneWidget);
    expect(find.byType(PayButton), findsNothing);
  });

  testWidgets('holds the Secure Window while mounted and releases it on dispose', (tester) async {
    await pumpPage(tester);
    expect(window.calls, [true]);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(window.calls, [true, false]);
  });

  testWidgets('renders the Brand sections in the Brand order once confirmation is awaited', (tester) async {
    await pumpPage(tester);
    await reachAwaitingConfirmation(tester);

    expect(find.byType(SecurityScanView), findsNothing);

    final promo = tester.getTopLeft(find.byType(PromoBanner)).dy;
    final summary = tester.getTopLeft(find.byType(SummaryCard)).dy;
    final pay = tester.getTopLeft(find.byType(PayButton)).dy;
    expect(promo, lessThan(summary));
    expect(summary, lessThan(pay));
  });

  testWidgets('a different Brand order renders in that order, with no code change', (tester) async {
    await pumpPage(
      tester,
      brand: _brand(
        ctaLabel: 'Confirm payment',
        sections: const [
          SummarySection(),
          BillBreakdownSection(),
          PayButtonSection(),
        ],
      ),
    );
    await reachAwaitingConfirmation(tester);

    expect(find.byType(PromoBanner), findsNothing);
    expect(find.byType(BillBreakdown), findsOneWidget);
    expect(find.text('Confirm payment'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(SummaryCard)).dy,
      lessThan(tester.getTopLeft(find.byType(BillBreakdown)).dy),
    );
  });

  testWidgets('renders a CustomSection a Brand supplies, unchanged', (tester) async {
    await pumpPage(
      tester,
      brand: _brand(
        sections: [
          const SummarySection(),
          CustomSection(
            (context, payment) => Text('loyalty ${payment.reference}'),
            debugLabel: 'loyalty',
          ),
          const PayButtonSection(),
        ],
      ),
    );
    await reachAwaitingConfirmation(tester);

    expect(find.text('loyalty PAY-DEMO-0001'), findsOneWidget);
  });

  testWidgets('the CTA says it is checking until the first assessment lands', (tester) async {
    await pumpPage(tester);
    repository.completeWith(_payment);
    await tester.pump(_scanDuration * 2);
    await tester.pump();

    expect(find.text('Checking…'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });

  testWidgets('a clear posture enables the CTA, and tapping it starts the Payment Job', (tester) async {
    await pumpPage(tester);
    await reachAwaitingConfirmation(tester);

    expect(find.text('Pay now'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(processor.startCallCount, 1);
    expect(processor.lastStartedPayment, _payment);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('a blocking posture shows the banner and keeps the CTA inert', (tester) async {
    await pumpPage(tester);
    await reachAwaitingConfirmation(tester, posture: _rootedPosture);

    expect(find.byType(PostureBanner), findsOneWidget);
    expect(find.textContaining('blocked'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

    await tester.tap(find.byType(FilledButton), warnIfMissed: false);
    await tester.pump();
    expect(processor.startCallCount, 0);
  });

  testWidgets('progress updates while processing, and back is blocked', (tester) async {
    await pumpPage(tester);
    await reachAwaitingConfirmation(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    processor.pushProgress(const Running(40));
    await tester.pump();

    expect(find.textContaining('40%'), findsOneWidget);
    expect(
      tester.widget<PopScope<Object?>>(find.byType(PopScope<Object?>)).canPop,
      isFalse,
    );
  });

  testWidgets('a succeeded job shows the receipt and no retry', (tester) async {
    await pumpPage(tester);
    await reachAwaitingConfirmation(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    processor.pushProgress(
      Succeeded(
        PaymentReceipt(
          reference: 'PAY-DEMO-0001',
          completedAt: DateTime.utc(2026, 9, 17, 8, 30),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ResultView), findsOneWidget);
    expect(find.textContaining('complete'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a failed job offers retry, which returns to awaiting confirmation', (tester) async {
    await pumpPage(tester);
    await reachAwaitingConfirmation(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    processor.pushProgress(const Failed(PaymentFailure.declined));
    await tester.pump();
    expect(find.textContaining('declined'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();

    expect(find.byType(ResultView), findsNothing);
    expect(find.text('Pay now'), findsOneWidget);
  });

  testWidgets('a posture that degrades while the job runs does not stop it, and shows as a caveat', (tester) async {
    await pumpPage(tester);
    await reachAwaitingConfirmation(tester);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    // Degrade mid-job: the flow bloc never subscribed to posture, so nothing interrupts it (§7).
    environment.pushPosture(
      SecurityPosture(const [
        ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
        ThreatAssessment(kind: ThreatKind.screenRecording, result: Detected()),
      ]),
    );
    await tester.pump();
    processor.pushProgress(
      Succeeded(
        PaymentReceipt(
          reference: 'PAY-DEMO-0001',
          completedAt: DateTime.utc(2026, 9, 17, 8, 30),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('complete'), findsOneWidget);
    expect(find.textContaining('recording'), findsOneWidget);
  });

  testWidgets('returning to the screen re-runs the one-shot checks', (tester) async {
    await pumpPage(tester);
    await reachAwaitingConfirmation(tester);
    final before = environment.assessCallCount;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(environment.assessCallCount, greaterThan(before));
  });
}
```

- [ ] **Step 2: Run them**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/payment/payment_confirmation_page_test.dart`
Expected: `00:0X +13: All tests passed!`

Three failures are plausible here and none of them mean the page is wrong — fix the *test*, and only after confirming by reading the failure:
- **`PopScope<Object?>` type argument.** If `find.byType(PopScope<Object?>)` finds nothing, print the tree (`debugDumpApp()`) and use whatever type argument Flutter 3.44 instantiates.
- **Lifecycle transitions.** If `assessCallCount` doesn't move, `AppLifecycleListener` may need a different transition pair on this platform default; try `paused` → `resumed`. If it still doesn't fire, keep the test but mark it `skip:` with the reason — do not delete it, and report it.
- **A `Succeeded`/`Failed` push arriving before the subscription exists.** The fake's controller is a broadcast stream, so a push with no listener is dropped. If a terminal state seems ignored, add one `await tester.pump()` after the tap so `_onPayPressed`'s `_listenToJob` has run before the push.

- [ ] **Step 3: Run the whole suite and lint**

Run: `~/fvm/versions/3.44.6/bin/flutter test && ~/fvm/versions/3.44.6/bin/dart analyze --fatal-infos`
Expected: all green.

- [ ] **Step 4: Commit**

```bash
git add test/features/payment/payment_confirmation_page_test.dart
git commit -m "test(payment): drive PaymentConfirmationPage through every phase"
```

---

### Task 12: `lib/brands/` — the two Brands, the registry, and §13.1(1)'s completeness guard

**Files:**
- Create: `lib/brands/retail.dart`
- Create: `lib/brands/utility.dart`
- Create: `lib/brands/registry.dart`
- Test: `test/brands/brand_registry_test.dart`

Every value below comes from §6's Brand table. Two things it doesn't give, decided here and flagged as such:

- **`headlineWeight`** — Retail `FontWeight.w700` (fluid, promotional), Utility `FontWeight.w500` (dense, institutional). §6 names the token but not its per-Brand values.
- **`displayName`** — "Retail Shop" and "Utility Pay", matching `CONTEXT.md`'s glossary entries and the `app_name` string resources Plan 4 already put in `android/app/build.gradle.kts`.

**One documented deviation from §13's code sketch.** §13 row 1 writes `const acmeBrand = BrandConfig(...)`. A `BrandConfig` containing a `SecurityBrandConfig` **cannot be `const`**, because `PosturePolicy`'s constructor calls `Map.unmodifiable` and asserts on coverage — neither is a constant expression. The Brands are therefore `final`, not `const`. This costs nothing at runtime (two objects, built once at startup) and keeps `PosturePolicy`'s immutability-and-coverage guard, which is worth more than `const`. Task 21 folds this correction into §13.

- [ ] **Step 1: Write the failing guard test**

This is §13.1(1) verbatim: the test that fails when someone adds a Brand and forgets a piece.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/brands/registry.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/payment/payment.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

void main() {
  test('the registry is not empty', () {
    expect(brandRegistry.all, isNotEmpty);
  });

  test('ids are unique', () {
    final ids = brandRegistry.ids.toList();
    expect(ids.toSet(), hasLength(ids.length));
  });

  for (final brand in brandRegistry.all) {
    group('Brand "${brand.id.value}"', () {
      test('id is a lower-case slug', () {
        expect(brand.id.value, matches(RegExp(r'^[a-z][a-z0-9]*$')));
      });

      test('displayName is non-empty', () {
        expect(brand.displayName.trim(), isNotEmpty);
      });

      test('resolves a PaymentBrandConfig with non-empty CTA copy', () {
        final config = brand.feature<PaymentBrandConfig>();
        expect(config.ctaLabel.trim(), isNotEmpty);
      });

      test('has exactly one SummarySection and one PayButtonSection', () {
        final sections = brand.feature<PaymentBrandConfig>().sections;
        expect(sections.whereType<SummarySection>(), hasLength(1));
        expect(sections.whereType<PayButtonSection>(), hasLength(1));
      });

      test('every CustomSection carries a non-empty debugLabel', () {
        final sections = brand.feature<PaymentBrandConfig>().sections;
        for (final custom in sections.whereType<CustomSection>()) {
          expect(custom.debugLabel.trim(), isNotEmpty);
        }
      });

      test('resolves a SecurityBrandConfig whose policy covers every ThreatKind', () {
        final policy = brand.feature<SecurityBrandConfig>().policy;
        for (final kind in ThreatKind.values) {
          expect(policy.onDetected, contains(kind));
          expect(policy.onUnavailable, contains(kind));
        }
      });

      test('builds a theme that carries its BrandTokens', () {
        final theme = buildBrandTheme(brand);
        expect(theme.extension<BrandTokens>(), same(brand.tokens));
      });

      test('is reachable through byId', () {
        expect(brandRegistry.byId(brand.id), same(brand));
      });
    });
  }

  test('Retail and Utility are both registered', () {
    expect(brandRegistry.ids, containsAll(['retail', 'utility']));
  });

  test('the two Brands differ in more than identity — tokens are the whole difference', () {
    final retail = brandRegistry.byId(const BrandId('retail'));
    final utility = brandRegistry.byId(const BrandId('utility'));

    expect(retail.tokens.seed, isNot(utility.tokens.seed));
    expect(retail.tokens.radius, isNot(utility.tokens.radius));
    expect(retail.tokens.scanMinDuration, isNot(utility.tokens.scanMinDuration));
    expect(
      retail.feature<PaymentBrandConfig>().ctaLabel,
      isNot(utility.feature<PaymentBrandConfig>().ctaLabel),
    );
  });
}
```

Add `import 'package:payment_module/core/brand_id.dart';` if the analyzer reports `BrandId` undefined — it's used in the last test.

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/brands/brand_registry_test.dart`
Expected: FAIL to compile — `Target of URI doesn't exist: 'package:payment_module/brands/registry.dart'`

- [ ] **Step 3: Implement Retail**

```dart
// lib/brands/retail.dart
import 'package:flutter/material.dart';

import '../brand_engine/brand_engine.dart';
import '../core/brand_id.dart';
import '../core/threat.dart';
import '../features/payment/payment.dart';
import '../features/security_guard/security_guard.dart';

/// "Brand A (Retail Shop)": warm palette, rounded, fluid, shows the Promo Banner, and warns
/// rather than blocks on an active screen recorder. Values from docs/architecture.md §6.
///
/// `final`, not `const`: `PosturePolicy` cannot be a constant (it copies its maps unmodifiable
/// and asserts ThreatKind coverage), so nothing containing one can be either.
final retailBrand = BrandConfig(
  id: const BrandId('retail'),
  displayName: 'Retail Shop',
  tokens: const BrandTokens(
    seed: Color(0xFFE65100),
    accent: Color(0xFFFFB300),
    radius: 20,
    density: VisualDensity.comfortable,
    spacing: 16,
    scanMinDuration: Duration(milliseconds: 2000),
    headlineWeight: FontWeight.w700,
  ),
  features: [
    const PaymentBrandConfig(
      ctaLabel: 'Pay now',
      sections: [
        PromoBannerSection(),
        SummarySection(),
        PayButtonSection(),
      ],
    ),
    SecurityBrandConfig(
      policy: PosturePolicy(
        onDetected: {
          ThreatKind.rooted: DetectedResponse.block,
          ThreatKind.screenRecording: DetectedResponse.warn,
        },
        onUnavailable: {
          ThreatKind.rooted: UnavailableResponse.allow,
          ThreatKind.screenRecording: UnavailableResponse.allow,
        },
      ),
    ),
  ],
);
```

- [ ] **Step 4: Implement Utility**

```dart
// lib/brands/utility.dart
import 'package:flutter/material.dart';

import '../brand_engine/brand_engine.dart';
import '../core/brand_id.dart';
import '../core/threat.dart';
import '../features/payment/payment.dart';
import '../features/security_guard/security_guard.dart';

/// "Brand B (Utility Pay)": navy/slate, dense, sharp, shows the Bill Breakdown, blocks on either
/// Threat and asks for a notice when a check could not run. Values from docs/architecture.md §6.
final utilityBrand = BrandConfig(
  id: const BrandId('utility'),
  displayName: 'Utility Pay',
  tokens: const BrandTokens(
    seed: Color(0xFF0D2B4E),
    accent: Color(0xFF5C6B7A),
    radius: 4,
    density: VisualDensity.compact,
    spacing: 8,
    scanMinDuration: Duration(milliseconds: 1200),
    headlineWeight: FontWeight.w500,
  ),
  features: [
    const PaymentBrandConfig(
      ctaLabel: 'Confirm payment',
      sections: [
        SummarySection(),
        BillBreakdownSection(),
        PayButtonSection(),
      ],
    ),
    SecurityBrandConfig(
      policy: PosturePolicy(
        onDetected: {
          ThreatKind.rooted: DetectedResponse.block,
          ThreatKind.screenRecording: DetectedResponse.block,
        },
        onUnavailable: {
          ThreatKind.rooted: UnavailableResponse.notice,
          ThreatKind.screenRecording: UnavailableResponse.notice,
        },
      ),
    ),
  ],
);
```

- [ ] **Step 5: Implement the registry**

```dart
// lib/brands/registry.dart
import '../brand_engine/brand_engine.dart';
import 'retail.dart';
import 'utility.dart';

/// Every Brand this binary ships. Adding a Brand is one file plus one line here plus one Gradle
/// flavor — docs/architecture.md §13, whose every step a failing test enforces (§13.1).
final brandRegistry = BrandRegistry([retailBrand, utilityBrand]);
```

- [ ] **Step 6: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/brands/brand_registry_test.dart`
Expected: all green — 4 top-level tests plus 8 per Brand × 2 Brands = `+20`.

- [ ] **Step 7: Verify lint**

Run: `~/fvm/versions/3.44.6/bin/dart analyze --fatal-infos`
Expected: `No issues found!` — `lib/brands/` is composition root, allowed to import everything; no rule targets it.

- [ ] **Step 8: Commit**

```bash
git add lib/brands test/brands/brand_registry_test.dart
git commit -m "feat(brands): add Retail and Utility and the registry completeness guard"
```

---

### Task 13: §13.1(2)'s flavor ↔ registry guard

**Files:**
- Test: `test/brands/flavor_registry_test.dart`

§13.1(2): a test regex-parses `productFlavors { create("…") }` out of `android/app/build.gradle.kts` and asserts set-equality with the registry's ids. It catches the half-done Brand addition — Dart side added, Gradle flavor forgotten, or the reverse — which would otherwise only show up as a build failure or, worse, a successful build of the wrong Brand.

- [ ] **Step 1: Write the test**

```dart
// §13.1(2): the Dart registry and the Gradle flavors must name exactly the same Brands.
// A Brand with no flavor cannot be built; a flavor with no Brand builds and then throws at
// startup when bootstrap() looks its BRAND up.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/brands/registry.dart';

void main() {
  test('every Gradle product flavor has a Brand, and every Brand has a flavor', () {
    final gradle = File('android/app/build.gradle.kts');
    expect(
      gradle.existsSync(),
      isTrue,
      reason: 'run this test from the package root',
    );

    final source = gradle.readAsStringSync();
    final block = RegExp(
      r'productFlavors\s*\{(.*?)\n    \}',
      dotAll: true,
    ).firstMatch(source);
    expect(
      block,
      isNotNull,
      reason: 'could not find the productFlavors block in build.gradle.kts',
    );

    final flavors = RegExp(r'create\("([a-z][a-z0-9]*)"\)')
        .allMatches(block!.group(1)!)
        .map((match) => match.group(1)!)
        .toSet();

    expect(
      flavors,
      isNotEmpty,
      reason: 'the regex matched the block but found no create("…") entries',
    );
    expect(
      flavors,
      brandRegistry.ids.toSet(),
      reason:
          'Gradle flavors and registry Brands have drifted — see docs/architecture.md §13',
    );
  });
}
```

- [ ] **Step 2: Run it**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/brands/flavor_registry_test.dart`
Expected: `00:00 +1: All tests passed!` — Plan 4 created `retail` and `utility` flavors and Task 12 registered those two Brands.

If the `productFlavors` block regex doesn't match, read `android/app/build.gradle.kts` and adjust the closing-brace pattern to that file's actual indentation. Keep the two-sided set equality; a one-sided `containsAll` would miss exactly the drift this test exists to catch.

- [ ] **Step 3: Commit**

```bash
git add test/brands/flavor_registry_test.dart
git commit -m "test(brands): assert Gradle flavors and the Brand registry agree"
```

---

### Task 14: `setupLocator`

**Files:**
- Create: `lib/app/locator.dart`
- Test: `test/app/locator_test.dart`

§4: "`lib/app/locator.dart` registers the `BrandConfig` singleton first and then calls both." It takes an optional `GetIt` so the test can use a fresh instance instead of mutating the global one.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:payment_module/app/locator.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/brands/registry.dart';
import 'package:payment_module/core/brand_id.dart';
import 'package:payment_module/features/payment/payment.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

void main() {
  late GetIt locator;

  setUp(() => locator = GetIt.asNewInstance());
  tearDown(() => locator.reset());

  test('registers the Brand it was given', () {
    final brand = brandRegistry.byId(const BrandId('utility'));
    setupLocator(brand, locator: locator);

    expect(locator<BrandConfig>(), same(brand));
  });

  test('registers both features\' ports', () {
    setupLocator(brandRegistry.byId(const BrandId('retail')), locator: locator);

    expect(locator<PaymentRepository>(), isA<InMemoryPaymentRepository>());
    expect(locator.isRegistered<PaymentProcessor>(), isTrue);
    expect(locator.isRegistered<SecurityEnvironment>(), isTrue);
    expect(locator.isRegistered<SecureWindow>(), isTrue);
    expect(locator.isRegistered<SecureWindowController>(), isTrue);
  });

  test('the ports are lazy — registering does not touch the platform', () {
    setupLocator(brandRegistry.byId(const BrandId('retail')), locator: locator);

    // Resolving the channel-backed adapters would be fine too (their constructors don't call
    // the platform), but this asserts the registration itself is inert.
    expect(locator<BrandConfig>().id.value, 'retail');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/app/locator_test.dart`
Expected: FAIL to compile — `Target of URI doesn't exist: 'package:payment_module/app/locator.dart'`

- [ ] **Step 3: Implement**

```dart
// lib/app/locator.dart
import 'package:get_it/get_it.dart';

import '../brand_engine/brand_engine.dart';
import '../features/payment/di.dart';
import '../features/security_guard/di.dart';

/// Wires the app: the active Brand first, then each feature's ports through its own `di.dart`
/// (docs/architecture.md §4). Pass [locator] to wire a fresh `GetIt` in a test; production uses
/// the shared instance, which is what `PaymentConfirmationPage` resolves from.
void setupLocator(BrandConfig brand, {GetIt? locator}) {
  final getIt = locator ?? GetIt.I;
  getIt.registerSingleton<BrandConfig>(brand);
  registerSecurityModule(getIt);
  registerPaymentModule(getIt);
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/app/locator_test.dart`
Expected: `00:00 +3: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/app/locator.dart test/app/locator_test.dart
git commit -m "feat(app): add setupLocator"
```

---

### Task 15: `PaymentApp`

**Files:**
- Create: `lib/app/payment_app.dart`
- Test: `test/app/payment_app_test.dart`

§4: `app/payment_app.dart` is `MaterialApp` + `BrandScope` + `PaymentConfirmationPage`. The theme comes from `buildBrandTheme` (so `context.tokens` resolves), the non-visual config from `BrandScope` (so `feature<T>()` resolves) — the two delivery mechanisms §6 describes, side by side.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:payment_module/app/locator.dart';
import 'package:payment_module/app/payment_app.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/brands/registry.dart';
import 'package:payment_module/core/brand_id.dart';
import 'package:payment_module/features/payment/payment.dart';

import '../support/fakes/fake_payment_processor.dart';
import '../support/fakes/fake_payment_repository.dart';
import '../support/fakes/fake_secure_window.dart';
import '../support/fakes/fake_security_environment.dart';

void main() {
  late FakePaymentProcessor processor;
  late FakeSecurityEnvironment environment;

  setUp(() {
    processor = FakePaymentProcessor();
    environment = FakeSecurityEnvironment();
    GetIt.I.reset();
    // setupLocator would register the channel adapters; the page only needs the ports to exist,
    // so register fakes directly and keep this test off the platform.
    GetIt.I.registerSingleton<BrandConfig>(
      brandRegistry.byId(const BrandId('retail')),
    );
    registerFakePorts(
      repository: FakePaymentRepository(),
      processor: processor,
      environment: environment,
      window: FakeSecureWindow(),
    );
  });

  tearDown(() async {
    await processor.dispose();
    await environment.dispose();
    await GetIt.I.reset();
  });

  testWidgets('builds the Brand theme and puts the Brand in scope above the page', (tester) async {
    final brand = brandRegistry.byId(const BrandId('retail'));
    await tester.pumpWidget(PaymentApp(brand: brand));
    await tester.pump();

    expect(find.byType(PaymentConfirmationPage), findsOneWidget);

    final context = tester.element(find.byType(PaymentConfirmationPage));
    expect(BrandScope.of(context), same(brand));
    expect(Theme.of(context).extension<BrandTokens>(), same(brand.tokens));
    expect(find.text('Retail Shop'), findsOneWidget); // the AppBar title
  });

  testWidgets('a different Brand themes and titles the same widget tree', (tester) async {
    final brand = brandRegistry.byId(const BrandId('utility'));
    GetIt.I.unregister<BrandConfig>();
    GetIt.I.registerSingleton<BrandConfig>(brand);

    await tester.pumpWidget(PaymentApp(brand: brand));
    await tester.pump();

    expect(find.text('Utility Pay'), findsOneWidget);
    final context = tester.element(find.byType(PaymentConfirmationPage));
    expect(Theme.of(context).visualDensity, VisualDensity.compact);
  });
}
```

This test needs a small shared helper so it and Task 11's test agree on how fakes get registered. Add it to `test/support/fakes/` as part of this task:

```dart
// test/support/fakes/register_fake_ports.dart
import 'package:get_it/get_it.dart';
import 'package:payment_module/features/payment/di.dart';
import 'package:payment_module/features/security_guard/di.dart';

import 'fake_payment_processor.dart';
import 'fake_payment_repository.dart';
import 'fake_secure_window.dart';
import 'fake_security_environment.dart';

/// Registers both features' ports against the shared `GetIt` with scripted fakes — what a widget
/// test needs so `PaymentConfirmationPage` can resolve its ports without touching the platform.
void registerFakePorts({
  required FakePaymentRepository repository,
  required FakePaymentProcessor processor,
  required FakeSecurityEnvironment environment,
  required FakeSecureWindow window,
  GetIt? locator,
}) {
  final getIt = locator ?? GetIt.I;
  registerSecurityModule(getIt, environment: environment, window: window);
  registerPaymentModule(getIt, repository: repository, processor: processor);
}
```

Add `import '../support/fakes/register_fake_ports.dart';` to the test above.

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/app/payment_app_test.dart`
Expected: FAIL to compile — `Target of URI doesn't exist: 'package:payment_module/app/payment_app.dart'`

- [ ] **Step 3: Implement**

```dart
// lib/app/payment_app.dart
import 'package:flutter/material.dart';

import '../brand_engine/brand_engine.dart';
import '../features/payment/payment.dart';

/// The app. One `MaterialApp` for every Brand: the visual half of the Brand arrives as
/// `ThemeData` + `BrandTokens`, the non-visual half through `BrandScope` — the two delivery
/// mechanisms of docs/architecture.md §6. There is exactly one route; the Result View is a phase
/// of it, not a second page (§11.1).
class PaymentApp extends StatelessWidget {
  const PaymentApp({super.key, required this.brand});

  final BrandConfig brand;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: brand.displayName,
    theme: buildBrandTheme(brand),
    home: BrandScope(
      brand: brand,
      child: const PaymentConfirmationPage(),
    ),
  );
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/app/payment_app_test.dart`
Expected: `00:00 +2: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/app test/app test/support/fakes/register_fake_ports.dart
git commit -m "feat(app): add PaymentApp"
```

---

### Task 16: `bootstrap()` and the real `main.dart`

**Files:**
- Modify: `lib/main.dart` (replace the placeholder entirely)
- Test: `test/app/bootstrap_test.dart`

§3.1 puts `bootstrap()` in `main.dart` and fixes its order: **BRAND dart-define → `BrandRegistry` → `setupLocator` → `preferHighRefreshRate` → debug drift assertion → `runApp`**.

Three details that decide whether this is correct or merely plausible:

- **A missing or unknown `BRAND` must fail loudly**, never fall back to a default Brand — shipping Retail's policy under Utility's name is precisely the failure mode §13.1(2) and the drift assertion exist to prevent. `resolveBrand` is factored out of `bootstrap()` so a test can prove that without calling `runApp`.
- **`preferHighRefreshRate` is best-effort** (§12.2): its result is logged, never awaited on the critical path, and a failure must not stop startup.
- **The drift assertion is debug-only and non-fatal on transport errors.** `buildInfo()` goes over a channel; in a test or on a host with no native side it throws, and a *failed check* must not crash the app — only a genuine mismatch should. Hence `kDebugMode` + try/catch around the call, with the `assert` on the value itself.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/brand_id.dart';
import 'package:payment_module/main.dart';

void main() {
  test('resolves a known BRAND to its Brand', () {
    expect(resolveBrand('utility').id, const BrandId('utility'));
    expect(resolveBrand('retail').displayName, 'Retail Shop');
  });

  test('a missing BRAND fails loudly, naming how to pass it', () {
    expect(
      () => resolveBrand(''),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('BRAND'), contains('make run')),
        ),
      ),
    );
  });

  test('an unknown BRAND fails loudly, naming the registered Brands', () {
    expect(
      () => resolveBrand('acme'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('acme'), contains('retail'), contains('utility')),
        ),
      ),
    );
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/app/bootstrap_test.dart`
Expected: FAIL to compile — `Undefined name 'resolveBrand'`

- [ ] **Step 3: Implement**

```dart
// lib/main.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app/locator.dart';
import 'app/payment_app.dart';
import 'bootstrap/channel_app_info.dart';
import 'bootstrap/channel_display_mode.dart';
import 'brand_engine/brand_engine.dart';
import 'brands/registry.dart';
import 'core/brand_id.dart';

/// The Brand this binary was built for, paired 1:1 with the Gradle product flavor of the same
/// name (docs/adr/0002). `make run BRAND=<id>` sets both knobs together.
const brandFromEnvironment = String.fromEnvironment('BRAND');

Future<void> main() => bootstrap();

/// BRAND dart-define → registry → locator → refresh-rate nudge → debug drift assertion →
/// `runApp`, in that order (docs/architecture.md §3.1, §6, §12.2).
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final brand = resolveBrand(brandFromEnvironment);
  setupLocator(brand);

  // Best-effort and off the critical path: the display may refuse, and that is not an error
  // (§12.2). Never awaited before the first frame.
  unawaited(_nudgeRefreshRate());

  if (kDebugMode) {
    unawaited(_assertFlavorMatches(brand));
  }

  runApp(PaymentApp(brand: brand));
}

/// Resolves the `BRAND` dart-define. Throws [StateError] rather than falling back to a default
/// Brand: a binary that quietly runs the wrong Brand's Posture Policy is worse than one that
/// refuses to start.
BrandConfig resolveBrand(String id) {
  if (id.isEmpty) {
    throw StateError(
      'No BRAND dart-define. Build through the Makefile, e.g. `make run BRAND=retail`, '
      'which pairs --flavor with --dart-define=BRAND.',
    );
  }
  return brandRegistry.byId(BrandId(id));
}

Future<void> _nudgeRefreshRate() async {
  try {
    final mode = await ChannelDisplayMode().preferHighRefreshRate();
    if (mode != null) {
      debugPrint(
        'Display mode requested: ${mode.refreshRate} Hz (mode ${mode.modeId})',
      );
    }
  } catch (error) {
    debugPrint('Refresh-rate nudge unavailable: $error');
  }
}

/// Debug-only: catches `--flavor retail --dart-define=BRAND=utility`, which builds fine and then
/// runs the wrong Brand (§6, §13.1(2)). A transport failure here is not a mismatch, so it is
/// logged rather than asserted on.
Future<void> _assertFlavorMatches(BrandConfig brand) async {
  try {
    final info = await ChannelAppInfo().buildInfo();
    assert(
      info.flavor == brand.id.value,
      'Flavor/BRAND drift: native flavor "${info.flavor}" but BRAND '
      '"${brand.id.value}" — rebuild with `make run BRAND=${info.flavor}`.',
    );
  } catch (error) {
    debugPrint('Could not read native buildInfo for the drift check: $error');
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/app/bootstrap_test.dart`
Expected: `00:00 +3: All tests passed!`

- [ ] **Step 5: Run the whole suite and lint**

Run: `~/fvm/versions/3.44.6/bin/flutter test && ~/fvm/versions/3.44.6/bin/dart analyze --fatal-infos`
Expected: all green.

- [ ] **Step 6: Build both flavors — the first real proof the app assembles**

```bash
~/fvm/versions/3.44.6/bin/flutter build apk --debug --flavor retail --dart-define=BRAND=retail
~/fvm/versions/3.44.6/bin/flutter build apk --debug --flavor utility --dart-define=BRAND=utility
```
Expected: both `✓ Built build/app/outputs/flutter-apk/…`. This is the step that catches a Gradle/flavor problem that no Dart test can see. If a build fails, report it — do not work around it by changing the flavor names, which Task 13's guard pins to the registry.

- [ ] **Step 7: Commit**

```bash
git add lib/main.dart test/app/bootstrap_test.dart
git commit -m "feat(app): replace the placeholder main with bootstrap()"
```

---

### Task 17: `test/architecture_test.dart` — §3.3's belt and braces

**Files:**
- Test: `test/architecture_test.dart`

§3.3 wants a test that "walks `lib/**` and regex-checks `import` lines against the same rules so CI enforces the policy even if the plugin misbehaves". Plan 1 learned the hard way that `import_lint` can silently not run (finding 1: `flutter analyze` reports clean while a rule is violated), which is exactly why this exists.

**It reads the rules out of `analysis_options.yaml` rather than restating them.** A copy of the eleven rules inside the test would drift from the real ones, and a drifted copy of a boundary check is worse than no copy: it passes while the real wall is down.

- [ ] **Step 1: Write the test**

```dart
// §3.3's second enforcement path. `import_lint` is the primary one, but it runs only under
// `dart analyze --fatal-infos` and has silently no-opped before (Plan 1, finding 1) — so the
// same rules are checked here, in plain Dart, from the same source of truth.
import 'dart:io';

import 'package:glob/glob.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

const _package = 'payment_module';

class _Rule {
  const _Rule(this.name, this.target, this.from, this.except);

  final String name;
  final String target;
  final String from;
  final List<String> except;

  bool targets(String uri) => Glob(target).matches(uri);
  bool forbids(String uri) => Glob(from).matches(uri) && !except.contains(uri);
}

List<_Rule> _loadRules() {
  final yaml = loadYaml(File('analysis_options.yaml').readAsStringSync());
  final rules = (yaml as YamlMap)['import_lint']['rules'] as YamlMap;
  return [
    for (final entry in rules.entries)
      _Rule(
        entry.key as String,
        (entry.value as YamlMap)['target'] as String,
        (entry.value as YamlMap)['from'] as String,
        [
          for (final item in ((entry.value as YamlMap)['except'] as YamlList?) ?? const [])
            item as String,
        ],
      ),
  ];
}

/// `lib/features/payment/src/x.dart` → `package:payment_module/features/payment/src/x.dart`
String _packageUri(File file) {
  final relative = file.path
      .replaceFirst(RegExp(r'^\.?/?lib/'), '')
      .replaceAll(r'\', '/');
  return 'package:$_package/$relative';
}

/// Every `import '...'` in [source], as an absolute URI resolved against [fileUri].
Iterable<String> _imports(String fileUri, String source) => RegExp(
  r'''^\s*import\s+['"]([^'"]+)['"]''',
  multiLine: true,
).allMatches(source).map((match) {
  final raw = match.group(1)!;
  if (raw.startsWith('dart:') || raw.startsWith('package:')) return raw;
  return Uri.parse(fileUri).resolve(raw).toString();
});

void main() {
  final rules = _loadRules();

  test('analysis_options.yaml declares the rules this test enforces', () {
    expect(rules, isNotEmpty);
    // Guards against a silent config rewrite: §3.3 fixes these names.
    expect(
      rules.map((rule) => rule.name),
      containsAll([
        'core_is_flutter_free',
        'core_depends_on_nothing',
        'engine_knows_no_features',
        'domain_no_data',
        'domain_no_presentation',
        'domain_no_flutter',
        'presentation_no_data',
        'security_guard_via_barrel',
        'no_reverse_dependency',
      ]),
    );
  });

  test('every rule declares an explicit except list', () {
    // Plan 1, finding 2: without `except: []` the plugin throws while parsing its own config,
    // and under the wrong analyze command that failure is swallowed.
    final yaml = loadYaml(File('analysis_options.yaml').readAsStringSync());
    final raw = (yaml as YamlMap)['import_lint']['rules'] as YamlMap;
    for (final entry in raw.entries) {
      expect(
        (entry.value as YamlMap).containsKey('except'),
        isTrue,
        reason: 'rule "${entry.key}" is missing `except: []`',
      );
    }
  });

  test('no file under lib/ imports across a wall', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    expect(files, isNotEmpty, reason: 'run this test from the package root');

    final violations = <String>[];
    for (final file in files) {
      final uri = _packageUri(file);
      final source = file.readAsStringSync();
      for (final rule in rules.where((rule) => rule.targets(uri))) {
        for (final import in _imports(uri, source)) {
          if (rule.forbids(import)) {
            violations.add('${rule.name}: $uri imports $import');
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'boundary violations:\n${violations.join('\n')}',
    );
  });

  test('the walker actually matches something — it is not vacuously green', () {
    // A rule set that matches no files would make the test above pass no matter what the code
    // does. Assert the two most load-bearing rules really cover real files.
    final core = 'package:$_package/core/money.dart';
    final payment = 'package:$_package/features/payment/src/presentation/can_pay.dart';

    expect(
      rules.where((rule) => rule.name == 'core_is_flutter_free').single.targets(core),
      isTrue,
    );
    expect(
      rules
          .where((rule) => rule.name == 'security_guard_via_barrel')
          .single
          .targets(payment),
      isTrue,
    );
    expect(
      rules
          .where((rule) => rule.name == 'security_guard_via_barrel')
          .single
          .forbids('package:$_package/features/security_guard/src/domain/policy_verdict.dart'),
      isTrue,
    );
  });
}
```

- [ ] **Step 2: Run it**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/architecture_test.dart`
Expected: `00:00 +4: All tests passed!`

- [ ] **Step 3: Prove it actually catches a violation — otherwise it is decoration**

Temporarily add `import 'package:payment_module/features/payment/payment.dart';` to `lib/features/security_guard/src/domain/security_posture.dart`, run the test, and confirm the third test fails naming `no_reverse_dependency`. Then revert the import and re-run to green.

If the walker does *not* catch it, the likely cause is `Glob` matching semantics on the `package:` prefix or on `{a,b}` braces — debug it with a one-off `print(Glob(pattern).matches(uri))` before changing the rule patterns, and never "fix" it by loosening a rule in `analysis_options.yaml`.

- [ ] **Step 4: Commit**

```bash
git add test/architecture_test.dart
git commit -m "test: enforce the module walls in plain Dart as well as import_lint"
```

---

### Task 18: Per-brand goldens — §13.1(3)

**Files:**
- Test: `test/golden/payment_page_golden_test.dart`
- Generated: `test/golden/goldens/{retail,utility}/*.png`

§13.1(3): each Brand × six BLoC-driven states, pumping the real page with scripted fakes, tagged `golden`. This is the visual proof the white-label engine works — twelve images where nothing but configuration differs.

**Animations are disabled for every golden** (`MediaQuery(disableAnimations: true)`). §12.1 already specifies that reduced motion holds the scan at a fixed phase, so this isn't a test-only hack — it's the same code path a user with reduced motion gets, and it's what makes the Scanning golden deterministic instead of catching the radar mid-sweep.

**Text renders as boxes.** `flutter_test` ships no real fonts, so goldens show Ahem blocks. That is normal and still catches what goldens are for here: layout, order, spacing, density, colour, shape.

- [ ] **Step 1: Write the test**

```dart
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:payment_module/app/payment_app.dart';
import 'package:payment_module/brand_engine/brand_engine.dart';
import 'package:payment_module/brands/registry.dart';
import 'package:payment_module/core/money.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/payment/payment.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

import '../support/fakes/fake_payment_processor.dart';
import '../support/fakes/fake_payment_repository.dart';
import '../support/fakes/fake_secure_window.dart';
import '../support/fakes/fake_security_environment.dart';
import '../support/fakes/register_fake_ports.dart';

const _payment = Payment(
  reference: 'PAY-DEMO-0001',
  amount: Money(amountMinor: 4200, currency: 'USD'),
  payee: 'Acme Utilities',
  lineItems: [
    LineItem(
      description: 'Monthly service',
      amount: Money(amountMinor: 3200, currency: 'USD'),
    ),
    LineItem(
      description: 'Usage overage',
      amount: Money(amountMinor: 1000, currency: 'USD'),
    ),
  ],
);

final _clear = SecurityPosture(const [
  ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
  ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
]);

final _unverified = SecurityPosture(const [
  ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
  ThreatAssessment(
    kind: ThreatKind.screenRecording,
    result: Unavailable(UnavailableReason.apiLevel),
  ),
]);

final _receipt = PaymentReceipt(
  reference: 'PAY-DEMO-0001',
  completedAt: DateTime.utc(2026, 9, 17, 8, 30),
);

void main() {
  late FakePaymentRepository repository;
  late FakePaymentProcessor processor;
  late FakeSecurityEnvironment environment;

  setUp(() {
    repository = FakePaymentRepository();
    processor = FakePaymentProcessor();
    environment = FakeSecurityEnvironment();
    GetIt.I.reset();
    registerFakePorts(
      repository: repository,
      processor: processor,
      environment: environment,
      window: FakeSecureWindow(),
    );
  });

  tearDown(() async {
    await processor.dispose();
    await environment.dispose();
    await GetIt.I.reset();
  });

  for (final brand in brandRegistry.all) {
    final id = brand.id.value;

    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        // Reduced motion holds the scan at a fixed phase (§12.1) — which is also what makes a
        // golden of an animated screen deterministic.
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: PaymentApp(brand: brand),
        ),
      );
      await tester.pump();
    }

    Future<void> reachAwaiting(WidgetTester tester, SecurityPosture posture) async {
      repository.completeWith(_payment);
      environment.pushPosture(posture);
      await tester.pump(brand.tokens.scanMinDuration * 2);
      await tester.pump();
    }

    Future<void> shoot(WidgetTester tester, String state) => expectLater(
      find.byType(PaymentApp),
      matchesGoldenFile('goldens/$id/$state.png'),
    );

    group('$id goldens', () {
      testWidgets('scanning', (tester) async {
        await pump(tester);
        await shoot(tester, 'scanning');
      });

      testWidgets('awaiting confirmation, secure', (tester) async {
        await pump(tester);
        await reachAwaiting(tester, _clear);
        await shoot(tester, 'awaiting-secure');
      });

      testWidgets('awaiting confirmation, unverified', (tester) async {
        await pump(tester);
        await reachAwaiting(tester, _unverified);
        await shoot(tester, 'awaiting-unverified');
      });

      testWidgets('processing at 40%', (tester) async {
        await pump(tester);
        await reachAwaiting(tester, _clear);
        await tester.tap(find.byType(FilledButton));
        await tester.pump();
        processor.pushProgress(const Running(40));
        await tester.pump();
        await shoot(tester, 'processing');
      });

      testWidgets('completed, succeeded', (tester) async {
        await pump(tester);
        await reachAwaiting(tester, _clear);
        await tester.tap(find.byType(FilledButton));
        await tester.pump();
        processor.pushProgress(Succeeded(_receipt));
        await tester.pump();
        await shoot(tester, 'completed-succeeded');
      });

      testWidgets('completed, failed', (tester) async {
        await pump(tester);
        await reachAwaiting(tester, _clear);
        await tester.tap(find.byType(FilledButton));
        await tester.pump();
        processor.pushProgress(const Failed(PaymentFailure.declined));
        await tester.pump();
        await shoot(tester, 'completed-failed');
      });
    });
  }
}
```

- [ ] **Step 2: Generate the reference images**

Run: `~/fvm/versions/3.44.6/bin/flutter test --tags golden --update-goldens`
Expected: 12 tests pass and 12 PNGs appear under `test/golden/goldens/retail/` and `.../utility/`.

- [ ] **Step 3: Look at them — a golden nobody looked at proves nothing**

Open the twelve files. Check that: Retail is warm/rounded and shows the Promo Banner above the summary; Utility is navy/sharp/denser and shows the Bill Breakdown; `awaiting-unverified` shows a notice banner on Utility and **no** banner on Retail (Retail's policy allows an unavailable check silently — §6's table); `processing` shows a progress bar; both `completed-*` show their result card. If any image contradicts those expectations, the bug is in the code or the Brand values, not in the golden — fix that and regenerate.

- [ ] **Step 4: Confirm they pass without `--update-goldens`, and that untagged runs skip them**

Run: `~/fvm/versions/3.44.6/bin/flutter test --tags golden`
Expected: `+12: All tests passed!`

Run: `~/fvm/versions/3.44.6/bin/flutter test`
Expected: the golden tests do **not** run (§15: `make test` excludes goldens). If they do run, the `@Tags(['golden'])` annotation isn't taking effect — check it sits above `library;` at the very top of the file, and that `make test`'s exclusion is what Task 20 configures.

- [ ] **Step 5: Commit**

```bash
git add test/golden
git commit -m "test(golden): capture both Brands across the six flow states"
```

---

### Task 19: `integration_test/perf_test.dart` — §12.3's second proof

**Files:**
- Test: `integration_test/perf_test.dart`

§12.3(2): wrap the scan in `watchPerformance()` for a fixed window while progress arrives at 10 Hz, and assert build/raster percentiles under a budget computed from the **live** refresh rate — §12.2 is explicit that the budget is `1000 / refreshRate` ms and never a hard-coded 16 or 8.

This runs on a device (`flutter test integration_test/perf_test.dart -d <id>`), like Plan 4's `native_bridge_test.dart`. It is not part of `make test`.

- [ ] **Step 1: Write the test**

```dart
// §12.3(2), on-device. Budget comes from the live Display.refreshRate (§12.2): a 120 Hz panel
// gets ~8.3 ms, a 60 Hz one ~16.7 ms, and the assertion is the same code either way.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:payment_module/app/payment_app.dart';
import 'package:payment_module/brands/registry.dart';
import 'package:payment_module/core/brand_id.dart';
import 'package:payment_module/core/money.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/payment/payment.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

import '../test/support/fakes/fake_payment_processor.dart';
import '../test/support/fakes/fake_payment_repository.dart';
import '../test/support/fakes/fake_secure_window.dart';
import '../test/support/fakes/fake_security_environment.dart';
import '../test/support/fakes/register_fake_ports.dart';

const _payment = Payment(
  reference: 'PAY-PERF-0001',
  amount: Money(amountMinor: 4200, currency: 'USD'),
  payee: 'Acme Utilities',
  lineItems: [],
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the scan holds its frame budget while the flow emits at 10 Hz', (tester) async {
    final repository = FakePaymentRepository();
    final processor = FakePaymentProcessor();
    final environment = FakeSecurityEnvironment();
    GetIt.I.reset();
    registerFakePorts(
      repository: repository,
      processor: processor,
      environment: environment,
      window: FakeSecureWindow(),
    );
    addTearDown(() async {
      await processor.dispose();
      await environment.dispose();
      await GetIt.I.reset();
    });

    final brand = brandRegistry.byId(const BrandId('retail'));
    await tester.pumpWidget(PaymentApp(brand: brand));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    // The live refresh rate decides the budget — never a hard-coded frame time (§12.2).
    final refreshRate = tester.view.display.refreshRate;
    final budgetMicros = (1000000 / refreshRate).round();
    debugPrint('Display refresh rate: $refreshRate Hz → budget ${budgetMicros}µs/frame');

    await binding.watchPerformance(() async {
      repository.completeWith(_payment);
      environment.pushPosture(
        SecurityPosture(const [
          ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
          ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
        ]),
      );

      // Scan visible, flow emitting at 10 Hz for three seconds.
      for (var percent = 0; percent < 30; percent++) {
        processor.pushProgress(Running(percent));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }, reportKey: 'scan_performance');

    final summary = binding.reportData!['scan_performance'] as Map<String, dynamic>;
    final timeline = summary['frame_build_times'] as List<dynamic>?;
    expect(
      timeline,
      isNotNull,
      reason: 'watchPerformance produced no frame timings — is this running on a device?',
    );

    final builds = timeline!.cast<num>().map((value) => value.toDouble()).toList()..sort();
    final p90 = builds[(builds.length * 0.9).floor().clamp(0, builds.length - 1)];
    debugPrint('p90 build time: ${p90}µs of ${budgetMicros}µs budget');

    expect(
      p90,
      lessThan(budgetMicros),
      reason:
          'p90 build time ${p90}µs exceeded the ${budgetMicros}µs budget at $refreshRate Hz',
    );
  });
}
```

- [ ] **Step 2: Run it on a device**

```bash
~/fvm/versions/3.44.6/bin/flutter devices
~/fvm/versions/3.44.6/bin/flutter test integration_test/perf_test.dart \
  --flavor retail --dart-define=BRAND=retail -d <device-id>
```
Expected: pass, with the printed refresh rate and p90 in the log.

**Report what you find rather than forcing green.** Two outcomes are legitimate and both must be written down in Task 21's note: the budget holds, or it doesn't on this particular device. If `reportData`'s key names differ in Flutter 3.44 from `frame_build_times`, print `summary.keys` and use the real key — that's a fix. If the p90 genuinely exceeds the budget, **do not loosen the assertion**: report it, with the numbers, as a finding. §12.2 already warns OEM power modes can hold a device at 60 Hz, and §17 already lists "measure, don't assume".

If no device is attached, say so and leave the test committed and unrun — it is a device test by design, exactly like Plan 4's `native_bridge_test.dart`.

- [ ] **Step 3: Commit**

```bash
git add integration_test/perf_test.dart
git commit -m "test(integration): measure the scan's frame budget against the live refresh rate"
```

---

### Task 20: `Makefile`

**Files:**
- Create: `Makefile`

§15's six targets, verbatim in behaviour. Two carry non-obvious content: `test` must exclude the `golden` tag (§15's comment says so), and `analyze` must be `dart analyze --fatal-infos`, never `flutter analyze` (§3.3 findings 1 and 3 — the reason this is a Makefile target at all is so nobody has to remember that).

`BRAND` is required by `run` and `apk` and pairs the two knobs that must never disagree (§6, ADR-0002).

- [ ] **Step 1: Write it**

```makefile
# docs/architecture.md §15. The point of these targets is that the two knobs which must agree —
# Gradle's --flavor and Dart's --dart-define=BRAND — are set from one variable, and that
# `analyze` runs the command that actually executes import_lint (§3.3: NOT flutter analyze).

FLUTTER := ~/fvm/versions/3.44.6/bin/flutter
DART    := ~/fvm/versions/3.44.6/bin/dart

.PHONY: run apk test goldens analyze format

## run BRAND=retail — debug the app for one Brand
run:
ifndef BRAND
	$(error BRAND is required, e.g. `make run BRAND=retail`)
endif
	$(FLUTTER) run --flavor $(BRAND) --dart-define=BRAND=$(BRAND)

## apk BRAND=utility — release APK for one Brand
apk:
ifndef BRAND
	$(error BRAND is required, e.g. `make apk BRAND=utility`)
endif
	$(FLUTTER) build apk --flavor $(BRAND) --dart-define=BRAND=$(BRAND)

## test — the whole suite except the goldens (they are platform-sensitive; §13.1)
test:
	$(FLUTTER) test --exclude-tags golden

## goldens — regenerate the per-Brand reference images, then review them by eye
goldens:
	$(FLUTTER) test --tags golden --update-goldens

## analyze — the real lint. `flutter analyze` silently skips import_lint (§3.3)
analyze:
	$(DART) analyze --fatal-infos

## format
format:
	$(DART) format lib test integration_test
```

- [ ] **Step 2: Verify every target that can run on a host does**

```bash
make analyze
make test
make format
make run          # expect the BRAND error, not a Flutter invocation
make apk BRAND=nonsense   # expect Gradle to reject the unknown flavor
```
Expected: `analyze` clean; `test` green with no golden tests in the count; `format` exits 0 (if it rewrites files, commit that); `make run` prints the `BRAND is required` error; the last one fails from Gradle, which proves the variable is really being passed through.

- [ ] **Step 3: Confirm `make test` really excludes goldens**

Compare `make test`'s test count with `~/fvm/versions/3.44.6/bin/flutter test --tags golden`'s count (12). The two together should equal a plain `flutter test` run's count. If `make test` includes the goldens, `--exclude-tags` isn't matching the annotation — check the tag spelling in both places.

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "build: add the Makefile targets from architecture §15"
```

---

### Task 21: README, the architecture fold-back, and the verification note

**Files:**
- Modify: `README.md` (it is still the Flutter template)
- Modify: `docs/architecture.md` (§6, §13 — record what this plan settled)
- Create: `docs/verification/2026-09-17-composition-root-verification.md`

Plans 1 and 4 both ended by folding what they learned back into `docs/architecture.md`. This plan found three things worth recording, and the first is a real correction to the document rather than an addition.

- [ ] **Step 1: Replace the README**

```markdown
# Payment Confirmation Module

A white-label Payment Confirmation screen for Android: one codebase, one Brand per Flavor, a
Secure Window while the screen is visible, native root and screen-recorder detection, and a
foreground service that simulates processing the payment.

## Run it

```sh
make run BRAND=retail     # warm, rounded, Promo Banner, warns on a screen recorder
make run BRAND=utility    # navy, dense, Bill Breakdown, blocks on either Threat
```

`BRAND` sets both knobs that must agree: Gradle's `--flavor` and Dart's `--dart-define=BRAND`.
A mismatch is caught by a debug assertion at startup and by `test/brands/flavor_registry_test.dart`.

## Verify it

```sh
make analyze    # dart analyze --fatal-infos — this is the lint; `flutter analyze` skips import_lint
make test       # the whole suite except goldens
make goldens    # regenerate the per-Brand reference images
```

On a device: `flutter test integration_test/native_bridge_test.dart` (the channels end to end)
and `integration_test/perf_test.dart` (the scan's frame budget).

## Where things are

| Path | What |
|---|---|
| `lib/core/` | Flutter-free shared kernel — `Money`, `BrandId`, `ThreatKind`, `PosturePolicy`, exceptions |
| `lib/brand_engine/` | `BrandConfig`, `BrandTokens`, `BrandRegistry`, `BrandScope`, `buildBrandTheme` |
| `lib/native_bridge/` | channel names, `invokeNative`, wire decoding |
| `lib/features/security_guard/` | Security Posture, the Secure Window, the Security Scan visual |
| `lib/features/payment/` | the Payment, the flow bloc, the Sections, the screen |
| `lib/brands/` | one file per Brand, plus the registry |
| `lib/app/`, `lib/main.dart` | the composition root: locator, `PaymentApp`, `bootstrap()` |
| `android/app/src/main/kotlin/dev/test/payment/` | the channel handlers and the Payment Job service |
| `docs/architecture.md` | the design, and the reasoning behind it |
| `CONTEXT.md` | the glossary — every capitalised term above is defined there |

Adding a Brand is three edits and one optional one: `docs/architecture.md` §13 lists them, and a
failing test enforces every step.
```

- [ ] **Step 2: Fold the corrections into `docs/architecture.md`**

Three edits:

1. **§13, row 1 — the `const` correction.** Change `const acmeBrand = BrandConfig(...)` to `final acmeBrand = BrandConfig(...)` and append to that row: *"`final`, not `const`: `PosturePolicy` copies its maps unmodifiable and asserts `ThreatKind` coverage, so neither it nor anything containing it can be a constant."*
2. **§6 — the two values the table lacked.** Add a `headlineWeight` row to the Brand values table: Retail `w700`, Utility `w500`. Add a `displayName` row: "Retail Shop" / "Utility Pay".
3. **§12.3(1) — how the isolation proof is actually structured.** Append to item 1: *"The shipped painter carries no paint counter; the test measures the mechanism with its own counting painters (including the no-boundary control, which `SecurityScanView` deliberately cannot express) and separately asserts that `SecurityScanView` is that structure — a `RepaintBoundary` over a `CustomPaint` driven by a running controller."*

- [ ] **Step 3: Run everything, and record the real numbers**

```bash
~/fvm/versions/3.44.6/bin/dart analyze --fatal-infos
~/fvm/versions/3.44.6/bin/flutter test
~/fvm/versions/3.44.6/bin/flutter test --tags golden
~/fvm/versions/3.44.6/bin/dart format --set-exit-if-changed lib test integration_test
~/fvm/versions/3.44.6/bin/flutter build apk --debug --flavor retail --dart-define=BRAND=retail
~/fvm/versions/3.44.6/bin/flutter build apk --debug --flavor utility --dart-define=BRAND=utility
```

- [ ] **Step 4: Write the verification note**

Fill every `<…>` with a number or sentence you actually observed. Do not estimate, and do not write "passing" where a count belongs.

```markdown
# Composition root verification — 2026-09-17

Plan: `docs/superpowers/plans/2026-09-17-composition-root.md`. Verified against
`docs/architecture.md` §3.1, §3.3, §4, §6, §7, §11, §12, §13, §14, §15.

## Commands

- `dart analyze --fatal-infos` — <result>
- `flutter test` — <N> tests passing, goldens excluded
- `flutter test --tags golden` — <N> goldens passing
- `dart format --set-exit-if-changed lib test integration_test` — <result>
- `flutter build apk --debug --flavor retail|utility` — <both built? yes/no>
- `integration_test/perf_test.dart` — <ran on device <name> at <N> Hz, p90 <N>µs of <N>µs budget
  | not run, no device attached>

## What the guards proved

- `test/architecture_test.dart` — the eleven §3.3 rules are read from `analysis_options.yaml` and
  checked against every file under `lib/`. Confirmed non-vacuous: a temporary
  `no_reverse_dependency` violation was added, observed failing, and reverted.
- `test/brands/brand_registry_test.dart` — <N> assertions across both Brands: configs resolve,
  ids are slugs, one Summary and one Pay Button each, policies cover every `ThreatKind`, themes
  carry their tokens.
- `test/brands/flavor_registry_test.dart` — Gradle flavors `{retail, utility}` equal the registry.
- `test/features/security_guard/scan_isolation_test.dart` — 60 animation frames → <N> scan
  paints, <N> page-layer paints; 10 emissions → <N> page-layer paints; control without the
  boundary → <N> page-layer paints.

## Corrections folded back into docs/architecture.md

- §13 row 1: Brands are `final`, not `const` — `PosturePolicy` cannot be a constant.
- §6: the Brand table gained `headlineWeight` (Retail w700 / Utility w500) and `displayName`.
- §12.3(1): recorded how the isolation proof is split, since the shipped painter carries no
  counter.

## Still open

- §13.1(3) wants the goldens "executed in CI on Linux". There is no CI here, so the committed
  reference images were generated on macOS and will not match a Linux runner byte for byte. The
  first CI job to run them must regenerate and review them once.
- §12.3(2)'s budget claim is only as good as the device it ran on — see the number above, and
  §17's standing warning that OEM power modes can hold a panel at 60 Hz.
- Everything else in §17 remains as Plan 4 left it.
```

- [ ] **Step 5: Commit**

```bash
git add README.md docs/architecture.md docs/verification/2026-09-17-composition-root-verification.md
git commit -m "docs: replace the template README; fold the composition root's corrections into the architecture"
```

---

## Self-review

**Spec coverage.** Walked §3.1's layout tree and §4's interface list line by line against the tasks:

| Spec | Task |
|---|---|
| §3.1 `lib/app/{payment_app,locator}.dart` | 14, 15 |
| §3.1 `lib/brands/{retail,utility,registry}.dart` | 12 |
| §3.1 `main.dart` → `bootstrap()` order | 16 |
| §3.1/§3.3 `test/architecture_test.dart` | 17 |
| §3.1 `Makefile` | 20 |
| §4 `brand_engine` exports `BrandRegistry` | 3 |
| §4 `security_guard` exports `SecurityScanView`, `PostureBanner` | 5, 7 |
| §4 `payment` exports `PaymentConfirmationPage`, `PaymentSection`, `PaymentBrandConfig` | 8, 10 |
| §4 `payment` `src/`: section widgets, money formatting | 4, 8 |
| §5 money formatting with `intl` in `payment/presentation` | 4 |
| §6 `BrandTokens.headlineWeight`; the Brand values table | 2, 12 |
| §6 sealed `PaymentSection` + `CustomSection` escape hatch | 8 |
| §7 `canPay` wired; no bloc-to-bloc relay; CTA "checking…" | 10, 11 |
| §11 `SecureSessionScope` around the page; `PopScope` during Processing | 10, 11 |
| §12.1 `RadarPainter`, `SecurityScanView`, reduced motion | 5 |
| §12.2 refresh-rate nudge at bootstrap; budget from the live rate | 16, 19 |
| §12.3(1) canary isolation test | 6 |
| §12.3(2) `integration_test/perf_test.dart` | 19 |
| §13.1(1) registry completeness | 12 |
| §13.1(2) flavor ↔ registry | 13 |
| §13.1(3) per-brand goldens | 18 |
| §14 page widget tests, composition-root tests | 11, 12, 13, 14, 15, 16, 17 |
| §15 the six `Makefile` targets | 20 |

Nothing in §3.1's tree is unaccounted for. Deliberately excluded, with the reason stated in the Scope Boundary: per-flavor launcher icons (§13 calls them optional), the prompt log and Insight Report (not code), a CI workflow (nothing in the spec asks for one).

**Placeholder scan.** No `TBD`, no "add error handling", no "similar to Task N". Every code step carries complete code. Three places deliberately defer to observation rather than prescribing an answer, and each says exactly what to do and what not to do: Task 11's three plausible test failures (fix the test, don't delete the assertion), Task 19's frame budget (report the number, don't loosen the assertion), and Task 21's verification note (fill in real numbers, don't estimate). Task 18 Step 3 asks a human to look at twelve images — that is the work, not a placeholder.

**Type consistency.** Checked every identifier this plan introduces against the code that consumes it later: `BrandTokens.headlineWeight` (Task 2) is read by `SummaryCard`/`PromoBanner` (8) and `ResultView` (9) and set in both Brands (12). `BrandRegistry.all`/`byId`/`ids` (3) are used by the guards (12, 13), `resolveBrand` (16) and the goldens (18). `formatMoney(Money)` (4) is called in 8 only. `PolicyVerdict.hasAnything` (7) is used by `PostureBanner` alone. `PaymentBrandConfig.ctaLabel`/`sections` and all five `PaymentSection` variants (8) are consumed by the page's two switches (10) and the completeness guard (12). `PayButton(label:, enabled:, onPressed:)` (8) matches `_PayButtonSlot`'s call (10) and the section-widget tests (8). `ResultView(outcome:, onRetry:, verdict:)` (9) matches `_ResultSlot` (10). `SecurityScanViewState.controller` (5) is read by the view test (5) and the isolation test (6). `registerFakePorts` (15) is used by 15, 18 and 19. `setupLocator(brand, {locator})` (14) is called by `bootstrap()` (16) and its own test.

One ordering detail worth stating, since it looks like an inconsistency and isn't: Task 11's page test registers the fakes inline, while Tasks 15, 18 and 19 go through the `registerFakePorts` helper that Task 15 creates. That is deliberate — Task 11 runs before the helper exists and needs nothing from it, and extracting a shared helper for a single caller would be premature. The helper appears at the point the third caller does.

**One risk this plan cannot fully de-risk on paper**, stated plainly rather than buried: Tasks 11, 18 and 19 drive real timers, a real animation controller and real platform channels through the test binding, and widget-test timing is the one area where carefully-reasoned code still surprises you. Each of those tasks names the specific failures I consider plausible and says which way to fix them (adjust the test's pump sequence; never loosen an assertion or delete a measurement). If a fourth surprise appears, that is a report-back, not a licence to weaken the proof.
