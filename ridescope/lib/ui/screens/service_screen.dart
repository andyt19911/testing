import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/ecu/profile.dart';
import '../../licensing/tier.dart';
import '../widgets/common.dart';
import 'procedures_screen.dart';

class ServiceScreen extends StatelessWidget {
  const ServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final items = app.session!.profile.procedures
        .where((x) => x.$2.kind == ProcedureKind.service || x.$2.kind == ProcedureKind.date)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Service')),
      body: Body(children: [
        if (!app.allows(Feature.serviceReset)) ...[const LockedCard(Feature.serviceReset), const SizedBox(height: 12)],
        const InfoBanner(
          text: 'Set the cluster date first if it is wrong; the service reset uses it to work out the next due date.',
          color: Colors.blueGrey,
        ),
        const SizedBox(height: 8),
        for (final (ecu, p) in items) ProcedureTile(ecu: ecu, procedure: p),
      ]),
    );
  }
}
