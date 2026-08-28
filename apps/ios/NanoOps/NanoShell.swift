import SwiftUI

/// Navigation destinations of the main shell. Shared by the phone tab tags and
/// the iPad sidebar so both read from one definition. Raw values keep the
/// original tab order.
enum ShellSection: Int, CaseIterable, Hashable, Identifiable {
    case overview, nodes, terminal, activity, settings

    var id: Int { rawValue }

    var titleKey: String {
        switch self {
        case .overview: return "nav.overview"
        case .nodes: return "nav.nodes"
        case .terminal: return "nav.terminal"
        case .activity: return "nav.activity"
        case .settings: return "nav.settings"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .nodes: return "server.rack"
        case .terminal: return "terminal"
        case .activity: return "bell"
        case .settings: return "gearshape"
        }
    }
}

/// Main shell. On compact width it ports `nano_shell.dart`'s 5-destination bottom
/// tab bar, each tab hosting its own `NavigationStack`. On regular width it is a
/// `NavigationSplitView` whose Nodes section is a persistent list/detail
/// workspace rather than a pushed stack.
struct NanoShell: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var l10n: L10n
    @Environment(\.nano) private var t
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var router: ShellRouter

    private var section: ShellSection { router.section }

    var body: some View {
        Group {
            if t.desktop {
                desktopShell
            } else if horizontalSizeClass == .regular {
                iPadShell
            } else {
                phoneShell
            }
        }
        .id(l10n.language)
        .tint(t.accent)
        .sheet(isPresented: $router.showServerSwitch) { ServerSwitchSheet() }
        .onChange(of: store.activeServerIdRaw) { _ in router.clearSelection() }
        .onChange(of: router.refreshTick) { _ in
            Task { @MainActor in await refreshServerData() }
        }
    }

    /// Backing for the ⌘R menu command: reconnect dropped sessions and refetch
    /// the server-sourced lists the screens read straight off the store.
    private func refreshServerData() async {
        store.applicationDidBecomeActive()
        await store.fetchRecentActivity()
        await store.fetchServerAlerts()
    }

    private var phoneShell: some View {
        TabView(selection: $router.section) {
            NavigationStack { DashboardScreen() }
                .tabItem { Label(tr("nav.overview"), systemImage: ShellSection.overview.icon) }
                .tag(ShellSection.overview)

            NavigationStack { AgentsScreen(initialFilter: router.nodesFilter) }
                .id(router.nodesFilter)
                .tabItem { Label(tr("nav.nodes"), systemImage: ShellSection.nodes.icon) }
                .tag(ShellSection.nodes)

            NavigationStack { TerminalScreen() }
                .tabItem { Label(tr("nav.terminal"), systemImage: ShellSection.terminal.icon) }
                .tag(ShellSection.terminal)

            NavigationStack { AlertsScreen() }
                .tabItem { Label(tr("nav.activity"), systemImage: ShellSection.activity.icon) }
                .tag(ShellSection.activity)
                .badge(alertBadge)

            NavigationStack { SettingsScreen() }
                .tabItem { Label(tr("nav.settings"), systemImage: ShellSection.settings.icon) }
                .tag(ShellSection.settings)
        }
    }

    /// Mac window: a persistent source list plus a real window toolbar, instead of
    /// the phone tab bar. Sections carry the window title, so the screens drop
    /// their inline large titles and the toolbar owns the global actions.
    private var desktopShell: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section(tr("menu.view")) {
                    ForEach(ShellSection.allCases) { item in
                        desktopSidebarRow(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle(tr("app.title"))
            .navigationBarTitleDisplayMode(.inline)
        } detail: {
            NavigationStack {
                selectedScreen
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .navigationTitle(tr(section.titleKey))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { desktopToolbar }
            }
            .id(section)
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// Binding that keeps `List` selection and the router's section in step.
    private var sidebarSelection: Binding<ShellSection?> {
        Binding(get: { router.section }, set: { newValue in
            if let newValue { router.show(newValue) }
        })
    }

    private func desktopSidebarRow(_ item: ShellSection) -> some View {
        let badge = item == .activity ? alertBadge : 0
        return Label(tr(item.titleKey), systemImage: item.icon)
            .badge(badge > 0 ? Text("\(badge)") : nil)
            .tag(item)
    }

    @ToolbarContentBuilder
    private var desktopToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { router.requestRefresh() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(NanoToolbarButtonStyle())
            .accessibilityLabel(tr("menu.refresh"))
            .help(tr("menu.refresh"))

            Button { router.showServerSwitch = true } label: {
                Image(systemName: "server.rack")
            }
            .buttonStyle(NanoToolbarButtonStyle())
            .accessibilityLabel(tr("agents.switchServer"))
            .help(tr("agents.switchServer"))
        }
    }

    private var iPadShell: some View {
        NavigationSplitView {
            List {
                ForEach(ShellSection.allCases) { item in sidebarRow(item) }
            }
            .navigationTitle(tr("app.title"))
            .listStyle(.sidebar)
        } detail: {
            NavigationStack {
                selectedScreen
                    .frame(maxWidth: section == .nodes ? .infinity : 1_200, maxHeight: .infinity)
                    .frame(maxWidth: .infinity)
            }
            .id(section)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var selectedScreen: some View {
        switch section {
        case .overview:
            DashboardScreen(onSelectAgent: { agent in
                router.select(agentID: agent.id)
            })
        case .nodes:
            AgentsWorkspaceScreen(selectedAgentID: $router.selectedAgentID,
                                  filter: $router.nodesFilter)
        case .terminal: TerminalScreen()
        case .activity: AlertsScreen()
        case .settings: SettingsScreen()
        }
    }

    private func sidebarRow(_ item: ShellSection) -> some View {
        let badge = item == .activity ? alertBadge : 0
        return Button { router.show(item) } label: {
            HStack {
                Label(tr(item.titleKey), systemImage: item.icon)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(t.crit, in: Capsule())
                }
            }
            .foregroundColor(section == item ? t.accent : t.fg2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(section == item ? t.accent.opacity(0.12) : Color.clear)
    }

    /// Unacknowledged alert count for the active server, surfaced on the tab.
    private var alertBadge: Int {
        store.unackedAlertCount(store.activeServerId)
    }
}
