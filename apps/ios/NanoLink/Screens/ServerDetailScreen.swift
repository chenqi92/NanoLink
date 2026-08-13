import SwiftUI
import UIKit

/// Detail and lifecycle management for one saved server connection.
struct ServerDetailScreen: View {
    let serverId: String

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nano) private var t
    @State private var showReauth = false
    @State private var confirmRemove = false
    @State private var notice: String?

    private var server: ServerConnection? { store.servers.first { $0.id == serverId } }

    var body: some View {
        Group {
            if let server {
                ScrollView {
                    VStack(spacing: 16) {
                        if store.needsReauth(serverId) { reauthBanner(server) }
                        informationCard(server)
                        actionsCard(server)
                        if let notice {
                            Text(notice).font(.system(size: 12.5)).foregroundColor(t.fg3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(EdgeInsets(top: 8, leading: 16, bottom: 40, trailing: 16))
                }
            } else {
                Text(tr("serverDetail.notFound"))
                    .font(.system(size: 14)).foregroundColor(t.fg3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(t.bg.ignoresSafeArea())
        .navigationTitle(server?.name ?? tr("serverDetail.notFound"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showReauth) {
            if let server { ReauthSheet(server: server) { notice = tr("serverDetail.reauthSuccess") } }
        }
        .alert(tr("serverDetail.removeConfirmTitle"), isPresented: $confirmRemove) {
            Button(tr("common.cancel"), role: .cancel) { }
            Button(tr("serverDetail.remove"), role: .destructive) {
                store.removeServer(serverId)
                dismiss()
            }
        } message: {
            Text(tr("serverDetail.removeConfirmBody", ["name": server?.name ?? ""]))
        }
    }

    private func informationCard(_ server: ServerConnection) -> some View {
        NanoCard {
            NanoListRow {
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name).font(.system(size: 16, weight: .semibold)).foregroundColor(t.fg)
                    NanoMono(server.url, size: 12, color: t.fg4).lineLimit(1)
                }
            } leading: {
                NanoIconBox(icon: "server.rack", size: 40)
            } trailing: {
                NanoStatusLabel(status: store.needsReauth(serverId) ? "connecting" : (server.isConnected ? "online" : "offline"))
            }
            keyValue(tr("serverDetail.connectionMode"), modeLabel(store.connectionMode(serverId)))
            keyValue(tr("serverDetail.authType"), server.hasFullPermissions ? tr("serverDetail.authFull") : tr("serverDetail.authReadonly"))
            keyValue(tr("serverDetail.nodeCount"), "\(store.agentsForServer(serverId).count)")
            if let username = server.username, !username.isEmpty {
                keyValue(tr("serverDetail.username"), username)
            }
            keyValue(tr("serverDetail.lastConnected"), server.lastConnected.map(Self.dateFormatter.string) ?? "—", divider: false)
        }
    }

    private func actionsCard(_ server: ServerConnection) -> some View {
        NanoCard {
            if store.needsReauth(serverId) {
                actionRow("lock.rotation", tr("serverDetail.reconnect"), color: t.warn) { showReauth = true }
            }
            actionRow("doc.on.doc", tr("serverDetail.copyUrl"), color: t.accent) {
                UIPasteboard.general.string = server.url
                notice = tr("serverDetail.urlCopied")
            }
            if store.activeServerId != serverId {
                actionRow("checkmark.circle", tr("serverDetail.setActive"), color: t.accent) {
                    store.setActiveServer(serverId)
                    notice = tr("serverDetail.switchedTo", ["name": server.name])
                }
            }
            actionRow("trash", tr("serverDetail.removeServer"), color: t.crit, divider: false) {
                confirmRemove = true
            }
        }
    }

    private func reauthBanner(_ server: ServerConnection) -> some View {
        NanoCard(padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14), color: t.warn.opacity(0.1)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock").font(.system(size: 18)).foregroundColor(t.warn)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("serverDetail.reauthTitle"))
                            .font(.system(size: 14.5, weight: .semibold)).foregroundColor(t.fg)
                        Text(tr("serverDetail.reauthBody"))
                            .font(.system(size: 12.5)).foregroundColor(t.fg3).lineSpacing(4)
                    }
                }
                NanoButton(tr("serverDetail.reconnect"), icon: "lock.rotation", fullWidth: true) {
                    showReauth = true
                }
            }
        }
    }

    private func keyValue(_ key: String, _ value: String, divider: Bool = true) -> some View {
        NanoListRow(divider: divider) {
            Text(key).font(.system(size: 14)).foregroundColor(t.fg3)
        } trailing: {
            Text(value).font(.system(size: 13.5)).foregroundColor(t.fg2)
                .multilineTextAlignment(.trailing).lineLimit(2).frame(maxWidth: 205, alignment: .trailing)
        }
    }

    private func actionRow(_ icon: String, _ label: String, color: Color,
                           divider: Bool = true, action: @escaping () -> Void) -> some View {
        NanoListRow(divider: divider, onTap: action) {
            Text(label).font(.system(size: 15, weight: .medium)).foregroundColor(color == t.crit ? t.crit : t.fg)
        } leading: {
            NanoIconBox(icon: icon, size: 36, iconSize: 17, bg: color.opacity(0.13), fg: color)
        } trailing: {
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(t.fg4)
        }
    }

    private func modeLabel(_ mode: ConnectionMode) -> String {
        switch mode {
        case .websocket: return tr("serverDetail.modeWebsocket")
        case .httpPolling: return tr("serverDetail.modeHttp")
        case .disconnected: return tr("serverDetail.modeDisconnected")
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

/// Credential sheet for restoring an expired/rejected account session.
private struct ReauthSheet: View {
    let server: ServerConnection
    let onSuccess: () -> Void

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nano) private var t
    @State private var username: String
    @State private var password = ""
    @State private var loading = false
    @State private var error: String?

    init(server: ServerConnection, onSuccess: @escaping () -> Void) {
        self.server = server
        self.onSuccess = onSuccess
        _username = State(initialValue: server.username ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(tr("serverDetail.reauthSheetBody", ["name": server.name]))
                        .font(.system(size: 13)).foregroundColor(t.fg3).lineSpacing(4)
                    field(tr("addServer.username"), text: $username, hint: "admin")
                    field(tr("addServer.password"), text: $password, hint: "••••••••", secure: true)
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.system(size: 13)).foregroundColor(t.crit)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(t.crit.opacity(0.12)).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    NanoButton(tr("serverDetail.reauthLogin"), icon: "arrow.right.circle",
                               fullWidth: true, loading: loading) { submit() }
                }
                .padding(20)
            }
            .background(t.bg)
            .navigationTitle(tr("serverDetail.reauthSheetTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("common.cancel")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func field(_ label: String, text: Binding<String>, hint: String, secure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundColor(t.fg2)
            Group {
                if secure { SecureField(hint, text: text) }
                else { TextField(hint, text: text).textInputAutocapitalization(.never).autocorrectionDisabled() }
            }
            .font(.system(size: 15)).foregroundColor(t.fg)
            .padding(.horizontal, 14).frame(height: 48).background(t.card2)
            .clipShape(RoundedRectangle(cornerRadius: t.fieldRadius, style: .continuous))
        }
    }

    private func submit() {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !password.isEmpty else { error = tr("serverDetail.reauthMissing"); return }
        loading = true; error = nil
        Task {
            let ok = await store.reauthenticate(serverId: server.id, username: user, password: password)
            loading = false
            if ok { onSuccess(); dismiss() }
            else { error = tr("serverDetail.reauthFailed") }
        }
    }
}
