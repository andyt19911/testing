import '../../licensing/tier.dart';
import '../ecu/profile.dart';
import '../ecu/template.dart';
import '../protocol/diag_client.dart';
import '../util/hex.dart';
import 'session.dart';

typedef ConfirmCallback = Future<bool> Function(String message);

class ProcedureProgress {
  ProcedureProgress(this.index, this.total, this.text);
  final int index;
  final int total;
  final String text;
  double get fraction => total == 0 ? 1 : index / total;
}

class ProcedureCancelled implements Exception {
  @override
  String toString() => 'Cancelled';
}

class VerificationFailed implements Exception {
  VerificationFailed(this.ident, this.expected, this.actual);
  final int ident;
  final List<int> expected;
  final List<int> actual;
  @override
  String toString() =>
      'Read-back of ${hexWord(ident, digits: 4)} did not match (expected ${toHex(expected)}, got ${toHex(actual)})';
}

/// Executes a [ProcedureDef] step by step. All BMW-specific detail (which
/// identifier, which routine, which data) comes from the profile.
class ProcedureRunner {
  ProcedureRunner(this.session, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final DiagnosticSession session;
  final DateTime Function() _clock;

  static Feature featureFor(ProcedureKind k) => switch (k) {
        ProcedureKind.service || ProcedureKind.date => Feature.serviceReset,
        ProcedureKind.adaptation || ProcedureKind.calibration => Feature.adaptations,
        ProcedureKind.actuator || ProcedureKind.bleed => Feature.actuators,
      };

  /// Reads the procedure's status values (e.g. the current service due date).
  Future<Map<String, String>> readStatus(EcuDef ecu, ProcedureDef p) async {
    final out = <String, String>{};
    final c = session.client(ecu);
    for (final f in p.statusReads) {
      try {
        out[f.name] = f.format(await c.readData(f.ident));
      } catch (e) {
        out[f.name] = '—';
      }
    }
    return out;
  }

  Future<void> run(
    EcuDef ecu,
    ProcedureDef p, {
    Map<String, int> inputs = const {},
    required ConfirmCallback confirm,
    void Function(ProcedureProgress)? onProgress,
  }) async {
    session.require(featureFor(p.kind));
    if (!session.tier.includes(p.tier)) throw FeatureLockedException(featureFor(p.kind));
    if (p.writes && !session.writesAllowed(ecu, procedureVerified: p.verified)) {
      throw StateError('${p.name} has not been verified on this bike');
    }
    final values = {for (final i in p.inputs) i.id: i.defaultValue, ...inputs};
    final c = session.client(ecu);
    final now = _clock();
    session.log.info('Running "${p.name}" on ${session.describeTarget(ecu)}');
    var sessionOpened = false;
    try {
      for (var i = 0; i < p.steps.length; i++) {
        final s = p.steps[i];
        onProgress?.call(ProcedureProgress(i, p.steps.length, s.label ?? _describe(s)));
        List<int> data() => s.data == null ? const [] : DataTemplate(s.data!).render(now: now, inputs: values);
        switch (s.op) {
          case 'session':
            await c.startSession(s.value ?? ecu.effectiveWriteSession);
            sessionOpened = true;
            break;
          case 'security':
            await session.prepareForWrite(ecu);
            sessionOpened = true;
            break;
          case 'write':
            await c.writeData(s.ident!, data());
            break;
          case 'verify':
            final expected = data();
            final actual = await c.readData(s.ident!);
            if (!_eq(expected, actual)) throw VerificationFailed(s.ident!, expected, actual);
            break;
          case 'read':
            await c.readData(s.ident!);
            break;
          case 'routine':
            await _routine(c, s, data());
            break;
          case 'io':
            await c.ioControl(s.ident!, s.param ?? 3, data: data());
            break;
          case 'wait':
            await Future<void>.delayed(Duration(milliseconds: s.ms ?? 1000));
            break;
          case 'prompt':
            if (!await confirm(s.message ?? 'Continue?')) throw ProcedureCancelled();
            break;
          case 'reset':
            await c.ecuReset(type: s.value ?? 1);
            sessionOpened = false;
            break;
          case 'clearDtcs':
            await c.clearDtcs();
            break;
          default:
            throw StateError('Unknown step "${s.op}" in ${p.id}');
        }
      }
      onProgress?.call(ProcedureProgress(p.steps.length, p.steps.length, 'Done'));
      session.log.info('"${p.name}" completed');
    } finally {
      if (sessionOpened) await session.endWrite(ecu);
    }
  }

  Future<void> _routine(DiagClient c, ProcedureStep s, List<int> data) async {
    try {
      await c.routine(s.ident!, control: s.control ?? 1, data: data);
    } on ResponsePendingException {
      // Long-running routine: poll for results until it finishes.
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        try {
          await c.routine(s.ident!, control: 3);
          return;
        } on ResponsePendingException {
          continue;
        } on NegativeResponseException catch (e) {
          if (e.code == 0x21 || e.code == 0x24) continue;
          rethrow;
        }
      }
      throw NoResponseException('routine ${hexWord(s.ident!, digits: 4)} did not finish');
    }
  }

  static String _describe(ProcedureStep s) => switch (s.op) {
        'session' => 'Opening diagnostic session',
        'security' => 'Unlocking control unit',
        'write' => 'Writing new values',
        'verify' => 'Checking the values were stored',
        'read' => 'Reading',
        'routine' => 'Running routine',
        'io' => 'Driving actuator',
        'wait' => 'Waiting',
        'prompt' => 'Waiting for you',
        'reset' => 'Restarting control unit',
        'clearDtcs' => 'Clearing fault memory',
        _ => s.op,
      };

  static bool _eq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
