import 'dart:io';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Connect to [uri], attaching a Bearer [token] via the Authorization header
/// so the server's AuthMiddleware accepts the connection on native platforms.
///
/// When [ignoreCert] is true, the handshake runs over a custom [HttpClient]
/// whose badCertificateCallback accepts self-signed / invalid TLS certs — scoped
/// to this connection only (no process-wide HttpOverrides).
WebSocketChannel connectAuthedWs(
  Uri uri, {
  String? token,
  Duration? pingInterval,
  bool ignoreCert = false,
}) {
  final headers = <String, dynamic>{
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };
  if (ignoreCert) {
    final client = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    return IOWebSocketChannel.connect(
      uri,
      headers: headers,
      pingInterval: pingInterval,
      customClient: client,
    );
  }
  return IOWebSocketChannel.connect(
    uri,
    headers: headers,
    pingInterval: pingInterval,
  );
}
