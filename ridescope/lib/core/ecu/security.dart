import '../sim/virtual_ecu.dart';

/// Seed/key algorithms by name. Real BMW algorithms are proprietary and are
/// not shipped; a profile that needs one stays unavailable until a licensed
/// implementation is registered here.
class KeyAlgorithms {
  static final Map<String, List<int> Function(List<int> seed)> _registry = {
    'sim-xor': VirtualEcu.simKey,
  };

  static bool has(String name) => name == 'none' || _registry.containsKey(name);

  static List<int> Function(List<int>)? lookup(String name) => _registry[name];

  static void register(String name, List<int> Function(List<int> seed) fn) => _registry[name] = fn;
}
