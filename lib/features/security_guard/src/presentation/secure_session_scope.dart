import 'package:flutter/widgets.dart';

import 'secure_window_controller.dart';

/// Holds the Secure Window for as long as this widget is mounted, and re-asserts it on resume.
/// Ref-counted via [SecureWindowController] so stacked secure routes and dialogs don't flicker
/// the flag. See docs/architecture.md §11 — "one lifetime, two owners" (this scope and
/// `SecurityPostureCubit` are the two; they are deliberately not merged).
class SecureSessionScope extends StatefulWidget {
  const SecureSessionScope({
    super.key,
    required this.controller,
    required this.child,
  });

  final SecureWindowController controller;
  final Widget child;

  @override
  State<SecureSessionScope> createState() => _SecureSessionScopeState();
}

class _SecureSessionScopeState extends State<SecureSessionScope>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.acquire();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.onResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
