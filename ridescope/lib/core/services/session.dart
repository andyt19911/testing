import '../../licensing/tier.dart';
import '../adapter/elm327.dart';
import '../ecu/profile.dart';
import '../ecu/security.dart';
import '../protocol/diag_client.dart';
import '../protocol/kwp2000.dart';
import '../protocol/obd2.dart';
import '../protocol/uds.dart';
import '../util/diag_log.dart';
import '../util/hex.dart';

class EcuStatus {
  EcuStatus(this.ecu, {required this.present, this.identity = const {}, this.error});
  final EcuDef ecu;
  final bool present;
  final Map<String, String> identity;
  final String? error;
}

/// One connection to one bike: the adapter, the selected profile, and the
/// current licence tier. Every feature service goes through it.
class DiagnosticSession {
  DiagnosticSession({
    required this.adapter,
    required this.profile,
    required Tier Function() tier,
    this.expertMode = false,
    this.offRoadMode = false,
  }) : _tier = tier; // ignore: prefer_initializing_formals

  final Elm327Adapter adapter;
  final BikeProfile profile;
  final Tier Function() _tier;
  bool expertMode;

  /// Closed-course / off-road use accepted by the rider. Gates procedures
  /// marked [ProcedureDef.offRoadOnly]. Does not suppress faults or change
  /// what the ECU monitors.
  bool offRoadMode;

  final Map<String, DiagClient> _clients = {};
  late final ObdClient obd = ObdClient(adapter);

  final Map<String, EcuStatus> status = {};
  String? vin;

  DiagLog get log => adapter.log;
  AdapterInfo get adapterInfo => adapter.info!;
  Tier get tier => _tier();

  bool allows(Feature f) => tier.includes(f.minTier);

  void require(Feature f) {
    if (!allows(f)) throw FeatureLockedException(f);
  }

  /// Whether write operations on [ecu] may run: the ECU must be verified,
  /// unless the user switched on expert mode (Pro).
  bool writesAllowed(EcuDef ecu, {bool procedureVerified = true}) =>
      (ecu.verified && procedureVerified) || (expertMode && allows(Feature.expertMode));

  DiagClient client(EcuDef ecu) {
    return _clients.putIfAbsent(ecu.id, () {
      switch (ecu.protocol) {
        case EcuProtocol.kwp:
          return Kwp2000Client(adapter, ecu.target);
        case EcuProtocol.uds:
          return UdsClient(adapter, ecu.target);
        case EcuProtocol.obd:
          throw StateError('Use DiagnosticSession.obd for OBD-II');
      }
    });
  }

  /// Checks which of the profile's ECUs answer and reads their identification.
  Future<List<EcuStatus>> scan({void Function(EcuDef ecu)? onEcu}) async {
    require(Feature.identify);
    final out = <EcuStatus>[];
    for (final ecu in profile.ecus) {
      onEcu?.call(ecu);
      out.add(await identify(ecu));
    }
    return out;
  }

  Future<EcuStatus> identify(EcuDef ecu) async {
    EcuStatus s;
    try {
      if (ecu.protocol == EcuProtocol.obd) {
        final v = await obd.readVin();
        final pids = await obd.supportedPids();
        s = EcuStatus(ecu, present: pids.isNotEmpty, identity: {
          'VIN': ?v,
          'Supported values': '${pids.length}',
        });
        vin ??= v;
      } else {
        final c = client(ecu);
        final id = <String, String>{};
        for (final f in ecu.identification) {
          try {
            id[f.name] = f.format(await c.readIdentification(f.ident));
          } on NegativeResponseException {
            // Not every ECU supports every identifier.
          }
        }
        if (id.isEmpty) await c.testerPresent();
        s = EcuStatus(ecu, present: true, identity: id);
        final v = id['VIN'];
        if (v != null && v.length == 17) vin ??= v;
      }
    } on NegativeResponseException catch (e) {
      // A negative answer still proves the ECU is there.
      s = EcuStatus(ecu, present: true, error: e.reason);
    } on NoResponseException {
      s = EcuStatus(ecu, present: false);
    } on AdapterException catch (e) {
      s = EcuStatus(ecu, present: false, error: e.message);
    }
    status[ecu.id] = s;
    return s;
  }

  Iterable<EcuDef> get presentEcus =>
      profile.ecus.where((e) => status[e.id]?.present ?? true);

  /// Sends a harmless, longer-than-one-frame read to find out whether the
  /// adapter can transmit long messages. Any reply from the ECU, even a
  /// negative one, proves the message went out.
  Future<bool> probeLongMessages() async {
    final info = adapterInfo;
    if (info.isStn) return info.longMessagesVerified = true;
    final ecu = presentEcus.where((e) => e.protocol != EcuProtocol.obd).firstOrNull;
    if (ecu == null) return false;
    final payload = ecu.protocol == EcuProtocol.uds
        ? [0x22, 0xF1, 0x90, 0xF1, 0x8C, 0xF1, 0x87, 0xF1, 0x89]
        : [0x1A, 0x80, 0, 0, 0, 0, 0, 0, 0];
    info.longMessagesVerified = true;
    try {
      final msgs = await adapter.sendTo(ecu.target, payload);
      final ok = msgs.any((m) => m.source == ecu.address);
      info.longMessagesVerified = ok;
      log.info('Long message test: ${ok ? 'passed' : 'no reply'}');
      return ok;
    } on AdapterException catch (e) {
      info.longMessagesVerified = false;
      log.info('Long message test failed: $e');
      return false;
    }
  }

  /// Opens the write session and unlocks security for [ecu] when its
  /// profile needs it.
  Future<void> prepareForWrite(EcuDef ecu) async {
    final c = client(ecu);
    final sec = ecu.security;
    await c.startSession(sec?.session ?? ecu.effectiveWriteSession);
    if (sec != null && sec.algorithm != 'none') {
      final fn = KeyAlgorithms.lookup(sec.algorithm);
      if (fn == null) {
        throw StateError('Security algorithm "${sec.algorithm}" for ${ecu.name} is not available');
      }
      await c.securityAccess(sec.level, fn);
    }
  }

  Future<void> endWrite(EcuDef ecu) async {
    try {
      await client(ecu).startSession(ecu.protocol == EcuProtocol.kwp ? 0x81 : 0x01);
    } catch (e) {
      log.info('Could not return ${ecu.shortName} to default session: $e');
    }
  }

  /// Reads engine speed when the profile defines it, to check that the
  /// engine is off before writes. Returns null if unknown.
  Future<double?> engineRpm() async {
    for (final ecu in presentEcus) {
      for (final v in ecu.liveData) {
        if (v.id != 'rpm') continue;
        try {
          final data = ecu.protocol == EcuProtocol.obd
              ? await obd.readPid(v.ident)
              : await client(ecu).readData(v.ident);
          if (data != null) return v.encoding.decodeNumber(data);
        } catch (_) {
          // Try the next source.
        }
      }
    }
    return null;
  }

  String describeTarget(EcuDef ecu) => '${ecu.shortName} @ ${hexWord(ecu.address)} (${ecu.protocol.name.toUpperCase()})';
}
