import SwiftUI
import UIKit

/// Account, server, tool, appearance, terminal, notification, security and app
/// metadata settings.
struct SettingsScreen: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var l10n: L10n
    @EnvironmentObject private var appLock: AppLockStore
    @Environment(\.nano) private var t
    @Environment(\.openURL) private var openURL

    @AppStorage(AppPreferenceKey.notifyAudit) private var notifyAudit = false
    @AppStorage(AppPreferenceKey.terminalTheme) private var terminalTheme = "phosphor"
    @AppStorage(AppPreferenceKey.terminalFontSize) private var terminalFontSize = 13
    @AppStorage(AppPreferenceKey.terminalCursor) private var terminalCursor = "block"
    @AppStorage(AppPreferenceKey.terminalCursorBlink) private var terminalCursorBlink = true
    @AppStorage(AppPreferenceKey.faceId) private var faceId = false
    @AppStorage(AppPreferenceKey.autoLock) private var autoLock = 2

    @State private var picker: SettingsPicker?
    @State private var confirmation: SettingsConfirmation?
    @State private var notice: String?
    @State private var noticeTask: Task<Void, Never>?

    private let terminalThemes = ["phosphor", "amber", "mono", "solarized"]
    private let terminalCursors = ["block", "bar", "underline"]
    private let terminalFontSizes = [11, 12, 13, 14, 15, 16]
    private let autoLockOptions = [0, 1, 2, 5, 10]

    private var loggedIn: Bool { store.servers.contains(where: \.hasFullPermissions) }
    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v\(version.flatMap { $0.isEmpty ? nil : $0 } ?? "0.0.0")"
    }

    private var pairingServerId: String? {
        if let active = store.activeServer, active.hasFullPermissions { return active.id }
        return store.servers.first(where: \.hasFullPermissions)?.id
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let notice { noticeBanner(notice) }
                accountCard
                serversSection
                toolsSection
                appearanceSection
                terminalSection
                notificationsSection
                securitySection
                aboutSection
                if loggedIn { logoutSection }
                NanoMono(tr("settings.footer", ["version": appVersion]), size: 11, color: t.fg4)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
            }
            .padding(EdgeInsets(top: 8, leading: 16,
                                bottom: t.desktop ? 24 : 96, trailing: 16))
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(t.bg.ignoresSafeArea())
        .navigationTitle(tr("settings.title"))
        .navigationBarTitleDisplayMode(t.desktop ? .inline : .large)
        .sheet(item: $picker) { selection in
            SettingsPickerSheet(title: pickerTitle(selection), options: pickerOptions(selection))
        }
        .alert(item: $confirmation) { action in confirmationAlert(action) }
        .onDisappear { noticeTask?.cancel() }
    }

    private var accountCard: some View {
        NanoCard {
            NanoListRow(divider: false) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(loggedIn ? tr("settings.loggedIn") : tr("settings.notLoggedIn"))
                        .font(.system(size: 16, weight: .semibold)).foregroundColor(t.fg)
                    Text(loggedIn ? tr("settings.loggedInSub") : tr("settings.notLoggedInSub"))
                        .font(.system(size: 12.5)).foregroundColor(t.fg3)
                }
            } leading: {
                ZStack {
                    LinearGradient(colors: [t.accent, t.tertiary], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "person.fill").font(.system(size: 21)).foregroundColor(.white)
                }
                .frame(width: 48, height: 48).clipShape(Circle())
            }
        }
    }

    private var serversSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            NanoSectionLabel(tr("settings.servers", ["n": store.servers.count]), grouped: true)
            NanoCard {
                ForEach(Array(store.servers.enumerated()), id: \.element.id) { index, server in
                    NavigationLink { ServerDetailScreen(serverId: server.id) } label: {
                        NanoListRow(divider: index < store.servers.count) {
                            HStack(spacing: 6) {
                                Text(server.name).font(.system(size: 15, weight: .medium)).foregroundColor(t.fg).lineLimit(1)
                                if server.id == store.activeServerId {
                                    NanoBadge(text: tr("settings.current"), color: t.info)
                                }
                            }
                        } leading: {
                            NanoIconBox(icon: "server.rack")
                        } trailing: {
                            HStack(spacing: 8) {
                                Text(tr("settings.nodeCount", ["n": store.agentsForServer(server.id).count]))
                                    .font(.system(size: 11.5)).foregroundColor(t.fg4)
                                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(t.fg4)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink { AddServerScreen() } label: {
                    NanoListRow(divider: false) {
                        Text(tr("settings.addNewServer"))
                            .font(.system(size: 15, weight: .medium)).foregroundColor(t.accent)
                    } leading: {
                        NanoIconBox(icon: "plus", bg: t.accent.opacity(0.14), fg: t.accent)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            NanoSectionLabel(tr("settings.tools"), grouped: true)
            NanoCard {
                NavigationLink { AssistantScreen() } label: {
                    NanoListRow {
                        Text(tr("settings.aiAssistant")).font(.system(size: 15)).foregroundColor(t.fg)
                    } leading: {
                        NanoIconBox(
                            icon: "sparkles", size: 30, iconSize: 15,
                            gradient: LinearGradient(colors: [t.accent, t.tertiary], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    } trailing: {
                        HStack(spacing: 8) {
                            NanoBadge(text: "MCP")
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(t.fg4)
                        }
                    }
                }
                .buttonStyle(.plain)

                if let pairingServerId {
                    NavigationLink { DevicePairingScreen(serverId: pairingServerId) } label: {
                        pairingRow
                    }
                    .buttonStyle(.plain)
                } else {
                    NanoListRow(divider: false, onTap: { showNotice(tr("settings.pairNeedsLogin")) }) {
                        Text(tr("settings.pairDevice")).font(.system(size: 15)).foregroundColor(t.fg)
                    } leading: {
                        NanoIconBox(icon: "qrcode", size: 30, iconSize: 16, fg: t.accent)
                    } trailing: {
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(t.fg4)
                    }
                }
            }
        }
    }

    private var pairingRow: some View {
        NanoListRow(divider: false) {
            Text(tr("settings.pairDevice")).font(.system(size: 15)).foregroundColor(t.fg)
        } leading: {
            NanoIconBox(icon: "qrcode", size: 30, iconSize: 16, fg: t.accent)
        } trailing: {
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(t.fg4)
        }
    }

    private var appearanceSection: some View {
        settingsSection(tr("settings.appearance")) {
            settingsRow(tr("settings.theme"), value: themeLabel(theme.mode)) { picker = .theme }
            settingsRow(tr("settings.language"), value: l10n.language == "zh" ? tr("settings.langChinese") : tr("settings.langEnglish")) {
                picker = .language
            }
            toggleRow(tr("settings.compactMode"), value: Binding(
                get: { theme.compact },
                set: { theme.compact = $0 }
            ), divider: false)
        }
    }

    private var terminalSection: some View {
        settingsSection(tr("settings.terminal")) {
            settingsRow(tr("settings.termTheme"), value: tr("settings.termTheme_\(terminalTheme)")) { picker = .terminalTheme }
            settingsRow(tr("settings.termFontSize"), value: tr("settings.ptValue", ["n": terminalFontSize])) { picker = .terminalFontSize }
            settingsRow(tr("settings.termCursor"), value: tr("settings.termCursor_\(terminalCursor)")) { picker = .terminalCursor }
            toggleRow(tr("settings.termBlink"), value: $terminalCursorBlink, divider: false)
        }
    }

    private var notificationsSection: some View {
        settingsSection(tr("settings.notifications")) {
            toggleRow(tr("settings.notifyOffline"), value: Binding(
                get: { store.notifyOffline },
                set: { store.setNotifyPref("notify_offline", $0) }
            ))
            toggleRow(tr("settings.notifyHigh"), value: Binding(
                get: { store.notifyHigh },
                set: { store.setNotifyPref("notify_high", $0) }
            ))
            toggleRow(tr("settings.notifyDisk"), value: Binding(
                get: { store.notifyDisk },
                set: { store.setNotifyPref("notify_disk", $0) }
            ))
            toggleRow(tr("settings.notifyAudit"), value: Binding(
                get: { notifyAudit },
                set: {
                    notifyAudit = $0
                    store.setAuditNotifications($0)
                    if $0 { showNotice(tr("settings.notifyAuditNote")) }
                }
            ), divider: false)
        }
    }

    private var securitySection: some View {
        settingsSection(tr("settings.security")) {
            toggleRow(tr("settings.faceId"), value: Binding(
                get: { faceId },
                set: { enabled in
                    if enabled {
                        Task {
                            let authorized = await appLock.authorizeProtection()
                            faceId = authorized
                            showNotice(authorized ? tr("settings.faceIdNote") : (appLock.errorMessage ?? tr("security.unavailable")))
                        }
                    } else {
                        faceId = false
                        appLock.disableProtection()
                    }
                }
            ))
            settingsRow(tr("settings.autoLock"), value: autoLockLabel(autoLock)) { picker = .autoLock }
            NanoListRow(divider: false, onTap: { confirmation = .clearTokens }) {
                Text(tr("settings.clearTokens"))
                    .font(.system(size: 15, weight: .medium)).foregroundColor(t.crit)
            }
        }
    }

    private var aboutSection: some View {
        settingsSection(tr("settings.about")) {
            settingsRow(tr("settings.version"), value: appVersion) {
                copy(appVersion, notice: tr("settings.copied"))
            }
            settingsRow(tr("settings.sourceCodeLabel"), value: "github.com/chenqi92/NanoLink") {
                open("https://github.com/chenqi92/NanoLink")
            }
            settingsRow(tr("settings.docsHelp")) {
                open("https://github.com/chenqi92/NanoLink#readme")
            }
            settingsRow(tr("settings.privacyPolicy")) {
                open("https://github.com/chenqi92/NanoLink/blob/main/PRIVACY.md")
            }
            settingsRow(tr("settings.sendFeedback"), divider: false) {
                open("https://github.com/chenqi92/NanoLink/issues/new/choose")
            }
        }
    }

    private var logoutSection: some View {
        NanoCard {
            NanoListRow(divider: false, onTap: { confirmation = .logout }) {
                Text(tr("settings.logout"))
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(t.crit)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.top, 16)
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NanoSectionLabel(title, grouped: true)
            NanoCard { content() }
        }
    }

    private func settingsRow(_ label: String, value: String? = nil, divider: Bool = true,
                             action: (() -> Void)? = nil) -> some View {
        NanoListRow(divider: divider, onTap: action) {
            Text(label).font(.system(size: 15)).foregroundColor(t.fg)
        } trailing: {
            HStack(spacing: 6) {
                if let value {
                    Text(value).font(.system(size: 14)).foregroundColor(t.fg3)
                        .lineLimit(1).frame(maxWidth: 190, alignment: .trailing)
                }
                if action != nil {
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(t.fg4)
                }
            }
        }
    }

    private func toggleRow(_ label: String, value: Binding<Bool>, divider: Bool = true) -> some View {
        NanoListRow(divider: divider) {
            Text(label).font(.system(size: 15)).foregroundColor(t.fg)
        } trailing: {
            Toggle("", isOn: value).labelsHidden().tint(t.ok)
        }
    }

    private func noticeBanner(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(.system(size: 12.5, weight: .medium)).foregroundColor(t.fg2)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(t.ok.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.bottom, 10)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func themeLabel(_ mode: AppThemeMode) -> String {
        switch mode {
        case .light: return tr("settings.themeLight")
        case .dark: return tr("settings.themeDark")
        case .system: return tr("settings.themeSystem")
        }
    }

    private func autoLockLabel(_ minutes: Int) -> String {
        minutes <= 0 ? tr("settings.autoLockOff") : tr("settings.minutesValue", ["n": minutes])
    }

    private func pickerTitle(_ selection: SettingsPicker) -> String {
        switch selection {
        case .theme: return tr("settings.theme")
        case .language: return tr("settings.language")
        case .terminalTheme: return tr("settings.termTheme")
        case .terminalFontSize: return tr("settings.termFontSize")
        case .terminalCursor: return tr("settings.termCursor")
        case .autoLock: return tr("settings.autoLock")
        }
    }

    private func pickerOptions(_ selection: SettingsPicker) -> [SettingsPickerOption] {
        switch selection {
        case .theme:
            return AppThemeMode.allCases.map { mode in
                SettingsPickerOption(id: "theme-\(mode.rawValue)", label: themeLabel(mode), selected: theme.mode == mode) {
                    theme.mode = mode
                }
            }
        case .language:
            return ["zh", "en"].map { language in
                SettingsPickerOption(
                    id: "language-\(language)",
                    label: language == "zh" ? tr("settings.langChinese") : tr("settings.langEnglish"),
                    selected: l10n.language == language
                ) { l10n.setLanguage(language) }
            }
        case .terminalTheme:
            return terminalThemes.map { id in
                SettingsPickerOption(id: "terminal-theme-\(id)", label: tr("settings.termTheme_\(id)"), selected: terminalTheme == id) {
                    terminalTheme = id
                }
            }
        case .terminalFontSize:
            return terminalFontSizes.map { size in
                SettingsPickerOption(id: "terminal-size-\(size)", label: tr("settings.ptValue", ["n": size]), selected: terminalFontSize == size) {
                    terminalFontSize = size
                }
            }
        case .terminalCursor:
            return terminalCursors.map { id in
                SettingsPickerOption(id: "terminal-cursor-\(id)", label: tr("settings.termCursor_\(id)"), selected: terminalCursor == id) {
                    terminalCursor = id
                }
            }
        case .autoLock:
            return autoLockOptions.map { minutes in
                SettingsPickerOption(id: "auto-lock-\(minutes)", label: autoLockLabel(minutes), selected: autoLock == minutes) {
                    autoLock = minutes
                }
            }
        }
    }

    private func confirmationAlert(_ action: SettingsConfirmation) -> Alert {
        switch action {
        case .clearTokens:
            return Alert(
                title: Text(tr("settings.clearTokens")),
                message: Text(tr("settings.clearTokensConfirm")),
                primaryButton: .cancel(Text(tr("common.cancel"))),
                secondaryButton: .destructive(Text(tr("settings.clearTokensConfirmAction"))) {
                    let ids = store.servers.map(\.id)
                    ids.forEach(store.removeServer)
                    showNotice(tr("settings.clearTokensDone"))
                }
            )
        case .logout:
            return Alert(
                title: Text(tr("settings.logout")),
                message: Text(tr("settings.logoutConfirm")),
                primaryButton: .cancel(Text(tr("common.cancel"))),
                secondaryButton: .destructive(Text(tr("settings.logout"))) {
                    let ids = store.servers.filter(\.hasFullPermissions).map(\.id)
                    ids.forEach(store.removeServer)
                    showNotice(tr("settings.logoutDone"))
                }
            )
        }
    }

    private func copy(_ value: String, notice: String) {
        UIPasteboard.general.string = value
        showNotice(notice)
    }

    private func open(_ value: String) {
        guard let url = URL(string: value) else { return }
        openURL(url)
    }

    private func showNotice(_ message: String) {
        noticeTask?.cancel()
        withAnimation { notice = message }
        noticeTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation { notice = nil } }
        }
    }
}

private enum SettingsPicker: String, Identifiable {
    case theme, language, terminalTheme, terminalFontSize, terminalCursor, autoLock
    var id: String { rawValue }
}

private enum SettingsConfirmation: String, Identifiable {
    case clearTokens, logout
    var id: String { rawValue }
}

private struct SettingsPickerOption: Identifiable {
    let id: String
    let label: String
    let selected: Bool
    let action: () -> Void
}

private struct SettingsPickerSheet: View {
    let title: String
    let options: [SettingsPickerOption]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nano) private var t

    var body: some View {
        NavigationStack {
            ScrollView {
                NanoCard {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        NanoListRow(divider: index < options.count - 1, onTap: {
                            option.action()
                            dismiss()
                        }) {
                            Text(option.label).font(.system(size: 15)).foregroundColor(t.fg)
                        } trailing: {
                            if option.selected {
                                Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundColor(t.accent)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(t.bg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("common.cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
