import SwiftUI

/// Read-only permission-tier overview for nodes on the active server.
struct PermissionsScreen: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.nano) private var t
    private let levels = [3, 2, 1, 0]

    private var agents: [Agent] { store.agentsForServer() }

    var body: some View {
        Group {
            if agents.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "shield").font(.system(size: 34)).foregroundColor(t.fg4)
                    Text(tr("permissions.empty")).font(.system(size: 15, weight: .medium)).foregroundColor(t.fg2)
                    Text(tr("permissions.emptySub")).font(.system(size: 12.5)).foregroundColor(t.fg4)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text(tr("permissions.intro")).font(.system(size: 13)).foregroundColor(t.fg3).lineSpacing(4).padding(.horizontal, 4).padding(.bottom, 8)
                        ForEach(levels, id: \.self) { level in
                            levelGroup(level)
                        }
                    }
                    .padding(EdgeInsets(top: 4, leading: 16, bottom: 50, trailing: 16))
                }
            }
        }
        .background(t.bg.ignoresSafeArea())
        .navigationTitle(tr("permissions.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func levelGroup(_ level: Int) -> some View {
        let group = agents.filter { min(max($0.permissionLevel, 0), 3) == level }.sorted { $0.hostname < $1.hostname }
        return VStack(alignment: .leading, spacing: 0) {
            NanoSectionLabel(tr("permissions.levelGroup", ["n": group.count])) { NanoPermPill(level: level) }
            NanoCard {
                if group.isEmpty {
                    Text(tr("permissions.noneAtLevel")).font(.system(size: 13)).foregroundColor(t.fg4).padding(14)
                } else {
                    ForEach(Array(group.enumerated()), id: \.element.id) { index, agent in
                        NanoListRow(divider: index < group.count - 1) {
                            VStack(alignment: .leading, spacing: 2) {
                                NanoMono(agent.hostname, size: 14, color: t.fg, weight: .medium)
                                Text("\(agent.os) · \(agent.arch)").font(.system(size: 12)).foregroundColor(t.fg3)
                            }
                        } leading: { NanoStatusDot(color: agent.isOnline ? t.ok : t.crit, size: 8, pulse: agent.isOnline) }
                        trailing: { Text(agent.isOnline ? tr("status.online") : tr("status.offline")).font(.system(size: 12)).foregroundColor(agent.isOnline ? t.fg3 : t.fg4) }
                    }
                }
            }
        }
    }
}
