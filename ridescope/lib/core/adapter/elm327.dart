import 'dart:async';
import 'dart:convert';

import '../transport/transport.dart';
import '../util/diag_log.dart';
import '../util/hex.dart';
import 'isotp.dart';

/// Tester (diagnostic tool) address used by BMW on K-line and CAN.
const int testerAddress = 0xF1;

enum AdapterFamily { stn, uniCarScan, genuineElm, clone, unknown }

extension AdapterFamilyLabel on AdapterFamily {
  String get label => switch (this) {
        AdapterFamily.stn => 'OBDLink / STN',
        AdapterFamily.uniCarScan => 'UniCarScan',
        AdapterFamily.genuineElm => 'ELM327',
        AdapterFamily.clone => 'ELM327-compatible',
        AdapterFamily.unknown => 'OBD adapter',
      };
}

class AdapterInfo {
  AdapterInfo({
    required this.identity,
    this.description,
    this.stnIdentity,
    this.voltage,
    required this.family,
  });

  final String identity;
  final String? description;
  final String? stnIdentity;
  double? voltage;
  final AdapterFamily family;

  /// Set by [DiagnosticSession.probeLongMessages] after a harmless test.
  bool? longMessagesVerified;

  bool get isStn => family == AdapterFamily.stn;

  /// Whether messages longer than a single frame can be sent. Needed for
  /// writing the cluster date, service data and most coding blocks.
  ///
  /// STN adapters always can. For everything else this is decided by the
  /// actual [DiagnosticSession.probeLongMessages] test, not by the ELM version
  /// string — many capable adapters (e.g. UniCarScan UCSI-2100) report only as
  /// "ELM327 v2.1", so the name alone must never gate write functions.
  bool get canSendLongMessages => isStn || longMessagesVerified == true;

  /// Plain-language capability once tested.
  String get capabilityLabel => switch (longMessagesVerified) {
        true => 'full messages',
        false => 'short messages only',
        null => isStn ? 'full messages' : 'capability not tested yet',
      };

  String get summary => [
        if (stnIdentity != null) stnIdentity! else identity,
        capabilityLabel,
      ].join(' · ');
}

/// How requests are addressed on the bus.
enum AddressingMode {
  /// ISO 14230 (KWP2000) on K-line, header `80 <ecu> F1`.
  kLine,

  /// ISO 15765 at 500 kbit/s with BMW extended addressing: CAN id 0x6F1,
  /// first data byte is the ECU address; replies come on 0x600 + ECU.
  canExtended,

  /// Standard OBD-II functional requests on 0x7DF, replies on 0x7E8–0x7EF.
  canObd,
}

class BusTarget {
  const BusTarget(this.mode, this.address);
  final AddressingMode mode;
  final int address;

  @override
  bool operator ==(Object other) =>
      other is BusTarget && other.mode == mode && other.address == address;
  @override
  int get hashCode => Object.hash(mode, address);
  @override
  String toString() => '${mode.name}@${hexWord(address)}';
}

class AdapterMessage {
  AdapterMessage(this.source, this.data);

  /// ECU address that sent the message (K-line source byte, CAN id − 0x600
  /// for extended addressing, or CAN id for OBD).
  final int source;
  final List<int> data;

  @override
  String toString() => '${hexWord(source)}: ${toHex(data)}';
}

class AdapterException implements Exception {
  AdapterException(this.message, {this.response});
  final String message;
  final String? response;
  @override
  String toString() => message;
}

/// Thrown before transmitting a message the adapter cannot send. The UI uses
/// it to explain that a better adapter is needed rather than failing silently.
class AdapterLimitException extends AdapterException {
  AdapterLimitException(int length, int max)
      : super('This adapter can only send $max data bytes per message; '
            'the request needs $length. Use an OBDLink (STN) adapter for this function.');
}

/// Driver for ELM327 and compatible (STN, UniCarScan, clones) adapters.
class Elm327Adapter {
  Elm327Adapter(this.transport, {DiagLog? log}) : log = log ?? DiagLog();

  final ByteTransport transport;
  final DiagLog log;

  StreamSubscription<List<int>>? _sub;
  final StringBuffer _rx = StringBuffer();
  Completer<String>? _waiting;
  Future<void> _lock = Future.value();

  AdapterInfo? info;
  BusTarget? _target;
  AddressingMode? _protocolMode;

  BusTarget? get currentTarget => _target;

  static const _statusLines = ['SEARCHING...', 'OK', 'STOPPED'];
  static const _errors = [
    'CAN ERROR',
    'BUS ERROR',
    'BUS BUSY',
    'UNABLE TO CONNECT',
    'DATA ERROR',
    'BUFFER FULL',
    'FB ERROR',
    'RX ERROR',
    'LV RESET',
    'ACT ALERT',
    'ERR',
  ];

  Future<T> _locked<T>(Future<T> Function() body) {
    final previous = _lock;
    final done = Completer<void>();
    _lock = done.future;
    return previous.then((_) => body()).whenComplete(done.complete);
  }

  Future<AdapterInfo> initialize() async {
    if (!transport.isOpen) await transport.open();
    _sub ??= transport.incoming.listen(_onData);
    _target = null;
    _protocolMode = null;
    return _locked(() async {
      // A bare CR first flushes any half-typed command left in the adapter.
      await _command('', timeout: const Duration(milliseconds: 500), allowTimeout: true);
      await _command('ATZ', timeout: const Duration(seconds: 5));
      await _command('ATE0');
      final identity = (await _command('ATI')).trim();
      await _command('ATL0');
      await _command('ATS1');
      await _command('ATH1');
      await _command('ATAT1');
      final description = _clean(await _command('AT@1', allowTimeout: true));
      final sti = _clean(await _command('STI', allowTimeout: true));
      final stn = (sti == null || sti.contains('?')) ? null : sti;
      final family = _classify(identity, description, stn);
      info = AdapterInfo(
        identity: identity,
        description: description,
        stnIdentity: stn,
        family: family,
      );
      info!.voltage = await _readVoltageUnlocked();
      log.info('Adapter: ${info!.summary}, ${info!.voltage?.toStringAsFixed(1) ?? '?'} V');
      return info!;
    });
  }

  static String? _clean(String s) {
    final t = s.trim();
    return t.isEmpty || t == '?' ? null : t;
  }

  static AdapterFamily _classify(String ati, String? at1, String? sti) {
    final all = '$ati ${at1 ?? ''} ${sti ?? ''}'.toUpperCase();
    if (sti != null || all.contains('OBDLINK') || all.contains('STN')) return AdapterFamily.stn;
    if (all.contains('UNICARSCAN') || all.contains('UCSI')) return AdapterFamily.uniCarScan;
    // ELM Electronics never released v1.5 or v2.1; those strings are clones.
    final m = RegExp(r'ELM327 V?(\d\.\d)').firstMatch(all);
    if (m == null) return AdapterFamily.unknown;
    final v = m.group(1);
    if (v == '1.5' || v == '2.1') return AdapterFamily.clone;
    if (at1 == null) return AdapterFamily.clone;
    return AdapterFamily.genuineElm;
  }

  Future<double?> readVoltage() => _locked(_readVoltageUnlocked);

  Future<double?> _readVoltageUnlocked() async {
    final r = await _command('ATRV', allowTimeout: true);
    final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(r);
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  /// Sends an arbitrary command (used by the Discovery console).
  Future<String> rawCommand(String cmd) => _locked(() => _command(cmd, allowTimeout: true));

  /// Points the adapter at [target]. Cheap to call repeatedly; only changed
  /// settings are sent.
  Future<void> selectTarget(BusTarget target) => _locked(() => _selectUnlocked(target));

  Future<void> _selectUnlocked(BusTarget target) async {
    if (_target == target) return;
    final a = hexWord(target.address);
    switch (target.mode) {
      case AddressingMode.kLine:
        if (_protocolMode != AddressingMode.kLine) {
          await _expectOk('ATSP5');
          await _expectOk('ATKW0');
          await _expectOk('ATST64');
        }
        await _expectOk('ATSH80${a}F1');
        await _expectOk('ATWM80${a}F13E');
        final init = await _command('ATFI', timeout: const Duration(seconds: 6));
        if (init.contains('ERROR') || init.contains('UNABLE')) {
          _target = null;
          throw AdapterException('No answer from ECU $a on K-line (fast init failed)', response: init);
        }
        break;
      case AddressingMode.canExtended:
        if (_protocolMode != AddressingMode.canExtended) {
          await _expectOk('ATSP6');
          await _expectOk('ATCAF1');
          await _expectOk('ATSH6F1');
          await _expectOk('ATFCSH6F1');
          await _expectOk('ATST32');
        }
        await _expectOk('ATCEA$a');
        await _expectOk('ATCRA6$a');
        await _expectOk('ATFCSD${a}300000');
        await _expectOk('ATFCSM1');
        break;
      case AddressingMode.canObd:
        await _expectOk('ATSP6');
        await _expectOk('ATCAF1');
        await _command('ATCEA', allowTimeout: true);
        await _expectOk('ATAR');
        await _expectOk('ATFCSM0');
        await _expectOk('ATSH7DF');
        break;
    }
    _protocolMode = target.mode;
    _target = target;
  }

  /// Maximum payload that fits in one message for the current mode without
  /// STN long-message support.
  int get maxShortPayload => switch (_target?.mode) {
        AddressingMode.kLine => 7,
        AddressingMode.canExtended => 6,
        _ => 7,
      };

  /// Sends a diagnostic request to the selected target and returns every
  /// message received for the tester. An empty list means `NO DATA`.
  Future<List<AdapterMessage>> send(List<int> payload, {Duration? timeout}) =>
      _locked(() => _sendUnlocked(payload, timeout: timeout));

  Future<List<AdapterMessage>> sendTo(BusTarget target, List<int> payload, {Duration? timeout}) =>
      _locked(() async {
        await _selectUnlocked(target);
        return _sendUnlocked(payload, timeout: timeout);
      });

  Future<List<AdapterMessage>> _sendUnlocked(List<int> payload, {Duration? timeout}) async {
    final target = _target;
    if (target == null) throw AdapterException('No ECU selected');
    final hex = toHex(payload, separator: '');
    String cmd;
    if (payload.length <= maxShortPayload) {
      cmd = hex;
    } else if (info?.canSendLongMessages ?? false) {
      cmd = info!.isStn ? 'STPX d:$hex' : hex;
    } else {
      throw AdapterLimitException(payload.length, maxShortPayload);
    }
    final text = await _command(cmd, timeout: timeout ?? const Duration(seconds: 4));
    return _parse(text, target);
  }

  List<AdapterMessage> _parse(String text, BusTarget target) {
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !_statusLines.contains(l) && !l.startsWith('BUS INIT'))
        .toList();
    if (lines.any((l) => l.contains('NO DATA'))) return [];
    for (final l in lines) {
      if (l == '?') throw AdapterException('Adapter rejected the request', response: text);
      for (final e in _errors) {
        if (l.contains(e)) throw AdapterException('Adapter reported $l', response: text);
      }
    }
    switch (target.mode) {
      case AddressingMode.kLine:
        return _parseKLine(lines);
      case AddressingMode.canExtended:
      case AddressingMode.canObd:
        return _parseCan(lines, target.mode);
    }
  }

  List<AdapterMessage> _parseKLine(List<String> lines) {
    final out = <AdapterMessage>[];
    for (final line in lines) {
      if (!isHexString(line)) continue;
      final b = fromHex(line);
      if (b.length < 4) continue;
      var len = b[0] & 0x3F;
      var idx = 3;
      if (len == 0) {
        len = b[3];
        idx = 4;
      }
      if (b[1] != testerAddress || b.length < idx + len) continue;
      out.add(AdapterMessage(b[2], b.sublist(idx, idx + len)));
    }
    return out;
  }

  List<AdapterMessage> _parseCan(List<String> lines, AddressingMode mode) {
    final ext = mode == AddressingMode.canExtended;
    final asm = IsoTpAssembler(extendedAddressing: ext);
    for (final raw in lines) {
      final line = raw.replaceAll(' ', '');
      if (line.length < 5 || !isHexString(line)) continue;
      final id = int.parse(line.substring(0, 3), radix: 16);
      final rest = line.substring(3);
      if (rest.length.isOdd) continue;
      asm.addFrame(id, fromHex(rest));
    }
    return asm.completed
        .where((m) => !ext || m.extAddress == testerAddress)
        .map((m) => AdapterMessage(ext ? m.canId - 0x600 : m.canId, m.data))
        .toList();
  }

  Future<void> _expectOk(String cmd) async {
    final r = await _command(cmd);
    if (!r.contains('OK')) {
      throw AdapterException('Adapter did not accept $cmd', response: r);
    }
  }

  void _onData(List<int> data) {
    _rx.write(latin1.decode(data, allowInvalid: true));
    final s = _rx.toString();
    final p = s.indexOf('>');
    if (p >= 0) {
      final response = s.substring(0, p);
      _rx
        ..clear()
        ..write(s.substring(p + 1));
      final w = _waiting;
      _waiting = null;
      if (w != null && !w.isCompleted) w.complete(response);
    }
  }

  Future<String> _command(String cmd,
      {Duration timeout = const Duration(seconds: 2), bool allowTimeout = false}) async {
    _rx.clear();
    final c = Completer<String>();
    _waiting = c;
    if (cmd.isNotEmpty) log.tx(cmd);
    await transport.write(latin1.encode('$cmd\r'));
    try {
      var r = await c.future.timeout(timeout);
      // Strip the echo if the adapter ignored ATE0.
      if (cmd.isNotEmpty && r.trimLeft().startsWith(cmd)) {
        r = r.trimLeft().substring(cmd.length);
      }
      final shown = r.trim().replaceAll(RegExp(r'[\r\n]+'), ' | ');
      if (shown.isNotEmpty) log.rx(shown);
      return r;
    } on TimeoutException {
      _waiting = null;
      if (allowTimeout) return '';
      log.error('Timeout waiting for reply to "$cmd"');
      throw AdapterException('The adapter stopped responding ("$cmd")');
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    if (transport.isOpen) await transport.close();
  }
}
