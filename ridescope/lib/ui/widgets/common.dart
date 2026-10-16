import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../licensing/tier.dart';
import '../screens/license_screen.dart';
import '../theme.dart';

/// Max content width so tablets and the web demo don't stretch rows.
class Body extends StatelessWidget {
  const Body({super.key, required this.children, this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 32)});
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: padding, children: children),
        ),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Row(children: [
          Expanded(
            child: Text(text.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ),
          ?trailing,
        ]),
      );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
          Flexible(
            child: Text(text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ]),
      );
}

class TierBadge extends StatelessWidget {
  const TierBadge(this.tier, {super.key});
  final Tier tier;
  @override
  Widget build(BuildContext context) =>
      Pill(tier.label, color: AppTheme.tier(tier), icon: tier == Tier.free ? null : Icons.workspace_premium);
}

/// Shown instead of a feature the current tier doesn't include.
class LockedCard extends StatelessWidget {
  const LockedCard(this.feature, {super.key});
  final Feature feature;

  @override
  Widget build(BuildContext context) {
    final t = feature.minTier;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.lock_outline, color: AppTheme.tier(t)),
            const SizedBox(width: 8),
            Expanded(child: Text(feature.label, style: Theme.of(context).textTheme.titleMedium)),
            TierBadge(t),
          ]),
          const SizedBox(height: 8),
          Text('Included in RideScope ${t.label}. ${t.tagline}.'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => openLicense(context, highlight: t),
            child: Text('See ${t.label}'),
          ),
        ]),
      ),
    );
  }
}

void openLicense(BuildContext context, {Tier? highlight}) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => LicenseScreen(highlight: highlight)));

/// Runs [body] if the tier allows [f], otherwise opens the upgrade screen.
void gated(BuildContext context, Feature f, VoidCallback body) {
  if (context.read<AppState>().allows(f)) {
    body();
  } else {
    openLicense(context, highlight: f.minTier);
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.text, required this.color, this.icon = Icons.info_outline, this.action});
  final String text;
  final Color color;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ]),
      );
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 140,
            child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}

/// Message for errors shown to riders (no stack traces).
String friendlyError(Object e) {
  final s = e.toString();
  return s.replaceFirst(RegExp(r'^(Exception|StateError|Bad state): ?'), '');
}

void showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(friendlyError(e)),
    backgroundColor: AppTheme.bad,
  ));
}

Future<bool> confirmDialog(BuildContext context, String title, String message,
    {String ok = 'Continue', String cancel = 'Cancel', bool destructive = false}) async {
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(cancel)),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppTheme.bad) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}
