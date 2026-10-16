import 'dart:convert';
import 'dart:math';

import '../util/hex.dart';

enum SimProtocol { kwp, uds }

typedef DataSource = List<int> Function();
typedef RoutineHandler = List<int>? Function(int control, List<int> data);

/// A control unit inside the [VirtualBike]. Implements enough of KWP2000 and
/// UDS to exercise every code path of the app, including negative responses,
/// security access and session handling.
class VirtualEcu {
  VirtualEcu({
    required this.address,
    required this.name,
    required this.protocol,
  });

  final int address;
  final String name;
  final SimProtocol protocol;

  /// Identifiers readable with 1A / 21 / 22.
  final Map<int, DataSource> readable = {};

  /// Identifiers writable with 3B / 2E (stored values are also readable).
  final Map<int, List<int>> writable = {};

  /// Writable identifiers that need the extended session + security.
  final Set<int> protectedWrites = {};

  final Map<int, RoutineHandler> routines = {};
  final Map<int, RoutineHandler> ioControls = {};

  /// Stored faults: code → status byte.
  final Map<int, int> dtcs = {};
  final Map<int, List<int>> freezeFrames = {};

  int session = 1;
  bool unlocked = false;
  List<int>? _seed;
  int failedKeys = 0;

  /// Set by the bike; used for "engine is running" negative responses.
  bool Function() engineRunning = () => false;

  /// Requests seen, for test assertions.
  final List<List<int>> requestLog = [];

  final _rand = Random(7);

  static List<int> simKey(List<int> seed) => seed.map((b) => (b ^ 0x5A) & 0xFF).toList();

  List<int> _neg(int sid, int code) => [0x7F, sid, code];

  bool get _extended => protocol == SimProtocol.uds ? session == 0x03 : session == 0x86 || session == 0x03;

  List<int>? handle(List<int> req) {
    if (req.isEmpty) return null;
    requestLog.add(List.of(req));
    final sid = req[0];
    final w = protocol == SimProtocol.uds ? 2 : 1;
    int id(int at) => protocol == SimProtocol.uds ? readUnsigned(req, at, 2) : req[at];
    switch (sid) {
      case 0x10:
        if (req.length < 2) return _neg(sid, 0x13);
        session = req[1];
        if (session == 1 || session == 0x81) unlocked = false;
        return protocol == SimProtocol.uds ? [0x50, req[1], 0x00, 0x32, 0x01, 0xF4] : [0x50, req[1]];
      case 0x3E:
        return [0x7E, if (req.length > 1) req[1]];
      case 0x11:
        session = 1;
        unlocked = false;
        return [0x51, req.length > 1 ? req[1] : 1];
      case 0x27:
        if (req.length < 2) return _neg(sid, 0x13);
        final level = req[1];
        if (level.isOdd) {
          if (!_extended) return _neg(sid, 0x7F);
          if (unlocked) return [0x67, level, 0, 0];
          _seed = [_rand.nextInt(256), _rand.nextInt(256)];
          return [0x67, level, ..._seed!];
        }
        if (_seed == null) return _neg(sid, 0x24);
        final key = req.sublist(2);
        if (_listEq(key, simKey(_seed!))) {
          unlocked = true;
          _seed = null;
          return [0x67, level];
        }
        failedKeys++;
        return _neg(sid, 0x35);
      case 0x1A:
      case 0x21:
      case 0x22:
        if (req.length < 1 + w) return _neg(sid, 0x13);
        // UDS allows several DIDs in one request; answer the first and use
        // the rest only to validate the adapter could send it.
        final ident = id(1);
        final src = readable[ident];
        final stored = writable[ident];
        final data = src?.call() ?? stored;
        if (data == null) return _neg(sid, 0x31);
        return [sid + 0x40, ...req.sublist(1, 1 + w), ...data];
      case 0x2E:
      case 0x3B:
        if (req.length < 2 + w) return _neg(sid, 0x13);
        final ident = id(1);
        final current = writable[ident];
        if (current == null) return _neg(sid, 0x31);
        if (protectedWrites.contains(ident)) {
          if (!_extended) return _neg(sid, 0x7F);
          if (!unlocked) return _neg(sid, 0x33);
        }
        if (engineRunning()) return _neg(sid, 0x22);
        final value = req.sublist(1 + w);
        if (value.length != current.length) return _neg(sid, 0x13);
        writable[ident] = value;
        return [sid + 0x40, ...req.sublist(1, 1 + w)];
      case 0x31:
      case 0x32:
      case 0x33:
        int control;
        int ident;
        List<int> data;
        if (protocol == SimProtocol.uds) {
          if (sid != 0x31 || req.length < 4) return _neg(sid, 0x13);
          control = req[1];
          ident = readUnsigned(req, 2, 2);
          data = req.sublist(4);
        } else {
          if (req.length < 2) return _neg(sid, 0x13);
          control = sid - 0x30;
          ident = req[1];
          data = req.sublist(2);
        }
        final r = routines[ident];
        if (r == null) return _neg(sid, 0x31);
        if (!_extended) return _neg(sid, 0x7F);
        final out = r(control, data);
        if (out == null) return _neg(sid, 0x22);
        return protocol == SimProtocol.uds
            ? [0x71, control, ...writeUnsigned(ident, 2), ...out]
            : [sid + 0x40, ident, ...out];
      case 0x2F:
      case 0x30:
        if (req.length < 2 + w) return _neg(sid, 0x13);
        final ident = id(1);
        final h = ioControls[ident];
        if (h == null) return _neg(sid, 0x31);
        if (!_extended) return _neg(sid, 0x7F);
        final param = req[1 + w];
        final out = h(param, req.sublist(2 + w));
        if (out == null) return _neg(sid, 0x22);
        return [sid + 0x40, ...req.sublist(1, 2 + w), ...out];
      case 0x18: // KWP read DTC by status
        if (protocol != SimProtocol.kwp) return _neg(sid, 0x11);
        return [
          0x58,
          dtcs.length,
          for (final e in dtcs.entries) ...[(e.key >> 8) & 0xFF, e.key & 0xFF, e.value],
        ];
      case 0x17:
        if (protocol != SimProtocol.kwp || req.length < 3) return _neg(sid, 0x11);
        final code = readUnsigned(req, 1, 2);
        if (!dtcs.containsKey(code)) return _neg(sid, 0x31);
        return [0x57, 1, req[1], req[2], dtcs[code]!, ...?freezeFrames[code]];
      case 0x19: // UDS read DTC information
        if (protocol != SimProtocol.uds || req.length < 2) return _neg(sid, 0x11);
        if (req[1] == 0x02) {
          return [
            0x59,
            0x02,
            0xFF,
            for (final e in dtcs.entries) ...[...writeUnsigned(e.key, 3), e.value],
          ];
        }
        if (req[1] == 0x04 && req.length >= 5) {
          final code = readUnsigned(req, 2, 3);
          if (!dtcs.containsKey(code)) return _neg(sid, 0x31);
          return [0x59, 0x04, ...writeUnsigned(code, 3), dtcs[code]!, 0x01, ...?freezeFrames[code]];
        }
        return _neg(sid, 0x12);
      case 0x14:
        dtcs.clear();
        freezeFrames.clear();
        return protocol == SimProtocol.uds ? [0x54] : [0x54, 0xFF, 0x00];
      default:
        return _neg(sid, 0x11);
    }
  }

  static bool _listEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static List<int> asciiBytes(String s) => ascii.encode(s);
}
