import '../../licensing/tier.dart';
import '../ecu/dtc_database.dart';
import '../ecu/profile.dart';
import '../protocol/diag_client.dart';
import 'session.dart';

class EcuFaults {
  EcuFaults(this.ecu, this.faults, {this.error});
  final EcuDef ecu;
  final List<FaultInfo> faults;
  final String? error;
}

class FaultService {
  FaultService(this.session);
  final DiagnosticSession session;

  Future<List<FaultInfo>> _read(EcuDef ecu) async {
    final dtcs = ecu.protocol == EcuProtocol.obd
        ? await session.obd.readDtcs()
        : await session.client(ecu).readDtcs();
    return dtcs.map((d) => DtcDatabase.describe(ecu, d)).toList();
  }

  /// Reads fault memory of every ECU that answered the scan.
  Future<List<EcuFaults>> readAll({void Function(EcuDef ecu)? onEcu}) async {
    session.require(Feature.readFaults);
    final out = <EcuFaults>[];
    for (final ecu in session.presentEcus) {
      onEcu?.call(ecu);
      try {
        out.add(EcuFaults(ecu, await _read(ecu)));
      } catch (e) {
        out.add(EcuFaults(ecu, const [], error: _message(e)));
      }
    }
    return out;
  }

  Future<FreezeFrame?> freezeFrame(FaultInfo f) async {
    session.require(Feature.freezeFrames);
    if (f.ecu.protocol == EcuProtocol.obd) return null;
    final ff = await session.client(f.ecu).readFreezeFrame(f.dtc);
    f.freezeFrame = ff;
    return ff;
  }

  Future<void> clear(EcuDef ecu) async {
    session.require(Feature.clearFaults);
    if (ecu.protocol == EcuProtocol.obd) {
      await session.obd.clearDtcs();
    } else {
      await session.client(ecu).clearDtcs();
    }
    session.log.info('Cleared fault memory of ${ecu.shortName}');
  }

  Future<Map<EcuDef, String?>> clearAll(Iterable<EcuDef> ecus) async {
    session.require(Feature.clearFaults);
    final out = <EcuDef, String?>{};
    for (final e in ecus) {
      try {
        await clear(e);
        out[e] = null;
      } catch (err) {
        out[e] = _message(err);
      }
    }
    return out;
  }

  static String _message(Object e) => switch (e) {
        NegativeResponseException n => n.reason,
        _ => e.toString(),
      };
}
