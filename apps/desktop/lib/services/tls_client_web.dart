import 'package:http/http.dart' as http;

/// Web has no SecurityContext/HttpClient, so certificate handling is delegated
/// to the browser and [ignoreCert] is ignored.
http.Client buildHttpClient({bool ignoreCert = false}) => http.Client();
