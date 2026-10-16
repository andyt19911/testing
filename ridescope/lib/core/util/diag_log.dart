import 'dart:async';
import 'dart:collection';

enum LogDirection { tx, rx, info, error }

class LogEntry {
  LogEntry(this.direction, this.text) : time = DateTime.now();
  final DateTime time;
  final LogDirection direction;
  final String text;

  String format() {
    final t = time.toIso8601String().substring(11, 23);
    final d = switch (direction) {
      LogDirection.tx => '>>',
      LogDirection.rx => '<<',
      LogDirection.info => '--',
      LogDirection.error => '!!',
    };
    return '$t $d $text';
  }
}

/// Ring buffer of raw adapter traffic. Exported from the Discovery console so
/// real-bike captures can be turned into verified ECU profiles.
class DiagLog {
  DiagLog({this.capacity = 5000});
  final int capacity;
  final _entries = ListQueue<LogEntry>();
  final _controller = StreamController<LogEntry>.broadcast();

  Stream<LogEntry> get stream => _controller.stream;
  List<LogEntry> get entries => List.unmodifiable(_entries);

  void add(LogDirection d, String text) {
    final e = LogEntry(d, text);
    _entries.addLast(e);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    _controller.add(e);
  }

  void tx(String t) => add(LogDirection.tx, t);
  void rx(String t) => add(LogDirection.rx, t);
  void info(String t) => add(LogDirection.info, t);
  void error(String t) => add(LogDirection.error, t);

  void clear() => _entries.clear();

  String export() => _entries.map((e) => e.format()).join('\n');
}
