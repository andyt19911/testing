import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'transport.dart';

/// Bluetooth Classic (RFCOMM/SPP) adapters on Android: OBDLink LX/MX/MX+,
/// UniCarScan UCSI-2000/2100 and most ELM327 Bluetooth adapters.
/// Implemented natively in `android/.../SppPlugin.kt`; iOS doesn't allow
/// SPP for non-MFi accessories, so iOS uses BLE or Wi-Fi adapters.
class SppTransport implements ByteTransport {
  SppTransport(this.address, this.name);
  final String address;
  final String name;

  static const _method = MethodChannel('app.ridescope/spp');
  static const _events = EventChannel('app.ridescope/spp/data');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final _in = StreamController<List<int>>.broadcast();
  StreamSubscription<dynamic>? _sub;
  bool _open = false;

  @override
  TransportKind get kind => TransportKind.bluetoothClassic;
  @override
  String get displayName => name;
  @override
  bool get isOpen => _open;
  @override
  Stream<List<int>> get incoming => _in.stream;

  /// Paired devices (Classic Bluetooth needs pairing in Android settings first).
  static Future<List<DiscoveredAdapter>> bondedDevices() async {
    if (!supported) return [];
    final list = await _method.invokeListMethod<Map<dynamic, dynamic>>('bondedDevices') ?? [];
    return [
      for (final d in list)
        DiscoveredAdapter(
          kind: TransportKind.bluetoothClassic,
          name: (d['name'] as String?) ?? d['address'] as String,
          address: d['address'] as String,
        ),
    ];
  }

  @override
  Future<void> open() async {
    try {
      _sub = _events.receiveBroadcastStream().listen(
        (d) => _in.add(List<int>.from(d as List)),
        onError: (Object e) => _open = false,
      );
      await _method.invokeMethod('connect', {'address': address});
      _open = true;
    } on PlatformException catch (e) {
      await _sub?.cancel();
      throw TransportException('Bluetooth connection to $name failed: ${e.message}');
    }
  }

  @override
  Future<void> write(List<int> data) async {
    if (!_open) throw TransportException('Not connected');
    await _method.invokeMethod('write', {'data': Uint8List.fromList(data)});
  }

  @override
  Future<void> close() async {
    _open = false;
    await _sub?.cancel();
    await _method.invokeMethod('disconnect');
  }
}
