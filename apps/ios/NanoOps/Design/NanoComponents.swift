import SwiftUI

// MARK: - Status dot

/// Small status dot (online/offline/warn) with an optional pulse glow.
/// Ports `NanoStatusDot`.
struct NanoStatusDot: View {
    let color: Color
    var size: CGFloat = 7
    var pulse: Bool = false

    @State private var animate = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background(
                Group {
                    if pulse {
                        Circle()
                            .fill(color)
                            .frame(width: size, height: size)
                            .scaleEffect(animate ? 2.4 : 1)
                            .opacity(animate ? 0 : 0.45)
                    }
                }
            )
            .onAppear {
                guard pulse else { return }
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: false)) {
                    animate = true
                }
            }
    }
}

// MARK: - Status label

/// Status pill = dot + localized label (online / offline / connecting).
struct NanoStatusLabel: View {
    /// `online` | `offline` | `connecting`
    let status: String
    @Environment(\.nano) private var t
    @EnvironmentObject private var l10n: L10n

    var body: some View {
        let (c, label): (Color, String) = {
            switch status {
            case "online": return (t.ok, tr("status.online"))
            case "connecting": return (t.warn, tr("status.connecting"))
            default: return (t.crit, tr("status.offline"))
            }
        }()
        HStack(spacing: 5) {
            NanoStatusDot(color: c, pulse: status == "online")
            Text(label).font(.system(size: 12)).foregroundColor(t.fg3)
        }
    }
}

// MARK: - Badge

/// Generic colored badge chip. Ports `NanoBadge`.
struct NanoBadge: View {
    let text: String
    var color: Color? = nil
    var icon: String? = nil
    var mono: Bool = false
    @Environment(\.nano) private var t

    var body: some View {
        let fg = color ?? t.fg3
        let bg = color == nil ? t.card2 : (color!).opacity(0.14)
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 11)).foregroundColor(fg) }
            Text(text)
                .font(mono ? NanoFont.mono(11, weight: .medium) : .system(size: 11, weight: .medium))
                .foregroundColor(fg)
        }
        .padding(.horizontal, 6)
        .frame(height: 19)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

// MARK: - Permission pill

/// Permission-level pill (L0..L3) with localized name.
struct NanoPermPill: View {
    let level: Int
    @Environment(\.nano) private var t
    @EnvironmentObject private var l10n: L10n

    var body: some View {
        let c = t.permColor(level)
        let lv = min(max(level, 0), 3)
        let labels = [tr("perm.l0"), tr("perm.l1"), tr("perm.l2"), tr("perm.l3")]
        Text("L\(lv) · \(labels[lv])")
            .font(NanoFont.mono(10.5, weight: .semibold))
            .foregroundColor(c)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(c.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - Meter

/// Thin linear usage meter (0..1). Ports `NanoMeter`.
struct NanoMeter: View {
    let value: Double
    var color: Color? = nil
    var height: CGFloat = 4
    @Environment(\.nano) private var t

    var body: some View {
        let c = color ?? t.meterColor(value * 100)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(t.card3)
                Capsule()
                    .fill(c)
                    .frame(width: geo.size.width * CGFloat(min(max(value, 0), 1)))
                    .animation(.easeInOut(duration: 0.25), value: value)
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

// MARK: - Section label

/// Section header label used between grouped cards. Ports `NanoSectionLabel`.
struct NanoSectionLabel<Trailing: View>: View {
    let label: String
    var grouped: Bool = false
    private let trailing: Trailing
    @Environment(\.nano) private var t
    @Environment(\.nanoCompact) private var compact

    init(_ label: String, grouped: Bool = false, @ViewBuilder trailing: () -> Trailing) {
        self.label = label
        self.grouped = grouped
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Text(grouped ? label.uppercased() : label)
                .font(.system(size: grouped ? 11.5 : 13,
                              weight: grouped ? .regular : .semibold))
                .tracking(grouped ? 0.4 : 0)
                .foregroundColor(grouped ? t.fg3 : t.fg2)
            Spacer(minLength: 0)
            trailing
        }
        .padding(EdgeInsets(top: compact ? 7 : (grouped ? 12 : 10), leading: 4,
                            bottom: compact ? 4 : (grouped ? 7 : 6), trailing: 4))
    }
}

extension NanoSectionLabel where Trailing == EmptyView {
    init(_ label: String, grouped: Bool = false) {
        self.init(label, grouped: grouped) { EmptyView() }
    }
}

// MARK: - Button

enum NanoButtonVariant { case primary, secondary, danger, outlined, text }

/// Compact icon-only control used in the Mac window toolbar. Drawing the
/// surface here avoids Catalyst stretching native toolbar buttons into pills.
struct NanoToolbarButtonStyle: ButtonStyle {
    @Environment(\.nano) private var t

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(t.fg2)
            .frame(width: 38, height: 38)
            .background(configuration.isPressed ? t.card2 : t.card)
            .overlay(Circle().stroke(t.sep2, lineWidth: 1))
            .clipShape(Circle())
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Shared button primitive. Heights/radii/typography follow the active platform
/// look. Ports `NanoButton`.
struct NanoButton: View {
    let label: String
    var icon: String? = nil
    var variant: NanoButtonVariant = .primary
    var fullWidth: Bool = false
    var loading: Bool = false
    var action: () -> Void
    @Environment(\.nano) private var t
    @Environment(\.nanoCompact) private var compact

    init(_ label: String, icon: String? = nil, variant: NanoButtonVariant = .primary,
         fullWidth: Bool = false, loading: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.variant = variant
        self.fullWidth = fullWidth
        self.loading = loading
        self.action = action
    }

    private var isIOS: Bool { t.isIOS }
    private var height: CGFloat {
        let regular: CGFloat = t.desktop
            ? (variant == .text ? 26 : t.controlHeight)
            : (variant == .text ? (isIOS ? 44 : 40) : (isIOS ? 50 : 40))
        return compact ? regular - 6 : regular
    }
    private var fg: Color {
        switch variant {
        case .primary: return t.onAccent
        case .danger: return t.crit
        case .outlined: return t.fg
        default: return t.accent
        }
    }
    private var bg: Color {
        switch variant {
        case .primary: return t.accent
        case .secondary: return t.card2
        case .danger: return t.crit.opacity(0.14)
        default: return .clear
        }
    }

    var body: some View {
        Button(action: { if !loading { action() } }) {
            ZStack {
                if loading {
                    ProgressView().tint(fg)
                } else if let icon {
                    HStack(spacing: t.desktop ? 6 : 8) {
                        Image(systemName: icon).font(.system(size: t.desktop ? 13 : (isIOS ? 20 : 18)))
                        Text(label)
                    }
                } else {
                    Text(label)
                }
            }
            .font(.system(size: t.controlFontSize,
                          weight: t.desktop ? .medium : (isIOS ? .semibold : .medium)))
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .padding(.horizontal, fullWidth ? 0 : 18)
            .foregroundColor(fg)
            .background(bg)
            .overlay(
                RoundedRectangle(cornerRadius: t.buttonRadius, style: .continuous)
                    .strokeBorder(variant == .outlined ? (isIOS ? t.sep : t.fg4) : .clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: t.buttonRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(loading)
    }
}

// MARK: - Mono text

/// Monospace text helper. Ports `NanoMono`.
struct NanoMono: View {
    let text: String
    var size: CGFloat = 12
    var color: Color? = nil
    var weight: Font.Weight = .regular
    @Environment(\.nano) private var t

    init(_ text: String, size: CGFloat = 12, color: Color? = nil, weight: Font.Weight = .regular) {
        self.text = text
        self.size = size
        self.color = color
        self.weight = weight
    }

    var body: some View {
        Text(text)
            .font(NanoFont.mono(size, weight: weight))
            .foregroundColor(color ?? t.fg2)
            .lineSpacing(size * 0.3)
    }
}
