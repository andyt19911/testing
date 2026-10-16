import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_state.dart';
import 'app/garage.dart';
import 'app/prefs_store.dart';
import 'core/ecu/profile_repository.dart';
import 'licensing/license_keys.dart';
import 'licensing/license_service.dart';
import 'licensing/license_token.dart';
import 'licensing/purchase_service.dart';
import 'ui/screens/dashboard_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final kv = PrefsKeyValueStore(prefs);

  final profiles = ProfileRepository(rootBundle.loadString);
  final userProfiles = {
    for (final s in kv.getStringList('profiles.user')) s.hashCode.toString(): s,
  };
  await profiles.load(userProfiles: userProfiles);

  final license = LicenseService(kv, LicenseCodec(licensePublicKey));
  await license.load();
  final purchases = PurchaseService(license);
  await purchases.init();

  final state = AppState(
    profiles: profiles,
    license: license,
    purchases: purchases,
    kv: kv,
    backups: PrefsBackupStore(kv),
    garage: Garage(kv),
  );
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      ChangeNotifierProvider.value(value: purchases),
    ],
    child: const RideScopeApp(),
  ));
}

class RideScopeApp extends StatelessWidget {
  const RideScopeApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'RideScope',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: const _Root(),
      );
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final connected = context.select<AppState, bool>((s) => s.connected && !s.connecting);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: connected ? const DashboardScreen() : const HomeScreen(),
    );
  }
}
