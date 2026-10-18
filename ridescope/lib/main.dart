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
import 'ui/widgets/common.dart';

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
  Widget build(BuildContext context) {
    final mode = context.select<AppState, ThemeMode>((s) => s.appearance.mode);
    return MaterialApp(
      title: 'RideScope',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      home: const _Root(),
    );
  }
}

class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final connected = app.connected && !app.connecting;
    // The dashboard is a root view (not a pushed route), so the system back
    // gesture would otherwise pop the app's only route and quit. Intercept it:
    // back on the dashboard disconnects and returns to Home instead.
    return PopScope(
      canPop: !connected,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !connected) return;
        final leave = app.isDemo ||
            await confirmDialog(
              context,
              'Disconnect?',
              'This ends the session with ${app.session?.profile.name ?? 'your bike'}.',
              ok: 'Disconnect',
              cancel: 'Stay connected',
            );
        if (leave) await app.disconnect();
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(anim),
            child: child,
          ),
        ),
        child: connected
            ? const DashboardScreen(key: ValueKey('dashboard'))
            : const HomeScreen(key: ValueKey('home')),
      ),
    );
  }
}
