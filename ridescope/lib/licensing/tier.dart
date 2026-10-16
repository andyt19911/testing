/// The three licence tiers.
enum Tier { free, plus, pro }

extension TierInfo on Tier {
  String get label => switch (this) {
        Tier.free => 'Free',
        Tier.plus => 'Plus',
        Tier.pro => 'Pro',
      };

  String get tagline => switch (this) {
        Tier.free => 'Check your bike and read fault codes',
        Tier.plus => 'Look after your own bike: service, faults and live data',
        Tier.pro => 'Everything, including coding and workshop tools',
      };

  /// Maximum number of bikes (VINs) the licence can be used with; null means unlimited.
  int? get maxBikes => switch (this) {
        Tier.free => 1,
        Tier.plus => 2,
        Tier.pro => null,
      };

  bool includes(Tier other) => index >= other.index;
}

/// Everything that is gated by tier. Checked in the service layer (not only by
/// hiding UI) so a gated action can never run on a lower tier.
enum Feature {
  identify(Tier.free, 'Control unit identification'),
  readFaults(Tier.free, 'Read fault codes'),
  basicLiveData(Tier.free, 'Basic live data'),
  clearFaults(Tier.plus, 'Clear fault codes'),
  fullLiveData(Tier.plus, 'All live data, charts and recording'),
  freezeFrames(Tier.plus, 'Freeze frames'),
  healthReport(Tier.plus, 'Shareable health report'),
  serviceReset(Tier.plus, 'Service reset and cluster date'),
  coding(Tier.pro, 'Coding with backup and restore'),
  adaptations(Tier.pro, 'Adaptations and calibrations'),
  actuators(Tier.pro, 'Actuator tests and ABS bleeding'),
  discovery(Tier.pro, 'Discovery console and raw logs'),
  expertMode(Tier.pro, 'Expert mode (unverified functions)');

  const Feature(this.minTier, this.label);
  final Tier minTier;
  final String label;
}

class FeatureLockedException implements Exception {
  FeatureLockedException(this.feature);
  final Feature feature;
  @override
  String toString() => '${feature.label} needs RideScope ${feature.minTier.label}';
}
