import '../protocol/diag_client.dart';
import '../protocol/obd2.dart';
import 'profile.dart';

enum Severity { info, low, medium, high }

extension SeverityText on Severity {
  String get label => switch (this) {
        Severity.info => 'Information',
        Severity.low => 'Minor',
        Severity.medium => 'Needs attention',
        Severity.high => 'Serious',
      };

  String get rideAdvice => switch (this) {
        Severity.info => 'No action needed.',
        Severity.low => 'Safe to ride. Have it checked at your next service.',
        Severity.medium => 'You can ride carefully. Get it checked soon.',
        Severity.high => 'Don\'t ride until this is checked. It affects a safety-related system.',
      };
}

class FaultInfo {
  FaultInfo({
    required this.ecu,
    required this.dtc,
    required this.code,
    required this.description,
    required this.severity,
    this.freezeFrame,
  });

  final EcuDef ecu;
  final Dtc dtc;
  final String code;
  final String description;
  final Severity severity;
  FreezeFrame? freezeFrame;
}

/// Plain-language text for common SAE codes. BMW-specific codes come from the
/// ECU profile's `dtcText`.
const Map<String, String> _obdText = {
  'P0101': 'Air-flow / intake pressure sensor reading out of range',
  'P0106': 'Intake manifold pressure sensor reading out of range',
  'P0112': 'Intake air temperature sensor: signal too low',
  'P0113': 'Intake air temperature sensor: signal too high',
  'P0115': 'Coolant temperature sensor circuit',
  'P0117': 'Coolant temperature sensor: signal too low',
  'P0118': 'Coolant temperature sensor: signal too high',
  'P0120': 'Throttle position sensor circuit',
  'P0130': 'Oxygen (lambda) sensor 1 circuit',
  'P0135': 'Oxygen (lambda) sensor 1 heater circuit',
  'P0171': 'Mixture too lean (bank 1). Common causes: air leak, dirty injector, low fuel pressure',
  'P0172': 'Mixture too rich (bank 1)',
  'P0201': 'Injector cylinder 1 circuit',
  'P0202': 'Injector cylinder 2 circuit',
  'P0300': 'Random or multiple misfires detected',
  'P0301': 'Misfire, cylinder 1',
  'P0302': 'Misfire, cylinder 2',
  'P0335': 'Crankshaft position sensor circuit',
  'P0340': 'Camshaft position sensor circuit',
  'P0420': 'Catalytic converter efficiency below threshold',
  'P0443': 'Evaporative emission purge valve circuit',
  'P0500': 'Vehicle speed sensor',
  'P0505': 'Idle control system',
  'P0560': 'System voltage problem',
  'P0562': 'System voltage low. Check the battery and charging',
  'P0563': 'System voltage high. Check the regulator',
  'P0601': 'Engine control unit memory checksum error',
  'P0700': 'Transmission / gear sensor fault reported',
};

class DtcDatabase {
  static FaultInfo describe(EcuDef ecu, Dtc dtc) {
    final isObd = ecu.protocol == EcuProtocol.obd;
    final code = isObd ? formatObdDtc(dtc.code) : dtc.hexCode;
    final text = ecu.dtcText[code] ?? (isObd ? _obdText[code] : null);
    return FaultInfo(
      ecu: ecu,
      dtc: dtc,
      code: code,
      description: text ??
          (isObd
              ? 'Emissions-related fault ($code)'
              : 'Fault code $code stored in ${ecu.name}. There is no description for it yet.'),
      severity: _severity(ecu, dtc, code),
    );
  }

  static Severity _severity(EcuDef ecu, Dtc dtc, String code) {
    final active = dtc.state == DtcState.active;
    switch (ecu.category) {
      case 'abs':
      case 'chassis':
        return active ? Severity.high : Severity.medium;
      case 'engine':
      case 'obd':
        if (code.startsWith('P03') || code.startsWith('P06')) return Severity.high;
        return active ? Severity.medium : Severity.low;
      case 'cluster':
      case 'body':
      case 'tpms':
        return active ? Severity.low : Severity.info;
      default:
        return active ? Severity.medium : Severity.low;
    }
  }
}
