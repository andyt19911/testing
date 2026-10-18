import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../licensing/license_service.dart';
import '../../licensing/purchase_service.dart';
import '../../licensing/tier.dart';
import '../theme.dart';
import '../widgets/common.dart';

class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key, this.highlight});
  final Tier? highlight;
  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final _key = TextEditingController();
  bool _applying = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _applyKey() async {
    final app = context.read<AppState>();
    setState(() => _applying = true);
    try {
      final t = await app.license.applyToken(_key.text);
      _key.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('RideScope ${t.tier.label} activated${t.holder.isEmpty ? '' : ' for ${t.holder}'}'),
          backgroundColor: AppTheme.ok,
        ));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
    if (mounted) setState(() => _applying = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final shop = context.watch<PurchaseService>();
    final lic = app.license;
    return Scaffold(
      appBar: AppBar(title: const Text('Licence')),
      body: Body(children: [
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Icon(Icons.workspace_premium, color: AppTheme.tier(lic.tier), size: 36),
            title: Text('You have RideScope ${lic.tier.label}', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(lic.token != null
                ? 'Licence key ${lic.token!.id}${lic.token!.expires == null ? '' : ', valid until ${lic.token!.expires!.toLocal().toString().substring(0, 10)}'}'
                : lic.tier.tagline),
          ),
        ),
        if (app.isDemo) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Preview tiers on the demo bike', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('Only applies to the demo bike, so you can see what each tier unlocks.'),
                const SizedBox(height: 12),
                SegmentedButton<Tier>(
                  segments: [for (final t in Tier.values) ButtonSegment(value: t, label: Text(t.label))],
                  selected: {lic.demoTier},
                  onSelectionChanged: (s) => lic.setDemoTier(s.first),
                ),
              ]),
            ),
          ),
        ],
        const SectionHeader('Compare'),
        _Comparison(highlight: widget.highlight),
        const SizedBox(height: 12),
        for (final t in [Tier.plus, Tier.pro])
          if (!lic.tier.includes(t))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.tier(t)),
                onPressed: shop.busy ? null : () => shop.buy(t),
                child: Text('Get ${t.label}${shop.priceFor(t) == null ? '' : ' · ${shop.priceFor(t)}'}'),
              ),
            ),
        if (PurchaseService.supportedPlatform)
          TextButton(onPressed: shop.restore, child: const Text('Restore purchases')),
        if (shop.error != null) InfoBanner(text: shop.error!, color: AppTheme.warn),
        const SectionHeader('Licence key'),
        const Text('Workshops and direct customers receive a licence key by email.'),
        const SizedBox(height: 8),
        TextField(
          controller: _key,
          minLines: 2,
          maxLines: 4,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: const InputDecoration(hintText: 'Paste your licence key'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _applying ? null : _applyKey, child: const Text('Activate')),
        const SectionHeader('Bikes on this licence'),
        Text(lic.tier.maxBikes == null
            ? 'Unlimited bikes.'
            : '${lic.registeredVins.length} of ${lic.tier.maxBikes} used. A bike is added the first time you connect to it.'),
        for (final vin in lic.registeredVins)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.two_wheeler),
            title: Text(vin, style: const TextStyle(fontFamily: 'monospace')),
            trailing: TextButton(
              onPressed: () async {
                if (!await confirmDialog(context, 'Remove bike?',
                    'Frees a slot for another bike. You can do this once every 30 days.', ok: 'Remove')) {
                  return;
                }
                try {
                  await lic.removeVin(vin);
                } catch (e) {
                  if (context.mounted) showError(context, e);
                }
              },
              child: const Text('Remove'),
            ),
          ),
        if (developerUnlockAvailable) ...[
          SectionHeader(testerBuild ? 'Tester build' : 'Developer (debug builds only)'),
          Wrap(spacing: 8, children: [
            for (final t in Tier.values) OutlinedButton(onPressed: () => lic.setDeveloperTier(t), child: Text('Unlock ${t.label}')),
          ]),
        ],
      ]),
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison({this.highlight});
  final Tier? highlight;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, List<String>)>[
      ('Bikes', ['1', '2', 'Unlimited']),
      for (final f in Feature.values)
        if (f != Feature.identify) (f.label, [for (final t in Tier.values) t.includes(f.minTier) ? '✓' : '—']),
    ];
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: const {0: FlexColumnWidth(2.4), 1: FlexColumnWidth(), 2: FlexColumnWidth(), 3: FlexColumnWidth()},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            decoration: BoxDecoration(color: scheme.surfaceContainer),
            children: [
              const SizedBox(),
              for (final t in Tier.values)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(t.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.tier(t),
                          decoration: highlight == t ? TextDecoration.underline : null,
                        )),
                  ),
                ),
            ],
          ),
          for (final (label, cells) in rows)
            TableRow(children: [
              Padding(padding: const EdgeInsets.fromLTRB(12, 10, 4, 10), child: Text(label)),
              for (var i = 0; i < 3; i++)
                Container(
                  color: highlight?.index == i ? AppTheme.tier(highlight!).withValues(alpha: 0.08) : null,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Center(
                    child: Text(cells[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: cells[i] == '—' ? scheme.onSurfaceVariant : AppTheme.tier(Tier.values[i]),
                        )),
                  ),
                ),
            ]),
        ],
      ),
    );
  }
}
