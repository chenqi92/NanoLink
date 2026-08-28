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
        Group {
            if t.desktop {
                if showAddServer {
                    AddServerScreen(onClose: { showAddServer = false })
                        .transition(.opacity)
                } else {
                    desktopContent
                        .transition(.opacity)
                }
            } else {
                touchContent
                    .sheet(isPresented: $showAddServer) {
                        NavigationStack { AddServerScreen() }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.bg.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.18), value: showAddServer)
    }

    private var desktopContent: some View {
        HStack(alignment: .center, spacing: 64) {
            VStack(alignment: .leading, spacing: 0) {
                BrandMark(size: 88)
                Text("NanoOps")
                    .font(.system(size: 38, weight: .bold))
                    .tracking(-1.1)
                    .foregroundColor(t.fg)
                    .padding(.top, 24)
                Text(tr("welcome.tagline"))
                    .font(.system(size: 16))
                    .foregroundColor(t.fg3)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                NanoButton(tr("welcome.addServer"), icon: "plus", fullWidth: true) {
                    showAddServer = true
                }
                .frame(width: 220)
                .padding(.top, 32)

                Text(tr("welcome.chooseMethodHint"))
                    .font(.system(size: 12.5))
                    .foregroundColor(t.fg4)
                    .lineSpacing(4)
                    .frame(maxWidth: 330, alignment: .leading)
                    .padding(.top, 12)
            }
            .frame(width: 340, alignment: .leading)

            VStack(spacing: 14) {
                ForEach(Array(features.enumerated()), id: \.offset) { _, feature in
                    featureCard(feature, desktop: true)
                }
            }
            .frame(width: 460)
        }
        .padding(56)
        .frame(minWidth: 900, minHeight: 600)
        .frame(maxWidth: 1_020, maxHeight: .infinity, alignment: .center)
        .frame(maxWidth: .infinity)
    }

    private var touchContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: t.isIOS ? .center : .leading, spacing: 0) {
                    BrandMark(size: t.isIOS ? 72 : 64)
                    Text("NanoOps")
                        .font(.system(size: t.isIOS ? 32 : 36, weight: t.displayWeight))
                        .tracking(t.displayTracking)
                        .foregroundColor(t.fg)
                        .padding(.top, 26)
                    Text(tr("welcome.tagline"))
                        .font(.system(size: 15.5))
                        .foregroundColor(t.fg3)
                        .multilineTextAlignment(t.isIOS ? .center : .leading)
                        .lineSpacing(5)
                        .padding(.top, 10)
                        .padding(.bottom, 28)

                    ForEach(Array(features.enumerated()), id: \.offset) { _, feature in
                        featureCard(feature, desktop: false)
                            .padding(.bottom, 10)
                    }
                }
                .frame(maxWidth: 460)
                .padding(EdgeInsets(top: 48, leading: 24, bottom: 8, trailing: 24))
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
    }

    private func featureCard(_ feature: (String, String, String), desktop: Bool) -> some View {
        NanoCard(
            padding: EdgeInsets(top: desktop ? 18 : 14, leading: desktop ? 18 : 14,
                                bottom: desktop ? 18 : 14, trailing: desktop ? 18 : 14),
            outlined: true
        ) {
            HStack(spacing: desktop ? 16 : 14) {
                NanoIconBox(icon: feature.0, size: desktop ? 48 : 40,
                            iconSize: desktop ? 22 : 20, fg: t.accent)
                VStack(alignment: .leading, spacing: desktop ? 4 : 2) {
                    Text(tr(feature.1))
                        .font(.system(size: desktop ? 16 : 15, weight: .semibold))
                        .foregroundColor(t.fg)
                    Text(tr(feature.2))
                        .font(.system(size: desktop ? 13.5 : 13))
                        .foregroundColor(t.fg3)
                }
            }
        }
    }
}

/// NanoOps gradient grid mark used by onboarding and settings.
struct BrandMark: View {
    let size: CGFloat
    @Environment(\.nano) private var t

    var body: some View {
        Image("BrandLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * (t.isIOS ? 0.22 : 0.18), style: .continuous))
            .shadow(color: t.accent.opacity(t.desktop ? 0.16 : 0.26), radius: t.desktop ? 18 : 12, y: 8)
    }
}
