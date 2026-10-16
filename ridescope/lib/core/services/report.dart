import 'package:intl/intl.dart';

import '../ecu/dtc_database.dart';
import 'fault_service.dart';
import 'session.dart';

/// Plain-text health report that can be shared (e.g. sent to a workshop or a
/// buyer).
class HealthReport {
  static String build(
    DiagnosticSession s, {
    required List<EcuFaults> faults,
    Map<String, String> service = const {},
    Map<String, String> keyValues = const {},
    DateTime? now,
  }) {
    final t = DateFormat('d MMM yyyy, HH:mm').format(now ?? DateTime.now());
    final b = StringBuffer()
      ..writeln('RideScope health report')
      ..writeln('=======================')
      ..writeln('Date:     $t')
      ..writeln('Bike:     ${s.profile.name}')
      ..writeln('VIN:      ${s.vin ?? 'unknown'}')
      ..writeln('Adapter:  ${s.adapterInfo.summary}')
      ..writeln();
    if (service.isNotEmpty) {
      b.writeln('Service');
      service.forEach((k, v) => b.writeln('  $k: $v'));
      b.writeln();
    }
    if (keyValues.isNotEmpty) {
      b.writeln('Readings');
      keyValues.forEach((k, v) => b.writeln('  $k: $v'));
      b.writeln();
    }
    b.writeln('Control units');
    for (final st in s.status.values) {
      final ident = st.identity.entries.where((e) => e.key != 'VIN').map((e) => '${e.key} ${e.value}').join(', ');
      b.writeln('  ${st.present ? '✓' : '✗'} ${st.ecu.name}${ident.isEmpty ? '' : ' ($ident)'}');
    }
    b.writeln();
    final total = faults.fold<int>(0, (a, f) => a + f.faults.length);
    b.writeln('Fault memory: ${total == 0 ? 'no faults stored' : '$total fault(s)'}');
    for (final f in faults) {
      if (f.error != null) {
        b.writeln('  ${f.ecu.name}: could not read (${f.error})');
        continue;
      }
      for (final x in f.faults) {
        b.writeln('  [${x.severity.label}] ${f.ecu.shortName} ${x.code} (${x.dtc.state.name}): ${x.description}');
      }
    }
    return b.toString();
  }
}
