import 'dart:async';

import '../../licensing/tier.dart';
import '../ecu/profile.dart';
import 'session.dart';

class LiveChannel {
  LiveChannel(this.ecu, this.def);
  final EcuDef ecu;
  final LiveValueDef def;
  String get key => '${ecu.id}/${def.id}';
}

class LiveSample {
  LiveSample(this.channel, this.value, this.text, this.time);
  final LiveChannel channel;
  final double? value;
  final String text;
  final DateTime time;
}

/// Polls the selected channels round-robin as fast as the adapter allows and
/// publishes samples. Optionally records them for CSV export.
class LiveDataService {
  LiveDataService(this.session);
  final DiagnosticSession session;

  final _controller = StreamController<LiveSample>.broadcast();
  Stream<LiveSample> get samples => _controller.stream;

  final Map<String, LiveSample> latest = {};
  List<LiveChannel> _channels = [];
  bool _running = false;
  int _generation = 0;
  bool get running => _running;

  bool recording = false;
  final List<LiveSample> recorded = [];

  /// Channels the current tier may show.
  static List<LiveChannel> available(DiagnosticSession s) {
    final full = s.allows(Feature.fullLiveData);
    return [
      for (final e in s.presentEcus)
        for (final v in e.liveData)
          if (full || v.basic) LiveChannel(e, v),
    ];
  }

  static List<LiveChannel> lockedChannels(DiagnosticSession s) {
    if (s.allows(Feature.fullLiveData)) return const [];
    return [
      for (final e in s.presentEcus)
        for (final v in e.liveData)
          if (!v.basic) LiveChannel(e, v),
    ];
  }

  Future<LiveSample> readOnce(LiveChannel ch) async {
    if (!ch.def.basic) session.require(Feature.fullLiveData);
    final data = ch.ecu.protocol == EcuProtocol.obd
        ? await session.obd.readPid(ch.def.ident)
        : await session.client(ch.ecu).readData(ch.def.ident);
    final now = DateTime.now();
    if (data == null) return LiveSample(ch, null, '—', now);
    return LiveSample(ch, ch.def.encoding.decodeNumber(data), ch.def.encoding.decodeText(data), now);
  }

  void start(List<LiveChannel> channels) {
    for (final c in channels) {
      if (!c.def.basic) session.require(Feature.fullLiveData);
    }
    _channels = channels;
    if (_running) return;
    _running = true;
    unawaited(_loop(++_generation));
  }

  void updateChannels(List<LiveChannel> channels) => start(channels);

  Future<void> _loop(int generation) async {
    var errors = 0;
    // A stop() followed quickly by start() begins a new generation; the old
    // loop must not keep polling alongside it.
    bool alive() => _running && generation == _generation;
    while (alive()) {
      if (_channels.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }
      for (final ch in List.of(_channels)) {
        if (!alive()) break;
        try {
          final s = await readOnce(ch);
          errors = 0;
          latest[ch.key] = s;
          if (recording) recorded.add(s);
          if (!_controller.isClosed) _controller.add(s);
        } catch (e) {
          errors++;
          session.log.error('Live ${ch.key}: $e');
          if (errors > 3 * _channels.length) {
            await Future<void>.delayed(const Duration(seconds: 1));
          }
        }
      }
      // Yield so UI-triggered requests can take the adapter lock.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  void stop() => _running = false;

  /// CSV with one row per sample (time, channel, value).
  String exportCsv() {
    final b = StringBuffer('time,ecu,channel,value,unit\n');
    for (final s in recorded) {
      b.writeln([
        s.time.toIso8601String(),
        s.channel.ecu.shortName,
        '"${s.channel.def.name}"',
        s.value?.toStringAsFixed(s.channel.def.encoding.decimals) ?? s.text,
        s.channel.def.unit,
      ].join(','));
    }
    return b.toString();
  }

  Future<void> dispose() async {
    stop();
    await _controller.close();
  }
}
