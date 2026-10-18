import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../app/garage.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import 'connect_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final bikes = app.garage.bikes;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                _TopBar(onSettings: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
                const SizedBox(height: 16),
                const _Hero(),
                if (app.error != null) ...[
                  const SizedBox(height: 14),
                  InfoBanner(text: app.error!, color: AppTheme.bad, icon: Icons.error_outline),
                ],
                if (bikes.isNotEmpty) ...[
                  SectionHeader('My garage', trailing: Text('${bikes.length}', style: context.text.labelMedium?.copyWith(color: context.rs.muted))),
                  for (final b in bikes) ...[_BikeCard(b), const SizedBox(height: 10)],
                ],
                const SectionHeader('Adapters that work'),
                const _AdapterGuide(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSettings});
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Row(children: [
      const Flexible(
        child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Wordmark(size: 26)),
      ),
      const Spacer(),
      InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: () => openLicense(context),
        child: Padding(padding: const EdgeInsets.all(6), child: TierBadge(app.license.tier)),
      ),
      const SizedBox(width: 4),
      IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings_outlined), onPressed: onSettings),
    ]);
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final rs = context.rs;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: rs.outline),
        gradient: rs.heroWash(rs.accent),
      ),
      child: Stack(children: [
        Positioned(
          right: -20,
          bottom: -10,
          child: Opacity(
            opacity: 0.18,
            child: CustomPaint(size: const Size(230, 150), painter: MotorcycleGlyph(color: rs.accent)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(gradient: rs.signature, borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.bluetooth_searching, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 18),
            Text('Connect to\nyour bike', style: context.text.displaySmall),
            const SizedBox(height: 10),
            SizedBox(
              width: 320,
              child: Text(
                'Plug the OBD adapter into the diagnostic socket, switch the ignition on and leave the engine off.',
                style: context.text.bodyLarge?.copyWith(color: rs.muted),
              ),
            ),
            const SizedBox(height: 22),
            GradientButton(
              label: 'Connect',
              icon: Icons.bluetooth_searching,
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectScreen())),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Try the demo bike'),
                onPressed: () => runConnect(context, () => app.connectDemo()),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _AdapterGuide extends StatelessWidget {
  const _AdapterGuide();

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const _AdapterRow('OBDLink LX / MX+ / CX', 'Recommended. Every function, including service reset and coding.', AppTheme.ok),
            _divider(context),
            const _AdapterRow('UniCarScan UCSI-2000 / 2100', 'Every function on most bikes.', AppTheme.ok),
            _divider(context),
            const _AdapterRow('ELM327 (generic)', 'Faults and live data. The app tests whether it can do service reset on connect.', AppTheme.warn),
            const SizedBox(height: 14),
            Row(children: [
              Icon(Icons.cable, size: 18, color: context.rs.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Bikes with the round 10-pin socket need a 10-pin to OBD-II cable.',
                    style: context.text.bodySmall),
              ),
            ]),
          ]),
        ),
      );

  Widget _divider(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Divider(height: 1, color: context.rs.outline));
}

class _AdapterRow extends StatelessWidget {
  const _AdapterRow(this.name, this.detail, this.color);
  final String name;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 3), child: StatusDot(color)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: context.text.titleSmall),
            const SizedBox(height: 2),
            Text(detail, style: context.text.bodySmall),
          ]),
        ),
      ]);
}

class _BikeCard extends StatelessWidget {
  const _BikeCard(this.bike);
  final GarageBike bike;

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final faultColor = bike.faultCount == null
        ? rs.muted
        : (bike.faultCount == 0 ? AppTheme.ok : AppTheme.warn);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectScreen())),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(gradient: rs.heroWash(rs.accent), borderRadius: BorderRadius.circular(14), border: Border.all(color: rs.outline)),
              child: CustomPaint(painter: MotorcycleGlyph(color: rs.accent, strokeWidth: 2.2), child: const SizedBox.expand()),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(bike.title, style: context.text.titleMedium),
                Text(bike.vin, style: context.text.bodySmall?.copyWith(fontFeatures: tabular, letterSpacing: 0.4)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  Pill('Seen ${DateFormat('d MMM').format(bike.lastConnected)}', color: rs.muted),
                  if (bike.faultCount != null)
                    Pill(bike.faultCount == 0 ? 'No faults' : '${bike.faultCount} faults', color: faultColor),
                  if (bike.serviceDue != null) Pill('Service ${bike.serviceDue}', color: AppTheme.accent),
                ]),
              ]),
            ),
            Icon(Icons.chevron_right, color: rs.muted),
          ]),
        ),
      ),
    );
  }
}
