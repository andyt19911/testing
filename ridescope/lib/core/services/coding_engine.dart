import '../../licensing/tier.dart';
import '../ecu/profile.dart';
import '../util/hex.dart';
import 'backup_store.dart';
import 'session.dart';

class CodingChange {
  CodingChange(this.ecu, this.block, this.param, this.from, this.to, {this.linkedFrom});
  final EcuDef ecu;
  final CodingBlock block;
  final CodingParam param;
  final int from;
  final int to;

  /// Set when this change was added automatically because of a linked setting.
  final CodingParam? linkedFrom;

  String get fromLabel => param.optionFor(from)?.label ?? '0x${hexWord(from)}';
  String get toLabel => param.optionFor(to)?.label ?? '0x${hexWord(to)}';
}

class BlockWrite {
  BlockWrite(this.ecu, this.block, this.before, this.after);
  final EcuDef ecu;
  final CodingBlock block;
  final List<int> before;
  final List<int> after;
}

class CodingPlan {
  CodingPlan(this.changes, this.writes);
  final List<CodingChange> changes;
  final List<BlockWrite> writes;
  bool get isEmpty => writes.isEmpty;
  List<EcuDef> get ecus => {for (final w in writes) w.ecu}.toList();
}

class CodingWriteFailed implements Exception {
  CodingWriteFailed(this.message, {required this.restored});
  final String message;
  final bool restored;
  @override
  String toString() => restored
      ? '$message. The original coding was restored.'
      : '$message. Restoring the original coding also failed. Use the backup under Coding › History.';
}

/// Reads, changes and writes coding blocks safely:
/// backup → write → read back and compare → roll back on mismatch.
class CodingEngine {
  CodingEngine(this.session, this.backups);
  final DiagnosticSession session;
  final BackupStore backups;

  final Map<String, List<int>> _cache = {};
  String _key(EcuDef e, CodingBlock b) => '${e.id}/${b.id}';

  Future<List<int>> readBlock(EcuDef ecu, CodingBlock block, {bool refresh = false}) async {
    session.require(Feature.coding);
    final k = _key(ecu, block);
    if (!refresh && _cache.containsKey(k)) return _cache[k]!;
    final data = await session.client(ecu).readData(block.ident);
    if (data.length < block.length) {
      throw StateError('${block.name}: expected ${block.length} bytes, got ${data.length}');
    }
    return _cache[k] = data.sublist(0, block.length);
  }

  /// Current value of every parameter in every coding block of [ecu].
  Future<Map<CodingParam, int>> readParams(EcuDef ecu) async {
    final out = <CodingParam, int>{};
    for (final b in ecu.coding) {
      final bytes = await readBlock(ecu, b);
      for (final p in b.params) {
        out[p] = p.read(bytes);
      }
    }
    return out;
  }

  /// Works out every block write needed for [desired] (keyed by ECU id and
  /// parameter id), including linked settings in other ECUs.
  Future<CodingPlan> plan(Map<(String, String), int> desired) async {
    session.require(Feature.coding);
    final all = <(String, String), (int, CodingParam?)>{};
    for (final e in desired.entries) {
      all[e.key] = (e.value, null);
      final ecu = session.profile.ecu(e.key.$1)!;
      final p = ecu.findParam(e.key.$2)!;
      for (final l in p.linked) {
        final mapped = l.valueMap[e.value];
        if (mapped != null && !desired.containsKey((l.ecu, l.param))) {
          all[(l.ecu, l.param)] = (mapped, p);
        }
      }
    }
    final changes = <CodingChange>[];
    final blocks = <String, (EcuDef, CodingBlock, List<int>, List<int>)>{};
    for (final e in all.entries) {
      final ecu = session.profile.ecu(e.key.$1);
      final param = ecu?.findParam(e.key.$2);
      if (ecu == null || param == null) continue;
      if (!(session.status[ecu.id]?.present ?? true)) continue;
      final block = ecu.blockOf(param)!;
      final k = _key(ecu, block);
      if (!blocks.containsKey(k)) {
        final current = await readBlock(ecu, block);
        blocks[k] = (ecu, block, current, current);
      }
      final entry = blocks[k]!;
      final from = param.read(entry.$4);
      if (from == e.value.$1) continue;
      blocks[k] = (ecu, block, entry.$3, param.apply(entry.$4, e.value.$1));
      changes.add(CodingChange(ecu, block, param, from, e.value.$1, linkedFrom: e.value.$2));
    }
    final writes = [
      for (final b in blocks.values)
        if (toHex(b.$3) != toHex(b.$4)) BlockWrite(b.$1, b.$2, b.$3, b.$4),
    ];
    return CodingPlan(changes, writes);
  }

  Future<void> apply(CodingPlan plan, {void Function(String)? onProgress}) async {
    session.require(Feature.coding);
    for (final w in plan.writes) {
      if (!session.writesAllowed(w.ecu)) {
        throw StateError('Coding for ${w.ecu.name} has not been verified on this bike');
      }
    }
    final stamp = DateTime.now();
    for (final w in plan.writes) {
      onProgress?.call('Backing up ${w.ecu.shortName}');
      await backups.save(CodingBackup(
        id: '${stamp.microsecondsSinceEpoch}-${w.ecu.id}-${w.block.id}',
        time: stamp,
        vin: session.vin,
        profileId: session.profile.id,
        ecuId: w.ecu.id,
        blockId: w.block.id,
        ident: w.block.ident,
        bytes: w.before,
        note: plan.changes.where((c) => c.ecu == w.ecu).map((c) => '${c.param.name}: ${c.fromLabel} → ${c.toLabel}').join('; '),
      ));
    }
    final done = <BlockWrite>[];
    for (final w in plan.writes) {
      onProgress?.call('Writing ${w.ecu.shortName}');
      try {
        await _writeVerified(w.ecu, w.block, w.after);
        done.add(w);
      } catch (e) {
        session.log.error('Coding write to ${w.ecu.shortName} failed: $e');
        onProgress?.call('Write failed, restoring');
        var restored = true;
        for (final r in [w, ...done.reversed]) {
          try {
            await _writeVerified(r.ecu, r.block, r.before);
          } catch (_) {
            restored = false;
          }
        }
        throw CodingWriteFailed('Writing ${w.block.name} in ${w.ecu.name} failed ($e)', restored: restored);
      }
    }
    onProgress?.call('Done');
  }

  Future<void> _writeVerified(EcuDef ecu, CodingBlock block, List<int> bytes) async {
    final c = session.client(ecu);
    try {
      await session.prepareForWrite(ecu);
      await c.writeData(block.ident, bytes);
      final back = await c.readData(block.ident);
      _cache.remove(_key(ecu, block));
      if (toHex(back.take(block.length).toList()) != toHex(bytes)) {
        throw StateError('read-back mismatch: wrote ${toHex(bytes)}, read ${toHex(back)}');
      }
      _cache[_key(ecu, block)] = List.of(bytes);
    } finally {
      await session.endWrite(ecu);
    }
  }

  /// Writes a stored backup back to its ECU.
  Future<void> restore(CodingBackup b) async {
    session.require(Feature.coding);
    final ecu = session.profile.ecu(b.ecuId);
    final block = ecu?.coding.where((x) => x.id == b.blockId).firstOrNull;
    if (ecu == null || block == null) throw StateError('Backup does not match this bike profile');
    if (b.vin != null && session.vin != null && b.vin != session.vin) {
      throw StateError('This backup was taken from a different bike (${b.vin})');
    }
    await _writeVerified(ecu, block, b.bytes);
  }
}
