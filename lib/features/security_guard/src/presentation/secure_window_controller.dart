import '../domain/secure_window.dart';

/// Ref-counted holder of the Secure Window: calls [SecureWindow.setSecure] only on 0→1 (acquire)
/// and 1→0 (release) transitions, so stacked secure routes and dialogs never toggle the flag
/// twice. Errors from the native side are swallowed — the flow must not depend on this call
/// succeeding on the first try; the next [onResumed] retries. See docs/architecture.md §11.
class SecureWindowController {
  SecureWindowController(this._window);

  final SecureWindow _window;
  int _count = 0;

  Future<void> acquire() async {
    _count++;
    if (_count == 1) {
      await _setSecureSwallowingErrors(true);
    }
  }

  Future<void> release() async {
    assert(
      _count > 0,
      'SecureWindowController.release() called more times than acquire()',
    );
    _count--;
    if (_count == 0) {
      await _setSecureSwallowingErrors(false);
    }
  }

  Future<void> onResumed() async {
    if (_count > 0) {
      await _setSecureSwallowingErrors(true);
    }
  }

  Future<void> _setSecureSwallowingErrors(bool secure) async {
    try {
      await _window.setSecure(secure);
    } catch (_) {
      // Swallowed by design: a transient ServiceException (e.g. no Activity attached during a
      // config change) must not break the payment flow. The next onResumed() retries.
    }
  }
}
