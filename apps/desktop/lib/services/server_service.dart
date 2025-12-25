import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/models.dart';

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
        if (connection.token != null && connection.token!.isNotEmpty)
          'Authorization': 'Bearer ${connection.token}',
      };

  String _buildUrl(String path) {
    final baseUrl = connection.url.endsWith('/')
        ? connection.url.substring(0, connection.url.length - 1)
        : connection.url;
    return '$baseUrl/api$path';
  }

  String _buildWsUrl() {
    var baseUrl = connection.url.endsWith('/')
        ? connection.url.substring(0, connection.url.length - 1)
        : connection.url;

    // Convert http(s) to ws(s)
    if (baseUrl.startsWith('https://')) {
      baseUrl = 'wss://${baseUrl.substring(8)}';
    } else if (baseUrl.startsWith('http://')) {
      baseUrl = 'ws://${baseUrl.substring(7)}';
    }

    final token = connection.token ?? '';
    return '$baseUrl/ws/dashboard?token=${Uri.encodeComponent(token)}';
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

      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));

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
