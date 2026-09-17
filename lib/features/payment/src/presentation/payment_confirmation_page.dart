import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../brand_engine/brand_engine.dart';
import '../../../security_guard/security_guard.dart';
import '../domain/payment.dart';
import '../domain/payment_job_progress.dart';
import '../domain/payment_processor.dart';
import '../domain/payment_repository.dart';
import 'can_pay.dart';
import 'payment_brand_config.dart';
import 'payment_confirmation_bloc.dart';
import 'payment_confirmation_event.dart';
import 'payment_confirmation_state.dart';
import 'result_view.dart';
import 'section_widgets.dart';

/// The Payment Confirmation screen. Builds the two units — the flow bloc and the posture cubit —
/// from the ports in the locator plus this Brand's configuration, and holds the Secure Window for
/// as long as it is mounted (docs/architecture.md §7, §11).
///
/// The two blocs never talk to each other: the only posture fact the flow needs rides inside
/// `PayPressed(verdict)`, and every cross-concern rule is the pure `canPay` function.
class PaymentConfirmationPage extends StatelessWidget {
  const PaymentConfirmationPage({super.key});

  @override
  Widget build(BuildContext context) {
    final brand = BrandScope.of(context);
    final locator = GetIt.I;
    return MultiBlocProvider(
      providers: [
        BlocProvider<SecurityPostureCubit>(
          create: (_) => SecurityPostureCubit(
            locator<SecurityEnvironment>(),
            brand.feature<SecurityBrandConfig>().policy,
          ),
        ),
        BlocProvider<PaymentConfirmationBloc>(
          create: (_) => PaymentConfirmationBloc(
            locator<PaymentRepository>(),
            locator<PaymentProcessor>(),
            scanMinDuration: brand.tokens.scanMinDuration,
          )..add(const Started()),
        ),
      ],
      child: SecureSessionScope(
        controller: locator<SecureWindowController>(),
        child: const _PaymentConfirmationView(),
      ),
    );
  }
}

class _PaymentConfirmationView extends StatefulWidget {
  const _PaymentConfirmationView();

  @override
  State<_PaymentConfirmationView> createState() =>
      _PaymentConfirmationViewState();
}

class _PaymentConfirmationViewState extends State<_PaymentConfirmationView> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Coming back to the screen silently re-runs the one-shot checks. The scope beside us
    // re-asserts the window flag on the same signal — one lifetime, two owners (§11).
    _lifecycle = AppLifecycleListener(
      onResume: () => context.read<SecurityPostureCubit>().onResumed(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = BrandScope.of(context);
    final config = brand.feature<PaymentBrandConfig>();
    final spacing = context.tokens.spacing;

    return BlocBuilder<PaymentConfirmationBloc, PaymentConfirmationState>(
      builder: (context, flow) => PopScope(
        // The page blocks back while the Payment Job runs; the Secure Window scope never blocks
        // navigation (§11.1(iv)).
        canPop: flow.phase is! Processing,
        child: Scaffold(
          appBar: AppBar(title: Text(brand.displayName)),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: ListView(
                  padding: EdgeInsets.all(spacing),
                  children: _bodyFor(context, flow, config, spacing),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _bodyFor(
    BuildContext context,
    PaymentConfirmationState flow,
    PaymentBrandConfig config,
    double spacing,
  ) {
    switch (flow.phase) {
      case Scanning():
        // A const instance: an emission during the Scan phase hands the element the same widget
        // and the animating scan is never rebuilt (§12.1).
        return const [_ScanPhaseView()];

      case AwaitingConfirmation():
        return [
          const _PostureBannerSlot(),
          for (final section in config.sections) ...[
            SizedBox(height: spacing),
            _sectionWidget(context, section, flow.payment, config.ctaLabel),
          ],
        ];

      case Processing(:final percent):
        return [
          const _PostureBannerSlot(),
          if (flow.payment case final payment?) ...[
            SizedBox(height: spacing),
            SummaryCard(payment: payment),
          ],
          SizedBox(height: spacing * 2),
          LinearProgressIndicator(value: percent / 100),
          SizedBox(height: spacing),
          Text('Processing payment… $percent%', textAlign: TextAlign.center),
        ];

      case Completed(:final outcome):
        return [
          SizedBox(height: spacing),
          _ResultSlot(outcome: outcome),
        ];
    }
  }

  Widget _sectionWidget(
    BuildContext context,
    PaymentSection section,
    Payment? payment,
    String ctaLabel,
  ) => switch (section) {
    // A Payment that hasn't loaded yet leaves its Sections empty rather than showing a spinner
    // per Section; the Scan phase has already covered that wait in the normal case (§7).
    SummarySection() => payment == null
        ? const SizedBox.shrink()
        : SummaryCard(payment: payment),
    PromoBannerSection() => const PromoBanner(),
    BillBreakdownSection() => payment == null
        ? const SizedBox.shrink()
        : BillBreakdown(payment: payment),
    PayButtonSection() => _PayButtonSlot(ctaLabel: ctaLabel),
    CustomSection(:final builder) => payment == null
        ? const SizedBox.shrink()
        : builder(context, payment),
  };
}

/// The scan, isolated. Const so a flow emission cannot rebuild it (§12.1).
class _ScanPhaseView extends StatelessWidget {
  const _ScanPhaseView();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      SizedBox(height: 32),
      SecurityScanView(),
      SizedBox(height: 24),
      Text('Checking this device…', textAlign: TextAlign.center),
    ],
  );
}

/// Draws the Policy Verdict. Watches the cubit only — no relay through the flow bloc (§7).
class _PostureBannerSlot extends StatelessWidget {
  const _PostureBannerSlot();

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<SecurityPostureCubit, PostureState>(
        builder: (context, posture) => PostureBanner(verdict: posture.verdict),
      );
}

/// The one place both states are read at once — and it reads them through the pure `canPay`
/// rule rather than re-deriving the condition inline (§7).
class _PayButtonSlot extends StatelessWidget {
  const _PayButtonSlot({required this.ctaLabel});

  final String ctaLabel;

  @override
  Widget build(BuildContext context) {
    final flow = context.watch<PaymentConfirmationBloc>().state;
    final posture = context.watch<SecurityPostureCubit>().state;
    final verdict = posture.verdict;

    return PayButton(
      // The CTA says it is still checking until the first assessment lands.
      label: posture.hasFirstAssessment ? ctaLabel : 'Checking…',
      enabled: canPay(flow, posture),
      onPressed: verdict == null
          ? null
          : () => context.read<PaymentConfirmationBloc>().add(
              PayPressed(verdict),
            ),
    );
  }
}

class _ResultSlot extends StatelessWidget {
  const _ResultSlot({required this.outcome});

  final PaymentJobProgress outcome;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<SecurityPostureCubit, PostureState>(
        builder: (context, posture) => ResultView(
          outcome: outcome,
          verdict: posture.verdict,
          onRetry: () => context.read<PaymentConfirmationBloc>().add(
            const RetryPressed(),
          ),
        ),
      );
}
