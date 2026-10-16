import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'license_keys.dart';
import 'license_service.dart';
import 'tier.dart';

/// Google Play / App Store purchases of Plus and Pro.
///
/// Purchases are trusted on the device here. Before a public release, send
/// `purchase.verificationData` to a small backend for receipt validation
/// and only then call [LicenseService.setStoreTier].
class PurchaseService extends ChangeNotifier {
  PurchaseService(this._license);

  final LicenseService _license;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool available = false;
  bool busy = false;
  String? error;
  final Map<String, ProductDetails> products = {};

  static const _ids = {productPlus, productPro, productPlusToPro};

  static bool get supportedPlatform =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> init() async {
    if (!supportedPlatform) return;
    final iap = InAppPurchase.instance;
    try {
      available = await iap.isAvailable();
    } catch (_) {
      available = false;
    }
    if (!available) {
      notifyListeners();
      return;
    }
    _sub = iap.purchaseStream.listen(_onPurchases, onError: (Object e) {
      error = '$e';
      busy = false;
      notifyListeners();
    });
    final r = await iap.queryProductDetails(_ids);
    for (final p in r.productDetails) {
      products[p.id] = p;
    }
    notifyListeners();
  }

  String? priceFor(Tier t) {
    final id = t == Tier.plus ? productPlus : productPro;
    if (t == Tier.pro && _license.storeTier == Tier.plus && products.containsKey(productPlusToPro)) {
      return products[productPlusToPro]!.price;
    }
    return products[id]?.price;
  }

  Future<void> buy(Tier t) async {
    if (!available) {
      error = 'In-app purchases are not available on this device.';
      notifyListeners();
      return;
    }
    final id = t == Tier.plus
        ? productPlus
        : (_license.storeTier == Tier.plus && products.containsKey(productPlusToPro) ? productPlusToPro : productPro);
    final p = products[id];
    if (p == null) {
      error = 'This product is not available in the store yet.';
      notifyListeners();
      return;
    }
    busy = true;
    error = null;
    notifyListeners();
    await InAppPurchase.instance.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: p));
  }

  Future<void> restore() async {
    if (!available) return;
    busy = true;
    notifyListeners();
    await InAppPurchase.instance.restorePurchases();
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
        final t = p.productID == productPlus ? Tier.plus : Tier.pro;
        if (t.index > _license.storeTier.index) await _license.setStoreTier(t);
      } else if (p.status == PurchaseStatus.error) {
        error = p.error?.message ?? 'Purchase failed';
      }
      if (p.pendingCompletePurchase) await InAppPurchase.instance.completePurchase(p);
      if (p.status != PurchaseStatus.pending) busy = false;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
