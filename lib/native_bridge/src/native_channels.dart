/// The six channel names of docs/architecture.md §9 (ADR-0003: four method channels, two event
/// channels). Mirrors Kotlin's `ChannelNames`; both sides are pinned to
/// contract/fixtures/channels.json by a test.
abstract final class NativeChannels {
  static const _prefix = 'dev.test.payment';
  static const securityEnvironment = '$_prefix/security.environment';
  static const securityEnvironmentEvents =
      '$_prefix/security.environment/events';
  static const window = '$_prefix/window';
  static const paymentJob = '$_prefix/payment.job';
  static const paymentJobEvents = '$_prefix/payment.job/events';
  static const app = '$_prefix/app';
}
