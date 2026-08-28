import SwiftUI

/// App entry point. Owns the global stores and injects the resolved design
/// tokens and localization into the whole view tree.
@main
struct NanoOpsApp: App {
    @StateObject private var store = AppStore.shared
    @StateObject private var theme = ThemeStore.shared
    @StateObject private var l10n = L10n.shared
    @StateObject private var appLock = AppLockStore.shared
    @StateObject private var router = ShellRouter.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NanoThemeProvider(theme: theme) {
                Group {
                    if appLock.isLocked { AppLockScreen() }
                    else { RootView() }
                }
            }
            .environmentObject(store)
            .environmentObject(theme)
            .environmentObject(l10n)
            .environmentObject(appLock)
            .environmentObject(router)
            .preferredColorScheme(theme.preferredColorScheme)
            .task { await store.start() }
            .onChange(of: scenePhase) { phase in
                switch phase {
                case .active:
                    store.applicationDidBecomeActive()
                    appLock.sceneDidBecomeActive()
                case .background:
                    appLock.sceneDidEnterBackground()
                default:
                    break
                }
            }
        }
        .commands { NanoShellCommands(router: router, l10n: l10n) }
    }
}
