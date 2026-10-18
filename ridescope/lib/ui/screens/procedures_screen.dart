import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/ecu/profile.dart';
import '../../core/services/procedure_runner.dart';
import '../../licensing/tier.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'procedure_screen.dart';

/// Adaptations, calibrations, actuator tests and brake bleeding.
class ProceduresScreen extends StatelessWidget {
  const ProceduresScreen({super.key});

  static const _kinds = [ProcedureKind.bleed, ProcedureKind.adaptation, ProcedureKind.calibration, ProcedureKind.actuator];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final all = app.session!.profile.procedures.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Workshop tools')),
      body: Body(children: [
        for (final k in _kinds)
          if (all.any((x) => x.$2.kind == k)) ...[
            SectionHeader(k.label),
            for (final (ecu, p) in all.where((x) => x.$2.kind == k)) ProcedureTile(ecu: ecu, procedure: p),
          ],
      ]),
    );
  }
}

class ProcedureTile extends StatelessWidget {
  const ProcedureTile({super.key, required this.ecu, required this.procedure});
  final EcuDef ecu;
  final ProcedureDef procedure;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final present = app.session!.status[ecu.id]?.present ?? false;
    final feature = ProcedureRunner.featureFor(procedure.kind);
    final locked = !app.allows(feature) || !app.tier.includes(procedure.tier);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          enabled: present,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Icon(
            switch (procedure.kind) {
              ProcedureKind.service => Icons.build_circle_outlined,
              ProcedureKind.date => Icons.event,
              ProcedureKind.bleed => Icons.water_drop_outlined,
              ProcedureKind.actuator => Icons.electric_bolt,
              ProcedureKind.calibration => Icons.straighten,
              ProcedureKind.adaptation => Icons.restart_alt,
            },
            color: AppTheme.accent,
          ),
          title: Row(children: [
            Flexible(child: Text(procedure.name, style: const TextStyle(fontWeight: FontWeight.w700))),
            if (procedure.offRoadOnly) ...[
              const SizedBox(width: 8),
              const Pill('Track', color: AppTheme.warn, icon: Icons.sports_motorsports_outlined),
            ],
          ]),
          subtitle: Text(present ? '${ecu.shortName} · ${procedure.description}' : '${ecu.name} not found on this bike',
              maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: locked ? TierBadge(procedure.tier) : const Icon(Icons.chevron_right),
          onTap: () => locked
              ? openLicense(context, highlight: procedure.tier)
              : Navigator.push(context, MaterialPageRoute(builder: (_) => ProcedureScreen(ecu: ecu, procedure: procedure))),
        ),
      ),
    );
  }
}
