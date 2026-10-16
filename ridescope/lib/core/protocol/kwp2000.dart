import '../util/hex.dart';
import 'diag_client.dart';

/// KWP2000 (ISO 14230-3) as used by K-line BMW motorcycles.
class Kwp2000Client extends DiagClient {
  Kwp2000Client(super.adapter, super.target);

  @override
  String get protocolName => 'KWP2000';

  @override
  int get idWidth => 1;

  @override
  Future<void> startSession(int type) => request([0x10, type]);

  @override
  Future<void> testerPresent() => request([0x3E, 0x01]);

  @override
  Future<List<int>> readIdentification(int id) async {
    final r = await request([0x1A, id & 0xFF]);
    return r.sublist(2);
  }

  @override
  Future<List<int>> readData(int id) async {
    final r = await request([0x21, id & 0xFF]);
    return r.sublist(2);
  }

  @override
  Future<void> writeData(int id, List<int> data) => request([0x3B, id & 0xFF, ...data]);

  @override
  Future<List<int>> routine(int id, {int control = 1, List<int> data = const []}) async {
    // KWP uses separate services for start (31), stop (32) and results (33).
    final sid = switch (control) { 2 => 0x32, 3 => 0x33, _ => 0x31 };
    final r = await request([sid, id & 0xFF, ...data], timeout: const Duration(seconds: 8));
    return r.sublist(2);
  }

  @override
  Future<List<int>> ioControl(int id, int parameter, {List<int> data = const []}) async {
    final r = await request([0x30, id & 0xFF, parameter, ...data]);
    return r.sublist(2);
  }

  @override
  Future<List<Dtc>> readDtcs() async {
    // readDiagnosticTroubleCodesByStatus, all groups, all statuses.
    final r = await request([0x18, 0x02, 0xFF, 0x00]);
    final count = r.length > 1 ? r[1] : 0;
    final out = <Dtc>[];
    for (var i = 0; i < count && 2 + i * 3 + 2 < r.length; i++) {
      final o = 2 + i * 3;
      out.add(Dtc(code: readUnsigned(r, o, 2), status: r[o + 2], raw: r.sublist(o, o + 2)));
    }
    return out;
  }

  @override
  Future<void> clearDtcs() => request([0x14, 0xFF, 0x00], timeout: const Duration(seconds: 6));

  @override
  Future<FreezeFrame?> readFreezeFrame(Dtc dtc) async {
    try {
      // readStatusOfDiagnosticTroubleCodes returns the environment data that
      // BMW stores with each fault.
      final r = await request([0x17, (dtc.code >> 8) & 0xFF, dtc.code & 0xFF]);
      return FreezeFrame(dtc.code, r.length > 5 ? r.sublist(5) : const []);
    } on NegativeResponseException {
      return null;
    }
  }

  @override
  Future<void> ecuReset({int type = 1}) => request([0x11, type]);

  @override
  Future<void> securityAccess(int level, List<int> Function(List<int> seed) keyFor) async {
    final r = await request([0x27, level]);
    final seed = r.sublist(2);
    if (seed.every((b) => b == 0)) return;
    await request([0x27, level + 1, ...keyFor(seed)]);
  }
}
