import SwiftUI

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
        NanoTokens.resolve(theme.style, theme.isDark(systemScheme))
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
