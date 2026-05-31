import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../services/server_service.dart';
import '../services/storage_service.dart';

/// Extended server connection with connection mode info
class ServerConnectionState {
  final ServerConnection connection;
  final ConnectionMode connectionMode;
  final DateTime? lastUpdate;
  final String? error;

  ServerConnectionState({
    required this.connection,
    this.connectionMode = ConnectionMode.disconnected,
    this.lastUpdate,
    this.error,
  });

  bool get isConnected => connection.isConnected;
  String get id => connection.id;
  String get name => connection.name;

  ServerConnectionState copyWith({
    ServerConnection? connection,
    ConnectionMode? connectionMode,
    DateTime? lastUpdate,
    String? error,
  }) {
    return ServerConnectionState(
      connection: connection ?? this.connection,
      connectionMode: connectionMode ?? this.connectionMode,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      error: error,
    );
  }
}

/// Application state provider managing servers, agents and metrics
class AppProvider extends ChangeNotifier {
  final StorageService _storageService = StorageService();
  final Map<String, ServerService> _serverServices = {};
  final Uuid _uuid = const Uuid();

  List<ServerConnection> _servers = [];
  Map<String, ConnectionMode> _connectionModes = {};
  List<Agent> _allAgents = [];
  Map<String, AgentMetrics> _allMetrics = {};
  Map<String, ServerSummary> _serverSummaries = {};
  bool _isLoading = true;
  String? _activeServerId;

  List<ServerConnection> get servers => _servers;
  List<Agent> get allAgents => _allAgents;
  Map<String, AgentMetrics> get allMetrics => _allMetrics;
  Map<String, ServerSummary> get serverSummaries => _serverSummaries;
  bool get isLoading => _isLoading;

  /// Currently focused server (defaults to the first one). The new mobile
  /// design exposes a server switcher; screens scope their data to this server.
  String? get activeServerId {
    if (_activeServerId != null &&
        _servers.any((s) => s.id == _activeServerId)) {
      return _activeServerId;
    }
    return _servers.isNotEmpty ? _servers.first.id : null;
  }

  ServerConnection? get activeServer {
    final id = activeServerId;
    if (id == null) return null;
    for (final s in _servers) {
      if (s.id == id) return s;
    }
    return null;
  }

  void setActiveServer(String serverId) {
    _activeServerId = serverId;
    notifyListeners();
  }

  /// Agents that belong to [serverId] (or the active server when null).
  List<Agent> agentsForServer([String? serverId]) {
    final id = serverId ?? activeServerId;
    if (id == null) return const [];
    return _allAgents.where((a) => a.serverId == id).toList();
  }

  /// Connection mode of the active server.
  ConnectionMode get activeConnectionMode =>
      getConnectionMode(activeServerId ?? '');

  AgentMetrics? metricsFor(String agentId) => _allMetrics[agentId];

  Agent? agentById(String agentId) {
    for (final a in _allAgents) {
      if (a.id == agentId) return a;
    }
    return null;
  }

  /// The live [ServerService] for a given server connection, if connected.
  ServerService? serviceForServer(String serverId) => _serverServices[serverId];

  /// The live [ServerService] that owns [agentId] (used for remote shell, etc.).
  ServerService? serviceForAgent(String agentId) {
    final agent = agentById(agentId);
    if (agent == null) return null;
    return _serverServices[agent.serverId];
  }

  /// Get connection mode for a server
  ConnectionMode getConnectionMode(String serverId) {
    return _connectionModes[serverId] ?? ConnectionMode.disconnected;
  }

  /// Check if any server is using WebSocket
  bool get hasWebSocketConnection {
    return _connectionModes.values.contains(ConnectionMode.websocket);
  }

  /// Check if any server is using HTTP polling
  bool get hasPollingConnection {
    return _connectionModes.values.contains(ConnectionMode.httpPolling);
  }

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

  /// Add a new server connection using username/password credentials
  Future<bool> addServerWithCredentials({
    required String name,
    required String url,
    required String username,
    required String password,
  }) async {
    final server = ServerConnection(
      id: _uuid.v4(),
      name: name,
      url: url,
      username: username,
    );

    // Test connection with login
    final service = ServerService(connection: server);
    final token = await service.login(username, password);

    if (token != null) {
      _servers.add(server.copyWith(
        isConnected: true,
        lastConnected: DateTime.now(),
        userToken: token,
      ));
      await _storageService.saveServers(_servers);
      await _connectToServer(server.copyWith(userToken: token));
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

    // Listen for connection status (now includes mode)
    service.connectionStream.listen((status) {
      _updateServerConnectionStatus(server.id, status);
    });

    // Listen for agent offline events
    service.agentOfflineStream.listen((agentId) {
      _handleAgentOffline(agentId);
    });

    // Listen for summary updates
    service.summaryStream.listen((summary) {
      _updateServerSummary(server.id, summary);
    });

    // Start polling (will try WebSocket first)
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

  void _updateServerConnectionStatus(String serverId, ConnectionStatus status) {
    final index = _servers.indexWhere((s) => s.id == serverId);
    if (index != -1) {
      _servers[index] = _servers[index].copyWith(
        isConnected: status.isConnected,
        lastConnected: status.isConnected ? DateTime.now() : null,
      );
      _connectionModes[serverId] = status.mode;
      notifyListeners();
    }
  }

  void _handleAgentOffline(String agentId) {
    _allAgents.removeWhere((a) => a.id == agentId);
    _allMetrics.remove(agentId);
    notifyListeners();
    debugPrint('[AppProvider] Agent removed: $agentId');
  }

  void _updateServerSummary(String serverId, ServerSummary summary) {
    _serverSummaries[serverId] = summary;
    notifyListeners();
  }

  /// Remove a server connection
  Future<void> removeServer(String serverId) async {
    _serverServices[serverId]?.dispose();
    _serverServices.remove(serverId);
    _servers.removeWhere((s) => s.id == serverId);
    _allAgents.removeWhere((a) => a.serverId == serverId);
    _connectionModes.remove(serverId);
    _serverSummaries.remove(serverId);
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

  /// Get total summary across all servers
  ServerSummary get totalSummary {
    if (_serverSummaries.isEmpty) {
      return ServerSummary(connectedAgents: _allAgents.length);
    }

    int totalAgents = 0;
    double totalCpu = 0;
    double totalMem = 0;
    int totalAlerts = 0;

    for (final summary in _serverSummaries.values) {
      totalAgents += summary.connectedAgents;
      totalCpu += summary.avgCpuUsage;
      totalMem += summary.avgMemoryUsage;
      totalAlerts += summary.totalAlerts;
    }

    final count = _serverSummaries.length;
    return ServerSummary(
      connectedAgents: totalAgents,
      avgCpuUsage: count > 0 ? totalCpu / count : 0,
      avgMemoryUsage: count > 0 ? totalMem / count : 0,
      totalAlerts: totalAlerts,
    );
  }

  @override
  void dispose() {
    for (final service in _serverServices.values) {
      service.dispose();
    }
    super.dispose();
  }
}
