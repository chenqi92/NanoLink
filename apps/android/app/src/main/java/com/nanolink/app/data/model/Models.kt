package com.nanolink.app.data.model

import java.time.Instant
import java.time.format.DateTimeParseException
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.longOrNull

internal val NanoJson = Json {
    ignoreUnknownKeys = true
    isLenient = true
    explicitNulls = false
}

internal fun JsonObject.element(vararg keys: String): JsonElement? =
    keys.firstNotNullOfOrNull { key -> get(key)?.takeUnless { it is JsonNull } }

internal fun JsonObject.string(vararg keys: String, default: String = ""): String =
    (element(*keys) as? JsonPrimitive)?.contentOrNull ?: default

internal fun JsonObject.stringOrNull(vararg keys: String): String? =
    string(*keys).trim().ifEmpty { null }

internal fun JsonObject.int(vararg keys: String, default: Int = 0): Int {
    val value = element(*keys) as? JsonPrimitive ?: return default
    return value.intOrNull ?: value.contentOrNull?.toIntOrNull() ?: default
}

internal fun JsonObject.long(vararg keys: String, default: Long = 0): Long {
    val value = element(*keys) as? JsonPrimitive ?: return default
    return value.longOrNull ?: value.contentOrNull?.toLongOrNull() ?: default
}

internal fun JsonObject.double(vararg keys: String, default: Double = 0.0): Double {
    val value = element(*keys) as? JsonPrimitive ?: return default
    return value.doubleOrNull ?: value.contentOrNull?.toDoubleOrNull() ?: default
}

internal fun JsonObject.doubleOrNull(vararg keys: String): Double? {
    val value = element(*keys) as? JsonPrimitive ?: return null
    return value.doubleOrNull ?: value.contentOrNull?.toDoubleOrNull()
}

internal fun JsonObject.bool(vararg keys: String, default: Boolean = false): Boolean {
    val value = element(*keys) as? JsonPrimitive ?: return default
    return value.booleanOrNull ?: when (value.contentOrNull?.lowercase()) {
        "true", "1" -> true
        "false", "0" -> false
        else -> default
    }
}

internal fun JsonObject.obj(vararg keys: String): JsonObject? = element(*keys) as? JsonObject

internal fun JsonObject.objects(vararg keys: String): List<JsonObject> =
    (element(*keys) as? JsonArray)?.mapNotNull { it as? JsonObject }.orEmpty()

internal fun JsonObject.doubles(vararg keys: String): List<Double> =
    (element(*keys) as? JsonArray)?.mapNotNull {
        (it as? JsonPrimitive)?.doubleOrNull ?: (it as? JsonPrimitive)?.contentOrNull?.toDoubleOrNull()
    }.orEmpty()

internal fun JsonObject.strings(vararg keys: String): List<String> =
    (element(*keys) as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.contentOrNull }.orEmpty()

internal fun timestampMillis(value: JsonElement?): Long? {
    val primitive = value as? JsonPrimitive ?: return null
    primitive.longOrNull?.let { return if (it > 1_000_000_000_000L) it else it * 1_000L }
    val raw = primitive.contentOrNull ?: return null
    raw.toDoubleOrNull()?.let { number ->
        return if (number > 1_000_000_000_000.0) number.toLong() else (number * 1_000).toLong()
    }
    return try {
        Instant.parse(raw).toEpochMilli()
    } catch (_: DateTimeParseException) {
        null
    }
}

@Serializable
data class ServerConnection(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val url: String,
    val token: String? = null,
    val userToken: String? = null,
    val username: String? = null,
    val isConnected: Boolean = false,
    val lastConnectedMillis: Long? = null,
    val forceTls: Boolean = false,
    val ignoreCert: Boolean = false,
) {
    val authToken: String? get() = userToken ?: token
    val hasFullPermissions: Boolean get() = userToken != null
}

data class Agent(
    val id: String,
    val serverId: String,
    val hostname: String,
    val os: String,
    val arch: String,
    val version: String,
    val permissionLevel: Int,
    val connectedAtMillis: Long?,
    val lastHeartbeatMillis: Long?,
) {
    val isOnline: Boolean
        get() = lastHeartbeatMillis?.let { System.currentTimeMillis() - it < 60_000 } == true

    companion object {
        fun from(json: JsonObject, serverId: String, unknownHostname: String = "Unknown") = Agent(
            id = json.string("id", "agent_id", "agentId"),
            serverId = serverId,
            hostname = json.string("hostname", default = unknownHostname),
            os = json.string("os"),
            arch = json.string("arch"),
            version = json.string("version"),
            permissionLevel = json.int("permission_level", "permissionLevel"),
            connectedAtMillis = timestampMillis(json.element("connected_at", "connectedAt")),
            lastHeartbeatMillis = timestampMillis(json.element("last_heartbeat", "lastHeartbeat")),
        )
    }
}

data class CpuMetrics(
    val usagePercent: Double = 0.0,
    val coreCount: Int = 0,
    val perCoreUsage: List<Double> = emptyList(),
    val model: String = "",
    val temperature: Double? = null,
    val loadAverage: List<Double> = emptyList(),
    val frequencyMhz: Double? = null,
) {
    val frequencyGhz: Double? get() = frequencyMhz?.div(1_000)

    companion object {
        fun from(json: JsonObject) = CpuMetrics(
            usagePercent = json.double("usage_percent", "usagePercent"),
            coreCount = json.int("core_count", "coreCount"),
            perCoreUsage = json.doubles("per_core_usage", "perCoreUsage"),
            model = json.string("model"),
            temperature = json.doubleOrNull("temperature"),
            loadAverage = json.doubles("load_average", "loadAverage"),
            frequencyMhz = json.doubleOrNull("frequency_mhz", "frequencyMhz"),
        )
    }
}

data class MemoryMetrics(
    val total: Long = 0,
    val used: Long = 0,
    val available: Long = 0,
    val swapTotal: Long = 0,
    val swapUsed: Long = 0,
    val cached: Long = 0,
    val buffers: Long = 0,
    val memoryType: String? = null,
    val memorySpeedMhz: Int? = null,
) {
    val usagePercent: Double get() = if (total > 0) used.toDouble() / total * 100 else 0.0

    companion object {
        fun from(json: JsonObject) = MemoryMetrics(
            total = json.long("total"),
            used = json.long("used"),
            available = json.long("available"),
            swapTotal = json.long("swap_total", "swapTotal"),
            swapUsed = json.long("swap_used", "swapUsed"),
            cached = json.long("cached"),
            buffers = json.long("buffers"),
            memoryType = json.stringOrNull("memory_type", "memoryType"),
            memorySpeedMhz = json.element("memory_speed_mhz", "memorySpeedMhz")?.let {
                json.int("memory_speed_mhz", "memorySpeedMhz")
            },
        )
    }
}

data class DiskMetrics(
    val mountPoint: String,
    val device: String,
    val fsType: String,
    val total: Long,
    val used: Long,
    val available: Long,
    val readBytesPerSec: Double,
    val writeBytesPerSec: Double,
    val diskType: String?,
    val temperature: Double?,
    val healthStatus: String?,
) {
    val id: String get() = "$device|$mountPoint"
    val usagePercent: Double get() = if (total > 0) used.toDouble() / total * 100 else 0.0

    companion object {
        fun from(json: JsonObject) = DiskMetrics(
            mountPoint = json.string("mount_point", "mountPoint"),
            device = json.string("device"),
            fsType = json.string("fs_type", "fsType"),
            total = json.long("total"),
            used = json.long("used"),
            available = json.long("available"),
            readBytesPerSec = json.double("read_bytes_per_sec", "readBytesPerSec"),
            writeBytesPerSec = json.double("write_bytes_per_sec", "writeBytesPerSec"),
            diskType = json.stringOrNull("disk_type", "diskType"),
            temperature = json.doubleOrNull("temperature"),
            healthStatus = json.stringOrNull("health_status", "healthStatus"),
        )
    }
}

data class NetworkMetrics(
    val interfaceName: String,
    val rxBytesPerSec: Double,
    val txBytesPerSec: Double,
    val isUp: Boolean,
    val macAddress: String?,
    val ipAddresses: List<String>,
    val speedMbps: Double?,
    val interfaceType: String?,
) {
    val id: String get() = interfaceName

    companion object {
        fun from(json: JsonObject) = NetworkMetrics(
            interfaceName = json.string("interface", "interface_", "name"),
            rxBytesPerSec = json.double("rx_bytes_per_sec", "rxBytesPerSec"),
            txBytesPerSec = json.double("tx_bytes_per_sec", "txBytesPerSec"),
            isUp = json.bool("is_up", "isUp", default = true),
            macAddress = json.stringOrNull("mac_address", "macAddress"),
            ipAddresses = json.strings("ip_addresses", "ipAddresses"),
            speedMbps = json.doubleOrNull("speed_mbps", "speedMbps"),
            interfaceType = json.stringOrNull("interface_type", "interfaceType"),
        )
    }
}

data class GpuMetrics(
    val index: Int,
    val name: String,
    val vendor: String,
    val usagePercent: Double,
    val memoryTotal: Long,
    val memoryUsed: Long,
    val temperature: Double?,
    val powerWatts: Double?,
    val fanSpeedPercent: Double?,
    val driverVersion: String?,
    val pcieGeneration: String?,
    val powerLimitWatts: Double?,
) {
    val id: Int get() = index
    val vramPercent: Double get() = if (memoryTotal > 0) memoryUsed.toDouble() / memoryTotal * 100 else 0.0

    companion object {
        fun from(json: JsonObject) = GpuMetrics(
            index = json.int("index"),
            name = json.string("name", default = "GPU"),
            vendor = json.string("vendor"),
            usagePercent = json.double("usage_percent", "usagePercent"),
            memoryTotal = json.long("memory_total", "memoryTotal"),
            memoryUsed = json.long("memory_used", "memoryUsed"),
            temperature = json.doubleOrNull("temperature"),
            powerWatts = json.doubleOrNull("power_watts", "powerWatts"),
            fanSpeedPercent = json.doubleOrNull("fan_speed_percent", "fanSpeedPercent"),
            driverVersion = json.stringOrNull("driver_version", "driverVersion"),
            pcieGeneration = json.stringOrNull("pcie_generation", "pcieGeneration"),
            powerLimitWatts = json.doubleOrNull("power_limit_watts", "powerLimitWatts"),
        )
    }
}

data class NpuMetrics(
    val index: Int,
    val name: String,
    val vendor: String,
    val usagePercent: Double,
    val temperature: Double?,
    val powerWatts: Double?,
) {
    val id: Int get() = index

    companion object {
        fun from(json: JsonObject) = NpuMetrics(
            index = json.int("index"),
            name = json.string("name", default = "NPU"),
            vendor = json.string("vendor"),
            usagePercent = json.double("usage_percent", "usagePercent"),
            temperature = json.doubleOrNull("temperature"),
            powerWatts = json.doubleOrNull("power_watts", "powerWatts"),
        )
    }
}

data class UserSession(
    val username: String,
    val tty: String,
    val loginTime: String,
    val remoteHost: String,
    val idleSeconds: Int,
    val sessionType: String,
) {
    val id: String get() = "$username|$tty"

    companion object {
        fun from(json: JsonObject) = UserSession(
            username = json.string("username", "user"),
            tty = json.string("tty"),
            loginTime = json.string("login_time", "loginTime"),
            remoteHost = json.string("remote_host", "remoteHost"),
            idleSeconds = json.int("idle_seconds", "idleSeconds"),
            sessionType = json.string("session_type", "sessionType"),
        )
    }
}

data class SystemInfo(
    val osName: String,
    val osVersion: String,
    val kernelVersion: String,
    val hostname: String,
    val bootTime: String,
    val uptimeSeconds: Long,
    val motherboardVendor: String?,
    val motherboardName: String?,
    val biosVersion: String?,
    val systemModel: String?,
    val systemVendor: String?,
    val chassis: String?,
    val primaryIp: String?,
) {
    companion object {
        fun from(json: JsonObject) = SystemInfo(
            osName = json.string("os_name", "osName"),
            osVersion = json.string("os_version", "osVersion"),
            kernelVersion = json.string("kernel_version", "kernelVersion"),
            hostname = json.string("hostname"),
            bootTime = json.string("boot_time", "bootTime"),
            uptimeSeconds = json.long("uptime_seconds", "uptimeSeconds"),
            motherboardVendor = json.stringOrNull("motherboard_vendor", "motherboardVendor"),
            motherboardName = json.stringOrNull("motherboard_name", "motherboardName"),
            biosVersion = json.stringOrNull("bios_version", "biosVersion"),
            systemModel = json.stringOrNull("system_model", "systemModel"),
            systemVendor = json.stringOrNull("system_vendor", "systemVendor"),
            chassis = json.stringOrNull("chassis"),
            primaryIp = json.stringOrNull("primary_ip", "primaryIp"),
        )
    }
}

data class AgentMetrics(
    val agentId: String,
    val cpu: CpuMetrics,
    val memory: MemoryMetrics,
    val disks: List<DiskMetrics>,
    val networks: List<NetworkMetrics>,
    val gpus: List<GpuMetrics>,
    val npus: List<NpuMetrics>,
    val userSessions: List<UserSession>,
    val systemInfo: SystemInfo?,
    val timestampMillis: Long?,
) {
    val cpuPercent: Double get() = cpu.usagePercent
    val memoryPercent: Double get() = memory.usagePercent
    val diskPercent: Double get() = disks.maxOfOrNull { it.usagePercent } ?: 0.0
    val networkIn: Double get() = networks.sumOf { it.rxBytesPerSec }
    val networkOut: Double get() = networks.sumOf { it.txBytesPerSec }

    companion object {
        fun from(json: JsonObject): AgentMetrics {
            val disks = json.objects("disks").map(DiskMetrics::from).ifEmpty {
                json.obj("disk")?.let { listOf(DiskMetrics.from(it)) }.orEmpty()
            }
            val networks = json.objects("networks").map(NetworkMetrics::from).ifEmpty {
                json.obj("network")?.let { listOf(NetworkMetrics.from(it)) }.orEmpty()
            }
            val gpus = json.objects("gpus").map(GpuMetrics::from).ifEmpty {
                json.obj("gpu")?.let { listOf(GpuMetrics.from(it)) }.orEmpty()
            }
            val npus = json.objects("npus").map(NpuMetrics::from).ifEmpty {
                json.obj("npu")?.let { listOf(NpuMetrics.from(it)) }.orEmpty()
            }
            return AgentMetrics(
                agentId = json.string("agent_id", "agentId"),
                cpu = json.obj("cpu")?.let(CpuMetrics::from) ?: CpuMetrics(),
                memory = json.obj("memory")?.let(MemoryMetrics::from) ?: MemoryMetrics(),
                disks = disks,
                networks = networks,
                gpus = gpus,
                npus = npus,
                userSessions = json.objects("user_sessions", "userSessions").map(UserSession::from),
                systemInfo = json.obj("system_info", "systemInfo")?.let(SystemInfo::from),
                timestampMillis = timestampMillis(json["timestamp"]),
            )
        }
    }
}

data class AlertInstance(
    val id: String,
    val level: String,
    val title: String,
    val description: String,
    val agent: String,
    val rule: String,
    val since: String,
    val acked: Boolean,
    val ackedBy: String,
    val value: Double?,
) {
    companion object {
        fun from(json: JsonObject) = AlertInstance(
            id = json.string("id"),
            level = json.string("level", default = "info"),
            title = json.string("title"),
            description = json.string("desc", "description"),
            agent = json.string("agent"),
            rule = json.string("rule"),
            since = json.string("since"),
            acked = json.bool("ack", "acked"),
            ackedBy = json.string("ackBy", "ackedBy"),
            value = json.doubleOrNull("value"),
        )
    }
}

data class AuditEntry(
    val id: String,
    val type: String,
    val user: String,
    val agentId: String,
    val agentHostname: String,
    val target: String,
    val params: String,
    val ok: Boolean,
    val error: String,
    val durationMs: Int,
    val atMillis: Long,
) {
    val paramsMap: Map<String, String>
        get() = runCatching {
            NanoJson.parseToJsonElement(params).jsonObject.mapValues { (_, value) ->
                (value as? JsonPrimitive)?.contentOrNull ?: value.toString()
            }
        }.getOrDefault(emptyMap())

    companion object {
        fun from(json: JsonObject): AuditEntry {
            val params = when (val value = json["params"]) {
                is JsonPrimitive -> value.contentOrNull.orEmpty()
                is JsonObject -> value.toString()
                else -> ""
            }
            return AuditEntry(
                id = json.string("id"),
                type = json.string("commandType", "type"),
                user = json.string("username", "user"),
                agentId = json.string("agentId", "agent_id"),
                agentHostname = json.string("agentHostname", "agent_hostname"),
                target = json.string("target"),
                params = params,
                ok = json.bool("success", "ok", default = true),
                error = json.string("error"),
                durationMs = json.int("durationMs", "duration_ms"),
                atMillis = timestampMillis(json.element("timestamp", "at")) ?: System.currentTimeMillis(),
            )
        }
    }
}

data class ChatMessage(
    val id: String = UUID.randomUUID().toString(),
    val role: String,
    val content: String,
)
