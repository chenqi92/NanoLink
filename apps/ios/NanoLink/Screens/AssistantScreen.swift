import SwiftUI

private struct AssistantTurn: Identifiable {
    let id = UUID()
    let role: String
    let content: String
    let isError: Bool

    var isUser: Bool { role == "user" }
}

/// Combined AI assistant screen with findings + chat.
struct AssistantScreen: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.nano) private var t

    @State private var findings: [AssistantFinding] = []
    @State private var turns: [AssistantTurn] = []
    @State private var input = ""
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12, pinnedViews: []) {
                        if !findings.isEmpty {
                            findingsSection
                        }

                        if turns.isEmpty && !sending {
                            emptyChatState
                        }

                        ForEach(turns) { turn in
                            chatBubble(turn).id(turn.id)
                        }

                        if sending {
                            thinkingBubble.id("thinking")
                        }
                    }
                    .padding(EdgeInsets(top: 12, leading: 16, bottom: 32, trailing: 16))
                }
                .onChange(of: turns.count) { _ in scroll(proxy) }
                .onChange(of: sending) { _ in scroll(proxy) }
            }

            composer
        }
        .background(t.bg.ignoresSafeArea())
        .navigationTitle(tr("assistant.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadFindings() }
    }

    private var findingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("assistant.diagnosis"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(t.fg3)

            FlowLayout(spacing: 8) {
                ForEach(findings) { finding in
                    findingCard(finding)
                }
            }
        }
    }

    private func findingCard(_ finding: AssistantFinding) -> some View {
        let (icon, tone) = toneIcon(finding.kind)

        return NanoCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(tone)
                    Text(finding.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(t.fg)
                }

                Text(finding.detail)
                    .font(.system(size: 12))
                    .foregroundColor(t.fg3)
                    .lineSpacing(4)

                if !finding.actions.isEmpty, let agentId = finding.agentId {
                    FlowLayout(spacing: 6) {
                        ForEach(finding.actions, id: \.self) { action in
                            actionChip(action, agentId: agentId)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private func actionChip(_ action: String, agentId: String) -> some View {
        let agent = store.agentById(agentId)
        let initialTab = action == "history" ? 1 : action == "shell" || action == "terminal" ? 2 : 0

        return NavigationLink {
            if let agent = agent {
                AgentDetailScreen(agent: agent, initialTab: initialTab)
            }
        } label: {
            Text(tr("assistant.action.\(action)"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(t.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(t.accent.opacity(0.14))
                .clipShape(Capsule())
        }
    }

    private var emptyChatState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 42))
                .foregroundColor(t.fg4)

            Text(tr("assistant.greeting"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(t.fg)

            Text(tr("assistant.intro"))
                .font(.system(size: 13))
                .foregroundColor(t.fg3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer().frame(height: 8)

            Text(tr("assistant.tryThese"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(t.fg3)

            FlowLayout(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button { send(suggestion) } label: {
                        Text(suggestion)
                            .font(.system(size: 12))
                            .foregroundColor(t.fg2)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(t.card2)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 32)
    }

    private var suggestions: [String] {
        [
            tr("assistant.suggestion.highCpu"),
            tr("assistant.suggestion.diskSpace"),
            tr("assistant.suggestion.offlineNodes"),
            tr("assistant.suggestion.resourceTrend"),
        ]
    }

    private func chatBubble(_ turn: AssistantTurn) -> some View {
        HStack {
            if turn.isUser { Spacer(minLength: 50) }

            Text(turn.content)
                .font(.system(size: 14))
                .foregroundColor(turn.isUser ? t.fg : turn.isError ? t.crit : t.fg2)
                .lineSpacing(5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(turn.isUser ? t.accent.opacity(0.14) : turn.isError ? t.crit.opacity(0.12) : t.card2)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !turn.isUser { Spacer(minLength: 50) }
        }
    }

    private var thinkingBubble: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(t.fg3)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(t.card2)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Spacer(minLength: 50)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(tr("assistant.inputHint"), text: $input, axis: .vertical)
                .font(.system(size: 14))
                .focused($focused)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(t.card)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .submitLabel(.send)
                .onSubmit { send(nil) }
                .disabled(sending)

            Button { send(nil) } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundColor(t.onAccent)
            }
            .frame(width: 40, height: 40)
            .background(
                (sending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ?
                    t.card2 : t.accent
            )
            .clipShape(Circle())
            .disabled(sending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .background(t.bg)
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard !turns.isEmpty || sending else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                if sending {
                    proxy.scrollTo("thinking", anchor: .bottom)
                } else {
                    proxy.scrollTo(turns.last?.id, anchor: .bottom)
                }
            }
        }
    }

    private func send(_ preset: String?) {
        let message = preset ?? input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !sending else { return }

        turns.append(AssistantTurn(role: "user", content: message, isError: false))
        input = ""
        sending = true

        Task {
            guard let serverId = store.activeServerId,
                  let service = store.serviceForServer(serverId) else {
                sending = false
                turns.append(AssistantTurn(role: "assistant", content: tr("assistant.error.notConfigured"), isError: true))
                return
            }

            let history = turns.map { ChatMessage(role: $0.role, content: $0.content) }
            let result = await service.assistantChat(history)

            await MainActor.run {
                sending = false
                if result.ok, let reply = result.reply {
                    turns.append(AssistantTurn(role: reply.role, content: reply.content, isError: false))
                } else {
                    let errorMsg = errorText(result.error)
                    turns.append(AssistantTurn(role: "assistant", content: errorMsg, isError: true))
                }
            }
        }
    }

    private func errorText(_ error: AssistantChatError?) -> String {
        switch error {
        case .notConfigured: return tr("assistant.error.notConfigured")
        case .badRequest: return tr("assistant.error.badRequest")
        case .upstreamFailed: return tr("assistant.error.upstreamFailed")
        case .serverError: return tr("assistant.error.serverError")
        case .network: return tr("assistant.error.network")
        case .none: return tr("assistant.error.unknown")
        }
    }

    private func loadFindings() async {
        guard let serverId = store.activeServerId,
              let service = store.serviceForServer(serverId) else { return }
        if let result = await service.fetchAssistantFindings() {
            await MainActor.run { findings = result }
        }
    }

    private func toneIcon(_ kind: String) -> (String, Color) {
        switch kind {
        case "anomaly": return ("bolt.fill", t.crit)
        case "warn": return ("exclamationmark.triangle.fill", t.warn)
        case "info": return ("info.circle.fill", t.info)
        case "ok": return ("checkmark.circle.fill", t.ok)
        default: return ("info.circle.fill", t.fg3)
        }
    }
}

/// Wrapping layout used by finding actions and suggested prompts.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
