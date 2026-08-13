import SwiftUI

/// Searchable and filterable node inventory with live CPU, memory and disk
/// summaries. Can also be pushed with an initial offline/warning filter.
struct AgentsScreen: View {
    var initialFilter: String? = nil
    var initialQuery: String? = nil

    @EnvironmentObject private var store: AppStore
    @Environment(\.nano) private var t
    @State private var query: String
    @State private var filter: String
    @State private var showServerSwitch = false
    @State private var actionAgent: Agent?

    init(initialFilter: String? = nil, initialQuery: String? = nil) {
        self.initialFilter = initialFilter
        self.initialQuery = initialQuery
        _query = State(initialValue: initialQuery ?? "")
        _filter = State(initialValue: initialFilter ?? "all")
    }

    private var allAgents: [Agent] { store.agentsForServer() }
    private func warning(_ agent: Agent) -> Bool {
        guard let m = store.metricsFor(agent.id) else { return false }
        return m.cpuPercent > 80 || m.memoryPercent > 80 || m.disks.contains { $0.usagePercent > 85 }
    }
    private var filtered: [Agent] {
        allAgents.filter { agent in
            if filter == "online" && !agent.isOnline { return false }
            if filter == "offline" && agent.isOnline { return false }
            if filter == "warn" && !warning(agent) { return false }
            if !query.isEmpty {
                let q = query.lowercased()
                return agent.hostname.lowercased().contains(q) || agent.os.lowercased().contains(q) || agent.id.lowercased().contains(q)
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField.padding(.top, 8)
            filterChips.padding(.vertical, 10)
            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "server.rack").font(.system(size: 30)).foregroundColor(t.fg4)
                    Text(allAgents.isEmpty ? tr("agents.noNodes") : tr("agents.noMatch"))
                        .font(.system(size: 13.5)).foregroundColor(t.fg4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { agent in
                            ZStack(alignment: .topTrailing) {
                                NavigationLink(value: AgentRoute(agent: agent)) {
                                    agentCard(agent)
                                }
                                .buttonStyle(.plain)
                                Button { actionAgent = agent } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 18))
                                        .foregroundColor(t.fg4)
                                        .frame(width: 36, height: 36)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 8)
                                .padding(.trailing, 6)
                            }
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
        .background(t.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationDestination(for: AgentRoute.self) { AgentDetailScreen(agent: $0.agent) }
        .sheet(isPresented: $showServerSwitch) { ServerSwitchSheet() }
        .sheet(item: $actionAgent) { AgentActionsSheet(agent: $0) }
        .safeAreaInset(edge: .bottom, alignment: .trailing) {
            Button { showServerSwitch = true } label: {
                Label(tr("agents.switchServer"), systemImage: "server.rack")
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(t.onAccent)
                    .padding(.horizontal, 17).frame(height: 46).background(t.accent).clipShape(Capsule())
            }
            .buttonStyle(.plain).padding(.trailing, 2).padding(.bottom, 4)
        }
    }

    private var header: some View {
        HStack {
            Text(tr("agents.title"))
                .font(.system(size: t.isIOS ? 32 : 28, weight: t.displayWeight))
                .tracking(t.displayTracking).foregroundColor(t.fg)
            Spacer()
            Image(systemName: filter == "all" ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 19)).foregroundColor(filter == "all" ? t.fg2 : t.accent)
        }
        .padding(.top, t.isIOS ? 40 : 8)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundColor(t.fg4)
            TextField(tr("agents.searchHint"), text: $query)
                .font(.system(size: 15)).foregroundColor(t.fg)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(t.fg4) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).frame(height: 38).background(t.card2)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var filters: [(String, String, Int)] {
        [("all", tr("agents.filterAll"), allAgents.count),
         ("online", tr("agents.filterOnline"), allAgents.filter(\.isOnline).count),
         ("warn", tr("agents.filterWarn"), allAgents.filter(warning).count),
         ("offline", tr("agents.filterOffline"), allAgents.filter { !$0.isOnline }.count)]
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(filters, id: \.0) { item in
                    let selected = filter == item.0
                    Button { filter = item.0 } label: {
                        HStack(spacing: 5) {
                            Text(item.1).font(.system(size: 13, weight: .medium))
                            Text("\(item.2)").font(NanoFont.mono(11)).opacity(0.65)
                        }
                        .foregroundColor(selected ? t.bg : t.fg2)
                        .padding(.horizontal, 11).frame(height: 30)
                        .background(selected ? t.fg : t.card)
                        .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func agentCard(_ agent: Agent) -> some View {
        NanoCard(padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 8)) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 10) {
                    NanoIconBox(icon: osIcon(agent.os))
                    VStack(alignment: .leading, spacing: 2) {
                        NanoMono(agent.hostname, size: 14, color: t.fg, weight: .semibold).lineLimit(1)
                        Text("\(agent.os) · \(agent.arch)").font(.system(size: 11.5)).foregroundColor(t.fg4).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 5) {
                        NanoStatusLabel(status: agent.isOnline ? "online" : "offline")
                        NanoPermPill(level: agent.permissionLevel)
                    }
                    Spacer().frame(width: 36)
                }
                summary(agent).padding(.leading, 46).padding(.trailing, 6)
            }
        }
    }

    @ViewBuilder
    private func summary(_ agent: Agent) -> some View {
        if !agent.isOnline || store.metricsFor(agent.id) == nil {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 13)).foregroundColor(t.fg4)
                Text(tr("agents.offlineNoData")).font(.system(size: 12)).foregroundColor(t.fg4)
            }.padding(.top, 4)
        } else if let m = store.metricsFor(agent.id) {
            VStack(spacing: 6) {
                NanoMetricRow(icon: "cpu", label: "CPU", value: String(format: "%.0f%%", m.cpuPercent),
                              sub: m.cpu.temperature.map { "\(m.cpu.coreCount)c · \(Int($0))°C" } ?? "\(m.cpu.coreCount)c",
                              pct: m.cpuPercent, tone: tone(m.cpuPercent))
                NanoMetricRow(icon: "memorychip", label: "MEM", value: String(format: "%.0f%%", m.memoryPercent),
                              sub: "\(Int(Fmt.gib(Double(m.memory.used))))/\(Int(Fmt.gib(Double(m.memory.total))))G",
                              pct: m.memoryPercent, tone: tone(m.memoryPercent))
                if let disk = m.disks.max(by: { $0.usagePercent < $1.usagePercent }) {
                    NanoMetricRow(icon: "internaldrive", label: "DSK", value: String(format: "%.0f%%", disk.usagePercent),
                                  sub: disk.mountPoint, pct: disk.usagePercent, tone: tone(disk.usagePercent))
                }
            }.padding(.top, 4)
        }
    }

    private func tone(_ value: Double) -> String? { value > 90 ? "crit" : (value > 75 ? "warn" : nil) }
}
