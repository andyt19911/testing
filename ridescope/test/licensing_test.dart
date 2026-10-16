import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ridescope/licensing/license_service.dart';
import 'package:ridescope/licensing/license_token.dart';
import 'package:ridescope/licensing/tier.dart';

void main() {
  late SimpleKeyPair keys;
  late LicenseCodec codec;
  final now = DateTime.utc(2026, 10, 16);

  setUpAll(() async {
    keys = await Ed25519().newKeyPairFromSeed(List.filled(32, 7));
    codec = LicenseCodec((await keys.extractPublicKey()).bytes);
  });

  Future<String> issue(Tier t, {List<String> vins = const [], DateTime? expires}) =>
      LicenseCodec.sign(LicenseToken(id: 'T1', tier: t, holder: 'Test', issued: now, vins: vins, expires: expires), keys);

  test('valid key round-trips', () async {
    final t = await codec.verify(await issue(Tier.pro), now: now);
    expect(t.tier, Tier.pro);
    expect(t.holder, 'Test');
  });

  test('tampered, foreign and expired keys are rejected', () async {
    final good = await issue(Tier.plus);
    final parts = good.split('.');
    final forged = await issue(Tier.pro);
    await expectLater(codec.verify('${forged.split('.')[0]}.${parts[1]}', now: now), throwsA(isA<InvalidLicense>()));
    final other = await Ed25519().newKeyPairFromSeed(List.filled(32, 9));
    final foreign = await LicenseCodec.sign(LicenseToken(id: 'X', tier: Tier.pro, holder: '', issued: now), other);
    await expectLater(codec.verify(foreign, now: now), throwsA(isA<InvalidLicense>()));
    await expectLater(codec.verify('garbage', now: now), throwsA(isA<InvalidLicense>()));
    final expired = await issue(Tier.pro, expires: now.subtract(const Duration(days: 1)));
    await expectLater(codec.verify(expired, now: now), throwsA(isA<InvalidLicense>()));
  });

  test('tier gates features', () {
    expect(Tier.free.includes(Feature.readFaults.minTier), isTrue);
    expect(Tier.free.includes(Feature.clearFaults.minTier), isFalse);
    expect(Tier.plus.includes(Feature.serviceReset.minTier), isTrue);
    expect(Tier.plus.includes(Feature.coding.minTier), isFalse);
    expect(Tier.pro.includes(Feature.discovery.minTier), isTrue);
  });

  group('LicenseService', () {
    late MemoryKeyValueStore kv;
    late DateTime clock;
    LicenseService svc() => LicenseService(kv, codec, clock: () => clock);

    setUp(() {
      kv = MemoryKeyValueStore();
      clock = now;
    });

    test('key survives restart', () async {
      final a = svc();
      await a.applyToken(await issue(Tier.plus));
      final b = svc();
      await b.load();
      expect(b.tier, Tier.plus);
    });

    test('plus covers two bikes, third runs as free', () async {
      final s = svc();
      await s.setStoreTier(Tier.plus);
      expect(await s.registerVin('VIN1'), isTrue);
      expect(await s.registerVin('VIN2'), isTrue);
      expect(await s.registerVin('VIN3'), isFalse);
      expect(s.tierForVin('VIN1'), Tier.plus);
      expect(s.tierForVin('VIN3'), Tier.free);
    });

    test('bike removal has a cooldown', () async {
      final s = svc();
      await s.setStoreTier(Tier.plus);
      await s.registerVin('VIN1');
      await s.registerVin('VIN2');
      await s.removeVin('VIN1');
      expect(() => s.removeVin('VIN2'), throwsStateError);
      clock = now.add(const Duration(days: 31));
      await s.removeVin('VIN2');
      expect(s.registeredVins, isEmpty);
    });

    test('VIN-locked key only applies to its bike', () async {
      final s = svc();
      await s.applyToken(await issue(Tier.pro, vins: ['WB10ABC']));
      expect(s.tierForVin('WB10ABC'), Tier.pro);
      expect(s.tierForVin('OTHER'), Tier.free);
    });

    test('pro is unlimited', () async {
      final s = svc();
      await s.setStoreTier(Tier.pro);
      for (var i = 0; i < 10; i++) {
        expect(await s.registerVin('V$i'), isTrue);
      }
      expect(s.tierForVin('V9'), Tier.pro);
    });
  });
}
