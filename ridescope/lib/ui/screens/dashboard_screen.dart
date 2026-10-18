import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/ecu/profile.dart';
import '../../licensing/tier.dart';
import '../theme.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import 'coding_screen.dart';
import 'discovery_screen.dart';
import 'ecus_screen.dart';
import 'faults_screen.dart';
import 'health_screen.dart';
import 'live_data_screen.dart';
import 'procedures_screen.dart';
import 'service_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // While disconnecting, AnimatedSwitcher keeps this screen mounted during
    // the fade-out even though the session is gone; render nothing then.
    final s = app.session;
    if (s == null) return const SizedBox.shrink();
    final present = s.status.values.where((e) => e.present).length;
    final hasCoding = s.profile.ecus.any((e) => e.coding.isNotEmpty);
    final hasService = s.profile.procedures.any((p) => p.$2.kind == ProcedureKind.service || p.$2.kind == ProcedureKind.date);
    final hasTools = s.profile.procedures.any((p) => p.$2.kind.defaultTier == Tier.pro);
    final rs = context.rs;

    void go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

    final tiles = <_Task>[
      _Task('Health check', 'Full scan + shareable report', Icons.monitor_heart_outlined, rs.accent, Feature.readFaults,
          () => go(const HealthScreen())),
      _Task('Fault codes', app.lastFaults == null ? 'Read and clear' : _faultSummary(app), Icons.report_gmailerrorred_outlined,
          AppTheme.warn, Feature.readFaults, () => go(const FaultsScreen())),
      _Task('Live data', 'Gauges, charts, recording', Icons.speed, rs.accent2, Feature.basicLiveData, () => go(const LiveDataScreen())),
      if (hasService)
        _Task('Service', 'Reset reminder, set date', Icons.build_circle_outlined, AppTheme.ok, Feature.serviceReset,
            () => go(const ServiceScreen())),
      if (hasCoding)
        _Task('Bike settings', 'Coding with auto-backup', Icons.tune, AppTheme.pro, Feature.coding, () => go(const CodingScreen())),
      if (hasTools)
        _Task('Workshop tools', 'Adaptations, ABS bleed', Icons.handyman_outlined, AppTheme.pro, Feature.adaptations,
            () => go(const ProceduresScreen())),
      _Task('Control units', '$present found', Icons.memory, rs.muted, Feature.identify, () => go(const EcusScreen())),
      _Task('Discovery', 'Find units and values', Icons.travel_explore, rs.muted, Feature.discovery,
          () => go(const DiscoveryScreen())),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: CustomScrollView(slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(children: [
                    Row(children: [
                      const Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Wordmark(size: 24),
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: () => openLicense(context),
                        child: Padding(padding: const EdgeInsets.all(6), child: TierBadge(app.tier)),
                      ),
                      const SizedBox(width: 2),
                      IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings_outlined), onPressed: () => go(const SettingsScreen())),
                      IconButton(
                        tooltip: 'Disconnect',
                        icon: const Icon(Icons.power_settings_new),
                        onPressed: () async {
                          final leave = app.isDemo ||
                              await confirmDialog(context, 'Disconnect?', 'This ends the session with ${s.profile.name}.',
                                  ok: 'Disconnect', cancel: 'Stay connected');
                          if (leave) await app.disconnect();
                        },
                      ),
                    ]),
                    const SizedBox(height: 10),
                    _BikeHero(),
                    if (app.bikeNotLicensed) ...[
                      const SizedBox(height: 12),
                      InfoBanner(
                        text: 'Your ${app.license.tier.label} licence already covers ${app.license.tier.maxBikes} bike(s). '
                            'This one runs as Free.',
                        color: AppTheme.warn,
                        action: TextButton(onPressed: () => openLicense(context), child: const Text('Licence')),
                      ),
                    ],
                    if (!s.profile.simulator && s.profile.ecus.any((e) => !e.verified && e.protocol != EcuProtocol.obd)) ...[
                      const SizedBox(height: 12),
                      const InfoBanner(
                        text: 'Some functions for this model aren\'t tested on a real bike yet. Reading is safe; '
                            'writing stays locked until they\'re verified.',
                        color: AppTheme.accent,
                      ),
                    ],
                    if (app.isDemo) ...[const SizedBox(height: 12), const _DemoEngineToggle()],
                    const Align(alignment: Alignment.centerLeft, child: SectionHeader('What do you want to do?')),
                  ]),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                sliver: SliverLayoutBuilder(builder: (context, constraints) {
                  final cols = Breakpoints.columns(constraints.crossAxisExtent, compact: 2, medium: 3, expanded: 4);
                  return SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _TaskTile(tiles[i], locked: !app.allows(tiles[i].feature)),
                      childCount: tiles.length,
                    ),
                  );
                }),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  static String _faultSummary(AppState app) {
    final n = app.lastFaults!.fold<int>(0, (a, f) => a + f.faults.length);
    return n == 0 ? 'No faults stored' : '$n fault${n == 1 ? '' : 's'} stored';
  }
}

class _BikeHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.session;
    if (s == null) return const SizedBox.shrink();
    final info = s.adapterInfo;
    final rs = context.rs;
    final volts = info.voltage;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: rs.outline),
        gradient: rs.heroWash(rs.accent),
      ),
      child: Stack(children: [
        Positioned(
          right: -14,
          top: 6,
          child: Opacity(opacity: 0.14, child: CustomPaint(size: const Size(180, 118), painter: MotorcycleGlyph(color: rs.accent))),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(app.isDemo ? 'DEMO BIKE' : 'CONNECTED',
                style: context.text.labelSmall?.copyWith(color: rs.accent2, letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Text(s.profile.name, style: context.text.headlineSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(s.vin ?? 'VIN not read',
                style: context.text.bodySmall?.copyWith(fontFeatures: tabular, letterSpacing: 0.5)),
            const SizedBox(height: 18),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _Stat(
                icon: Icons.settings_input_component,
                label: 'Adapter',
                value: info.isStn ? 'OBDLink' : (info.canSendLongMessages ? 'Capable' : 'Limited'),
                color: info.canSendLongMessages ? AppTheme.ok : AppTheme.warn,
              ),
              _Stat(
                icon: Icons.bolt,
                label: 'Battery',
                value: volts != null ? '${volts.toStringAsFixed(1)} V' : '—',
                color: volts == null ? rs.muted : (volts >= 12.2 ? AppTheme.ok : AppTheme.bad),
              ),
              _Stat(icon: Icons.lan_outlined, label: 'Bus', value: s.profile.isKLine ? 'K-line' : 'CAN', color: rs.accent),
              _Stat(
                icon: Icons.memory,
                label: 'Units',
                value: '${s.status.values.where((e) => e.present).length}',
                color: rs.accent,
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label, required this.value, required this.color});
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: rs.surface1.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: rs.outline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label.toUpperCase(), style: context.text.labelSmall?.copyWith(color: rs.muted, fontSize: 10)),
          Text(value, style: context.text.titleSmall?.copyWith(fontFeatures: tabular)),
        ]),
      ]),
    );
  }
}

class _DemoEngineToggle extends StatelessWidget {
  const _DemoEngineToggle();
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final on = app.simBike?.engineRunning ?? false;
    return Card(
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        secondary: Icon(Icons.local_fire_department_outlined, color: on ? AppTheme.warn : context.rs.muted),
        title: const Text('Demo engine running'),
        subtitle: const Text('Start the simulated engine to see live data move'),
        value: on,
        onChanged: (_) => app.toggleDemoEngine(),
      ),
    );
  }
}

class _Task {
  _Task(this.title, this.subtitle, this.icon, this.color, this.feature, this.onTap);
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Feature feature;
  final VoidCallback onTap;
}

class _TaskTile extends StatelessWidget {
  const _TaskTile(this.task, {required this.locked});
  final _Task task;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final rs = context.rs;
    final tint = locked ? rs.muted : task.color;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => gated(context, task.feature, task.onTap),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: tint.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(13)),
                child: Icon(task.icon, size: 24, color: tint),
              ),
              const Spacer(),
              if (locked) Icon(Icons.lock_outline, size: 16, color: rs.muted),
            ]),
            const Spacer(),
            Text(task.title, style: context.text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(task.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
            if (locked) ...[
              const SizedBox(height: 8),
              TierBadge(task.feature.minTier),
            ],
          ]),
        ),
      ),
    );
  }
}
