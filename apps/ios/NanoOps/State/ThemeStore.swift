import Foundation
import SwiftUI
import Combine

/// App theme mode persisted as an integer under `theme_mode`
/// (0=light, 1=dark, 2=system); default system, so a fresh install follows the
/// OS appearance instead of pinning dark.
enum AppThemeMode: Int, CaseIterable {
    case light = 0
    case dark = 1
    case system = 2
}

/// Visual style dimension of the NanoTokens design system.
enum ThemeStyle: String { case ios, md }

/// Observable theme state driving light/dark palettes and the iOS/MD style axis.
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published var mode: AppThemeMode {
        didSet { PreferencesStore.themeMode = String(mode.rawValue) }
    }
    @Published var style: ThemeStyle {
        didSet { PreferencesStore.themeStyle = style.rawValue }
    }
    @Published var compact: Bool {
        didSet { UserDefaults.standard.set(compact, forKey: "ui_compact") }
    }

    private init() {
        let raw = Int(PreferencesStore.themeMode) ?? AppThemeMode.system.rawValue
        mode = AppThemeMode(rawValue: min(max(raw, 0), 2)) ?? .system
        style = ThemeStyle(rawValue: PreferencesStore.themeStyle) ?? .ios
        let defaults = UserDefaults.standard
        if let value = defaults.object(forKey: "ui_compact") as? Bool {
            compact = value
        } else {
            // Migrate the pre-native key once so existing installations retain
            // their density preference while all new writes use the shared key.
            compact = defaults.object(forKey: "compact_mode") as? Bool ?? false
            defaults.set(compact, forKey: "ui_compact")
            defaults.removeObject(forKey: "compact_mode")
        }
    }

    /// Resolve to a concrete light/dark boolean, honoring the system setting.
    func isDark(_ systemColorScheme: ColorScheme) -> Bool {
        switch mode {
        case .light: return false
        case .dark: return true
        case .system: return systemColorScheme == .dark
        }
    }

    /// SwiftUI color-scheme override (nil = follow system).
    var preferredColorScheme: ColorScheme? {
        switch mode {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    func cycle() {
        let all = AppThemeMode.allCases
        let next = (all.firstIndex(of: mode)! + 1) % all.count
        mode = all[next]
    }
}
