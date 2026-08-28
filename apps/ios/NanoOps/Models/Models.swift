import Foundation

// MARK: - JSON access helper

/// Tolerant reader over `JSONSerialization` output (`[String: Any]`). Server
/// payloads mix snake_case / camelCase and numbers-as-strings, so every getter
/// coerces defensively and accepts a list of candidate keys.
struct JSON {
    let raw: [String: Any]
    init(_ raw: [String: Any]) { self.raw = raw }

    static func parse(_ data: Data) -> JSON? {
        (try? JSONSerialization.jsonObject(with: data)) .flatMap { $0 as? [String: Any] }.map(JSON.init)
    }

    private func value(_ keys: [String]) -> Any? {
        for k in keys { if let v = raw[k], !(v is NSNull) { return v } }
        return nil
    }

    func string(_ keys: String..., default def: String = "") -> String {
        guard let v = value(keys) else { return def }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return def
    }

    func stringOrNil(_ keys: String...) -> String? {
        guard let v = value(keys) else { return nil }
        if let s = v as? String { return s.isEmpty ? nil : s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    func int(_ keys: String..., default def: Int = 0) -> Int {
        guard let v = value(keys) else { return def }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String, let i = Int(s) { return i }
        return def
    }

    func double(_ keys: String..., default def: Double = 0) -> Double {
        guard let v = value(keys) else { return def }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String, let d = Double(s) { return d }
        return def
    }

    func doubleOrNil(_ keys: String...) -> Double? {
        guard let v = value(keys) else { return nil }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }

    func bool(_ keys: String..., default def: Bool = false) -> Bool {
        guard let v = value(keys) else { return def }
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String { return s == "true" || s == "1" }
        return def
    }

    func obj(_ keys: String...) -> JSON? {
        (value(keys) as? [String: Any]).map(JSON.init)
    }

    func list(_ keys: String...) -> [JSON] {
        (value(keys) as? [Any])?.compactMap { ($0 as? [String: Any]).map(JSON.init) } ?? []
    }

    func doubleList(_ keys: String...) -> [Double] {
        (value(keys) as? [Any])?.compactMap {
            if let n = $0 as? NSNumber { return n.doubleValue }
            if let s = $0 as? String { return Double(s) }
            return nil
        } ?? []
    }

    func stringList(_ keys: String...) -> [String] {
        (value(keys) as? [Any])?.compactMap { $0 as? String } ?? []
    }
}

/// Parse an RFC3339 / ISO8601 timestamp, or a unix seconds/millis number.
enum DateParse {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(_ any: Any?) -> Date? {
        guard let any = any, !(any is NSNull) else { return nil }
        if let s = any as? String {
            if let d = iso.date(from: s) ?? isoPlain.date(from: s) { return d }
            if let n = Double(s) { return fromNumber(n) }
            return nil
        }
        if let n = any as? NSNumber { return fromNumber(n.doubleValue) }
        return nil
    }

    private static func fromNumber(_ n: Double) -> Date {
        // Heuristic: > 10^12 → milliseconds.
        n > 1_000_000_000_000 ? Date(timeIntervalSince1970: n / 1000) : Date(timeIntervalSince1970: n)
    }
}

// MARK: - Persisted server connection

/// A configured NanoOps server. Secrets (`token` / `userToken`) live in the
/// Keychain; metadata is stored in UserDefaults. `authToken` prefers the account
/// (user) token which carries full permissions over a read-only device token.
struct ServerConnection: Identifiable, Equatable {
    var id: String
    var name: String
    var url: String
    var token: String?          // device token (read-only)
    var userToken: String?      // account token (full permissions)
    var username: String?
    var isConnected: Bool = false      // runtime only, not persisted
    var lastConnected: Date?
    var forceTls: Bool = false
    var ignoreCert: Bool = false

    var authToken: String? { userToken ?? token }
    var hasFullPermissions: Bool { userToken != nil }

    init(id: String = UUID().uuidString,
         name: String,
         url: String,
         token: String? = nil,
         userToken: String? = nil,
         username: String? = nil,
         lastConnected: Date? = nil,
         forceTls: Bool = false,
         ignoreCert: Bool = false) {
        self.id = id
        self.name = name
        self.url = url
        self.token = token
        self.userToken = userToken
        self.username = username
        self.lastConnected = lastConnected
        self.forceTls = forceTls
        self.ignoreCert = ignoreCert
    }

    /// Non-secret metadata dictionary persisted to UserDefaults.
    func metadataDict() -> [String: Any] {
        var m: [String: Any] = ["id": id, "name": name, "url": url,
                                "forceTls": forceTls, "ignoreCert": ignoreCert]
        if let username = username { m["username"] = username }
        if let lastConnected = lastConnected {
            m["lastConnected"] = ISO8601DateFormatter().string(from: lastConnected)
        }
        return m
    }

    static func fromMetadata(_ j: JSON) -> ServerConnection? {
        let id = j.string("id")
        let url = j.string("url")
        guard !id.isEmpty, !url.isEmpty else { return nil }
        return ServerConnection(
            id: id,
            name: j.string("name", default: "Server"),
            url: url,
            username: j.stringOrNil("username"),
            lastConnected: DateParse.date(j.raw["lastConnected"]),
            forceTls: j.bool("forceTls"),
            ignoreCert: j.bool("ignoreCert")
        )
    }
}

// MARK: - Agent

struct Agent: Identifiable, Equatable {
    var id: String
    var serverId: String
    var hostname: String
    var os: String
    var arch: String
    var version: String
    var permissionLevel: Int
    var connectedAt: Date?
    var lastHeartbeat: Date?

    var isOnline: Bool {
        guard let hb = lastHeartbeat else { return false }
        return Date().timeIntervalSince(hb) < 60
    }

    static func from(_ j: JSON, serverId: String) -> Agent {
        Agent(
            id: j.string("id", "agent_id", "agentId"),
            serverId: serverId,
            hostname: j.string("hostname", default: tr("common.unknown")),
            os: j.string("os", default: ""),
            arch: j.string("arch", default: ""),
            version: j.string("version", default: ""),
            permissionLevel: j.int("permission_level", "permissionLevel"),
            connectedAt: DateParse.date(j.raw["connected_at"] ?? j.raw["connectedAt"]),
            lastHeartbeat: DateParse.date(j.raw["last_heartbeat"] ?? j.raw["lastHeartbeat"])
        )
    }
}

// MARK: - Metrics

struct CpuMetrics {
    var usagePercent: Double
    var coreCount: Int
    var perCoreUsage: [Double]
    var model: String
    var temperature: Double?
    var loadAverage: [Double]
    var frequencyMhz: Double?
    var frequencyGhz: Double? { frequencyMhz.map { $0 / 1000 } }

    static func from(_ j: JSON) -> CpuMetrics {
        CpuMetrics(
            usagePercent: j.double("usage_percent", "usagePercent"),
            coreCount: j.int("core_count", "coreCount"),
            perCoreUsage: j.doubleList("per_core_usage", "perCoreUsage"),
            model: j.string("model", default: ""),
            temperature: j.doubleOrNil("temperature"),
            loadAverage: j.doubleList("load_average", "loadAverage"),
            frequencyMhz: j.doubleOrNil("frequency_mhz", "frequencyMhz")
        )
    }
    static let empty = CpuMetrics(usagePercent: 0, coreCount: 0, perCoreUsage: [], model: "", temperature: nil, loadAverage: [], frequencyMhz: nil)
}

struct MemoryMetrics {
    var total: Int
    var used: Int
    var available: Int
    var swapTotal: Int
    var swapUsed: Int
    var cached: Int
    var buffers: Int
    var memoryType: String?
    var memorySpeedMhz: Int?
    var usagePercent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }

    static func from(_ j: JSON) -> MemoryMetrics {
        MemoryMetrics(
            total: j.int("total"),
            used: j.int("used"),
            available: j.int("available"),
            swapTotal: j.int("swap_total", "swapTotal"),
            swapUsed: j.int("swap_used", "swapUsed"),
            cached: j.int("cached"),
            buffers: j.int("buffers"),
            memoryType: j.stringOrNil("memory_type", "memoryType"),
            memorySpeedMhz: j.raw["memory_speed_mhz"] != nil || j.raw["memorySpeedMhz"] != nil ? j.int("memory_speed_mhz", "memorySpeedMhz") : nil
        )
    }
    static let empty = MemoryMetrics(total: 0, used: 0, available: 0, swapTotal: 0, swapUsed: 0, cached: 0, buffers: 0, memoryType: nil, memorySpeedMhz: nil)
}

struct DiskMetrics: Identifiable {
    var mountPoint: String
    var device: String
    var fsType: String
    var total: Int
    var used: Int
    var available: Int
    var readBytesPerSec: Double
    var writeBytesPerSec: Double
    var diskType: String?
    var temperature: Double?
    var healthStatus: String?
    var id: String { "\(device)|\(mountPoint)" }
    var usagePercent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }

    static func from(_ j: JSON) -> DiskMetrics {
        DiskMetrics(
            mountPoint: j.string("mount_point", "mountPoint"),
            device: j.string("device"),
            fsType: j.string("fs_type", "fsType"),
            total: j.int("total"),
            used: j.int("used"),
            available: j.int("available"),
            readBytesPerSec: j.double("read_bytes_per_sec", "readBytesPerSec"),
            writeBytesPerSec: j.double("write_bytes_per_sec", "writeBytesPerSec"),
            diskType: j.stringOrNil("disk_type", "diskType"),
            temperature: j.doubleOrNil("temperature"),
            healthStatus: j.stringOrNil("health_status", "healthStatus")
        )
    }
}

struct NetworkMetrics: Identifiable {
    var interfaceName: String
    var rxBytesPerSec: Double
    var txBytesPerSec: Double
    var isUp: Bool
    var macAddress: String?
    var ipAddresses: [String]
    var speedMbps: Double?
    var interfaceType: String?
    var id: String { interfaceName }

    static func from(_ j: JSON) -> NetworkMetrics {
        NetworkMetrics(
            interfaceName: j.string("interface", "interface_", "name"),
            rxBytesPerSec: j.double("rx_bytes_per_sec", "rxBytesPerSec"),
            txBytesPerSec: j.double("tx_bytes_per_sec", "txBytesPerSec"),
            isUp: j.bool("is_up", "isUp", default: true),
            macAddress: j.stringOrNil("mac_address", "macAddress"),
            ipAddresses: j.stringList("ip_addresses", "ipAddresses"),
            speedMbps: j.doubleOrNil("speed_mbps", "speedMbps"),
            interfaceType: j.stringOrNil("interface_type", "interfaceType")
        )
    }
}

struct GpuMetrics: Identifiable {
    var index: Int
    var name: String
    var vendor: String
    var usagePercent: Double
    var memoryTotal: Int
    var memoryUsed: Int
    var temperature: Double?
    var powerWatts: Double?
    var fanSpeedPercent: Double?
    var driverVersion: String?
    var pcieGeneration: String?
    var powerLimitWatts: Double?
    var id: Int { index }
    var vramPercent: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) * 100 : 0 }

    static func from(_ j: JSON) -> GpuMetrics {
        GpuMetrics(
            index: j.int("index"),
            name: j.string("name", default: "GPU"),
            vendor: j.string("vendor", default: ""),
            usagePercent: j.double("usage_percent", "usagePercent"),
            memoryTotal: j.int("memory_total", "memoryTotal"),
            memoryUsed: j.int("memory_used", "memoryUsed"),
            temperature: j.doubleOrNil("temperature"),
            powerWatts: j.doubleOrNil("power_watts", "powerWatts"),
            fanSpeedPercent: j.doubleOrNil("fan_speed_percent", "fanSpeedPercent"),
            driverVersion: j.stringOrNil("driver_version", "driverVersion"),
            pcieGeneration: j.stringOrNil("pcie_generation", "pcieGeneration"),
            powerLimitWatts: j.doubleOrNil("power_limit_watts", "powerLimitWatts")
        )
    }
}

struct NpuMetrics: Identifiable {
    var index: Int
    var name: String
    var vendor: String
    var usagePercent: Double
    var temperature: Double?
    var powerWatts: Double?
    var id: Int { index }

    static func from(_ j: JSON) -> NpuMetrics {
        NpuMetrics(
            index: j.int("index"),
            name: j.string("name", default: "NPU"),
            vendor: j.string("vendor", default: ""),
            usagePercent: j.double("usage_percent", "usagePercent"),
            temperature: j.doubleOrNil("temperature"),
            powerWatts: j.doubleOrNil("power_watts", "powerWatts")
        )
    }
}

struct UserSession: Identifiable {
    var username: String
    var tty: String
    var loginTime: String
    var remoteHost: String
    var idleSeconds: Int
    var sessionType: String
    var id: String { "\(username)|\(tty)" }

    static func from(_ j: JSON) -> UserSession {
        UserSession(
            username: j.string("username", "user"),
            tty: j.string("tty"),
            loginTime: j.string("login_time", "loginTime"),
            remoteHost: j.string("remote_host", "remoteHost"),
            idleSeconds: j.int("idle_seconds", "idleSeconds"),
            sessionType: j.string("session_type", "sessionType")
        )
    }
}

struct SystemInfo {
    var osName: String
    var osVersion: String
    var kernelVersion: String
    var hostname: String
    var bootTime: String
    var uptimeSeconds: Int
    var motherboardVendor: String?
    var motherboardName: String?
    var biosVersion: String?
    var systemModel: String?
    var systemVendor: String?
    var chassis: String?
    var primaryIp: String?

    static func from(_ j: JSON) -> SystemInfo {
        SystemInfo(
            osName: j.string("os_name", "osName"),
            osVersion: j.string("os_version", "osVersion"),
            kernelVersion: j.string("kernel_version", "kernelVersion"),
            hostname: j.string("hostname"),
            bootTime: j.string("boot_time", "bootTime"),
            uptimeSeconds: j.int("uptime_seconds", "uptimeSeconds"),
            motherboardVendor: j.stringOrNil("motherboard_vendor", "motherboardVendor"),
            motherboardName: j.stringOrNil("motherboard_model", "motherboardModel", "motherboard_name", "motherboardName"),
            biosVersion: j.stringOrNil("bios_version", "biosVersion"),
            systemModel: j.stringOrNil("system_model", "systemModel"),
            systemVendor: j.stringOrNil("system_vendor", "systemVendor"),
            chassis: j.stringOrNil("chassis"),
            primaryIp: j.stringOrNil("primary_ip", "primaryIp")
        )
    }
}

/// Aggregated per-agent metrics snapshot. The server historically shipped either
/// singular (`disk`, `network`, `gpu`) or plural array forms; both are accepted.
struct AgentMetrics {
    var agentId: String
    var cpu: CpuMetrics
    var memory: MemoryMetrics
    var disks: [DiskMetrics]
    var networks: [NetworkMetrics]
    var gpus: [GpuMetrics]
    var npus: [NpuMetrics]
    var userSessions: [UserSession]
    var systemInfo: SystemInfo?
    var timestamp: Date?

    // Legacy convenience accessors used by list rows / KPI aggregation.
    var cpuPercent: Double { cpu.usagePercent }
    var memoryPercent: Double { memory.usagePercent }
    var diskPercent: Double { disks.map { $0.usagePercent }.max() ?? 0 }
    var networkIn: Double { networks.reduce(0) { $0 + $1.rxBytesPerSec } }
    var networkOut: Double { networks.reduce(0) { $0 + $1.txBytesPerSec } }

    static func from(_ j: JSON) -> AgentMetrics {
        // disks: plural array, else singular object.
        var disks = j.list("disks").map(DiskMetrics.from)
        if disks.isEmpty, let d = j.obj("disk") { disks = [DiskMetrics.from(d)] }

        var networks = j.list("networks").map(NetworkMetrics.from)
        if networks.isEmpty, let n = j.obj("network") { networks = [NetworkMetrics.from(n)] }

        var gpus = j.list("gpus").map(GpuMetrics.from)
        if gpus.isEmpty, let g = j.obj("gpu") { gpus = [GpuMetrics.from(g)] }

        var npus = j.list("npus").map(NpuMetrics.from)
        if npus.isEmpty, let n = j.obj("npu") { npus = [NpuMetrics.from(n)] }

        return AgentMetrics(
            agentId: j.string("agent_id", "agentId"),
            cpu: j.obj("cpu").map(CpuMetrics.from) ?? .empty,
            memory: j.obj("memory").map(MemoryMetrics.from) ?? .empty,
            disks: disks,
            networks: networks,
            gpus: gpus,
            npus: npus,
            userSessions: j.list("user_sessions", "userSessions").map(UserSession.from),
            systemInfo: j.obj("system_info", "systemInfo").map(SystemInfo.from),
            timestamp: DateParse.date(j.raw["timestamp"])
        )
    }
}

// MARK: - Alerts / Audit / Chat

struct AlertInstance: Identifiable {
    var id: String
    var level: String       // crit | warn | info
    var title: String
    var description: String
    var agent: String
    var rule: String
    var since: String
    var acked: Bool
    var ackedBy: String
    var value: Double?

    static func from(_ j: JSON) -> AlertInstance {
        AlertInstance(
            id: j.string("id"),
            level: j.string("level", default: "info"),
            title: j.string("title"),
            description: j.string("desc", "description"),
            agent: j.string("agent"),
            rule: j.string("rule"),
            since: j.string("since"),
            acked: j.bool("ack", "acked"),
            ackedBy: j.string("ackBy", "ackedBy"),
            value: j.doubleOrNil("value")
        )
    }
}

struct AuditEntry: Identifiable {
    var id: String
    var type: String            // commandType
    var user: String            // username
    var agentId: String
    var agentHostname: String
    var target: String
    var params: String          // raw JSON string
    var ok: Bool                // success
    var error: String
    var durationMs: Int
    var at: Date

    /// Decoded params (raw string may be a JSON object).
    var paramsMap: [String: String] {
        guard let data = params.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in obj { out[k] = "\(v)" }
        return out
    }

    static func from(_ j: JSON) -> AuditEntry {
        AuditEntry(
            id: j.string("id"),
            type: j.string("commandType", "type"),
            user: j.string("username", "user"),
            agentId: j.string("agentId", "agent_id"),
            agentHostname: j.string("agentHostname", "agent_hostname"),
            target: j.string("target"),
            params: {
                if let s = j.raw["params"] as? String { return s }
                if let m = j.raw["params"] as? [String: Any],
                   let d = try? JSONSerialization.data(withJSONObject: m),
                   let s = String(data: d, encoding: .utf8) { return s }
                return ""
            }(),
            ok: j.bool("success", "ok", default: true),
            error: j.string("error"),
            durationMs: j.int("durationMs", "duration_ms"),
            at: DateParse.date(j.raw["timestamp"] ?? j.raw["at"]) ?? Date()
        )
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    var role: String        // user | assistant
    var content: String
}
