import 'dart:async';
import 'dart:convert';

import '../adapter/isotp.dart';
import '../transport/transport.dart';
import '../util/hex.dart';
import 'virtual_bike.dart';

/// Which adapter the simulator pretends to be.
enum SimAdapter { stn, clone }

/// Emulates an ELM327/STN adapter plugged into a [VirtualBike]. Speaks the
/// same text protocol as the real hardware so the full stack is exercised.
class SimulatedTransport implements ByteTransport {
  SimulatedTransport(this.bike, {this.adapter = SimAdapter.stn, this.latency = const Duration(milliseconds: 4)});

  final VirtualBike bike;
  final SimAdapter adapter;
  final Duration latency;

  final _out = StreamController<List<int>>.broadcast();
  final _line = StringBuffer();
  bool _open = false;

  // ELM state
  bool _echo = true;
  bool _spaces = true;
  bool _headers = false;
  int _protocol = 0;
  List<int> _header = [];
  int? _cea;
  bool _kLineInitialised = false;

  /// Commands received, for tests.
  final List<String> received = [];

  @override
  TransportKind get kind => TransportKind.simulator;

  @override
  String get displayName =>
      adapter == SimAdapter.stn ? 'Demo bike (OBDLink)' : 'Demo bike (ELM327 clone)';

  @override
  bool get isOpen => _open;

  @override
  Stream<List<int>> get incoming => _out.stream;

  @override
  Future<void> open() async => _open = true;

  @override
  Future<void> close() async => _open = false;

  @override
  Future<void> write(List<int> data) async {
    if (!_open) throw TransportException('Not connected');
    for (final c in latin1.decode(data).split('')) {
      if (c == '\r') {
        final cmd = _line.toString();
        _line.clear();
        final reply = _process(cmd);
        final text = '${_echo ? '$cmd\r' : ''}$reply\r\r>';
        Future<void>.delayed(latency, () {
          if (!_out.isClosed) _out.add(latin1.encode(text));
        });
      } else if (c != '\n') {
        _line.write(c);
      }
    }
  }

  String _process(String raw) {
    final cmd = raw.trim().toUpperCase();
    received.add(cmd);
    if (cmd.isEmpty) return '';
    if (cmd.startsWith('AT')) return _at(cmd.substring(2).replaceAll(' ', ''));
    if (cmd.startsWith('ST')) return _st(cmd);
    final hex = cmd.replaceAll(' ', '');
    if (!isHexString(hex) || hex.length.isOdd) return '?';
    return _request(fromHex(hex), long: false);
  }

  String get _identity => adapter == SimAdapter.stn ? 'ELM327 v1.4b' : 'ELM327 v1.5';

  String _at(String c) {
    if (c == 'Z' || c == 'WS') {
      _echo = true;
      _headers = false;
      _spaces = true;
      _protocol = 0;
      _cea = null;
      _kLineInitialised = false;
      return '\r$_identity';
    }
    if (c == 'I') return _identity;
    if (c == '@1') return adapter == SimAdapter.stn ? 'OBDLink MX+ r2.4' : 'OBDII to RS232 Interpreter';
    if (c == 'RV') return '${bike.battery.toStringAsFixed(1)}V';
    if (c.startsWith('E')) return _flag(c, (v) => _echo = v);
    if (c.startsWith('S') && c.length == 2 && '01'.contains(c[1])) return _flag(c, (v) => _spaces = v);
    if (c.startsWith('H') && c.length == 2) return _flag(c, (v) => _headers = v);
    if (c.startsWith('SP')) {
      _protocol = int.tryParse(c.substring(2), radix: 16) ?? 0;
      _kLineInitialised = false;
      return 'OK';
    }
    if (c.startsWith('SH')) {
      final h = c.substring(2);
      if (!isHexString(h) || !(h.length == 3 || h.length == 6)) return '?';
      _header = h.length == 3 ? [int.parse(h, radix: 16)] : fromHex(h);
      return 'OK';
    }
    if (c.startsWith('CEA')) {
      final a = c.substring(3);
      _cea = a.isEmpty ? null : int.parse(a, radix: 16);
      return 'OK';
    }
    if (c == 'FI') {
      if (_protocol != 5 || _header.length != 3) return 'BUS INIT: ...ERROR';
      final ok = bike.bus == SimBus.kLine && bike.ecus.containsKey(_header[1]);
      _kLineInitialised = ok;
      return ok ? 'BUS INIT: ...OK' : 'BUS INIT: ...ERROR';
    }
    const accepted = ['L', 'AT', 'KW', 'ST', 'WM', 'CAF', 'CRA', 'AR', 'FCSH', 'FCSD', 'FCSM', 'D', 'PC', 'SW', 'BI'];
    if (accepted.any(c.startsWith)) return 'OK';
    return '?';
  }

  String _flag(String c, void Function(bool) set) {
    final v = c.substring(c.length - 1);
    if (v != '0' && v != '1') return '?';
    set(v == '1');
    return 'OK';
  }

  String _st(String c) {
    if (adapter != SimAdapter.stn) return '?';
    if (c == 'STI') return 'STN2255 v5.10.3';
    final m = RegExp(r'^STPX\s*D:([0-9A-F]+)').firstMatch(c);
    if (m != null) return _request(fromHex(m.group(1)!), long: true);
    return '?';
  }

  String _fmt(List<int> bytes) => toHex(bytes, separator: _spaces ? ' ' : '');

  String _request(List<int> payload, {required bool long}) {
    if (_protocol == 6) return _can(payload, long: long);
    if (_protocol == 5) return _kLine(payload, long: long);
    return 'NO DATA';
  }

  String _can(List<int> payload, {required bool long}) {
    if (bike.bus != SimBus.can) return 'NO DATA';
    final functional = _header.isNotEmpty && _header[0] == 0x7DF && _cea == null;
    final maxSingle = functional ? 7 : 6;
    if (!long && payload.length > maxSingle) return '?';
    if (functional) {
      final r = bike.obdRequest(payload);
      if (r == null) return 'NO DATA';
      return segmentIsoTp(r).map((f) => _canLine(0x7E8, f)).join('\r');
    }
    if (_cea == null || _header.isEmpty || _header[0] != 0x6F1) return 'NO DATA';
    final r = bike.request(_cea!, payload);
    if (r == null) return 'NO DATA';
    return segmentIsoTp(r, extAddress: 0xF1).map((f) => _canLine(0x600 + _cea!, f)).join('\r');
  }

  String _canLine(int id, List<int> frame) {
    final data = _headers ? frame : frame.sublist(_cea == null ? 1 : 2);
    final h = _headers ? '${hexWord(id, digits: 3)}${_spaces ? ' ' : ''}' : '';
    return '$h${_fmt(data)}';
  }

  String _kLine(List<int> payload, {required bool long}) {
    if (bike.bus != SimBus.kLine) return 'BUS INIT: ...ERROR';
    if (!long && payload.length > 7) return '?';
    if (_header.length != 3) return 'NO DATA';
    final target = _header[1];
    if (!_kLineInitialised) {
      _kLineInitialised = bike.ecus.containsKey(target);
      if (!_kLineInitialised) return 'BUS INIT: ...ERROR';
    }
    final r = bike.request(target, payload);
    if (r == null) return 'NO DATA';
    final frame = r.length < 64
        ? [0x80 | r.length, 0xF1, target, ...r]
        : [0x80, 0xF1, target, r.length, ...r];
    final cs = frame.fold<int>(0, (a, b) => (a + b) & 0xFF);
    return _headers ? _fmt([...frame, cs]) : _fmt(r);
  }
}
