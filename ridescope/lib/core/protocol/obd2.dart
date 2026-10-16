import 'dart:convert';

import '../adapter/elm327.dart';
import 'diag_client.dart';

const obdTarget = BusTarget(AddressingMode.canObd, 0x7DF);

/// Generic OBD-II (SAE J1979) over CAN. Euro 4 and later BMW motorcycles
/// answer these standard emissions requests, which gives real live data
/// without any BMW-specific knowledge.
class ObdClient {
  ObdClient(this.adapter);
  final Elm327Adapter adapter;

  Future<List<AdapterMessage>> _ask(List<int> payload) =>
      adapter.sendTo(obdTarget, payload, timeout: const Duration(seconds: 3));

  List<int>? _positive(List<AdapterMessage> msgs, int sid) {
    for (final m in msgs) {
      if (m.data.isNotEmpty && m.data[0] == sid + 0x40) return m.data;
    }
    return null;
  }

  /// Returns the PIDs (0x01–0xA0) the engine ECU reports as supported.
  Future<Set<int>> supportedPids() async {
    final out = <int>{};
    for (var base = 0x00; base <= 0x80; base += 0x20) {
      final d = _positive(await _ask([0x01, base]), 0x01);
      if (d == null || d.length < 6) break;
      final mask = (d[2] << 24) | (d[3] << 16) | (d[4] << 8) | d[5];
      for (var i = 0; i < 32; i++) {
        if (mask & (1 << (31 - i)) != 0) out.add(base + i + 1);
      }
      if (!out.contains(base + 0x20)) break;
    }
    return out;
  }

  /// Raw data bytes for mode 01 [pid], or null if not answered.
  Future<List<int>?> readPid(int pid) async {
    final d = _positive(await _ask([0x01, pid]), 0x01);
    return d == null || d.length < 2 ? null : d.sublist(2);
  }

  Future<String?> readVin() async {
    final d = _positive(await _ask([0x09, 0x02]), 0x09);
    if (d == null || d.length < 4) return null;
    final s = ascii.decode(d.sublist(3).where((b) => b >= 0x20 && b < 0x7F).toList());
    return s.isEmpty ? null : s;
  }

  /// Emissions-related stored codes (mode 03).
  Future<List<Dtc>> readDtcs() async {
    final d = _positive(await _ask([0x03]), 0x03);
    if (d == null) return [];
    final out = <Dtc>[];
    for (var o = 2; o + 1 < d.length; o += 2) {
      final code = (d[o] << 8) | d[o + 1];
      if (code != 0) out.add(Dtc(code: code, status: 0x08, raw: [d[o], d[o + 1]]));
    }
    return out;
  }

  Future<void> clearDtcs() async {
    final d = _positive(await _ask([0x04]), 0x04);
    if (d == null) throw NoResponseException('OBD clear');
  }
}

/// Formats an OBD-II 2-byte trouble code as the familiar P0123 style.
String formatObdDtc(int code) {
  const letters = ['P', 'C', 'B', 'U'];
  final l = letters[(code >> 14) & 0x3];
  final d1 = (code >> 12) & 0x3;
  final rest = (code & 0x0FFF).toRadixString(16).padLeft(3, '0').toUpperCase();
  return '$l$d1$rest';
}
