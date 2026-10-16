import 'dart:convert';

import '../licensing/license_service.dart';

/// A bike RideScope has connected to before.
class GarageBike {
  GarageBike({
    required this.vin,
    required this.profileId,
    required this.profileName,
    required this.lastConnected,
    this.nickname,
    this.faultCount,
    this.serviceDue,
  });

  factory GarageBike.fromJson(Map<String, dynamic> j) => GarageBike(
        vin: j['vin'],
        profileId: j['profileId'],
        profileName: j['profileName'],
        lastConnected: DateTime.parse(j['lastConnected']),
        nickname: j['nickname'],
        faultCount: j['faultCount'],
        serviceDue: j['serviceDue'],
      );

  final String vin;
  final String profileId;
  final String profileName;
  final DateTime lastConnected;
  final String? nickname;
  final int? faultCount;
  final String? serviceDue;

  String get title => nickname ?? profileName;

  GarageBike copyWith({DateTime? lastConnected, String? nickname, int? faultCount, String? serviceDue, String? profileName}) =>
      GarageBike(
        vin: vin,
        profileId: profileId,
        profileName: profileName ?? this.profileName,
        lastConnected: lastConnected ?? this.lastConnected,
        nickname: nickname ?? this.nickname,
        faultCount: faultCount ?? this.faultCount,
        serviceDue: serviceDue ?? this.serviceDue,
      );

  Map<String, dynamic> toJson() => {
        'vin': vin,
        'profileId': profileId,
        'profileName': profileName,
        'lastConnected': lastConnected.toIso8601String(),
        if (nickname != null) 'nickname': nickname,
        if (faultCount != null) 'faultCount': faultCount,
        if (serviceDue != null) 'serviceDue': serviceDue,
      };
}

class Garage {
  Garage(this._kv);
  final KeyValueStore _kv;
  static const _key = 'garage.bikes';

  List<GarageBike> get bikes {
    final list = _kv
        .getStringList(_key)
        .map((s) => GarageBike.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
    list.sort((a, b) => b.lastConnected.compareTo(a.lastConnected));
    return list;
  }

  GarageBike? byVin(String vin) => bikes.where((b) => b.vin == vin).firstOrNull;

  Future<void> upsert(GarageBike bike) async {
    final others = bikes.where((b) => b.vin != bike.vin);
    await _kv.setStringList(_key, [...others, bike].map((b) => jsonEncode(b.toJson())).toList());
  }

  Future<void> remove(String vin) async {
    await _kv.setStringList(
        _key, bikes.where((b) => b.vin != vin).map((b) => jsonEncode(b.toJson())).toList());
  }
}
