/// Holds or releases the Secure Window (`FLAG_SECURE`) — blocks screenshots and screen sharing
/// while the payment screen is visible. See CONTEXT.md → Secure Window.
abstract class SecureWindow {
  Future<void> setSecure(bool secure);
}
