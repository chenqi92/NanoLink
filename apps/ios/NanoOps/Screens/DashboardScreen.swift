import SwiftUI

/// Aggregate overview for the active server: rolling KPIs, offline nodes, top CPU
/// nodes and the most recent audit activity.
struct DashboardScreen: View {
    /// Set by the regular-width shell so node rows select in the Nodes workspace
    /// instead of pushing a detail screen onto this stack.
    var onSelectAgent: ((Agent) -> Void)? = nil

    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var router: ShellRouter
    @Environment(\.nano) private var t
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var cpuSpark: [Double] = []
    @State private var memSpark: [Double] = []
    @State private var sparkServerId: String?
    @State private var showAddServer = false
    @State private var showServerSwitch = false

    private var agents: [Agent] { store.agentsForServer() }
    private var online: [Agent] { agents.filter(\.isOnline) }
    private var offline: [Agent] { agents.filter { !$0.isOnline } }

    private func average(_ select: (AgentMetrics) -> Double) -> Double {
        let values = online.compactMap { store.metricsFor($0.id) }.map(select)
        return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private var avgCpu: Double { average(\.cpuPercent) }
    private var avgMemory: Double { average(\.memoryPercent) }
    private var memoryUsedGiB: Double {
        Fmt.gib(Double(online.compactMap { store.metricsFor($0.id)?.memory.used }.reduce(0, +)))
    }
    private var diskAlerts: Int {
        agents.filter { agent in
            store.metricsFor(agent.id)?.disks.contains { $0.usagePercent > 85 } == true
        }.count
    }
    private var topCpu: [Agent] {
        online.sorted { (store.metricsFor($0.id)?.cpuPercent ?? 0) > (store.metricsFor($1.id)?.cpuPercent ?? 0) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // The Mac window titles the section itself and carries the global
                // actions in its toolbar, so the inline header is phone/iPad only.
                if !t.desktop { header }
                serverChips.padding(.top, t.desktop ? 4 : 12)
                kpiGrid.padding(.top, 12)
                if !offline.isEmpty { offlineBanner.padding(.top, 12) }

                NanoSectionLabel(tr("dashboard.topCpu"))
                if topCpu.isEmpty {
                    emptyHint(icon: "server.rack", text: store.servers.isEmpty ? tr("dashboard.noServersYet") : tr("dashboard.noOnlineNodes"))
                } else {
                    NanoCard {
                        ForEach(Array(topCpu.prefix(4).enumerated()), id: \.element.id) { index, agent in
                            let divider = index < min(topCpu.count, 4) - 1
                            if let onSelectAgent = onSelectAgent {
                                Button { onSelectAgent(agent) } label: {
                                    topCpuRow(agent, divider: divider)
                                }.buttonStyle(.plain)
                            } else {
                                NavigationLink(value: AgentRoute(agent: agent)) {
                                    topCpuRow(agent, divider: divider)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }

                NanoSectionLabel(tr("dashboard.recentActivity"))
                if store.recentActivity().isEmpty {
                    NanoCard(padding: EdgeInsets(top: 22, leading: 12, bottom: 22, trailing: 12)) {
                        Text(tr("dashboard.noActivity"))
                            .font(.system(size: 13)).foregroundColor(t.fg4)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    NanoCard {
                        ForEach(Array(store.recentActivity().prefix(5).enumerated()), id: \.element.id) { index, entry in
                            auditRow(entry, divider: index < min(store.recentActivity().count, 5) - 1)
                        }
                    }
                }
            }
            .padding(EdgeInsets(top: 8, leading: 16,
                                bottom: t.desktop ? 24 : (horizontalSizeClass == .regular ? 48 : 110),
                                trailing: 16))
        }
        .nanoPullToRefresh(enabled: !t.desktop) { await refresh() }
        .background(t.bg)
        .navigationDestination(for: AgentRoute.self) { AgentDetailScreen(agent: $0.agent) }
        .navigationDestination(isPresented: $showAddServer) { AddServerScreen() }
        .sheet(isPresented: $showServerSwitch) { ServerSwitchSheet() }
        .toolbar {
            if t.desktop {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddServer = true } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(NanoToolbarButtonStyle())
                    .accessibilityLabel(tr("dashboard.newNode"))
                    .help(tr("dashboard.newNode"))
                }
            }
        }
        .nanoFloatingAction(enabled: !t.desktop) {
            Button { showAddServer = true } label: {
                Label(tr("dashboard.newNode"), systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18).frame(height: 48)
                    .background(LinearGradient(colors: [t.accent, t.tertiary], startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: t.accent.opacity(0.3), radius: 8, y: 5)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16).padding(.bottom, 4)
        }
        .task { await refresh() }
        .onReceive(store.$allMetrics) { _ in pushSparks() }
        .onChange(of: store.activeServerIdRaw) { _ in pushSparks() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(tr("dashboard.title"))
                .font(.system(size: t.isIOS ? 32 : 28, weight: t.displayWeight))
                .tracking(t.displayTracking).foregroundColor(t.fg)
            Spacer()
            NavigationLink { AssistantScreen() } label: {
                circleButton("sparkles", gradient: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("nav.assistant"))
            .help(tr("nav.assistant"))
            NavigationLink { AgentsScreen() } label: { circleButton("magnifyingglass") }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("agents.searchHint"))
                .help(tr("agents.searchHint"))
            Button { showServerSwitch = true } label: { circleButton("server.rack") }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("agents.switchServer"))
                .help(tr("agents.switchServer"))
        }
        .padding(.top, t.isIOS ? 32 : 4)
    }

    private func circleButton(_ icon: String, gradient: Bool = false) -> some View {
        ZStack {
            if gradient { LinearGradient(colors: [t.accent, t.tertiary], startPoint: .topLeading, endPoint: .bottomTrailing) }
            else { t.card }
            Image(systemName: icon).font(.system(size: 16)).foregroundColor(gradient ? .white : t.accent)
        }
        .frame(width: 34, height: 34).clipShape(Circle())
    }

    private var serverChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.servers) { server in
                    Button { store.setActiveServer(server.id) } label: {
                        HStack(spacing: 6) {
                            NanoStatusDot(color: server.isConnected ? t.ok : t.crit, pulse: server.isConnected)
                            Text(server.name).font(.system(size: 13.5, weight: .medium)).foregroundColor(t.fg)
                            Text("\(store.agentsForServer(server.id).count)").font(NanoFont.mono(10.5)).foregroundColor(t.fg4)
                        }
                        .padding(.horizontal, 12).frame(height: 34)
                        .background(server.id == store.activeServerId ? t.card : Color.clear)
                        .overlay(Capsule().stroke(t.sep2, lineWidth: 1))
                        .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
                Button { showAddServer = true } label: {
                    Label(tr("dashboard.add"), systemImage: "plus")
                        .font(.system(size: 13)).foregroundColor(t.fg3)
                        .padding(.horizontal, 12).frame(height: 34)
                        .overlay(Capsule().stroke(t.sep, lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
    }

    private var kpiGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                 count: horizontalSizeClass == .regular ? 4 : 2), spacing: 10) {
            NanoKpiTile(label: tr("dashboard.onlineNodes"), sub: tr("dashboard.nodesOffline", ["n": offline.count]), icon: "server.rack") {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(online.count)")
                    Text("/\(agents.count)").font(.system(size: 18)).foregroundColor(t.fg4)
                }
            }
            NanoKpiTile(label: tr("dashboard.avgCpu"), sub: tr("dashboard.avgCpuLast60s"), icon: "cpu",
                        tone: avgCpu > 80 ? "warn" : nil, spark: cpuSpark.count >= 2 ? cpuSpark : nil) {
                Text(String(format: "%.1f%%", avgCpu))
            }
            NanoKpiTile(label: tr("dashboard.avgMemory"), sub: tr("dashboard.avgMemUsed", ["gib": String(format: "%.0f", memoryUsedGiB)]), icon: "memorychip",
                        tone: avgMemory > 80 ? "warn" : nil, spark: memSpark.count >= 2 ? memSpark : nil) {
                Text(String(format: "%.1f%%", avgMemory))
            }
            NanoKpiTile(label: tr("dashboard.diskAlerts"), sub: tr("dashboard.diskAlertsSub"), icon: "exclamationmark.triangle",
                        tone: diskAlerts > 0 ? "warn" : nil) { Text("\(diskAlerts)") }
        }
    }

    private var offlineBanner: some View {
        Button { router.showNodes(filter: "offline") } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle").foregroundColor(t.crit)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("dashboard.offlineBanner", ["n": offline.count])).font(.system(size: 13.5, weight: .medium)).foregroundColor(t.fg)
                    Text(offline.map(\.hostname).joined(separator: " · ")).font(.system(size: 11.5)).foregroundColor(t.fg3).lineLimit(1)
                }
                Spacer()
                Text(tr("dashboard.view")).font(.system(size: 13, weight: .semibold)).foregroundColor(t.crit)
            }
            .padding(12).background(t.crit.opacity(0.1))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(t.crit.opacity(0.25), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("dashboard.offlineBanner", ["n": offline.count]))
    }

    private func topCpuRow(_ agent: Agent, divider: Bool) -> some View {
        let cpu = store.metricsFor(agent.id)?.cpuPercent ?? 0
        return NanoListRow(divider: divider) {
            VStack(alignment: .leading, spacing: 2) {
                NanoMono(agent.hostname, size: 14, color: t.fg, weight: .medium)
                Text("\(agent.os) · \(agent.arch)").font(.system(size: 11.5)).foregroundColor(t.fg4)
            }
        } leading: {
            Image(systemName: osIcon(agent.os)).font(.system(size: 17)).foregroundColor(t.fg3).frame(width: 20)
        } trailing: {
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(String(format: "%.0f%%", cpu)).font(.system(size: 15, weight: .semibold)).foregroundColor(t.usageColor(cpu)).monospacedDigit()
                    NanoMeter(value: cpu / 100).frame(width: 50)
                }
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(t.fg4)
            }
        }
    }

    private func auditRow(_ entry: AuditEntry, divider: Bool) -> some View {
        let tone = entry.ok ? t.ok : t.crit
        let summary = entry.paramsMap.isEmpty
            ? (!entry.target.isEmpty ? entry.target : (!entry.agentHostname.isEmpty ? entry.agentHostname : entry.error))
            : entry.paramsMap.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " · ")
        return NanoListRow(divider: divider) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    NanoMono(entry.type.isEmpty ? "event" : entry.type, size: 13, color: t.fg, weight: .medium)
                    Text(Fmt.ago(entry.at)).font(.system(size: 11)).foregroundColor(t.fg4)
                }
                if !summary.isEmpty { NanoMono(summary, size: 11.5, color: t.fg3).lineLimit(1) }
            }
        } leading: {
            ZStack { Circle().fill(tone.opacity(0.16)); Image(systemName: auditIcon(entry.type)).font(.system(size: 14)).foregroundColor(tone) }
                .frame(width: 34, height: 34)
        } trailing: {
            if !entry.user.isEmpty { Text(entry.user).font(.system(size: 11)).foregroundColor(t.fg4) }
        }
    }

    private func emptyHint(icon: String, text: String) -> some View {
        NanoCard(padding: EdgeInsets(top: 28, leading: 12, bottom: 28, trailing: 12)) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 26)).foregroundColor(t.fg4)
                Text(text).font(.system(size: 13)).foregroundColor(t.fg4)
            }.frame(maxWidth: .infinity)
        }
    }

    private func refresh() async {
        guard let id = store.activeServerId else { return }
        await store.fetchRecentActivity(serverId: id, limit: 50)
        pushSparks()
    }

    private func pushSparks() {
        let server = store.activeServerId
        if server != sparkServerId { sparkServerId = server; cpuSpark.removeAll(); memSpark.removeAll() }
        func push(_ buffer: inout [Double], _ value: Double) {
            if let last = buffer.last, abs(last - value) < 0.05 { return }
            buffer.append(value); if buffer.count > 20 { buffer.removeFirst() }
        }
        push(&cpuSpark, avgCpu); push(&memSpark, avgMemory)
    }
}

/// Hashable navigation wrapper while the model itself intentionally stays plain.
struct AgentRoute: Hashable {
    let agent: Agent
    static func == (lhs: AgentRoute, rhs: AgentRoute) -> Bool { lhs.agent.id == rhs.agent.id }
    func hash(into hasher: inout Hasher) { hasher.combine(agent.id) }
}

func osIcon(_ os: String) -> String {
    let s = os.lowercased()
    if s.contains("mac") || s.contains("darwin") || s.contains("ios") { return "apple.logo" }
    if s.contains("win") { return "window.ceiling" }
    return "terminal"
}

private func auditIcon(_ type: String) -> String {
    let s = type.lowercased()
    if s.contains("shell") || s.contains("exec") { return "terminal" }
    if s.contains("restart") || s.contains("reload") { return "arrow.clockwise" }
    if s.contains("reboot") || s.contains("power") || s.contains("shutdown") { return "power" }
    if s.contains("stop") || s.contains("kill") { return "stop.fill" }
    if s.contains("start") { return "play.fill" }
    return "clock.arrow.circlepath"
}
