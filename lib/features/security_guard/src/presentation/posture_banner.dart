import 'package:flutter/material.dart';

import '../../../../brand_engine/brand_engine.dart';
import '../../../../core/threat.dart';
import '../domain/policy_verdict.dart';

/// Tells the user what the Policy Verdict found, in the Brand's shape. A dumb widget: it is
/// handed a verdict rather than reading `SecurityPostureCubit`, so the page owns the
/// subscription and this stays reusable — the Result View draws it as its caveat
/// (docs/architecture.md §7). [verdict] is null until the first assessment lands.
///
/// Blockers beat warnings beat notices, and only the winning band renders: one posture, one
/// banner. Nothing renders when there is nothing to say.
class PostureBanner extends StatelessWidget {
  const PostureBanner({super.key, required this.verdict});

  final PolicyVerdict? verdict;

  @override
  Widget build(BuildContext context) {
    final verdict = this.verdict;
    if (verdict == null || !verdict.hasAnything) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final (icon, background, foreground, message) = switch (verdict) {
      PolicyVerdict(blockers: final kinds) when kinds.isNotEmpty => (
        Icons.gpp_bad,
        scheme.errorContainer,
        scheme.onErrorContainer,
        'Payment blocked — ${_detected(kinds)}.',
      ),
      PolicyVerdict(warnings: final kinds) when kinds.isNotEmpty => (
        Icons.warning_amber,
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
        'Heads up — ${_detected(kinds)}. You can still continue.',
      ),
      PolicyVerdict(notices: final kinds) => (
        Icons.info_outline,
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        '${_unavailable(kinds)}.',
      ),
    };

    final spacing = context.tokens.spacing;
    return Card(
      color: background,
      child: Padding(
        padding: EdgeInsets.all(spacing),
        child: Row(
          children: [
            Icon(icon, color: foreground),
            SizedBox(width: spacing),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _detected(Set<ThreatKind> kinds) =>
      kinds.map(_detectedLabel).join(' and ');

  static String _unavailable(Set<ThreatKind> kinds) =>
      kinds.map(_unavailableLabel).join('; ');

  static String _detectedLabel(ThreatKind kind) => switch (kind) {
    ThreatKind.rooted => 'this device appears to be rooted',
    ThreatKind.screenRecording => 'screen recording is active',
  };

  static String _unavailableLabel(ThreatKind kind) => switch (kind) {
    ThreatKind.rooted => 'Root detection could not run on this device',
    ThreatKind.screenRecording =>
      'Screen-recording protection could not be verified on this Android version',
  };
}
