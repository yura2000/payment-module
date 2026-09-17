import 'package:flutter/material.dart';

import '../../../../brand_engine/brand_engine.dart';
import '../domain/payment.dart';
import 'format_money.dart';

/// The Payment's headline: what is owed, to whom, under which reference. Reads Brand tokens for
/// its shape and weight; it never asks which Brand is active (docs/architecture.md §2
/// principle 5).
class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.payment});

  final Payment payment;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing * 1.25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Amount due', style: text.labelLarge),
            Text(
              formatMoney(payment.amount),
              style: text.displaySmall?.copyWith(
                fontWeight: tokens.headlineWeight,
              ),
            ),
            SizedBox(height: tokens.spacing / 2),
            Text(
              'To ${payment.payee} · ${payment.reference}',
              style: text.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Retail's Brand feature: promotional content. Purely visual — it never changes the amount
/// (CONTEXT.md → Promo Banner).
class PromoBanner extends StatelessWidget {
  const PromoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.all(tokens.spacing * 1.25),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.radius),
        gradient: LinearGradient(colors: [scheme.primary, scheme.secondary]),
      ),
      child: Row(
        children: [
          Icon(Icons.local_offer, color: scheme.onPrimary),
          SizedBox(width: tokens.spacing),
          Expanded(
            child: Text(
              'Member offer · earn points on this payment',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.onPrimary,
                fontWeight: tokens.headlineWeight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Utility's Brand feature: the Payment's Line Items itemised, with a total that is the
/// Payment's own amount rather than a re-derived sum (CONTEXT.md → Bill Breakdown).
class BillBreakdown extends StatelessWidget {
  const BillBreakdown({super.key, required this.payment});

  final Payment payment;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Bill breakdown', style: text.titleSmall),
            ),
            const Divider(),
            for (final item in payment.lineItems)
              Padding(
                padding: EdgeInsets.symmetric(vertical: tokens.spacing / 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(item.description, style: text.bodyMedium),
                    ),
                    Text(formatMoney(item.amount), style: text.bodyMedium),
                  ],
                ),
              ),
            const Divider(),
            Row(
              children: [
                Expanded(child: Text('Total', style: text.titleSmall)),
                Text(formatMoney(payment.amount), style: text.titleSmall),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The call to action. Its copy is Brand configuration ([label]); whether it is live is the
/// `canPay` derived rule's answer, computed by the page (docs/architecture.md §7).
class PayButton extends StatelessWidget {
  const PayButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: const Icon(Icons.lock),
      label: Text(label),
    ),
  );
}
