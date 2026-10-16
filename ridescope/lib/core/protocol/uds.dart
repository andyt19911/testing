import '../util/hex.dart';
import 'diag_client.dart';

/// UDS (ISO 14229) over ISO-TP as used by CAN BMW motorcycles.
class UdsClient extends DiagClient {
  UdsClient(super.adapter, super.target);

  @override
  String get protocolName => 'UDS';

  @override
  int get idWidth => 2;

  List<int> _id(int id) => [(id >> 8) & 0xFF, id & 0xFF];

  @override
  Future<void> startSession(int type) => request([0x10, type]);

  @override
  Future<void> testerPresent() => request([0x3E, 0x00]);

  @override
  Future<List<int>> readIdentification(int id) => readData(id);

  @override
  Future<List<int>> readData(int id) async {
    final r = await request([0x22, ..._id(id)]);
    return r.sublist(3);
  }

  @override
  Future<void> writeData(int id, List<int> data) => request([0x2E, ..._id(id), ...data]);

  @override
  Future<List<int>> routine(int id, {int control = 1, List<int> data = const []}) async {
    final r = await request([0x31, control, ..._id(id), ...data],
        timeout: const Duration(seconds: 8));
    return r.sublist(4);
  }

  @override
  Future<List<int>> ioControl(int id, int parameter, {List<int> data = const []}) async {
    final r = await request([0x2F, ..._id(id), parameter, ...data]);
    return r.sublist(4);
  }

  @override
  Future<List<Dtc>> readDtcs() async {
    // reportDTCByStatusMask, every status bit.
    final r = await request([0x19, 0x02, 0xFF]);
    final out = <Dtc>[];
    for (var o = 3; o + 3 < r.length; o += 4) {
      final status = r[o + 3];
      if (status == 0) continue;
      out.add(Dtc(code: readUnsigned(r, o, 3), status: status, raw: r.sublist(o, o + 3)));
    }
    return out;
  }

  @override
  Future<void> clearDtcs() =>
      request([0x14, 0xFF, 0xFF, 0xFF], timeout: const Duration(seconds: 6));

  @override
  Future<FreezeFrame?> readFreezeFrame(Dtc dtc) async {
    try {
      final r = await request([0x19, 0x04, ...writeUnsigned(dtc.code, 3), 0xFF]);
      // 59 04 DTC(3) status, then snapshot records.
      return FreezeFrame(dtc.code, r.length > 6 ? r.sublist(6) : const []);
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
