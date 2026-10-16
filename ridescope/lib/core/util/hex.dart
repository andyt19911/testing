import 'dart:typed_data';

/// Formats [bytes] as upper-case hex pairs, e.g. `[0x22, 0xF1]` → `22 F1`.
String toHex(List<int> bytes, {String separator = ' '}) =>
    bytes.map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase()).join(separator);

/// Formats a single value as a fixed-width hex string without separator.
String hexWord(int value, {int digits = 2}) =>
    value.toRadixString(16).padLeft(digits, '0').toUpperCase();

/// Parses a hex string, ignoring whitespace. Throws [FormatException] on
/// odd length or non-hex characters.
Uint8List fromHex(String hex) {
  final clean = hex.replaceAll(RegExp(r'\s'), '');
  if (clean.length.isOdd) {
    throw FormatException('Odd number of hex digits', hex);
  }
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final v = int.tryParse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    if (v == null) throw FormatException('Invalid hex', hex);
    out[i] = v;
  }
  return out;
}

/// Parses `"0x1F"`, `"1F"` or a decimal string into an int.
int parseIntFlexible(Object value) {
  if (value is int) return value;
  final s = value.toString().trim();
  if (s.startsWith('0x') || s.startsWith('0X')) return int.parse(s.substring(2), radix: 16);
  return int.tryParse(s) ?? int.parse(s, radix: 16);
}

bool isHexString(String s) => RegExp(r'^[0-9A-Fa-f\s]+$').hasMatch(s);

int bcdEncode(int value) => ((value ~/ 10) % 10) << 4 | (value % 10);
int bcdDecode(int byte) => ((byte >> 4) & 0xF) * 10 + (byte & 0xF);

int readUnsigned(List<int> data, int start, int length, {bool bigEndian = true}) {
  var v = 0;
  for (var i = 0; i < length; i++) {
    final b = data[bigEndian ? start + i : start + length - 1 - i];
    v = (v << 8) | (b & 0xFF);
  }
  return v;
}

List<int> writeUnsigned(int value, int length, {bool bigEndian = true}) {
  final out = List<int>.filled(length, 0);
  for (var i = 0; i < length; i++) {
    final b = (value >> (8 * (length - 1 - i))) & 0xFF;
    out[bigEndian ? i : length - 1 - i] = b;
  }
  return out;
}
