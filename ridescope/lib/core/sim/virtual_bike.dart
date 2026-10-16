import 'dart:math';

import '../util/hex.dart';
import 'virtual_ecu.dart';

enum SimBus { can, kLine }

/// A simulated motorcycle with engine, ABS, instrument cluster and central
/// electronics. Its identifiers match `assets/profiles/sim_*.json` exactly so
/// the demo profiles can be marked verified.
class VirtualBike {
  VirtualBike({this.bus = SimBus.can, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now {
    _start = _clock();
    _build();
  }

  final SimBus bus;
  final DateTime Function() _clock;
  late DateTime _start;

  bool engineRunning = false;
  double restingVoltage = 12.6;
  int serviceResets = 0;

  final Map<int, VirtualEcu> ecus = {};

  static const engineAddr = 0x12;
  static const absAddr = 0x29;
  static const zfeAddr = 0x40;
  static const kombiAddr = 0x60;

  static const vin = 'WB10A1100SIM00001';

  SimProtocol get _proto => bus == SimBus.can ? SimProtocol.uds : SimProtocol.kwp;
  bool get _uds => bus == SimBus.can;

  /// Identifier numbering used by the demo profiles: UDS uses 0xXXNN, KWP
  /// the low byte only.
  int ident(int uds) => _uds ? uds : uds & 0xFF;
  int identId(int uds, int kwp) => _uds ? uds : kwp;

  double get _t => _clock().difference(_start).inMilliseconds / 1000.0;

  double get throttle => engineRunning ? (30 * (1 + sin(_t / 3))).clamp(0, 60).toDouble() : 0;
  double get rpm => engineRunning ? 1150 + throttle * 80 : 0;
  double get speed => engineRunning ? throttle * 1.6 : 0;
  int get gear => speed < 1 ? 0 : min(6, 1 + speed ~/ 18);
  double get coolant => engineRunning ? min(92, 38 + _t / 2) : 24;
  double get battery => engineRunning ? 14.1 + sin(_t) * 0.05 : restingVoltage;
  double get lambda => engineRunning ? 1.0 + sin(_t * 2.3) * 0.03 : 0;
  double get odometer => 12873 + _t * speed / 3600;

  List<int> _u8(num v) => [v.round().clamp(0, 255)];
  List<int> _u16(num v) => writeUnsigned(v.round().clamp(0, 65535), 2);

  void _build() {
    final p = _proto;

    // Engine
    final eng = VirtualEcu(address: engineAddr, name: 'Engine', protocol: p);
    _ident(eng, part: '8 569 123', sw: 'BMS 12.04.01', serial: 'E7701234');
    eng.readable[ident(0x4001)] = () => _u16(rpm);
    eng.readable[ident(0x4002)] = () => _u8(coolant + 40);
    eng.readable[ident(0x4003)] = () => _u8(throttle * 2.55);
    eng.readable[ident(0x4004)] = () => _u8(22 + 40 + (engineRunning ? 6 : 0));
    eng.readable[ident(0x4005)] = () => _u16(battery * 1000);
    eng.readable[ident(0x4006)] = () => _u8(gear);
    eng.readable[ident(0x4007)] = () => _u16(lambda * 10000);
    eng.readable[ident(0x4008)] = () => _u8((engineRunning ? coolant + 8 : 24) + 40);
    eng.dtcs[_uds ? 0x2A9400 : 0x2A94] = 0x08;
    eng.freezeFrames[_uds ? 0x2A9400 : 0x2A94] = [0x0F, 0xA0, 0x7A, 0x31];
    eng.routines[ident(0xA001)] = (c, d) => [0x00];
    eng.routines[ident(0xA002)] = (c, d) => gear == 0 ? [0x00] : null;
    eng.engineRunning = () => engineRunning;
    _add(eng);

    // ABS
    final abs = VirtualEcu(address: absAddr, name: 'ABS', protocol: p);
    _ident(abs, part: '8 532 801', sw: 'ABS2 K25 3.1', serial: 'A1100456');
    abs.readable[ident(0x4101)] = () => _u16(speed * 10);
    abs.readable[ident(0x4102)] = () => _u16(speed * 10 + (engineRunning ? 3 : 0));
    abs.readable[ident(0x4103)] = () => _u8(0);
    abs.dtcs[_uds ? 0x5E2101 : 0x5E21] = 0x01;
    abs.freezeFrames[_uds ? 0x5E2101 : 0x5E21] = [0x00, 0x00, 0x7C];
    abs.routines[ident(0xB001)] = (c, d) => engineRunning ? null : [0x00];
    abs.routines[ident(0xB002)] = (c, d) => engineRunning ? null : [0x00];
    abs.ioControls[ident(0xB010)] = (param, d) => engineRunning ? null : [0x00];
    abs.engineRunning = () => engineRunning;
    _add(abs);

    // Central electronics
    final zfe = VirtualEcu(address: zfeAddr, name: 'ZFE', protocol: p);
    _ident(zfe, part: '8 389 777', sw: 'ZFE HIGH 7.2', serial: 'Z5510099');
    zfe.writable[ident(0x3100)] = [0x01, 0x01, 0x00, 0x00, 0x00, 0x00];
    zfe.protectedWrites.add(ident(0x3100));
    zfe.readable[ident(0x4201)] = () => _u8(68 * 2.55);
    zfe.routines[ident(0xC001)] = (c, d) => [0x00];
    zfe.routines[ident(0xC002)] = (c, d) => engineRunning ? null : [0x00];
    zfe.engineRunning = () => engineRunning;
    _add(zfe);

    // Instrument cluster
    final kombi = VirtualEcu(address: kombiAddr, name: 'KOMBI', protocol: p);
    _ident(kombi, part: '8 365 320', sw: 'KOMBI K03 5.0', serial: 'K0301777');
    kombi.writable[ident(0x3000)] = [0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
    kombi.protectedWrites.add(ident(0x3000));
    // Service due: 14 Mar 2026 (BCD), 1 250 km remaining.
    kombi.writable[ident(0x5001)] = [0x14, 0x03, 0x20, 0x26];
    kombi.writable[ident(0x5002)] = writeUnsigned(1250, 3);
    kombi.writable[ident(0x5003)] = [0x01, 0x01, 0x20, 0x24, 0x00, 0x00];
    kombi.readable[ident(0x4310)] = () => writeUnsigned(odometer.round(), 3);
    kombi.routines[ident(0x5100)] = (c, d) {
      serviceResets++;
      return [0x00];
    };
    kombi.engineRunning = () => engineRunning;
    _add(kombi);
  }

  void _ident(VirtualEcu e, {required String part, required String sw, required String serial}) {
    e.readable[identId(0xF190, 0x90)] = () => VirtualEcu.asciiBytes(vin);
    e.readable[identId(0xF187, 0x87)] = () => VirtualEcu.asciiBytes(part);
    e.readable[identId(0xF189, 0x89)] = () => VirtualEcu.asciiBytes(sw);
    e.readable[identId(0xF18C, 0x8C)] = () => VirtualEcu.asciiBytes(serial);
  }

  void _add(VirtualEcu e) => ecus[e.address] = e;

  /// Physical request to one ECU. `null` means the ECU stays silent.
  List<int>? request(int address, List<int> payload) => ecus[address]?.handle(payload);

  // ---- OBD-II (engine only, CAN only) ----

  Map<int, List<int> Function()> get _obdPids => {
        0x04: () => _u8(engineRunning ? 22 * 2.55 : 0),
        0x05: () => _u8(coolant + 40),
        0x0B: () => _u8(engineRunning ? 45 : 101),
        0x0C: () => _u16(rpm * 4),
        0x0D: () => _u8(speed),
        0x0E: () => _u8((engineRunning ? 12 : 0) * 2 + 128),
        0x0F: () => _u8(62),
        0x11: () => _u8(throttle * 2.55),
        0x1F: () => _u16(engineRunning ? _t : 0),
        0x2F: () => _u8(68 * 2.55),
        0x42: () => _u16(battery * 1000),
        0x46: () => _u8(21 + 40),
        0x5C: () => _u8((engineRunning ? coolant + 8 : 24) + 40),
      };

  /// Answers a functional OBD request; returns the engine's reply.
  List<int>? obdRequest(List<int> payload) {
    if (bus != SimBus.can || payload.isEmpty) return null;
    final mode = payload[0];
    if (mode == 0x01 && payload.length >= 2) {
      final pid = payload[1];
      if (pid % 0x20 == 0) {
        var mask = 0;
        final pids = _obdPids.keys.toSet();
        for (var i = 1; i <= 32; i++) {
          if (pids.contains(pid + i) || (i == 32 && pids.any((p) => p > pid + 32))) {
            mask |= 1 << (32 - i);
          }
        }
        if (mask == 0 && pid != 0) return null;
        return [0x41, pid, ...writeUnsigned(mask, 4)];
      }
      final f = _obdPids[pid];
      return f == null ? null : [0x41, pid, ...f()];
    }
    if (mode == 0x03) {
      return [0x43, 0x01, 0x01, 0x71];
    }
    if (mode == 0x04) return [0x44];
    if (mode == 0x09 && payload.length >= 2 && payload[1] == 0x02) {
      return [0x49, 0x02, 0x01, ...VirtualEcu.asciiBytes(vin)];
    }
    return null;
  }
}
