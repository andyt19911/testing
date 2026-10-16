import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../licensing/tier.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _import(BuildContext context) async {
    final app = context.read<AppState>();
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Import bike profile'),
        content: TextField(
          controller: ctrl,
          minLines: 6,
          maxLines: 12,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: const InputDecoration(hintText: 'Paste profile JSON'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Import')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final p = app.profiles.addUserProfile(ctrl.text);
      await app.kv.setStringList('profiles.user', app.profiles.userSources.values.toList());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported "${p.name}"'), backgroundColor: AppTheme.ok));
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pro = app.tier.includes(Tier.pro);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Body(children: [
        const SectionHeader('Licence'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.workspace_premium),
            title: const Text('Licence and bikes'),
            trailing: TierBadge(app.license.tier),
            onTap: () => openLicense(context),
          ),
        ),
        const SectionHeader('Advanced'),
        Card(
          child: Column(children: [
            SwitchListTile(
              secondary: const Icon(Icons.science_outlined),
              title: const Text('Expert mode'),
              subtitle: const Text('Allow writing with functions that haven\'t been tested on your model yet. '
                  'Backups and safety checks still run, but you accept the risk.'),
              value: app.expertMode,
              onChanged: pro
                  ? (v) async {
                      if (v &&
                          !await confirmDialog(context, 'Turn on expert mode?',
                              'Untested functions can put a control unit into a state that needs a workshop to fix. '
                              'Only use them on your own bike and keep a charger connected.',
                              ok: 'Turn on', destructive: true)) {
                        return;
                      }
                      await app.setExpertMode(v);
                    }
                  : (_) => openLicense(context, highlight: Tier.pro),
            ),
            if (app.connected && app.profiles.all.length > 1)
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Bike profile'),
                subtitle: Text(app.session!.profile.name),
                onTap: () async {
                  final candidates = app.profiles.all.where((p) => p.simulator == app.isDemo).toList();
                  final chosen = await showDialog<String>(
                    context: context,
                    builder: (c) => SimpleDialog(
                      title: const Text('Bike profile'),
                      children: [
                        for (final p in candidates)
                          SimpleDialogOption(onPressed: () => Navigator.pop(c, p.id), child: Text(p.name)),
                      ],
                    ),
                  );
                  final p = chosen == null ? null : app.profiles.byId(chosen);
                  if (p != null) await app.switchProfile(p);
                },
              ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Import bike profile'),
              subtitle: const Text('Add support for a model from a profile file (JSON)'),
              onTap: () => pro ? _import(context) : openLicense(context, highlight: Tier.pro),
            ),
          ]),
        ),
        const SectionHeader('About'),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'RideScope is an independent diagnostic app and is not affiliated with or endorsed by BMW AG. '
              'BMW and BMW Motorrad are trademarks of BMW AG.\n\n'
              'Not supported on purpose: odometer changes, immobiliser/key programming, emissions-related '
              'deletes and ECU flashing.',
            ),
          ),
        ),
      ]),
    );
  }
}
