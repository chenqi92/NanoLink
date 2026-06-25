import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Build an [http.Client] for a single server connection. When [ignoreCert] is
/// true the underlying [HttpClient] accepts self-signed / invalid TLS certs for
/// this client only (does not touch the process-wide [HttpOverrides]).
http.Client buildHttpClient({bool ignoreCert = false}) {
  if (!ignoreCert) return http.Client();
  final inner = HttpClient()
    ..badCertificateCallback = (cert, host, port) => true;
  return IOClient(inner);
}
