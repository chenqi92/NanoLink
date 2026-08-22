import Foundation
import Combine

/// A critical alert pending a local-notification decision.
private struct PendingAlert {
    let category: String   // offline | high | disk
    let title: String
    let body: String
}

/// Application state manager: owns server connections, aggregates agents /
/// metrics / summaries across all servers, evaluates client-side alert
/// notifications, and handles silent re-authentication on token expiry.
///
/// All mutations occur on the main actor so SwiftUI observation is consistent;
/// `ServerService` delivers its callbacks here already hopped to main.
@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    private let storage = StorageService.shared
    private let notifications = NotificationService.shared
    private var services: [String: ServerService] = [:]

    // MARK: Published state

    @Published private(set) var servers: [ServerConnection] = []
    @Published private(set) var allAgents: [Agent] = []
    @Published private(set) var allMetrics: [String: AgentMetrics] = [:]
    @Published private(set) var serverSummaries: [String: ServerSummary] = [:]
    @Published private(set) var connectionModes: [String: ConnectionMode] = [:]
    @Published private(set) var serverAlertsMap: [String: [AlertInstance]] = [:]
    @Published private(set) var recentActivityMap: [String: [AuditEntry]] = [:]
    @Published private(set) var needsReauthIds: Set<String> = []
    @Published private(set) var isLoading = true
    @Published var activeServerIdRaw: String?

    // MARK: Notification prefs (persisted) + alert-dedup state

    @Published var notifyOffline = false { didSet { UserDefaults.standard.set(notifyOffline, forKey: "notify_offline") } }
    @Published var notifyHigh = false { didSet { UserDefaults.standard.set(notifyHigh, forKey: "notify_high") } }
    @Published var notifyDisk = false { didSet { UserDefaults.standard.set(notifyDisk, forKey: "notify_disk") } }

    private var activeAlerts: Set<String> = []
    private var alertsSeeded = false
    private var latestAuditIds: [String: Set<String>] = [:]
    private var auditPollingTask: Task<Void, Never>?

    // Transient (in-memory only) account passwords for silent re-login.
    private var sessionPasswords: [String: String] = [:]
    private var reauthInFlight: Set<String> = []
    private var hasStarted = false

    private init() {}

    // MARK: Derived accessors

    var activeServerId: String? {
        if let id = activeServerIdRaw, servers.contains(where: { $0.id == id }) { return id }
        return servers.first?.id
    }

    var activeServer: ServerConnection? {
        guard let id = activeServerId else { return nil }
        return servers.first { $0.id == id }
    }

    func setActiveServer(_ serverId: String) {
        guard servers.contains(where: { $0.id == serverId }) else { return }
        activeServerIdRaw = serverId
        PreferencesStore.activeServerId = serverId
    }

    func agentsForServer(_ serverId: String? = nil) -> [Agent] {
        guard let id = serverId ?? activeServerId else { return [] }
        return allAgents.filter { $0.serverId == id }
    }

    func metricsFor(_ agentId: String) -> AgentMetrics? { allMetrics[agentId] }

    func agentById(_ agentId: String) -> Agent? { allAgents.first { $0.id == agentId } }

    func serviceForServer(_ serverId: String) -> ServerService? { services[serverId] }

    func serviceForAgent(_ agentId: String) -> ServerService? {
        guard let agent = agentById(agentId) else { return nil }
        return services[agent.serverId]
    }

    func connectionMode(_ serverId: String) -> ConnectionMode { connectionModes[serverId] ?? .disconnected }

    var activeConnectionMode: ConnectionMode { connectionMode(activeServerId ?? "") }

    func serverAlerts(_ serverId: String? = nil) -> [AlertInstance] {
        guard let id = serverId ?? activeServerId else { return [] }
        return serverAlertsMap[id] ?? []
    }

    func recentActivity(_ serverId: String? = nil) -> [AuditEntry] {
        guard let id = serverId ?? activeServerId else { return [] }
        return recentActivityMap[id] ?? []
    }

    func unackedAlertCount(_ serverId: String? = nil) -> Int {
        serverAlerts(serverId).filter { !$0.acked }.count
    }

    func needsReauth(_ serverId: String? = nil) -> Bool {
        guard let id = serverId ?? activeServerId else { return false }
        return needsReauthIds.contains(id)
    }

    var hasReauthNeeded: Bool { !needsReauthIds.isEmpty }

    func serverName(_ serverId: String) -> String {
        servers.first { $0.id == serverId }?.name ?? tr("common.unknown")
    }

    var totalSummary: ServerSummary {
        if serverSummaries.isEmpty {
            return ServerSummary(connectedAgents: allAgents.count)
        }
        var agents = 0; var cpu = 0.0; var mem = 0.0; var alerts = 0
        for s in serverSummaries.values {
            agents += s.connectedAgents; cpu += s.avgCpuUsage; mem += s.avgMemoryUsage; alerts += s.totalAlerts
        }
        let count = serverSummaries.count
        return ServerSummary(connectedAgents: agents,
                             avgCpuUsage: count > 0 ? cpu / Double(count) : 0,
                             avgMemoryUsage: count > 0 ? mem / Double(count) : 0,
                             totalAlerts: alerts)
    }

    // MARK: Lifecycle

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        isLoading = true

#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--app-store-screenshot") {
            loadAppStoreScreenshotFixture()
            isLoading = false
            return
        }
#endif

        notifyOffline = UserDefaults.standard.object(forKey: "notify_offline") as? Bool ?? false
        notifyHigh = UserDefaults.standard.object(forKey: "notify_high") as? Bool ?? false
        notifyDisk = UserDefaults.standard.object(forKey: "notify_disk") as? Bool ?? false

        servers = storage.getServers()
        let persistedServerId = PreferencesStore.activeServerId
        if let persistedServerId, servers.contains(where: { $0.id == persistedServerId }) {
            activeServerIdRaw = persistedServerId
        } else {
            activeServerIdRaw = servers.first?.id
            PreferencesStore.activeServerId = activeServerIdRaw
        }
        for server in servers { connectToServer(server) }
        configureAuditPolling()
        isLoading = false
    }

    func applicationDidBecomeActive() {
        notifications.refreshAuthorization()
        guard hasStarted else { return }
        for server in servers where services[server.id] == nil {
            connectToServer(server)
        }
    }

    // MARK: Add / remove servers

    private var deviceName: String { tr("device.defaultName") }
    private var deviceType: String { "mobile" }
    private var deviceOs: String { "iOS" }

    /// Add a server using a device token (QR / manual). Validates the token at
    /// add-time; the no-token path falls back to the public health check.
    @discardableResult
    func addServer(name: String, url: String, token: String? = nil,
                   forceTls: Bool = false, ignoreCert: Bool = false) async -> Bool {
        var server = ServerConnection(name: name, url: url, token: token,
                                      forceTls: forceTls, ignoreCert: ignoreCert)
        let service = ServerService(connection: server)
        let connected: Bool
        if let token = token, !token.isEmpty {
            let auth = await service.validateDeviceToken(token,
                                                         deviceName: name.isEmpty ? deviceName : name,
                                                         deviceType: deviceType, deviceOs: deviceOs)
            connected = auth.ok
        } else {
            connected = await service.testConnection()
        }
        service.dispose()

        guard connected else { return false }
        server.isConnected = true
        server.lastConnected = Date()
        servers.append(server)
        storage.saveServers(servers)
        if activeServerIdRaw == nil { setActiveServer(server.id) }
        connectToServer(server)
        return true
    }

    /// Add a server using username/password; keeps the password in memory only
    /// for silent re-login on token expiry.
    @discardableResult
    func addServerWithCredentials(name: String, url: String, username: String, password: String) async -> Bool {
        var server = ServerConnection(name: name, url: url, username: username)
        let service = ServerService(connection: server)
        let token = await service.login(username, password)
        service.dispose()

        guard let token = token else { return false }
        server.isConnected = true
        server.lastConnected = Date()
        server.userToken = token
        sessionPasswords[server.id] = password
        servers.append(server)
        storage.saveServers(servers)
        if activeServerIdRaw == nil { setActiveServer(server.id) }
        connectToServer(server)
        return true
    }

    /// Add a server by redeeming a 6-digit pairing code for a device token.
    @discardableResult
    func addServerWithPairingCode(name: String, url: String, pairingCode: String) async -> Bool {
        var server = ServerConnection(name: name, url: url)
        let service = ServerService(connection: server)
        let token = await service.redeemPairingCode(pairingCode)
        service.dispose()

        guard let token = token else { return false }
        server.isConnected = true
        server.lastConnected = Date()
        server.token = token
        servers.append(server)
        storage.saveServers(servers)
        if activeServerIdRaw == nil { setActiveServer(server.id) }
        connectToServer(server)
        return true
    }

    func removeServer(_ serverId: String) {
        services[serverId]?.dispose()
        services.removeValue(forKey: serverId)
        servers.removeAll { $0.id == serverId }
        allAgents.removeAll { $0.serverId == serverId }
        connectionModes.removeValue(forKey: serverId)
        serverSummaries.removeValue(forKey: serverId)
        serverAlertsMap.removeValue(forKey: serverId)
        recentActivityMap.removeValue(forKey: serverId)
        latestAuditIds.removeValue(forKey: serverId)
        needsReauthIds.remove(serverId)
        sessionPasswords.removeValue(forKey: serverId)
        reauthInFlight.remove(serverId)
        storage.deleteServer(serverId)
        let activeStillExists = activeServerIdRaw.map { id in
            servers.contains(where: { $0.id == id })
        } ?? false
        if activeServerIdRaw == serverId || !activeStillExists {
            activeServerIdRaw = servers.first?.id
            PreferencesStore.activeServerId = activeServerIdRaw
        }
    }

    // MARK: Connect + wire callbacks

    private func connectToServer(_ server: ServerConnection) {
        services[server.id]?.dispose()
        let service = ServerService(connection: server)
        services[server.id] = service
        let id = server.id

        service.onAgents = { [weak self] agents in
            Task { @MainActor in self?.updateAgents(serverId: id, agents: agents) }
        }
        service.onMetrics = { [weak self] metrics in
            Task { @MainActor in self?.updateMetrics(metrics) }
        }
        service.onConnection = { [weak self] status in
            Task { @MainActor in self?.updateConnectionStatus(serverId: id, status: status) }
        }
        service.onAgentOffline = { [weak self] agentId in
            Task { @MainActor in self?.handleAgentOffline(agentId) }
        }
        service.onSummary = { [weak self] summary in
            Task { @MainActor in self?.serverSummaries[id] = summary }
        }
        service.startUpdates()
    }

    private func updateAgents(serverId: String, agents: [Agent]) {
        var next = allAgents.filter { $0.serverId != serverId }
        next.append(contentsOf: agents)
        allAgents = next
        evaluateAlerts()
    }

    private func updateMetrics(_ metrics: [String: AgentMetrics]) {
        allMetrics.merge(metrics) { _, new in new }
        evaluateAlerts()
    }

    private func handleAgentOffline(_ agentId: String) {
        allAgents.removeAll { $0.id == agentId }
        allMetrics.removeValue(forKey: agentId)
    }

    private func updateConnectionStatus(serverId: String, status: ConnectionStatus) {
        guard let idx = servers.firstIndex(where: { $0.id == serverId }) else { return }
        servers[idx].isConnected = status.isConnected
        if status.isConnected { servers[idx].lastConnected = Date() }
        connectionModes[serverId] = status.mode

        if status.isConnected { needsReauthIds.remove(serverId) }

        if !status.isConnected, looksLikeAuthFailure(status.error) {
            Task { await handleAuthFailure(serverId) }
        }
    }

    // MARK: Alert notifications (client-derived)

    private func evaluateAlerts() {
        var current: [String: PendingAlert] = [:]
        for a in allAgents {
            let host = a.hostname
            if !a.isOnline {
                current["offline:\(a.id)"] = PendingAlert(category: "offline",
                                                          title: tr("alerts.nodeOffline", ["host": host]),
                                                          body: tr("alerts.nodeOfflineDetail"))
                continue
            }
            guard let m = allMetrics[a.id] else { continue }
            if m.cpuPercent > 90 {
                current["cpu:\(a.id)"] = PendingAlert(category: "high",
                                                      title: tr("alerts.cpuPressure", ["host": host]),
                                                      body: tr("alerts.usageDetail", ["value": String(format: "%.0f", m.cpuPercent)]))
            }
            if m.memoryPercent > 90 {
                current["mem:\(a.id)"] = PendingAlert(category: "high",
                                                      title: tr("alerts.memPressure", ["host": host]),
                                                      body: tr("alerts.usageDetail", ["value": String(format: "%.0f", m.memoryPercent)]))
            }
            for d in m.disks where d.usagePercent > 90 {
                current["disk:\(a.id):\(d.mountPoint)"] = PendingAlert(category: "disk",
                                                                       title: tr("alerts.diskFull", ["host": host]),
                                                                       body: tr("alerts.diskDetail", ["mount": d.mountPoint, "value": String(format: "%.0f", d.usagePercent)]))
            }
        }

        if !alertsSeeded {
            activeAlerts = Set(current.keys)
            alertsSeeded = true
            return
        }

        for (key, p) in current where !activeAlerts.contains(key) {
            let enabled: Bool
            switch p.category {
            case "offline": enabled = notifyOffline
            case "disk": enabled = notifyDisk
            default: enabled = notifyHigh
            }
            if enabled { notifications.show(key: key, title: p.title, body: p.body) }
        }
        activeAlerts = Set(current.keys)
    }

    func setNotifyPref(_ key: String, _ value: Bool) {
        guard value else {
            applyNotifyPref(key, false)
            return
        }
        notifications.requestAuthorization { [weak self] granted in
            Task { @MainActor in self?.applyNotifyPref(key, granted) }
        }
    }

    private func applyNotifyPref(_ key: String, _ value: Bool) {
        switch key {
        case "notify_offline": notifyOffline = value
        case "notify_high": notifyHigh = value
        case "notify_disk": notifyDisk = value
        default: break
        }
    }

    func setAuditNotifications(_ enabled: Bool) {
        guard enabled else {
            UserDefaults.standard.set(false, forKey: AppPreferenceKey.notifyAudit)
            configureAuditPolling()
            return
        }
        notifications.requestAuthorization { [weak self] granted in
            Task { @MainActor in
                UserDefaults.standard.set(granted, forKey: AppPreferenceKey.notifyAudit)
                self?.configureAuditPolling()
            }
        }
    }

#if DEBUG
    /// Deterministic, non-networked sample state used only to capture App Store
    /// artwork from the real native views. It is stripped from release builds.
    private func loadAppStoreScreenshotFixture() {
        let serverId = "sample-control-plane"
        var server = ServerConnection(
            id: serverId,
            name: "Production Fleet",
            url: "https://ops.example.net",
            userToken: "sample",
            username: "ops-admin",
            lastConnected: Date()
        )
        server.isConnected = true
        servers = [server]
        activeServerIdRaw = serverId
        connectionModes = [serverId: .websocket]

        let now = ISO8601DateFormatter().string(from: Date())
        let stale = ISO8601DateFormatter().string(from: Date(timeIntervalSinceNow: -7_200))
        let agentRows: [[String: Any]] = [
            ["id": "edge-gateway", "hostname": "edge-gateway", "os": "Linux", "arch": "arm64", "version": "0.5.0", "permissionLevel": 3, "lastHeartbeat": now],
            ["id": "api-cluster-01", "hostname": "api-cluster-01", "os": "Ubuntu 24.04", "arch": "x86_64", "version": "0.5.0", "permissionLevel": 2, "lastHeartbeat": now],
            ["id": "build-runner", "hostname": "build-runner", "os": "macOS 26", "arch": "arm64", "version": "0.5.0", "permissionLevel": 2, "lastHeartbeat": now],
            ["id": "backup-node", "hostname": "backup-node", "os": "Windows Server", "arch": "x86_64", "version": "0.5.0", "permissionLevel": 1, "lastHeartbeat": stale],
        ]
        allAgents = agentRows.map { Agent.from(JSON($0), serverId: serverId) }

        let metricRows: [[String: Any]] = [
            screenshotMetrics(agentId: "edge-gateway", cpu: 32, memory: 44, disk: 58, rx: 18_400_000, tx: 7_600_000),
            screenshotMetrics(agentId: "api-cluster-01", cpu: 68, memory: 63, disk: 72, rx: 42_100_000, tx: 28_900_000),
            screenshotMetrics(agentId: "build-runner", cpu: 84, memory: 76, disk: 87, rx: 9_800_000, tx: 16_200_000),
        ]
        allMetrics = Dictionary(uniqueKeysWithValues: metricRows.map {
            let metrics = AgentMetrics.from(JSON($0))
            return (metrics.agentId, metrics)
        })
        serverSummaries = [serverId: ServerSummary(connectedAgents: 3, avgCpuUsage: 61.3, avgMemoryUsage: 61, totalAlerts: 2)]

        serverAlertsMap = [serverId: [
            AlertInstance(id: "alert-disk", level: "warn",
                          title: tr("alerts.diskFull", ["host": "build-runner"]),
                          description: tr("alerts.diskDetail", ["mount": "/data", "value": "87"]),
                          agent: "build-runner", rule: "disk_usage", since: "8m", acked: false, ackedBy: "", value: 87),
            AlertInstance(id: "alert-offline", level: "crit",
                          title: tr("alerts.nodeOffline", ["host": "backup-node"]),
                          description: tr("alerts.nodeOfflineDetail"), agent: "backup-node",
                          rule: "heartbeat", since: "2h", acked: false, ackedBy: "", value: nil),
        ]]
        recentActivityMap = [serverId: [
            AuditEntry(id: "audit-1", type: "service.restart", user: "ops-admin", agentId: "api-cluster-01", agentHostname: "api-cluster-01", target: "nanolink-api", params: "{}", ok: true, error: "", durationMs: 420, at: Date(timeIntervalSinceNow: -180)),
            AuditEntry(id: "audit-2", type: "docker.logs", user: "maintainer", agentId: "edge-gateway", agentHostname: "edge-gateway", target: "gateway", params: "{}", ok: true, error: "", durationMs: 96, at: Date(timeIntervalSinceNow: -620)),
            AuditEntry(id: "audit-3", type: "file.read", user: "ops-admin", agentId: "build-runner", agentHostname: "build-runner", target: "/var/log/build.log", params: "{}", ok: true, error: "", durationMs: 72, at: Date(timeIntervalSinceNow: -1_260)),
        ]]

        let sectionValue = ProcessInfo.processInfo.arguments
            .first { $0.hasPrefix("--app-store-section=") }?
            .replacingOccurrences(of: "--app-store-section=", with: "")
        let router = ShellRouter.shared
        switch sectionValue {
        case "nodes":
            router.show(.nodes)
            router.selectedAgentID = "api-cluster-01"
        case "activity": router.show(.activity)
        case "terminal": router.show(.terminal)
        case "settings": router.show(.settings)
        default: router.show(.overview)
        }
    }

    private func screenshotMetrics(agentId: String, cpu: Double, memory: Double,
                                   disk: Double, rx: Double, tx: Double) -> [String: Any] {
        let memoryTotal = 34_359_738_368
        let diskTotal = 1_099_511_627_776
        return [
            "agentId": agentId,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "cpu": ["usagePercent": cpu, "coreCount": 12, "model": "Apple / AMD Compute", "temperature": 52, "loadAverage": [1.2, 1.7, 1.9]],
            "memory": ["total": memoryTotal, "used": Int(Double(memoryTotal) * memory / 100), "available": Int(Double(memoryTotal) * (100 - memory) / 100), "swapTotal": 4_294_967_296, "swapUsed": 536_870_912, "cached": 2_147_483_648, "buffers": 268_435_456],
            "disks": [["mountPoint": "/data", "device": "nvme0n1", "fsType": "apfs", "total": diskTotal, "used": Int(Double(diskTotal) * disk / 100), "available": Int(Double(diskTotal) * (100 - disk) / 100), "readBytesPerSec": 28_000_000, "writeBytesPerSec": 12_000_000, "diskType": "NVMe", "temperature": 43]],
            "networks": [["interface": "en0", "rxBytesPerSec": rx, "txBytesPerSec": tx, "isUp": true, "ipAddresses": ["10.0.0.24"], "speedMbps": 1000]],
            "systemInfo": ["osName": "Linux", "osVersion": "24.04", "kernelVersion": "6.8", "hostname": agentId, "uptimeSeconds": 428_400, "primaryIp": "10.0.0.24"],
        ]
    }
#endif

    private func configureAuditPolling() {
        auditPollingTask?.cancel()
        auditPollingTask = nil
        guard UserDefaults.standard.bool(forKey: AppPreferenceKey.notifyAudit) else { return }

        auditPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let serverIds = self.servers.map(\.id)
                for serverId in serverIds {
                    guard !Task.isCancelled else { return }
                    _ = await self.fetchRecentActivity(serverId: serverId, limit: 50)
                }
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    // MARK: Server-sourced alerts / audit

    @discardableResult
    func fetchServerAlerts(serverId: String? = nil, status: String? = nil) async -> [AlertInstance] {
        guard let id = serverId ?? activeServerId else { return [] }
        guard let service = services[id] else { return serverAlertsMap[id] ?? [] }
        let alerts = await service.fetchAlerts(status: status)
        serverAlertsMap[id] = alerts
        return alerts
    }

    @discardableResult
    func fetchRecentActivity(serverId: String? = nil, limit: Int = 50) async -> [AuditEntry] {
        guard let id = serverId ?? activeServerId else { return [] }
        guard let service = services[id] else { return recentActivityMap[id] ?? [] }
        let entries = await service.fetchRecentAudit(limit: limit)
        let previousIds = latestAuditIds[id]
        latestAuditIds[id] = Set(entries.map(\.id))
        recentActivityMap[id] = entries
        if UserDefaults.standard.bool(forKey: AppPreferenceKey.notifyAudit), let previousIds {
            for entry in entries where !previousIds.contains(entry.id) {
                let host = entry.agentHostname.isEmpty ? entry.agentId : entry.agentHostname
                let title = tr("alerts.auditActivity", ["host": host.isEmpty ? serverName(id) : host])
                let body = entry.error.isEmpty ? entry.type : "\(entry.type): \(entry.error)"
                notifications.show(key: "audit:\(id):\(entry.id)", title: title, body: body)
            }
        }
        return entries
    }

    func acknowledgeAlert(_ alertId: String, serverId: String? = nil) async -> String? {
        guard let id = serverId ?? activeServerId else { return tr("errors.noActiveServer") }
        guard let service = services[id] else { return tr("errors.serverNotConnected") }
        let err = await service.ackAlert(alertId)
        if err == nil { await fetchServerAlerts(serverId: id) }
        return err
    }

    @discardableResult
    func acknowledgeAllAlerts(serverId: String? = nil) async -> Int? {
        guard let id = serverId ?? activeServerId else { return nil }
        guard let service = services[id] else { return nil }
        let count = await service.ackAllAlerts()
        if count != nil { await fetchServerAlerts(serverId: id) }
        return count
    }

    // MARK: Re-authentication

    private func looksLikeAuthFailure(_ error: String?) -> Bool {
        guard let error = error, !error.isEmpty else { return false }
        let e = error.lowercased()
        return e.contains("401") || e.contains("403") || e.contains("unauthorized")
            || e.contains("forbidden") || e.contains("invalid token")
            || e.contains("token expired") || e.contains("expired token")
    }

    private func handleAuthFailure(_ serverId: String) async {
        guard !reauthInFlight.contains(serverId) else { return }
        reauthInFlight.insert(serverId)
        defer { reauthInFlight.remove(serverId) }
        let reconnected = await attemptReauth(serverId)
        if !reconnected { needsReauthIds.insert(serverId) }
    }

    private func attemptReauth(_ serverId: String) async -> Bool {
        guard let idx = servers.firstIndex(where: { $0.id == serverId }) else { return false }
        let server = servers[idx]
        guard let username = server.username, !username.isEmpty,
              let password = sessionPasswords[serverId],
              let service = services[serverId] else { return false }

        let result = await service.loginDetailed(username, password)
        guard result.ok, let token = result.token else {
            if result.error == .invalidCredentials { sessionPasswords.removeValue(forKey: serverId) }
            return false
        }

        var refreshed = server
        refreshed.userToken = token
        servers[idx] = refreshed
        storage.saveServers(servers)

        services[serverId]?.dispose()
        services.removeValue(forKey: serverId)
        needsReauthIds.remove(serverId)
        connectToServer(refreshed)
        return true
    }

    /// UI-driven re-auth with freshly-entered credentials.
    @discardableResult
    func reauthenticate(serverId: String, username: String, password: String) async -> Bool {
        guard let idx = servers.firstIndex(where: { $0.id == serverId }) else { return false }
        let service = services[serverId] ?? ServerService(connection: servers[idx])
        let result = await service.loginDetailed(username, password)
        guard result.ok, let token = result.token else { return false }

        sessionPasswords[serverId] = password
        var refreshed = servers[idx]
        refreshed.username = username
        refreshed.userToken = token
        servers[idx] = refreshed
        storage.saveServers(servers)

        services[serverId]?.dispose()
        services.removeValue(forKey: serverId)
        needsReauthIds.remove(serverId)
        connectToServer(refreshed)
        return true
    }
}
