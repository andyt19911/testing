import '../../licensing/tier.dart';
import '../adapter/elm327.dart';
import '../ecu/profile.dart';
import '../ecu/security.dart';
import 'procedure_runner.dart';
import 'session.dart';

enum CheckState { ok, warning, fail, confirm }

class PreflightCheck {
  PreflightCheck(this.label, this.state, [this.detail]);
  final String label;
  final CheckState state;
  final String? detail;
}

class PreflightResult {
  PreflightResult(this.checks);
  final List<PreflightCheck> checks;

  bool get blocked => checks.any((c) => c.state == CheckState.fail);
  List<PreflightCheck> get confirmations =>
      checks.where((c) => c.state == CheckState.confirm).toList();
}

/// Safety checks run before any operation that writes to the bike.
class Preflight {
  Preflight(this.session);
  final DiagnosticSession session;

  Future<PreflightResult> forProcedure(EcuDef ecu, ProcedureDef p) => _run(
        feature: ProcedureRunner.featureFor(p.kind),
        tier: p.tier,
        ecus: [ecu],
        verified: ecu.verified && p.verified,
        needsLong: p.needsLongMessages,
        pre: p.preconditions,
        writes: p.writes,
      );

  Future<PreflightResult> forCoding(List<EcuDef> ecus, {bool needsLong = true}) => _run(
        feature: Feature.coding,
        tier: Tier.pro,
        ecus: ecus,
        verified: ecus.every((e) => e.verified),
        needsLong: needsLong,
        pre: const Preconditions(minVoltage: 12.2),
        writes: true,
      );

  Future<PreflightResult> _run({
    required Feature feature,
    required Tier tier,
    required List<EcuDef> ecus,
    required bool verified,
    required bool needsLong,
    required Preconditions pre,
    required bool writes,
  }) async {
    final checks = <PreflightCheck>[];
    final required = tier.index > feature.minTier.index ? tier : feature.minTier;
    checks.add(session.tier.includes(required)
        ? PreflightCheck('Licence', CheckState.ok, session.tier.label)
        : PreflightCheck('Licence', CheckState.fail, 'Needs RideScope ${required.label}'));

    if (writes) {
      if (verified) {
        checks.add(PreflightCheck('Bike support', CheckState.ok, 'Tested on this model'));
      } else if (session.writesAllowed(ecus.first, procedureVerified: false)) {
        checks.add(PreflightCheck('Bike support', CheckState.warning,
            'Not yet tested on this model. Expert mode is on, so you take the risk.'));
      } else {
        checks.add(PreflightCheck('Bike support', CheckState.fail,
            'Not yet tested on this model. Use Discovery to confirm it on your bike, or switch on expert mode (Pro).'));
      }

      for (final e in ecus) {
        final sec = e.security;
        if (sec != null && !KeyAlgorithms.has(sec.algorithm)) {
          checks.add(PreflightCheck('Access to ${e.shortName}', CheckState.fail,
              'This control unit needs an access key that RideScope doesn\'t have.'));
        }
      }
    }

    if (needsLong) {
      final info = session.adapterInfo;
      if (info.canSendLongMessages) {
        checks.add(PreflightCheck('Adapter', CheckState.ok, info.summary));
      } else if (info.longMessagesVerified == null) {
        final ok = await session.probeLongMessages();
        checks.add(ok
            ? PreflightCheck('Adapter', CheckState.ok, 'Long messages supported')
            : PreflightCheck('Adapter', CheckState.fail,
                '${info.family.label} cannot send the long messages this needs. Use an OBDLink LX/MX+/CX adapter.'));
      } else {
        checks.add(PreflightCheck('Adapter', CheckState.fail,
            '${info.family.label} cannot send the long messages this needs. Use an OBDLink LX/MX+/CX adapter.'));
      }
    }

    final v = await session.adapter.readVoltage();
    if (v == null) {
      checks.add(PreflightCheck('Battery', CheckState.warning, 'Voltage unknown'));
    } else if (v < pre.minVoltage) {
      checks.add(PreflightCheck('Battery', CheckState.fail,
          '${v.toStringAsFixed(1)} V is below ${pre.minVoltage.toStringAsFixed(1)} V. Connect a charger first.'));
    } else {
      checks.add(PreflightCheck('Battery', CheckState.ok, '${v.toStringAsFixed(1)} V'));
    }

    if (pre.engineOff || pre.engineRunning) {
      final rpm = await session.engineRpm();
      if (rpm == null) {
        checks.add(PreflightCheck(
            pre.engineOff ? 'Engine is off' : 'Engine is running', CheckState.confirm));
      } else if (pre.engineOff && rpm > 50) {
        checks.add(PreflightCheck('Engine', CheckState.fail,
            'Engine is running (${rpm.round()} rpm). Switch it off, ignition on.'));
      } else if (pre.engineRunning && rpm < 300) {
        checks.add(PreflightCheck('Engine', CheckState.fail, 'Start the engine first.'));
      } else {
        checks.add(PreflightCheck('Engine', CheckState.ok, pre.engineOff ? 'Off' : '${rpm.round()} rpm'));
      }
    }
    if (pre.ignitionOn) checks.add(PreflightCheck('Ignition is on', CheckState.confirm));
    for (final x in pre.extra) {
      checks.add(PreflightCheck(x, CheckState.confirm));
    }
    return PreflightResult(checks);
  }
}
