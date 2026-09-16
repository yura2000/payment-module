import 'package:flutter/material.dart';

/// Placeholder entry point. Replaced by the real bootstrap — BRAND dart-define →
/// BrandRegistry → setupLocator → runApp — in the app-composition-root implementation plan.
/// See docs/architecture.md §6 and §15.
void main() {
  runApp(const _PlaceholderApp());
}

class _PlaceholderApp extends StatelessWidget {
  const _PlaceholderApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(body: Center(child: Text('payment_module scaffold'))),
    );
  }
}
