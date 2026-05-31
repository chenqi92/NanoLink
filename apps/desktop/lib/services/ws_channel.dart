// Cross-platform authenticated WebSocket connect.
//
// The server's auth middleware reads the JWT from the `Authorization` header
// (or auth cookie) — query-param tokens are no longer accepted. Native
// platforms therefore attach a Bearer header; web browsers cannot set custom
// handshake headers, so they fall back to the token query param / same-origin
// cookie carried in the uri.
export 'ws_channel_io.dart' if (dart.library.html) 'ws_channel_web.dart';
