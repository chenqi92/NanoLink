import SwiftUI

/// Live alerts + recent audit activity. Pull-to-refresh fetches both feeds;
/// individual alerts and all alerts can be acknowledged through the server API.
struct AlertsScreen: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.nano) private var t
    @State private var clearing = false
    @State private var message: String?

    private var alerts: [AlertInstance] {
        store.serverAlerts().filter { !$0.acked }.sorted { rank($0.level) < rank($1.level) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                stats.padding(.top, 12)
                NanoSectionLabel(tr("alerts.current"))
                if alerts.isEmpty { emptyAlerts }
                else {
                    ForEach(alerts) { alert in
                        alertCard(alert).padding(.bottom, 8)
                    }
                }
                NanoSectionLabel(tr("alerts.auditRecent"))
                let audit = store.recentActivity()
                if audit.isEmpty {
                    NanoCard(padding: EdgeInsets(top: 22, leading: 12, bottom: 22, trailing: 12)) {
                        Text(tr("alerts.auditEmpty")).font(.system(size: 12.5)).foregroundColor(t.fg4).frame(maxWidth: .infinity)
                    }
                } else {
                    NanoCard {
                        ForEach(Array(audit.prefix(6).enumerated()), id: \.element.id) { index, entry in
                            auditRow(entry, divider: index < min(audit.count, 6) - 1)
                        }
                    }
                }
                if let message {
                    Text(message).font(.system(size: 12.5)).foregroundColor(t.fg3).padding(.top, 12)
                }
            }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 100, trailing: 16))
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await refresh() }
        .background(t.bg)
        .navigationBarHidden(true)
        .task { await refresh() }
    }

    private var header: some View {
        HStack {
            Text(tr("alerts.title"))
                .font(.system(size: t.isIOS ? 32 : 28, weight: t.displayWeight)).tracking(t.displayTracking).foregroundColor(t.fg)
            Spacer()
            if clearing { ProgressView().frame(width: 36, height: 36) }
            else {
                Button(tr("alerts.clearAll")) { acknowledgeAll() }
                    .font(.system(size: 15, weight: .medium)).foregroundColor(alerts.isEmpty ? t.fg4 : t.accent)
                    .disabled(alerts.isEmpty)
            }
        }.padding(.top, t.isIOS ? 32 : 4)
    }

    private var stats: some View {
        let critical = alerts.filter { $0.level == "crit" }.count
        let warning = alerts.filter { $0.level == "warn" }.count
        let info = alerts.filter { $0.level == "info" }.count
        return NanoCard(padding: EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14), outlined: true) {
            HStack(spacing: 0) {
                miniStat(tr("alerts.critical"), critical, t.crit)
                Rectangle().fill(t.sep).frame(width: 1, height: 38)
                miniStat(tr("alerts.warning"), warning, t.warn)
                Rectangle().fill(t.sep).frame(width: 1, height: 38)
                miniStat(tr("alerts.info"), info, t.info)
            }
        }
    }

    private func miniStat(_ label: String, _ value: Int, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(value)").font(.system(size: 26, weight: .semibold)).foregroundColor(color).monospacedDigit()
            HStack(spacing: 5) { Circle().fill(color).frame(width: 6, height: 6); Text(label).font(.system(size: 11.5, weight: .medium)).foregroundColor(t.fg3) }
        }.frame(maxWidth: .infinity)
    }

    private var emptyAlerts: some View {
        NanoCard(padding: EdgeInsets(top: 36, leading: 12, bottom: 36, trailing: 12)) {
            VStack(spacing: 7) {
                Image(systemName: "checkmark.circle").font(.system(size: 30)).foregroundColor(t.ok)
                Text(tr("alerts.allClear")).font(.system(size: 15, weight: .medium)).foregroundColor(t.fg2)
                Text(tr("alerts.allClearSub")).font(.system(size: 12.5)).foregroundColor(t.fg4).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity)
        }
    }

    private func alertCard(_ alert: AlertInstance) -> some View {
        let color = alert.level == "crit" ? t.crit : (alert.level == "warn" ? t.warn : t.info)
        return Button { acknowledge(alert.id) } label: {
            HStack(alignment: .top, spacing: 14) {
                ZStack { Circle().fill(color.opacity(0.16)); Image(systemName: "exclamationmark.triangle").font(.system(size: 15)).foregroundColor(color) }
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Text(alert.title).font(.system(size: 14, weight: .medium)).foregroundColor(t.fg).lineLimit(1)
                        Spacer()
                        if !alert.since.isEmpty { Text(alert.since).font(.system(size: 11)).foregroundColor(t.fg4) }
                    }
                    if !alert.description.isEmpty { Text(alert.description).font(.system(size: 12.5)).foregroundColor(t.fg3).lineSpacing(3) }
                    if !alert.agent.isEmpty { NanoBadge(text: alert.agent, mono: true) }
                }
            }
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.card)
            .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 4) }
            .clipShape(RoundedRectangle(cornerRadius: t.cardRadius, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func auditRow(_ entry: AuditEntry, divider: Bool) -> some View {
        NanoListRow(divider: divider) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    NanoMono(entry.type, size: 13, color: t.fg, weight: .medium)
                    Text(Fmt.ago(entry.at)).font(.system(size: 11)).foregroundColor(t.fg4)
                }
                Text("\(entry.user.isEmpty ? "—" : entry.user)  →  \(entry.agentHostname.isEmpty ? "—" : entry.agentHostname)")
                    .font(.system(size: 12)).foregroundColor(t.fg3).lineLimit(1)
            }
        } leading: { NanoStatusDot(color: entry.ok ? t.ok : t.crit, size: 8) }
    }

    private func rank(_ level: String) -> Int { level == "crit" ? 0 : (level == "warn" ? 1 : 2) }

    private func refresh() async {
        guard let id = store.activeServerId else { return }
        async let a = store.fetchServerAlerts(serverId: id)
        async let b = store.fetchRecentActivity(serverId: id, limit: 50)
        _ = await (a, b)
    }

    private func acknowledge(_ id: String) {
        Task {
            if let error = await store.acknowledgeAlert(id) { message = tr("alerts.ackFailed", ["error": error]) }
        }
    }

    private func acknowledgeAll() {
        guard !clearing else { return }
        clearing = true
        Task {
            let count = await store.acknowledgeAllAlerts()
            clearing = false
            if let count { if count > 0 { message = tr("alerts.clearedCount", ["n": count]) } }
            else { message = tr("alerts.clearAllFailed") }
        }
    }
}
