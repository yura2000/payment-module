/// The base of this app's exception hierarchy. Thrown by adapters for the *unexpected* — a
/// native call that failed for reasons the caller cannot recover from within the flow itself.
/// Expected outcomes (a Compromised posture, a failed Payment Job) are values, never exceptions.
/// See docs/architecture.md §2 principle 3.
sealed class AppException implements Exception {
  const AppException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// A transient failure in the environment surrounding an operation — a native call that could
/// not complete right now but might on retry (e.g. no Activity attached during a config change).
final class ServiceException extends AppException {
  const ServiceException(super.message);
}

/// A programming error or invariant violation — a call made in a state the code should have
/// prevented (e.g. starting a Payment Job that is already running).
final class ClientException extends AppException {
  const ClientException(super.message);
}

/// A failure in the transport itself — a malformed payload, an unregistered channel handler, or
/// a native call that did not reply in time.
final class TransportException extends AppException {
  const TransportException(super.message);
}
