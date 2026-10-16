import 'dart:async';
import 'dart:collection';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app_state.dart';
import '../../core/services/live_data_service.dart';
import '../../licensing/tier.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/gauge.dart';

class LiveDataScreen extends StatefulWidget {
  const LiveDataScreen({super.key});
  @override
  State<LiveDataScreen> createState() => _LiveDataScreenState();
}

class _LiveDataScreenState extends State<LiveDataScreen> {
  late LiveDataService _live;
  List<LiveChannel> _available = [];
  List<LiveChannel> _selected = [];
  final Map<String, ListQueue<FlSpot>> _history = {};
  StreamSubscription<LiveSample>? _sub;
  bool _charts = false;
  final _start = DateTime.now();

  static const _historyLength = 150;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _live = app.live;
    _available = LiveDataService.available(app.session!);
    // Prefer the bike's own ECU values; skip OBD duplicates in the default view.
    final own = _available.where((c) => c.ecu.id != 'obd').toList();
    _selected = (own.isNotEmpty ? own : _available).take(6).toList();
    _sub = _live.samples.listen(_onSample);
    _live.start(_selected);
  }

  void _onSample(LiveSample s) {
    final v = s.value;
    if (v != null) {
      final q = _history.putIfAbsent(s.channel.key, ListQueue.new);
      q.addLast(FlSpot(s.time.difference(_start).inMilliseconds / 1000, v));
      while (q.length > _historyLength) {
        q.removeFirst();
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _live.stop();
    _live.recording = false;
    super.dispose();
  }

  void _setSelection(List<LiveChannel> sel) {
    setState(() => _selected = sel);
    _live.updateChannels(sel);
  }

  Future<void> _pick() async {
    final app = context.read<AppState>();
    final locked = LiveDataService.lockedChannels(app.session!);
    final chosen = {for (final c in _selected) c.key};
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          final groups = <String, List<LiveChannel>>{};
          for (final ch in _available) {
            groups.putIfAbsent('${ch.ecu.shortName} · ${ch.def.group}', () => []).add(ch);
          }
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            builder: (c, scroll) => Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Text('Values (${chosen.length})', style: Theme.of(c).textTheme.titleLarge),
                  const Spacer(),
                  FilledButton(onPressed: () => Navigator.pop(c, chosen), child: const Text('Show')),
                ]),
              ),
              Expanded(
                child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
                  for (final g in groups.entries) ...[
                    SectionHeader(g.key),
                    for (final ch in g.value)
                      CheckboxListTile(
                        value: chosen.contains(ch.key),
                        title: Text(ch.def.name),
                        subtitle: ch.def.unit.isEmpty ? null : Text(ch.def.unit),
                        onChanged: (v) => set(() => v == true ? chosen.add(ch.key) : chosen.remove(ch.key)),
                      ),
                  ],
                  if (locked.isNotEmpty) ...[
                    SectionHeader('${locked.length} more with Plus'),
                    for (final ch in locked.take(8))
                      ListTile(
                        leading: const Icon(Icons.lock_outline),
                        title: Text(ch.def.name),
                        subtitle: Text(ch.ecu.shortName),
                        onTap: () => openLicense(context, highlight: Tier.plus),
                      ),
                  ],
                ]),
              ),
            ]),
          );
        },
      ),
    );
    if (result != null) _setSelection(_available.where((c) => result.contains(c.key)).toList());
  }

  void _toggleRecording() {
    if (_live.recording) {
      _live.recording = false;
      final csv = _live.exportCsv();
      SharePlus.instance.share(ShareParams(text: csv, subject: 'RideScope live data'));
    } else {
      _live.recorded.clear();
      _live.recording = true;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live data'),
        actions: [
          IconButton(
            tooltip: _charts ? 'Gauges' : 'Charts',
            icon: Icon(_charts ? Icons.speed : Icons.show_chart),
            onPressed: () => setState(() => _charts = !_charts),
          ),
          IconButton(tooltip: 'Choose values', icon: const Icon(Icons.tune), onPressed: _pick),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _live.recording ? AppTheme.bad : null,
        icon: Icon(_live.recording ? Icons.stop : (app.allows(Feature.fullLiveData) ? Icons.fiber_manual_record : Icons.lock_outline)),
        label: Text(_live.recording ? 'Stop · ${_live.recorded.length} samples' : 'Record'),
        onPressed: () => gated(context, Feature.fullLiveData, _toggleRecording),
      ),
      body: _selected.isEmpty
          ? Body(children: [
              const InfoBanner(text: 'Pick the values you want to watch.', color: AppTheme.accent),
              const SizedBox(height: 12),
              FilledButton(onPressed: _pick, child: const Text('Choose values')),
            ])
          : _charts
              ? Body(children: [for (final ch in _selected) _ChartCard(ch, _history[ch.key], _live.latest[ch.key])])
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: LayoutBuilder(builder: (context, c) {
                      final cols = c.maxWidth > 560 ? 3 : 2;
                      return GridView.count(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        crossAxisCount: cols,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.95,
                        children: [for (final ch in _selected) _GaugeCard(ch, _live.latest[ch.key])],
                      );
                    }),
                  ),
                ),
    );
  }
}

class _GaugeCard extends StatelessWidget {
  const _GaugeCard(this.ch, this.sample);
  final LiveChannel ch;
  final LiveSample? sample;

  @override
  Widget build(BuildContext context) {
    final d = ch.def;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(ch.ecu.shortName, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Expanded(
            child: Center(
              child: d.min != null && d.max != null
                  ? ArcGauge(value: sample?.value, min: d.min!, max: d.max!, label: d.name, unit: d.unit)
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      FittedBox(
                        child: Text(sample?.text ?? '—',
                            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
                      ),
                      Text(d.unit, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard(this.ch, this.history, this.sample);
  final LiveChannel ch;
  final ListQueue<FlSpot>? history;
  final LiveSample? sample;

  @override
  Widget build(BuildContext context) {
    final spots = history?.toList() ?? const <FlSpot>[];
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${ch.def.name} · ${ch.ecu.shortName}', style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('${sample?.text ?? '—'} ${ch.def.unit}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, fontFeatures: [FontFeature.tabularFigures()])),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              height: 110,
              child: spots.length < 2
                  ? const Center(child: Text('Collecting…'))
                  : LineChart(
                      LineChartData(
                        minY: ch.def.min,
                        maxY: ch.def.max,
                        gridData: FlGridData(
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant.withValues(alpha: 0.3), strokeWidth: 1),
                        ),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(),
                          rightTitles: const AxisTitles(),
                          bottomTitles: const AxisTitles(),
                          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
                        ),
                        lineTouchData: const LineTouchData(enabled: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: false,
                            color: AppTheme.accent,
                            barWidth: 2.5,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(show: true, color: AppTheme.accent.withValues(alpha: 0.12)),
                          ),
                        ],
                      ),
                      duration: Duration.zero,
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
