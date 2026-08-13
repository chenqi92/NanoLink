import SwiftUI

/// Pure selection resolution shared by the shell and the workspace: an ID that
/// no longer belongs to the visible node set collapses to `nil` instead of
/// keeping a stale detail pane on screen.
enum AgentSelection {
    static func resolve(_ id: String?, in agents: [Agent]) -> String? {
        guard let id, agents.contains(where: { $0.id == id }) else { return nil }
        return id
    }
}

/// Regular-width (iPad) node workspace: a persistent list pane on the left with
/// the selected node's detail rendered in place instead of pushed onto a stack.
struct AgentsWorkspaceScreen: View {
    @Binding var selectedAgentID: String?
    var initialFilter: String? = nil

    @EnvironmentObject private var store: AppStore
    @Environment(\.nano) private var t
    @State private var query = ""
    @State private var filter: String
    @State private var showServerSwitch = false

    init(selectedAgentID: Binding<String?>, initialFilter: String? = nil) {
        _selectedAgentID = selectedAgentID
        self.initialFilter = initialFilter
        _filter = State(initialValue: initialFilter ?? "all")
    }

    private var resolvedID: String? {
        AgentSelection.resolve(selectedAgentID, in: store.agentsForServer())
    }

    private var selectedAgent: Agent? {
        resolvedID.flatMap { store.agentById($0) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                AgentListPane(query: $query, filter: $filter, compact: true,
                              selectedAgentID: resolvedID) { selectedAgentID = $0.id }
            }
            .padding(.horizontal, 12)
            .frame(width: 340)

            Rectangle().fill(t.sep2).frame(width: 0.5)

            Group {
                if let agent = selectedAgent {
                    AgentDetailScreen(agent: agent, showsBackButton: false).id(agent.id)
                } else {
                    placeholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(t.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .sheet(isPresented: $showServerSwitch) { ServerSwitchSheet() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(tr("agents.title"))
                .font(.system(size: 24, weight: t.displayWeight))
                .tracking(t.displayTracking).foregroundColor(t.fg)
            Spacer()
            Button { showServerSwitch = true } label: {
                Image(systemName: "server.rack").font(.system(size: 15)).foregroundColor(t.accent)
                    .frame(width: 32, height: 32).background(t.card).clipShape(Circle())
            }.buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    private var placeholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.tap").font(.system(size: 30)).foregroundColor(t.fg4)
            Text(tr("agents.selectNode")).font(.system(size: 13.5)).foregroundColor(t.fg4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
