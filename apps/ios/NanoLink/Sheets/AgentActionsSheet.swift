import SwiftUI
import UIKit

/// Permission-aware actions for a node: terminal, metrics refresh, ID copy and
/// L3-only reboot with command-result polling.
struct AgentActionsSheet: View {
    let agent: Agent
    var onOpenTerminal: (() -> Void)? = nil

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nano) private var t
    @State private var confirmReboot = false
    @State private var busyMessage: String?
    @State private var resultMessage: String?
    @State private var resultIsError = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                NanoCard {
                    if agent.permissionLevel >= 3 {
                        actionRow("terminal", "actions.openTerminal", "actions.openTerminalSub") {
                            dismiss(); onOpenTerminal?()
                        }
                    }
                    actionRow("arrow.clockwise", "actions.requestData", "actions.requestDataSub") {
                        requestData()
                    }
                    actionRow("doc.on.doc", "actions.copyAgentId", nil) {
                        UIPasteboard.general.string = agent.id
                        showResult(tr("actions.agentIdCopied"))
                    }
                    if agent.permissionLevel >= 3 {
                        actionRow("power", "actions.reboot", "actions.rebootSub", danger: true, divider: false) {
                            confirmReboot = true
                        }
                    }
                }
                .padding(16)

                if let busyMessage {
                    HStack(spacing: 10) { ProgressView(); Text(busyMessage).foregroundColor(t.fg2) }
                        .font(.system(size: 13)).padding(.horizontal, 20)
                } else if let resultMessage {
                    HStack(spacing: 9) {
                        Image(systemName: resultIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundColor(resultIsError ? t.crit : t.ok)
                        Text(resultMessage).font(.system(size: 13)).foregroundColor(t.fg2)
                    }
                    .padding(.horizontal, 20)
                }
                Spacer()
            }
            .background(t.bg)
            .navigationTitle(tr("actions.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("common.dismiss")) { dismiss() } } }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .alert(tr("actions.rebootConfirmTitle"), isPresented: $confirmReboot) {
            Button(tr("common.cancel"), role: .cancel) { }
            Button(tr("actions.rebootConfirm"), role: .destructive) { reboot() }
        } message: { Text(tr("actions.rebootConfirmBody")) }
    }

    private func actionRow(_ icon: String, _ title: String, _ sub: String?,
                           danger: Bool = false, divider: Bool = true,
                           action: @escaping () -> Void) -> some View {
        NanoListRow(divider: divider, onTap: busyMessage == nil ? action : nil) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr(title)).font(.system(size: 15, weight: .medium)).foregroundColor(danger ? t.crit : t.fg)
                if let sub { Text(tr(sub)).font(.system(size: 12.5)).foregroundColor(t.fg3) }
            }
        } leading: {
            Image(systemName: icon).font(.system(size: 18)).foregroundColor(danger ? t.crit : t.accent).frame(width: 24)
        } trailing: {
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(t.fg4)
        }
    }

    private func requestData() {
        guard let service = store.serviceForAgent(agent.id) else {
            showResult(tr("actions.noServerForNode"), error: true); return
        }
        busyMessage = tr("actions.requestDataPending")
        resultMessage = nil
        Task {
            let error = await service.requestData(agent.id)
            busyMessage = nil
            if let error { showResult(tr("actions.dataRequestFailed", ["error": error]), error: true) }
            else { showResult(tr("actions.dataRequested")) }
        }
    }

    private func reboot() {
        guard let service = store.serviceForAgent(agent.id) else {
            showResult(tr("actions.noServerForNode"), error: true); return
        }
        busyMessage = tr("actions.rebootPending")
        resultMessage = nil
        Task {
            let dispatch = await service.sendCommandReturningId(agent.id, type: "SYSTEM_REBOOT")
            guard dispatch.ok, let commandId = dispatch.commandId else {
                busyMessage = nil
                showResult(tr("actions.rebootFailed", ["error": dispatch.error ?? "unknown"]), error: true)
                return
            }
            for _ in 0..<6 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let result = await service.pollCommandResult(agent.id, commandId)
                switch result.status {
                case .ready:
                    busyMessage = nil; showResult(tr("actions.rebootDone")); return
                case .denied:
                    busyMessage = nil; showResult(tr("actions.commandDenied"), error: true); return
                case .error:
                    busyMessage = nil; showResult(tr("actions.rebootFailed", ["error": result.message ?? "unknown"]), error: true); return
                case .pending: continue
                }
            }
            busyMessage = nil
            showResult(tr("actions.rebootSent"))
        }
    }

    private func showResult(_ message: String, error: Bool = false) {
        resultMessage = message
        resultIsError = error
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if resultMessage == message { resultMessage = nil }
        }
    }
}
