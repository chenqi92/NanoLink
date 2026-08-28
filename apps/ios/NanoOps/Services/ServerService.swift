import Foundation

// MARK: - Client version

/// Native client version reported to the server.
let clientVersion = "0.3.3"

// MARK: - Connection status

enum ConnectionMode {
    case disconnected
    case websocket
    case httpPolling
}

struct ConnectionStatus {
    var isConnected: Bool
    var mode: ConnectionMode
    var lastUpdate: Date?
    var error: String?

    static let disconnected = ConnectionStatus(isConnected: false, mode: .disconnected)
}

// MARK: - Value types returned by the API

struct ServerSummary {
    var connectedAgents: Int = 0
    var avgCpuUsage: Double = 0
    var avgMemoryUsage: Double = 0
    var totalAlerts: Int = 0

    static func from(_ j: JSON) -> ServerSummary {
        ServerSummary(
            connectedAgents: j.int("connectedAgents"),
            avgCpuUsage: j.double("avgCpuUsage"),
            avgMemoryUsage: j.double("avgMemoryUsage"),
            totalAlerts: j.int("totalAlerts")
        )
    }
}

/// One auto-diagnosis finding from `GET /api/assistant/findings`.
struct AssistantFinding: Identifiable {
    let id = UUID()
    var kind: String        // anomaly | warn | info | ok
    var title: String
    var detail: String
    var agentId: String?
    var actions: [String]

    static func from(_ j: JSON) -> AssistantFinding {
        let fallbackTitle = j.string("title")
        let (code, legacyParams) = legacyCodeAndParams(for: fallbackTitle)
        let findingCode = j.string("code", default: code)
        let params = j.obj("params")
        let named: [String: CustomStringConvertible] = [
            "host": params?.string("host", default: legacyParams["host"] ?? "") ?? legacyParams["host"] ?? "",
            "mount": params?.string("mount", default: legacyParams["mount"] ?? "") ?? legacyParams["mount"] ?? "",
            "value": params?.string("value", default: legacyParams["value"] ?? "") ?? legacyParams["value"] ?? "",
        ]
        let titleKey = findingCode.isEmpty ? "" : "assistant.finding.\(findingCode).title"
        let translatedTitle = titleKey.isEmpty ? fallbackTitle : tr(titleKey, named)
        let localizedTitle = translatedTitle == titleKey ? fallbackTitle : translatedTitle
        let detailKey = findingCode.isEmpty ? "" : "assistant.finding.\(findingCode).detail"
        let fallbackDetail = j.string("detail")
        let translatedDetail = detailKey.isEmpty ? fallbackDetail : tr(detailKey, named)
        let localizedDetail = translatedDetail == detailKey ? fallbackDetail : translatedDetail
        let actions = j.stringList("actions").compactMap(normalizedAction)

        return AssistantFinding(
            kind: j.string("kind", default: "info"),
            title: localizedTitle,
            detail: localizedDetail,
            agentId: j.stringOrNil("agentId"),
            actions: actions
        )
    }

    private static func normalizedAction(_ raw: String) -> String? {
        switch raw.lowercased() {
        case "view history", "history": return "history"
        case "open shell", "shell", "terminal": return "shell"
        // The iOS detail screen has no process-list destination yet; hiding the
        // unsupported shortcut is better than opening an unrelated tab.
        case "list processes", "processes": return nil
        default: return nil
        }
    }

    private static func legacyCodeAndParams(for title: String) -> (String, [String: String]) {
        if title == "Fleet healthy" { return ("fleetHealthy", [:]) }
        if title == "No agents assigned" { return ("noAgents", [:]) }
        if let values = captures(#"^(.+) CPU sustained at ([0-9.]+)%$"#, in: title) {
            return ("cpuHigh", ["host": values[0], "value": values[1]])
        }
        if let values = captures(#"^(.+) memory pressure at ([0-9.]+)%$"#, in: title) {
            return ("memoryHigh", ["host": values[0], "value": values[1]])
        }
        if let values = captures(#"^(.+) (/.+) at ([0-9.]+)% full$"#, in: title) {
            return ("diskHigh", ["host": values[0], "mount": values[1], "value": values[2]])
        }
        if let values = captures(#"^(.+) GPU sustained at ([0-9.]+)%$"#, in: title) {
            return ("gpuHigh", ["host": values[0], "value": values[1]])
        }
        if let values = captures(#"^(.+) is offline$"#, in: title) {
            return ("offline", ["host": values[0]])
        }
        return ("", [:])
    }

    private static func captures(_ pattern: String, in value: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else {
            return nil
        }
        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: value).map { String(value[$0]) }
        }
    }
}

/// Result of generating a device pairing token (`POST /api/devices/token`).
struct DeviceTokenResult {
    var qrData: String
    var pairingCode: String
    var permissionLevel: Int = 0
    var expiresAt: Date?
}

/// Server version information from the WebSocket welcome message.
struct ServerInfo {
    var version: String
    var minVersion: String
    var serverTime: Int
    var features: [String]

    static func from(_ j: JSON) -> ServerInfo {
        ServerInfo(
            version: j.string("version", default: "0.0.0"),
            minVersion: j.string("minVersion", default: "0.0.0"),
            serverTime: j.int("serverTime"),
            features: j.stringList("features")
        )
    }

    func isCompatible(_ client: String) -> Bool {
        ServerInfo.compare(client, minVersion) >= 0
    }

    static func compare(_ v1: String, _ v2: String) -> Int {
        let p1 = v1.split(separator: ".").map { Int($0) ?? 0 }
        let p2 = v2.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<3 {
            let a = i < p1.count ? p1[i] : 0
            let b = i < p2.count ? p2[i] : 0
            if a < b { return -1 }
            if a > b { return 1 }
        }
        return 0
    }
}

// MARK: - Login

enum LoginError {
    case invalidCredentials   // 401
    case rateLimited          // 429
    case badRequest           // 400
    case serverError          // 5xx
    case network              // transport/timeout/parse
}

struct LoginResult {
    var token: String?
    var error: LoginError?
    var message: String?
    var statusCode: Int?

    var ok: Bool { token != nil && error == nil }

    static func success(_ token: String) -> LoginResult {
        LoginResult(token: token, error: nil, message: nil, statusCode: 200)
    }
    static func failure(_ error: LoginError, message: String? = nil, statusCode: Int? = nil) -> LoginResult {
        LoginResult(token: nil, error: error, message: message, statusCode: statusCode)
    }
}

// MARK: - Assistant chat

enum AssistantChatError {
    case notConfigured        // 503
    case badRequest           // 400
    case upstreamFailed       // 502
    case serverError          // other non-2xx
    case network
}

struct AssistantChatResult {
    var reply: ChatMessage?
    var error: AssistantChatError?
    var message: String?
    var statusCode: Int?

    var ok: Bool { reply != nil && error == nil }

    static func success(_ reply: ChatMessage) -> AssistantChatResult {
        AssistantChatResult(reply: reply, error: nil, message: nil, statusCode: 200)
    }
    static func failure(_ error: AssistantChatError, message: String? = nil, statusCode: Int? = nil) -> AssistantChatResult {
        AssistantChatResult(reply: nil, error: error, message: message, statusCode: statusCode)
    }
}

// MARK: - Command dispatch / result

struct CommandDispatch {
    var commandId: String?
    var error: String?
    var ok: Bool { commandId != nil && error == nil }

    static func success(_ id: String) -> CommandDispatch { CommandDispatch(commandId: id, error: nil) }
    static func failure(_ error: String) -> CommandDispatch { CommandDispatch(commandId: nil, error: error) }
}

enum CommandResultStatus { case ready, pending, denied, error }

struct CommandResult {
    var status: CommandResultStatus
    var data: [String: Any]?
    var message: String?

    var isReady: Bool { status == .ready }
    var isPending: Bool { status == .pending }
}

/// Result of validating a device token at add-time (`POST /api/auth/device`).
struct DeviceAuthResult {
    var ok: Bool
    var permissionLevel: Int = 0
    var serverName: String = ""
    var error: String?
    var statusCode: Int?
}

// MARK: - Metrics history

/// Parsed historical metrics for one agent, shaped for the history charts.
/// Handles both backend response shapes (DB-aggregated and in-memory).
struct MetricsHistory {
    var times: [Date] = []
    var cpu: [Double] = []       // %
    var mem: [Double] = []       // %
    var netRx: [Double] = []     // MB/s
    var netTx: [Double] = []     // MB/s
    var diskRead: [Double] = []  // MB/s
    var diskWrite: [Double] = [] // MB/s
    var gpuUsage: [Double] = []  // %
    var gpuTemp: [Double] = []   // °C (may be empty)
    var cpuMax: [Double] = []
    var memMax: [Double] = []
    var loadAvg: [Double] = []

    var isEmpty: Bool { cpu.isEmpty }
    var hasGpu: Bool { !gpuUsage.isEmpty && gpuUsage.contains { $0 > 0 } }
    var hasMaxBands: Bool { !cpuMax.isEmpty || !memMax.isEmpty }

    static func parse(_ raw: [Any]) -> MetricsHistory {
        var h = MetricsHistory()
        var anyGpuTemp = false, anyCpuMax = false, anyMemMax = false, anyLoad = false
        let mb = 1_000_000.0

        func n(_ v: Any?) -> Double {
            if let num = v as? NSNumber { return num.doubleValue }
            if let s = v as? String { return Double(s) ?? 0 }
            return 0
        }

        for e in raw {
            guard let m = e as? [String: Any] else { continue }
            h.times.append(DateParse.date(m["timestamp"]) ?? Date(timeIntervalSince1970: 0))

            let cpuMap = m["cpu"] as? [String: Any] ?? [:]
            h.cpu.append(n(cpuMap["usagePercent"]))
            if cpuMap["maxPercent"] != nil { anyCpuMax = true; h.cpuMax.append(n(cpuMap["maxPercent"])) }
            else { h.cpuMax.append(0) }

            let memMap = m["memory"] as? [String: Any] ?? [:]
            let total = n(memMap["total"]), used = n(memMap["used"])
            h.mem.append(total > 0 ? min(100, max(0, used / total * 100)) : 0)
            if memMap["maxPercent"] != nil { anyMemMax = true; h.memMax.append(min(100, max(0, n(memMap["maxPercent"])))) }
            else { h.memMax.append(0) }

            let loadList = m["loadAverage"] as? [Any] ?? []
            if let first = loadList.first { anyLoad = true; h.loadAvg.append(n(first)) }
            else { h.loadAvg.append(0) }

            var rx = 0.0, tx = 0.0
            for net in (m["networks"] as? [Any] ?? []) {
                if let net = net as? [String: Any] { rx += n(net["rxBytesPerSec"]); tx += n(net["txBytesPerSec"]) }
            }
            h.netRx.append(rx / mb); h.netTx.append(tx / mb)

            var rd = 0.0, wr = 0.0
            for d in (m["disks"] as? [Any] ?? []) {
                if let d = d as? [String: Any] { rd += n(d["readBytesPerSec"]); wr += n(d["writeBytesPerSec"]) }
            }
            h.diskRead.append(rd / mb); h.diskWrite.append(wr / mb)

            let gpus = m["gpus"] as? [Any] ?? []
            if let g = gpus.first as? [String: Any] {
                h.gpuUsage.append(n(g["usagePercent"]))
                if g["temperature"] != nil { anyGpuTemp = true; h.gpuTemp.append(n(g["temperature"])) }
                else { h.gpuTemp.append(0) }
            } else {
                h.gpuUsage.append(0); h.gpuTemp.append(0)
            }
        }

        if !anyGpuTemp { h.gpuTemp = [] }
        if !anyCpuMax { h.cpuMax = [] }
        if !anyMemMax { h.memMax = [] }
        if !anyLoad { h.loadAvg = [] }
        return h
    }
}

// MARK: - ServerService

/// Communicates with a NanoOps server over WebSocket (real-time) with an HTTP
/// polling fallback. Ports `server_service.dart`. Emits updates through closure
/// callbacks assigned by the owning `AppStore`; callbacks are invoked on the
/// main queue.
final class ServerService: NSObject {
    let connection: ServerConnection

    private var session: URLSession!
    private var wsTask: URLSessionWebSocketTask?
    private var wsConnected = false
    private var useWebSocket = true
    private var pingTimer: DispatchSourceTimer?
    private var pollingTimer: DispatchSourceTimer?
    private var pollingInterval: TimeInterval = 2
    private(set) var lastPong: Date?
    private(set) var serverInfo: ServerInfo?

    private var cachedAgents: [Agent] = []
    private var cachedMetrics: [String: AgentMetrics] = [:]

    // Callbacks (assigned by AppStore).
    var onAgents: (([Agent]) -> Void)?
    var onMetrics: (([String: AgentMetrics]) -> Void)?
    var onConnection: ((ConnectionStatus) -> Void)?
    var onSummary: ((ServerSummary) -> Void)?
    var onAgentOffline: ((String) -> Void)?
    var onServerInfo: ((ServerInfo) -> Void)?

    var isWebSocketConnected: Bool { wsConnected }
    var connectionMode: ConnectionMode {
        wsConnected ? .websocket : (pollingTimer != nil ? .httpPolling : .disconnected)
    }
    var isCompatibleServer: Bool { serverInfo?.isCompatible(clientVersion) ?? true }

    init(connection: ServerConnection) {
        self.connection = connection
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        // A delegate is required to accept self-signed certs per-connection.
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: URL helpers

    private func httpBaseUrl() -> String {
        var base = connection.url
        if base.hasSuffix("/") { base.removeLast() }
        if connection.forceTls, base.hasPrefix("http://") {
            base = "https://" + base.dropFirst("http://".count)
        }
        return base
    }

    private func buildUrl(_ path: String) -> URL? { URL(string: "\(httpBaseUrl())/api\(path)") }

    private func wsBaseUrl() -> String {
        var base = httpBaseUrl()
        if base.hasPrefix("https://") { base = "wss://" + base.dropFirst("https://".count) }
        else if base.hasPrefix("http://") { base = "ws://" + base.dropFirst("http://".count) }
        return base
    }

    private func buildWsUrl() -> String { "\(wsBaseUrl())/ws/dashboard" }

    private var authHeaders: [String: String] {
        var h = ["Content-Type": "application/json"]
        if let t = connection.authToken, !t.isEmpty { h["Authorization"] = "Bearer \(t)" }
        return h
    }

    /// Open a remote shell session for `agentId` (`/ws/shell/:id`).
    func openShell(_ agentId: String) -> ShellSession {
        let encoded = agentId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? agentId
        let url = URL(string: "\(wsBaseUrl())/ws/shell/\(encoded)")!
        return ShellSession(url: url, token: connection.authToken, ignoreCert: connection.ignoreCert)
    }

    // MARK: Low-level request

    private func perform(_ method: String,
                         _ path: String,
                         body: Any? = nil,
                         headers: [String: String]? = nil,
                         query: [String: String]? = nil,
                         timeout: TimeInterval = 10) async -> (Data, HTTPURLResponse)? {
        guard var comps = buildUrl(path).flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) else { return nil }
        if let query = query, !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = timeout
        for (k, v) in (headers ?? authHeaders) { req.setValue(v, forHTTPHeaderField: k) }
        if let body = body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return nil }
            return (data, http)
        } catch {
            return nil
        }
    }

    private func errorMessage(_ data: Data, _ status: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let e = (obj["error"] ?? obj["details"]) as? String, !e.isEmpty { return e }
        }
        return "HTTP \(status)"
    }

    // MARK: Auth

    func login(_ username: String, _ password: String) async -> String? {
        let headers = ["Content-Type": "application/json", "X-NanoOps-Client": "native"]
        guard let (data, resp) = await perform("POST", "/auth/login",
                                               body: ["username": username, "password": password],
                                               headers: headers) else { return nil }
        guard resp.statusCode == 200, let j = JSON.parse(data) else { return nil }
        return j.stringOrNil("token")
    }

    func loginDetailed(_ username: String, _ password: String) async -> LoginResult {
        let headers = ["Content-Type": "application/json", "X-NanoOps-Client": "native"]
        guard let (data, resp) = await perform("POST", "/auth/login",
                                               body: ["username": username, "password": password],
                                               headers: headers) else {
            return .failure(.network, message: tr("errors.connectionFailed"))
        }
        if resp.statusCode == 200 {
            if let token = JSON.parse(data)?.stringOrNil("token") { return .success(token) }
            return .failure(.serverError, message: tr("errors.loginMissingToken"), statusCode: 200)
        }
        let reason = errorMessage(data, resp.statusCode)
        switch resp.statusCode {
        case 401: return .failure(.invalidCredentials, message: reason, statusCode: 401)
        case 429: return .failure(.rateLimited, message: reason, statusCode: 429)
        case 400: return .failure(.badRequest, message: reason, statusCode: 400)
        default:  return .failure(.serverError, message: reason, statusCode: resp.statusCode)
        }
    }

    func redeemPairingCode(_ code: String) async -> String? {
        guard let (data, resp) = await perform("POST", "/auth/pairing",
                                               body: ["pairingCode": code],
                                               headers: ["Content-Type": "application/json"]) else { return nil }
        guard resp.statusCode == 200 else { return nil }
        return JSON.parse(data)?.stringOrNil("token")
    }

    func testConnection() async -> Bool {
        guard let (_, resp) = await perform("GET", "/health", timeout: 5) else { return false }
        return resp.statusCode == 200
    }

    func validateDeviceToken(_ token: String, deviceName: String, deviceType: String, deviceOs: String) async -> DeviceAuthResult {
        let headers = ["Content-Type": "application/json", "X-Device-Token": token]
        guard let (data, resp) = await perform("POST", "/auth/device",
                                               body: ["deviceName": deviceName, "deviceType": deviceType, "deviceOs": deviceOs],
                                               headers: headers) else {
            return DeviceAuthResult(ok: false, error: tr("errors.connectionFailed"))
        }
        if resp.statusCode == 200, let j = JSON.parse(data) {
            let info = j.obj("serverInfo")
            return DeviceAuthResult(ok: true,
                                    permissionLevel: info?.int("permissionLevel") ?? 0,
                                    serverName: info?.string("name") ?? "",
                                    statusCode: 200)
        }
        return DeviceAuthResult(ok: false, error: errorMessage(data, resp.statusCode), statusCode: resp.statusCode)
    }

    func generateDeviceToken(serverName: String? = nil) async -> DeviceTokenResult? {
        var body: [String: Any] = [:]
        if let serverName = serverName { body["serverName"] = serverName }
        guard let (data, resp) = await perform("POST", "/devices/token", body: body, timeout: 12) else { return nil }
        guard resp.statusCode == 200 || resp.statusCode == 201, let j = JSON.parse(data) else { return nil }
        let qr = j.string("qrData")
        return DeviceTokenResult(qrData: qr,
                                 pairingCode: j.string("pairingCode"),
                                 permissionLevel: j.int("permissionLevel"),
                                 expiresAt: ServerService.qrExpiry(qr))
    }

    private static func qrExpiry(_ qr: String) -> Date? {
        guard !qr.isEmpty,
              let data = Data(base64Encoded: qr),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let e = obj["e"] as? NSNumber, e.doubleValue > 0 else { return nil }
        return Date(timeIntervalSince1970: e.doubleValue)
    }

    // MARK: Fetches

    func fetchAgents() async -> [Agent] {
        guard let (data, resp) = await perform("GET", "/agents") else {
            emitConnection(false, .disconnected, "fetch failed"); return []
        }
        guard resp.statusCode == 200,
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return arr.compactMap { ($0 as? [String: Any]).map { Agent.from(JSON($0), serverId: connection.id) } }
    }

    func fetchMetrics() async -> [String: AgentMetrics] {
        guard let (data, resp) = await perform("GET", "/metrics"),
              resp.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [String: AgentMetrics] = [:]
        for (agentId, v) in obj {
            if let m = v as? [String: Any] { out[agentId] = AgentMetrics.from(JSON(m)) }
        }
        return out
    }

    func fetchMetricsHistory(_ agentId: String, window: TimeInterval, interval: String = "auto", limit: Int = 240) async -> MetricsHistory? {
        let end = Date()
        let start = end.addingTimeInterval(-window)
        let query = [
            "agentId": agentId,
            "start": "\(Int(start.timeIntervalSince1970 * 1000))",
            "end": "\(Int(end.timeIntervalSince1970 * 1000))",
            "interval": interval,
            "limit": "\(limit)",
        ]
        guard let (data, resp) = await perform("GET", "/metrics/history", query: query, timeout: 12) else { return nil }
        guard resp.statusCode == 200 else { return nil }
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] { return MetricsHistory.parse(arr) }
        return MetricsHistory()
    }

    func fetchSummary() async -> ServerSummary? {
        guard let (data, resp) = await perform("GET", "/summary"),
              resp.statusCode == 200, let j = JSON.parse(data) else { return nil }
        return ServerSummary.from(j)
    }

    func fetchAlerts(status: String? = nil) async -> [AlertInstance] {
        var query: [String: String] = [:]
        if let status = status, !status.isEmpty { query["status"] = status }
        guard let (data, resp) = await perform("GET", "/alerts", query: query),
              resp.statusCode == 200,
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        return arr.compactMap { ($0 as? [String: Any]).map { AlertInstance.from(JSON($0)) } }
    }

    func ackAlert(_ id: String) async -> String? {
        guard let (data, resp) = await perform("POST", "/alerts/ack/\(id)") else { return tr("errors.connectionFailed") }
        return resp.statusCode == 200 ? nil : errorMessage(data, resp.statusCode)
    }

    func ackAllAlerts() async -> Int? {
        guard let (data, resp) = await perform("POST", "/alerts/ack-all"),
              resp.statusCode == 200, let j = JSON.parse(data) else { return nil }
        return j.int("count")
    }

    func fetchRecentAudit(limit: Int = 50) async -> [AuditEntry] {
        guard let (data, resp) = await perform("GET", "/audit/recent", query: ["limit": "\(limit)"]),
              resp.statusCode == 200 else { return [] }
        let decoded = try? JSONSerialization.jsonObject(with: data)
        let logs: [Any]?
        if let obj = decoded as? [String: Any] { logs = obj["logs"] as? [Any] }
        else { logs = decoded as? [Any] }
        return (logs ?? []).compactMap { ($0 as? [String: Any]).map { AuditEntry.from(JSON($0)) } }
    }

    func fetchAssistantFindings() async -> [AssistantFinding]? {
        guard let (data, resp) = await perform("GET", "/assistant/findings", timeout: 12) else { return nil }
        guard resp.statusCode == 200 else { return nil }
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return arr.compactMap { ($0 as? [String: Any]).map { AssistantFinding.from(JSON($0)) } }
        }
        return []
    }

    func assistantChat(_ messages: [ChatMessage]) async -> AssistantChatResult {
        let body: [String: Any] = ["messages": messages.map { ["role": $0.role, "content": $0.content] }]
        guard let (data, resp) = await perform("POST", "/assistant/chat", body: body, timeout: 30) else {
            return .failure(.network, message: tr("errors.connectionFailed"))
        }
        if resp.statusCode == 200 {
            let reply = JSON.parse(data)?.string("reply") ?? ""
            return .success(ChatMessage(role: "assistant", content: reply))
        }
        let reason = errorMessage(data, resp.statusCode)
        switch resp.statusCode {
        case 503: return .failure(.notConfigured, message: reason, statusCode: 503)
        case 400: return .failure(.badRequest, message: reason, statusCode: 400)
        case 502: return .failure(.upstreamFailed, message: reason, statusCode: 502)
        default:  return .failure(.serverError, message: reason, statusCode: resp.statusCode)
        }
    }

    // MARK: Commands

    func sendCommand(_ agentId: String, type: String, target: String = "", params: [String: String]? = nil) async -> String? {
        var body: [String: Any] = ["type": type, "target": target]
        if let params = params { body["params"] = params }
        guard let (data, resp) = await perform("POST", "/agents/\(agentId)/command", body: body) else { return tr("errors.connectionFailed") }
        return resp.statusCode == 200 ? nil : errorMessage(data, resp.statusCode)
    }

    func sendCommandReturningId(_ agentId: String, type: String, target: String = "", params: [String: String]? = nil) async -> CommandDispatch {
        var body: [String: Any] = ["type": type, "target": target]
        if let params = params { body["params"] = params }
        guard let (data, resp) = await perform("POST", "/agents/\(agentId)/command", body: body) else {
            return .failure(tr("errors.connectionFailed"))
        }
        if resp.statusCode == 200 {
            if let id = JSON.parse(data)?.stringOrNil("commandId") { return .success(id) }
            return .failure(tr("errors.commandMissingId"))
        }
        return .failure(errorMessage(data, resp.statusCode))
    }

    func pollCommandResult(_ agentId: String, _ commandId: String) async -> CommandResult {
        guard let (data, resp) = await perform("GET", "/agents/\(agentId)/command/\(commandId)/result") else {
            return CommandResult(status: .error, message: tr("errors.connectionFailed"))
        }
        switch resp.statusCode {
        case 200:
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            return CommandResult(status: .ready, data: obj ?? nil)
        case 202: return CommandResult(status: .pending)
        case 403: return CommandResult(status: .denied, message: errorMessage(data, resp.statusCode))
        default:  return CommandResult(status: .error, message: errorMessage(data, resp.statusCode))
        }
    }

    func requestData(_ agentId: String, requestType: String = "full", target: String = "") async -> String? {
        let body: [String: Any] = ["requestType": requestType, "target": target]
        guard let (data, resp) = await perform("POST", "/agents/\(agentId)/data-request", body: body) else { return tr("errors.connectionFailed") }
        return resp.statusCode == 200 ? nil : errorMessage(data, resp.statusCode)
    }

    // MARK: WebSocket

    private func connectWebSocket() {
        guard useWebSocket, !wsConnected, wsTask == nil else { return }
        guard let url = URL(string: buildWsUrl()) else { startPollingInternal(); return }

        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        if let t = connection.authToken, !t.isEmpty { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }

        let task = session.webSocketTask(with: req)
        wsTask = task
        task.resume()
        receiveLoop(task)
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text): self.onWsMessage(text)
                case .data(let data): self.onWsMessage(String(data: data, encoding: .utf8) ?? "")
                @unknown default: break
                }
                // Continue only if this is still the active task.
                if self.wsTask === task { self.receiveLoop(task) }
            case .failure(let error):
                self.onWsClosed(task, error: error)
            }
        }
    }

    private func onWsMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let type = msg["type"] as? String
        let payload = msg["data"]

        switch type {
        case "welcome":
            if let p = payload as? [String: Any] {
                let info = ServerInfo.from(JSON(p))
                serverInfo = info
                emitMain { self.onServerInfo?(info) }
            }

        case "agents":
            if let arr = payload as? [Any] {
                cachedAgents = arr.compactMap { ($0 as? [String: Any]).map { Agent.from(JSON($0), serverId: connection.id) } }
                let snapshot = cachedAgents
                emitMain { self.onAgents?(snapshot) }
            }

        case "agent_update":
            if let p = payload as? [String: Any] {
                let updated = Agent.from(JSON(p), serverId: connection.id)
                if let idx = cachedAgents.firstIndex(where: { $0.id == updated.id }) { cachedAgents[idx] = updated }
                else { cachedAgents.append(updated) }
                let snapshot = cachedAgents
                emitMain { self.onAgents?(snapshot) }
            }

        case "metrics":
            if let p = payload as? [String: Any] {
                if let agentId = p["agentId"] as? String, let metricsData = p["metrics"] as? [String: Any] {
                    cachedMetrics[agentId] = AgentMetrics.from(JSON(metricsData))
                } else {
                    for (key, value) in p {
                        if let m = value as? [String: Any] { cachedMetrics[key] = AgentMetrics.from(JSON(m)) }
                    }
                }
                let snapshot = cachedMetrics
                emitMain { self.onMetrics?(snapshot) }
            }

        case "agent_offline":
            var offlineId: String?
            if let s = payload as? String { offlineId = s }
            else if let p = payload as? [String: Any] { offlineId = p["agentId"] as? String }
            if let id = offlineId {
                cachedAgents.removeAll { $0.id == id }
                cachedMetrics.removeValue(forKey: id)
                let agents = cachedAgents, metrics = cachedMetrics
                emitMain {
                    self.onAgents?(agents)
                    self.onMetrics?(metrics)
                    self.onAgentOffline?(id)
                }
            }

        case "summary":
            if let p = payload as? [String: Any] {
                let summary = ServerSummary.from(JSON(p))
                emitMain { self.onSummary?(summary) }
            }

        case "pong":
            lastPong = Date()

        default:
            break
        }
    }

    private func markWebSocketConnected(_ task: URLSessionWebSocketTask) {
        guard wsTask === task, useWebSocket else { return }
        wsConnected = true
        lastPong = Date()
        stopPolling()
        emitConnection(true, .websocket)
        startPingTimer()
    }

    private func onWsClosed(_ task: URLSessionWebSocketTask,
                            error: Error? = nil,
                            closeCode: URLSessionWebSocketTask.CloseCode? = nil,
                            reason: Data? = nil) {
        guard wsTask === task else { return }
        wsTask = nil
        wsConnected = false
        stopPingTimer()
        task.cancel(with: .goingAway, reason: nil)

        guard useWebSocket else { return }
        let message = webSocketError(task: task, error: error, closeCode: closeCode, reason: reason)
        emitConnection(false, .disconnected, message)
        startPollingInternal(interval: pollingInterval)

        // Reconnect after a delay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self, self.useWebSocket else { return }
            self.connectWebSocket()
        }
    }

    private func webSocketError(task: URLSessionWebSocketTask,
                                error: Error?,
                                closeCode: URLSessionWebSocketTask.CloseCode?,
                                reason: Data?) -> String {
        if let status = (task.response as? HTTPURLResponse)?.statusCode, status >= 400 {
            return "HTTP \(status)"
        }
        if let error { return error.localizedDescription }
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let closeCode {
            if let reasonText, !reasonText.isEmpty {
                return "WebSocket \(closeCode.rawValue): \(reasonText)"
            }
            return "WebSocket closed (\(closeCode.rawValue))"
        }
        return "WebSocket disconnected"
    }

    private func startPingTimer() {
        stopPingTimer()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in self?.sendWsPing() }
        pingTimer = timer
        timer.resume()
    }

    private func stopPingTimer() {
        pingTimer?.cancel()
        pingTimer = nil
    }

    private func sendWsPing() {
        guard wsConnected, let task = wsTask else { return }
        let payload: [String: Any] = ["type": "ping", "timestamp": Int(Date().timeIntervalSince1970 * 1000)]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { [weak self, weak task] error in
            guard let self, let task, let error else { return }
            self.onWsClosed(task, error: error)
        }
    }

    // MARK: Polling

    /// Start real-time updates (WebSocket first, polling fallback).
    func startUpdates(interval: TimeInterval = 2) {
        pollingInterval = interval
        useWebSocket = true
        connectWebSocket()
        // If the socket doesn't come up quickly, fall back to polling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self = self, self.useWebSocket, !self.wsConnected else { return }
            self.startPollingInternal(interval: interval)
        }
    }

    private func startPollingInternal(interval: TimeInterval = 2) {
        guard useWebSocket else { return }
        guard !wsConnected else { return }
        guard pollingTimer == nil else { return }
        Task { await self.fetchAndEmit() }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in Task { await self?.fetchAndEmit() } }
        pollingTimer = timer
        timer.resume()
    }

    private func fetchAndEmit() async {
        guard let (data, response) = await perform("GET", "/agents") else {
            emitConnection(false, .disconnected, "fetch failed")
            return
        }
        guard response.statusCode == 200 else {
            emitConnection(false, .disconnected, errorMessage(data, response.statusCode))
            return
        }
        guard let rawAgents = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            emitConnection(false, .disconnected, "invalid agents response")
            return
        }
        let agents = rawAgents.compactMap {
            ($0 as? [String: Any]).map { Agent.from(JSON($0), serverId: connection.id) }
        }
        cachedAgents = agents
        emitMain { self.onAgents?(agents) }

        let metrics = await fetchMetrics()
        cachedMetrics = metrics
        emitMain { self.onMetrics?(metrics) }

        if let summary = await fetchSummary() {
            emitMain { self.onSummary?(summary) }
        }
        if !wsConnected { emitConnection(true, .httpPolling) }
    }

    func stopPolling() {
        pollingTimer?.cancel()
        pollingTimer = nil
    }

    private func emitConnection(_ connected: Bool, _ mode: ConnectionMode, _ error: String? = nil) {
        let status = ConnectionStatus(isConnected: connected, mode: mode, lastUpdate: Date(), error: error)
        emitMain { self.onConnection?(status) }
    }

    private func emitMain(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }

    // MARK: Teardown

    func dispose() {
        useWebSocket = false
        stopPolling()
        stopPingTimer()
        let task = wsTask
        wsTask = nil
        wsConnected = false
        task?.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }
}

// MARK: - Per-connection TLS

extension ServerService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        markWebSocketConnected(webSocketTask)
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        onWsClosed(webSocketTask, closeCode: closeCode, reason: reason)
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard connection.ignoreCert,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // Accept self-signed / invalid certs for this connection only.
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
