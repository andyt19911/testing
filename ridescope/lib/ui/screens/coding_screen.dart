import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/ecu/profile.dart';
import '../../core/services/backup_store.dart';
import '../../core/services/coding_engine.dart';
import '../../core/services/preflight.dart';
import '../../licensing/tier.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Bike settings (ECU coding) with plain-language options, a review step,
/// automatic backups and one-tap restore.
class CodingScreen extends StatefulWidget {
  const CodingScreen({super.key});
  @override
  State<CodingScreen> createState() => _CodingScreenState();
}

class _CodingScreenState extends State<CodingScreen> {
  final Map<String, Map<CodingParam, int>> _current = {};
  final Map<String, String> _errors = {};
  final Map<(String, String), int> _pending = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (context.read<AppState>().allows(Feature.coding)) {
      _load();
    } else {
      _loading = false;
    }
  }

  List<EcuDef> get _ecus {
    final s = context.read<AppState>().session!;
    return s.profile.ecus.where((e) => e.coding.isNotEmpty && (s.status[e.id]?.present ?? false)).toList();
  }

  Future<void> _load() async {
    final engine = context.read<AppState>().coding;
    setState(() => _loading = true);
    _current.clear();
    _errors.clear();
    for (final e in _ecus) {
      try {
        _current[e.id] = await engine.readParams(e);
      } catch (err) {
        _errors[e.id] = friendlyError(err);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  int? _valueOf(EcuDef e, CodingParam p) => _pending[(e.id, p.id)] ?? _current[e.id]?[p];

  void _set(EcuDef e, CodingParam p, int v) {
    setState(() {
      if (_current[e.id]?[p] == v) {
        _pending.remove((e.id, p.id));
      } else {
        _pending[(e.id, p.id)] = v;
      }
    });
  }

  Future<void> _review() async {
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReviewSheet(Map.of(_pending)),
    );
    if (applied == true) {
      _pending.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Settings saved. Switch the ignition off and on for them to take effect.'),
          backgroundColor: AppTheme.ok,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bike settings'),
        actions: [
          if (app.allows(Feature.coding))
            IconButton(
              tooltip: 'Backups',
              icon: const Icon(Icons.history),
              onPressed: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupsScreen()));
                _load();
              },
            ),
        ],
      ),
      bottomNavigationBar: _pending.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  TextButton(onPressed: () => setState(_pending.clear), child: const Text('Undo all')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _review,
                      child: Text('Review ${_pending.length} change${_pending.length == 1 ? '' : 's'}'),
                    ),
                  ),
                ]),
              ),
            ),
      body: !app.allows(Feature.coding)
          ? const Body(children: [LockedCard(Feature.coding)])
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : Body(children: [
                  const InfoBanner(
                    text: 'Every change is backed up first, checked after writing, and can be undone from Backups.',
                    color: AppTheme.accent,
                    icon: Icons.shield_outlined,
                  ),
                  for (final e in _ecus) ...[
                    SectionHeader(e.name,
                        trailing: e.verified ? null : const Pill('Not yet tested', color: AppTheme.warn)),
                    if (_errors[e.id] != null)
                      InfoBanner(text: 'Could not read settings: ${_errors[e.id]}', color: AppTheme.warn)
                    else
                      for (final b in e.coding)
                        for (final p in b.params) ...[_ParamCard(e, p, _current[e.id]?[p], _valueOf(e, p), _set), const SizedBox(height: 8)],
                  ],
                ]),
    );
  }
}

class _ParamCard extends StatelessWidget {
  const _ParamCard(this.ecu, this.param, this.current, this.value, this.onChanged);
  final EcuDef ecu;
  final CodingParam param;
  final int? current;
  final int? value;
  final void Function(EcuDef, CodingParam, int) onChanged;

  @override
  Widget build(BuildContext context) {
    final changed = value != current;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: changed ? AppTheme.accent : scheme.outlineVariant.withValues(alpha: 0.35), width: changed ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(param.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            if (param.risk != Risk.low)
              Pill(param.risk == Risk.high ? 'High risk' : 'Check first', color: param.risk == Risk.high ? AppTheme.bad : AppTheme.warn),
          ]),
          if (param.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(param.description, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
          if (param.linked.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.link, size: 16, color: AppTheme.accent),
              const SizedBox(width: 4),
              Expanded(
                child: Text('Also changes: ${param.linked.map((l) => l.ecu.toUpperCase()).join(', ')}',
                    style: const TextStyle(color: AppTheme.accent, fontSize: 13)),
              ),
            ]),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final o in param.options)
              ChoiceChip(
                label: Text(o.label),
                selected: value == o.value,
                onSelected: (_) => onChanged(ecu, param, o.value),
                avatar: current == o.value && value != o.value ? const Icon(Icons.undo, size: 16) : null,
              ),
            if (value != null && param.optionFor(value!) == null)
              Pill('Current: 0x${value!.toRadixString(16).toUpperCase()}', color: Colors.blueGrey),
          ]),
          if (param.warning != null && changed) ...[
            const SizedBox(height: 10),
            InfoBanner(text: param.warning!, color: AppTheme.warn, icon: Icons.warning_amber_rounded),
          ],
        ]),
      ),
    );
  }
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet(this.desired);
  final Map<(String, String), int> desired;
  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  CodingPlan? _plan;
  PreflightResult? _checks;
  final Set<String> _confirmed = {};
  String? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final app = context.read<AppState>();
    try {
      final plan = await app.coding.plan(widget.desired);
      final checks = await app.preflight.forCoding(plan.ecus);
      if (mounted) {
        setState(() {
          _plan = plan;
          _checks = checks;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _apply() async {
    final app = context.read<AppState>();
    setState(() {
      _progress = 'Starting';
      _error = null;
    });
    try {
      await app.coding.apply(_plan!, onProgress: (m) => setState(() => _progress = m));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _progress = null;
        _error = friendlyError(e);
      });
    }
  }

  bool get _ready =>
      _checks != null && !_checks!.blocked && _checks!.confirmations.every((c) => _confirmed.contains(c.label));

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Review changes', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (plan == null && _error == null) const LinearProgressIndicator(),
            if (plan != null)
              for (final c in plan.changes)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(c.linkedFrom == null ? Icons.edit : Icons.link, color: AppTheme.accent),
                  title: Text('${c.param.name} (${c.ecu.shortName})'),
                  subtitle: Text('${c.fromLabel} → ${c.toLabel}'
                      '${c.linkedFrom == null ? '' : '\nAdded because of ${c.linkedFrom!.name}'}'),
                ),
            if (_checks != null) ...[
              const SectionHeader('Safety checks'),
              for (final c in _checks!.checks)
                c.state == CheckState.confirm
                    ? CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _confirmed.contains(c.label),
                        title: Text(c.label),
                        onChanged: (v) => setState(() => v == true ? _confirmed.add(c.label) : _confirmed.remove(c.label)),
                      )
                    : ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          c.state == CheckState.ok ? Icons.check_circle : (c.state == CheckState.warning ? Icons.error_outline : Icons.cancel),
                          color: c.state == CheckState.ok ? AppTheme.ok : (c.state == CheckState.warning ? AppTheme.warn : AppTheme.bad),
                        ),
                        title: Text(c.label),
                        subtitle: c.detail == null ? null : Text(c.detail!),
                      ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              InfoBanner(text: _error!, color: AppTheme.bad, icon: Icons.error_outline),
            ],
            const SizedBox(height: 16),
            if (_progress != null) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(_progress!),
            ] else
              FilledButton(
                onPressed: _ready ? _apply : null,
                child: const Text('Back up and write'),
              ),
          ]),
        ),
      ),
    );
  }
}

class BackupsScreen extends StatefulWidget {
  const BackupsScreen({super.key});
  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

class _BackupsScreenState extends State<BackupsScreen> {
  List<CodingBackup>? _items;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final all = await app.backups.list(vin: app.session?.vin);
    if (mounted) setState(() => _items = all.where((b) => b.profileId == app.session?.profile.id).toList());
  }

  Future<void> _restore(CodingBackup b) async {
    if (!await confirmDialog(context, 'Restore backup?',
        'Writes the ${b.blockId} settings from ${DateFormat('d MMM yyyy, HH:mm').format(b.time)} back to ${b.ecuId.toUpperCase()}.',
        ok: 'Restore')) {
      return;
    }
    if (!mounted) return;
    final app = context.read<AppState>();
    setState(() => _busy = b.id);
    try {
      await app.coding.restore(b);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Backup restored'), backgroundColor: AppTheme.ok));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => _busy = null);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Backups')),
      body: items == null
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Body(children: [InfoBanner(text: 'No backups yet. One is made automatically before every change.', color: AppTheme.accent)])
              : Body(children: [
                  for (final b in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          title: Text('${b.ecuId.toUpperCase()} · ${DateFormat('d MMM yyyy, HH:mm').format(b.time)}'),
                          subtitle: Text(b.note.isEmpty ? b.blockId : 'Before: ${b.note}'),
                          trailing: _busy == b.id
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                              : TextButton(onPressed: _busy == null ? () => _restore(b) : null, child: const Text('Restore')),
                        ),
                      ),
                    ),
                ]),
    );
  }
}
