import 'package:web_socket_channel/web_socket_channel.dart';

/// Browsers cannot set custom headers on the WebSocket handshake, so auth
/// relies on the token query param / same-origin cookie already on [uri].
///
/// [ignoreCert] is a no-op on web — browsers reject untrusted TLS certs and
/// expose no override.
WebSocketChannel connectAuthedWs(
  Uri uri, {
  String? token,
  Duration? pingInterval,
  bool ignoreCert = false,
}) {
  return WebSocketChannel.connect(uri);
}
