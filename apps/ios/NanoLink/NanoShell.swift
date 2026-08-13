import SwiftUI

/// Main tab shell (iOS bottom tab bar). Ports `nano_shell.dart`'s 5 navigation
/// destinations: overview / nodes / terminal / activity / settings. Each tab
/// hosts its own `NavigationStack` so detail screens push independently.
struct NanoShell: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var l10n: L10n
    @Environment(\.nano) private var t
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selection: Int = 0

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadShell
            } else {
                phoneShell
            }
        }
        .id(l10n.language)
        .tint(t.accent)
    }

    private var phoneShell: some View {
        TabView(selection: $selection) {
            NavigationStack { DashboardScreen() }
                .tabItem { Label(tr("nav.overview"), systemImage: "square.grid.2x2") }
                .tag(0)

            NavigationStack { AgentsScreen() }
                .tabItem { Label(tr("nav.nodes"), systemImage: "server.rack") }
                .tag(1)

            NavigationStack { TerminalScreen() }
                .tabItem { Label(tr("nav.terminal"), systemImage: "terminal") }
                .tag(2)

            NavigationStack { AlertsScreen() }
                .tabItem { Label(tr("nav.activity"), systemImage: "bell") }
                .tag(3)
                .badge(alertBadge)

            NavigationStack { SettingsScreen() }
                .tabItem { Label(tr("nav.settings"), systemImage: "gearshape") }
                .tag(4)
        }
    }

    private var iPadShell: some View {
        NavigationSplitView {
            List {
                sidebarRow(tr("nav.overview"), icon: "square.grid.2x2", tag: 0)
                sidebarRow(tr("nav.nodes"), icon: "server.rack", tag: 1)
                sidebarRow(tr("nav.terminal"), icon: "terminal", tag: 2)
                sidebarRow(tr("nav.activity"), icon: "bell", tag: 3, badge: alertBadge)
                sidebarRow(tr("nav.settings"), icon: "gearshape", tag: 4)
            }
            .navigationTitle(tr("app.title"))
            .listStyle(.sidebar)
        } detail: {
            NavigationStack {
                selectedScreen
                    .frame(maxWidth: 1_200, maxHeight: .infinity)
                    .frame(maxWidth: .infinity)
            }
            .id(selection)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var selectedScreen: some View {
        switch selection {
        case 1: AgentsScreen()
        case 2: TerminalScreen()
        case 3: AlertsScreen()
        case 4: SettingsScreen()
        default: DashboardScreen()
        }
    }

    private func sidebarRow(_ title: String, icon: String, tag: Int, badge: Int = 0) -> some View {
        Button { selection = tag } label: {
            HStack {
                Label(title, systemImage: icon)
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
            .foregroundColor(selection == tag ? t.accent : t.fg2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(selection == tag ? t.accent.opacity(0.12) : Color.clear)
    }

    /// Unacknowledged alert count for the active server, surfaced on the tab.
    private var alertBadge: Int {
        store.unackedAlertCount(store.activeServerId)
    }
}
