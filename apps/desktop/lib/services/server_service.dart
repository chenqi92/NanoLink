import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/models.dart';

/// Service for communicating with NanoLink servers using WebSocket + HTTP fallback
class ServerService {
  final ServerConnection connection;
  final http.Client _client;
  Timer? _pollingTimer;
  WebSocketChannel? _wsChannel;
  bool _wsConnected = false;
  bool _useWebSocket = true;
  Timer? _wsPingTimer;

  final StreamController<List<Agent>> _agentsController =
      StreamController<List<Agent>>.broadcast();
  final StreamController<Map<String, AgentMetrics>> _metricsController =
      StreamController<Map<String, AgentMetrics>>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Stream<List<Agent>> get agentsStream => _agentsController.stream;
  Stream<Map<String, AgentMetrics>> get metricsStream => _metricsController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;
  bool get isWebSocketConnected => _wsConnected;

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
      _connectionController.add(true);

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

  void _onWsMessage(dynamic data) {
    try {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      final type = msg['type'] as String?;
      final payload = msg['data'];

      switch (type) {
        case 'agents':
          if (payload is List) {
            final agents = payload
                .map((j) => Agent.fromJson(j as Map<String, dynamic>, connection.id))
                .toList();
            _agentsController.add(agents);
          }

        case 'metrics':
          if (payload is Map) {
            final metricsMap = <String, AgentMetrics>{};

            // Check if single agent update or full update
            if (payload.containsKey('agentId') && payload.containsKey('metrics')) {
              final agentId = payload['agentId'] as String;
              final metricsData = payload['metrics'] as Map<String, dynamic>;
              metricsMap[agentId] = AgentMetrics.fromJson(metricsData, agentId);
            } else {
              payload.forEach((key, value) {
                if (value != null && value is Map<String, dynamic>) {
                  metricsMap[key as String] = AgentMetrics.fromJson(value, key);
                }
              });
            }

            _metricsController.add(metricsMap);
          }

        case 'agent_offline':
          // Handle agent offline - emit empty list update
          debugPrint('[WS] Agent offline: $payload');

        case 'pong':
          // Heartbeat response
          break;
      }
    } catch (e) {
      debugPrint('[WS] Message parse error: $e');
    }
  }

  void _onWsError(Object error) {
    debugPrint('[WS] Error: $error');
    _wsConnected = false;
    _connectionController.add(false);
    _startPolling();
  }

  void _onWsDone() {
    debugPrint('[WS] Connection closed');
    _wsConnected = false;
    _wsPingTimer?.cancel();
    _connectionController.add(false);
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
      _connectionController.add(false);
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

  /// Start polling for updates (called when WebSocket is unavailable)
  void _startPolling({Duration interval = const Duration(seconds: 2)}) {
    if (_wsConnected) return; // Don't poll if WebSocket is connected

    stopPolling();
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
      _agentsController.add(agents);

      final metrics = await fetchMetrics();
      _metricsController.add(metrics);

      _connectionController.add(true);
    } catch (e) {
      _connectionController.add(false);
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
    _client.close();
  }
}
