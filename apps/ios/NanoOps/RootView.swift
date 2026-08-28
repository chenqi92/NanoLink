import SwiftUI

/// Top-level router. Ports the routing decision in `main.dart`:
/// while the initial load runs → spinner; no servers → the welcome/onboarding
/// flow; otherwise → the main tab shell.
struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var l10n: L10n
    @Environment(\.nano) private var t

    var body: some View {
        Group {
            if store.isLoading && store.servers.isEmpty {
                loadingView
            } else if store.servers.isEmpty {
                ServerWelcomeScreen()
            } else {
                NanoShell()
            }
        }
        .id(l10n.language)
        .animation(.easeInOut(duration: 0.25), value: store.servers.isEmpty)
        .animation(.easeInOut(duration: 0.25), value: store.isLoading)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text(tr("home.connectingToServers"))
                .font(.system(size: 13))
                .foregroundColor(t.fg3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.bg)
    }
}
