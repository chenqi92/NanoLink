import SwiftUI
import UIKit

/// Environment plumbing for the NanoLink design tokens.
///
/// A root view resolves `NanoTokens` from the `ThemeStore` (style + mode) and the
/// system color scheme, then injects them via `.nanoTheme(...)`. Descendant views
/// read the tokens through `@Environment(\.nano)`.
private struct NanoTokensKey: EnvironmentKey {
    static let defaultValue: NanoTokens = .iosDark
}

private struct NanoCompactKey: EnvironmentKey {
    static let defaultValue = false
}

/// True when running in the macOS idiom (Catalyst "Optimize Interface for Mac").
/// Screens read this to swap phone chrome — inline large titles, floating action
/// buttons, a bottom tab bar — for window-native equivalents.
enum NanoIdiom {
    static let isDesktop: Bool = {
        #if targetEnvironment(macCatalyst)
        return UIDevice.current.userInterfaceIdiom == .mac
        #else
        return false
        #endif
    }()
}

extension EnvironmentValues {
    var nano: NanoTokens {
        get { self[NanoTokensKey.self] }
        set { self[NanoTokensKey.self] = newValue }
    }

    var nanoCompact: Bool {
        get { self[NanoCompactKey.self] }
        set { self[NanoCompactKey.self] = newValue }
    }
}

extension View {
    /// Inject a resolved `NanoTokens` palette into the environment.
    func nanoTheme(_ tokens: NanoTokens) -> some View {
        environment(\.nano, tokens)
    }

    /// Pull-to-refresh, applied only where the platform supports it. The Mac
    /// idiom has no `UIRefreshControl`, so attaching `.refreshable` there both
    /// looks wrong and offers no way to trigger it with a pointer; those windows
    /// refresh from the toolbar and the ⌘R menu command instead.
    @ViewBuilder
    func nanoPullToRefresh(enabled: Bool, action: @escaping @Sendable () async -> Void) -> some View {
        if enabled { refreshable(action: action) } else { self }
    }

    /// Bottom-trailing floating action button, applied only on touch layouts.
    /// Desktop windows surface the same action in the toolbar.
    @ViewBuilder
    func nanoFloatingAction<Action: View>(enabled: Bool,
                                         @ViewBuilder action: () -> Action) -> some View {
        if enabled {
            safeAreaInset(edge: .bottom, alignment: .trailing) { action() }
        } else {
            self
        }
    }

    /// Hide the navigation bar on touch layouts, where these screens draw their own
    /// inline title. A Mac window needs the bar to keep its title and toolbar.
    func nanoNavigationBarHidden(_ hidden: Bool) -> some View {
        navigationBarHidden(hidden)
    }
}

/// Wraps content and keeps the injected tokens in sync with `ThemeStore`
/// (style + mode) and the current system color scheme. Also paints the page
/// background and drives the light/dark override for the whole subtree.
struct NanoThemeProvider<Content: View>: View {
    @ObservedObject var theme: ThemeStore
    @Environment(\.colorScheme) private var systemScheme
    private let content: () -> Content

    init(theme: ThemeStore, @ViewBuilder content: @escaping () -> Content) {
        self.theme = theme
        self.content = content
    }

    private var tokens: NanoTokens {
        NanoTokens.resolve(theme.style, theme.isDark(systemScheme), desktop: NanoIdiom.isDesktop)
    }

    var body: some View {
        let t = tokens
        return content()
            .nanoTheme(t)
            .environment(\.nanoCompact, theme.compact)
            .environment(\.defaultMinListRowHeight, theme.compact ? 36 : 44)
            .controlSize(theme.compact ? .small : .regular)
            .tint(t.accent)
            .background(t.bg.ignoresSafeArea())
    }
}
