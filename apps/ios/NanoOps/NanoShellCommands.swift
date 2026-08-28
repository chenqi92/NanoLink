import SwiftUI

/// Scene-level menu commands. On a Mac window (Catalyst) these appear as real
/// menu-bar items under a "View" menu; on iPad the same declarations register
/// the shortcuts for a hardware keyboard and the ⌘-hold shortcut overlay.
///
/// Actions go through `ShellRouter` only — no `@MainActor` type is touched here,
/// because `Commands` bodies are not actor-annotated.
struct NanoShellCommands: Commands {
    @ObservedObject var router: ShellRouter
    /// Observed so menu titles rebuild when the in-app language changes.
    @ObservedObject var l10n: L10n

    var body: some Commands {
        CommandMenu(tr("menu.view")) {
            ForEach(ShellSection.allCases) { section in
                Button(tr(section.titleKey)) { router.show(section) }
                    .keyboardShortcut(shortcut(for: section), modifiers: .command)
            }

            Divider()

            Button(tr("menu.refresh")) { router.requestRefresh() }
                .keyboardShortcut("r", modifiers: .command)
            Button(tr("agents.switchServer")) { router.showServerSwitch = true }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }
    }

    /// ⌘1–⌘5 in sidebar/tab order.
    private func shortcut(for section: ShellSection) -> KeyEquivalent {
        switch section {
        case .overview: return "1"
        case .nodes: return "2"
        case .terminal: return "3"
        case .activity: return "4"
        case .settings: return "5"
        }
    }
}
