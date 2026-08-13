import SwiftUI
import UIKit

/// UserDefaults keys shared by settings and the features that consume them.
enum AppPreferenceKey {
    static let notifyAudit = "notify_audit"
    static let terminalTheme = "term_theme"
    static let terminalFontSize = "term_font_size"
    static let terminalCursor = "term_cursor"
    static let terminalCursorBlink = "term_cursor_blink"
    static let faceId = "sec_face_id"
    static let autoLock = "sec_auto_lock"
}

/// Live command-oriented remote terminal backed by `ShellSession`.
struct NanoTerminalView: View {
    let agent: Agent

    @EnvironmentObject private var store: AppStore
    @Environment(\.nano) private var t
    @State private var session: ShellSession?
    @State private var setupFailed = false

    var body: some View {
        Group {
            if agent.permissionLevel < 3 {
                locked
            } else if let session {
                NanoTerminalConsole(agent: agent, session: session)
            } else if setupFailed {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.icloud").font(.system(size: 30)).foregroundColor(t.crit)
                    Text(tr("terminal.consoleNoServer")).font(.system(size: 13)).foregroundColor(t.fg3)
                        .multilineTextAlignment(.center)
                }
                .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(argb: 0xFF090B0A))
        .task { createSessionIfNeeded() }
        .onDisappear {
            session?.close()
            session = nil
        }
    }

    private var locked: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill").font(.system(size: 30)).foregroundColor(t.warn)
            Text(tr("terminal.lockedTitle")).font(.system(size: 16, weight: .semibold)).foregroundColor(t.fg)
            Text(tr("terminal.lockedDesc")).font(.system(size: 13)).foregroundColor(t.fg3)
                .multilineTextAlignment(.center).lineSpacing(4)
        }
        .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func createSessionIfNeeded() {
        guard session == nil else { return }
        guard let service = store.serviceForAgent(agent.id) else { setupFailed = true; return }
        let shell = service.openShell(agent.id)
        session = shell
        shell.system(tr("terminal.consoleConnecting", ["url": shell.displayUrl]))
        shell.connect()
    }
}

private struct NanoTerminalConsole: View {
    let agent: Agent
    @ObservedObject var session: ShellSession
    @Environment(\.nano) private var t
    @AppStorage(AppPreferenceKey.terminalTheme) private var terminalTheme = "phosphor"
    @AppStorage(AppPreferenceKey.terminalFontSize) private var terminalFontSize = 13
    @AppStorage(AppPreferenceKey.terminalCursor) private var terminalCursor = "block"
    @AppStorage(AppPreferenceKey.terminalCursorBlink) private var terminalCursorBlink = true
    @State private var input = ""
    @State private var commandHistory: [String] = []
    @State private var historyIndex: Int?
    @State private var lastTerminalSize: (cols: Int, rows: Int)?
    @State private var inputRequest: TerminalInputRequest?

    private var palette: TerminalPalette { TerminalPalette.named(terminalTheme) }

    private var statusColor: Color {
        switch session.status {
        case .connected: return t.ok
        case .connecting: return t.warn
        case .error: return t.crit
        case .closed: return t.fg4
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                NanoStatusDot(color: statusColor, pulse: session.status == .connected)
                NanoMono(agent.hostname, size: 12, color: palette.subtle, weight: .semibold)
                Spacer()
                NanoMono(statusLabel, size: 10.5, color: palette.muted)
                if session.status == .error || session.status == .closed {
                    Button { session.reconnect() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(palette.accent)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr("terminal.reconnect"))
                }
                Button { session.clearLines() } label: {
                    Image(systemName: "trash").font(.system(size: 13)).foregroundColor(palette.subtle)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("terminal.clear"))
            }
            .padding(.horizontal, 12).frame(height: 42)
            .background(palette.chrome)
            .overlay(alignment: .bottom) { Rectangle().fill(palette.separator).frame(height: 0.5) }

            ScrollViewReader { proxy in
                GeometryReader { geometry in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(session.lines) { line in
                                TerminalLineView(line: line, fontSize: CGFloat(terminalFontSize), palette: palette)
                                    .id(line.id)
                            }
                        }
                        .padding(EdgeInsets(top: 10, leading: 12, bottom: 14, trailing: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(palette.background)
                    .onAppear { resizeTerminal(for: geometry.size) }
                    .onChange(of: geometry.size) { resizeTerminal(for: $0) }
                    .onChange(of: terminalFontSize) { _ in resizeTerminal(for: geometry.size) }
                    .onChange(of: session.lines.count) { _ in
                        guard let last = session.lines.last else { return }
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            VStack(spacing: 0) {
                terminalKeys
                HStack(alignment: .bottom, spacing: 8) {
                    Text("$").font(NanoFont.mono(CGFloat(terminalFontSize + 1), weight: .bold)).foregroundColor(palette.accent)
                        .padding(.bottom, 9)
                    TerminalCommandField(
                        text: $input,
                        request: $inputRequest,
                        placeholder: session.status == .connected ? tr("terminal.inputHint") : tr("terminal.inputHintWaiting"),
                        fontSize: CGFloat(terminalFontSize),
                        foreground: UIColor(palette.foreground),
                        placeholderColor: UIColor(palette.muted),
                        accent: UIColor(palette.accent),
                        cursorStyle: terminalCursor,
                        cursorBlink: terminalCursorBlink,
                        isEnabled: session.status == .connected,
                        onSubmit: submit
                    )
                    .frame(height: 36)
                    Button(action: submit) {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 25))
                            .foregroundColor(session.status == .connected && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                             ? palette.accent : palette.disabled)
                    }
                    .buttonStyle(.plain)
                    .disabled(session.status != .connected || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 10))
            }
            .background(palette.chrome)
            .overlay(alignment: .top) { Rectangle().fill(palette.separator).frame(height: 0.5) }
        }
        .background(palette.background)
        .onChange(of: session.status) { status in
            guard status == .connected else { return }
            session.system(tr("terminal.consoleAuthenticated", ["level": agent.permissionLevel]))
            lastTerminalSize = nil
        }
    }

    private var terminalKeys: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                terminalKey("Esc") { applyInput(.clear) }
                terminalKey("Tab") { applyInput(.insert("\t")) }
                terminalKey("Ctrl+C") { interruptCommand() }
                terminalKey("Alt") { applyInput(.toggleHomeEnd) }
                terminalKey("↑") { previousCommand() }
                terminalKey("↓") { nextCommand() }
                terminalKey("←") { applyInput(.move(-1)) }
                terminalKey("→") { applyInput(.move(1)) }
                terminalKey("/") { applyInput(.insert("/")) }
                terminalKey("|") { applyInput(.insert("|")) }
                terminalKey("-") { applyInput(.insert("-")) }
                terminalKey("~") { applyInput(.insert("~")) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(palette.separator).frame(height: 0.5) }
    }

    private func terminalKey(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NanoMono(label, size: 11.5, color: session.status == .connected ? palette.subtle : palette.disabled, weight: .medium)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(palette.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(session.status != .connected)
    }

    private var statusLabel: String {
        switch session.status {
        case .connecting: return tr("status.connecting")
        case .connected: return tr("status.connected")
        case .error: return tr("status.error")
        case .closed: return tr("status.closed")
        }
    }

    private func submit() {
        let command = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, session.status == .connected else { return }
        input = ""
        if commandHistory.last != command { commandHistory.append(command) }
        historyIndex = nil
        if command == "clear" || command == "cls" {
            session.clearLines()
            return
        }
        session.echoInput(command)
        session.sendInput(command)
    }

    private func interruptCommand() {
        guard session.status == .connected else { return }
        session.sendInput("\u{3}")
        input = ""
        historyIndex = nil
        applyInput(.clear)
    }

    private func applyInput(_ command: TerminalInputCommand) {
        inputRequest = TerminalInputRequest(command: command)
    }

    private func previousCommand() {
        guard !commandHistory.isEmpty else { return }
        let next = max(0, (historyIndex ?? commandHistory.count) - 1)
        historyIndex = next
        input = commandHistory[next]
        applyInput(.moveToEnd)
    }

    private func nextCommand() {
        guard let current = historyIndex else { return }
        let next = current + 1
        if next >= commandHistory.count {
            historyIndex = nil
            input = ""
            applyInput(.clear)
        } else {
            historyIndex = next
            input = commandHistory[next]
            applyInput(.moveToEnd)
        }
    }

    private func resizeTerminal(for size: CGSize) {
        guard session.status == .connected, size.width > 0, size.height > 0 else { return }
        let characterWidth = max(7, CGFloat(terminalFontSize) * 0.62)
        let lineHeight = max(14, CGFloat(terminalFontSize) * 1.35)
        let cols = max(20, Int((size.width - 24) / characterWidth))
        let rows = max(8, Int((size.height - 20) / lineHeight))
        guard lastTerminalSize?.cols != cols || lastTerminalSize?.rows != rows else { return }
        lastTerminalSize = (cols, rows)
        session.resize(cols: cols, rows: rows)
    }
}

private enum TerminalInputCommand: Equatable {
    case clear
    case insert(String)
    case move(Int)
    case toggleHomeEnd
    case moveToEnd
}

private struct TerminalInputRequest: Equatable {
    let id = UUID()
    let command: TerminalInputCommand
}

private struct TerminalCommandField: UIViewRepresentable {
    @Binding var text: String
    @Binding var request: TerminalInputRequest?
    let placeholder: String
    let fontSize: CGFloat
    let foreground: UIColor
    let placeholderColor: UIColor
    let accent: UIColor
    let cursorStyle: String
    let cursorBlink: Bool
    let isEnabled: Bool
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> TerminalUITextField {
        let field = TerminalUITextField(frame: .zero)
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.returnKeyType = .send
        field.clearButtonMode = .never
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.addTarget(context.coordinator, action: #selector(Coordinator.submitted(_:)), for: .editingDidEndOnExit)
        return field
    }

    func updateUIView(_ field: TerminalUITextField, context: Context) {
        context.coordinator.parent = self
        field.isEnabled = isEnabled
        field.textColor = foreground
        field.cursorColor = accent
        field.terminalCursorStyle = cursorStyle
        field.terminalCursorBlink = cursorBlink
        field.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: placeholderColor]
        )

        if field.text != text {
            field.text = text
            context.coordinator.moveCaretToEnd(field)
        }
        if let request, request.id != context.coordinator.lastRequestId {
            context.coordinator.lastRequestId = request.id
            context.coordinator.apply(request.command, to: field)
        }
    }

    final class Coordinator: NSObject {
        var parent: TerminalCommandField
        var lastRequestId: UUID?

        init(_ parent: TerminalCommandField) { self.parent = parent }

        @objc func changed(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        @objc func submitted(_ field: UITextField) {
            parent.onSubmit()
        }

        func apply(_ command: TerminalInputCommand, to field: UITextField) {
            switch command {
            case .clear:
                field.text = ""
                moveCaretToEnd(field)
            case .insert(let value):
                if let selection = field.selectedTextRange {
                    field.replace(selection, withText: value)
                } else {
                    field.text = (field.text ?? "") + value
                }
            case .move(let delta):
                moveCaret(field, by: delta)
            case .toggleHomeEnd:
                toggleHomeEnd(field)
            case .moveToEnd:
                moveCaretToEnd(field)
            }
            field.becomeFirstResponder()
            field.setNeedsLayout()
            let updated = field.text ?? ""
            DispatchQueue.main.async { [weak self] in self?.parent.text = updated }
        }

        func moveCaretToEnd(_ field: UITextField) {
            let length = ((field.text ?? "") as NSString).length
            guard let end = field.position(from: field.beginningOfDocument, offset: length) else { return }
            field.selectedTextRange = field.textRange(from: end, to: end)
        }

        private func moveCaret(_ field: UITextField, by delta: Int) {
            guard let selection = field.selectedTextRange else { return }
            let current = field.offset(from: field.beginningOfDocument, to: selection.start)
            let length = ((field.text ?? "") as NSString).length
            let target = min(max(0, current + delta), length)
            guard let position = field.position(from: field.beginningOfDocument, offset: target) else { return }
            field.selectedTextRange = field.textRange(from: position, to: position)
        }

        private func toggleHomeEnd(_ field: UITextField) {
            let current = field.selectedTextRange.map {
                field.offset(from: field.beginningOfDocument, to: $0.start)
            } ?? 0
            let length = ((field.text ?? "") as NSString).length
            let target = current == 0 ? length : 0
            guard let position = field.position(from: field.beginningOfDocument, offset: target) else { return }
            field.selectedTextRange = field.textRange(from: position, to: position)
        }
    }
}

private final class TerminalUITextField: UITextField {
    var terminalCursorStyle = "block" { didSet { setNeedsLayout() } }
    var terminalCursorBlink = true { didSet { updateCursorAppearance() } }
    var cursorColor = UIColor.systemGreen { didSet { updateCursorAppearance() } }
    private let steadyCursor = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        steadyCursor.isHidden = true
        layer.addSublayer(steadyCursor)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        steadyCursor.isHidden = true
        layer.addSublayer(steadyCursor)
    }

    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        let glyphWidth = max(7, (font?.pointSize ?? 13) * 0.62)
        switch terminalCursorStyle {
        case "underline":
            rect.origin.y = rect.maxY - 2
            rect.size = CGSize(width: glyphWidth, height: 2)
        case "block":
            rect.size.width = glyphWidth
        default:
            rect.size.width = 2
        }
        return rect
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateCursorAppearance()
        guard !terminalCursorBlink, isFirstResponder,
              let selection = selectedTextRange,
              offset(from: selection.start, to: selection.end) == 0 else {
            steadyCursor.isHidden = true
            return
        }
        steadyCursor.frame = caretRect(for: selection.start)
        steadyCursor.isHidden = false
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        setNeedsLayout()
        return result
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        setNeedsLayout()
        return result
    }

    private func updateCursorAppearance() {
        tintColor = terminalCursorBlink ? cursorColor : .clear
        steadyCursor.backgroundColor = cursorColor.cgColor
        steadyCursor.isHidden = terminalCursorBlink || !isFirstResponder
    }
}

private struct TerminalLineView: View {
    let line: ShellLine
    let fontSize: CGFloat
    let palette: TerminalPalette

    private var color: Color {
        switch line.kind {
        case .sys: return palette.muted
        case .input: return palette.accent
        case .output: return palette.foreground
        case .error: return palette.error
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if line.kind == .input {
                Text("$").font(NanoFont.mono(fontSize, weight: .bold)).foregroundColor(color)
            }
            Text(line.text)
                .font(NanoFont.mono(fontSize))
                .foregroundColor(color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TerminalPalette {
    let background: Color
    let chrome: Color
    let separator: Color
    let foreground: Color
    let subtle: Color
    let muted: Color
    let accent: Color
    let error: Color
    let disabled: Color

    static func named(_ id: String) -> TerminalPalette {
        switch id {
        case "amber":
            return TerminalPalette(
                background: Color(argb: 0xFF100C05), chrome: Color(argb: 0xFF191207),
                separator: Color(argb: 0xFF3B2A0A), foreground: Color(argb: 0xFFFFE5AF),
                subtle: Color(argb: 0xFFCDB67C), muted: Color(argb: 0xFF8B764C),
                accent: Color(argb: 0xFFFFB000), error: Color(argb: 0xFFFF6B62),
                disabled: Color(argb: 0xFF5E5134)
            )
        case "mono":
            return TerminalPalette(
                background: Color(argb: 0xFF090909), chrome: Color(argb: 0xFF141414),
                separator: Color(argb: 0xFF303030), foreground: Color(argb: 0xFFE7E7E7),
                subtle: Color(argb: 0xFFB8B8B8), muted: Color(argb: 0xFF777777),
                accent: Color(argb: 0xFFFFFFFF), error: Color(argb: 0xFFFF6B62),
                disabled: Color(argb: 0xFF555555)
            )
        case "solarized":
            return TerminalPalette(
                background: Color(argb: 0xFF002B36), chrome: Color(argb: 0xFF073642),
                separator: Color(argb: 0xFF31545C), foreground: Color(argb: 0xFFEEE8D5),
                subtle: Color(argb: 0xFF93A1A1), muted: Color(argb: 0xFF657B83),
                accent: Color(argb: 0xFF2AA198), error: Color(argb: 0xFFDC322F),
                disabled: Color(argb: 0xFF49676E)
            )
        default:
            return TerminalPalette(
                background: Color(argb: 0xFF090B0A), chrome: Color(argb: 0xFF111512),
                separator: Color(argb: 0xFF263029), foreground: Color(argb: 0xFFD7E0DB),
                subtle: Color(argb: 0xFFB8C4BE), muted: Color(argb: 0xFF68736D),
                accent: Color(argb: 0xFF57E389), error: Color(argb: 0xFFFF6B62),
                disabled: Color(argb: 0xFF4A544F)
            )
        }
    }
}
