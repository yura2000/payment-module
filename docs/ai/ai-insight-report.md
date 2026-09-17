# AI Insight Report — Hyper-Tenant Secure Payment Portal

This doubles as the Prompt Log the brief asks for separately: §2 below is three real
interactions (prompt → what came back → what I changed) rather than a screenshot dump, because
the actual audit trail is more useful to a reviewer than a picture of a chat window.

## 0. Tooling: which model did what, and why

I built this with **Claude Code**, routed across three model tiers rather than one flat
assistant. That routing is itself a design decision, so I'm stating it plainly instead of
hiding behind a generic "I used AI":

| Model | Commits | Used for |
|---|---|---|
| **Opus 5** | 27 | Architecture-level judgment: writing plan documents from a blank page, resolving ambiguous or conflicting instructions before touching code, the two prototype spikes (the `RadarPainter` visual, the sealed-section brand-slot layout), and the two hardest native-bridge fixes — the screen-recorder monitor's registered-flag race and the timed-out root-check force-kill. |
| **Sonnet 5** | 32 | Orchestration and judgment-heavy execution: turning an approved plan into working code, wiring the two Blocs together on the payment screen, and every spec-compliance / code-quality review pass. |
| **Haiku 4.5** | 39 | Mechanical implementation of tasks a plan had already pinned down to literal code — a new value-class field, a lookup class, a dependency bump — dispatched as a subagent and never merged without a Sonnet-tier review. |

The split isn't accidental. A plan with real design freedom left in it (a fresh feature, an
ambiguous native-threading question) goes to Opus. Once a plan exists and the remaining work is
"implement exactly this," that work goes to Haiku — cheaper and faster — and a stronger model
reviews it before it lands. Nothing merges on one model's say-so: every implementer subagent's
work goes through an independent spec-compliance check and a separate code-quality check, done
by re-reading the diff, not by trusting the implementer's own report.

---

## 1. How the multi-tenant config is structured

The brief's constraint is explicit — no `if (brand == retail)` anywhere — so the question isn't
"add a toggle," it's "make Brand identity a value the engine never inspects." Two channels carry
that value, matching Flutter's own two ways to make data ambient:

**Visual half → `ThemeExtension`.** `BrandTokens` (`lib/brand_engine/src/brand_tokens.dart`)
holds seed/accent color, corner radius, density, spacing, minimum scan duration, and headline
weight, and extends `ThemeExtension<BrandTokens>` — `copyWith`/`lerp` included, so a theme
transition between Brands animates instead of snapping. Every widget reads it as
`Theme.of(context).extension<BrandTokens>()` (wrapped as `context.tokens`), never as a Brand
lookup.

**Non-visual half → `InheritedWidget`.** `BrandScope` exposes the active `BrandConfig` —
display name, tokens, and a `List<BrandFeatureConfig>` — to the whole subtree. Each feature
module contributes its own slice without the engine knowing it exists:
`PaymentBrandConfig(ctaLabel, sections)` for the payment screen, `SecurityBrandConfig(policy)`
for the posture rules. Lookup is `brand.feature<PaymentBrandConfig>()` — typed, and open for a
third feature to add its own config type without touching `BrandConfig` itself.

**Section ordering is data, not layout code.** The payment screen doesn't have an `if
(brand.showsPromoBanner)`; it has `sections: [PromoBannerSection(), SummarySection(),
PayButtonSection()]` for Retail and a different list for Utility, drawn by a sealed
`PaymentSection` hierarchy the page switches over exhaustively. A `CustomSection` variant is the
escape hatch for content the payment module has never heard of — a Brand can ship UI the core
engine doesn't know exists, and the exhaustive switch still compiles because `CustomSection`
carries its own builder.

**Selection, not switching.** Brand is chosen once, at build time, via
`--dart-define=BRAND=<id>` paired 1:1 with an Android product flavor of the same name
(`docs/adr/0002`) — resolved through a `BrandRegistry` (`all`, `byId`) that a completeness-guard
test iterates. A debug-only assertion cross-checks the Dart `BRAND` against the native
`BuildConfig.FLAVOR` at startup so the two knobs can't silently drift.

**What adding a third brand costs:** one file (`lib/brands/loyalty.dart`), one line in
`lib/brands/registry.dart`, one Gradle flavor block. `test/brands/brand_registry_test.dart`
fails loudly if the new Brand is missing a `PaymentBrandConfig`, a policy that doesn't cover
every `ThreatKind`, or an empty CTA label — before it ever reaches a device.

---

## 2. How AI accelerated development — three real interactions

### 2.1 Generating the white-label theme mapping

**Prompt:**
> Design the white-label configuration layer for two Brands. Hard constraint: zero
> conditionals on Brand identity anywhere in the widget tree — every visual and behavioral
> difference has to come from data. Visual differences (palette, radius, density, spacing, a
> headline weight) need to compose into `ThemeData` the Flutter way, so they animate on
> transition instead of snapping. Non-visual differences (which sections render, in what order,
> the security posture policy) need to be reachable anywhere below one root widget without
> prop-drilling, and open for a third feature module to add its own slice later without
> touching the shared config type. Sketch the types.

**What came back:** `BrandTokens extends ThemeExtension<BrandTokens>` with `lerp`, a `BrandScope`
`InheritedWidget`, and `BrandConfig.feature<T>()` as a typed lookup into a
`List<BrandFeatureConfig>` — essentially the shape in §1 above, correct on the first pass.

**What I did with it:** the harder problem was proving the "zero conditionals" rule stays true
as the codebase grows, not writing it once. I didn't trust a single enforcement mechanism — the
`import_lint` plugin (module-boundary rules in `analysis_options.yaml`) had already been caught
silently no-opping under `flutter analyze` instead of `dart analyze --fatal-infos` earlier in
the project. So I had the same rules re-checked a second, independent way:
`test/architecture_test.dart` reads the eleven rules straight out of `analysis_options.yaml` and
regex-walks every import under `lib/` against them in plain Dart — no plugin dependency, runs in
CI either way. That test also proves it isn't vacuously green: it temporarily injects a real
violation, confirms the walker catches it by name, then reverts.

### 2.2 Optimizing the `CustomPainter` math

**Prompt:**
> Build the Security Scan as a `CustomPainter` — pulsing rings, a rotating gradient sweep,
> fading blips — running at display refresh rate. It has to be isolated in both directions: a
> Bloc emission elsewhere on the payment screen must never repaint this animation, and an
> animation frame must never trigger a rebuild of anything else in the tree.

**What came back:** `RadarPainter` wired with `super(repaint: progress)` — the `Animation<double>`
feeds the painter's repaint listenable directly, so a frame paints without going through
`setState`/`build` at all. Every `Paint` object (ring, cross, sweep shader, edge, blip, center)
is built once in the constructor instead of per frame, and `shouldRepaint` compares Brand tokens
by identity rather than the animation value. Wrapped in a `RepaintBoundary`.

**What I did with it:** the isolation claim only holds one direction unless the *host* widget is
also inert to outside rebuilds, and the first draft didn't address that — the painter was
correct, but nothing stopped a `BlocBuilder` emission during the Scan phase from rebuilding the
element above it. I hoisted the phase into its own `const _ScanPhaseView()` instance
(`payment_confirmation_page.dart`), so an unrelated state change hands Flutter the identical
widget and the subtree is skipped, not just repainted less. Separately, the first draft also
carried prototype-only scaffolding — a `scanStyle` enum, an `isolate` toggle, a global paint
counter — that was useful for exploring the animation but wasn't real configuration surface per
the spec (Brand differences come from `BrandTokens` data, not a second parallel style system). I
cut all three before merging.

### 2.3 Architecting the Native Bridge

**Prompt:**
> Design the Kotlin side of the security checks (root detection, screen-recorder detection) and
> the payment Foreground Service as `MethodChannel`s. Root detection shells out to check for
> su/Magisk binaries — that can't run on the platform channel's own thread. I need: which calls
> are safe on the channel thread and which need to move off it, how a result gets back to Dart
> without ever replying from the wrong thread, and how the Foreground Service survives the OS
> killing and restarting it mid-job without double-reporting or losing the client's progress
> subscription.

**What came back:** `MainThreadResult` wraps `MethodChannel.Result` so every `success`/`error`/
`notImplemented` call is forced back onto the main thread by construction —
(`android/app/src/main/kotlin/dev/test/payment/bridge/MainThreadResult.kt`) — instead of relying
on every handler to remember to hop threads itself. Root and recorder checks run on a background
dispatcher and reply through that wrapper. `PaymentJobService.onStartCommand` tracks the
current `startId` and calls `stopSelf(startId)` rather than the no-arg overload, so a job started
while a previous `stopSelf()` call is still in flight doesn't get torn down out from under the
new request — Android only honors `stopSelf(startId)` when that id is still the latest one.

**What I did with it:** shipped the threading wrapper close to as generated, but two real bugs
surfaced under review and got fixed, not waved through: (1) the recorder monitor's "am I
registered" flag could go stale relative to the actual OS registration state across a
start/stop race — fixed so the flag can't lie about whether a callback is really attached; (2)
a slow root-check shell command had no timeout, so a wedged process could hang the channel call
indefinitely — fixed to force-kill it after a bound. Neither was something a first read of the
generated code would catch; both came out of writing the on-device integration smoke test and
asking "what happens if this runs twice, or never returns."

---

## 3. Where AI got it wrong, and how I caught it

**Headline case: a `const` that can't be `const`.** The architecture doc's own early sketch
(§13) wrote each Brand as a top-level `const BrandConfig`, the idiomatic Dart pattern for
value-shaped global config. Wiring up the real Retail and Utility Brands against
`SecurityBrandConfig(policy: PosturePolicy(...))`, that broke: `PosturePolicy`'s constructor
calls `Map.unmodifiable` on its two response maps and asserts every `ThreatKind` is covered —
neither of those is a constant expression in Dart, so a `BrandConfig` holding one can't be
`const` either, no matter how it's spelled.

The instructive part isn't the compile error — it's that the *plan itself*, generated to match
the architecture doc's sketch, had copied the same mistake forward: it proposed `const
retailBrand = BrandConfig(...)` before a single line of it had been run. Executing it is what
surfaced the contradiction between "this should be const" and "this constructor isn't a const
expression." I changed both Brands to `final` — costs nothing at runtime, two objects built once
at startup — and, rather than patching around it quietly, corrected the architecture doc itself
(§13, now: *"`final`, not `const`: `PosturePolicy` copies its maps unmodifiable and asserts
`ThreatKind` coverage, so neither it nor anything containing it can be a constant"*) so the next
plan that reads that section inherits the correction instead of the original mistake.

**Second, smaller case, for pattern rather than novelty:** a generated `PaymentConfirmationBloc`
had a real concurrency bug — `close()` didn't stop an already-suspended async event handler, so a
slow in-flight payment call could still try to `emit()` after the Bloc was closed, either
leaking a subscription or crashing on "add after close." A code-quality review subagent caught
it, not a human eyeballing the diff; fixing it properly (an `isClosed` guard after every `await`,
not just at the top of the handler) took four review/fix rounds, each one proven with a test that
failed deterministically when the guard was stripped and passed once it was restored. Same
lesson as the `const` case: generated code that compiles and passes a happy-path test is not the
same claim as generated code that's correct, and the difference only shows up when something
actively tries to break it.
