import 'package:payment_module/features/security_guard/security_guard.dart';

/// A recording [SecureWindow] for tests: every successful call is appended to [calls]. Set
/// [errorToThrow] to make the next call throw once (then reset itself).
class FakeSecureWindow implements SecureWindow {
  final calls = <bool>[];
  Object? errorToThrow;

  @override
  Future<void> setSecure(bool secure) async {
    if (errorToThrow != null) {
      final error = errorToThrow!;
      errorToThrow = null;
      throw error;
    }
    calls.add(secure);
  }
}
