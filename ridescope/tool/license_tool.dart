// Creates signing keys and licence keys for RideScope.
//
//   dart run tool/license_tool.dart keygen
//       Prints a new private seed (keep it secret, never commit it) and the
//       public key to paste into lib/licensing/license_keys.dart.
//
//   dart run tool/license_tool.dart sign --seed <base64> --tier pro \
//       --holder "Workshop name" [--vin WB10...] [--days 365]
//       Prints a licence key the customer pastes into Settings › Licence.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:ridescope/licensing/license_token.dart';
import 'package:ridescope/licensing/tier.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) return _usage();
  final alg = Ed25519();
  switch (args.first) {
    case 'keygen':
      final seed = List<int>.generate(32, (_) => Random.secure().nextInt(256));
      final kp = await alg.newKeyPairFromSeed(seed);
      final pub = await kp.extractPublicKey();
      stdout.writeln('Private seed (keep secret): ${base64.encode(seed)}');
      stdout.writeln('Public key for license_keys.dart: ${base64.encode(pub.bytes)}');
      break;
    case 'sign':
      final opts = _parse(args.skip(1).toList());
      final seed = opts['seed'];
      final tier = opts['tier'];
      if (seed == null || tier == null) return _usage();
      final kp = await alg.newKeyPairFromSeed(base64.decode(seed));
      final now = DateTime.now().toUtc();
      final days = int.tryParse(opts['days'] ?? '');
      final token = LicenseToken(
        id: 'L${now.millisecondsSinceEpoch.toRadixString(36).toUpperCase()}',
        tier: Tier.values.byName(tier),
        holder: opts['holder'] ?? '',
        issued: now,
        expires: days == null ? null : now.add(Duration(days: days)),
        vins: opts['vin'] == null ? const [] : opts['vin']!.split(','),
      );
      stdout.writeln(await LicenseCodec.sign(token, kp));
      break;
    default:
      _usage();
  }
}

Map<String, String> _parse(List<String> a) {
  final out = <String, String>{};
  for (var i = 0; i + 1 < a.length; i += 2) {
    out[a[i].replaceFirst('--', '')] = a[i + 1];
  }
  return out;
}

void _usage() {
  stderr.writeln('usage: license_tool.dart keygen | sign --seed <b64> --tier free|plus|pro '
      '[--holder name] [--vin VIN[,VIN]] [--days N]');
  exitCode = 64;
}
