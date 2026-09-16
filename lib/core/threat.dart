/// A kind of Threat the Security Environment checks for. See CONTEXT.md → Threat.
enum ThreatKind { rooted, screenRecording }

/// What a Posture Policy does when a Threat is detected.
enum DetectedResponse { block, warn }

/// What a Posture Policy does when a Threat's check could not run.
enum UnavailableResponse { allow, notice }

/// A Brand's rule, per kind of Threat, for what a detected Threat does to the payment and what
/// an unavailable check does. Every ThreatKind must be covered in both maps — enforced here so a
/// brand can never ship with an undefined policy for a Threat kind. See CONTEXT.md → Posture Policy.
class PosturePolicy {
  PosturePolicy({
    required Map<ThreatKind, DetectedResponse> onDetected,
    required Map<ThreatKind, UnavailableResponse> onUnavailable,
  })  : onDetected = Map.unmodifiable(onDetected),
        onUnavailable = Map.unmodifiable(onUnavailable) {
    for (final kind in ThreatKind.values) {
      assert(onDetected.containsKey(kind), 'PosturePolicy.onDetected is missing $kind');
      assert(onUnavailable.containsKey(kind), 'PosturePolicy.onUnavailable is missing $kind');
    }
  }

  final Map<ThreatKind, DetectedResponse> onDetected;
  final Map<ThreatKind, UnavailableResponse> onUnavailable;
}
