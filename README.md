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
A mismatch is caught by a debug assertion at startup.

## Verify it

```sh
make analyze    # dart analyze --fatal-infos — this is the lint; `flutter analyze` skips import_lint
make test       # the whole suite
```

On a device: `flutter test integration_test/native_bridge_test.dart` (the channels end to end).

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

Adding a Brand is three edits and one optional one: `docs/architecture.md` §13 lists them.
`test/brands/brand_registry_test.dart` enforces the Dart side; the Gradle-side and golden guards
§13 also calls for are not built here.
