import SwiftUI
import UIKit

/// Generates a short-lived device token and presents its QR payload + six-digit
/// pairing code. Requires an account-authenticated server connection.
struct DevicePairingScreen: View {
    let serverId: String

    @EnvironmentObject private var store: AppStore
    @Environment(\.nano) private var t
    @State private var result: DeviceTokenResult?
    @State private var loading = true
    @State private var remaining = 0
    @State private var countdownTask: Task<Void, Never>?

    private let fallbackTTL = 15 * 60

    var body: some View {
        Group {
            if loading {
                ProgressView().controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result {
                content(result)
            } else {
                errorView
            }
        }
        .background(t.bg.ignoresSafeArea())
        .navigationTitle(tr("pairing.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { if result == nil { await generate() } }
        .onDisappear { countdownTask?.cancel() }
    }

    private func content(_ result: DeviceTokenResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(tr("pairing.intro", ["name": store.serverName(serverId)]))
                    .font(.system(size: 14))
                    .foregroundColor(t.fg3)
                    .lineSpacing(5)

                QRCodeView(value: result.qrData)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)

                NanoSectionLabel(tr("pairing.pairingCode"), grouped: true)
                NanoCard {
                    NanoListRow(divider: false) {
                        Text(formatCode(result.pairingCode))
                            .font(NanoFont.mono(26, weight: .bold))
                            .tracking(6)
                            .foregroundColor(t.fg)
                    } trailing: {
                        Button {
                            UIPasteboard.general.string = result.pairingCode
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 18))
                                .foregroundColor(t.accent)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tr("common.copy"))
                    }
                }

                metadataRow(level: result.permissionLevel)
                    .padding(.top, 12)

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock")
                        .font(.system(size: 16))
                        .foregroundColor(t.warn)
                    Text(tr("pairing.securityNote"))
                        .font(.system(size: 12.5))
                        .foregroundColor(t.fg2)
                        .lineSpacing(4)
                }
                .padding(14)
                .background(t.warn.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 16)

                NanoButton(tr("pairing.regenerate"), icon: "arrow.clockwise",
                           variant: .outlined, fullWidth: true, loading: loading) {
                    Task { await generate() }
                }
                .padding(.top, 20)
            }
            .padding(EdgeInsets(top: 8, leading: 20, bottom: 32, trailing: 20))
        }
    }

    private func metadataRow(level: Int) -> some View {
        let expired = remaining == 0
        let low = remaining > 0 && remaining < 60
        let color = expired ? t.crit : (low ? t.warn : t.fg2)
        return HStack(spacing: 6) {
            Image(systemName: "timer").font(.system(size: 15)).foregroundColor(color)
            Text(expired ? tr("pairing.expired") : tr("pairing.expiresIn", ["time": formatRemaining()]))
                .font(NanoFont.mono(13))
                .foregroundColor(color)
            Spacer()
            Text(tr("pairing.grants")).font(.system(size: 12.5)).foregroundColor(t.fg3)
            NanoPermPill(level: level)
        }
    }

    private var errorView: some View {
        VStack(spacing: 12) {
            Image(systemName: "qrcode")
                .font(.system(size: 36))
                .foregroundColor(t.fg4)
            Text(tr("pairing.errorTitle"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(t.fg)
            Text(tr("pairing.errorDesc"))
                .font(.system(size: 13))
                .foregroundColor(t.fg3)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            NanoButton(tr("common.retry"), icon: "arrow.clockwise", variant: .text) {
                Task { await generate() }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func generate() async {
        countdownTask?.cancel()
        loading = true
        result = nil
        guard let service = store.serviceForServer(serverId) else {
            loading = false
            return
        }
        let generated = await service.generateDeviceToken(serverName: store.serverName(serverId))
        result = generated
        loading = false
        guard let generated else { return }
        let seconds: Int
        if let expiresAt = generated.expiresAt {
            seconds = min(max(Int(expiresAt.timeIntervalSinceNow), 0), fallbackTTL * 4)
        } else {
            seconds = fallbackTTL
        }
        startCountdown(seconds)
    }

    private func startCountdown(_ seconds: Int) {
        remaining = seconds
        countdownTask = Task {
            while !Task.isCancelled && remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                remaining -= 1
            }
        }
    }

    private func formatRemaining() -> String {
        String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    private func formatCode(_ code: String) -> String {
        guard code.count == 6 else { return code }
        let split = code.index(code.startIndex, offsetBy: 3)
        return "\(code[..<split]) \(code[split...])"
    }
}
