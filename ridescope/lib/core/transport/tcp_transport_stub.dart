import 'transport.dart';

/// Web builds have no raw sockets; Wi-Fi adapters are unavailable there.
class TcpTransport implements ByteTransport {
  TcpTransport(this.host, this.port);
  final String host;
  final int port;

  static bool get supported => false;

  @override
  TransportKind get kind => TransportKind.wifi;
  @override
  String get displayName => '$host:$port';
  @override
  bool get isOpen => false;
  @override
  Stream<List<int>> get incoming => const Stream.empty();
  @override
  Future<void> open() async => throw TransportException('Wi-Fi adapters are not supported in the browser');
  @override
  Future<void> write(List<int> data) async => throw TransportException('Not connected');
  @override
  Future<void> close() async {}
}
