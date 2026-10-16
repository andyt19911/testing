import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/adapter/elm327.dart';
import '../../core/ecu/profile.dart';
import '../../core/protocol/diag_client.dart';
import '../../core/services/preflight.dart';
import '../../core/services/procedure_runner.dart';
import '../../licensing/tier.dart';
import '../theme.dart';
import '../widgets/common.dart';

enum _Stage { setup, running, done, failed }

/// Guided wizard for any profile procedure: explain → inputs → safety
/// checks → run with prompts → result.
class ProcedureScreen extends StatefulWidget {
  const ProcedureScreen({super.key, required this.ecu, required this.procedure});
  final EcuDef ecu;
  final ProcedureDef procedure;

  @override
  State<ProcedureScreen> createState() => _ProcedureScreenState();
}

class _ProcedureScreenState extends State<ProcedureScreen> {
  _Stage _stage = _Stage.setup;
  Map<String, String>? _status;
  PreflightResult? _checks;
  final Set<String> _confirmed = {};
  late final Map<String, int> _inputs = {for (final i in widget.procedure.inputs) i.id: i.defaultValue};
  ProcedureProgress? _progress;
  String? _error;
  String? _hint;

  ProcedureDef get p => widget.procedure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    if (p.statusReads.isNotEmpty) {
      final st = await app.runner.readStatus(widget.ecu, p);
      if (mounted) setState(() => _status = st);
    }
    await _runChecks();
  }

  Future<void> _runChecks() async {
    setState(() => _checks = null);
    final r = await context.read<AppState>().preflight.forProcedure(widget.ecu, p);
    if (mounted) setState(() => _checks = r);
  }

  bool get _ready {
    final c = _checks;
    if (c == null || c.blocked) return false;
    return c.confirmations.every((x) => _confirmed.contains(x.label));
  }

  Future<void> _start() async {
    final app = context.read<AppState>();
    setState(() {
      _stage = _Stage.running;
      _error = null;
      _hint = null;
    });
    try {
      await app.runner.run(
        widget.ecu,
        p,
        inputs: _inputs,
        confirm: (m) => confirmDialog(context, p.name, m),
        onProgress: (pr) => setState(() => _progress = pr),
      );
      if (p.statusReads.isNotEmpty) {
        _status = await app.runner.readStatus(widget.ecu, p);
        if (p.kind == ProcedureKind.service) await app.rememberService(_status!.values.first);
      }
      setState(() => _stage = _Stage.done);
    } catch (e) {
      setState(() {
        _stage = _Stage.failed;
        _error = friendlyError(e);
        _hint = switch (e) {
          NegativeResponseException n => n.hint,
          AdapterLimitException _ => 'Use an OBDLink LX/MX+/CX adapter for this function.',
          ProcedureCancelled _ => 'Nothing else was changed after you cancelled.',
          _ => 'Check the connection and try again.',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(p.name)),
      body: Body(children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 6, children: [
                Pill(p.kind.label, color: AppTheme.accent),
                Pill(widget.ecu.shortName, color: Colors.blueGrey, icon: Icons.memory),
                if (widget.ecu.verified && p.verified)
                  const Pill('Tested on this model', color: AppTheme.ok, icon: Icons.verified)
                else
                  const Pill('Not yet tested', color: AppTheme.warn, icon: Icons.science_outlined),
              ]),
              const SizedBox(height: 12),
              Text(p.description.isEmpty ? p.name : p.description),
              if (_status != null && _status!.isNotEmpty) ...[
                const Divider(height: 28),
                for (final e in _status!.entries) KeyValueRow(e.key, e.value),
              ],
            ]),
          ),
        ),
        ...switch (_stage) {
          _Stage.setup => _setup(),
          _Stage.running => _running(),
          _Stage.done => _done(),
          _Stage.failed => _failed(),
        },
      ]),
    );
  }

  List<Widget> _setup() => [
        if (p.inputs.isNotEmpty) ...[
          const SectionHeader('Settings'),
          for (final i in p.inputs)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(i.label)),
                    Text('${_inputs[i.id]} ${i.unit}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  ]),
                  Slider(
                    value: _inputs[i.id]!.toDouble(),
                    min: i.min.toDouble(),
                    max: i.max.toDouble(),
                    divisions: ((i.max - i.min) / i.step).round().clamp(1, 1000),
                    onChanged: (v) => setState(() => _inputs[i.id] = (v / i.step).round() * i.step),
                  ),
                ]),
              ),
            ),
        ],
        SectionHeader('Before you start',
            trailing: IconButton(onPressed: _runChecks, icon: const Icon(Icons.refresh), tooltip: 'Check again')),
        if (_checks == null)
          const LinearProgressIndicator()
        else
          Card(
            child: Column(children: [
              for (final c in _checks!.checks)
                c.state == CheckState.confirm
                    ? CheckboxListTile(
                        value: _confirmed.contains(c.label),
                        onChanged: (v) => setState(() => v == true ? _confirmed.add(c.label) : _confirmed.remove(c.label)),
                        title: Text(c.label),
                        controlAffinity: ListTileControlAffinity.leading,
                      )
                    : ListTile(
                        leading: Icon(
                          switch (c.state) {
                            CheckState.ok => Icons.check_circle,
                            CheckState.warning => Icons.error_outline,
                            _ => Icons.cancel,
                          },
                          color: switch (c.state) {
                            CheckState.ok => AppTheme.ok,
                            CheckState.warning => AppTheme.warn,
                            _ => AppTheme.bad,
                          },
                        ),
                        title: Text(c.label),
                        subtitle: c.detail == null ? null : Text(c.detail!),
                      ),
            ]),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(_checks?.blocked ?? false ? 'Fix the items above first' : 'Start'),
          onPressed: _ready ? _start : null,
        ),
        if (_checks?.checks.any((c) => c.label == 'Licence' && c.state == CheckState.fail) ?? false) ...[
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => openLicense(context, highlight: p.tier), child: Text('Get ${p.tier.label}')),
        ],
      ];

  List<Widget> _running() => [
        const SizedBox(height: 24),
        LinearProgressIndicator(value: _progress?.fraction, minHeight: 8, borderRadius: BorderRadius.circular(8)),
        const SizedBox(height: 12),
        Text(_progress?.text ?? 'Starting…', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('Keep the ignition on and don\'t disconnect the adapter.'),
      ];

  List<Widget> _done() => [
        const SizedBox(height: 16),
        InfoBanner(text: p.successMessage ?? 'Done.', color: AppTheme.ok, icon: Icons.check_circle_outline),
        const SizedBox(height: 20),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Finish')),
      ];

  List<Widget> _failed() => [
        const SizedBox(height: 16),
        InfoBanner(text: _error ?? 'Failed', color: AppTheme.bad, icon: Icons.error_outline),
        if (_hint != null) ...[
          const SizedBox(height: 8),
          InfoBanner(text: _hint!, color: AppTheme.accent, icon: Icons.lightbulb_outline),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () {
            setState(() => _stage = _Stage.setup);
            _runChecks();
          },
          child: const Text('Try again'),
        ),
      ];
}
