import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'transport.dart';

/// Bluetooth LE adapters (OBDLink CX / MX+, Vgate iCar Pro BLE, Veepeak BLE…).
/// Works on Android and iOS. Finds the serial service by looking for a
/// characteristic pair: one that notifies and one that accepts writes.
class BleTransport implements ByteTransport {
  BleTransport(this.deviceId, this.name);
  final String deviceId;
  final String name;

  static final _ble = FlutterReactiveBle();

  static bool get supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Characteristic? _rx;
  Characteristic? _tx;
  StreamSubscription<List<int>>? _sub;
  StreamSubscription<ConnectionStateUpdate>? _conn;
  final _in = StreamController<List<int>>.broadcast();
  bool _open = false;

  /// Serial services used by common adapters, tried first.
  static final _preferred = [
    Uuid.parse('fff0'),
    Uuid.parse('ffe0'),
    Uuid.parse('e7810a71-73ae-499d-8c15-faa9aef0c3f2'),
  ];

  @override
  TransportKind get kind => TransportKind.ble;
  @override
  String get displayName => name;
  @override
  bool get isOpen => _open;
  @override
  Stream<List<int>> get incoming => _in.stream;

  static Stream<DiscoveredAdapter> scan() {
    final seen = <String>{};
    return _ble
        .scanForDevices(withServices: const [], scanMode: ScanMode.lowLatency)
        .where((d) => seen.add(d.id))
        .map((d) => DiscoveredAdapter(
              kind: TransportKind.ble,
              name: d.name.isEmpty ? d.id : d.name,
              address: d.id,
              rssi: d.rssi,
            ));
  }

  @override
  Future<void> open() async {
    final connected = Completer<void>();
    _conn = _ble
        .connectToDevice(id: deviceId, connectionTimeout: const Duration(seconds: 10))
        .listen((u) {
      if (u.connectionState == DeviceConnectionState.connected && !connected.isCompleted) {
        connected.complete();
      } else if (u.connectionState == DeviceConnectionState.disconnected) {
        _open = false;
        if (!connected.isCompleted) {
          connected.completeError(TransportException('Could not connect to $name over Bluetooth LE'));
        }
      }
    }, onError: (Object e) {
      if (!connected.isCompleted) connected.completeError(TransportException('Bluetooth LE: $e'));
    });
    await connected.future.timeout(const Duration(seconds: 15),
        onTimeout: () => throw TransportException('Timed out connecting to $name'));

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _ble.requestMtu(deviceId: deviceId, mtu: 185);
    }
    await _ble.discoverAllServices(deviceId);
    final services = await _ble.getDiscoveredServices(deviceId);
    services.sort((a, b) {
      int rank(Service s) => _preferred.contains(s.id) ? 0 : 1;
      return rank(a).compareTo(rank(b));
    });
    for (final s in services) {
      Characteristic? rx;
      Characteristic? tx;
      for (final c in s.characteristics) {
        if (rx == null && (c.isNotifiable || c.isIndicatable)) rx = c;
        if (tx == null && (c.isWritableWithResponse || c.isWritableWithoutResponse)) tx = c;
      }
      if (rx != null && tx != null) {
        _rx = rx;
        _tx = tx;
        break;
      }
    }
    if (_rx == null || _tx == null) {
      await close();
      throw TransportException('$name does not look like an OBD adapter (no serial service)');
    }
    _sub = _rx!.subscribe().listen(_in.add);
    _open = true;
  }

  @override
  Future<void> write(List<int> data) async {
    final tx = _tx;
    if (tx == null) throw TransportException('Not connected');
    final withResponse = !tx.isWritableWithoutResponse;
    const chunk = 20;
    for (var i = 0; i < data.length; i += chunk) {
      final end = (i + chunk).clamp(0, data.length);
      await tx.write(data.sublist(i, end), withResponse: withResponse);
    }
  }

  @override
  Future<void> close() async {
    _open = false;
    await _sub?.cancel();
    await _conn?.cancel();
  }
}
