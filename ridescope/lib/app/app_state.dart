import 'package:flutter/foundation.dart';

import '../core/adapter/elm327.dart';
import '../core/ecu/profile.dart';
import '../core/ecu/profile_repository.dart';
import '../core/protocol/diag_client.dart';
import '../core/protocol/obd2.dart';
import '../core/protocol/uds.dart';
import '../core/protocol/kwp2000.dart';
import '../core/services/backup_store.dart';
import '../core/services/coding_engine.dart';
import '../core/services/discovery_service.dart';
import '../core/services/fault_service.dart';
import '../core/services/live_data_service.dart';
import '../core/services/preflight.dart';
import '../core/services/procedure_runner.dart';
import '../core/services/session.dart';
import '../core/sim/sim_transport.dart';
import '../core/sim/virtual_bike.dart';
import '../core/transport/transport.dart';
import '../core/util/diag_log.dart';
import '../licensing/license_service.dart';
import '../licensing/purchase_service.dart';
import '../licensing/tier.dart';
import '../ui/theme.dart' show Appearance;
import 'garage.dart';

enum ConnectStep { link, adapter, bike, units, done }

extension ConnectStepLabel on ConnectStep {
  String get label => switch (this) {
        ConnectStep.link => 'Connecting to the adapter',
        ConnectStep.adapter => 'Checking the adapter',
        ConnectStep.bike => 'Looking for your bike',
        ConnectStep.units => 'Reading control units',
        ConnectStep.done => 'Connected',
      };
}

/// Everything the UI needs: licence, profiles, garage and the live session.
class AppState extends ChangeNotifier {
  AppState({
    required this.profiles,
    required this.license,
    required this.purchases,
    required this.kv,
    required this.backups,
    required this.garage,
  }) {
    license.addListener(notifyListeners);
    _expert = kv.getString('settings.expert') == '1';
    _offRoad = kv.getString('settings.offRoad') == '1';
    _appearance = Appearance.values.asNameMap()[kv.getString('settings.appearance')] ?? Appearance.dark;
  }

  final ProfileRepository profiles;
  final LicenseService license;
  final PurchaseService purchases;
  final KeyValueStore kv;
  final BackupStore backups;
  final Garage garage;

  DiagnosticSession? session;
  VirtualBike? simBike;
  final DiagLog log = DiagLog();

  bool _expert = false;
  bool get expertMode => _expert && tier.includes(Tier.pro);

  bool _offRoad = false;
  bool get offRoadMode => _offRoad && tier.includes(Tier.pro);

  Appearance _appearance = Appearance.dark;
  Appearance get appearance => _appearance;

  Future<void> setAppearance(Appearance a) async {
    _appearance = a;
    await kv.setString('settings.appearance', a.name);
    notifyListeners();
  }

  bool connecting = false;
  ConnectStep? step;
  String? error;

  /// Set when the connected bike is beyond the licence's bike limit.
  bool bikeNotLicensed = false;

  LiveDataService? _live;
  List<EcuFaults>? lastFaults;

  bool get connected => session != null;
  bool get isDemo => session?.profile.simulator ?? false;

  Tier get tier {
    final s = session;
    if (s != null && s.profile.simulator) return license.demoTier;
    return license.tierForVin(s?.vin);
  }

  bool allows(Feature f) => tier.includes(f.minTier);

  FaultService get faults => FaultService(session!);
  LiveDataService get live => _live ??= LiveDataService(session!);
  ProcedureRunner get runner => ProcedureRunner(session!);
  CodingEngine get coding => CodingEngine(session!, backups);
  DiscoveryService get discovery => DiscoveryService(session!);
  Preflight get preflight => Preflight(session!);

  Future<void> setExpertMode(bool v) async {
    _expert = v;
    session?.expertMode = expertMode;
    await kv.setString('settings.expert', v ? '1' : '0');
    notifyListeners();
  }

  Future<void> setOffRoadMode(bool v) async {
    _offRoad = v;
    session?.offRoadMode = offRoadMode;
    await kv.setString('settings.offRoad', v ? '1' : '0');
    notifyListeners();
  }

  void _step(ConnectStep s) {
    step = s;
    notifyListeners();
  }

  /// Connects to the demo bike.
  Future<void> connectDemo({SimBus bus = SimBus.can, SimAdapter adapter = SimAdapter.stn}) async {
    final bike = VirtualBike(bus: bus);
    final profile = profiles.byId(bus == SimBus.can ? 'sim-can' : 'sim-kline')!;
    simBike = bike;
    await connect(SimulatedTransport(bike, adapter: adapter, latency: const Duration(milliseconds: 12)), profile: profile);
  }

  /// Opens [transport], identifies the adapter, works out which bus the bike
  /// uses (unless [profile] is given) and scans the control units.
  Future<void> connect(ByteTransport transport, {BikeProfile? profile}) async {
    await disconnect();
    connecting = true;
    error = null;
    bikeNotLicensed = false;
    if (transport is! SimulatedTransport) simBike = null;
    notifyListeners();
    Elm327Adapter? adapter;
    try {
      _step(ConnectStep.link);
      await transport.open();
      _step(ConnectStep.adapter);
      adapter = Elm327Adapter(transport, log: log);
      await adapter.initialize();
      _step(ConnectStep.bike);
      profile ??= await _detectProfile(adapter);
      if (profile == null) {
        throw AdapterException('No answer from the bike. Check that the ignition is on and the adapter is plugged in firmly.');
      }
      final s = DiagnosticSession(adapter: adapter, profile: profile, tier: () => tier, expertMode: false);
      session = s;
      s.expertMode = expertMode;
      s.offRoadMode = offRoadMode;
      _step(ConnectStep.units);
      await s.scan();
      // Test the adapter's real send capability now (not from its ELM version
      // string), so the dashboard and write functions reflect what it can do.
      try {
        await s.probeLongMessages();
      } catch (_) {}
      if (s.vin != null && !profile.simulator) {
        final ok = await license.registerVin(s.vin!);
        bikeNotLicensed = !ok && license.tier != Tier.free;
        final existing = garage.byVin(s.vin!);
        await garage.upsert((existing ??
                GarageBike(vin: s.vin!, profileId: profile.id, profileName: profile.name, lastConnected: DateTime.now()))
            .copyWith(lastConnected: DateTime.now(), profileName: profile.name));
      }
      _step(ConnectStep.done);
    } catch (e) {
      error = e is AdapterException || e is TransportException ? e.toString() : 'Connection failed: $e';
      session = null;
      try {
        await adapter?.dispose();
        if (adapter == null) await transport.close();
      } catch (_) {}
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  /// Tries CAN first (UDS, then OBD-II), then K-line.
  Future<BikeProfile?> _detectProfile(Elm327Adapter a) async {
    Future<bool> answers(DiagClient c) async {
      try {
        await c.testerPresent();
        return true;
      } on NegativeResponseException {
        return true;
      } catch (_) {
        return false;
      }
    }

    if (await answers(UdsClient(a, const BusTarget(AddressingMode.canExtended, 0x12)))) {
      return profiles.byId('bmw-can');
    }
    try {
      if ((await ObdClient(a).supportedPids()).isNotEmpty) return profiles.byId('bmw-can');
    } catch (_) {}
    if (await answers(Kwp2000Client(a, const BusTarget(AddressingMode.kLine, 0x12)))) {
      return profiles.byId('bmw-kline');
    }
    return null;
  }

  /// Switches the connected bike to another profile (e.g. a user profile).
  Future<void> switchProfile(BikeProfile p) async {
    final s = session;
    if (s == null) return;
    _live?.stop();
    _live = null;
    final next = DiagnosticSession(adapter: s.adapter, profile: p, tier: () => tier)
      ..expertMode = expertMode
      ..offRoadMode = offRoadMode;
    session = next;
    notifyListeners();
    await next.scan();
    notifyListeners();
  }

  Future<void> rememberFaults(List<EcuFaults> f) async {
    lastFaults = f;
    final vin = session?.vin;
    if (vin != null && !isDemo) {
      final b = garage.byVin(vin);
      if (b != null) await garage.upsert(b.copyWith(faultCount: f.fold<int>(0, (a, e) => a + e.faults.length)));
    }
    notifyListeners();
  }

  Future<void> rememberService(String due) async {
    final vin = session?.vin;
    if (vin == null || isDemo) return;
    final b = garage.byVin(vin);
    if (b != null) await garage.upsert(b.copyWith(serviceDue: due));
  }

  Future<void> disconnect() async {
    _live?.stop();
    _live = null;
    lastFaults = null;
    final s = session;
    session = null;
    step = null;
    if (s != null) {
      try {
        await s.adapter.dispose();
      } catch (_) {}
    }
    notifyListeners();
  }

  void toggleDemoEngine() {
    final b = simBike;
    if (b == null) return;
    b.engineRunning = !b.engineRunning;
    notifyListeners();
  }
}
