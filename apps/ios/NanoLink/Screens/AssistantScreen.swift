import SwiftUI

/// Server-generated operational findings with direct links to the relevant node,
/// history chart or remote terminal.
struct AssistantScreen: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.nano) private var t
    @State private var findings: [AssistantFinding]?
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        Group {
            if loading { ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if failed { errorView }
            else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        intro.padding(.bottom, 4)
                        ForEach(findings ?? []) { finding in findingCard(finding) }
                    }
                    .padding(EdgeInsets(top: 12, leading: 16, bottom: 32, trailing: 16))
                }.nanoPullToRefresh(enabled: !t.desktop) { await load() }
            }
        }
        .background(t.bg.ignoresSafeArea())
        .navigationTitle(tr("assistant.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                NavigationLink { AssistantChatScreen() } label: { Image(systemName: "bubble.left.and.bubble.right") }
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .task { await load() }
    }

    private var intro: some View {
        let actionable = (findings ?? []).filter { $0.kind != "ok" }.count
        return VStack(alignment: .leading, spacing: 10) {
            Label(tr("assistant.autoDiagnosis"), systemImage: "chart.line.uptrend.xyaxis")
                .font(.system(size: 15, weight: .semibold)).foregroundColor(t.fg)
            Text(actionable == 0 ? tr("assistant.allHealthy") : tr("assistant.findingsCount", ["n": actionable]))
                .font(.system(size: 13)).foregroundColor(t.fg2).lineSpacing(4)
            NavigationLink { AssistantChatScreen() } label: {
                Label(tr("assistant.askAssistant"), systemImage: "bubble.left.fill")
                    .font(.system(size: 13.5, weight: .semibold)).foregroundColor(t.onAccent)
                    .padding(.horizontal, 14).frame(height: 40)
                    .background(LinearGradient(colors: [t.accent, t.tertiary], startPoint: .leading, endPoint: .trailing))
                    .clipShape(RoundedRectangle(cornerRadius: t.buttonRadius, style: .continuous))
            }.buttonStyle(.plain)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [t.accent.opacity(0.16), t.tertiary.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: t.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private func findingCard(_ finding: AssistantFinding) -> some View {
        let tone = findingTone(finding.kind)
        let agent = finding.agentId.flatMap(store.agentById)
        NanoCard(padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: tone.icon).font(.system(size: 17)).foregroundColor(tone.color)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(finding.title).font(.system(size: 14.5, weight: .semibold)).foregroundColor(t.fg)
                        Text(finding.detail).font(.system(size: 12.5)).foregroundColor(t.fg3).lineSpacing(4)
                    }
                }
                if let agent, !finding.actions.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(finding.actions, id: \.self) { action in
                            NavigationLink { AgentDetailScreen(agent: agent, initialTab: tab(for: action)) } label: {
                                Text(label(for: action)).font(.system(size: 12.5, weight: .medium)).foregroundColor(t.fg2)
                                    .padding(.horizontal, 11).frame(height: 30).background(t.card2)
                                    .overlay(Capsule().stroke(t.sep2, lineWidth: 0.5)).clipShape(Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                } else if let agent {
                    NavigationLink { AgentDetailScreen(agent: agent) } label: {
                        Label(agent.hostname, systemImage: "chevron.right").font(.system(size: 12.5)).foregroundColor(t.accent)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "icloud.slash").font(.system(size: 34)).foregroundColor(t.fg4)
            Text(tr("assistant.loadError")).font(.system(size: 16, weight: .semibold)).foregroundColor(t.fg)
            Text(tr("assistant.loadErrorDesc")).font(.system(size: 13)).foregroundColor(t.fg3).multilineTextAlignment(.center).lineSpacing(4)
            NanoButton(tr("common.retry"), icon: "arrow.clockwise", variant: .text) { Task { await load() } }
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor private func load() async {
        loading = true; failed = false
        guard let id = store.activeServerId, let service = store.serviceForServer(id) else { loading = false; failed = true; return }
        findings = await service.fetchAssistantFindings()
        failed = findings == nil
        loading = false
    }

    private func findingTone(_ kind: String) -> (color: Color, icon: String) {
        switch kind { case "anomaly": return (t.crit, "bolt.fill"); case "warn": return (t.warn, "exclamationmark.triangle"); case "ok": return (t.ok, "checkmark.circle.fill"); default: return (t.info, "info.circle") }
    }
    private func tab(for action: String) -> Int { let a = action.lowercased(); return a.contains("history") ? 1 : ((a.contains("shell") || a.contains("terminal")) ? 2 : 0) }
    private func label(for action: String) -> String { let a = action.lowercased(); if a.contains("history") { return tr("assistant.actHistory") }; if a.contains("shell") || a.contains("terminal") { return tr("assistant.actShell") }; if a.contains("process") { return tr("assistant.actProcesses") }; return action }
}

/// Simple wrapping layout for action chips, available on iOS 16.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
    }
}
