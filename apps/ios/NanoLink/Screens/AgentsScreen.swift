import SwiftUI

/// Phone node inventory: header plus the shared `AgentListPane`, with detail
/// pushed onto the enclosing navigation stack. Can also be pushed with an
/// initial offline/warning filter.
struct AgentsScreen: View {
    var initialFilter: String? = nil
    var initialQuery: String? = nil

    @Environment(\.nano) private var t
    @State private var query: String
    @State private var filter: String
    @State private var showServerSwitch = false

    init(initialFilter: String? = nil, initialQuery: String? = nil) {
        self.initialFilter = initialFilter
        self.initialQuery = initialQuery
        _query = State(initialValue: initialQuery ?? "")
        _filter = State(initialValue: initialFilter ?? "all")
    }

    var body: some View {
        VStack(spacing: 0) {
            if !t.desktop { header }
            AgentListPane(query: $query, filter: $filter)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
        .background(t.bg.ignoresSafeArea())
        .nanoNavigationBarHidden(!t.desktop)
        .navigationDestination(for: AgentRoute.self) { AgentDetailScreen(agent: $0.agent) }
        .sheet(isPresented: $showServerSwitch) { ServerSwitchSheet() }
        .nanoFloatingAction(enabled: !t.desktop) {
            Button { showServerSwitch = true } label: {
                Label(tr("agents.switchServer"), systemImage: "server.rack")
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(t.onAccent)
                    .padding(.horizontal, 17).frame(height: 46).background(t.accent).clipShape(Capsule())
            }
            .buttonStyle(.plain).padding(.trailing, 2).padding(.bottom, 4)
        }
    }

    private var header: some View {
        HStack {
            Text(tr("agents.title"))
                .font(.system(size: t.titleSize, weight: t.displayWeight))
                .tracking(t.displayTracking).foregroundColor(t.fg)
            Spacer()
            Image(systemName: filter == "all" ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 19)).foregroundColor(filter == "all" ? t.fg2 : t.accent)
        }
        .padding(.top, t.isIOS ? 40 : 8)
    }
}
