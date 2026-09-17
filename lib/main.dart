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
/// runs the wrong Brand (§6). A transport failure here is not a mismatch, so it is logged rather
/// than asserted on.
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
