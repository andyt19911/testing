import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app_state.dart';
import '../../core/ecu/dtc_database.dart';
import '../../core/ecu/profile.dart';
import '../../core/services/fault_service.dart';
import '../../core/services/live_data_service.dart';
import '../../core/services/report.dart';
import '../../licensing/tier.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'faults_screen.dart';

/// One tap: control units, faults, service status and key readings, with a
/// report to share.
class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});
  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  String _step = 'Starting';
  bool _done = false;
  List<EcuFaults> _faults = [];
  final Map<String, String> _service = {};
  final Map<String, String> _values = {};

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final app = context.read<AppState>();
    final s = app.session!;
    try {
      setState(() => _step = 'Checking control units');
      await s.scan();
      setState(() => _step = 'Reading fault memory');
      _faults = await app.faults.readAll();
      await app.rememberFaults(_faults);
      setState(() => _step = 'Reading service status');
      for (final (ecu, p) in s.profile.procedures.where((x) => x.$2.kind == ProcedureKind.service)) {
        if (!(s.status[ecu.id]?.present ?? false)) continue;
        _service.addAll(await app.runner.readStatus(ecu, p));
      }
      final due = _service.values.firstOrNull;
      if (due != null) await app.rememberService(due);
      setState(() => _step = 'Taking readings');
      for (final ch in LiveDataService.available(s).where((c) => c.def.basic)) {
        try {
          final v = await app.live.readOnce(ch);
          _values['${ch.def.name} (${ch.ecu.shortName})'] = '${v.text} ${ch.def.unit}'.trim();
        } catch (_) {}
      }
      final volts = await s.adapter.readVoltage();
      if (volts != null) _values['Battery at socket'] = '${volts.toStringAsFixed(1)} V';
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.session!;
    final all = _faults.expand((f) => f.faults).toList();
    final high = all.where((f) => f.severity == Severity.high).length;
    final present = s.status.values.where((e) => e.present).length;
    final score = !_done
        ? null
        : high > 0
            ? ('Needs attention', AppTheme.bad, Icons.report_outlined)
            : all.isNotEmpty
                ? ('Mostly healthy', AppTheme.warn, Icons.info_outline)
                : ('Healthy', AppTheme.ok, Icons.verified_outlined);
    return Scaffold(
      appBar: AppBar(title: const Text('Health check')),
      bottomNavigationBar: _done
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  icon: Icon(app.allows(Feature.healthReport) ? Icons.ios_share : Icons.lock_outline),
                  label: Text(app.allows(Feature.healthReport) ? 'Share report' : 'Share report (Plus)'),
                  onPressed: () => gated(context, Feature.healthReport, () {
                    final text = HealthReport.build(s, faults: _faults, service: _service, keyValues: _values);
                    SharePlus.instance.share(ShareParams(text: text, subject: 'RideScope health report'));
                  }),
                ),
              ),
            )
          : null,
      body: !_done
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('$_step…'),
              ]),
            )
          : Body(children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(children: [
                    Icon(score!.$3, size: 48, color: score.$2),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(score.$1, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: score.$2)),
                        Text('$present control units answered · ${all.length} fault${all.length == 1 ? '' : 's'}'),
                      ]),
                    ),
                  ]),
                ),
              ),
              if (_service.isNotEmpty) ...[
                const SectionHeader('Service'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [for (final e in _service.entries) KeyValueRow(e.key, e.value)]),
                  ),
                ),
              ],
              SectionHeader('Faults',
                  trailing: TextButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FaultsScreen())),
                      child: const Text('Details'))),
              if (all.isEmpty)
                const InfoBanner(text: 'No faults stored in any control unit.', color: AppTheme.ok, icon: Icons.check_circle_outline)
              else
                for (final f in all)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InfoBanner(
                      text: '${f.ecu.shortName} ${f.code}: ${f.description}',
                      color: AppTheme.severity(f.severity),
                      icon: Icons.warning_amber_rounded,
                    ),
                  ),
              if (_values.isNotEmpty) ...[
                const SectionHeader('Readings'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [for (final e in _values.entries) KeyValueRow(e.key, e.value)]),
                  ),
                ),
              ],
            ]),
    );
  }
}
