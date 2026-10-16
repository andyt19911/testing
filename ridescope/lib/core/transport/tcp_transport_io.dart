import 'dart:async';
import 'dart:io';

import 'transport.dart';

/// Wi-Fi ELM327 adapters (usually 192.168.0.10:35000).
class TcpTransport implements ByteTransport {
  TcpTransport(this.host, this.port);
  final String host;
  final int port;

  static bool get supported => true;

  Socket? _socket;
  final _in = StreamController<List<int>>.broadcast();

  @override
  TransportKind get kind => TransportKind.wifi;
  @override
  String get displayName => 'Wi-Fi $host:$port';
  @override
  bool get isOpen => _socket != null;
  @override
  Stream<List<int>> get incoming => _in.stream;

  @override
  Future<void> open() async {
    try {
      final s = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
      s.setOption(SocketOption.tcpNoDelay, true);
      _socket = s;
      s.listen(_in.add, onDone: () => _socket = null, onError: (_) => _socket = null);
    } on SocketException catch (e) {
      throw TransportException('Could not reach the adapter at $host:$port (${e.message}). '
          'Is the phone connected to the adapter\'s Wi-Fi network?');
    }
  }

  @override
  Future<void> write(List<int> data) async {
    final s = _socket;
    if (s == null) throw TransportException('Not connected');
    s.add(data);
    await s.flush();
  }

  @override
  Future<void> close() async {
    await _socket?.close();
    _socket = null;
  }
}
