package com.nanolink.app.data.network

import android.util.Base64
import com.nanolink.app.data.model.Agent
import com.nanolink.app.data.model.AgentMetrics
import com.nanolink.app.data.model.AlertInstance
import com.nanolink.app.data.model.AssistantChatError
import com.nanolink.app.data.model.AssistantChatResult
import com.nanolink.app.data.model.AssistantFinding
import com.nanolink.app.data.model.AuditEntry
import com.nanolink.app.data.model.ChatMessage
import com.nanolink.app.data.model.CommandDispatch
import com.nanolink.app.data.model.CommandResult
import com.nanolink.app.data.model.CommandResultStatus
import com.nanolink.app.data.model.ConnectionMode
import com.nanolink.app.data.model.ConnectionStatus
import com.nanolink.app.data.model.DeviceAuthResult
import com.nanolink.app.data.model.DeviceTokenResult
import com.nanolink.app.data.model.LoginError
import com.nanolink.app.data.model.LoginResult
import com.nanolink.app.data.model.MetricsHistory
import com.nanolink.app.data.model.NanoJson
import com.nanolink.app.data.model.ServerConnection
import com.nanolink.app.data.model.ServerInfo
import com.nanolink.app.data.model.ServerSummary
import com.nanolink.app.data.model.int
import com.nanolink.app.data.model.long
import com.nanolink.app.data.model.obj
import com.nanolink.app.data.model.string
import com.nanolink.app.data.model.stringOrNull
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager
import kotlin.coroutines.resume
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.io.IOException

class ServerService(val connection: ServerConnection) {
    internal data class Payload(val status: Int, val body: String)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val client = createClient(connection.ignoreCert)
    private var webSocket: WebSocket? = null
    private var pollingJob: Job? = null
    private var pingJob: Job? = null
    private var reconnectJob: Job? = null
    private var useWebSocket = true
    private var cachedAgents = emptyList<Agent>()
    private var cachedMetrics = emptyMap<String, AgentMetrics>()

    private val _agents = MutableStateFlow<List<Agent>>(emptyList())
    val agents: StateFlow<List<Agent>> = _agents.asStateFlow()
    private val _metrics = MutableStateFlow<Map<String, AgentMetrics>>(emptyMap())
    val metrics: StateFlow<Map<String, AgentMetrics>> = _metrics.asStateFlow()
    private val _summary = MutableStateFlow(ServerSummary())
    val summary: StateFlow<ServerSummary> = _summary.asStateFlow()
    private val _connectionStatus = MutableStateFlow(ConnectionStatus.Disconnected)
    val connectionStatus: StateFlow<ConnectionStatus> = _connectionStatus.asStateFlow()
    private val _serverInfo = MutableStateFlow<ServerInfo?>(null)
    val serverInfo: StateFlow<ServerInfo?> = _serverInfo.asStateFlow()
    private val _offlineAgents = MutableSharedFlow<String>(extraBufferCapacity = 8)
    val offlineAgents: SharedFlow<String> = _offlineAgents.asSharedFlow()

    val connectionMode: ConnectionMode get() = _connectionStatus.value.mode
    val isCompatibleServer: Boolean get() = _serverInfo.value?.isCompatible() ?: true

    private fun httpBaseUrl(): String {
        var base = connection.url.trim().trimEnd('/')
        if (connection.forceTls && base.startsWith("http://")) {
            base = "https://${base.removePrefix("http://")}"
        }
        return base
    }

    private fun wsBaseUrl(): String = when {
        httpBaseUrl().startsWith("https://") -> "wss://${httpBaseUrl().removePrefix("https://")}"
        httpBaseUrl().startsWith("http://") -> "ws://${httpBaseUrl().removePrefix("http://")}"
        else -> httpBaseUrl()
    }

    private fun apiUrl(path: String, query: Map<String, String> = emptyMap()): String? {
        val builder = "${httpBaseUrl()}/api$path".toHttpUrlOrNull()?.newBuilder() ?: return null
        query.forEach { (key, value) -> builder.addQueryParameter(key, value) }
        return builder.build().toString()
    }

    fun openShell(agentId: String): ShellSession {
        val encoded = URLEncoder.encode(agentId, StandardCharsets.UTF_8.toString()).replace("+", "%20")
        return ShellSession(client, "${wsBaseUrl()}/ws/shell/$encoded", connection.authToken)
    }

    private suspend fun perform(
        method: String,
        path: String,
        body: JsonElement? = null,
        headers: Map<String, String>? = null,
        query: Map<String, String> = emptyMap(),
    ): Payload? {
        val url = apiUrl(path, query) ?: return null
        val requestBody = body?.toString()?.toRequestBody(JSON_MEDIA_TYPE)
        val request = Request.Builder().url(url).apply {
            (headers ?: authHeaders()).forEach { (key, value) -> header(key, value) }
            when (method) {
                "GET" -> get()
                "POST" -> post(requestBody ?: EMPTY_BODY)
                "PUT" -> put(requestBody ?: EMPTY_BODY)
                "DELETE" -> if (requestBody == null) delete() else delete(requestBody)
                else -> method(method, requestBody)
            }
        }.build()
        return withTimeoutOrNull(10_000) { client.newCall(request).awaitPayload() }
    }

    private fun authHeaders(): Map<String, String> = buildMap {
        put("Content-Type", "application/json")
        connection.authToken?.takeIf(String::isNotEmpty)?.let { put("Authorization", "Bearer $it") }
    }

    private fun errorMessage(payload: Payload): String {
        val json = runCatching { NanoJson.parseToJsonElement(payload.body).jsonObject }.getOrNull()
        return json?.stringOrNull("error", "details") ?: "HTTP ${payload.status}"
    }

    suspend fun login(username: String, password: String): String? = loginDetailed(username, password).token

    suspend fun loginDetailed(username: String, password: String): LoginResult {
        val body = buildJsonObject {
            put("username", username)
            put("password", password)
        }
        val response = perform(
            "POST",
            "/auth/login",
            body,
            mapOf("Content-Type" to "application/json", "X-NanoLink-Client" to "native"),
        ) ?: return LoginResult(error = LoginError.NETWORK, message = "connection failed")
        if (response.status == 200) {
            val token = runCatching { NanoJson.parseToJsonElement(response.body).jsonObject.stringOrNull("token") }.getOrNull()
            return if (token != null) LoginResult(token = token, statusCode = 200)
            else LoginResult(error = LoginError.SERVER_ERROR, message = "login succeeded but no token was returned", statusCode = 200)
        }
        val error = when (response.status) {
            400 -> LoginError.BAD_REQUEST
            401 -> LoginError.INVALID_CREDENTIALS
            429 -> LoginError.RATE_LIMITED
            else -> LoginError.SERVER_ERROR
        }
        return LoginResult(error = error, message = errorMessage(response), statusCode = response.status)
    }

    suspend fun redeemPairingCode(code: String): String? {
        val response = perform(
            "POST",
            "/auth/pairing",
            buildJsonObject { put("pairingCode", code) },
            mapOf("Content-Type" to "application/json"),
        ) ?: return null
        if (response.status != 200) return null
        return runCatching { NanoJson.parseToJsonElement(response.body).jsonObject.stringOrNull("token") }.getOrNull()
    }

    suspend fun testConnection(): Boolean = perform("GET", "/health")?.status == 200

    suspend fun validateDeviceToken(
        token: String,
        deviceName: String,
        deviceType: String = "mobile",
        deviceOs: String = "Android",
    ): DeviceAuthResult {
        val response = perform(
            "POST",
            "/auth/device",
            buildJsonObject {
                put("deviceName", deviceName)
                put("deviceType", deviceType)
                put("deviceOs", deviceOs)
            },
            mapOf("Content-Type" to "application/json", "X-Device-Token" to token),
        ) ?: return DeviceAuthResult(ok = false, error = "connection failed")
        if (response.status == 200) {
            val info = runCatching { NanoJson.parseToJsonElement(response.body).jsonObject.obj("serverInfo") }.getOrNull()
            return DeviceAuthResult(
                ok = true,
                permissionLevel = info?.int("permissionLevel") ?: 0,
                serverName = info?.string("name").orEmpty(),
                statusCode = 200,
            )
        }
        return DeviceAuthResult(false, error = errorMessage(response), statusCode = response.status)
    }

    suspend fun generateDeviceToken(serverName: String? = null): DeviceTokenResult? {
        val response = perform("POST", "/devices/token", buildJsonObject {
            serverName?.let { put("serverName", it) }
        }) ?: return null
        if (response.status !in listOf(200, 201)) return null
        val json = runCatching { NanoJson.parseToJsonElement(response.body).jsonObject }.getOrNull() ?: return null
        val qr = json.string("qrData")
        val expiry = runCatching {
            val decoded = Base64.decode(qr, Base64.DEFAULT).toString(Charsets.UTF_8)
            val seconds = NanoJson.parseToJsonElement(decoded).jsonObject.long("e")
            seconds.takeIf { it > 0 }?.times(1_000)
        }.getOrNull()
        return DeviceTokenResult(qr, json.string("pairingCode"), json.int("permissionLevel"), expiry)
    }

    suspend fun fetchAgents(): List<Agent> {
        val response = perform("GET", "/agents") ?: return emptyList()
        if (response.status != 200) return emptyList()
        return runCatching {
            NanoJson.parseToJsonElement(response.body).jsonArray.mapNotNull { it as? JsonObject }
                .map { Agent.from(it, connection.id) }
        }.getOrDefault(emptyList())
    }

    suspend fun fetchMetrics(): Map<String, AgentMetrics> {
        val response = perform("GET", "/metrics") ?: return emptyMap()
        if (response.status != 200) return emptyMap()
        return runCatching {
            NanoJson.parseToJsonElement(response.body).jsonObject.mapNotNull { (agentId, value) ->
                (value as? JsonObject)?.let { agentId to AgentMetrics.from(it).copy(agentId = agentId) }
            }.toMap()
        }.getOrDefault(emptyMap())
    }

    suspend fun fetchMetricsHistory(
        agentId: String,
        windowMillis: Long,
        interval: String = "auto",
        limit: Int = 240,
    ): MetricsHistory? {
        val end = System.currentTimeMillis()
        val response = perform(
            "GET",
            "/metrics/history",
            query = mapOf(
                "agentId" to agentId,
                "start" to (end - windowMillis).toString(),
                "end" to end.toString(),
                "interval" to interval,
                "limit" to limit.toString(),
            ),
        ) ?: return null
        if (response.status != 200) return null
        return runCatching { MetricsHistory.parse(NanoJson.parseToJsonElement(response.body).jsonArray) }
            .getOrDefault(MetricsHistory())
    }

    suspend fun fetchSummary(): ServerSummary? {
        val response = perform("GET", "/summary") ?: return null
        if (response.status != 200) return null
        return runCatching { ServerSummary.from(NanoJson.parseToJsonElement(response.body).jsonObject) }.getOrNull()
    }

    suspend fun fetchAlerts(status: String? = null): List<AlertInstance> {
        val query = status?.takeIf(String::isNotEmpty)?.let { mapOf("status" to it) }.orEmpty()
        val response = perform("GET", "/alerts", query = query) ?: return emptyList()
        if (response.status != 200) return emptyList()
        return runCatching {
            NanoJson.parseToJsonElement(response.body).jsonArray.mapNotNull { it as? JsonObject }.map(AlertInstance::from)
        }.getOrDefault(emptyList())
    }

    suspend fun acknowledgeAlert(id: String): String? {
        val response = perform("POST", "/alerts/ack/$id") ?: return "connection failed"
        return if (response.status == 200) null else errorMessage(response)
    }

    suspend fun acknowledgeAllAlerts(): Int? {
        val response = perform("POST", "/alerts/ack-all") ?: return null
        if (response.status != 200) return null
        return runCatching { NanoJson.parseToJsonElement(response.body).jsonObject.int("count") }.getOrNull()
    }

    suspend fun fetchRecentAudit(limit: Int = 50): List<AuditEntry> {
        val response = perform("GET", "/audit/recent", query = mapOf("limit" to limit.toString())) ?: return emptyList()
        if (response.status != 200) return emptyList()
        return runCatching {
            val decoded = NanoJson.parseToJsonElement(response.body)
            val logs = when (decoded) {
                is JsonArray -> decoded
                is JsonObject -> decoded["logs"] as? JsonArray ?: JsonArray(emptyList())
                else -> JsonArray(emptyList())
            }
            logs.mapNotNull { it as? JsonObject }.map(AuditEntry::from)
        }.getOrDefault(emptyList())
    }

    suspend fun fetchAssistantFindings(): List<AssistantFinding>? {
        val response = perform("GET", "/assistant/findings") ?: return null
        if (response.status != 200) return null
        return runCatching {
            NanoJson.parseToJsonElement(response.body).jsonArray.mapNotNull { it as? JsonObject }.map(AssistantFinding::from)
        }.getOrDefault(emptyList())
    }

    suspend fun assistantChat(messages: List<ChatMessage>): AssistantChatResult {
        val body = buildJsonObject {
            putJsonArray("messages") {
                messages.forEach { message ->
                    add(buildJsonObject {
                        put("role", message.role)
                        put("content", message.content)
                    })
                }
            }
        }
        val response = perform("POST", "/assistant/chat", body) ?:
            return AssistantChatResult(error = AssistantChatError.NETWORK, message = "connection failed")
        if (response.status == 200) {
            val reply = runCatching { NanoJson.parseToJsonElement(response.body).jsonObject.string("reply") }.getOrDefault("")
            return AssistantChatResult(reply = ChatMessage(role = "assistant", content = reply), statusCode = 200)
        }
        val error = when (response.status) {
            400 -> AssistantChatError.BAD_REQUEST
            502 -> AssistantChatError.UPSTREAM_FAILED
            503 -> AssistantChatError.NOT_CONFIGURED
            else -> AssistantChatError.SERVER_ERROR
        }
        return AssistantChatResult(error = error, message = errorMessage(response), statusCode = response.status)
    }

    suspend fun sendCommand(
        agentId: String,
        type: String,
        target: String = "",
        params: Map<String, String>? = null,
    ): String? {
        val response = perform("POST", "/agents/$agentId/command", commandBody(type, target, params))
            ?: return "connection failed"
        return if (response.status == 200) null else errorMessage(response)
    }

    suspend fun sendCommandReturningId(
        agentId: String,
        type: String,
        target: String = "",
        params: Map<String, String>? = null,
    ): CommandDispatch {
        val response = perform("POST", "/agents/$agentId/command", commandBody(type, target, params))
            ?: return CommandDispatch(error = "connection failed")
        if (response.status != 200) return CommandDispatch(error = errorMessage(response))
        val id = runCatching { NanoJson.parseToJsonElement(response.body).jsonObject.stringOrNull("commandId") }.getOrNull()
        return if (id != null) CommandDispatch(commandId = id) else CommandDispatch(error = "server returned no commandId")
    }

    private fun commandBody(type: String, target: String, params: Map<String, String>?) = buildJsonObject {
        put("type", type)
        put("target", target)
        params?.let { values -> putJsonObject("params") { values.forEach { (key, value) -> put(key, value) } } }
    }

    suspend fun pollCommandResult(agentId: String, commandId: String): CommandResult {
        val response = perform("GET", "/agents/$agentId/command/$commandId/result")
            ?: return CommandResult(CommandResultStatus.ERROR, message = "connection failed")
        return when (response.status) {
            200 -> CommandResult(
                CommandResultStatus.READY,
                data = runCatching { NanoJson.parseToJsonElement(response.body).jsonObject }.getOrNull(),
            )
            202 -> CommandResult(CommandResultStatus.PENDING)
            403 -> CommandResult(CommandResultStatus.DENIED, message = errorMessage(response))
            else -> CommandResult(CommandResultStatus.ERROR, message = errorMessage(response))
        }
    }

    suspend fun requestData(agentId: String, requestType: String = "full", target: String = ""): String? {
        val response = perform("POST", "/agents/$agentId/data-request", buildJsonObject {
            put("requestType", requestType)
            put("target", target)
        }) ?: return "connection failed"
        return if (response.status == 200) null else errorMessage(response)
    }

    fun startUpdates(pollIntervalMillis: Long = 2_000) {
        useWebSocket = true
        connectWebSocket()
        scope.launch {
            delay(4_000)
            if (_connectionStatus.value.mode != ConnectionMode.WEBSOCKET) startPolling(pollIntervalMillis)
        }
    }

    private fun connectWebSocket() {
        if (!useWebSocket || webSocket != null) return
        val request = Request.Builder().url("${wsBaseUrl()}/ws/dashboard").apply {
            connection.authToken?.takeIf(String::isNotEmpty)?.let { header("Authorization", "Bearer $it") }
        }.build()
        webSocket = client.newWebSocket(request, DashboardSocketListener())
    }

    private fun startPolling(intervalMillis: Long = 2_000) {
        if (_connectionStatus.value.mode == ConnectionMode.WEBSOCKET || pollingJob?.isActive == true) return
        pollingJob = scope.launch {
            while (isActive && _connectionStatus.value.mode != ConnectionMode.WEBSOCKET) {
                val fetchedAgents = fetchAgents()
                val fetchedMetrics = fetchMetrics()
                val fetchedSummary = fetchSummary()
                cachedAgents = fetchedAgents
                cachedMetrics = fetchedMetrics
                _agents.value = fetchedAgents
                _metrics.value = fetchedMetrics
                fetchedSummary?.let { _summary.value = it }
                emitConnection(true, ConnectionMode.HTTP_POLLING)
                delay(intervalMillis)
            }
        }
    }

    private fun stopPolling() {
        pollingJob?.cancel()
        pollingJob = null
    }

    private fun emitConnection(connected: Boolean, mode: ConnectionMode, error: String? = null) {
        _connectionStatus.value = ConnectionStatus(connected, mode, System.currentTimeMillis(), error)
    }

    private fun onSocketMessage(text: String) {
        val message = runCatching { NanoJson.parseToJsonElement(text).jsonObject }.getOrNull() ?: return
        val type = message["type"]?.jsonPrimitive?.contentOrNull
        val data = message["data"]
        when (type) {
            "welcome" -> (data as? JsonObject)?.let { _serverInfo.value = ServerInfo.from(it) }
            "agents" -> (data as? JsonArray)?.let { array ->
                cachedAgents = array.mapNotNull { it as? JsonObject }.map { Agent.from(it, connection.id) }
                _agents.value = cachedAgents
            }
            "agent_update" -> (data as? JsonObject)?.let { payload ->
                val agent = Agent.from(payload, connection.id)
                cachedAgents = cachedAgents.filterNot { it.id == agent.id } + agent
                _agents.value = cachedAgents
            }
            "metrics" -> (data as? JsonObject)?.let { payload ->
                val agentId = payload.stringOrNull("agentId")
                val single = payload.obj("metrics")
                cachedMetrics = if (agentId != null && single != null) {
                    cachedMetrics + (agentId to AgentMetrics.from(single).copy(agentId = agentId))
                } else {
                    cachedMetrics + payload.mapNotNull { (id, value) ->
                        (value as? JsonObject)?.let { id to AgentMetrics.from(it).copy(agentId = id) }
                    }.toMap()
                }
                _metrics.value = cachedMetrics
            }
            "agent_offline" -> {
                val id = when (data) {
                    is JsonPrimitive -> data.contentOrNull
                    is JsonObject -> data.stringOrNull("agentId")
                    else -> null
                }
                id?.let {
                    cachedAgents = cachedAgents.filterNot { agent -> agent.id == it }
                    cachedMetrics = cachedMetrics - it
                    _agents.value = cachedAgents
                    _metrics.value = cachedMetrics
                    _offlineAgents.tryEmit(it)
                }
            }
            "summary" -> (data as? JsonObject)?.let { _summary.value = ServerSummary.from(it) }
        }
    }

    private fun scheduleReconnect() {
        reconnectJob?.cancel()
        reconnectJob = scope.launch {
            delay(3_000)
            if (useWebSocket) connectWebSocket()
        }
    }

    fun dispose() {
        useWebSocket = false
        reconnectJob?.cancel()
        stopPolling()
        pingJob?.cancel()
        webSocket?.close(1001, "client disposed")
        webSocket = null
        scope.cancel()
    }

    private inner class DashboardSocketListener : WebSocketListener() {
        override fun onOpen(socket: WebSocket, response: Response) {
            if (webSocket !== socket) return
            stopPolling()
            emitConnection(true, ConnectionMode.WEBSOCKET)
            pingJob?.cancel()
            pingJob = scope.launch {
                while (isActive && webSocket === socket) {
                    delay(30_000)
                    socket.send(buildJsonObject {
                        put("type", "ping")
                        put("timestamp", System.currentTimeMillis())
                    }.toString())
                }
            }
        }

        override fun onMessage(socket: WebSocket, text: String) {
            if (webSocket === socket) onSocketMessage(text)
        }

        override fun onClosing(socket: WebSocket, code: Int, reason: String) {
            socket.close(code, reason)
        }

        override fun onClosed(socket: WebSocket, code: Int, reason: String) {
            if (webSocket !== socket) return
            webSocket = null
            pingJob?.cancel()
            emitConnection(false, ConnectionMode.DISCONNECTED)
            if (useWebSocket) {
                startPolling()
                scheduleReconnect()
            }
        }

        override fun onFailure(socket: WebSocket, throwable: Throwable, response: Response?) {
            if (webSocket !== socket) return
            webSocket = null
            pingJob?.cancel()
            emitConnection(false, ConnectionMode.DISCONNECTED, throwable.localizedMessage)
            if (useWebSocket) {
                startPolling()
                scheduleReconnect()
            }
        }
    }

    companion object {
        private val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
        private val EMPTY_BODY = ByteArray(0).toRequestBody(JSON_MEDIA_TYPE)

        private fun createClient(ignoreCert: Boolean): OkHttpClient {
            val builder = OkHttpClient.Builder()
                .connectTimeout(15, TimeUnit.SECONDS)
                .readTimeout(30, TimeUnit.SECONDS)
                .writeTimeout(15, TimeUnit.SECONDS)
            if (!ignoreCert) return builder.build()

            val trustManager = object : X509TrustManager {
                override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
                override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
                override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
            }
            val sslContext = SSLContext.getInstance("TLS").apply {
                init(null, arrayOf<TrustManager>(trustManager), SecureRandom())
            }
            return builder
                .sslSocketFactory(sslContext.socketFactory, trustManager)
                .hostnameVerifier { _, _ -> true }
                .build()
        }
    }
}

private suspend fun Call.awaitPayload(): ServerService.Payload? = suspendCancellableCoroutine { continuation ->
    continuation.invokeOnCancellation { cancel() }
    enqueue(object : Callback {
        override fun onFailure(call: Call, error: IOException) {
            if (continuation.isActive) continuation.resume(null)
        }

        override fun onResponse(call: Call, response: Response) {
            response.use {
                val payload = ServerService.Payload(response.code, response.body?.string().orEmpty())
                if (continuation.isActive) continuation.resume(payload)
            }
        }
    })
}
