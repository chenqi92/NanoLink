import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../services/server_service.dart';
import '../services/storage_service.dart';

/// Application state provider managing servers, agents and metrics
class AppProvider extends ChangeNotifier {
  final StorageService _storageService = StorageService();
  final Map<String, ServerService> _serverServices = {};
  final Uuid _uuid = const Uuid();

  List<ServerConnection> _servers = [];
  List<Agent> _allAgents = [];
  Map<String, AgentMetrics> _allMetrics = {};
  bool _isLoading = true;

  List<ServerConnection> get servers => _servers;
  List<Agent> get allAgents => _allAgents;
  Map<String, AgentMetrics> get allMetrics => _allMetrics;
  bool get isLoading => _isLoading;

  /// Initialize the provider
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    _servers = await _storageService.getServers();
    
    // Connect to all saved servers
    for (final server in _servers) {
      await _connectToServer(server);
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Add a new server connection
  Future<bool> addServer({
    required String name,
    required String url,
    String? token,
  }) async {
    final server = ServerConnection(
      id: _uuid.v4(),
      name: name,
      url: url,
      token: token,
    );

    // Test connection first
    final service = ServerService(connection: server);
    final connected = await service.testConnection();
    
    if (connected) {
      _servers.add(server.copyWith(isConnected: true, lastConnected: DateTime.now()));
      await _storageService.saveServers(_servers);
      await _connectToServer(server);
      notifyListeners();
      return true;
    }
    
    service.dispose();
    return false;
  }

  /// Connect to a server and start listening for updates
  Future<void> _connectToServer(ServerConnection server) async {
    final service = ServerService(connection: server);
    _serverServices[server.id] = service;

    // Listen for agents
    service.agentsStream.listen((agents) {
      _updateAgentsFromServer(server.id, agents);
    });

    // Listen for metrics
    service.metricsStream.listen((metrics) {
      _updateMetricsFromServer(metrics);
    });

    // Listen for connection status
    service.connectionStream.listen((connected) {
      _updateServerConnectionStatus(server.id, connected);
    });

    // Start polling
    service.startPolling();
  }

  void _updateAgentsFromServer(String serverId, List<Agent> agents) {
    // Remove old agents from this server
    _allAgents.removeWhere((a) => a.serverId == serverId);
    // Add new agents
    _allAgents.addAll(agents);
    notifyListeners();
  }

  void _updateMetricsFromServer(Map<String, AgentMetrics> metrics) {
    _allMetrics.addAll(metrics);
    notifyListeners();
  }

  void _updateServerConnectionStatus(String serverId, bool connected) {
    final index = _servers.indexWhere((s) => s.id == serverId);
    if (index != -1) {
      _servers[index] = _servers[index].copyWith(
        isConnected: connected,
        lastConnected: connected ? DateTime.now() : null,
      );
      notifyListeners();
    }
  }

  /// Remove a server connection
  Future<void> removeServer(String serverId) async {
    _serverServices[serverId]?.dispose();
    _serverServices.remove(serverId);
    _servers.removeWhere((s) => s.id == serverId);
    _allAgents.removeWhere((a) => a.serverId == serverId);
    await _storageService.saveServers(_servers);
    notifyListeners();
  }

  /// Get server name for an agent
  String getServerName(String serverId) {
    return _servers.firstWhere(
      (s) => s.id == serverId,
      orElse: () => ServerConnection(id: '', name: 'Unknown', url: ''),
    ).name;
  }

  @override
  void dispose() {
    for (final service in _serverServices.values) {
      service.dispose();
    }
    super.dispose();
  }
}
