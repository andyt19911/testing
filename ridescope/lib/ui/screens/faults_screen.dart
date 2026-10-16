import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/ecu/dtc_database.dart';
import '../../core/protocol/diag_client.dart';
import '../../core/services/fault_service.dart';
import '../../core/util/hex.dart';
import '../../licensing/tier.dart';
import '../theme.dart';
import '../widgets/common.dart';

class FaultsScreen extends StatefulWidget {
  const FaultsScreen({super.key});
  @override
  State<FaultsScreen> createState() => _FaultsScreenState();
}

class _FaultsScreenState extends State<FaultsScreen> {
  List<EcuFaults>? _result;
  String? _reading;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final app = context.read<AppState>();
    setState(() {
      _result = null;
      _reading = 'Starting';
    });
    try {
      final r = await app.faults.readAll(onEcu: (e) => setState(() => _reading = e.name));
      await app.rememberFaults(r);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _reading = null);
    }
  }

  Future<void> _clear() async {
    final app = context.read<AppState>();
    final ecus = _result!.where((f) => f.faults.isNotEmpty).map((f) => f.ecu).toList();
    if (!await confirmDialog(context, 'Clear fault memory?',
        'This clears ${ecus.length} control unit(s). Faults that are still present will come back. '
        'Write down or share the codes first if you need them.',
        ok: 'Clear')) {
      return;
    }
    setState(() => _clearing = true);
    try {
      final r = await app.faults.clearAll(ecus);
      final failed = r.entries.where((e) => e.value != null).toList();
      if (mounted && failed.isNotEmpty) {
        showError(context, 'Could not clear ${failed.map((e) => e.key.shortName).join(', ')}: ${failed.first.value}');
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
    await _read();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final r = _result;
    final total = r?.fold<int>(0, (a, f) => a + f.faults.length) ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fault codes'),
        actions: [IconButton(onPressed: _reading == null ? _read : null, icon: const Icon(Icons.refresh), tooltip: 'Read again')],
      ),
      bottomNavigationBar: r != null && total > 0
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  icon: _clearing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(app.allows(Feature.clearFaults) ? Icons.delete_sweep_outlined : Icons.lock_outline),
                  label: Text(app.allows(Feature.clearFaults) ? 'Clear all faults' : 'Clear faults (Plus)'),
                  onPressed: _clearing ? null : () => gated(context, Feature.clearFaults, _clear),
                ),
              ),
            )
          : null,
      body: _reading != null
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('Reading $_reading…'),
              ]),
            )
          : r == null
              ? const SizedBox()
              : Body(children: [
                  _Summary(total: total, high: r.expand((f) => f.faults).where((x) => x.severity == Severity.high).length),
                  for (final ef in r) ...[
                    SectionHeader(ef.ecu.name,
                        trailing: ef.error != null
                            ? const Pill('Not read', color: AppTheme.warn)
                            : Pill(ef.faults.isEmpty ? 'OK' : '${ef.faults.length}',
                                color: ef.faults.isEmpty ? AppTheme.ok : AppTheme.warn)),
                    if (ef.error != null)
                      InfoBanner(text: 'Could not read: ${ef.error}', color: AppTheme.warn)
                    else if (ef.faults.isEmpty)
                      const SizedBox.shrink()
                    else
                      for (final f in ef.faults) ...[_FaultCard(f), const SizedBox(height: 8)],
                  ],
                ]),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.total, required this.high});
  final int total;
  final int high;

  @override
  Widget build(BuildContext context) {
    final color = total == 0 ? AppTheme.ok : (high > 0 ? AppTheme.bad : AppTheme.warn);
    final text = total == 0
        ? 'No faults stored. Everything looks good.'
        : high > 0
            ? '$total fault${total == 1 ? '' : 's'}, $high serious. Have the bike checked before riding.'
            : '$total fault${total == 1 ? '' : 's'} stored. None look serious.';
    return InfoBanner(
      text: text,
      color: color,
      icon: total == 0 ? Icons.check_circle_outline : Icons.warning_amber_rounded,
    );
  }
}

class _FaultCard extends StatelessWidget {
  const _FaultCard(this.f);
  final FaultInfo f;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.severity(f.severity);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _FaultDetails(f),
        ),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 6, color: c),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(f.code, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(width: 8),
                    Pill(f.severity.label, color: c),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_state(f.dtc.state),
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text(f.description),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

String _state(DtcState s) => switch (s) {
      DtcState.active => 'Present now',
      DtcState.stored => 'Stored',
      DtcState.pending => 'Intermittent',
    };

class _FaultDetails extends StatefulWidget {
  const _FaultDetails(this.f);
  final FaultInfo f;
  @override
  State<_FaultDetails> createState() => _FaultDetailsState();
}

class _FaultDetailsState extends State<_FaultDetails> {
  FreezeFrame? _ff;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    if (app.allows(Feature.freezeFrames)) _load(app);
  }

  Future<void> _load(AppState app) async {
    setState(() => _loading = true);
    try {
      _ff = await app.faults.freezeFrame(widget.f);
    } catch (e) {
      _error = friendlyError(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.f;
    final app = context.watch<AppState>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f.code, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontFamily: 'monospace', fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(f.description, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            InfoBanner(
              text: f.severity.rideAdvice,
              color: AppTheme.severity(f.severity),
              icon: f.severity == Severity.high ? Icons.dangerous_outlined : Icons.two_wheeler,
            ),
            const SizedBox(height: 12),
            KeyValueRow('Control unit', f.ecu.name),
            KeyValueRow('Status', _state(f.dtc.state)),
            KeyValueRow('Status byte', '0x${hexWord(f.dtc.status)}'),
            const SectionHeader('Freeze frame'),
            if (!app.allows(Feature.freezeFrames))
              const LockedCard(Feature.freezeFrames)
            else if (_loading)
              const LinearProgressIndicator()
            else if (_error != null)
              Text(_error!)
            else if (_ff == null || _ff!.raw.isEmpty)
              const Text('This control unit stored no extra data with the fault.')
            else
              KeyValueRow('Recorded data', toHex(_ff!.raw)),
          ]),
        ),
      ),
    );
  }
}
