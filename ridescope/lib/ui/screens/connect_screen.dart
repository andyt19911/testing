import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/ecu/profile.dart';
import '../../core/sim/sim_transport.dart';
import '../../core/sim/virtual_bike.dart';
import '../../core/transport/ble_transport.dart';
import '../../core/transport/spp_transport.dart';
import '../../core/transport/tcp_transport.dart';
import '../../core/transport/transport.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Runs a connection with a progress dialog, then returns to the root screen.
Future<void> runConnect(BuildContext context, Future<void> Function() connect) async {
  final nav = Navigator.of(context);
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ConnectProgress(),
  ));
  await connect();
  nav.pop();
  if (!context.mounted) return;
  final app = context.read<AppState>();
  if (app.connected) nav.popUntil((r) => r.isFirst);
}

class _ConnectProgress extends StatelessWidget {
  const _ConnectProgress();

  @override
  Widget build(BuildContext context) {
    final step = context.watch<AppState>().step;
    return AlertDialog(
      title: const Text('Connecting'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final s in ConnectStep.values.where((s) => s != ConnectStep.done))
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: step == null || s.index > step.index
                ? const Icon(Icons.radio_button_unchecked)
                : s == step
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Icon(Icons.check_circle, color: AppTheme.ok),
            title: Text(s.label),
          ),
      ]),
    );
  }
}

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late TransportKind _kind;
  List<DiscoveredAdapter> _devices = [];
  bool _scanning = false;
  String? _scanError;
  StreamSubscription<DiscoveredAdapter>? _bleSub;
  final _host = TextEditingController(text: '192.168.0.10');
  final _port = TextEditingController(text: '35000');
  String _profileId = 'auto';
  SimBus _demoBus = SimBus.can;
  SimAdapter _demoAdapter = SimAdapter.stn;

  List<TransportKind> get _kinds => [
        if (SppTransport.supported) TransportKind.bluetoothClassic,
        if (BleTransport.supported) TransportKind.ble,
        if (TcpTransport.supported) TransportKind.wifi,
        TransportKind.simulator,
      ];

  @override
  void initState() {
    super.initState();
    _kind = _kinds.first;
    _refresh();
  }

  @override
  void dispose() {
    _bleSub?.cancel();
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<bool> _permissions() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
    final r = await [Permission.bluetoothConnect, Permission.bluetoothScan, Permission.locationWhenInUse].request();
    return r[Permission.bluetoothConnect]?.isGranted ?? true;
  }

  Future<void> _refresh() async {
    await _bleSub?.cancel();
    setState(() {
      _devices = [];
      _scanError = null;
    });
    if (_kind == TransportKind.bluetoothClassic) {
      if (!await _permissions()) {
        setState(() => _scanError = 'RideScope needs Bluetooth permission to find your adapter.');
        return;
      }
      try {
        final list = await SppTransport.bondedDevices();
        list.sort((a, b) => (b.looksLikeObdAdapter ? 1 : 0) - (a.looksLikeObdAdapter ? 1 : 0));
        setState(() => _devices = list);
      } catch (e) {
        setState(() => _scanError = friendlyError(e));
      }
    } else if (_kind == TransportKind.ble) {
      if (!await _permissions()) {
        setState(() => _scanError = 'RideScope needs Bluetooth permission to find your adapter.');
        return;
      }
      setState(() => _scanning = true);
      _bleSub = BleTransport.scan().listen((d) {
        setState(() {
          _devices = [..._devices, d]..sort((a, b) {
              final o = (b.looksLikeObdAdapter ? 1 : 0) - (a.looksLikeObdAdapter ? 1 : 0);
              return o != 0 ? o : (b.rssi ?? -999).compareTo(a.rssi ?? -999);
            });
        });
      }, onError: (Object e) => setState(() => _scanError = friendlyError(e)));
      Future<void>.delayed(const Duration(seconds: 10), () {
        _bleSub?.cancel();
        if (mounted) setState(() => _scanning = false);
      });
    }
  }

  BikeProfile? get _profile => _profileId == 'auto' ? null : context.read<AppState>().profiles.byId(_profileId);

  void _connect(ByteTransport t) {
    _bleSub?.cancel();
    final app = context.read<AppState>();
    runConnect(context, () => app.connect(t, profile: _profile));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Connect')),
      body: Body(children: [
        SegmentedButton<TransportKind>(
          segments: [
            for (final k in _kinds)
              ButtonSegment(
                value: k,
                label: Text(k.label),
                icon: Icon(switch (k) {
                  TransportKind.bluetoothClassic => Icons.bluetooth,
                  TransportKind.ble => Icons.bluetooth_audio,
                  TransportKind.wifi => Icons.wifi,
                  TransportKind.simulator => Icons.science_outlined,
                }),
              ),
          ],
          selected: {_kind},
          showSelectedIcon: false,
          onSelectionChanged: (s) {
            setState(() => _kind = s.first);
            _refresh();
          },
        ),
        if (kIsWeb) ...[
          const SizedBox(height: 12),
          const InfoBanner(
            text: 'The browser version only runs the demo bike. Install the Android or iOS app to connect to a real adapter.',
            color: AppTheme.accent,
          ),
        ],
        if (app.error != null) ...[
          const SizedBox(height: 12),
          InfoBanner(text: app.error!, color: AppTheme.bad, icon: Icons.error_outline),
        ],
        if (_kind != TransportKind.simulator) ...[
          const SectionHeader('Bike type'),
          DropdownButtonFormField<String>(
            initialValue: _profileId,
            isExpanded: true,
            items: [
              const DropdownMenuItem(value: 'auto', child: Text('Detect automatically')),
              for (final p in app.profiles.real) DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _profileId = v ?? 'auto'),
          ),
        ],
        ...switch (_kind) {
          TransportKind.bluetoothClassic || TransportKind.ble => _deviceList(),
          TransportKind.wifi => _wifi(),
          TransportKind.simulator => _demo(app),
        },
      ]),
    );
  }

  List<Widget> _deviceList() => [
        SectionHeader(
          _kind == TransportKind.ble ? 'Nearby adapters' : 'Paired adapters',
          trailing: _scanning
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : IconButton(icon: const Icon(Icons.refresh), tooltip: 'Search again', onPressed: _refresh),
        ),
        if (_scanError != null) InfoBanner(text: _scanError!, color: AppTheme.warn),
        if (_devices.isEmpty && !_scanning && _scanError == null)
          InfoBanner(
            text: _kind == TransportKind.bluetoothClassic
                ? 'No paired adapters. Pair the adapter in Android Bluetooth settings first (PIN is usually 1234 or 0000), then come back.'
                : 'No adapters found. Check that the adapter is plugged in and the ignition is on.',
            color: AppTheme.accent,
          ),
        for (final d in _devices)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                leading: Icon(d.looksLikeObdAdapter ? Icons.settings_input_component : Icons.bluetooth,
                    color: d.looksLikeObdAdapter ? AppTheme.accent : null),
                title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(d.address),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _connect(d.kind == TransportKind.ble
                    ? BleTransport(d.address, d.name)
                    : SppTransport(d.address, d.name)),
              ),
            ),
          ),
      ];

  List<Widget> _wifi() => [
        const SectionHeader('Wi-Fi adapter'),
        const Text('Join the adapter\'s Wi-Fi network in your phone settings first.'),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(flex: 3, child: TextField(controller: _host, decoration: const InputDecoration(labelText: 'Address'))),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Port'),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => _connect(TcpTransport(_host.text.trim(), int.tryParse(_port.text) ?? 35000)),
          child: const Text('Connect'),
        ),
      ];

  List<Widget> _demo(AppState app) => [
        const SectionHeader('Demo bike'),
        const Text('A simulated motorcycle that answers like a real one. Try every function safely; nothing is sent to a real bike.'),
        const SizedBox(height: 16),
        SegmentedButton<SimBus>(
          segments: const [
            ButtonSegment(value: SimBus.can, label: Text('Newer bike (CAN)')),
            ButtonSegment(value: SimBus.kLine, label: Text('Older bike (K-line)')),
          ],
          selected: {_demoBus},
          onSelectionChanged: (s) => setState(() => _demoBus = s.first),
        ),
        const SizedBox(height: 12),
        SegmentedButton<SimAdapter>(
          segments: const [
            ButtonSegment(value: SimAdapter.stn, label: Text('OBDLink adapter')),
            ButtonSegment(value: SimAdapter.clone, label: Text('Cheap ELM327')),
          ],
          selected: {_demoAdapter},
          onSelectionChanged: (s) => setState(() => _demoAdapter = s.first),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () => runConnect(context, () => app.connectDemo(bus: _demoBus, adapter: _demoAdapter)),
          child: const Text('Start demo'),
        ),
      ];
}
