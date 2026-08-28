import SwiftUI

// MARK: - Card

/// Grouped card surface (iOS inset-grouped / Material filled card). Ports `NanoCard`.
struct NanoCard<Content: View>: View {
    var padding: EdgeInsets? = nil
    var color: Color? = nil
    var outlined: Bool = false
    var onTap: (() -> Void)? = nil
    private let content: Content
    @Environment(\.nano) private var t

    init(padding: EdgeInsets? = nil, color: Color? = nil, outlined: Bool = false,
         onTap: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.color = color
        self.outlined = outlined
        self.onTap = onTap
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: t.cardRadius, style: .continuous)
        // The content is stacked explicitly: a multi-statement ViewBuilder body
        // produces a `TupleView`, and applying `.background`/`.clipShape` to that
        // directly fills and rounds *each* child separately, so a card holding N
        // rows renders as N stacked cards butted against one another. Wrapping in
        // a zero-spacing VStack keeps the card a single surface.
        let inner = VStack(spacing: 0) { content }
            .modifier(OptionalPadding(padding: padding))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color ?? t.card)
            .overlay(shape.strokeBorder(outlined ? t.sep : .clear, lineWidth: 1))
            .clipShape(shape)

        if let onTap {
            Button(action: onTap) { inner }
                .buttonStyle(NanoCardButtonStyle())
                .hoverEffect(.highlight)
        } else {
            inner
        }
    }
}

/// Applies padding only when a value is supplied.
private struct OptionalPadding: ViewModifier {
    let padding: EdgeInsets?
    func body(content: Content) -> some View {
        if let padding { content.padding(padding) } else { content }
    }
}

// MARK: - List row

/// A single row inside a `NanoCard`, with an optional hairline divider.
/// Ports `NanoListRow`.
struct NanoListRow<Leading: View, Content: View, Trailing: View>: View {
    private let leading: Leading
    private let content: Content
    private let trailing: Trailing
    var divider: Bool = true
    var onTap: (() -> Void)? = nil
    /// `nil` takes the vertical inset from the design tokens, which are denser in
    /// the desktop idiom.
    var padding: EdgeInsets? = nil
    var verticalAlignment: VerticalAlignment = .center
    @Environment(\.nano) private var t
    @Environment(\.nanoCompact) private var compact

    init(divider: Bool = true, onTap: (() -> Void)? = nil,
         padding: EdgeInsets? = nil,
         verticalAlignment: VerticalAlignment = .center,
         @ViewBuilder content: () -> Content,
         @ViewBuilder leading: () -> Leading = { EmptyView() },
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.divider = divider
        self.onTap = onTap
        self.padding = padding
        self.verticalAlignment = verticalAlignment
        self.content = content()
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        let row = HStack(alignment: verticalAlignment, spacing: 0) {
            if !(leading is EmptyView) { leading; Spacer().frame(width: 12) }
            content.frame(maxWidth: .infinity, alignment: .leading)
            if !(trailing is EmptyView) { Spacer().frame(width: 10); trailing }
        }
        .padding(resolvedPadding)
        .overlay(alignment: .bottom) {
            if divider { Rectangle().fill(t.sep2).frame(height: 0.5) }
        }
        .contentShape(Rectangle())

        if let onTap {
            Button(action: onTap) { row }
                .buttonStyle(NanoRowButtonStyle())
                .hoverEffect(.highlight)
        } else {
            row
        }
    }

    private var resolvedPadding: EdgeInsets {
        let base = padding ?? EdgeInsets(top: t.rowVerticalPadding, leading: 16,
                                         bottom: t.rowVerticalPadding, trailing: 16)
        guard compact else { return base }
        return EdgeInsets(top: max(5, base.top - 3), leading: base.leading,
                          bottom: max(5, base.bottom - 3), trailing: base.trailing)
    }
}

/// Visible press feedback for full-card navigation and selection controls.
struct NanoCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.995 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Press feedback for rows embedded in a shared card surface.
private struct NanoRowButtonStyle: ButtonStyle {
    @Environment(\.nano) private var t

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? t.card2 : Color.clear)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Icon box

/// Rounded square icon container used as a list-row leading element.
/// Ports `NanoIconBox`.
struct NanoIconBox: View {
    let icon: String
    var size: CGFloat = 36
    var iconSize: CGFloat = 18
    var bg: Color? = nil
    var fg: Color? = nil
    var gradient: LinearGradient? = nil
    @Environment(\.nano) private var t

    var body: some View {
        ZStack {
            if let gradient {
                gradient
            } else {
                (bg ?? t.card2)
            }
            Image(systemName: icon)
                .font(.system(size: iconSize))
                .foregroundColor(fg ?? t.fg3)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
    }
}
