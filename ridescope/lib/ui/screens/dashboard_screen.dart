import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/ecu/profile.dart';
import '../../licensing/tier.dart';
import '../theme.dart';
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
    final s = app.session!;
    final info = s.adapterInfo;
    final present = s.status.values.where((e) => e.present).length;
    final hasCoding = s.profile.ecus.any((e) => e.coding.isNotEmpty);
    final hasService = s.profile.procedures.any((p) => p.$2.kind == ProcedureKind.service || p.$2.kind == ProcedureKind.date);
    final hasTools = s.profile.procedures.any((p) => p.$2.kind.defaultTier == Tier.pro);

    void go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

    final tiles = <_Task>[
      _Task('Health check', 'Full check and a report to share', Icons.monitor_heart_outlined, Feature.readFaults,
          () => go(const HealthScreen())),
      _Task('Fault codes', app.lastFaults == null ? 'Read and clear' : _faultSummary(app), Icons.warning_amber_rounded,
          Feature.readFaults, () => go(const FaultsScreen())),
      _Task('Live data', 'Gauges, charts, recording', Icons.speed, Feature.basicLiveData, () => go(const LiveDataScreen())),
      if (hasService)
        _Task('Service', 'Reset reminder, set date', Icons.build_circle_outlined, Feature.serviceReset,
            () => go(const ServiceScreen())),
      if (hasCoding)
        _Task('Bike settings', 'Coding with automatic backup', Icons.tune, Feature.coding, () => go(const CodingScreen())),
      if (hasTools)
        _Task('Workshop tools', 'Adaptations, calibration, ABS bleeding', Icons.handyman_outlined, Feature.adaptations,
            () => go(const ProceduresScreen())),
      _Task('Control units', '$present found', Icons.memory, Feature.identify, () => go(const EcusScreen())),
      _Task('Discovery', 'Find control units and values', Icons.travel_explore, Feature.discovery,
          () => go(const DiscoveryScreen())),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(app.isDemo ? 'Demo bike' : 'RideScope'),
        actions: [
          InkWell(
            borderRadius: BorderRadius.circular(99),
            onTap: () => openLicense(context),
            child: Padding(padding: const EdgeInsets.all(8), child: TierBadge(app.tier)),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => go(const SettingsScreen()),
          ),
          IconButton(
            tooltip: 'Disconnect',
            icon: const Icon(Icons.link_off),
            onPressed: () => app.disconnect(),
          ),
        ],
      ),
      body: Body(children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.two_wheeler, color: AppTheme.accent, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.profile.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text(s.vin ?? 'VIN not read',
                        style: TextStyle(fontFamily: 'monospace', color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ]),
                ),
              ]),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Pill(info.summary, color: info.canSendLongMessages ? AppTheme.ok : AppTheme.warn, icon: Icons.settings_input_component),
                if (info.voltage != null)
                  Pill('${info.voltage!.toStringAsFixed(1)} V',
                      color: info.voltage! >= 12.2 ? AppTheme.ok : AppTheme.bad, icon: Icons.battery_charging_full),
                Pill(s.profile.isKLine ? 'K-line' : 'CAN', color: Colors.blueGrey, icon: Icons.cable),
              ]),
            ]),
          ),
        ),
        if (app.bikeNotLicensed) ...[
          const SizedBox(height: 12),
          InfoBanner(
            text: 'Your ${app.license.tier.label} licence is already used on ${app.license.tier.maxBikes} bike(s). '
                'This bike runs as Free. Manage bikes under Licence.',
            color: AppTheme.warn,
            action: TextButton(onPressed: () => openLicense(context), child: const Text('Licence')),
          ),
        ],
        if (!s.profile.simulator && s.profile.ecus.any((e) => !e.verified && e.protocol != EcuProtocol.obd)) ...[
          const SizedBox(height: 12),
          const InfoBanner(
            text: 'Some functions for this model haven\'t been tested on a real bike yet. Reading is safe; '
                'writing stays locked until they are verified.',
            color: AppTheme.accent,
          ),
        ],
        if (app.isDemo) ...[
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.local_gas_station_outlined),
              title: const Text('Demo engine running'),
              subtitle: const Text('Start the simulated engine to see live data move'),
              value: app.simBike?.engineRunning ?? false,
              onChanged: (_) => app.toggleDemoEngine(),
            ),
          ),
        ],
        const SectionHeader('What do you want to do?'),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 560 ? 3 : 2;
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.15,
            children: [for (final t in tiles) _TaskTile(t, locked: !app.allows(t.feature))],
          );
        }),
      ]),
    );
  }

  static String _faultSummary(AppState app) {
    final n = app.lastFaults!.fold<int>(0, (a, f) => a + f.faults.length);
    return n == 0 ? 'No faults stored' : '$n fault${n == 1 ? '' : 's'} stored';
  }
}

class _Task {
  _Task(this.title, this.subtitle, this.icon, this.feature, this.onTap);
  final String title;
  final String subtitle;
  final IconData icon;
  final Feature feature;
  final VoidCallback onTap;
}

class _TaskTile extends StatelessWidget {
  const _TaskTile(this.task, {required this.locked});
  final _Task task;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => gated(context, task.feature, task.onTap),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(task.icon, size: 30, color: locked ? scheme.onSurfaceVariant : AppTheme.accent),
              const Spacer(),
              if (locked) TierBadge(task.feature.minTier),
            ]),
            const Spacer(),
            Text(task.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(task.subtitle,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}
