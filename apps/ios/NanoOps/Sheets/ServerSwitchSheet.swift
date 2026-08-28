import SwiftUI

/// Server chooser shared by the dashboard and node list.
struct ServerSwitchSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nano) private var t
    @State private var showAddServer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                NanoCard {
                    ForEach(Array(store.servers.enumerated()), id: \.element.id) { index, server in
                        NanoListRow(divider: index < store.servers.count - 1, onTap: {
                            store.setActiveServer(server.id)
                            dismiss()
                        }) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(server.name)
                                    .font(.system(size: 15, weight: server.id == store.activeServerId ? .semibold : .medium))
                                    .foregroundColor(server.id == store.activeServerId ? t.accent : t.fg)
                                NanoMono(server.url, size: 11, color: t.fg4).lineLimit(1)
                            }
                        } leading: {
                            NanoIconBox(icon: "server.rack", size: 38, iconSize: 18,
                                        bg: server.id == store.activeServerId ? t.accent.opacity(0.15) : nil,
                                        fg: server.id == store.activeServerId ? t.accent : t.fg3)
                        } trailing: {
                            if server.id == store.activeServerId {
                                Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundColor(t.accent)
                            } else {
                                NanoStatusDot(color: server.isConnected ? t.ok : t.crit, pulse: server.isConnected)
                            }
                        }
                    }
                }
                .padding(16)

                NanoButton(tr("serverSwitch.addServer"), icon: "plus", variant: .text, fullWidth: true) {
                    showAddServer = true
                }
                .padding(.horizontal, 16)
            }
            .background(t.bg)
            .navigationTitle(tr("serverSwitch.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("common.dismiss")) { dismiss() }
                }
            }
            .sheet(isPresented: $showAddServer) { NavigationStack { AddServerScreen() } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
