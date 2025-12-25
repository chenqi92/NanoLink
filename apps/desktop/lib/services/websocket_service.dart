import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/models.dart';

/// WebSocket service for real-time dashboard updates
class WebSocketService {
  final String wsUrl;
  final String? token;
  final void Function(List<Agent>)? onAgents;
  final void Function(Map<String, AgentMetrics>)? onMetrics;
  final void Function(String agentId)? onAgentOffline;
  final void Function(bool connected)? onConnectionChange;

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isConnected = false;
  bool _intentionalDisconnect = false;

  WebSocketService({
    required this.wsUrl,
    this.token,
    this.onAgents,
    this.onMetrics,
    this.onAgentOffline,
    this.onConnectionChange,
  });

  bool get isConnected => _isConnected;

  /// Connect to WebSocket server
  Future<void> connect() async {
    if (_isConnected) return;
    _intentionalDisconnect = false;

    try {
      final uri = Uri.parse('$wsUrl?token=${Uri.encodeComponent(token ?? '')}');
      debugPrint('[WS] Connecting to $wsUrl');
      
      _channel = WebSocketChannel.connect(uri);
      
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
      );

      _isConnected = true;
      onConnectionChange?.call(true);

      // Start ping timer
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _sendPing();
      });

      debugPrint('[WS] Connected successfully');
    } catch (e) {
      debugPrint('[WS] Connection error: $e');
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic data) {
    try {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      final type = msg['type'] as String?;
      final payload = msg['data'];

      switch (type) {
        case 'agents':
          if (onAgents != null && payload is List) {
            final agents = payload
                .map((j) => Agent.fromJson(j as Map<String, dynamic>, ''))
                .toList();
            onAgents!(agents);
          }

        case 'metrics':
          if (onMetrics != null && payload is Map) {
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
            
            onMetrics!(metricsMap);
          }

        case 'agent_offline':
          if (onAgentOffline != null && payload is String) {
            onAgentOffline!(payload);
          }

        case 'pong':
          // Heartbeat response, connection is alive
          break;
      }
    } catch (e) {
      debugPrint('[WS] Message parse error: $e');
    }
  }

  void _onError(Object error) {
    debugPrint('[WS] Error: $error');
    _isConnected = false;
    onConnectionChange?.call(false);
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('[WS] Connection closed');
    _isConnected = false;
    onConnectionChange?.call(false);
    _pingTimer?.cancel();

    if (!_intentionalDisconnect) {
      _scheduleReconnect();
    }
  }

  void _sendPing() {
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode({
          'type': 'ping',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }));
      } catch (e) {
        debugPrint('[WS] Ping error: $e');
      }
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (!_intentionalDisconnect) {
      _reconnectTimer = Timer(const Duration(seconds: 3), () {
        debugPrint('[WS] Attempting reconnect...');
        connect();
      });
    }
  }

  /// Disconnect from WebSocket server
  void disconnect() {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    onConnectionChange?.call(false);
    debugPrint('[WS] Disconnected');
  }

  /// Dispose resources
  void dispose() {
    disconnect();
  }
}
