package com.nanolink.app.data.model

import kotlin.math.max
import kotlin.math.min
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull

const val CLIENT_VERSION = "0.3.3"

enum class ConnectionMode { DISCONNECTED, WEBSOCKET, HTTP_POLLING }

data class ConnectionStatus(
    val isConnected: Boolean,
    val mode: ConnectionMode,
    val lastUpdateMillis: Long? = null,
    val error: String? = null,
) {
    companion object {
        val Disconnected = ConnectionStatus(false, ConnectionMode.DISCONNECTED)
    }
}

data class ServerSummary(
    val connectedAgents: Int = 0,
    val avgCpuUsage: Double = 0.0,
    val avgMemoryUsage: Double = 0.0,
    val totalAlerts: Int = 0,
) {
    companion object {
        fun from(json: JsonObject) = ServerSummary(
            connectedAgents = json.int("connectedAgents", "connected_agents"),
            avgCpuUsage = json.double("avgCpuUsage", "avg_cpu_usage"),
            avgMemoryUsage = json.double("avgMemoryUsage", "avg_memory_usage"),
            totalAlerts = json.int("totalAlerts", "total_alerts"),
        )
    }
}

data class AssistantFinding(
    val kind: String,
    val title: String,
    val detail: String,
    val agentId: String?,
    val actions: List<String>,
) {
    companion object {
        fun from(json: JsonObject) = AssistantFinding(
            kind = json.string("kind", default = "info"),
            title = json.string("title"),
            detail = json.string("detail"),
            agentId = json.stringOrNull("agentId", "agent_id"),
            actions = json.strings("actions"),
        )
    }
}

data class DeviceTokenResult(
    val qrData: String,
    val pairingCode: String,
    val permissionLevel: Int,
    val expiresAtMillis: Long?,
)

data class ServerInfo(
    val version: String,
    val minVersion: String,
    val serverTime: Long,
    val features: List<String>,
) {
    fun isCompatible(client: String = CLIENT_VERSION): Boolean = compareVersions(client, minVersion) >= 0

    companion object {
        fun from(json: JsonObject) = ServerInfo(
            version = json.string("version", default = "0.0.0"),
            minVersion = json.string("minVersion", "min_version", default = "0.0.0"),
            serverTime = json.long("serverTime", "server_time"),
            features = json.strings("features"),
        )

        fun compareVersions(first: String, second: String): Int {
            val a = first.split('.').map { it.toIntOrNull() ?: 0 }
            val b = second.split('.').map { it.toIntOrNull() ?: 0 }
            repeat(3) { index ->
                val left = a.getOrElse(index) { 0 }
                val right = b.getOrElse(index) { 0 }
                if (left != right) return left.compareTo(right)
            }
            return 0
        }
    }
}

enum class LoginError { INVALID_CREDENTIALS, RATE_LIMITED, BAD_REQUEST, SERVER_ERROR, NETWORK }

data class LoginResult(
    val token: String? = null,
    val error: LoginError? = null,
    val message: String? = null,
    val statusCode: Int? = null,
) {
    val ok: Boolean get() = token != null && error == null
}

enum class AssistantChatError { NOT_CONFIGURED, BAD_REQUEST, UPSTREAM_FAILED, SERVER_ERROR, NETWORK }

data class AssistantChatResult(
    val reply: ChatMessage? = null,
    val error: AssistantChatError? = null,
    val message: String? = null,
    val statusCode: Int? = null,
) {
    val ok: Boolean get() = reply != null && error == null
}

data class CommandDispatch(val commandId: String? = null, val error: String? = null) {
    val ok: Boolean get() = commandId != null && error == null
}

enum class CommandResultStatus { READY, PENDING, DENIED, ERROR }

data class CommandResult(
    val status: CommandResultStatus,
    val data: JsonObject? = null,
    val message: String? = null,
) {
    val isReady: Boolean get() = status == CommandResultStatus.READY
    val isPending: Boolean get() = status == CommandResultStatus.PENDING
}

data class DeviceAuthResult(
    val ok: Boolean,
    val permissionLevel: Int = 0,
    val serverName: String = "",
    val error: String? = null,
    val statusCode: Int? = null,
)

data class MetricsHistory(
    val timesMillis: List<Long> = emptyList(),
    val cpu: List<Double> = emptyList(),
    val memory: List<Double> = emptyList(),
    val networkRx: List<Double> = emptyList(),
    val networkTx: List<Double> = emptyList(),
    val diskRead: List<Double> = emptyList(),
    val diskWrite: List<Double> = emptyList(),
    val gpuUsage: List<Double> = emptyList(),
    val gpuTemperature: List<Double> = emptyList(),
    val cpuMax: List<Double> = emptyList(),
    val memoryMax: List<Double> = emptyList(),
    val loadAverage: List<Double> = emptyList(),
) {
    val isEmpty: Boolean get() = cpu.isEmpty()
    val hasGpu: Boolean get() = gpuUsage.any { it > 0 }
    val hasMaxBands: Boolean get() = cpuMax.isNotEmpty() || memoryMax.isNotEmpty()

    companion object {
        fun parse(array: JsonArray): MetricsHistory {
            val times = mutableListOf<Long>()
            val cpu = mutableListOf<Double>()
            val memory = mutableListOf<Double>()
            val rx = mutableListOf<Double>()
            val tx = mutableListOf<Double>()
            val read = mutableListOf<Double>()
            val write = mutableListOf<Double>()
            val gpu = mutableListOf<Double>()
            val gpuTemp = mutableListOf<Double>()
            val cpuMax = mutableListOf<Double>()
            val memoryMax = mutableListOf<Double>()
            val load = mutableListOf<Double>()
            var hasGpuTemp = false
            var hasCpuMax = false
            var hasMemoryMax = false
            var hasLoad = false
            val megabyte = 1_000_000.0

            fun number(element: kotlinx.serialization.json.JsonElement?): Double =
                (element as? JsonPrimitive)?.doubleOrNull
                    ?: (element as? JsonPrimitive)?.content?.toDoubleOrNull()
                    ?: 0.0

            array.mapNotNull { it as? JsonObject }.forEach { item ->
                times += timestampMillis(item["timestamp"]) ?: 0L
                val cpuObject = item.obj("cpu") ?: JsonObject(emptyMap())
                cpu += number(cpuObject["usagePercent"] ?: cpuObject["usage_percent"])
                cpuMax += number(cpuObject["maxPercent"] ?: cpuObject["max_percent"])
                hasCpuMax = hasCpuMax || cpuObject.element("maxPercent", "max_percent") != null

                val memoryObject = item.obj("memory") ?: JsonObject(emptyMap())
                val total = number(memoryObject["total"])
                val used = number(memoryObject["used"])
                memory += if (total > 0) min(100.0, max(0.0, used / total * 100)) else 0.0
                memoryMax += min(100.0, max(0.0, number(memoryObject["maxPercent"] ?: memoryObject["max_percent"])))
                hasMemoryMax = hasMemoryMax || memoryObject.element("maxPercent", "max_percent") != null

                val loads = item.element("loadAverage", "load_average") as? JsonArray
                load += number(loads?.firstOrNull())
                hasLoad = hasLoad || !loads.isNullOrEmpty()

                val networks = item.objects("networks")
                rx += networks.sumOf { number(it["rxBytesPerSec"] ?: it["rx_bytes_per_sec"]) } / megabyte
                tx += networks.sumOf { number(it["txBytesPerSec"] ?: it["tx_bytes_per_sec"]) } / megabyte

                val disks = item.objects("disks")
                read += disks.sumOf { number(it["readBytesPerSec"] ?: it["read_bytes_per_sec"]) } / megabyte
                write += disks.sumOf { number(it["writeBytesPerSec"] ?: it["write_bytes_per_sec"]) } / megabyte

                val firstGpu = item.objects("gpus").firstOrNull()
                gpu += number(firstGpu?.get("usagePercent") ?: firstGpu?.get("usage_percent"))
                gpuTemp += number(firstGpu?.get("temperature"))
                hasGpuTemp = hasGpuTemp || firstGpu?.get("temperature") != null
            }

            return MetricsHistory(
                timesMillis = times,
                cpu = cpu,
                memory = memory,
                networkRx = rx,
                networkTx = tx,
                diskRead = read,
                diskWrite = write,
                gpuUsage = gpu,
                gpuTemperature = if (hasGpuTemp) gpuTemp else emptyList(),
                cpuMax = if (hasCpuMax) cpuMax else emptyList(),
                memoryMax = if (hasMemoryMax) memoryMax else emptyList(),
                loadAverage = if (hasLoad) load else emptyList(),
            )
        }
    }
}
