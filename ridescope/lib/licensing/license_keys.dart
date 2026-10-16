import 'dart:convert';

/// Ed25519 public key that licence keys are checked against.
///
/// This is a placeholder whose private key was discarded, so no licence
/// keys can be issued for it. Before release, run
/// `dart run tool/license_tool.dart keygen`, keep the private seed somewhere
/// safe (not in git) and paste the public key here.
const String licensePublicKeyBase64 = 'Ee7l3MW926qUfSvtjeCS2bMw0k+Rrkk7K1yy4oHOTKU=';

List<int> get licensePublicKey => base64.decode(licensePublicKeyBase64);

/// Store product ids (configure the same ids in Google Play Console and App
/// Store Connect as non-consumable products).
const String productPlus = 'ridescope_plus';
const String productPro = 'ridescope_pro';
const String productPlusToPro = 'ridescope_plus_to_pro';
