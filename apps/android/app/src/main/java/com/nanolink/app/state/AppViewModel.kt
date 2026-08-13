package com.nanolink.app.state

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.nanolink.app.data.model.Agent
import com.nanolink.app.data.model.AgentMetrics
import com.nanolink.app.data.model.AlertInstance
import com.nanolink.app.data.model.AuditEntry
import com.nanolink.app.data.model.ChatMessage
import com.nanolink.app.data.model.ConnectionMode
import com.nanolink.app.data.model.ConnectionStatus
import com.nanolink.app.data.model.LoginError
import com.nanolink.app.data.model.ServerConnection
import com.nanolink.app.data.model.ServerSummary
import com.nanolink.app.data.network.ServerService
import com.nanolink.app.data.notification.NotificationService
import com.nanolink.app.data.storage.PreferenceKeys
import com.nanolink.app.data.storage.PreferencesStore
import com.nanolink.app.data.storage.SecureStore
import com.nanolink.app.data.storage.StorageService
import com.nanolink.app.localization.L10n
import kotlin.math.roundToInt
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class AppThemeMode { LIGHT, DARK, SYSTEM }
enum class ThemeStyle { IOS, MD }

/// Theme state for the design system.
data class ThemeState(
    val mode: AppThemeMode = AppThemeMode.SYSTEM,
    val style: ThemeStyle = ThemeStyle.MD,
    val compact: Boolean = false,
)

/// A client-derived alert awaiting a local-notification decision.
private data class PendingAlert(val category: String, val title: String, val body: String)

class AppViewModel(application: Application) : AndroidViewModel(application) {
    private val preferences = PreferencesStore(application)
    internal fun getPreferences() = preferences
    private val secureStore = SecureStore(application)
    private val storage = StorageService(preferences, secureStore)
    private val notifications = NotificationService(application)
    private val l10n = L10n(application, preferences)
    private val services = mutableMapOf<String, ServerService>()
    private val sessionPasswords = mutableMapOf<String, String>()
    private val reauthInFlight = mutableSetOf<String>()
    private val activeAlerts = mutableSetOf<String>()
    private var alertsSeeded = false

    private val _servers = MutableStateFlow<List<ServerConnection>>(emptyList())
    val servers: StateFlow<List<ServerConnection>> = _servers.asStateFlow()
    private val _agents = MutableStateFlow<List<Agent>>(emptyList())
    val agents: StateFlow<List<Agent>> = _agents.asStateFlow()
    private val _metrics = MutableStateFlow<Map<String, AgentMetrics>>(emptyMap())
    val metrics: StateFlow<Map<String, AgentMetrics>> = _metrics.asStateFlow()
    private val _summaries = MutableStateFlow<Map<String, ServerSummary>>(emptyMap())
    val summaries: StateFlow<Map<String, ServerSummary>> = _summaries.asStateFlow()
    private val _connectionModes = MutableStateFlow<Map<String, ConnectionMode>>(emptyMap())
    val connectionModes: StateFlow<Map<String, ConnectionMode>> = _connectionModes.asStateFlow()
    private val _alerts = MutableStateFlow<Map<String, List<AlertInstance>>>(emptyMap())
    val alerts: StateFlow<Map<String, List<AlertInstance>>> = _alerts.asStateFlow()
    private val _activity = MutableStateFlow<Map<String, List<AuditEntry>>>(emptyMap())
    val activity: StateFlow<Map<String, List<AuditEntry>>> = _activity.asStateFlow()
    private val _needsReauth = MutableStateFlow<Set<String>>(emptySet())
    val needsReauth: StateFlow<Set<String>> = _needsReauth.asStateFlow()
    private val _isLoading = MutableStateFlow(true)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()
    private val _activeServerId = MutableStateFlow<String?>(null)
    val activeServerId: StateFlow<String?> = _activeServerId.asStateFlow()

    private val _notifyOffline = MutableStateFlow(true)
    val notifyOffline: StateFlow<Boolean> = _notifyOffline.asStateFlow()
    private val _notifyHigh = MutableStateFlow(true)
    val notifyHigh: StateFlow<Boolean> = _notifyHigh.asStateFlow()
    private val _notifyDisk = MutableStateFlow(true)
    val notifyDisk: StateFlow<Boolean> = _notifyDisk.asStateFlow()

    init {
        viewModelScope.launch { start() }
    }

    /// Shared localization engine, also used by the Compose layer.
    val localization: L10n get() = l10n

    /// Current language code for recomposition triggers.
    val currentLanguage: StateFlow<String> = l10n.currentLanguageFlow

    private val _themeState = MutableStateFlow(ThemeState())
    val themeState: StateFlow<ThemeState> = _themeState.asStateFlow()

    /// Count of unacknowledged alerts across all servers.
    val unackedAlertCount: StateFlow<Int> = MutableStateFlow(0)

    val activeServer: ServerConnection?
        get() = _servers.value.firstOrNull { it.id == activeServerId.value } ?: _servers.value.firstOrNull()

    val totalSummary: ServerSummary
        get() {
            if (_summaries.value.isEmpty()) return ServerSummary(connectedAgents = _agents.value.size)
            val values = _summaries.value.values
            return ServerSummary(
                connectedAgents = values.sumOf { it.connectedAgents },
                avgCpuUsage = values.map { it.avgCpuUsage }.average().takeUnless(Double::isNaN) ?: 0.0,
                avgMemoryUsage = values.map { it.avgMemoryUsage }.average().takeUnless(Double::isNaN) ?: 0.0,
                totalAlerts = values.sumOf { it.totalAlerts },
            )
        }

    suspend fun start() {
        _isLoading.value = true
        l10n.currentLanguage()
        _notifyOffline.value = preferences.get(PreferenceKeys.NotifyOffline, true)
        _notifyHigh.value = preferences.get(PreferenceKeys.NotifyHigh, true)
        _notifyDisk.value = preferences.get(PreferenceKeys.NotifyDisk, true)
        val saved = storage.getServers()
        _servers.value = saved
        val savedActiveId = preferences.get(PreferenceKeys.ActiveServer, "").takeIf { it.isNotEmpty() }
        _activeServerId.value = savedActiveId ?: saved.firstOrNull()?.id
        saved.forEach(::connectToServer)
        _isLoading.value = false
    }

    fun setActiveServer(serverId: String) {
        if (_servers.value.any { it.id == serverId }) {
            _activeServerId.value = serverId
            viewModelScope.launch { preferences.set(PreferenceKeys.ActiveServer, serverId) }
        }
    }

    fun agentsForServer(serverId: String? = activeServerId.value): List<Agent> =
        _agents.value.filter { it.serverId == serverId }

    fun metricsFor(agentId: String): AgentMetrics? = _metrics.value[agentId]
    fun agentById(agentId: String): Agent? = _agents.value.firstOrNull { it.id == agentId }
    fun serviceForServer(serverId: String): ServerService? = services[serverId]
    fun serviceForAgent(agentId: String): ServerService? = agentById(agentId)?.let { services[it.serverId] }
    fun connectionMode(serverId: String): ConnectionMode = _connectionModes.value[serverId] ?: ConnectionMode.DISCONNECTED
    fun serverName(serverId: String): String = _servers.value.firstOrNull { it.id == serverId }?.name ?: "Unknown"
    fun serverAlerts(serverId: String? = activeServerId.value): List<AlertInstance> = serverId?.let { _alerts.value[it] }.orEmpty()
    fun recentActivity(serverId: String? = activeServerId.value): List<AuditEntry> = serverId?.let { _activity.value[it] }.orEmpty()
    fun unackedAlertCount(serverId: String? = activeServerId.value): Int = serverAlerts(serverId).count { !it.acked }

    fun setNotifyPref(key: String, value: Boolean) {
        val preferenceKey = when (key) {
            "notify_offline" -> PreferenceKeys.NotifyOffline
            "notify_high" -> PreferenceKeys.NotifyHigh
            "notify_disk" -> PreferenceKeys.NotifyDisk
            else -> return
        }
        when (key) {
            "notify_offline" -> _notifyOffline.value = value
            "notify_high" -> _notifyHigh.value = value
            "notify_disk" -> _notifyDisk.value = value
        }
        viewModelScope.launch { preferences.set(preferenceKey, value) }
    }

    suspend fun addServer(
        name: String,
        url: String,
        token: String? = null,
        forceTls: Boolean = false,
        ignoreCert: Boolean = false,
    ): Boolean {
        var server = ServerConnection(name = name, url = url, token = token, forceTls = forceTls, ignoreCert = ignoreCert)
        val service = ServerService(server)
        val valid = if (!token.isNullOrEmpty()) {
            service.validateDeviceToken(token, name.ifEmpty { "Android device" }).ok
        } else {
            service.testConnection()
        }
        service.dispose()
        if (!valid) return false
        server = server.copy(isConnected = true, lastConnectedMillis = System.currentTimeMillis())
        _servers.value = _servers.value + server
        storage.saveServers(_servers.value)
        connectToServer(server)
        return true
    }

    suspend fun addServerWithCredentials(name: String, url: String, username: String, password: String): Boolean {
        val pending = ServerConnection(name = name, url = url, username = username)
        val service = ServerService(pending)
        val token = service.login(username, password)
        service.dispose()
        if (token == null) return false
        val server = pending.copy(isConnected = true, lastConnectedMillis = System.currentTimeMillis(), userToken = token)
        sessionPasswords[server.id] = password
        _servers.value = _servers.value + server
        storage.saveServers(_servers.value)
        connectToServer(server)
        return true
    }

    suspend fun addServerWithPairingCode(name: String, url: String, pairingCode: String): Boolean {
        val pending = ServerConnection(name = name, url = url)
        val service = ServerService(pending)
        val token = service.redeemPairingCode(pairingCode)
        service.dispose()
        if (token == null) return false
        val server = pending.copy(isConnected = true, lastConnectedMillis = System.currentTimeMillis(), token = token)
        _servers.value = _servers.value + server
        storage.saveServers(_servers.value)
        connectToServer(server)
        return true
    }

    fun removeServer(serverId: String) {
        services.remove(serverId)?.dispose()
        _servers.value = _servers.value.filterNot { it.id == serverId }
        _agents.value = _agents.value.filterNot { it.serverId == serverId }
        _connectionModes.value = _connectionModes.value - serverId
        _summaries.value = _summaries.value - serverId
        _alerts.value = _alerts.value - serverId
        _activity.value = _activity.value - serverId
        _needsReauth.value = _needsReauth.value - serverId
        sessionPasswords.remove(serverId)
        viewModelScope.launch { storage.deleteServer(serverId) }
    }

    suspend fun reauthenticate(serverId: String, username: String, password: String): Boolean {
        val old = _servers.value.firstOrNull { it.id == serverId } ?: return false
        val service = services[serverId] ?: ServerService(old)
        val result = service.loginDetailed(username, password)
        if (!result.ok || result.token == null) return false
        sessionPasswords[serverId] = password
        val refreshed = old.copy(username = username, userToken = result.token)
        _servers.value = _servers.value.map { if (it.id == serverId) refreshed else it }
        storage.saveServers(_servers.value)
        services.remove(serverId)?.dispose()
        _needsReauth.value = _needsReauth.value - serverId
        connectToServer(refreshed)
        return true
    }

    suspend fun fetchServerAlerts(serverId: String? = activeServerId.value, status: String? = null): List<AlertInstance> {
        val id = serverId ?: return emptyList()
        val service = services[id] ?: return serverAlerts(id)
        val result = service.fetchAlerts(status)
        _alerts.value = _alerts.value + (id to result)
        return result
    }

    suspend fun fetchRecentActivity(serverId: String? = activeServerId.value, limit: Int = 50): List<AuditEntry> {
        val id = serverId ?: return emptyList()
        val service = services[id] ?: return recentActivity(id)
        val result = service.fetchRecentAudit(limit)
        _activity.value = _activity.value + (id to result)
        return result
    }

    suspend fun acknowledgeAlert(alertId: String, serverId: String? = activeServerId.value): String? {
        val id = serverId ?: return "no active server"
        val service = services[id] ?: return "server not connected"
        val error = service.acknowledgeAlert(alertId)
        if (error == null) fetchServerAlerts(id)
        return error
    }

    suspend fun acknowledgeAllAlerts(serverId: String? = activeServerId.value): Int? {
        val id = serverId ?: return null
        val count = services[id]?.acknowledgeAllAlerts()
        if (count != null) fetchServerAlerts(id)
        return count
    }

    private fun connectToServer(server: ServerConnection) {
        services[server.id]?.dispose()
        val service = ServerService(server)
        services[server.id] = service
        viewModelScope.launch {
            service.agents.collect { incoming ->
                _agents.value = _agents.value.filterNot { it.serverId == server.id } + incoming
                evaluateAlerts()
            }
        }
        viewModelScope.launch {
            service.metrics.collect { incoming ->
                _metrics.value = _metrics.value + incoming
                evaluateAlerts()
            }
        }
        viewModelScope.launch {
            service.summary.collect { _summaries.value = _summaries.value + (server.id to it) }
        }
        viewModelScope.launch {
            service.connectionStatus.collect { status ->
                _connectionModes.value = _connectionModes.value + (server.id to status.mode)
                _servers.value = _servers.value.map {
                    if (it.id == server.id) {
                        it.copy(
                            isConnected = status.isConnected,
                            lastConnectedMillis = if (status.isConnected) System.currentTimeMillis() else it.lastConnectedMillis,
                        )
                    } else {
                        it
                    }
                }
                if (status.isConnected) {
                    _needsReauth.value = _needsReauth.value - server.id
                } else if (looksLikeAuthFailure(status.error)) {
                    handleAuthFailure(server.id)
                }
            }
        }
        viewModelScope.launch {
            service.offlineAgents.collect { agentId ->
                _agents.value = _agents.value.filterNot { it.id == agentId }
                _metrics.value = _metrics.value - agentId
            }
        }
        service.startUpdates()
    }

    /// Only auth-shaped transport errors trigger re-login, so an ordinary network
    /// blip isn't mistaken for an expired token.
    private fun looksLikeAuthFailure(error: String?): Boolean {
        val message = error?.lowercase()?.takeIf(String::isNotEmpty) ?: return false
        return listOf("401", "403", "unauthorized", "forbidden", "invalid token", "token expired", "expired token")
            .any(message::contains)
    }

    private suspend fun handleAuthFailure(serverId: String) {
        if (!reauthInFlight.add(serverId)) return
        try {
            if (!attemptReauth(serverId)) _needsReauth.value = _needsReauth.value + serverId
        } finally {
            reauthInFlight.remove(serverId)
        }
    }

    /// Silent re-login using the in-memory password captured when the account was
    /// added. Returns false when no credentials are available to retry with.
    private suspend fun attemptReauth(serverId: String): Boolean {
        val server = _servers.value.firstOrNull { it.id == serverId } ?: return false
        val username = server.username?.takeIf(String::isNotEmpty) ?: return false
        val password = sessionPasswords[serverId] ?: return false
        val service = services[serverId] ?: return false

        val result = service.loginDetailed(username, password)
        val token = result.token
        if (!result.ok || token == null) {
            if (result.error == LoginError.INVALID_CREDENTIALS) sessionPasswords.remove(serverId)
            return false
        }

        val refreshed = server.copy(userToken = token)
        _servers.value = _servers.value.map { if (it.id == serverId) refreshed else it }
        storage.saveServers(_servers.value)
        services.remove(serverId)?.dispose()
        _needsReauth.value = _needsReauth.value - serverId
        connectToServer(refreshed)
        return true
    }

    /// Re-derive the client-side alert set and push a local notification for each
    /// newly-appeared alert. The first pass only seeds `activeAlerts` so existing
    /// conditions don't notify at launch; resolved keys drop out so a recurring
    /// condition notifies again.
    private fun evaluateAlerts() {
        val current = mutableMapOf<String, PendingAlert>()
        _agents.value.forEach { agent ->
            val host = agent.hostname
            if (!agent.isOnline) {
                current["offline:${agent.id}"] = PendingAlert(
                    category = "offline",
                    title = l10n.text("alerts.nodeOffline", mapOf("host" to host)),
                    body = l10n.text("alerts.nodeOfflineDetail"),
                )
                return@forEach
            }
            val metrics = _metrics.value[agent.id] ?: return@forEach
            if (metrics.cpuPercent > 90) {
                current["cpu:${agent.id}"] = PendingAlert(
                    category = "high",
                    title = l10n.text("alerts.cpuPressure", mapOf("host" to host)),
                    body = l10n.text("alerts.usageDetail", mapOf("value" to metrics.cpuPercent.roundToInt())),
                )
            }
            if (metrics.memoryPercent > 90) {
                current["mem:${agent.id}"] = PendingAlert(
                    category = "high",
                    title = l10n.text("alerts.memPressure", mapOf("host" to host)),
                    body = l10n.text("alerts.usageDetail", mapOf("value" to metrics.memoryPercent.roundToInt())),
                )
            }
            metrics.disks.filter { it.usagePercent > 90 }.forEach { disk ->
                current["disk:${agent.id}:${disk.mountPoint}"] = PendingAlert(
                    category = "disk",
                    title = l10n.text("alerts.diskFull", mapOf("host" to host)),
                    body = l10n.text(
                        "alerts.diskDetail",
                        mapOf("mount" to disk.mountPoint, "value" to disk.usagePercent.roundToInt()),
                    ),
                )
            }
        }

        if (!alertsSeeded) {
            activeAlerts.clear()
            activeAlerts += current.keys
            alertsSeeded = true
            return
        }

        current.forEach { (key, alert) ->
            if (key in activeAlerts) return@forEach
            val enabled = when (alert.category) {
                "offline" -> _notifyOffline.value
                "disk" -> _notifyDisk.value
                else -> _notifyHigh.value
            }
            if (enabled) notifications.show(key, alert.title, alert.body)
        }
        activeAlerts.clear()
        activeAlerts += current.keys
    }

    override fun onCleared() {
        services.values.forEach(ServerService::dispose)
        services.clear()
        super.onCleared()
    }
}
