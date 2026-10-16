import 'dart:convert';

import 'profile.dart';

/// Loads the built-in profiles and any profiles the user imported or built
/// with Discovery.
class ProfileRepository {
  ProfileRepository(this._loadAsset);

  final Future<String> Function(String path) _loadAsset;

  static const builtIn = [
    'assets/profiles/bmw_can.json',
    'assets/profiles/bmw_kline.json',
    'assets/profiles/sim_can.json',
    'assets/profiles/sim_kline.json',
  ];

  final List<BikeProfile> _profiles = [];
  final Map<String, String> _userSources = {};

  List<BikeProfile> get all => List.unmodifiable(_profiles);
  List<BikeProfile> get real => _profiles.where((p) => !p.simulator).toList();
  List<BikeProfile> get demos => _profiles.where((p) => p.simulator).toList();
  Map<String, String> get userSources => Map.unmodifiable(_userSources);

  Future<void> load({Map<String, String> userProfiles = const {}}) async {
    _profiles.clear();
    for (final path in builtIn) {
      _profiles.add(BikeProfile.parse(await _loadAsset(path)));
    }
    for (final src in userProfiles.values) {
      addUserProfile(src);
    }
  }

  BikeProfile? byId(String id) {
    for (final p in _profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Adds or replaces a user profile from JSON. Throws [FormatException] on
  /// invalid input.
  BikeProfile addUserProfile(String source) {
    final BikeProfile p;
    try {
      p = BikeProfile.fromJson(jsonDecode(source) as Map<String, dynamic>);
    } catch (e) {
      throw FormatException('Not a valid RideScope profile: $e');
    }
    if (p.simulator) throw const FormatException('Imported profiles cannot be demo profiles');
    _profiles.removeWhere((x) => x.id == p.id);
    _profiles.add(p);
    _userSources[p.id] = source;
    return p;
  }

  /// Adds a user-defined live value to an ECU of a profile (from Discovery).
  /// Returns the updated JSON source to persist.
  String addLiveValue(String profileId, String ecuId, LiveValueDef v, {required String Function(String) baseSource}) {
    final src = _userSources[profileId] ?? baseSource(profileId);
    final j = jsonDecode(src) as Map<String, dynamic>;
    final base = j['id'] as String;
    if (!_userSources.containsKey(profileId)) {
      j['id'] = '$base-custom';
      j['name'] = '${j['name']} (custom)';
    }
    final ecus = (j['ecus'] as List).cast<Map<String, dynamic>>();
    final ecu = ecus.firstWhere((e) => e['id'] == ecuId);
    final list = (ecu['liveData'] as List? ?? []).cast<Map<String, dynamic>>()
      ..removeWhere((x) => x['id'] == v.id)
      ..add(v.toJson());
    ecu['liveData'] = list;
    final out = const JsonEncoder.withIndent('  ').convert(j);
    addUserProfile(out);
    return out;
  }
}
