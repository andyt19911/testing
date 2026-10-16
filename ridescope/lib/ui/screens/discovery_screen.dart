import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app_state.dart';
import '../../core/adapter/elm327.dart';
import '../../core/ecu/profile.dart';
import '../../core/services/discovery_service.dart';
import '../../core/util/hex.dart';
import '../../licensing/tier.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Pro tools for learning a bike that has no verified profile yet.
class DiscoveryScreen extends StatelessWidget {
  const DiscoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.allows(Feature.discovery)) {
      return Scaffold(appBar: AppBar(title: const Text('Discovery')), body: const Body(children: [LockedCard(Feature.discovery)]));
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Discovery'),
          actions: [
            IconButton(
              tooltip: 'Share raw log',
              icon: const Icon(Icons.ios_share),
              onPressed: () => SharePlus.instance.share(ShareParams(text: app.log.export(), subject: 'RideScope raw log')),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Find units'), Tab(text: 'Find values'), Tab(text: 'Console')]),
        ),
        body: const TabBarView(children: [_SweepTab(), _ScanTab(), _ConsoleTab()]),
      ),
    );
  }
}

AddressingMode _busMode(AppState app) =>
    app.session!.profile.isKLine ? AddressingMode.kLine : AddressingMode.canExtended;

class _SweepTab extends StatefulWidget {
  const _SweepTab();
  @override
  State<_SweepTab> createState() => _SweepTabState();
}

class _SweepTabState extends State<_SweepTab> {
  final List<DiscoveredEcu> _found = [];
  int? _current;
  bool _running = false;
  DiscoveryService? _svc;

  Future<void> _sweep() async {
    final app = context.read<AppState>();
    final mode = _busMode(app);
    _svc = app.discovery;
    setState(() {
      _found.clear();
      _running = true;
    });
    try {
      await for (final (addr, d) in _svc!.sweep(mode, List.generate(0x100, (i) => i).where((a) => a != testerAddress))) {
        if (!mounted) return;
        setState(() {
          _current = addr;
          if (d != null) _found.add(d);
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  void dispose() {
    _svc?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final kLine = app.session!.profile.isKLine;
    return Body(children: [
      InfoBanner(
        text: 'Asks every address on the ${kLine ? 'K-line' : 'CAN bus'} whether a control unit is there. Read-only. '
            '${kLine ? 'K-line is slow: allow about 5 minutes.' : 'Takes about a minute.'}',
        color: AppTheme.accent,
      ),
      const SizedBox(height: 12),
      if (_running) ...[
        LinearProgressIndicator(value: (_current ?? 0) / 255),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text('Address 0x${hexWord(_current ?? 0)} · ${_found.length} found')),
          TextButton(onPressed: () => _svc?.cancel(), child: const Text('Stop')),
        ]),
      ] else
        FilledButton.icon(onPressed: _sweep, icon: const Icon(Icons.radar), label: const Text('Find control units')),
      for (final d in _found) ...[
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.memory, color: AppTheme.ok),
            title: Text('0x${hexWord(d.address)}${_known(app, d.address)}'),
            subtitle: Text([
              if (d.partNumber != null && d.partNumber!.isNotEmpty) 'Part ${d.partNumber}',
              if (d.software != null && d.software!.isNotEmpty) d.software,
              if (d.vin != null && d.vin!.isNotEmpty) 'VIN ${d.vin}',
              if (d.negative != null) 'Answered: ${d.negative}',
            ].join(' · ')),
          ),
        ),
      ],
    ]);
  }

  String _known(AppState app, int addr) {
    final e = app.session!.profile.ecus.where((e) => e.address == addr && e.protocol != EcuProtocol.obd).firstOrNull;
    return e == null ? ' · new' : ' · ${e.name}';
  }
}

class _ScanTab extends StatefulWidget {
  const _ScanTab();
  @override
  State<_ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends State<_ScanTab> {
  final _addr = TextEditingController(text: '12');
  final _from = TextEditingController();
  final _to = TextEditingController();
  final List<IdentifierHit> _hits = [];
  bool _running = false;
  int? _current;
  DiscoveryService? _svc;
  Timer? _watchTimer;
  int? _watching;

  @override
  void initState() {
    super.initState();
    final kLine = context.read<AppState>().session!.profile.isKLine;
    _from.text = kLine ? '00' : '4000';
    _to.text = kLine ? 'FF' : '40FF';
  }

  @override
  void dispose() {
    _svc?.cancel();
    _watchTimer?.cancel();
    _addr.dispose();
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  BusTarget _target(AppState app) => BusTarget(_busMode(app), int.parse(_addr.text, radix: 16));

  Future<void> _scan() async {
    final app = context.read<AppState>();
    final from = int.tryParse(_from.text, radix: 16);
    final to = int.tryParse(_to.text, radix: 16);
    if (from == null || to == null || to < from || to - from > 0x1000) {
      showError(context, 'Enter a hex range of at most 4096 identifiers');
      return;
    }
    _svc = app.discovery;
    setState(() {
      _hits.clear();
      _running = true;
    });
    try {
      await for (final (id, hit) in _svc!.scanIdentifiers(_target(app), List.generate(to - from + 1, (i) => from + i))) {
        if (!mounted) return;
        setState(() {
          _current = id;
          if (hit != null) _hits.add(hit);
        });
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => _running = false);
  }

  void _watch(IdentifierHit h) {
    _watchTimer?.cancel();
    if (_watching == h.ident) {
      setState(() => _watching = null);
      return;
    }
    final app = context.read<AppState>();
    final client = _busMode(app) == AddressingMode.kLine;
    setState(() => _watching = h.ident);
    _watchTimer = Timer.periodic(const Duration(milliseconds: 600), (_) async {
      try {
        final msgs = await app.session!.adapter.sendTo(
            _target(app), client ? [0x21, h.ident & 0xFF] : [0x22, (h.ident >> 8) & 0xFF, h.ident & 0xFF]);
        final d = msgs.where((m) => m.data.isNotEmpty && m.data[0] != 0x7F).firstOrNull?.data;
        if (d == null || !mounted) return;
        final i = _hits.indexWhere((x) => x.ident == h.ident);
        if (i >= 0) setState(() => _hits[i] = IdentifierHit(h.ident, d.sublist(client ? 2 : 3)));
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final kLine = context.watch<AppState>().session!.profile.isKLine;
    return Body(children: [
      InfoBanner(
        text: 'Reads every ${kLine ? 'local identifier (service 21)' : 'data identifier (service 22)'} in the range. '
            'Read-only. Tap a result to watch it live while you operate the bike (twist the throttle, switch the lights).',
        color: AppTheme.accent,
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: TextField(controller: _addr, decoration: const InputDecoration(labelText: 'Unit (hex)'))),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: _from, decoration: const InputDecoration(labelText: 'From'))),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: _to, decoration: const InputDecoration(labelText: 'To'))),
      ]),
      const SizedBox(height: 12),
      if (_running)
        Row(children: [
          Expanded(child: Text('Reading ${_current == null ? '' : hexWord(_current!, digits: kLine ? 2 : 4)} · ${_hits.length} answered')),
          TextButton(onPressed: () => _svc?.cancel(), child: const Text('Stop')),
        ])
      else
        FilledButton.icon(onPressed: _scan, icon: const Icon(Icons.search), label: const Text('Scan')),
      const SizedBox(height: 8),
      for (final h in _hits)
        Card(
          child: ListTile(
            dense: true,
            leading: Icon(_watching == h.ident ? Icons.visibility : Icons.data_object,
                color: _watching == h.ident ? AppTheme.accent : null),
            title: Text(hexWord(h.ident, digits: kLine ? 2 : 4), style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700)),
            subtitle: Text('${toHex(h.data)}${h.ascii.isEmpty ? '' : '\n"${h.ascii}"'}', style: const TextStyle(fontFamily: 'monospace')),
            onTap: () => _watch(h),
          ),
        ),
    ]);
  }
}

class _ConsoleTab extends StatefulWidget {
  const _ConsoleTab();
  @override
  State<_ConsoleTab> createState() => _ConsoleTabState();
}

class _ConsoleTabState extends State<_ConsoleTab> {
  final _addr = TextEditingController(text: '12');
  final _cmd = TextEditingController();
  final List<(String, String)> _lines = [];

  @override
  void dispose() {
    _addr.dispose();
    _cmd.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final app = context.read<AppState>();
    final text = _cmd.text.trim();
    if (text.isEmpty) return;
    String out;
    try {
      final a = int.tryParse(_addr.text, radix: 16);
      out = await app.discovery.console(text, a == null ? null : BusTarget(_busMode(app), a));
    } catch (e) {
      out = friendlyError(e);
    }
    if (mounted) setState(() => _lines.insert(0, (text, out)));
  }

  @override
  Widget build(BuildContext context) {
    return Body(children: [
      const InfoBanner(
        text: 'Send AT commands to the adapter or raw hex requests to a control unit. Programming services are blocked.',
        color: AppTheme.warn,
        icon: Icons.terminal,
      ),
      const SizedBox(height: 12),
      Row(children: [
        SizedBox(width: 90, child: TextField(controller: _addr, decoration: const InputDecoration(labelText: 'Unit'))),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _cmd,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: const InputDecoration(labelText: 'e.g. 22 F1 90 or ATRV'),
            onSubmitted: (_) => _send(),
          ),
        ),
        IconButton(onPressed: _send, icon: const Icon(Icons.send)),
      ]),
      const SizedBox(height: 12),
      for (final (cmd, out) in _lines)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SelectableText('> $cmd\n$out', style: const TextStyle(fontFamily: 'monospace')),
        ),
    ]);
  }
}
