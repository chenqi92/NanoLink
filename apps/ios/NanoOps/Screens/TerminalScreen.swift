import SwiftUI

/// Terminal navigation tab: pick an online L3 node or reopen one of the recent
/// shell sessions derived from the audit log.
struct TerminalScreen: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.nano) private var t

    private var agents: [Agent] {
        store.agentsForServer().filter { $0.isOnline && $0.permissionLevel >= 3 }.sorted { $0.hostname < $1.hostname }
    }
    private var sessions: [AuditEntry] {
        let types: Set<String> = ["SHELL_EXECUTE", "shell", "shell.exec"]
        return store.recentActivity().filter { types.contains($0.type) }.sorted { $0.at > $1.at }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !t.desktop {
                    Text(tr("terminal.navTitle"))
                        .font(.system(size: t.titleSize, weight: t.displayWeight))
                        .tracking(t.displayTracking).foregroundColor(t.fg)
                        .padding(.top, t.titleTopPadding)
                }
                Text(tr("terminal.navDesc"))
                    .font(.system(size: 13.5)).foregroundColor(t.fg3).lineSpacing(5)
                    .padding(EdgeInsets(top: 6, leading: 4, bottom: 14, trailing: 4))

                if agents.isEmpty {
                    emptyInline
                } else {
                    NanoCard {
                        ForEach(Array(agents.enumerated()), id: \.element.id) { index, agent in
                            NavigationLink { AgentDetailScreen(agent: agent, initialTab: 2) } label: {
                                NanoListRow(divider: index < agents.count - 1) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        NanoMono(agent.hostname, size: 14, color: t.fg, weight: .semibold)
                                        Text("\(agent.os) · \(agent.arch)").font(.system(size: 11.5)).foregroundColor(t.fg4)
                                    }
                                } leading: { NanoIconBox(icon: osIcon(agent.os)) }
                                trailing: {
                                    HStack(spacing: 6) { NanoPermPill(level: agent.permissionLevel); Image(systemName: "chevron.right").foregroundColor(t.fg4) }
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }

                if !sessions.isEmpty {
                    NanoSectionLabel(tr("terminal.recentSessions"), grouped: t.isIOS)
                    NanoCard {
                        ForEach(Array(sessions.prefix(5).enumerated()), id: \.element.id) { index, entry in
                            sessionRow(entry, divider: index < min(sessions.count, 5) - 1)
                        }
                    }
                }
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: t.contentBottomInset, trailing: 16))
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .nanoPullToRefresh(enabled: !t.desktop) { await load() }
        .background(t.bg)
        .nanoNavigationBarHidden(!t.desktop)
        .task { await load() }
    }

    private var emptyInline: some View {
        NanoCard(padding: EdgeInsets(top: 18, leading: 16, bottom: 18, trailing: 16)) {
            HStack(spacing: 12) {
                Image(systemName: "terminal").font(.system(size: 21)).foregroundColor(t.fg4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("terminal.noAvailableNodes")).font(.system(size: 14, weight: .medium)).foregroundColor(t.fg2)
                    Text(tr("terminal.noAvailableNodesSub")).font(.system(size: 12)).foregroundColor(t.fg4)
                }
            }
        }
    }

    @ViewBuilder
    private func sessionRow(_ entry: AuditEntry, divider: Bool) -> some View {
        let matched = matchAgent(entry)
        let command = !entry.target.isEmpty ? entry.target : (entry.paramsMap["command"] ?? entry.paramsMap["cmd"] ?? entry.type)
        let host = !entry.agentHostname.isEmpty ? entry.agentHostname : entry.agentId
        let content = NanoListRow(divider: divider) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    NanoMono(host, size: 13.5, color: t.fg, weight: .medium)
                    if !entry.ok { NanoBadge(text: tr("terminal.sessionFailed"), color: t.crit) }
                }
                NanoMono(command, size: 11.5, color: t.fg3).lineLimit(1)
            }
        } leading: {
            NanoIconBox(icon: "terminal", size: 32, iconSize: 15, fg: entry.ok ? t.accent : t.crit)
        } trailing: {
            Text(Fmt.ago(entry.at)).font(.system(size: 11)).foregroundColor(t.fg4)
        }
        if let matched {
            NavigationLink { AgentDetailScreen(agent: matched, initialTab: 2) } label: { content }.buttonStyle(.plain)
        } else { content }
    }

    private func matchAgent(_ entry: AuditEntry) -> Agent? {
        agents.first { (!entry.agentId.isEmpty && $0.id == entry.agentId) || (!entry.agentHostname.isEmpty && $0.hostname == entry.agentHostname) }
    }

    private func load() async {
        guard let id = store.activeServerId else { return }
        await store.fetchRecentActivity(serverId: id, limit: 50)
    }
}
