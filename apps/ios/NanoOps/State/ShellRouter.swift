import Combine

/// Shell navigation state hoisted out of `NanoShell`'s `@State` so scene-level
/// menu commands can drive the same section and node selection the shell
/// renders. `NanoShellCommands` mutates this object; `NanoShell` observes it.
///
/// Deliberately not `@MainActor`-isolated: SwiftUI `Commands` bodies carry no
/// actor annotation, so the menu actions must be callable from a plain
/// synchronous context. All mutations happen on the main thread in practice
/// because both the menus and the shell run there.
final class ShellRouter: ObservableObject {
    static let shared = ShellRouter()

    @Published var section: ShellSection = .overview
    @Published var selectedAgentID: String?
    @Published var nodesFilter = "all"

    /// Bumped by the Refresh command. The shell reloads server-sourced data on
    /// change instead of every screen wiring its own command handler.
    @Published private(set) var refreshTick = 0

    /// Set by the Switch Server command; the shell presents the sheet.
    @Published var showServerSwitch = false

    /// The app injects `shared`; tests build throwaway instances.
    init() {}

    func show(_ section: ShellSection) {
        self.section = section
    }

    /// Opens the node workspace with an explicit inventory filter. Dashboard
    /// summaries use this instead of pushing a second phone-style node screen
    /// into the current navigation stack.
    func showNodes(filter: String = "all") {
        nodesFilter = filter
        selectedAgentID = nil
        section = .nodes
    }

    /// Selecting a node also lands on the Nodes section, matching what a
    /// dashboard row tap does on regular width.
    func select(agentID: String?) {
        selectedAgentID = agentID
        if agentID != nil {
            nodesFilter = "all"
            section = .nodes
        }
    }

    func clearSelection() {
        selectedAgentID = nil
    }

    func requestRefresh() {
        refreshTick += 1
    }
}
