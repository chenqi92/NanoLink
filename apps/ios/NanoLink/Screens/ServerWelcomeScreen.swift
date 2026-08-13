import SwiftUI

/// First-run screen: brand intro, product capabilities and the add-server CTA.
struct ServerWelcomeScreen: View {
    @Environment(\.nano) private var t
    @State private var showAddServer = false

    private let features: [(String, String, String)] = [
        ("chart.xyaxis.line", "welcome.featureMetricsTitle", "welcome.featureMetricsDesc"),
        ("terminal", "welcome.featureTerminalTitle", "welcome.featureTerminalDesc"),
        ("bell.badge", "welcome.featureAuditTitle", "welcome.featureAuditDesc"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: t.isIOS ? .center : .leading, spacing: 0) {
                    BrandMark(size: t.desktop ? 56 : (t.isIOS ? 72 : 64))
                    Text("NanoOps")
                        .font(.system(size: t.desktop ? 24 : (t.isIOS ? 32 : 36), weight: t.displayWeight))
                        .tracking(t.displayTracking)
                        .foregroundColor(t.fg)
                        .padding(.top, t.desktop ? 16 : 26)
                    Text(tr("welcome.tagline"))
                        .font(.system(size: t.desktop ? 13 : 15.5))
                        .foregroundColor(t.fg3)
                        .multilineTextAlignment(t.isIOS ? .center : .leading)
                        .lineSpacing(5)
                        .padding(.top, t.desktop ? 6 : 10)
                        .padding(.bottom, t.desktop ? 20 : 28)

                    ForEach(Array(features.enumerated()), id: \.offset) { _, feature in
                        NanoCard(
                            padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14),
                            outlined: true
                        ) {
                            HStack(spacing: 14) {
                                NanoIconBox(icon: feature.0, size: 40, iconSize: 20, fg: t.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tr(feature.1))
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(t.fg)
                                    Text(tr(feature.2))
                                        .font(.system(size: 13))
                                        .foregroundColor(t.fg3)
                                }
                            }
                        }
                        .padding(.bottom, 10)
                    }
                }
                .frame(maxWidth: 460)
                .padding(EdgeInsets(top: t.desktop ? 28 : 48, leading: 24, bottom: 8, trailing: 24))
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 0) {
                NanoButton(tr("welcome.addServer"), icon: "plus", fullWidth: true) {
                    showAddServer = true
                }
                if t.isIOS {
                    Text(tr("welcome.chooseMethodHint"))
                        .font(.system(size: 12))
                        .foregroundColor(t.fg4)
                        .multilineTextAlignment(.center)
                        .padding(.top, 14)
                }
            }
            .frame(maxWidth: 460)
            .padding(EdgeInsets(top: 8, leading: 24, bottom: 20, trailing: 24))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.bg.ignoresSafeArea())
        .sheet(isPresented: $showAddServer) {
            NavigationStack { AddServerScreen() }
        }
    }
}

/// NanoOps gradient grid mark used by onboarding and settings.
struct BrandMark: View {
    let size: CGFloat
    @Environment(\.nano) private var t

    var body: some View {
        ZStack {
            LinearGradient(colors: [t.accent, t.tertiary], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundColor(t.onAccent)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * (t.isIOS ? 0.22 : 0.32), style: .continuous))
        .shadow(color: t.isIOS ? t.accent.opacity(0.3) : .clear, radius: 12, y: 8)
    }
}
