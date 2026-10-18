import '../adapter/elm327.dart';
import '../util/hex.dart';

/// Negative response codes shared by KWP2000 (ISO 14230-3) and UDS (ISO 14229).
const Map<int, String> negativeResponseNames = {
  0x10: 'General reject',
  0x11: 'Service not supported',
  0x12: 'Sub-function not supported',
  0x13: 'Incorrect message length or format',
  0x14: 'Response too long',
  0x21: 'Busy, repeat request',
  0x22: 'Conditions not correct',
  0x24: 'Request sequence error',
  0x31: 'Request out of range',
  0x33: 'Security access denied',
  0x35: 'Invalid key',
  0x36: 'Exceeded number of attempts',
  0x37: 'Required time delay not expired',
  0x72: 'General programming failure',
  0x78: 'Response pending',
  0x7E: 'Sub-function not supported in active session',
  0x7F: 'Service not supported in active session',
  0x81: 'RPM too high',
  0x82: 'RPM too low',
  0x83: 'Engine is running',
  0x84: 'Engine is not running',
  0x88: 'Vehicle speed too high',
  0x92: 'Voltage too high',
  0x93: 'Voltage too low',
};

class NegativeResponseException implements Exception {
  NegativeResponseException(this.service, this.code);
  final int service;
  final int code;

  String get reason => negativeResponseNames[code] ?? 'Code ${hexWord(code)}';

  /// Plain-language hint shown to riders.
  String get hint => switch (code) {
        0x22 => 'Check that the ignition is on and the engine is off, then try again.',
        0x33 || 0x35 => 'The control unit refused access to this function.',
        0x83 => 'Switch the engine off (ignition stays on) and try again.',
        0x84 => 'Start the engine and try again.',
        0x93 => 'The battery voltage is too low. Connect a charger and try again.',
        0x11 || 0x12 || 0x31 => 'This control unit does not support this function.',
        _ => 'The control unit rejected the request.',
      };

  @override
  String toString() => 'ECU rejected ${hexWord(service)}: $reason';
}

class NoResponseException implements Exception {
  NoResponseException(this.what);
  final String what;
  @override
  String toString() => 'No response from control unit ($what)';
}

enum DtcState { active, stored, pending }

class Dtc {
  Dtc({required this.code, required this.status, this.raw = const []});

  /// Numeric code as reported by the ECU (2 bytes for KWP, 3 for UDS).
  final int code;
  final int status;
  final List<int> raw;

  /// Whether the fault is present now, intermittent, or just stored.
  ///
  /// The status byte means different things on the two protocols, so it is
  /// read differently (UDS codes are 3 bytes, KWP 2):
  ///  * UDS (ISO 14229): bit 0 `testFailed` = failing now; bit 2 `pendingDTC`
  ///    = intermittent. Bits 4/6 are "test not completed" and do NOT mean the
  ///    fault is present — a common BMW status is 0x50, which is stored only.
  ///  * KWP2000: bit 6 = present, bit 2 = pending.
  DtcState get state {
    if (raw.length >= 3) {
      if (status & 0x01 != 0) return DtcState.active;
      if (status & 0x04 != 0) return DtcState.pending;
      return DtcState.stored;
    }
    if (status & 0x01 != 0 || status & 0x40 != 0) return DtcState.active;
    if (status & 0x04 != 0) return DtcState.pending;
    return DtcState.stored;
  }

  String get hexCode => hexWord(code, digits: raw.length >= 3 ? 6 : 4);

  @override
  String toString() => '$hexCode (${state.name})';
}

class FreezeFrame {
  FreezeFrame(this.dtc, this.raw, [this.values = const {}]);
  final int dtc;
  final List<int> raw;
  final Map<String, String> values;
}

/// Common operations implemented by [Kwp2000Client] and [UdsClient], keyed
/// by numeric identifiers so ECU profiles stay protocol-neutral.
abstract class DiagClient {
  DiagClient(this.adapter, this.target);

  final Elm327Adapter adapter;
  final BusTarget target;

  String get protocolName;

  /// Width in bytes of data identifiers for this protocol.
  int get idWidth;

  Future<void> startSession(int type);
  Future<void> testerPresent();
  Future<List<int>> readIdentification(int id);
  Future<List<int>> readData(int id);
  Future<void> writeData(int id, List<int> data);
  Future<List<int>> routine(int id, {int control = 1, List<int> data = const []});
  Future<List<int>> ioControl(int id, int parameter, {List<int> data = const []});
  Future<List<Dtc>> readDtcs();
  Future<void> clearDtcs();
  Future<FreezeFrame?> readFreezeFrame(Dtc dtc);
  Future<void> ecuReset({int type = 1});

  /// Requests a seed for [level] and sends the key computed by [keyFor].
  /// A seed of all zeroes means the ECU is already unlocked.
  Future<void> securityAccess(int level, List<int> Function(List<int> seed) keyFor);

  /// Sends a raw request and returns the positive response (service + 0x40
  /// first). Handles "response pending" and turns negative responses into
  /// [NegativeResponseException].
  Future<List<int>> request(List<int> payload, {Duration? timeout}) =>
      _request(payload, timeout, 0);

  Future<List<int>> _request(List<int> payload, Duration? timeout, int attempt) async {
    final sid = payload.first;
    final msgs = await adapter.sendTo(target, payload, timeout: timeout);
    final mine = msgs.where((m) => m.source == target.address || target.mode == AddressingMode.canObd);
    List<int>? positive;
    NegativeResponseException? negative;
    var pendingOnly = false;
    for (final m in mine) {
      final d = m.data;
      if (d.isEmpty) continue;
      if (d[0] == 0x7F && d.length >= 3 && d[1] == sid) {
        if (d[2] == 0x78) {
          pendingOnly = true;
          continue;
        }
        negative = NegativeResponseException(sid, d[2]);
      } else if (d[0] == (sid + 0x40) & 0xFF) {
        positive = d;
      }
    }
    if (positive != null) return positive;
    if (negative != null) throw negative;
    if (pendingOnly) {
      // The ECU accepted the request but had not answered when the adapter
      // gave up listening. Reads are safe to repeat; anything else is
      // reported so the caller can poll for results instead of re-running it.
      if (_readServices.contains(sid) && attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        return _request(payload, timeout, attempt + 1);
      }
      throw ResponsePendingException(sid);
    }
    throw NoResponseException(hexWord(sid));
  }

  static const _readServices = {0x12, 0x17, 0x18, 0x19, 0x1A, 0x21, 0x22};
}

class ResponsePendingException implements Exception {
  ResponsePendingException(this.service);
  final int service;
  @override
  String toString() => 'Control unit is still working on ${hexWord(service)}';
}
