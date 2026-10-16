import 'dart:convert';

import '../util/hex.dart';

/// A copy of a coding block taken before it was changed.
class CodingBackup {
  CodingBackup({
    required this.id,
    required this.time,
    required this.vin,
    required this.profileId,
    required this.ecuId,
    required this.blockId,
    required this.ident,
    required this.bytes,
    this.note = '',
  });

  factory CodingBackup.fromJson(Map<String, dynamic> j) => CodingBackup(
        id: j['id'],
        time: DateTime.parse(j['time']),
        vin: j['vin'],
        profileId: j['profileId'],
        ecuId: j['ecuId'],
        blockId: j['blockId'],
        ident: j['ident'],
        bytes: fromHex(j['bytes']),
        note: j['note'] ?? '',
      );

  final String id;
  final DateTime time;
  final String? vin;
  final String profileId;
  final String ecuId;
  final String blockId;
  final int ident;
  final List<int> bytes;
  final String note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time.toIso8601String(),
        'vin': vin,
        'profileId': profileId,
        'ecuId': ecuId,
        'blockId': blockId,
        'ident': ident,
        'bytes': toHex(bytes, separator: ''),
        'note': note,
      };
}

/// Persists coding backups. The app uses a SharedPreferences-backed
/// implementation; tests use [MemoryBackupStore].
abstract class BackupStore {
  Future<void> save(CodingBackup b);
  Future<List<CodingBackup>> list({String? vin});
  Future<void> delete(String id);
}

class MemoryBackupStore implements BackupStore {
  final List<CodingBackup> _items = [];

  @override
  Future<void> save(CodingBackup b) async => _items.add(b);

  @override
  Future<List<CodingBackup>> list({String? vin}) async =>
      _items.where((b) => vin == null || b.vin == vin).toList().reversed.toList();

  @override
  Future<void> delete(String id) async => _items.removeWhere((b) => b.id == id);

  String exportJson() => jsonEncode(_items.map((b) => b.toJson()).toList());
}
