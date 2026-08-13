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
        let inner = content
            .modifier(OptionalPadding(padding: padding))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color ?? t.card)
            .overlay(shape.strokeBorder(outlined ? t.sep : .clear, lineWidth: 1))
            .clipShape(shape)

        if let onTap {
            Button(action: onTap) { inner }.buttonStyle(.plain)
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
    var padding = EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16)
    var verticalAlignment: VerticalAlignment = .center
    @Environment(\.nano) private var t
    @Environment(\.nanoCompact) private var compact

    init(divider: Bool = true, onTap: (() -> Void)? = nil,
         padding: EdgeInsets = EdgeInsets(top: 11, leading: 16, bottom: 11, trailing: 16),
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
            Button(action: onTap) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }

    private var resolvedPadding: EdgeInsets {
        guard compact else { return padding }
        return EdgeInsets(top: max(5, padding.top - 3), leading: padding.leading,
                          bottom: max(5, padding.bottom - 3), trailing: padding.trailing)
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
