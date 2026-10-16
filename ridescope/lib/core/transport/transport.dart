import 'dart:async';

/// How the phone reaches the OBD adapter.
enum TransportKind { bluetoothClassic, ble, wifi, simulator }

extension TransportKindLabel on TransportKind {
  String get label => switch (this) {
        TransportKind.bluetoothClassic => 'Bluetooth',
        TransportKind.ble => 'Bluetooth LE',
        TransportKind.wifi => 'Wi-Fi',
        TransportKind.simulator => 'Demo bike',
      };
}

/// A bidirectional byte pipe to an ELM327-compatible adapter.
abstract class ByteTransport {
  TransportKind get kind;
  String get displayName;
  bool get isOpen;

  /// Bytes received from the adapter. Single-subscription is not assumed; the
  /// stream must be broadcast.
  Stream<List<int>> get incoming;

  Future<void> open();
  Future<void> write(List<int> data);
  Future<void> close();
}

class TransportException implements Exception {
  TransportException(this.message);
  final String message;
  @override
  String toString() => 'TransportException: $message';
}

/// A device found while scanning, before connecting.
class DiscoveredAdapter {
  DiscoveredAdapter({
    required this.kind,
    required this.name,
    required this.address,
    this.rssi,
  });

  final TransportKind kind;
  final String name;

  /// MAC address, BLE remote id, `host:port`, or `sim:<variant>`.
  final String address;
  final int? rssi;

  /// Heuristic: names commonly used by OBD adapters.
  bool get looksLikeObdAdapter => RegExp(
        r'obd|elm|vlink|v-link|vgate|icar|obdlink|ucsi|unicarscan|konnwei|kw\d|veepeak|carista|scan',
        caseSensitive: false,
      ).hasMatch(name);
}
