import '../util/hex.dart';

/// Renders data templates used by procedure steps into bytes.
///
/// Literal hex is copied as-is. Tokens in braces are replaced:
/// `{source|format}` where source is one of
///   * `today.dd`, `today.mm`, `today.yyyy`, `today.yy`, `today.HH`, `today.MI`
///   * `due.dd`, `due.mm`, `due.yyyy`, `due.yy` — today plus input `months`
///   * `input.<id>` — a value the user entered
/// and format is `u8`, `u16`, `u24`, `u32`, `bcd8` or `bcd16`.
///
/// Example: `"{due.dd|bcd8}{due.mm|bcd8}{due.yyyy|bcd16}"`.
class DataTemplate {
  DataTemplate(this.source);
  final String source;

  static final _token = RegExp(r'\{([a-zA-Z0-9_.]+)\|([a-z0-9]+)\}');

  List<int> render({required DateTime now, Map<String, int> inputs = const {}}) {
    final out = <int>[];
    var pos = 0;
    for (final m in _token.allMatches(source)) {
      out.addAll(_literal(source.substring(pos, m.start)));
      out.addAll(_encode(_value(m.group(1)!, now, inputs), m.group(2)!));
      pos = m.end;
    }
    out.addAll(_literal(source.substring(pos)));
    return out;
  }

  static List<int> _literal(String s) {
    final t = s.replaceAll(RegExp(r'\s'), '');
    return t.isEmpty ? const [] : fromHex(t);
  }

  static int _value(String key, DateTime now, Map<String, int> inputs) {
    if (key.startsWith('input.')) {
      final id = key.substring(6);
      final v = inputs[id];
      if (v == null) throw ArgumentError('Missing input "$id"');
      return v;
    }
    final parts = key.split('.');
    if (parts.length != 2) throw ArgumentError('Bad template key "$key"');
    final DateTime d;
    switch (parts[0]) {
      case 'today':
        d = now;
        break;
      case 'due':
        d = addMonths(now, inputs['months'] ?? 12);
        break;
      default:
        throw ArgumentError('Unknown template source "$key"');
    }
    return switch (parts[1]) {
      'dd' => d.day,
      'mm' => d.month,
      'yyyy' => d.year,
      'yy' => d.year % 100,
      'HH' => d.hour,
      'MI' => d.minute,
      _ => throw ArgumentError('Unknown date field "$key"'),
    };
  }

  static List<int> _encode(int v, String format) => switch (format) {
        'u8' => writeUnsigned(v, 1),
        'u16' => writeUnsigned(v, 2),
        'u24' => writeUnsigned(v, 3),
        'u32' => writeUnsigned(v, 4),
        'bcd8' => [bcdEncode(v % 100)],
        'bcd16' => [bcdEncode((v ~/ 100) % 100), bcdEncode(v % 100)],
        _ => throw ArgumentError('Unknown format "$format"'),
      };
}

/// Adds calendar months, clamping the day (31 Jan + 1 month → 28/29 Feb).
DateTime addMonths(DateTime d, int months) {
  final total = d.year * 12 + (d.month - 1) + months;
  final y = total ~/ 12;
  final m = total % 12 + 1;
  final lastDay = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, d.day > lastDay ? lastDay : d.day, d.hour, d.minute);
}
