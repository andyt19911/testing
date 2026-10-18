import 'package:flutter/foundation.dart';

import 'license_token.dart';
import 'tier.dart';

/// Set with `--dart-define=RIDESCOPE_TESTER=true` for builds handed to
/// testers: allows unlocking paid tiers on the device, like debug builds.
/// Never set it for store builds.
const bool testerBuild = bool.fromEnvironment('RIDESCOPE_TESTER');

/// Whether the developer tier unlock is available in this build.
bool get developerUnlockAvailable => kDebugMode || testerBuild;

/// Minimal key-value persistence, so the service can be tested without
/// platform plugins.
abstract class KeyValueStore {
  String? getString(String key);
  Future<void> setString(String key, String value);
  List<String> getStringList(String key);
  Future<void> setStringList(String key, List<String> value);
  Future<void> remove(String key);
}

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, Object> _m = {};
  @override
  String? getString(String key) => _m[key] as String?;
  @override
  Future<void> setString(String key, String value) async => _m[key] = value;
  @override
  List<String> getStringList(String key) => (_m[key] as List<String>?) ?? [];
  @override
  Future<void> setStringList(String key, List<String> value) async => _m[key] = value;
  @override
  Future<void> remove(String key) async => _m.remove(key);
}

/// Works out the effective tier from store purchases and licence keys, and
/// enforces the per-tier bike (VIN) limit.
class LicenseService extends ChangeNotifier {
  LicenseService(this._store, this._codec, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final KeyValueStore _store;
  final LicenseCodec _codec;
  final DateTime Function() _clock;

  static const _kToken = 'license.token';
  static const _kStoreTier = 'license.storeTier';
  static const _kVins = 'license.vins';
  static const _kLastRemoval = 'license.lastVinRemoval';
  static const _kDemoTier = 'license.demoTier';

  /// How often a bike can be removed from the licence to make room for another.
  static const vinSwapCooldown = Duration(days: 30);

  LicenseToken? _token;
  Tier _storeTier = Tier.free;
  Tier _devTier = Tier.free;
  Tier demoTier = Tier.pro;

  LicenseToken? get token => _token;
  Tier get storeTier => _storeTier;

  /// Tier bought or licensed, before the per-bike limit.
  Tier get tier {
    var t = _storeTier;
    if (_token != null && !_token!.isExpired(_clock()) && _token!.tier.index > t.index) t = _token!.tier;
    if (_devTier.index > t.index) t = _devTier;
    return t;
  }

  List<String> get registeredVins => _store.getStringList(_kVins);

  Future<void> load() async {
    final raw = _store.getString(_kToken);
    if (raw != null) {
      try {
        _token = await _codec.verify(raw, now: _clock());
      } on InvalidLicense {
        _token = null;
      }
    }
    final st = _store.getString(_kStoreTier);
    if (st != null) _storeTier = Tier.values.byName(st);
    final dt = _store.getString(_kDemoTier);
    if (dt != null) demoTier = Tier.values.byName(dt);
    notifyListeners();
  }

  /// Applies a licence key typed or pasted by the user.
  Future<LicenseToken> applyToken(String raw) async {
    final t = await _codec.verify(raw, now: _clock());
    _token = t;
    await _store.setString(_kToken, raw.trim());
    notifyListeners();
    return t;
  }

  Future<void> removeToken() async {
    _token = null;
    await _store.remove(_kToken);
    notifyListeners();
  }

  /// Called by the purchase service after a verified store purchase/restore.
  Future<void> setStoreTier(Tier t) async {
    _storeTier = t;
    await _store.setString(_kStoreTier, t.name);
    notifyListeners();
  }

  Future<void> setDemoTier(Tier t) async {
    demoTier = t;
    await _store.setString(_kDemoTier, t.name);
    notifyListeners();
  }

  /// Debug and tester builds only: lets developers test paid features on a
  /// real bike.
  void setDeveloperTier(Tier t) {
    if (!developerUnlockAvailable) return;
    _devTier = t;
    notifyListeners();
  }

  /// Tier that applies to a particular bike. Bikes beyond the tier's limit,
  /// or not listed in a VIN-locked licence key, fall back to Free.
  Tier tierForVin(String? vin) {
    final t = tier;
    if (vin == null || t == Tier.free) return t;
    if (_token != null && _token!.tier == t && _token!.vins.isNotEmpty && !_token!.vins.contains(vin)) {
      return _storeTier.index >= _devTier.index ? _storeTier : _devTier;
    }
    final max = t.maxBikes;
    if (max == null) return t;
    final vins = registeredVins;
    if (vins.contains(vin) || vins.length < max) return t;
    return Tier.free;
  }

  /// Records a bike against the licence (on first successful connection).
  Future<bool> registerVin(String vin) async {
    final vins = registeredVins;
    if (vins.contains(vin)) return true;
    final max = tier.maxBikes;
    if (max != null && vins.length >= max) return false;
    await _store.setStringList(_kVins, [...vins, vin]);
    notifyListeners();
    return true;
  }

  DateTime? get nextVinRemovalAllowed {
    final last = _store.getString(_kLastRemoval);
    if (last == null) return null;
    final next = DateTime.parse(last).add(vinSwapCooldown);
    return next.isAfter(_clock()) ? next : null;
  }

  /// Frees a bike slot. Limited to once per [vinSwapCooldown].
  Future<void> removeVin(String vin) async {
    final next = nextVinRemovalAllowed;
    if (next != null) {
      throw StateError('You can remove another bike after ${next.toLocal().toString().substring(0, 10)}');
    }
    await _store.setStringList(_kVins, registeredVins.where((v) => v != vin).toList());
    await _store.setString(_kLastRemoval, _clock().toIso8601String());
    notifyListeners();
  }
}
