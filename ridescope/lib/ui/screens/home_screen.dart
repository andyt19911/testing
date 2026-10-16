import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../app/garage.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'connect_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final bikes = app.garage.bikes;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('RideScope'),
        actions: [
          InkWell(
            borderRadius: BorderRadius.circular(99),
            onTap: () => openLicense(context),
            child: Padding(padding: const EdgeInsets.all(8), child: TierBadge(app.license.tier)),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: Body(children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.two_wheeler, size: 44, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text('Connect to your bike', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Plug the OBD adapter into the diagnostic socket, switch the ignition on and leave the engine off.'),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.bluetooth_searching),
                  label: const Text('Connect'),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectScreen())),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Try the demo bike'),
                  onPressed: () => runConnect(context, () => app.connectDemo()),
                ),
              ),
            ]),
          ),
        ),
        if (app.error != null) ...[
          const SizedBox(height: 12),
          InfoBanner(text: app.error!, color: AppTheme.bad, icon: Icons.error_outline),
        ],
        if (bikes.isNotEmpty) ...[
          const SectionHeader('My garage'),
          for (final b in bikes) ...[_BikeCard(b), const SizedBox(height: 8)],
        ],
        const SectionHeader('Adapters that work'),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _AdapterRow('OBDLink LX / MX+ / CX', 'Recommended. Every function, including service reset and coding.', AppTheme.ok),
              _AdapterRow('UniCarScan UCSI-2000 / 2100', 'Every function on most bikes.', AppTheme.ok),
              _AdapterRow('ELM327 (genuine or clone)', 'Faults and live data only. Can\'t send the long messages needed for service reset.', AppTheme.warn),
              SizedBox(height: 8),
              Text('Bikes with the round 10-pin socket need a 10-pin to OBD-II cable.'),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _AdapterRow extends StatelessWidget {
  const _AdapterRow(this.name, this.detail, this.color);
  final String name;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 4), child: Icon(Icons.circle, size: 10, color: color)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(detail, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ),
        ]),
      );
}

class _BikeCard extends StatelessWidget {
  const _BikeCard(this.bike);
  final GarageBike bike;

  @override
  Widget build(BuildContext context) {
    final sub = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const CircleAvatar(child: Icon(Icons.two_wheeler)),
        title: Text(bike.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(bike.vin, style: TextStyle(color: sub, fontFamily: 'monospace')),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            Pill('Last seen ${DateFormat('d MMM').format(bike.lastConnected)}', color: Colors.blueGrey),
            if (bike.faultCount != null)
              Pill(bike.faultCount == 0 ? 'No faults' : '${bike.faultCount} faults',
                  color: bike.faultCount == 0 ? AppTheme.ok : AppTheme.warn),
            if (bike.serviceDue != null) Pill('Service ${bike.serviceDue}', color: AppTheme.accent),
          ]),
        ]),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectScreen())),
      ),
    );
  }
}
