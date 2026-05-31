import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/models.dart';
import 'shell_session.dart';
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
  });

  bool get isEmpty => cpu.isEmpty;
  bool get hasGpu => gpuUsage.any((v) => v > 0) && gpuUsage.isNotEmpty;

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
    var anyGpuTemp = false;

    double n(dynamic v) => (v as num?)?.toDouble() ?? 0;
    const mb = 1000000.0;

    for (final e in raw) {
      if (e is! Map) continue;
      final m = e.cast<String, dynamic>();

      times.add(_parseTime(m['timestamp']));

      cpu.add(n((m['cpu'] as Map?)?['usagePercent']));

      final memMap = (m['memory'] as Map?) ?? const {};
      final total = n(memMap['total']);
      final used = n(memMap['used']);
      mem.add(total > 0 ? (used / total * 100).clamp(0, 100).toDouble() : 0);

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
  Stream<Map<String, AgentMetrics>> get metricsStream => _metricsController.stream;
  Stream<ConnectionStatus> get connectionStream => _connectionController.stream;
  Stream<ServerSummary> get summaryStream => _summaryController.stream;
  Stream<String> get agentOfflineStream => _agentOfflineController.stream;
  Stream<ServerInfo> get serverInfoStream => _serverInfoController.stream;

  ServerInfo? _serverInfo;

  bool get isWebSocketConnected => _wsConnected;
  ConnectionMode get connectionMode => _wsConnected
      ? ConnectionMode.websocket
      : (_pollingTimer != null ? ConnectionMode.httpPolling : ConnectionMode.disconnected);

  /// Get cached server info (available after WebSocket connection)
  ServerInfo? get serverInfo => _serverInfo;

  /// Check if connected to a compatible server
  bool get isCompatibleServer =>
      _serverInfo == null || _serverInfo!.isCompatible(clientVersion);

  ServerService({required this.connection, http.Client? client})
      : _client = client ?? http.Client();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (connection.authToken != null && connection.authToken!.isNotEmpty)
          'Authorization': 'Bearer ${connection.authToken}',
      };

  String _buildUrl(String path) {
    final baseUrl = connection.url.endsWith('/')
        ? connection.url.substring(0, connection.url.length - 1)
        : connection.url;
    return '$baseUrl/api$path';
  }

  /// `ws(s)://host[:port]` base derived from the configured HTTP url.
  String _wsBaseUrl() {
    var baseUrl = connection.url.endsWith('/')
        ? connection.url.substring(0, connection.url.length - 1)
        : connection.url;

    // Convert http(s) to ws(s)
    if (baseUrl.startsWith('https://')) {
      baseUrl = 'wss://${baseUrl.substring(8)}';
    } else if (baseUrl.startsWith('http://')) {
      baseUrl = 'ws://${baseUrl.substring(7)}';
    }
    return baseUrl;
  }

  String _buildWsUrl() {
    final token = connection.authToken ?? '';
    return '${_wsBaseUrl()}/ws/dashboard?token=${Uri.encodeComponent(token)}';
  }

  /// Open a remote shell session for [agentId] (`/ws/shell/:id`).
  ///
  /// The returned session is not connected yet — wire up its [ShellSession.lines]
  /// / [ShellSession.statusStream] listeners first, then call
  /// [ShellSession.connect]. Auth uses the Authorization header on native (the
  /// query token is kept only for web/cookie fallback).
  ShellSession openShell(String agentId) {
    final token = connection.authToken ?? '';
    final uri = Uri.parse(
        '${_wsBaseUrl()}/ws/shell/${Uri.encodeComponent(agentId)}'
        '?token=${Uri.encodeComponent(token)}');
    return ShellSession(uri: uri, token: connection.authToken);
  }

  /// Login with username and password, returns JWT token on success
  Future<String?> login(String username, String password) async {
    try {
      final response = await _client.post(
        Uri.parse(_buildUrl('/auth/login')),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 10));

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
          token: connection.authToken);

      _wsChannel!.stream.listen(
        _onWsMessage,
        onError: _onWsError,
        onDone: _onWsDone,
      );

      _wsConnected = true;
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

  void _emitConnectionStatus(bool connected, ConnectionMode mode, [String? error]) {
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
                .map((j) => Agent.fromJson(j as Map<String, dynamic>, connection.id))
                .toList();
            _agentsController.add(_cachedAgents);
          }

        case 'agent_update':
          // Handle single agent update
          if (payload is Map<String, dynamic>) {
            final updatedAgent = Agent.fromJson(payload, connection.id);
            final index = _cachedAgents.indexWhere((a) => a.id == updatedAgent.id);
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
            if (payload.containsKey('agentId') && payload.containsKey('metrics')) {
              final agentId = payload['agentId'] as String;
              final metricsData = payload['metrics'] as Map<String, dynamic>;
              _cachedMetrics[agentId] = AgentMetrics.fromJson(metricsData, agentId);
            } else {
              // Full metrics update
              payload.forEach((key, value) {
                if (value != null && value is Map<String, dynamic>) {
                  _cachedMetrics[key as String] = AgentMetrics.fromJson(value, key);
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
            debugPrint('[WS] Summary updated: ${summary.connectedAgents} agents');
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
            .map((json) => Agent.fromJson(json as Map<String, dynamic>, connection.id))
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
      final response =
          await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) return MetricsHistory.parse(data);
        return const MetricsHistory(
          times: [], cpu: [], mem: [], netRx: [], netTx: [],
          diskRead: [], diskWrite: [], gpuUsage: [], gpuTemp: [],
        );
      }
      return null;
    } catch (e) {
      debugPrint('[History] fetch error: $e');
      return null;
    }
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
