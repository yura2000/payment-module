# 08. Brand slot / section-list mechanism

Type: prototype
Status: resolved
Blocked by: —
Part of: ../map.md

## Question

Prototype (UI branch of the `prototype` skill) the "no if/else" composition mechanism: `BrandConfig` carries per-feature config looked up by type (`config<PaymentBrandConfig>()`, the `ThemeExtension` pattern applied to config), and `PaymentBrandConfig.sections` is an ordered list of section descriptors the page maps to widgets; capability flags exist only for *behaviour*.

Show both brands rendering from the same page code with zero conditionals on identity, and what adding (a) a 3rd brand and (b) a new section type each cost. Decide: sections as an enum (closed set, exhaustive switch) vs section objects carrying their own builder (open set; a brand can add a novel section)?

**Deliverable**: verdict + the exact shapes to write into the spec; prototype captured on a throwaway branch with a pointer here.

**Inputs from resolved tickets**
- Ticket 07: brand config must carry a motion token `scanMinDuration` and the Posture Policy `onUnavailable` verb (Retail `allow`, Utility `notice`) — check the prototype's config shape accommodates per-feature config of that kind (`SecurityBrandConfig`), not just payment sections.

## Answer

**Resolved 2026-09-16 (prototype, UI branch / sub-shape B; verdict accepted in one round).**

**Asset**: branch `prototype/brand-slots`, path `prototypes/brand_slots/` (throwaway Flutter web app; README explains how to run: `flutter run -d web-server --web-port 8081`, then `?variant=A|C|S&brand=retail|utility|acme`). Three structurally different mechanisms × three brands (Retail, Utility, plus a hypothetical **Acme Energy** added only to measure cost), a floating switcher and a resolved-config panel.

### Verdict
1. **Mechanism: C — sealed known sections + `CustomSection` escape hatch.** The only variant passing both PDF tests at once: "add a 3rd/4th brand" (Acme's loyalty section is defined in the brand's own file with **zero edits to `payment`**) and Utility's "high-density layout" (brands own section order). Rejected: **A** closed enum (a novel section needs an enum value + switch arm inside `payment`; Acme's loyalty card is not representable), **S** slots (fixed skeleton; brands can't reorder), **B** open objects without `sealed` (gives up the compiler's exhaustiveness check for nothing).
2. **Config shape**: `features: List<BrandFeatureConfig>` + `feature<T>() => features.whereType<T>().single`, mirroring `ThemeData.extensions`; `single` makes a missing/duplicated config fail loudly at first use. A registry-driven **completeness test** (every brand carries every required feature config; every `CustomSection` has a `debugLabel`) makes it a CI failure → ticket 14's guard.
3. **Layer placement**: `PaymentBrandConfig` (holds section objects that build widgets) → `payment/presentation`; `SecurityBrandConfig` (holds only a `PosturePolicy`) → `security_guard/domain`. `BrandFeatureConfig` subclasses may live in either layer of a feature; `brand_engine` stays layer-agnostic.
4. **No capability flags** — the Posture Policy covered every behavioural difference. Rule: a boolean capability, if one ever appears, is a field on the owning feature's config read through `feature<T>()`, never a top-level flag on `BrandConfig`.

### Evidence
- Zero identity conditionals: `grep BrandId lib/payment lib/security lib/brand_engine` → one hit, the `id` field declaration. The Utility/Acme notice banner and the 1200/1500/2000 ms scan chip are pure config.
- Adding Acme: one 80-line brand file (≈ 45 lines once only mechanism C remains) + one registry line (+ a Gradle flavor in the real app). Adding its novel section under C: 0 lines in `payment`.

### Shapes for the spec (as prototyped, minus the two rejected mechanisms)
```dart
// brand_engine (knows nothing about features)
abstract class BrandFeatureConfig { const BrandFeatureConfig(); }
class BrandTokens extends ThemeExtension<BrandTokens> {   // seed, accent, radius, density, spacing, scanMinDuration, headlineWeight
  ... copyWith / lerp
}
class BrandConfig {
  const BrandConfig({required this.id, required this.displayName, required this.tokens, required this.features});
  final BrandId id; final String displayName; final BrandTokens tokens; final List<BrandFeatureConfig> features;
  T feature<T extends BrandFeatureConfig>() => features.whereType<T>().single;
}
class BrandScope extends InheritedWidget { static BrandConfig of(BuildContext context); }
ThemeData buildBrandTheme(BrandConfig brand);   // ColorScheme.fromSeed(tokens.seed) + shapes(radius) + VisualDensity + extensions: [tokens]
extension on BuildContext { BrandTokens get tokens => Theme.of(this).extension<BrandTokens>()!; }

// payment/presentation
sealed class PaymentSection { const PaymentSection(); }
final class SummarySection extends PaymentSection { const SummarySection(); }
final class PromoBannerSection extends PaymentSection { const PromoBannerSection(); }
final class BillBreakdownSection extends PaymentSection { const BillBreakdownSection(); }
final class PayButtonSection extends PaymentSection { const PayButtonSection(); }
final class CustomSection extends PaymentSection {          // brand-supplied; `payment` renders it blind
  const CustomSection(this.builder, {required this.debugLabel});
  final Widget Function(BuildContext, Payment) builder; final String debugLabel;
}
class PaymentBrandConfig extends BrandFeatureConfig { const PaymentBrandConfig({required this.ctaLabel, required this.sections}); ... }
// page: for (final s in cfg.sections) switch (s) { SummarySection() => ..., ..., CustomSection(:final builder) => builder(context, payment) }

// security_guard/domain
class SecurityBrandConfig extends BrandFeatureConfig { const SecurityBrandConfig({required this.policy}); final PosturePolicy policy; }

// app/lib/brands/<brand>.dart — one const BrandConfig per brand; app/lib/brands/registry.dart — const brands = [...]
```

### Consequences pushed
- Ticket 13: `brand_engine` exports `BrandFeatureConfig`, `BrandTokens`, `BrandConfig`, `BrandScope`, `buildBrandTheme`, the `tokens` context extension; `payment` exports `PaymentSection` hierarchy + `PaymentBrandConfig`; `security_guard` exports `SecurityBrandConfig`.
- Ticket 14: the recipe is "one file in `app/lib/brands/` + one registry line + one Gradle flavor"; the guard is the registry-driven completeness test + per-brand goldens.
- Ticket 15: shapes above verbatim; the A/S/B rejections as the "considered alternatives".
- Ticket 09: `BrandTokens` (seed/accent/radius/density/spacing/scanMinDuration) is the token set the painter reads.
- `CONTEXT.md`: **Section**, **Brand Token** added.
- Map fog: the dev-only brand picker is now known to cost ~one widget (the prototype's switcher is one); stays in the fog until ticket 14 decides whether the demo wants it.
