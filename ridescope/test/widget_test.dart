import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ridescope/app/app_state.dart';
import 'package:ridescope/app/garage.dart';
import 'package:ridescope/app/prefs_store.dart';
import 'package:ridescope/core/ecu/profile_repository.dart';
import 'package:ridescope/licensing/license_service.dart';
import 'package:ridescope/licensing/license_token.dart';
import 'package:ridescope/licensing/purchase_service.dart';
import 'package:ridescope/licensing/tier.dart';
import 'package:ridescope/main.dart';

Future<AppState> makeState() async {
  final kv = MemoryKeyValueStore();
  final profiles = ProfileRepository((p) => File(p).readAsString());
  await profiles.load();
  final license = LicenseService(kv, LicenseCodec(List.filled(32, 0)));
  return AppState(
    profiles: profiles,
    license: license,
    purchases: PurchaseService(license),
    kv: kv,
    backups: PrefsBackupStore(kv),
    garage: Garage(kv),
  );
}

Widget wrap(AppState s) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: s),
        ChangeNotifierProvider.value(value: s.purchases),
      ],
      child: const RideScopeApp(),
    );

/// Lets real adapter I/O run (it lives outside the fake test clock), then
/// pumps frames without waiting for spinners to stop.
Future<void> settle(WidgetTester t, [int ms = 2000]) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 50));
  }
}


void main() {
  testWidgets('demo bike: connect, dashboard, faults, service wizard', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    final state = await tester.runAsync(makeState);
    await tester.pumpWidget(wrap(state!));
    expect(find.text('Connect to your bike'), findsOneWidget);

    await tester.runAsync(() => state.connectDemo());
    await tester.pumpAndSettle();
    expect(state.error, isNull);
    expect(state.connected, isTrue);
    expect(find.text('WHAT DO YOU WANT TO DO?'), findsOneWidget);
    expect(find.text('Fault codes'), findsOneWidget);
    expect(find.text('Bike settings'), findsOneWidget);

    await tester.tap(find.text('Fault codes'));
    await settle(tester);
    expect(find.text('5E2101'), findsOneWidget);
    expect(find.text('Clear all faults'), findsOneWidget);
    await tester.pageBack();
    await settle(tester, 300);

    await tester.tap(find.text('Service'));
    await settle(tester, 300);
    await tester.tap(find.text('Reset service reminder'));
    await settle(tester);
    expect(find.text('BEFORE YOU START'), findsOneWidget);
    expect(find.text('Ignition is on'), findsOneWidget);
  });

  testWidgets('free tier shows coding as locked', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final state = await tester.runAsync(makeState);
    await tester.runAsync(() => state!.license.setDemoTier(Tier.free));
    await tester.pumpWidget(wrap(state!));
    await tester.runAsync(() => state.connectDemo());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Bike settings'));
    await tester.tap(find.text('Bike settings'));
    await settle(tester, 300);
    expect(find.text('COMPARE'), findsOneWidget);
  });
}
