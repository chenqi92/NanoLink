import SwiftUI

private struct AssistantTurn: Identifiable {
    let id = UUID()
    let role: String
    let content: String
    var isError = false
    var isUser: Bool { role == "user" }
}

/// Conversational assistant backed by `POST /api/assistant/chat`, preserving the
/// non-error transcript and rendering server/network failures inline.
struct AssistantChatScreen: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.nano) private var t
    @State private var turns: [AssistantTurn] = []
    @State private var input = ""
    @State private var sending = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if turns.isEmpty { emptyState }
                        else {
                            ForEach(turns) { turn in bubble(turn).id(turn.id) }
                            if sending { ThinkingBubble().id("thinking") }
                        }
                    }
                    .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                }
                .onChange(of: turns.count) { _ in scroll(proxy) }
                .onChange(of: sending) { _ in scroll(proxy) }
            }
            composer
        }
        .background(t.bg.ignoresSafeArea())
        .navigationTitle(tr("assistant.chatTitle"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(colors: [t.accent, t.tertiary], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "sparkles").font(.system(size: 25)).foregroundColor(.white)
            }
            .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(tr("assistant.greeting")).font(.system(size: 18, weight: .bold)).foregroundColor(t.fg).padding(.top, 16)
            Text(tr("assistant.intro")).font(.system(size: 13.5)).foregroundColor(t.fg3).multilineTextAlignment(.center).lineSpacing(5).padding(.top, 8)
            HStack(spacing: 6) { Image(systemName: "bolt.fill"); Text(tr("assistant.tryThese")) }
                .font(.system(size: 13, weight: .semibold)).foregroundColor(t.fg2).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 24)
            ForEach(suggestions, id: \.self) { suggestion in
                Button { send(suggestion) } label: {
                    HStack {
                        Text(suggestion).font(.system(size: 13.5)).foregroundColor(t.fg2).multilineTextAlignment(.leading)
                        Spacer(); Image(systemName: "arrow.up.right").font(.system(size: 14)).foregroundColor(t.fg4)
                    }
                    .padding(.horizontal, 14).frame(minHeight: 46).background(t.card)
                    .overlay(RoundedRectangle(cornerRadius: t.cardRadius).stroke(t.sep2, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: t.cardRadius, style: .continuous))
                }.buttonStyle(.plain).padding(.top, 8)
            }
        }
        .padding(EdgeInsets(top: 14, leading: 4, bottom: 20, trailing: 4))
    }

    private var suggestions: [String] { [tr("assistant.suggestTopCpu"), tr("assistant.suggestDiskFull"), tr("assistant.suggestHealth")] }

    private func bubble(_ turn: AssistantTurn) -> some View {
        HStack {
            if turn.isUser { Spacer(minLength: 50) }
            VStack(alignment: .leading, spacing: 5) {
                if turn.isError {
                    Label(tr("assistant.errLabel"), systemImage: "exclamationmark.circle")
                        .font(.system(size: 11.5, weight: .semibold)).foregroundColor(t.crit)
                }
                Text(turn.content).font(.system(size: 14.5)).foregroundColor(turn.isUser ? t.onAccent : t.fg)
                    .lineSpacing(4).textSelection(.enabled)
            }
            .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
            .background(turn.isUser ? t.accent : (turn.isError ? t.crit.opacity(0.14) : t.card))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(turn.isError ? t.crit.opacity(0.4) : (turn.isUser ? .clear : t.sep2), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            if !turn.isUser { Spacer(minLength: 50) }
        }.padding(.bottom, 10)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(tr("assistant.inputHint"), text: $input, axis: .vertical)
                .font(.system(size: 15)).foregroundColor(t.fg).lineLimit(1...5)
                .padding(.horizontal, 14).padding(.vertical, 10).background(t.card2)
                .overlay(Capsule().stroke(t.sep2, lineWidth: 0.5)).clipShape(Capsule())
                .focused($focused).disabled(sending).submitLabel(.send).onSubmit { send() }
            Button { send() } label: {
                ZStack {
                    if sending { t.card3; ProgressView().tint(t.fg4).scaleEffect(0.8) }
                    else { LinearGradient(colors: [t.accent, t.tertiary], startPoint: .topLeading, endPoint: .bottomTrailing); Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold)).foregroundColor(t.onAccent) }
                }.frame(width: 40, height: 40).clipShape(Circle())
            }.buttonStyle(.plain).disabled(sending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 12, trailing: 12))
        .background(t.bg).overlay(alignment: .top) { Rectangle().fill(t.sep2).frame(height: 0.5) }
    }

    private func send(_ preset: String? = nil) {
        let text = (preset ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        turns.append(AssistantTurn(role: "user", content: text)); input = ""; sending = true
        guard let id = store.activeServerId, let service = store.serviceForServer(id) else {
            turns.append(AssistantTurn(role: "assistant", content: tr("assistant.noServer"), isError: true)); sending = false; return
        }
        let history = turns.filter { !$0.isError }.map { ChatMessage(role: $0.role, content: $0.content) }
        Task {
            let result = await service.assistantChat(history)
            sending = false
            if result.ok, let reply = result.reply { turns.append(AssistantTurn(role: "assistant", content: reply.content)) }
            else { turns.append(AssistantTurn(role: "assistant", content: errorText(result.error), isError: true)) }
        }
    }

    private func errorText(_ error: AssistantChatError?) -> String {
        switch error { case .notConfigured: return tr("assistant.errNotConfigured"); case .upstreamFailed: return tr("assistant.errUpstream"); case .badRequest: return tr("assistant.errBadRequest"); case .network: return tr("assistant.errNetwork"); default: return tr("assistant.errServer") }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.24)) {
            if sending { proxy.scrollTo("thinking", anchor: .bottom) }
            else if let last = turns.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }
}

private struct ThinkingBubble: View {
    @Environment(\.nano) private var t
    @State private var animate = false
    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle().fill(t.fg3).frame(width: 7, height: 7)
                        .offset(y: animate ? -3 : 3).opacity(animate ? 0.9 : 0.35)
                        .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true).delay(Double(index) * 0.14), value: animate)
                }
            }
            .padding(.horizontal, 16).frame(height: 42).background(t.card)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(t.sep2, lineWidth: 0.5)).clipShape(RoundedRectangle(cornerRadius: 18))
            Spacer()
        }.padding(.bottom, 10).onAppear { animate = true }
    }
}
