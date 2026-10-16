import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'tier.dart';

/// An offline licence: `base64url(json payload).base64url(Ed25519 signature)`.
///
/// Used for workshop and direct sales. Tokens are created with
/// `dart run tool/license_tool.dart sign …` using the private key, which never
/// ships with the app; the app only holds the public key.
class LicenseToken {
  LicenseToken({
    required this.id,
    required this.tier,
    required this.holder,
    required this.issued,
    this.expires,
    this.vins = const [],
  });

  factory LicenseToken.fromPayload(Map<String, dynamic> j) => LicenseToken(
        id: j['id'],
        tier: Tier.values.byName(j['tier']),
        holder: j['holder'] ?? '',
        issued: DateTime.parse(j['issued']),
        expires: j['expires'] == null ? null : DateTime.parse(j['expires']),
        vins: (j['vins'] as List? ?? const []).cast<String>(),
      );

  final String id;
  final Tier tier;
  final String holder;
  final DateTime issued;
  final DateTime? expires;

  /// When non-empty the licence only works with these bikes.
  final List<String> vins;

  Map<String, dynamic> toPayload() => {
        'v': 1,
        'id': id,
        'tier': tier.name,
        'holder': holder,
        'issued': issued.toUtc().toIso8601String(),
        if (expires != null) 'expires': expires!.toUtc().toIso8601String(),
        if (vins.isNotEmpty) 'vins': vins,
      };

  bool isExpired(DateTime now) => expires != null && now.isAfter(expires!);
}

class InvalidLicense implements Exception {
  InvalidLicense(this.message);
  final String message;
  @override
  String toString() => message;
}

class LicenseCodec {
  LicenseCodec(this.publicKey);

  /// Raw 32-byte Ed25519 public key.
  final List<int> publicKey;
  static final _alg = Ed25519();

  static String _b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');
  static List<int> _unb64(String s) => base64Url.decode(base64Url.normalize(s));

  Future<LicenseToken> verify(String token, {DateTime? now}) async {
    final parts = token.trim().split('.');
    if (parts.length != 2) throw InvalidLicense('This is not a RideScope licence key');
    final List<int> payload;
    final List<int> sig;
    try {
      payload = _unb64(parts[0]);
      sig = _unb64(parts[1]);
    } on FormatException {
      throw InvalidLicense('This is not a RideScope licence key');
    }
    final ok = await _alg.verify(
      payload,
      signature: Signature(sig, publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519)),
    );
    if (!ok) throw InvalidLicense('The licence key is not valid');
    final LicenseToken t;
    try {
      t = LicenseToken.fromPayload(jsonDecode(utf8.decode(payload)));
    } catch (_) {
      throw InvalidLicense('The licence key is damaged');
    }
    if (t.isExpired(now ?? DateTime.now())) throw InvalidLicense('The licence expired on ${t.expires}');
    return t;
  }

  /// Signs a licence. Only used by the licence tool and tests.
  static Future<String> sign(LicenseToken t, SimpleKeyPair keyPair) async {
    final payload = utf8.encode(jsonEncode(t.toPayload()));
    final sig = await _alg.sign(payload, keyPair: keyPair);
    return '${_b64(payload)}.${_b64(sig.bytes)}';
  }
}
