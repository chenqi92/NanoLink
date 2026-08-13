import SwiftUI

/// Full audit feed for the active server.
struct AuditLogScreen: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.nano) private var t
    @State private var loading = true

    var body: some View {
        Group {
            if loading && store.recentActivity().isEmpty {
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.recentActivity().isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        NanoSectionLabel(tr("audit.entriesCount", ["n": store.recentActivity().count]))
                        NanoCard {
                            ForEach(Array(store.recentActivity().enumerated()), id: \.element.id) { index, entry in
                                row(entry, divider: index < store.recentActivity().count - 1)
                            }
                        }
                    }
                    .padding(EdgeInsets(top: 4, leading: 16, bottom: 50, trailing: 16))
                }
                .refreshable { await load() }
            }
        }
        .background(t.bg.ignoresSafeArea())
        .navigationTitle(tr("audit.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 34)).foregroundColor(t.fg4)
            Text(tr("audit.empty")).font(.system(size: 15, weight: .medium)).foregroundColor(t.fg2)
            Text(tr("audit.emptySub")).font(.system(size: 12.5)).foregroundColor(t.fg4)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ entry: AuditEntry, divider: Bool) -> some View {
        let tone = entry.ok ? t.ok : t.crit
        let detail = entry.paramsMap.isEmpty
            ? (!entry.target.isEmpty ? entry.target : entry.agentHostname)
            : entry.paramsMap.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
        return NanoListRow(divider: divider, verticalAlignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    NanoMono(entry.type, size: 13, color: t.fg, weight: .medium)
                    Text(Fmt.ago(entry.at)).font(.system(size: 11)).foregroundColor(t.fg4)
                }
                if !detail.isEmpty { NanoMono(detail, size: 11.5, color: t.fg3).lineLimit(1) }
                if !entry.error.isEmpty { Text(entry.error).font(.system(size: 11.5)).foregroundColor(t.crit).lineLimit(2) }
                HStack(spacing: 6) {
                    if !entry.user.isEmpty { NanoBadge(text: entry.user, icon: "person") }
                    if !entry.agentHostname.isEmpty { NanoBadge(text: entry.agentHostname, mono: true) }
                    Spacer()
                    if entry.durationMs > 0 { NanoMono("\(entry.durationMs)ms", size: 10.5, color: t.fg4) }
                }.padding(.top, 1)
            }
        } leading: {
            ZStack { Circle().fill(tone.opacity(0.16)); Image(systemName: auditLogIcon(entry.type)).font(.system(size: 15)).foregroundColor(tone) }
                .frame(width: 36, height: 36)
        }
    }

    private func load() async {
        guard let id = store.activeServerId else { loading = false; return }
        await store.fetchRecentActivity(serverId: id, limit: 200)
        loading = false
    }
}

private func auditLogIcon(_ type: String) -> String {
    switch type.lowercased() {
    case "shell.exec", "shell_execute": return "terminal"
    case "service.restart", "docker.restart": return "arrow.clockwise"
    case "system.reboot": return "power"
    default: return "clock.arrow.circlepath"
    }
}
