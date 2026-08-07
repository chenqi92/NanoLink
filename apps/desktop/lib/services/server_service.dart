import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/models.dart';
import 'shell_session.dart';
import 'tls_client.dart';
import 'ws_channel.dart';

/// Connection mode enum
enum ConnectionMode {
  disconnected,
  websocket,
  httpPolling,
}

/// Connection status with mode information
class ConnectionStatus {
  final bool isConnected;
  final ConnectionMode mode;
  final DateTime? lastUpdate;
  final String? error;

  const ConnectionStatus({
    required this.isConnected,
    required this.mode,
    this.lastUpdate,
    this.error,
  });

  static const disconnected = ConnectionStatus(
    isConnected: false,
    mode: ConnectionMode.disconnected,
  );
}

/// Server summary data
class ServerSummary {
  final int connectedAgents;
  final double avgCpuUsage;
  final double avgMemoryUsage;
  final int totalAlerts;

  const ServerSummary({
    this.connectedAgents = 0,
    this.avgCpuUsage = 0,
    this.avgMemoryUsage = 0,
    this.totalAlerts = 0,
  });

  factory ServerSummary.fromJson(Map<String, dynamic> json) {
    return ServerSummary(
      connectedAgents: json['connectedAgents'] as int? ?? 0,
      avgCpuUsage: (json['avgCpuUsage'] as num?)?.toDouble() ?? 0,
      avgMemoryUsage: (json['avgMemoryUsage'] as num?)?.toDouble() ?? 0,
      totalAlerts: json['totalAlerts'] as int? ?? 0,
    );
  }
}

/// One auto-diagnosis finding from `GET /api/assistant/findings`.
class AssistantFinding {
  final String kind; // anomaly | warn | info | ok
  final String title;
  final String detail;
  final String? agentId;
  final List<String> actions;

  const AssistantFinding({
    required this.kind,
    required this.title,
    required this.detail,
    this.agentId,
    required this.actions,
  });

  factory AssistantFinding.fromJson(Map<String, dynamic> j) => AssistantFinding(
        kind: j['kind'] as String? ?? 'info',
        title: j['title'] as String? ?? '',
        detail: j['detail'] as String? ?? '',
        agentId: (j['agentId'] as String?)?.isEmpty ?? true
            ? null
            : j['agentId'] as String?,
        actions: (j['actions'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
      );
}

/// Result of generating a device pairing token (`POST /api/devices/token`).
class DeviceTokenResult {
  /// Base64(JSON) payload to render as a QR code (embeds server URL + token).
  final String qrData;

  /// 6-digit manual pairing code.
  final String pairingCode;

  /// Permission level granted to the paired device (0=read-only .. 3=system).
  /// Mirrors the server's top-level `permissionLevel` field.
  final int permissionLevel;

  /// When the QR/pairing offer expires, decoded from the QR payload's `e`
  /// (Unix-seconds) field; null when the server did not advertise an expiry.
  final DateTime? expiresAt;

  const DeviceTokenResult({
    required this.qrData,
    required this.pairingCode,
    this.permissionLevel = 0,
    this.expiresAt,
  });
}

/// Parsed historical metrics for one agent, shaped for the history charts.
///
/// Handles both backend response shapes (DB-aggregated and in-memory): each
/// sample exposes `cpu.usagePercent`, `memory.used/total`, `networks[].rx/tx`,
/// `disks[].read/write` and optional `gpus[]`. Network/disk rates are converted
/// to MB/s; memory is normalised to a percentage.
class MetricsHistory {
  final List<DateTime> times;
  final List<double> cpu; // %
  final List<double> mem; // %
  final List<double> netRx; // MB/s
  final List<double> netTx; // MB/s
  final List<double> diskRead; // MB/s
  final List<double> diskWrite; // MB/s
  final List<double> gpuUsage; // %
  final List<double> gpuTemp; // °C (may be empty)
  final List<double>
      cpuMax; // % per-bucket peak (DB-aggregated; empty if absent)
  final List<double>
      memMax; // % per-bucket peak (DB-aggregated; empty if absent)
  final List<double>
      loadAvg; // 1-min load average (DB-aggregated; empty if absent)

  const MetricsHistory({
    required this.times,
    required this.cpu,
    required this.mem,
    required this.netRx,
    required this.netTx,
    required this.diskRead,
    required this.diskWrite,
    required this.gpuUsage,
    required this.gpuTemp,
    this.cpuMax = const [],
    this.memMax = const [],
    this.loadAvg = const [],
  });

  bool get isEmpty => cpu.isEmpty;
  bool get hasGpu => gpuUsage.any((v) => v > 0) && gpuUsage.isNotEmpty;

  /// Whether the server supplied per-bucket CPU/Mem peak bands (DB path only).
  bool get hasMaxBands => cpuMax.isNotEmpty || memMax.isNotEmpty;

  factory MetricsHistory.parse(List<dynamic> raw) {
    final times = <DateTime>[];
    final cpu = <double>[];
    final mem = <double>[];
    final netRx = <double>[];
    final netTx = <double>[];
    final diskRead = <double>[];
    final diskWrite = <double>[];
    final gpuUsage = <double>[];
    final gpuTemp = <double>[];
    final cpuMax = <double>[];
    final memMax = <double>[];
    final loadAvg = <double>[];
    var anyGpuTemp = false;
    var anyCpuMax = false;
    var anyMemMax = false;
    var anyLoad = false;

    double n(dynamic v) => (v as num?)?.toDouble() ?? 0;
    const mb = 1000000.0;

    for (final e in raw) {
      if (e is! Map) continue;
      final m = e.cast<String, dynamic>();

      times.add(_parseTime(m['timestamp']));

      final cpuMap = (m['cpu'] as Map?) ?? const {};
      cpu.add(n(cpuMap['usagePercent']));
      // DB-aggregated path emits per-bucket peak as cpu.maxPercent (omitted when 0).
      if (cpuMap.containsKey('maxPercent')) {
        anyCpuMax = true;
        cpuMax.add(n(cpuMap['maxPercent']));
      } else {
        cpuMax.add(0);
      }

      final memMap = (m['memory'] as Map?) ?? const {};
      final total = n(memMap['total']);
      final used = n(memMap['used']);
      mem.add(total > 0 ? (used / total * 100).clamp(0, 100).toDouble() : 0);
      // memory.maxPercent is already a percentage (DB-aggregated path).
      if (memMap.containsKey('maxPercent')) {
        anyMemMax = true;
        memMax.add(n(memMap['maxPercent']).clamp(0, 100).toDouble());
      } else {
        memMax.add(0);
      }

      // loadAverage is a top-level array per sample on the DB-aggregated path.
      final loadList = m['loadAverage'] as List? ?? const [];
      if (loadList.isNotEmpty) {
        anyLoad = true;
        loadAvg.add(n(loadList.first));
      } else {
        loadAvg.add(0);
      }

      double rx = 0, tx = 0;
      for (final net in (m['networks'] as List? ?? const [])) {
        if (net is Map) {
          rx += n(net['rxBytesPerSec']);
          tx += n(net['txBytesPerSec']);
        }
      }
      netRx.add(rx / mb);
      netTx.add(tx / mb);

      double rd = 0, wr = 0;
      for (final d in (m['disks'] as List? ?? const [])) {
        if (d is Map) {
          rd += n(d['readBytesPerSec']);
          wr += n(d['writeBytesPerSec']);
        }
      }
      diskRead.add(rd / mb);
      diskWrite.add(wr / mb);

      final gpus = m['gpus'] as List? ?? const [];
      if (gpus.isNotEmpty && gpus.first is Map) {
        final g = (gpus.first as Map);
        gpuUsage.add(n(g['usagePercent']));
        if (g.containsKey('temperature')) {
          anyGpuTemp = true;
          gpuTemp.add(n(g['temperature']));
        } else {
          gpuTemp.add(0);
        }
      } else {
        gpuUsage.add(0);
        gpuTemp.add(0);
      }
    }

    return MetricsHistory(
      times: times,
      cpu: cpu,
      mem: mem,
      netRx: netRx,
      netTx: netTx,
      diskRead: diskRead,
      diskWrite: diskWrite,
      gpuUsage: gpuUsage,
      gpuTemp: anyGpuTemp ? gpuTemp : const [],
      cpuMax: anyCpuMax ? cpuMax : const [],
      memMax: anyMemMax ? memMax : const [],
      loadAvg: anyLoad ? loadAvg : const [],
    );
  }

  static DateTime _parseTime(dynamic v) {
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) {
      final ms = int.tryParse(v);
      if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
      return DateTime.tryParse(v) ?? DateTime.now();
    }
    return DateTime.now();
  }
}

/// Server version information from welcome message
class ServerInfo {
  final String version;
  final String minVersion;
  final int serverTime;
  final List<String> features;

  const ServerInfo({
    required this.version,
    required this.minVersion,
    required this.serverTime,
    required this.features,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    return ServerInfo(
      version: json['version'] as String? ?? '0.0.0',
      minVersion: json['minVersion'] as String? ?? '0.0.0',
      serverTime: json['serverTime'] as int? ?? 0,
      features: (json['features'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
    );
  }

  /// Check if client version is compatible with server
  bool isCompatible(String clientVersion) {
    return _compareVersions(clientVersion, minVersion) >= 0;
  }

  /// Compare two version strings (returns -1, 0, or 1)
  static int _compareVersions(String v1, String v2) {
    final parts1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final parts2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (var i = 0; i < 3; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 < p2) return -1;
      if (p1 > p2) return 1;
    }
    return 0;
  }
}

/// Desktop client version
const String clientVersion = '0.3.3';

/// Why a login attempt failed, so the UI can show a specific message.
///
/// Maps the server's `POST /api/auth/login` status codes (auth_handler.go):
/// 400 → [badRequest], 401 → [invalidCredentials], 429 → [rateLimited],
/// 5xx → [serverError]; transport/timeout failures → [network].
enum LoginError {
  invalidCredentials, // 401
  rateLimited, // 429
  badRequest, // 400
  serverError, // 5xx
  network, // transport/timeout/parse failure
}

/// Outcome of a login attempt. On success [token] is non-null and [error] null;
/// on failure [error] is set (and [message] carries the server's reason if any).
class LoginResult {
  final String? token;
  final LoginError? error;
  final String? message;
  final int? statusCode;

  const LoginResult.success(this.token)
      : error = null,
        message = null,
        statusCode = 200;

  const LoginResult.failure(this.error, {this.message, this.statusCode})
      : token = null;

  bool get ok => token != null && error == null;
}

/// Outcome of an assistant chat call, distinguishing the not-configured (503),
/// bad-request (400) and upstream-failure (502) cases the server returns.
enum AssistantChatError {
  notConfigured, // 503 — llm disabled / no API key
  badRequest, // 400 — invalid / empty / too-long messages
  upstreamFailed, // 502 — LLM call failed
  serverError, // other non-2xx
  network, // transport/timeout/parse failure
}

/// Result of [ServerService.assistantChat]: on success [reply] is non-null;
/// on failure [error] is set and [message] carries the server's reason.
class AssistantChatResult {
  final ChatMessage? reply;
  final AssistantChatError? error;
  final String? message;
  final int? statusCode;

  const AssistantChatResult.success(this.reply)
      : error = null,
        message = null,
        statusCode = 200;

  const AssistantChatResult.failure(this.error, {this.message, this.statusCode})
      : reply = null;

  bool get ok => reply != null && error == null;
}

/// Result of dispatching a command via [ServerService.sendCommandReturningId].
/// On success [commandId] is non-null (poll it with [ServerService.pollCommandResult]);
/// on failure [error] holds a human-readable message.
class CommandDispatch {
  final String? commandId;
  final String? error;

  const CommandDispatch.success(this.commandId) : error = null;
  const CommandDispatch.failure(this.error) : commandId = null;

  bool get ok => commandId != null && error == null;
}

/// Status of a polled command result (`GET /api/agents/:id/command/:commandId/result`).
enum CommandResultStatus { ready, pending, denied, error }

/// Result of polling a dispatched command's structured output.
/// - [CommandResultStatus.ready]: [data] holds the decoded JSON result.
/// - [CommandResultStatus.pending]: agent has not reported yet (HTTP 202).
/// - [CommandResultStatus.denied]: caller may not read this result (HTTP 403).
/// - [CommandResultStatus.error]: transport/server failure ([message] set).
class CommandResult {
  final CommandResultStatus status;
  final Map<String, dynamic>? data;
  final String? message;

  const CommandResult(this.status, {this.data, this.message});

  bool get isReady => status == CommandResultStatus.ready;
  bool get isPending => status == CommandResultStatus.pending;
}

/// Result of validating a device token at add-time
/// (`POST /api/auth/device`, device_handler.go AuthenticateDevice).
class DeviceAuthResult {
  final bool ok;
  final int permissionLevel;
  final String serverName;
  final String? error;
  final int? statusCode;

  const DeviceAuthResult({
    required this.ok,
    this.permissionLevel = 0,
    this.serverName = '',
    this.error,
    this.statusCode,
  });
}

/// Service for communicating with NanoLink servers using WebSocket + HTTP fallback
class ServerService {
  final ServerConnection connection;
  final http.Client _client;
  Timer? _pollingTimer;
  WebSocketChannel? _wsChannel;
  bool _wsConnected = false;
  bool _useWebSocket = true;
  Timer? _wsPingTimer;
  DateTime? _lastPongTime;

  // Cached data for incremental updates
  List<Agent> _cachedAgents = [];
  Map<String, AgentMetrics> _cachedMetrics = {};

  final StreamController<List<Agent>> _agentsController =
      StreamController<List<Agent>>.broadcast();
  final StreamController<Map<String, AgentMetrics>> _metricsController =
      StreamController<Map<String, AgentMetrics>>.broadcast();
  final StreamController<ConnectionStatus> _connectionController =
      StreamController<ConnectionStatus>.broadcast();
  final StreamController<ServerSummary> _summaryController =
      StreamController<ServerSummary>.broadcast();
  final StreamController<String> _agentOfflineController =
      StreamController<String>.broadcast();
  final StreamController<ServerInfo> _serverInfoController =
      StreamController<ServerInfo>.broadcast();

  Stream<List<Agent>> get agentsStream => _agentsController.stream;
  Stream<Map<String, AgentMetrics>> get metricsStream =>
      _metricsController.stream;
  Stream<ConnectionStatus> get connectionStream => _connectionController.stream;
  Stream<ServerSummary> get summaryStream => _summaryController.stream;
  Stream<String> get agentOfflineStream => _agentOfflineController.stream;
  Stream<ServerInfo> get serverInfoStream => _serverInfoController.stream;

  ServerInfo? _serverInfo;

  bool get isWebSocketConnected => _wsConnected;
  ConnectionMode get connectionMode => _wsConnected
      ? ConnectionMode.websocket
      : (_pollingTimer != null
          ? ConnectionMode.httpPolling
          : ConnectionMode.disconnected);

  /// Timestamp of the most recent WebSocket `pong` (heartbeat reply), or null
  /// when no pong has been received on the current connection.
  DateTime? get lastPong => _lastPongTime;

  /// True when the WebSocket is connected but the last heartbeat reply is older
  /// than [threshold] (default 90s ≈ 3 missed 30s pings), indicating a stale /
  /// half-open socket. False while polling or before the first pong.
  bool isWsStale({Duration threshold = const Duration(seconds: 90)}) {
    if (!_wsConnected || _lastPongTime == null) return false;
    return DateTime.now().difference(_lastPongTime!) > threshold;
  }

  /// Get cached server info (available after WebSocket connection)
  ServerInfo? get serverInfo => _serverInfo;

  /// Check if connected to a compatible server
  bool get isCompatibleServer =>
      _serverInfo == null || _serverInfo!.isCompatible(clientVersion);

  ServerService({required this.connection, http.Client? client})
      : _client = client ?? buildHttpClient(ignoreCert: connection.ignoreCert);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (connection.authToken != null && connection.authToken!.isNotEmpty)
          'Authorization': 'Bearer ${connection.authToken}',
      };

  /// Trailing-slash-trimmed HTTP base. When [ServerConnection.forceTls] is set,
  /// an insecure `http://` origin is upgraded to `https://` so requests never
  /// fall back to cleartext.
  String _httpBaseUrl() {
    var baseUrl = connection.url.endsWith('/')
        ? connection.url.substring(0, connection.url.length - 1)
        : connection.url;
    if (connection.forceTls && baseUrl.startsWith('http://')) {
      baseUrl = 'https://${baseUrl.substring(7)}';
    }
    return baseUrl;
  }

  String _buildUrl(String path) => '${_httpBaseUrl()}/api$path';

  /// `ws(s)://host[:port]` base derived from the configured HTTP url. Honors
  /// [ServerConnection.forceTls] (via [_httpBaseUrl]) so the socket upgrades to
  /// `wss://` alongside the REST origin.
  String _wsBaseUrl() {
    var baseUrl = _httpBaseUrl();

    // Convert http(s) to ws(s)
    if (baseUrl.startsWith('https://')) {
      baseUrl = 'wss://${baseUrl.substring(8)}';
    } else if (baseUrl.startsWith('http://')) {
      baseUrl = 'ws://${baseUrl.substring(7)}';
    }
    return baseUrl;
  }

  String _buildWsUrl() {
    return '${_wsBaseUrl()}/ws/dashboard';
  }

  /// Open a remote shell session for [agentId] (`/ws/shell/:id`).
  ///
  /// The returned session is not connected yet — wire up its [ShellSession.lines]
  /// / [ShellSession.statusStream] listeners first, then call
  /// [ShellSession.connect]. Auth uses the Authorization header on native and
  /// the same-origin HttpOnly cookie in a browser.
  ShellSession openShell(String agentId) {
    final uri =
        Uri.parse('${_wsBaseUrl()}/ws/shell/${Uri.encodeComponent(agentId)}');
    return ShellSession(
        uri: uri,
        token: connection.authToken,
        ignoreCert: connection.ignoreCert);
  }

  /// Login with username and password, returns JWT token on success
  Future<String?> login(String username, String password) async {
    try {
      final response = await _client
          .post(
            Uri.parse(_buildUrl('/auth/login')),
            headers: {
              'Content-Type': 'application/json',
              'X-NanoLink-Client': 'native',
            },
            body: jsonEncode({
              'username': username,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['token'] as String?;
      }
      debugPrint('[Auth] Login failed: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('[Auth] Login error: $e');
      return null;
    }
  }

  /// Login variant that differentiates failures so the UI can show specifics.
  ///
  /// Same request as [login] (`POST /api/auth/login`), but returns a
  /// [LoginResult] mapping the server's status codes (auth_handler.go):
  /// 401 → invalid credentials, 429 → rate-limited (locked out), 400 → bad
  /// request, 5xx → server error; transport/timeout failures → network.
  /// On success the JWT is taken from the JSON body's `token` field (the server
  /// also sets an HttpOnly cookie, which native clients cannot read).
  Future<LoginResult> loginDetailed(String username, String password) async {
    try {
      final response = await _client
          .post(
            Uri.parse(_buildUrl('/auth/login')),
            headers: {
              'Content-Type': 'application/json',
              'X-NanoLink-Client': 'native',
            },
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final token = data['token'] as String?;
        if (token != null && token.isNotEmpty) {
          return LoginResult.success(token);
        }
        return const LoginResult.failure(LoginError.serverError,
            message: 'login succeeded but no token was returned',
            statusCode: 200);
      }

      final reason = _errorMessage(response);
      switch (response.statusCode) {
        case 401:
          return LoginResult.failure(LoginError.invalidCredentials,
              message: reason, statusCode: 401);
        case 429:
          return LoginResult.failure(LoginError.rateLimited,
              message: reason, statusCode: 429);
        case 400:
          return LoginResult.failure(LoginError.badRequest,
              message: reason, statusCode: 400);
        default:
          return LoginResult.failure(LoginError.serverError,
              message: reason, statusCode: response.statusCode);
      }
    } catch (e) {
      debugPrint('[Auth] Login error: $e');
      return LoginResult.failure(LoginError.network, message: e.toString());
    }
  }

  /// Redeem a 6-digit pairing code for a device token.
  ///
  /// Posts to the public `/api/auth/pairing` endpoint; returns the rotated
  /// device token on success, or null on failure.
  Future<String?> redeemPairingCode(String code) async {
    try {
      final response = await _client
          .post(
            Uri.parse(_buildUrl('/auth/pairing')),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'pairingCode': code}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['token'] as String?;
      }
      debugPrint('[Auth] Pairing redeem failed: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('[Auth] Pairing redeem error: $e');
      return null;
    }
  }

  /// Test connection to server
  Future<bool> testConnection() async {
    try {
      final response = await _client
          .get(Uri.parse(_buildUrl('/health')), headers: _headers)
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Connect to WebSocket for real-time updates
  Future<void> _connectWebSocket() async {
    if (!_useWebSocket || _wsConnected) return;

    try {
      final wsUrl = _buildWsUrl();
      debugPrint('[WS] Connecting to $wsUrl');

      _wsChannel = connectAuthedWs(Uri.parse(wsUrl),
          token: connection.authToken, ignoreCert: connection.ignoreCert);

      _wsChannel!.stream.listen(
        _onWsMessage,
        onError: _onWsError,
        onDone: _onWsDone,
      );

      _wsConnected = true;
      // Seed the heartbeat clock so staleness is measured from connect time,
      // not from a stale pong on a previous socket.
      _lastPongTime = DateTime.now();
      _emitConnectionStatus(true, ConnectionMode.websocket);

      // Start ping timer
      _wsPingTimer?.cancel();
      _wsPingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _sendWsPing();
      });

      debugPrint('[WS] Connected successfully');
    } catch (e) {
      debugPrint('[WS] Connection failed: $e');
      _wsConnected = false;
      // Fall back to polling
      _startPolling();
    }
  }

  void _emitConnectionStatus(bool connected, ConnectionMode mode,
      [String? error]) {
    _connectionController.add(ConnectionStatus(
      isConnected: connected,
      mode: mode,
      lastUpdate: DateTime.now(),
      error: error,
    ));
  }

  void _onWsMessage(dynamic data) {
    try {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      final type = msg['type'] as String?;
      final payload = msg['data'];

      switch (type) {
        case 'welcome':
          // Handle welcome message with version info
          if (payload is Map<String, dynamic>) {
            _serverInfo = ServerInfo.fromJson(payload);
            _serverInfoController.add(_serverInfo!);
            debugPrint('[WS] Connected to server v${_serverInfo!.version}');

            // Check compatibility
            if (!_serverInfo!.isCompatible(clientVersion)) {
              debugPrint(
                  '[WS] Warning: Client v$clientVersion may not be compatible '
                  'with server (min: ${_serverInfo!.minVersion})');
            }
          }

        case 'agents':
          if (payload is List) {
            _cachedAgents = payload
                .map((j) =>
                    Agent.fromJson(j as Map<String, dynamic>, connection.id))
                .toList();
            _agentsController.add(_cachedAgents);
          }

        case 'agent_update':
          // Handle single agent update
          if (payload is Map<String, dynamic>) {
            final updatedAgent = Agent.fromJson(payload, connection.id);
            final index =
                _cachedAgents.indexWhere((a) => a.id == updatedAgent.id);
            if (index >= 0) {
              _cachedAgents[index] = updatedAgent;
            } else {
              _cachedAgents.add(updatedAgent);
            }
            _agentsController.add(List.from(_cachedAgents));
            debugPrint('[WS] Agent updated: ${updatedAgent.hostname}');
          }

        case 'metrics':
          if (payload is Map) {
            // Check if single agent update or full update
            if (payload.containsKey('agentId') &&
                payload.containsKey('metrics')) {
              final agentId = payload['agentId'] as String;
              final metricsData = payload['metrics'] as Map<String, dynamic>;
              _cachedMetrics[agentId] =
                  AgentMetrics.fromJson(metricsData, agentId);
            } else {
              // Full metrics update
              payload.forEach((key, value) {
                if (value != null && value is Map<String, dynamic>) {
                  _cachedMetrics[key as String] =
                      AgentMetrics.fromJson(value, key);
                }
              });
            }
            _metricsController.add(Map.from(_cachedMetrics));
          }

        case 'agent_offline':
          // Handle agent going offline
          String? offlineAgentId;
          if (payload is String) {
            offlineAgentId = payload;
          } else if (payload is Map && payload.containsKey('agentId')) {
            offlineAgentId = payload['agentId'] as String?;
          }

          if (offlineAgentId != null) {
            debugPrint('[WS] Agent offline: $offlineAgentId');
            // Remove from cached data
            _cachedAgents.removeWhere((a) => a.id == offlineAgentId);
            _cachedMetrics.remove(offlineAgentId);
            // Emit updates
            _agentsController.add(List.from(_cachedAgents));
            _metricsController.add(Map.from(_cachedMetrics));
            _agentOfflineController.add(offlineAgentId);
          }

        case 'summary':
          // Handle server summary update
          if (payload is Map<String, dynamic>) {
            final summary = ServerSummary.fromJson(payload);
            _summaryController.add(summary);
            debugPrint(
                '[WS] Summary updated: ${summary.connectedAgents} agents');
          }

        case 'pong':
          // Heartbeat response - track latency
          _lastPongTime = DateTime.now();
          break;

        default:
          debugPrint('[WS] Unknown message type: $type');
      }
    } catch (e) {
      debugPrint('[WS] Message parse error: $e');
    }
  }

  void _onWsError(Object error) {
    debugPrint('[WS] Error: $error');
    _wsConnected = false;
    _emitConnectionStatus(false, ConnectionMode.disconnected, error.toString());
    _startPolling();
  }

  void _onWsDone() {
    debugPrint('[WS] Connection closed');
    _wsConnected = false;
    _wsPingTimer?.cancel();
    _emitConnectionStatus(false, ConnectionMode.disconnected);
    // Try to reconnect after delay
    Timer(const Duration(seconds: 3), () {
      if (_useWebSocket) {
        _connectWebSocket();
      }
    });
  }

  void _sendWsPing() {
    if (_wsConnected && _wsChannel != null) {
      try {
        _wsChannel!.sink.add(jsonEncode({
          'type': 'ping',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }));
      } catch (e) {
        debugPrint('[WS] Ping error: $e');
      }
    }
  }

  /// Fetch agents from server (HTTP fallback)
  Future<List<Agent>> fetchAgents() async {
    try {
      final response = await _client
          .get(Uri.parse(_buildUrl('/agents')), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        return data
            .map((json) =>
                Agent.fromJson(json as Map<String, dynamic>, connection.id))
            .toList();
      }
      return [];
    } catch (e) {
      _emitConnectionStatus(false, ConnectionMode.disconnected, e.toString());
      return [];
    }
  }

  /// Fetch metrics for all agents (HTTP fallback)
  Future<Map<String, AgentMetrics>> fetchMetrics() async {
    try {
      final response = await _client
          .get(Uri.parse(_buildUrl('/metrics')), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        final metrics = <String, AgentMetrics>{};
        data.forEach((agentId, metricsJson) {
          if (metricsJson != null) {
            metrics[agentId] = AgentMetrics.fromJson(
              metricsJson as Map<String, dynamic>,
              agentId,
            );
          }
        });
        return metrics;
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  /// Fetch historical metrics for [agentId] over the trailing [window].
  ///
  /// Sends `start`/`end` (Unix ms) so the server uses its DB-aggregated path
  /// when persistence is available, otherwise it falls back to the in-memory
  /// ring buffer (same JSON shape, capped by [limit]).
  Future<MetricsHistory?> fetchMetricsHistory(
    String agentId, {
    required Duration window,
    String interval = 'auto',
    int limit = 240,
  }) async {
    try {
      final end = DateTime.now();
      final start = end.subtract(window);
      final uri = Uri.parse(_buildUrl('/metrics/history')).replace(
        queryParameters: {
          'agentId': agentId,
          'start': '${start.millisecondsSinceEpoch}',
          'end': '${end.millisecondsSinceEpoch}',
          'interval': interval,
          'limit': '$limit',
        },
      );
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) return MetricsHistory.parse(data);
        return const MetricsHistory(
          times: [],
          cpu: [],
          mem: [],
          netRx: [],
          netTx: [],
          diskRead: [],
          diskWrite: [],
          gpuUsage: [],
          gpuTemp: [],
        );
      }
      return null;
    } catch (e) {
      debugPrint('[History] fetch error: $e');
      return null;
    }
  }

  /// Send a control command to an agent (`POST /api/agents/:id/command`).
  ///
  /// [type] is a backend `CommandType` enum name (e.g. `SYSTEM_REBOOT`,
  /// `HEALTH_CHECK`, `SERVICE_RESTART`). Returns `null` on success, otherwise a
  /// human-readable error message. Requires L1+ (server enforces per-route).
  Future<String?> sendCommand(
    String agentId,
    String type, {
    String target = '',
    Map<String, String>? params,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse(_buildUrl('/agents/$agentId/command')),
            headers: _headers,
            body: jsonEncode({
              'type': type,
              'target': target,
              if (params != null) 'params': params,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return null;
      return _errorMessage(response);
    } catch (e) {
      return e.toString();
    }
  }

  /// Dispatch a command and return its server-assigned `commandId` so the caller
  /// can poll the result with [pollCommandResult]. Same route/body as
  /// [sendCommand] (`POST /api/agents/:id/command`); the server replies 200 with
  /// `{ "commandId": "...", ... }` on dispatch.
  Future<CommandDispatch> sendCommandReturningId(
    String agentId,
    String type, {
    String target = '',
    Map<String, String>? params,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse(_buildUrl('/agents/$agentId/command')),
            headers: _headers,
            body: jsonEncode({
              'type': type,
              'target': target,
              if (params != null) 'params': params,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final id = data['commandId'] as String?;
        if (id != null && id.isNotEmpty) return CommandDispatch.success(id);
        return const CommandDispatch.failure('server returned no commandId');
      }
      return CommandDispatch.failure(_errorMessage(response));
    } catch (e) {
      return CommandDispatch.failure(e.toString());
    }
  }

  /// Poll the structured result of a dispatched command
  /// (`GET /api/agents/:id/command/:commandId/result`).
  ///
  /// The server returns 200 with the decoded result once the agent reports back,
  /// 202 (`{ "status": "pending" }`) while still in flight, or 403 when the
  /// caller may not read this command's result. Callers should re-poll on
  /// [CommandResultStatus.pending] with a short backoff.
  Future<CommandResult> pollCommandResult(
      String agentId, String commandId) async {
    try {
      final response = await _client
          .get(
            Uri.parse(_buildUrl('/agents/$agentId/command/$commandId/result')),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      switch (response.statusCode) {
        case 200:
          final decoded = jsonDecode(response.body);
          return CommandResult(
            CommandResultStatus.ready,
            data: decoded is Map<String, dynamic> ? decoded : null,
          );
        case 202:
          return const CommandResult(CommandResultStatus.pending);
        case 403:
          return CommandResult(CommandResultStatus.denied,
              message: _errorMessage(response));
        default:
          return CommandResult(CommandResultStatus.error,
              message: _errorMessage(response));
      }
    } catch (e) {
      return CommandResult(CommandResultStatus.error, message: e.toString());
    }
  }

  /// Ask an agent to push fresh data on demand
  /// (`POST /api/agents/:id/data-request`). [requestType] ∈
  /// full / static / disk_usage / network_info / user_sessions / gpu_info /
  /// health. Returns `null` on success, otherwise an error message.
  Future<String?> requestData(
    String agentId, {
    String requestType = 'full',
    String target = '',
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse(_buildUrl('/agents/$agentId/data-request')),
            headers: _headers,
            body: jsonEncode({'requestType': requestType, 'target': target}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return null;
      return _errorMessage(response);
    } catch (e) {
      return e.toString();
    }
  }

  /// Fetch metric-derived auto-diagnosis findings
  /// (`GET /api/assistant/findings`). Returns `null` on failure.
  Future<List<AssistantFinding>?> fetchAssistantFindings() async {
    try {
      final response = await _client
          .get(Uri.parse(_buildUrl('/assistant/findings')), headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return data
              .whereType<Map<String, dynamic>>()
              .map(AssistantFinding.fromJson)
              .toList();
        }
        return const <AssistantFinding>[];
      }
      return null;
    } catch (e) {
      debugPrint('[Assistant] findings error: $e');
      return null;
    }
  }

  /// Ask the AI assistant a question grounded in the live fleet snapshot
  /// (`POST /api/assistant/chat`).
  ///
  /// Sends `{ "messages": [ {role, content}, ... ] }` and reads `{ "reply": "..." }`
  /// on success. Distinguishes the server's failure cases (assistant_handler.go):
  /// 503 → not configured, 400 → bad request, 502 → upstream LLM failed.
  Future<AssistantChatResult> assistantChat(List<ChatMessage> messages) async {
    try {
      final response = await _client
          .post(
            Uri.parse(_buildUrl('/assistant/chat')),
            headers: _headers,
            body: jsonEncode(
                {'messages': messages.map((m) => m.toJson()).toList()}),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final reply = data['reply'] as String? ?? '';
        return AssistantChatResult.success(
            ChatMessage(role: 'assistant', content: reply));
      }
      final reason = _errorMessage(response);
      switch (response.statusCode) {
        case 503:
          return AssistantChatResult.failure(AssistantChatError.notConfigured,
              message: reason, statusCode: 503);
        case 400:
          return AssistantChatResult.failure(AssistantChatError.badRequest,
              message: reason, statusCode: 400);
        case 502:
          return AssistantChatResult.failure(AssistantChatError.upstreamFailed,
              message: reason, statusCode: 502);
        default:
          return AssistantChatResult.failure(AssistantChatError.serverError,
              message: reason, statusCode: response.statusCode);
      }
    } catch (e) {
      debugPrint('[Assistant] chat error: $e');
      return AssistantChatResult.failure(AssistantChatError.network,
          message: e.toString());
    }
  }

  /// Fetch active alert instances (`GET /api/alerts`).
  ///
  /// The server returns a JSON array of alertDTO (alert_handler.go). Pass
  /// [status] to filter (e.g. "firing", "acked") via the `status` query param;
  /// omit for all. Returns an empty list on failure.
  Future<List<AlertInstance>> fetchAlerts({String? status}) async {
    try {
      final uri = Uri.parse(_buildUrl('/alerts')).replace(
        queryParameters: {
          if (status != null && status.isNotEmpty) 'status': status,
        },
      );
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return data
              .whereType<Map<String, dynamic>>()
              .map(AlertInstance.fromJson)
              .toList();
        }
      }
      return const [];
    } catch (e) {
      debugPrint('[Alerts] fetch error: $e');
      return const [];
    }
  }

  /// Acknowledge a single alert (`POST /api/alerts/ack/:id`).
  /// Returns `null` on success, otherwise a human-readable error message.
  Future<String?> ackAlert(String id) async {
    try {
      final response = await _client
          .post(Uri.parse(_buildUrl('/alerts/ack/$id')), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) return null;
      return _errorMessage(response);
    } catch (e) {
      return e.toString();
    }
  }

  /// Acknowledge all firing alerts (`POST /api/alerts/ack-all`).
  /// Returns the number acked on success, or `null` on failure.
  Future<int?> ackAllAlerts() async {
    try {
      final response = await _client
          .post(Uri.parse(_buildUrl('/alerts/ack-all')), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['count'] as int? ?? 0;
      }
      return null;
    } catch (e) {
      debugPrint('[Alerts] ack-all error: $e');
      return null;
    }
  }

  /// Fetch the most recent audit log entries (`GET /api/audit/recent`).
  ///
  /// The server wraps the records as `{ "logs": [ ...AuditLog ] }`
  /// (audit.go GetRecentLogs); [limit] is capped server-side (max 500).
  /// Returns an empty list on failure.
  Future<List<AuditEntry>> fetchRecentAudit({int limit = 50}) async {
    try {
      final uri = Uri.parse(_buildUrl('/audit/recent')).replace(
        queryParameters: {'limit': '$limit'},
      );
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final logs = data is Map ? data['logs'] : data;
        if (logs is List) {
          return logs
              .whereType<Map<String, dynamic>>()
              .map(AuditEntry.fromJson)
              .toList();
        }
      }
      return const [];
    } catch (e) {
      debugPrint('[Audit] recent error: $e');
      return const [];
    }
  }

  /// Validate a device token against the server at add-time
  /// (`POST /api/auth/device`, device_handler.go AuthenticateDevice).
  ///
  /// Sends the token in the `X-Device-Token` header plus
  /// `{ deviceName, deviceType, deviceOs }` in the body (all required by the
  /// server's binding). On success returns [DeviceAuthResult.ok] = true with the
  /// granted `permissionLevel` and server name; on failure maps the status code
  /// (401 invalid, 403 disabled, 400 bad request) into [DeviceAuthResult.error].
  Future<DeviceAuthResult> validateDeviceToken(
    String token, {
    required String deviceName,
    required String deviceType,
    required String deviceOs,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse(_buildUrl('/auth/device')),
            headers: {
              'Content-Type': 'application/json',
              'X-Device-Token': token,
            },
            body: jsonEncode({
              'deviceName': deviceName,
              'deviceType': deviceType,
              'deviceOs': deviceOs,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final info = (data['serverInfo'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        return DeviceAuthResult(
          ok: true,
          permissionLevel: info['permissionLevel'] as int? ?? 0,
          serverName: info['name'] as String? ?? '',
          statusCode: 200,
        );
      }
      return DeviceAuthResult(
        ok: false,
        error: _errorMessage(response),
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('[Device] validate error: $e');
      return DeviceAuthResult(ok: false, error: e.toString());
    }
  }

  /// Generate a device pairing token + QR payload (`POST /api/devices/token`).
  /// Requires an account-authenticated (JWT) connection. Returns `null` on
  /// failure (e.g. device-token-only connections cannot generate codes).
  Future<DeviceTokenResult?> generateDeviceToken({String? serverName}) async {
    try {
      final response = await _client
          .post(
            Uri.parse(_buildUrl('/devices/token')),
            headers: _headers,
            body:
                jsonEncode({if (serverName != null) 'serverName': serverName}),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final qrData = data['qrData'] as String? ?? '';
        return DeviceTokenResult(
          qrData: qrData,
          pairingCode: data['pairingCode'] as String? ?? '',
          permissionLevel: data['permissionLevel'] as int? ?? 0,
          expiresAt: _qrExpiry(qrData),
        );
      }
      return null;
    } catch (e) {
      debugPrint('[Pairing] generate error: $e');
      return null;
    }
  }

  /// Decode the QR payload's `e` (Unix-seconds) expiry from a base64(JSON)
  /// [qrData] string. Returns null when the payload is unreadable or carries no
  /// expiry (the field is `omitempty` server-side).
  static DateTime? _qrExpiry(String qrData) {
    if (qrData.isEmpty) return null;
    try {
      final decoded = jsonDecode(utf8.decode(base64.decode(qrData)));
      if (decoded is Map) {
        final e = decoded['e'];
        if (e is num && e > 0) {
          return DateTime.fromMillisecondsSinceEpoch(e.toInt() * 1000);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Extract a readable error from a failed JSON response.
  String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map) {
        final err = body['error'] ?? body['details'];
        if (err is String && err.isNotEmpty) return err;
      }
    } catch (_) {}
    return 'HTTP ${response.statusCode}';
  }

  /// Fetch server summary
  Future<ServerSummary?> fetchSummary() async {
    try {
      final response = await _client
          .get(Uri.parse(_buildUrl('/summary')), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ServerSummary.fromJson(data);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Start polling for updates (called when WebSocket is unavailable)
  void _startPolling({Duration interval = const Duration(seconds: 2)}) {
    if (_wsConnected) return; // Don't poll if WebSocket is connected

    stopPolling();
    debugPrint('[HTTP] Starting polling mode');
    _emitConnectionStatus(true, ConnectionMode.httpPolling);
    _fetchAndEmit();
    _pollingTimer = Timer.periodic(interval, (_) => _fetchAndEmit());
  }

  /// Start real-time updates (tries WebSocket first, falls back to polling)
  void startPolling({Duration interval = const Duration(seconds: 2)}) {
    _useWebSocket = true;
    _connectWebSocket().then((_) {
      if (!_wsConnected) {
        _startPolling(interval: interval);
      }
    });
  }

  Future<void> _fetchAndEmit() async {
    try {
      final agents = await fetchAgents();
      _cachedAgents = agents;
      _agentsController.add(agents);

      final metrics = await fetchMetrics();
      _cachedMetrics = metrics;
      _metricsController.add(metrics);

      // Also fetch summary in polling mode
      final summary = await fetchSummary();
      if (summary != null) {
        _summaryController.add(summary);
      }

      _emitConnectionStatus(true, ConnectionMode.httpPolling);
    } catch (e) {
      _emitConnectionStatus(false, ConnectionMode.disconnected, e.toString());
    }
  }

  /// Stop polling
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Dispose resources
  void dispose() {
    _useWebSocket = false;
    stopPolling();
    _wsPingTimer?.cancel();
    _wsChannel?.sink.close();
    _agentsController.close();
    _metricsController.close();
    _connectionController.close();
    _summaryController.close();
    _agentOfflineController.close();
    _serverInfoController.close();
    _client.close();
  }
}
