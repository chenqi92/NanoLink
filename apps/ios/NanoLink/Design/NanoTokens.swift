import SwiftUI

/// Visual language of the NanoLink app. Ships two platform looks that share the
/// same data and primitives:
/// - `.ios` — Apple system colors, large titles, grouped cards.
/// - `.md`  — Material 3 / Material You surfaces.
///
/// Concrete color values follow the shared mobile design tokens.
enum NanoStyle { case ios, md }

extension Color {
    /// Build a color from a 0xAARRGGBB integer (alpha-first).
    init(argb: UInt32) {
        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8) & 0xFF) / 255.0
        let b = Double(argb & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

/// Design tokens for a `style` + `isDark` pair. Widgets pull every color / radius
/// value from here instead of hard-coding, so a single place controls the iOS vs
/// Material palettes in light and dark.
struct NanoTokens {
    let style: NanoStyle
    let isDark: Bool

    // Surfaces / backgrounds
    let bg: Color       // page background
    let bg2: Color      // secondary background
    let card: Color     // primary grouped card / surface
    let card2: Color    // nested / pressed surface
    let card3: Color    // meter track / deepest surface
    let sep: Color      // separators (stronger)
    let sep2: Color     // separators (hairline)

    // Foreground text tiers
    let fg: Color
    let fg2: Color
    let fg3: Color
    let fg4: Color
    let fg5: Color

    // Accents
    let accent: Color
    let onAccent: Color
    let secondary: Color
    let tertiary: Color

    // Chrome
    let tabBg: Color
    let glassBorder: Color

    // Status (shared across platforms)
    let ok: Color
    let warn: Color
    let crit: Color
    let info: Color

    /// True in the macOS ("Optimize Interface for Mac") idiom, where controls are
    /// pointer-sized and the window itself supplies title and toolbar chrome.
    /// Set by `NanoTokens.resolve`; the palettes themselves stay platform-neutral.
    var desktop: Bool = false

    var isIOS: Bool { style == .ios }

    // MARK: Corner radius conventions per platform

    var cardRadius: CGFloat { desktop ? 8 : (isIOS ? 14 : 16) }
    var fieldRadius: CGFloat { desktop ? 6 : (isIOS ? 12 : 8) }
    var buttonRadius: CGFloat { desktop ? 6 : (isIOS ? 14 : 100) }

    // MARK: Display title weight (iOS is heavier/tighter than Material You)

    var displayWeight: Font.Weight { desktop ? .semibold : (isIOS ? .bold : .medium) }
    var displayTracking: CGFloat { desktop ? -0.2 : (isIOS ? -0.8 : -0.3) }

    // MARK: Desktop-aware metrics
    //
    // A pointer-driven window wants denser rows, smaller controls and no room
    // reserved for a bottom tab bar, so screens read these instead of hard-coding
    // the phone values.

    /// Size of an inline page heading. Desktop windows carry the title in their
    /// own chrome, so this only applies where a heading is still drawn in content.
    var titleSize: CGFloat { desktop ? 20 : (isIOS ? 32 : 28) }

    /// Top inset above an inline page heading.
    var titleTopPadding: CGFloat { desktop ? 2 : (isIOS ? 32 : 4) }

    /// Height of a standard push button.
    var controlHeight: CGFloat { desktop ? 30 : (isIOS ? 50 : 40) }

    /// Font size inside a standard push button.
    var controlFontSize: CGFloat { desktop ? 13 : (isIOS ? 17 : 14) }

    /// Vertical padding of a list row inside a grouped card.
    var rowVerticalPadding: CGFloat { desktop ? 7 : 11 }

    /// Bottom inset of a scrollable screen. Phones reserve room for the floating
    /// tab bar; a desktop window has none.
    var contentBottomInset: CGFloat { desktop ? 24 : 100 }

    // MARK: shared status palette

    private static let _ok = Color(argb: 0xFF30D158)
    private static let _warn = Color(argb: 0xFFFFB020)
    private static let _crit = Color(argb: 0xFFFF453A)
    private static let _info = Color(argb: 0xFF0A84FF)

    /// Color for a 0-100 usage value: ok < 75 < warn < 90 < crit.
    func usageColor(_ pct: Double) -> Color {
        if pct > 90 { return crit }
        if pct > 75 { return warn }
        return fg
    }

    /// Tone color for meters/sparks.
    func meterColor(_ pct: Double) -> Color {
        if pct > 90 { return crit }
        if pct > 75 { return warn }
        return fg2
    }

    /// Permission-level pill color (L0..L3).
    func permColor(_ level: Int) -> Color {
        switch level {
        case 1: return NanoTokens._info
        case 2: return warn
        case 3: return crit
        default: return Color(argb: 0xFFA3A3A3)
        }
    }

    // MARK: factory palettes (1:1 with mobile-tokens.css)

    static let iosDark = NanoTokens(
        style: .ios, isDark: true,
        bg: Color(argb: 0xFF000000),
        bg2: Color(argb: 0xFF0A0A0A),
        card: Color(argb: 0xFF1C1C1E),
        card2: Color(argb: 0xFF2C2C2E),
        card3: Color(argb: 0xFF3A3A3C),
        sep: Color(argb: 0x80545458),
        sep2: Color(argb: 0x52545458),
        fg: Color(argb: 0xFFFFFFFF),
        fg2: Color(argb: 0xD9EBEBF5),
        fg3: Color(argb: 0x99EBEBF5),
        fg4: Color(argb: 0x66EBEBF5),
        fg5: Color(argb: 0x40EBEBF5),
        accent: Color(argb: 0xFF0A84FF),
        onAccent: Color(argb: 0xFFFFFFFF),
        secondary: Color(argb: 0xFF0A84FF),
        tertiary: Color(argb: 0xFF5E5CE6),
        tabBg: Color(argb: 0xC71C1C1E),
        glassBorder: Color(argb: 0x12FFFFFF),
        ok: _ok, warn: _warn, crit: _crit, info: _info
    )

    static let iosLight = NanoTokens(
        style: .ios, isDark: false,
        bg: Color(argb: 0xFFF2F2F7),
        bg2: Color(argb: 0xFFE5E5EA),
        card: Color(argb: 0xFFFFFFFF),
        card2: Color(argb: 0xFFF2F2F7),
        card3: Color(argb: 0xFFE5E5EA),
        sep: Color(argb: 0x4A3C3C43),
        sep2: Color(argb: 0x2E3C3C43),
        fg: Color(argb: 0xFF000000),
        fg2: Color(argb: 0xDB3C3C43),
        fg3: Color(argb: 0x993C3C43),
        fg4: Color(argb: 0x663C3C43),
        fg5: Color(argb: 0x403C3C43),
        accent: Color(argb: 0xFF007AFF),
        onAccent: Color(argb: 0xFFFFFFFF),
        secondary: Color(argb: 0xFF007AFF),
        tertiary: Color(argb: 0xFF5856D6),
        tabBg: Color(argb: 0xC7F8F8F8),
        glassBorder: Color(argb: 0x12000000),
        ok: _ok, warn: _warn, crit: _crit, info: _info
    )

    static let mdDark = NanoTokens(
        style: .md, isDark: true,
        bg: Color(argb: 0xFF131318),
        bg2: Color(argb: 0xFF1B1B21),
        card: Color(argb: 0xFF1F1F25),
        card2: Color(argb: 0xFF28282E),
        card3: Color(argb: 0xFF36363D),
        sep: Color(argb: 0xFF2A2A30),
        sep2: Color(argb: 0xFF36363D),
        fg: Color(argb: 0xFFE6E1E9),
        fg2: Color(argb: 0xFFCAC4D0),
        fg3: Color(argb: 0xFF938F99),
        fg4: Color(argb: 0xFF79747E),
        fg5: Color(argb: 0xFF49454F),
        accent: Color(argb: 0xFFB4C5FF),
        onAccent: Color(argb: 0xFF1B2C5D),
        secondary: Color(argb: 0xFFC6C2DC),
        tertiary: Color(argb: 0xFFEEB8E8),
        tabBg: Color(argb: 0xF21F1F25),
        glassBorder: Color(argb: 0x14FFFFFF),
        ok: _ok, warn: _warn, crit: _crit, info: _info
    )

    static let mdLight = NanoTokens(
        style: .md, isDark: false,
        bg: Color(argb: 0xFFFFFBFF),
        bg2: Color(argb: 0xFFF4EFF4),
        card: Color(argb: 0xFFECE6EB),
        card2: Color(argb: 0xFFE6E0E9),
        card3: Color(argb: 0xFFE6E0E9),
        sep: Color(argb: 0xFFE6E0E9),
        sep2: Color(argb: 0xFFECE6EB),
        fg: Color(argb: 0xFF1C1B1F),
        fg2: Color(argb: 0xFF49454F),
        fg3: Color(argb: 0xFF79747E),
        fg4: Color(argb: 0xFF938F99),
        fg5: Color(argb: 0xFFCAC4D0),
        accent: Color(argb: 0xFF4F5A86),
        onAccent: Color(argb: 0xFFFFFFFF),
        secondary: Color(argb: 0xFF5A5D72),
        tertiary: Color(argb: 0xFF7E5260),
        tabBg: Color(argb: 0xEBFFFBFF),
        glassBorder: Color(argb: 0x14000000),
        ok: _ok, warn: _warn, crit: _crit, info: _info
    )

    /// Resolve the tokens for a `ThemeStyle` + dark flag, optionally in the
    /// desktop idiom.
    static func resolve(_ style: ThemeStyle, _ isDark: Bool, desktop: Bool = false) -> NanoTokens {
        var tokens: NanoTokens
        switch style {
        case .ios: tokens = isDark ? iosDark : iosLight
        case .md: tokens = isDark ? mdDark : mdLight
        }
        tokens.desktop = desktop
        return tokens
    }
}

/// Monospace font-family fallbacks (no bundled mono font; rely on platform fonts).
/// SwiftUI can only take one custom name plus a system fallback, so callers use
/// `Font.nanoMono(...)` which prefers "SF Mono" and falls back to the system
/// monospaced face.
enum NanoFont {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        // SF Mono ships on iOS; `.monospaced` design guarantees a fallback.
        .system(size: size, weight: weight, design: .monospaced)
    }
}
