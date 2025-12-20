import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';

/// Service for communicating with NanoLink servers
class ServerService {
  final ServerConnection connection;
  final http.Client _client;
  Timer? _pollingTimer;
  
  final StreamController<List<Agent>> _agentsController =
      StreamController<List<Agent>>.broadcast();
  final StreamController<Map<String, AgentMetrics>> _metricsController =
      StreamController<Map<String, AgentMetrics>>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Stream<List<Agent>> get agentsStream => _agentsController.stream;
  Stream<Map<String, AgentMetrics>> get metricsStream => _metricsController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;

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

  /// Fetch agents from server
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

  /// Fetch metrics for all agents
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

  /// Start polling for updates
  void startPolling({Duration interval = const Duration(seconds: 2)}) {
    stopPolling();
    _fetchAndEmit();
    _pollingTimer = Timer.periodic(interval, (_) => _fetchAndEmit());
    _connectionController.add(true);
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
    stopPolling();
    _agentsController.close();
    _metricsController.close();
    _connectionController.close();
    _client.close();
  }
}
