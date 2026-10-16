import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/backup_store.dart';
import '../licensing/license_service.dart';

class PrefsKeyValueStore implements KeyValueStore {
  PrefsKeyValueStore(this._p);
  final SharedPreferences _p;

  @override
  String? getString(String key) => _p.getString(key);
  @override
  Future<void> setString(String key, String value) => _p.setString(key, value);
  @override
  List<String> getStringList(String key) => _p.getStringList(key) ?? [];
  @override
  Future<void> setStringList(String key, List<String> value) => _p.setStringList(key, value);
  @override
  Future<void> remove(String key) => _p.remove(key);
}

/// Coding backups kept on the device. They are also included in the
/// exported diagnostics bundle so they survive a phone change.
class PrefsBackupStore implements BackupStore {
  PrefsBackupStore(this._kv);
  final KeyValueStore _kv;
  static const _key = 'coding.backups';

  List<CodingBackup> _all() => _kv
      .getStringList(_key)
      .map((s) => CodingBackup.fromJson(jsonDecode(s) as Map<String, dynamic>))
      .toList();

  @override
  Future<void> save(CodingBackup b) =>
      _kv.setStringList(_key, [..._kv.getStringList(_key), jsonEncode(b.toJson())]);

  @override
  Future<List<CodingBackup>> list({String? vin}) async =>
      _all().where((b) => vin == null || b.vin == vin).toList().reversed.toList();

  @override
  Future<void> delete(String id) async => _kv.setStringList(
        _key,
        _all().where((b) => b.id != id).map((b) => jsonEncode(b.toJson())).toList(),
      );
}
