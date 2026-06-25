// Cross-platform factory for a per-connection HTTP client.
//
// When [ignoreCert] is set, native platforms return a client backed by an
// HttpClient whose badCertificateCallback accepts otherwise-rejected TLS
// certificates — scoped to this client only (no process-wide HttpOverrides).
// On web there is no SecurityContext/HttpClient, so [ignoreCert] is a no-op and
// a default client is returned.
export 'tls_client_io.dart' if (dart.library.html) 'tls_client_web.dart';
