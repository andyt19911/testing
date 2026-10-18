import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../licensing/tier.dart';
import '../screens/license_screen.dart';
import '../theme.dart';

/// Scrollable page body with a comfortable reading width and safe-area gutters.
class Body extends StatelessWidget {
  const Body({super.key, required this.children, this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 40)});
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: padding + MediaQuery.of(context).padding.copyWith(top: 0, left: 0, right: 0),
            children: children,
          ),
        ),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
        child: Row(children: [
          Container(
            width: 3,
            height: 15,
            margin: const EdgeInsets.only(right: 9),
            decoration: BoxDecoration(gradient: context.rs.signature, borderRadius: BorderRadius.circular(2)),
          ),
          Expanded(
            child: Text(text.toUpperCase(),
                style: context.text.labelMedium?.copyWith(letterSpacing: 1.3, color: context.rs.muted)),
          ),
          ?trailing,
        ]),
      );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color, this.icon, this.filled = false});
  final String text;
  final Color color;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(icon != null ? 8 : 11, 5, 11, 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: filled ? 1 : 0.14),
          borderRadius: BorderRadius.circular(99),
          border: filled ? null : Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: filled ? Colors.white : color),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(text,
                overflow: TextOverflow.ellipsis,
                style: context.text.labelSmall?.copyWith(
                    color: filled ? Colors.white : color, fontSize: 12, letterSpacing: 0.2)),
          ),
        ]),
      );
}

/// A small coloured dot, for inline status.
class StatusDot extends StatelessWidget {
  const StatusDot(this.color, {super.key, this.size = 9, this.glow = true});
  final Color color;
  final double size;
  final bool glow;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: glow ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 7, spreadRadius: 0.5)] : null,
        ),
      );
}

class TierBadge extends StatelessWidget {
  const TierBadge(this.tier, {super.key, this.filled = false});
  final Tier tier;
  final bool filled;
  @override
  Widget build(BuildContext context) => Pill(
        tier.label.toUpperCase(),
        color: AppTheme.tier(tier),
        filled: filled,
        icon: tier == Tier.free ? null : Icons.bolt,
      );
}

/// Primary call-to-action with the signature gradient.
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.onPressed, this.icon, this.enabled = true});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final on = enabled && onPressed != null;
    return Opacity(
      opacity: on ? 1 : 0.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: context.rs.signature,
          borderRadius: BorderRadius.circular(16),
          boxShadow: on
              ? [BoxShadow(color: context.rs.accent.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8))]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: on ? onPressed : null,
            child: Container(
              height: 56,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, color: Colors.white, size: 22), const SizedBox(width: 10)],
                Flexible(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.labelLarge?.copyWith(color: Colors.white, fontSize: 17)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown instead of a feature the current tier doesn't include.
class LockedCard extends StatelessWidget {
  const LockedCard(this.feature, {super.key});
  final Feature feature;

  @override
  Widget build(BuildContext context) {
    final t = feature.minTier;
    final tc = AppTheme.tier(t);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: tc.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.lock_outline, color: tc),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(feature.label, style: context.text.titleLarge)),
            TierBadge(t),
          ]),
          const SizedBox(height: 12),
          Text('Included in RideScope ${t.label}. ${t.tagline}.', style: TextStyle(color: context.rs.muted)),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: GradientButton(label: 'Unlock ${t.label}', icon: Icons.bolt, onPressed: () => openLicense(context, highlight: t)),
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: context.text.bodyMedium?.copyWith(height: 1.45))),
          if (action != null) ...[const SizedBox(width: 8), action!],
        ]),
      );
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow(this.label, this.value, {super.key, this.mono = false});
  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 150,
            child: Text(label, style: context.text.bodyMedium?.copyWith(color: context.rs.muted)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(value,
                style: context.text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: mono ? tabular : null,
                    letterSpacing: mono ? 0.3 : 0)),
          ),
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
    content: Row(children: [
      const Icon(Icons.error_outline, color: Colors.white, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(friendlyError(e), style: const TextStyle(color: Colors.white))),
    ]),
    backgroundColor: AppTheme.bad,
  ));
}

void showOk(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [
      const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
    ]),
    backgroundColor: AppTheme.ok,
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
