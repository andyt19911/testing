import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../core/util/hex.dart';
import '../theme.dart';
import '../widgets/common.dart';

class EcusScreen extends StatefulWidget {
  const EcusScreen({super.key});
  @override
  State<EcusScreen> createState() => _EcusScreenState();
}

class _EcusScreenState extends State<EcusScreen> {
  bool _scanning = false;

  Future<void> _rescan() async {
    setState(() => _scanning = true);
    try {
      await context.read<AppState>().session!.scan();
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().session!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Control units'),
        actions: [
          _scanning
              ? const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(onPressed: _rescan, icon: const Icon(Icons.refresh), tooltip: 'Scan again'),
        ],
      ),
      body: Body(children: [
        for (final e in s.profile.ecus) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.memory, color: (s.status[e.id]?.present ?? false) ? AppTheme.ok : Colors.blueGrey),
                  const SizedBox(width: 10),
                  Expanded(child: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                  Pill((s.status[e.id]?.present ?? false) ? 'Found' : 'No answer',
                      color: (s.status[e.id]?.present ?? false) ? AppTheme.ok : Colors.blueGrey),
                ]),
                const SizedBox(height: 8),
                KeyValueRow('Address', '0x${hexWord(e.address, digits: e.address > 0xFF ? 3 : 2)} · ${e.protocol.name.toUpperCase()}'),
                KeyValueRow('Profile', e.verified ? 'Tested on this model' : 'Not yet tested on this model'),
                for (final kv in (s.status[e.id]?.identity ?? const <String, String>{}).entries) KeyValueRow(kv.key, kv.value),
                if (s.status[e.id]?.error != null) KeyValueRow('Note', s.status[e.id]!.error!),
              ]),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ]),
    );
  }
}
