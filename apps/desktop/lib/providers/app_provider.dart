import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../services/notification_service.dart';
import '../services/server_service.dart';
import '../services/storage_service.dart';

/// A critical alert pending a notification decision.
class _PendingAlert {
  final String category; // offline | high | disk
  final String title;
  final String body;
  const _PendingAlert(this.category, this.title, this.body);
}

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
  final NotificationService _notifications = NotificationService();
  final Map<String, ServerService> _serverServices = {};
  final Uuid _uuid = const Uuid();

  // Notification preferences (persisted) + alert-dedup state.
  static const _kNotifyOffline = 'notify_offline';
  static const _kNotifyHigh = 'notify_high';
  static const _kNotifyDisk = 'notify_disk';
  bool notifyOffline = true;
  bool notifyHigh = true;
  bool notifyDisk = true;
  final Set<String> _activeAlerts = {};
  bool _alertsSeeded = false;

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

  /// Update a notification preference and persist it.
  Future<void> setNotifyPref(String key, bool value) async {
    switch (key) {
      case _kNotifyOffline:
        notifyOffline = value;
      case _kNotifyHigh:
        notifyHigh = value;
      case _kNotifyDisk:
        notifyDisk = value;
    }
    await _storageService.setBool(key, value);
    notifyListeners();
  }

  /// Initialize the provider
  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    notifyOffline = await _storageService.getBool(_kNotifyOffline);
    notifyHigh = await _storageService.getBool(_kNotifyHigh);
    notifyDisk = await _storageService.getBool(_kNotifyDisk);
    await _notifications.init();

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
    _evaluateAlerts();
    notifyListeners();
  }

  void _updateMetricsFromServer(Map<String, AgentMetrics> metrics) {
    _allMetrics.addAll(metrics);
    _evaluateAlerts();
    notifyListeners();
  }

  /// Detect newly-appeared critical alert conditions across all agents and fire
  /// a local notification for each (honoring the per-category toggles). The
  /// first pass only seeds the active set so existing alerts don't all fire on
  /// launch.
  void _evaluateAlerts() {
    final current = <String, _PendingAlert>{};
    for (final a in _allAgents) {
      final host = a.hostname;
      if (!a.isOnline) {
        current['offline:${a.id}'] = _PendingAlert(
          'offline',
          tr('alerts.nodeOffline', namedArgs: {'host': host}),
          tr('alerts.nodeOfflineDetail'),
        );
        continue;
      }
      final m = _allMetrics[a.id];
      if (m == null) continue;
      if (m.cpuPercent > 90) {
        current['cpu:${a.id}'] = _PendingAlert(
          'high',
          tr('alerts.cpuPressure', namedArgs: {'host': host}),
          tr('alerts.usageDetail',
              namedArgs: {'value': m.cpuPercent.toStringAsFixed(0)}),
        );
      }
      if (m.memoryPercent > 90) {
        current['mem:${a.id}'] = _PendingAlert(
          'high',
          tr('alerts.memPressure', namedArgs: {'host': host}),
          tr('alerts.usageDetail',
              namedArgs: {'value': m.memoryPercent.toStringAsFixed(0)}),
        );
      }
      for (final d in m.disks) {
        if (d.usagePercent > 90) {
          current['disk:${a.id}:${d.mountPoint}'] = _PendingAlert(
            'disk',
            tr('alerts.diskFull', namedArgs: {'host': host}),
            tr('alerts.diskDetail', namedArgs: {
              'mount': d.mountPoint,
              'value': d.usagePercent.toStringAsFixed(0)
            }),
          );
        }
      }
    }

    if (!_alertsSeeded) {
      _activeAlerts
        ..clear()
        ..addAll(current.keys);
      _alertsSeeded = true;
      return;
    }

    for (final entry in current.entries) {
      if (_activeAlerts.contains(entry.key)) continue;
      final p = entry.value;
      final enabled = switch (p.category) {
        'offline' => notifyOffline,
        'disk' => notifyDisk,
        _ => notifyHigh,
      };
      if (enabled) _notifications.show(entry.key, p.title, p.body);
    }
    _activeAlerts
      ..clear()
      ..addAll(current.keys);
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
