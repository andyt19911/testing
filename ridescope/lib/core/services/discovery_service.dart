import '../../licensing/tier.dart';
import '../adapter/elm327.dart';
import '../ecu/profile.dart';
import '../protocol/diag_client.dart';
import '../protocol/kwp2000.dart';
import '../protocol/uds.dart';
import '../util/hex.dart';
import 'session.dart';

class DiscoveredEcu {
  DiscoveredEcu(this.address, this.mode, {this.vin, this.partNumber, this.software, this.negative});
  final int address;
  final AddressingMode mode;
  final String? vin;
  final String? partNumber;
  final String? software;

  /// NRC returned to the probe (the ECU exists but refused it).
  final String? negative;
}

class IdentifierHit {
  IdentifierHit(this.ident, this.data);
  final int ident;
  final List<int> data;

  String get ascii {
    final printable = data.where((b) => b >= 0x20 && b < 0x7F).length;
    if (data.isEmpty || printable < data.length * 0.8) return '';
    return String.fromCharCodes(data.where((b) => b >= 0x20 && b < 0x7F));
  }
}

/// Read-only tools for learning an unknown bike: find ECUs, find which
/// identifiers they answer, and send raw requests from the console.
class DiscoveryService {
  DiscoveryService(this.session);
  final DiagnosticSession session;
  bool _cancel = false;

  void cancel() => _cancel = true;

  DiagClient _client(BusTarget t) => t.mode == AddressingMode.kLine
      ? Kwp2000Client(session.adapter, t)
      : UdsClient(session.adapter, t);

  /// Probes each address with Tester Present and reads identification from
  /// those that answer.
  Stream<(int, DiscoveredEcu?)> sweep(AddressingMode mode, Iterable<int> addresses) async* {
    session.require(Feature.discovery);
    _cancel = false;
    for (final a in addresses) {
      if (_cancel) return;
      final t = BusTarget(mode, a);
      final c = _client(t);
      DiscoveredEcu? found;
      try {
        await c.testerPresent();
        found = await _identify(c, a, mode);
      } on NegativeResponseException catch (e) {
        found = await _identify(c, a, mode, negative: e.reason);
      } on NoResponseException {
        found = null;
      } on AdapterException {
        found = null;
      }
      yield (a, found);
    }
  }

  Future<DiscoveredEcu> _identify(DiagClient c, int a, AddressingMode mode, {String? negative}) async {
    Future<String?> read(int uds, int kwp) async {
      try {
        final d = await c.readIdentification(mode == AddressingMode.kLine ? kwp : uds);
        return IdentifierHit(0, d).ascii.trim();
      } catch (_) {
        return null;
      }
    }

    return DiscoveredEcu(
      a,
      mode,
      vin: await read(0xF190, 0x90),
      partNumber: await read(0xF187, 0x87),
      software: await read(0xF189, 0x89),
      negative: negative,
    );
  }

  /// Read-only scan of data identifiers (21/22) or identification (1A).
  Stream<(int, IdentifierHit?)> scanIdentifiers(BusTarget t, Iterable<int> idents, {bool identification = false}) async* {
    session.require(Feature.discovery);
    _cancel = false;
    final c = _client(t);
    for (final id in idents) {
      if (_cancel) return;
      try {
        final d = identification ? await c.readIdentification(id) : await c.readData(id);
        yield (id, IdentifierHit(id, d));
      } on NegativeResponseException {
        yield (id, null);
      } on NoResponseException {
        yield (id, null);
      }
    }
  }

  /// Services that could reprogram or damage an ECU are refused in the console.
  static const blockedServices = {0x34, 0x35, 0x36, 0x37, 0x3D, 0x85};

  /// Sends a console line: an AT/ST command, or hex bytes to [target].
  Future<String> console(String line, BusTarget? target) async {
    session.require(Feature.discovery);
    final cmd = line.trim().toUpperCase();
    if (cmd.startsWith('AT') || cmd.startsWith('ST')) {
      if (cmd.startsWith('ATMA') || cmd.startsWith('STM')) {
        return 'Bus monitoring is not available in the console.';
      }
      return (await session.adapter.rawCommand(cmd)).trim();
    }
    if (target == null) return 'Pick a control unit first.';
    final bytes = fromHex(cmd);
    if (bytes.isEmpty) return '';
    if (blockedServices.contains(bytes.first)) {
      return 'Service ${hexWord(bytes.first)} (programming / memory write) is blocked.';
    }
    final msgs = await session.adapter.sendTo(target, bytes);
    if (msgs.isEmpty) return 'NO DATA';
    return msgs.map((m) => '${hexWord(m.source)}: ${toHex(m.data)}').join('\n');
  }

  /// Builds a starter profile entry from a discovered ECU.
  static Map<String, dynamic> ecuJson(DiscoveredEcu d, String id, String name) => {
        'id': id,
        'name': name,
        'shortName': id.toUpperCase(),
        'address': '0x${hexWord(d.address)}',
        'protocol': d.mode == AddressingMode.kLine ? EcuProtocol.kwp.name : EcuProtocol.uds.name,
        'verified': false,
        'identification': [
          {'id': 'vin', 'name': 'VIN', 'ident': d.mode == AddressingMode.kLine ? '0x90' : '0xF190'},
        ],
      };
}
