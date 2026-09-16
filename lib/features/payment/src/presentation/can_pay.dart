import '../../../security_guard/security_guard.dart' show PostureState;
import 'payment_confirmation_state.dart';

/// Whether the Pay button is enabled: the flow is awaiting confirmation with a loaded Payment,
/// and the Security Posture has been assessed at least once and doesn't block. See
/// docs/architecture.md §7.
bool canPay(PaymentConfirmationState flow, PostureState posture) =>
    flow.phase is AwaitingConfirmation &&
    flow.payment != null &&
    posture.hasFirstAssessment &&
    !(posture.verdict?.isBlocked ?? false);
