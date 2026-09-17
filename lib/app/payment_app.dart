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
    home: BrandScope(brand: brand, child: const PaymentConfirmationPage()),
  );
}
