import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Connect to [uri], attaching a Bearer [token] via the Authorization header
/// so the server's AuthMiddleware accepts the connection on native platforms.
WebSocketChannel connectAuthedWs(
  Uri uri, {
  String? token,
  Duration? pingInterval,
}) {
  return IOWebSocketChannel.connect(
    uri,
    headers: <String, dynamic>{
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    },
    pingInterval: pingInterval,
  );
}
