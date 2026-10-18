import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridescope/core/adapter/elm327.dart';
import 'package:ridescope/core/ecu/dtc_database.dart';
import 'package:ridescope/core/ecu/profile.dart';
import 'package:ridescope/core/ecu/profile_repository.dart';
import 'package:ridescope/core/ecu/template.dart';
import 'package:ridescope/core/services/backup_store.dart';
import 'package:ridescope/core/services/coding_engine.dart';
import 'package:ridescope/core/services/discovery_service.dart';
import 'package:ridescope/core/services/fault_service.dart';
import 'package:ridescope/core/services/live_data_service.dart';
import 'package:ridescope/core/services/preflight.dart';
import 'package:ridescope/core/services/procedure_runner.dart';
import 'package:ridescope/core/services/report.dart';
import 'package:ridescope/core/services/session.dart';
import 'package:ridescope/core/sim/sim_transport.dart';
import 'package:ridescope/core/sim/virtual_bike.dart';
import 'package:ridescope/licensing/tier.dart';

late ProfileRepository repo;

Future<(DiagnosticSession, VirtualBike)> open(
  String profileId, {
  Tier tier = Tier.pro,
  SimAdapter adapter = SimAdapter.stn,
}) async {
  final profile = repo.byId(profileId)!;
  final bike = VirtualBike(bus: profile.isKLine ? SimBus.kLine : SimBus.can);
  final elm = Elm327Adapter(SimulatedTransport(bike, adapter: adapter, latency: Duration.zero));
  await elm.initialize();
  final s = DiagnosticSession(adapter: elm, profile: profile, tier: () => tier);
  await s.scan();
  return (s, bike);
}

Future<bool> yes(String _) async => true;

void main() {
  setUpAll(() async {
    repo = ProfileRepository((p) => File(p).readAsString());
    await repo.load();
  });

  test('all built-in profiles parse', () {
    expect(repo.all.map((p) => p.id), containsAll(['bmw-can', 'bmw-kline', 'sim-can', 'sim-kline']));
    expect(repo.real.every((p) => p.ecus.where((e) => e.protocol != EcuProtocol.obd).every((e) => !e.verified)), isTrue,
        reason: 'real-bike BMW ECUs must stay unverified until confirmed on a bike');
  });

  for (final id in ['sim-can', 'sim-kline']) {
    group(id, () {
      test('scan finds every ECU and the VIN', () async {
        final (s, _) = await open(id);
        expect(s.status.values.every((e) => e.present), isTrue);
        expect(s.vin, VirtualBike.vin);
        expect(s.status['engine']!.identity['Part number'], '8 569 123');
      });

      test('faults: read with descriptions, freeze frame, clear', () async {
        final (s, _) = await open(id);
        final svc = FaultService(s);
        final all = await svc.readAll();
        final abs = all.firstWhere((f) => f.ecu.id == 'abs').faults.single;
        expect(abs.description, contains('wheel speed'));
        expect(abs.severity, Severity.high);
        final eng = all.firstWhere((f) => f.ecu.id == 'engine').faults.single;
        expect(await svc.freezeFrame(eng), isNotNull);
        await svc.clear(abs.ecu);
        final after = await svc.readAll();
        expect(after.firstWhere((f) => f.ecu.id == 'abs').faults, isEmpty);
      });

      test('live data decodes values', () async {
        final (s, bike) = await open(id);
        bike.engineRunning = true;
        final live = LiveDataService(s);
        final chans = LiveDataService.available(s);
        final rpm = chans.firstWhere((c) => c.key == 'engine/rpm');
        final batt = chans.firstWhere((c) => c.key == 'engine/battery');
        expect((await live.readOnce(rpm)).value, greaterThan(1000));
        expect((await live.readOnce(batt)).value, closeTo(14.1, 0.2));
        final gear = chans.firstWhere((c) => c.key == 'engine/gear');
        expect((await live.readOnce(gear)).text, isNotEmpty);
      });

      test('service reset writes date and distance and verifies', () async {
        final now = DateTime(2026, 10, 16, 9, 30);
        final (s, bike) = await open(id);
        final kombi = s.profile.ecu('kombi')!;
        final proc = kombi.procedures.firstWhere((p) => p.id == 'service_reset');
        final runner = ProcedureRunner(s, clock: () => now);
        final pre = await Preflight(s).forProcedure(kombi, proc);
        expect(pre.blocked, isFalse, reason: pre.checks.map((c) => '${c.label}:${c.detail}').join(', '));
        await runner.run(kombi, proc, inputs: {'distance': 10000, 'months': 12}, confirm: yes);
        final status = await runner.readStatus(kombi, proc);
        expect(status['Service due on'], '16.10.2027');
        expect(status['Service due in'], '10000 km');
        expect(bike.serviceResets, 1);
      });

      test('coding: linked TPMS change, backup, verify, restore', () async {
        final (s, bike) = await open(id);
        final store = MemoryBackupStore();
        final eng = CodingEngine(s, store);
        final plan = await eng.plan({('zfe', 'tpms'): 0});
        expect(plan.changes.map((c) => c.param.id), containsAll(['tpms', 'tpms_display']));
        expect(plan.writes.length, 2);
        await eng.apply(plan);
        final zfeIdent = s.profile.ecu('zfe')!.coding.first.ident;
        expect(bike.ecus[0x40]!.writable[zfeIdent]![0] & 1, 0);
        final params = await eng.readParams(s.profile.ecu('kombi')!);
        expect(params.entries.firstWhere((e) => e.key.id == 'tpms_display').value, 0);
        final backups = await store.list();
        expect(backups.length, 2);
        await eng.restore(backups.firstWhere((b) => b.ecuId == 'zfe'));
        expect(bike.ecus[0x40]!.writable[zfeIdent]![0] & 1, 1);
      });

      test('ABS bleed asks the rider and can be cancelled', () async {
        final (s, _) = await open(id);
        final abs = s.profile.ecu('abs')!;
        final proc = abs.procedures.firstWhere((p) => p.id == 'bleed_front');
        final prompts = <String>[];
        await ProcedureRunner(s).run(abs, proc, confirm: (m) async {
          prompts.add(m);
          return true;
        });
        expect(prompts.length, 3);
        await expectLater(
          ProcedureRunner(s).run(abs, proc, confirm: (m) async => false),
          throwsA(isA<ProcedureCancelled>()),
        );
      });

      test('engine running blocks writes in preflight', () async {
        final (s, bike) = await open(id);
        bike.engineRunning = true;
        final kombi = s.profile.ecu('kombi')!;
        final pre = await Preflight(s).forProcedure(kombi, kombi.procedures.first);
        expect(pre.blocked, isTrue);
      });

      test('exhaust flap: actuator test drives the servo and frees a sticky flap', () async {
        final (s, bike) = await open(id);
        final eng = s.profile.ecu('engine')!;
        final proc = eng.procedures.firstWhere((p) => p.id == 'exhaust_flap_test');
        expect(bike.flapFreed, isFalse);
        // Sticky flap can't reach full open before the test.
        bike.flapCommandPct = 100;
        expect(bike.flapActualPct, lessThan(60));
        expect(bike.flapServoCurrent, greaterThan(1.0));
        bike.flapCommandPct = null;
        await ProcedureRunner(s).run(eng, proc, confirm: (_) async => true);
        // Driving it fully open frees it and returns control to the ECU.
        expect(bike.flapFreed, isTrue);
        expect(bike.flapCommandPct, isNull);
      });

      test('exhaust flap: live position reads back', () async {
        final (s, bike) = await open(id);
        bike.flapFreed = true;
        bike.flapCommandPct = 100;
        final chans = LiveDataService.available(s);
        final actual = chans.firstWhere((c) => c.key == 'engine/flap_actual');
        final current = chans.firstWhere((c) => c.key == 'engine/flap_current');
        expect((await LiveDataService(s).readOnce(actual)).value, closeTo(100, 1));
        expect((await LiveDataService(s).readOnce(current)).value, isNotNull);
      });

      test('exhaust flap: hold open needs track mode, then returns control', () async {
        final (s, bike) = await open(id);
        final eng = s.profile.ecu('engine')!;
        final proc = eng.procedures.firstWhere((p) => p.id == 'exhaust_flap_hold');
        expect(proc.offRoadOnly, isTrue);
        // Blocked without track mode.
        final pre = await Preflight(s).forProcedure(eng, proc);
        expect(pre.blocked, isTrue);
        await expectLater(
          ProcedureRunner(s).run(eng, proc, confirm: (_) async => true, hold: (_) async {}),
          throwsA(isA<StateError>()),
        );
        // With track mode on, the flap is held open, then control is returned.
        s.offRoadMode = true;
        var heldOpenDuringHold = false;
        await ProcedureRunner(s).run(eng, proc, confirm: (_) async => true, hold: (_) async {
          heldOpenDuringHold = bike.flapCommandPct == 100;
        });
        expect(heldOpenDuringHold, isTrue);
        expect(bike.flapCommandPct, isNull, reason: 'control returned to the ECU');
      });
    });
  }

  group('licensing', () {
    test('free tier reads faults but cannot clear or code', () async {
      final (s, _) = await open('sim-can', tier: Tier.free);
      final faults = await FaultService(s).readAll();
      expect(faults, isNotEmpty);
      await expectLater(FaultService(s).clear(s.profile.ecu('abs')!), throwsA(isA<FeatureLockedException>()));
      await expectLater(CodingEngine(s, MemoryBackupStore()).plan({('zfe', 'tpms'): 0}),
          throwsA(isA<FeatureLockedException>()));
      final chans = LiveDataService.available(s);
      expect(chans.every((c) => c.def.basic), isTrue);
      expect(LiveDataService.lockedChannels(s), isNotEmpty);
    });

    test('plus tier can reset service but not run adaptations', () async {
      final (s, _) = await open('sim-can', tier: Tier.plus);
      final eng = s.profile.ecu('engine')!;
      await expectLater(
        ProcedureRunner(s).run(eng, eng.procedures.first, confirm: yes),
        throwsA(isA<FeatureLockedException>()),
      );
      final pre = await Preflight(s).forProcedure(eng, eng.procedures.first);
      expect(pre.blocked, isTrue);
    });
  });

  group('safety', () {
    test('clone adapter blocks service reset in preflight', () async {
      final (s, _) = await open('sim-can', adapter: SimAdapter.clone);
      final kombi = s.profile.ecu('kombi')!;
      final pre = await Preflight(s).forProcedure(kombi, kombi.procedures.first);
      expect(pre.blocked, isTrue);
      expect(pre.checks.firstWhere((c) => c.label == 'Adapter').state, CheckState.fail);
    });

    test('low battery blocks writes', () async {
      final (s, bike) = await open('sim-can');
      bike.restingVoltage = 11.4;
      final kombi = s.profile.ecu('kombi')!;
      final pre = await Preflight(s).forProcedure(kombi, kombi.procedures.first);
      expect(pre.checks.firstWhere((c) => c.label == 'Battery').state, CheckState.fail);
    });

    test('writes to unverified real-bike profiles are refused without expert mode', () async {
      final profile = repo.byId('bmw-can')!;
      final engine = profile.ecu('engine')!;
      final bike = VirtualBike();
      final elm = Elm327Adapter(SimulatedTransport(bike, latency: Duration.zero));
      await elm.initialize();
      final s = DiagnosticSession(adapter: elm, profile: profile, tier: () => Tier.pro);
      expect(s.writesAllowed(engine), isFalse);
      s.expertMode = true;
      expect(s.writesAllowed(engine), isTrue);
    });

    test('discovery console blocks programming services', () async {
      final (s, _) = await open('sim-can');
      final d = DiscoveryService(s);
      final r = await d.console('34 00 44', const BusTarget(AddressingMode.canExtended, 0x12));
      expect(r, contains('blocked'));
    });
  });

  group('discovery', () {
    test('finds ECUs on CAN and reads identifiers', () async {
      final (s, _) = await open('sim-can');
      final d = DiscoveryService(s);
      final found = await d.sweep(AddressingMode.canExtended, [0x10, 0x12, 0x29, 0x30, 0x60]).where((e) => e.$2 != null).toList();
      expect(found.map((e) => e.$1), [0x12, 0x29, 0x60]);
      expect(found.first.$2!.vin, VirtualBike.vin);
      final hits = await d
          .scanIdentifiers(const BusTarget(AddressingMode.canExtended, 0x12), List.generate(10, (i) => 0x4000 + i))
          .where((e) => e.$2 != null)
          .toList();
      // 0x4001..0x4009 answer (engine live values incl. exhaust flap position).
      expect(hits.length, 9);
    });

    test('finds ECUs on K-line', () async {
      final (s, _) = await open('sim-kline');
      final found = await DiscoveryService(s).sweep(AddressingMode.kLine, [0x11, 0x12, 0x60]).where((e) => e.$2 != null).toList();
      expect(found.map((e) => e.$1), [0x12, 0x60]);
    });
  });

  test('health report lists faults', () async {
    final (s, _) = await open('sim-can');
    final faults = await FaultService(s).readAll();
    final r = HealthReport.build(s, faults: faults, now: DateTime(2026, 10, 16));
    expect(r, contains(VirtualBike.vin));
    expect(r, contains('5E2101'));
    expect(r, contains('P0171'));
  });

  test('templates encode dates and inputs', () {
    final t = DataTemplate('{due.dd|bcd8}{due.mm|bcd8}{due.yyyy|bcd16}{input.km|u24}AA');
    expect(t.render(now: DateTime(2026, 1, 31), inputs: {'months': 1, 'km': 10000}),
        [0x28, 0x02, 0x20, 0x26, 0x00, 0x27, 0x10, 0xAA]);
  });

  test('value encodings', () {
    expect(ValueEncoding(type: 's', length: 1).decodeNumber([0xFF]), -1);
    expect(ValueEncoding(mask: 0x06).decodeNumber([0x04]), 2);
    expect(ValueEncoding(type: 'date', length: 4).decodeText([0x14, 0x03, 0x20, 0x26]), '14.03.2026');
  });
}
