import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ridescope/core/adapter/elm327.dart';
import 'package:ridescope/core/adapter/isotp.dart';
import 'package:ridescope/core/protocol/diag_client.dart';
import 'package:ridescope/core/protocol/kwp2000.dart';
import 'package:ridescope/core/protocol/obd2.dart';
import 'package:ridescope/core/protocol/uds.dart';
import 'package:ridescope/core/sim/sim_transport.dart';
import 'package:ridescope/core/sim/virtual_bike.dart';
import 'package:ridescope/core/sim/virtual_ecu.dart';

Future<(Elm327Adapter, VirtualBike)> connect(SimBus bus, {SimAdapter adapter = SimAdapter.stn}) async {
  final bike = VirtualBike(bus: bus);
  final elm = Elm327Adapter(SimulatedTransport(bike, adapter: adapter, latency: Duration.zero));
  await elm.initialize();
  return (elm, bike);
}

void main() {
  group('ISO-TP', () {
    test('segments and reassembles with extended addressing', () {
      final payload = List<int>.generate(40, (i) => i);
      final frames = segmentIsoTp(payload, extAddress: 0xF1);
      expect(frames.length, greaterThan(1));
      final asm = IsoTpAssembler(extendedAddressing: true);
      for (final f in frames) {
        asm.addFrame(0x612, f);
      }
      expect(asm.completed.single.data, payload);
      expect(asm.completed.single.extAddress, 0xF1);
    });

    test('drops a sequence with a missing frame', () {
      final frames = segmentIsoTp(List<int>.generate(30, (i) => i));
      final asm = IsoTpAssembler(extendedAddressing: false);
      asm.addFrame(0x7E8, frames[0]);
      asm.addFrame(0x7E8, frames[2]);
      expect(asm.completed, isEmpty);
    });
  });

  group('adapter detection', () {
    test('identifies an STN adapter', () async {
      final (elm, _) = await connect(SimBus.can);
      expect(elm.info!.family, AdapterFamily.stn);
      expect(elm.info!.canSendLongMessages, isTrue);
      expect(elm.info!.voltage, closeTo(12.6, 0.01));
    });

    test('flags a v1.5 clone', () async {
      final (elm, _) = await connect(SimBus.can, adapter: SimAdapter.clone);
      expect(elm.info!.family, AdapterFamily.clone);
      expect(elm.info!.canSendLongMessages, isFalse);
    });
  });

  group('UDS over CAN', () {
    test('reads a multi-frame VIN', () async {
      final (elm, _) = await connect(SimBus.can);
      final uds = UdsClient(elm, const BusTarget(AddressingMode.canExtended, 0x12));
      expect(ascii.decode(await uds.readData(0xF190)), VirtualBike.vin);
    });

    test('reads and clears faults', () async {
      final (elm, _) = await connect(SimBus.can);
      final uds = UdsClient(elm, const BusTarget(AddressingMode.canExtended, 0x29));
      final dtcs = await uds.readDtcs();
      expect(dtcs.single.hexCode, '5E2101');
      expect(dtcs.single.state, DtcState.active);
      await uds.clearDtcs();
      expect(await uds.readDtcs(), isEmpty);
    });

    test('negative responses become exceptions', () async {
      final (elm, _) = await connect(SimBus.can);
      final uds = UdsClient(elm, const BusTarget(AddressingMode.canExtended, 0x60));
      await expectLater(
        uds.writeData(0x3000, List.filled(8, 0)),
        throwsA(isA<NegativeResponseException>().having((e) => e.code, 'code', 0x7F)),
      );
    });

    test('security access unlocks protected writes', () async {
      final (elm, bike) = await connect(SimBus.can);
      final uds = UdsClient(elm, const BusTarget(AddressingMode.canExtended, 0x60));
      await uds.startSession(0x03);
      await uds.securityAccess(1, VirtualEcu.simKey);
      await uds.writeData(0x3000, [1, 1, 0, 0, 0, 0, 0, 0]);
      expect(bike.ecus[0x60]!.writable[0x3000]!.first, 1);
    });

    test('long writes fail cleanly on a clone adapter', () async {
      final (elm, _) = await connect(SimBus.can, adapter: SimAdapter.clone);
      final uds = UdsClient(elm, const BusTarget(AddressingMode.canExtended, 0x60));
      await expectLater(uds.writeData(0x5001, [0x01, 0x02, 0x20, 0x26]),
          throwsA(isA<AdapterLimitException>()));
    });

    test('silent address gives NoResponse', () async {
      final (elm, _) = await connect(SimBus.can);
      final uds = UdsClient(elm, const BusTarget(AddressingMode.canExtended, 0x77));
      await expectLater(uds.testerPresent(), throwsA(isA<NoResponseException>()));
    });
  });

  group('KWP2000 over K-line', () {
    test('reads identification and DTCs', () async {
      final (elm, _) = await connect(SimBus.kLine);
      final kwp = Kwp2000Client(elm, const BusTarget(AddressingMode.kLine, 0x12));
      expect(ascii.decode(await kwp.readIdentification(0x90)), VirtualBike.vin);
      final dtcs = await kwp.readDtcs();
      expect(dtcs.single.hexCode, '2A94');
      final ff = await kwp.readFreezeFrame(dtcs.single);
      expect(ff!.raw, isNotEmpty);
    });

    test('switches between ECUs', () async {
      final (elm, _) = await connect(SimBus.kLine);
      final engine = Kwp2000Client(elm, const BusTarget(AddressingMode.kLine, 0x12));
      final abs = Kwp2000Client(elm, const BusTarget(AddressingMode.kLine, 0x29));
      expect(await engine.readData(0x06), [0]);
      expect((await abs.readDtcs()).single.hexCode, '5E21');
      expect(ascii.decode(await engine.readIdentification(0x87)), '8 569 123');
    });

    test('missing ECU fails fast init', () async {
      final (elm, _) = await connect(SimBus.kLine);
      final kwp = Kwp2000Client(elm, const BusTarget(AddressingMode.kLine, 0x55));
      await expectLater(kwp.testerPresent(), throwsA(isA<AdapterException>()));
    });
  });

  group('OBD-II', () {
    test('reads supported PIDs, RPM and VIN', () async {
      final (elm, bike) = await connect(SimBus.can);
      bike.engineRunning = true;
      final obd = ObdClient(elm);
      final pids = await obd.supportedPids();
      expect(pids, containsAll([0x0C, 0x05, 0x42, 0x5C]));
      final rpm = await obd.readPid(0x0C);
      expect(((rpm![0] << 8) | rpm[1]) / 4, greaterThan(1000));
      expect(await obd.readVin(), VirtualBike.vin);
      expect(formatObdDtc((await obd.readDtcs()).single.code), 'P0171');
    });
  });
}
