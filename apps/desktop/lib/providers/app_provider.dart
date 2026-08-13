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

  /// True when the server rejected our credentials/token (401/expiry) and the
  /// connection needs the user to re-authenticate (no usable saved secret to
  /// silently recover with).
  final bool needsReauth;

  ServerConnectionState({
    required this.connection,
    this.connectionMode = ConnectionMode.disconnected,
    this.lastUpdate,
    this.error,
    this.needsReauth = false,
  });

  bool get isConnected => connection.isConnected;
  String get id => connection.id;
  String get name => connection.name;

  ServerConnectionState copyWith({
    ServerConnection? connection,
    ConnectionMode? connectionMode,
    DateTime? lastUpdate,
    String? error,
    bool? needsReauth,
  }) {
    return ServerConnectionState(
      connection: connection ?? this.connection,
      connectionMode: connectionMode ?? this.connectionMode,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      error: error,
      needsReauth: needsReauth ?? this.needsReauth,
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
  final Map<String, ConnectionMode> _connectionModes = {};
  final List<Agent> _allAgents = [];
  final Map<String, AgentMetrics> _allMetrics = {};
  final Map<String, ServerSummary> _serverSummaries = {};
  bool _isLoading = true;
  String? _activeServerId;

  // Server-sourced alert/audit feeds, cached per server id. These come from the
  // server's real alert engine + audit log (distinct from the client-derived
  // _evaluateAlerts path which only drives local push notifications).
  final Map<String, List<AlertInstance>> _serverAlerts = {};
  final Map<String, List<AuditEntry>> _recentActivity = {};

  // Servers whose token/credentials the server rejected (401/expiry) and which
  // could not be silently recovered. UI should prompt the user to re-auth.
  final Set<String> _needsReauth = {};

  // Transient (in-memory only, never persisted) account passwords captured at
  // add/login time, used to silently re-login on token expiry. Cleared on
  // removeServer/dispose.
  final Map<String, String> _sessionPasswords = {};

  // De-dupes concurrent re-auth attempts per server.
  final Set<String> _reauthInFlight = {};

  List<ServerConnection> get servers => _servers;
  List<Agent> get allAgents => _allAgents;
  Map<String, AgentMetrics> get allMetrics => _allMetrics;
  Map<String, ServerSummary> get serverSummaries => _serverSummaries;
  bool get isLoading => _isLoading;

  /// Cached server-sourced alerts for [serverId] (or the active server when
  /// null). Empty until [fetchServerAlerts] has run for that server.
  List<AlertInstance> serverAlerts([String? serverId]) {
    final id = serverId ?? activeServerId;
    if (id == null) return const [];
    return _serverAlerts[id] ?? const [];
  }

  /// Cached recent audit entries for [serverId] (or the active server when
  /// null). Empty until [fetchRecentActivity] has run for that server.
  List<AuditEntry> recentActivity([String? serverId]) {
    final id = serverId ?? activeServerId;
    if (id == null) return const [];
    return _recentActivity[id] ?? const [];
  }

  /// Count of unacknowledged server-sourced alerts for [serverId] (active when
  /// null).
  int unackedAlertCount([String? serverId]) =>
      serverAlerts(serverId).where((a) => !a.acked).length;

  /// Whether [serverId] (active when null) needs the user to re-authenticate
  /// (token/credentials rejected and not silently recoverable).
  bool needsReauth([String? serverId]) {
    final id = serverId ?? activeServerId;
    if (id == null) return false;
    return _needsReauth.contains(id);
  }

  /// Whether any connected server currently needs re-authentication.
  bool get hasReauthNeeded => _needsReauth.isNotEmpty;

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

  /// Add a new server connection.
  ///
  /// [forceTls] upgrades an `http://` url to `https://` (and `ws://`→`wss://`)
  /// when building requests; [ignoreCert] accepts self-signed / invalid TLS
  /// certificates for this connection only (no process-wide override; web
  /// no-op). Both default to false.
  Future<bool> addServer({
    required String name,
    required String url,
    String? token,
    bool forceTls = false,
    bool ignoreCert = false,
  }) async {
    final server = ServerConnection(
      id: _uuid.v4(),
      name: name,
      url: url,
      token: token,
      forceTls: forceTls,
      ignoreCert: ignoreCert,
    );

    // Validate the connection. When a device token is supplied (QR / manual
    // token), authenticate it against /api/auth/device so an invalid or
    // disabled token fails at add-time. The no-token path falls back to the
    // public /health check.
    final service = ServerService(connection: server);
    final bool connected;
    if (token != null && token.isNotEmpty) {
      final auth = await service.validateDeviceToken(
        token,
        deviceName: name.isNotEmpty ? name : _deviceName,
        deviceType: _deviceType,
        deviceOs: _deviceOs,
      );
      connected = auth.ok;
    } else {
      connected = await service.testConnection();
    }

    if (connected) {
      _servers.add(
          server.copyWith(isConnected: true, lastConnected: DateTime.now()));
      await _storageService.saveServers(_servers);
      await _connectToServer(server);
      notifyListeners();
      return true;
    }

    service.dispose();
    return false;
  }

  /// A human-readable name for this client device (used when registering a
  /// device token with the server).
  String get _deviceName {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android device';
      case TargetPlatform.iOS:
        return 'iOS device';
      case TargetPlatform.macOS:
        return 'macOS device';
      case TargetPlatform.windows:
        return 'Windows device';
      case TargetPlatform.linux:
        return 'Linux device';
      default:
        return 'NanoOps client';
    }
  }

  /// Coarse device type for device-token registration ("mobile" | "desktop").
  String get _deviceType {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return 'mobile';
      default:
        return 'desktop';
    }
  }

  /// OS label for device-token registration.
  String get _deviceOs {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.iOS:
        return 'iOS';
      case TargetPlatform.macOS:
        return 'macOS';
      case TargetPlatform.windows:
        return 'Windows';
      case TargetPlatform.linux:
        return 'Linux';
      default:
        return 'Unknown';
    }
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
      // Keep the password in memory (only) so a later token expiry can recover
      // silently; it is never persisted.
      _sessionPasswords[server.id] = password;
      await _storageService.saveServers(_servers);
      await _connectToServer(server.copyWith(userToken: token));
      notifyListeners();
      return true;
    }

    service.dispose();
    return false;
  }

  /// Add a new server connection using a 6-digit pairing code.
  ///
  /// Exchanges the code for a device token via the server's `/api/auth/pairing`
  /// endpoint, then saves and connects exactly like a token connection.
  Future<bool> addServerWithPairingCode({
    required String name,
    required String url,
    required String pairingCode,
  }) async {
    final server = ServerConnection(
      id: _uuid.v4(),
      name: name,
      url: url,
    );

    final service = ServerService(connection: server);
    final token = await service.redeemPairingCode(pairingCode);

    if (token != null) {
      _servers.add(server.copyWith(
        isConnected: true,
        lastConnected: DateTime.now(),
        token: token,
      ));
      await _storageService.saveServers(_servers);
      await _connectToServer(server.copyWith(token: token));
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

  /// Fetch the server's real alert instances for [serverId] (active when null)
  /// and cache them for screens. Optionally filter by [status] (e.g. "firing").
  /// Returns the fetched list (also cached + notified).
  Future<List<AlertInstance>> fetchServerAlerts({
    String? serverId,
    String? status,
  }) async {
    final id = serverId ?? activeServerId;
    if (id == null) return const [];
    final service = _serverServices[id];
    if (service == null) return _serverAlerts[id] ?? const [];

    final alerts = await service.fetchAlerts(status: status);
    _serverAlerts[id] = alerts;
    notifyListeners();
    return alerts;
  }

  /// Fetch the most recent audit entries for [serverId] (active when null) and
  /// cache them for screens. Returns the fetched list (also cached + notified).
  Future<List<AuditEntry>> fetchRecentActivity({
    String? serverId,
    int limit = 50,
  }) async {
    final id = serverId ?? activeServerId;
    if (id == null) return const [];
    final service = _serverServices[id];
    if (service == null) return _recentActivity[id] ?? const [];

    final entries = await service.fetchRecentAudit(limit: limit);
    _recentActivity[id] = entries;
    notifyListeners();
    return entries;
  }

  /// Acknowledge a single server alert. On success refreshes the cached alert
  /// list for that server. Returns null on success, else an error message.
  Future<String?> acknowledgeAlert(String alertId, {String? serverId}) async {
    final id = serverId ?? activeServerId;
    if (id == null) return 'errors.noActiveServer'.tr();
    final service = _serverServices[id];
    if (service == null) return 'errors.serverNotConnected'.tr();

    final err = await service.ackAlert(alertId);
    if (err == null) {
      await fetchServerAlerts(serverId: id);
    }
    return err;
  }

  /// Acknowledge all firing alerts on [serverId] (active when null). On success
  /// refreshes the cached alert list. Returns the number acked, or null on
  /// failure.
  Future<int?> acknowledgeAllAlerts({String? serverId}) async {
    final id = serverId ?? activeServerId;
    if (id == null) return null;
    final service = _serverServices[id];
    if (service == null) return null;

    final count = await service.ackAllAlerts();
    if (count != null) {
      await fetchServerAlerts(serverId: id);
    }
    return count;
  }

  void _updateServerConnectionStatus(String serverId, ConnectionStatus status) {
    final index = _servers.indexWhere((s) => s.id == serverId);
    if (index != -1) {
      _servers[index] = _servers[index].copyWith(
        isConnected: status.isConnected,
        lastConnected: status.isConnected ? DateTime.now() : null,
      );
      _connectionModes[serverId] = status.mode;

      // A live connection means our token/credentials are currently accepted.
      if (status.isConnected && _needsReauth.remove(serverId)) {
        // needs-reauth cleared
      }

      // Detect auth-class failures and attempt silent recovery / surface
      // needs-reauth. Only react to auth-shaped errors to avoid treating
      // ordinary transient network drops as token expiry.
      if (!status.isConnected && _looksLikeAuthFailure(status.error)) {
        _handleAuthFailure(serverId);
      }

      notifyListeners();
    }
  }

  /// True when [error] looks like an authentication/authorization rejection
  /// (401/403/expired token) rather than a generic transport failure.
  bool _looksLikeAuthFailure(String? error) {
    if (error == null || error.isEmpty) return false;
    final e = error.toLowerCase();
    return e.contains('401') ||
        e.contains('403') ||
        e.contains('unauthorized') ||
        e.contains('forbidden') ||
        e.contains('invalid token') ||
        e.contains('token expired') ||
        e.contains('expired token');
  }

  /// Handle an auth-class connection failure for [serverId]: try to silently
  /// re-login with an in-memory password (if available) and reconnect; when no
  /// usable secret exists, mark the server as needing re-authentication.
  Future<void> _handleAuthFailure(String serverId) async {
    if (_reauthInFlight.contains(serverId)) return;
    _reauthInFlight.add(serverId);
    try {
      final reconnected = await _attemptReauth(serverId);
      if (!reconnected) {
        _needsReauth.add(serverId);
        notifyListeners();
      }
    } finally {
      _reauthInFlight.remove(serverId);
    }
  }

  /// Try to recover a rejected connection by re-logging in with the transient
  /// in-memory password for that server's account. Returns true if a fresh
  /// token was obtained and the connection was re-established.
  ///
  /// Never persists or reads a plaintext password; only an in-memory session
  /// password (captured at login time) is used. Token-only / pairing
  /// connections, or accounts whose password we don't hold this session, return
  /// false so the UI can prompt for re-auth.
  Future<bool> _attemptReauth(String serverId) async {
    final index = _servers.indexWhere((s) => s.id == serverId);
    if (index == -1) return false;
    final server = _servers[index];
    final username = server.username;
    final password = _sessionPasswords[serverId];
    if (username == null || username.isEmpty || password == null) {
      return false;
    }

    final service = _serverServices[serverId];
    if (service == null) return false;

    final result = await service.loginDetailed(username, password);
    if (!result.ok || result.token == null) {
      // Stored session password no longer valid; drop it so we don't retry.
      if (result.error == LoginError.invalidCredentials) {
        _sessionPasswords.remove(serverId);
      }
      return false;
    }

    // Swap in the refreshed JWT and reconnect with a new service instance.
    final refreshed = server.copyWith(userToken: result.token);
    _servers[index] = refreshed;
    await _storageService.saveServers(_servers);

    _serverServices[serverId]?.dispose();
    _serverServices.remove(serverId);
    _needsReauth.remove(serverId);
    await _connectToServer(refreshed);
    notifyListeners();
    return true;
  }

  /// Re-authenticate [serverId] with freshly-entered credentials (UI-driven,
  /// e.g. from a needs-reauth prompt). Captures the password in memory for this
  /// session so future token expiries can recover silently. Returns true on
  /// success.
  Future<bool> reauthenticate({
    required String serverId,
    required String username,
    required String password,
  }) async {
    final index = _servers.indexWhere((s) => s.id == serverId);
    if (index == -1) return false;
    final service =
        _serverServices[serverId] ?? ServerService(connection: _servers[index]);

    final result = await service.loginDetailed(username, password);
    if (!result.ok || result.token == null) return false;

    _sessionPasswords[serverId] = password;
    final refreshed =
        _servers[index].copyWith(username: username, userToken: result.token);
    _servers[index] = refreshed;
    await _storageService.saveServers(_servers);

    _serverServices[serverId]?.dispose();
    _serverServices.remove(serverId);
    _needsReauth.remove(serverId);
    await _connectToServer(refreshed);
    notifyListeners();
    return true;
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
    _serverAlerts.remove(serverId);
    _recentActivity.remove(serverId);
    _needsReauth.remove(serverId);
    _sessionPasswords.remove(serverId);
    _reauthInFlight.remove(serverId);
    await _storageService.saveServers(_servers);
    notifyListeners();
  }

  /// Get server name for an agent
  String getServerName(String serverId) {
    return _servers
        .firstWhere(
          (s) => s.id == serverId,
          orElse: () =>
              ServerConnection(id: '', name: 'common.unknown'.tr(), url: ''),
        )
        .name;
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
    _sessionPasswords.clear();
    super.dispose();
  }
}
