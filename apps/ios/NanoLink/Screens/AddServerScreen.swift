import SwiftUI
import UIKit

private enum ServerConnectionMethod: String, Identifiable {
    case qrCode, account, pairing, manual
    var id: String { rawValue }
}

/// Add-server flow with all four connection methods from the Flutter app.
struct AddServerScreen: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nano) private var t

    @State private var method: ServerConnectionMethod?
    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var token = ""
    @State private var pairingCode = ""
    @State private var deviceName = UIDevice.current.name
    @State private var forceTls = false
    @State private var ignoreCert = false
    @State private var advanced = false
    @State private var loading = false
    @State private var error: String?
    @State private var torchOn = false
    @State private var qrIdentity: String?
    @State private var qrScanID = UUID()
    @State private var qrRestartTask: Task<Void, Never>?
    @State private var pairingState: PairingState = .input
    @State private var pairingRemaining = 60
    @State private var countdownTask: Task<Void, Never>?

    private enum PairingState { case input, verifying, success, invalid }

    var body: some View {
        Group {
            if let method {
                methodContent(method)
            } else {
                methodSelection
            }
        }
        .background(t.bg.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    if method == nil { dismiss() } else { resetMethod() }
                } label: {
                    if method == nil { Text(tr("common.cancel")) }
                    else { Image(systemName: "chevron.left") }
                }
            }
            if method == .qrCode {
                ToolbarItem(placement: .primaryAction) {
                    Button { torchOn.toggle() } label: {
                        Image(systemName: torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    }
                }
            }
        }
        .onDisappear {
            countdownTask?.cancel()
            qrRestartTask?.cancel()
        }
    }

    private var title: String {
        switch method {
        case .qrCode: return tr("addServer.headerScanQr")
        case .account: return tr("addServer.headerAccount")
        case .pairing: return tr("addServer.headerPairing")
        case .manual: return tr("addServer.headerManual")
        case nil: return tr("addServer.title")
        }
    }

    private var methodSelection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(tr("server.chooseMethodDesc"))
                    .font(.system(size: 14))
                    .foregroundColor(t.fg3)
                    .padding(.bottom, 20)
                NanoCard {
                    methodRow(.qrCode, icon: "qrcode.viewfinder", title: "addServer.methodScanQr", sub: "addServer.methodScanQrDesc")
                    methodRow(.account, icon: "person.crop.circle.badge.checkmark", title: "addServer.methodAccount", sub: "addServer.methodAccountDesc")
                    methodRow(.pairing, icon: "number.square", title: "addServer.methodPairing", sub: "addServer.methodPairingDesc")
                    methodRow(.manual, icon: "slider.horizontal.3", title: "addServer.methodManual", sub: "addServer.methodManualDesc", divider: false)
                }
                Text(tr("addServer.chooseMethodHint"))
                    .font(.system(size: 12.5))
                    .foregroundColor(t.fg4)
                    .lineSpacing(4)
                    .padding(.top, 18)
            }
            .padding(20)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
    }

    private func methodRow(_ value: ServerConnectionMethod, icon: String,
                           title: String, sub: String, divider: Bool = true) -> some View {
        NanoListRow(divider: divider, onTap: {
            error = nil
            method = value
            if value == .pairing { startCountdown() }
        }) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tr(title)).font(.system(size: 15, weight: .medium)).foregroundColor(t.fg)
                Text(tr(sub)).font(.system(size: 12.5)).foregroundColor(t.fg3)
            }
        } leading: {
            NanoIconBox(icon: icon, size: 44, iconSize: 21, fg: t.accent)
        } trailing: {
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(t.fg4)
        }
    }

    @ViewBuilder
    private func methodContent(_ method: ServerConnectionMethod) -> some View {
        switch method {
        case .qrCode: qrScanner
        case .account: accountForm
        case .pairing: pairingForm
        case .manual: manualForm
        }
    }

    private var qrScanner: some View {
        VStack(spacing: 0) {
            ZStack {
                QRScannerView(onCode: processQr, onError: handleQrFailure, torchOn: $torchOn)
                    .id(qrScanID)
                ScanFrame()
                    .stroke(t.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 245, height: 245)
                if loading {
                    Color.black.opacity(0.45)
                    VStack(spacing: 12) {
                        ProgressView().tint(.white)
                        Text(tr("addServer.qrSaving")).font(.system(size: 13)).foregroundColor(.white)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: t.cardRadius, style: .continuous))
            .padding(20)

            if let qrIdentity {
                Text("✓ \(qrIdentity)")
                    .font(NanoFont.mono(12, weight: .medium))
                    .foregroundColor(t.ok)
                    .padding(.bottom, 10)
            }
            Text(tr("addServer.qrHint"))
                .font(.system(size: 13))
                .foregroundColor(t.fg3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            if let error { errorBanner(error) }
            Spacer()
            Button(tr("addServer.useManualInstead")) { self.method = .manual }
                .font(.system(size: 14, weight: .medium))
                .padding(.bottom, 20)
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    private var accountForm: some View {
        formScroll {
            notice("person.crop.circle.badge.checkmark", tr("addServer.accountNotice"), color: t.info)
            field(tr("addServer.serverName"), text: $name, hint: tr("addServer.serverNameHint"), contentType: .organizationName)
            field(tr("addServer.serverUrl"), text: $url, hint: "https://server.example.com", keyboard: .URL, contentType: .URL, capitalization: .never)
            field(tr("addServer.username"), text: $username, hint: tr("server.usernameHint"), contentType: .username, capitalization: .never)
            field(tr("addServer.password"), text: $password, hint: tr("server.passwordHint"), secure: true, contentType: .password)
            if let error { errorBanner(error) }
            NanoButton(tr("addServer.login"), icon: "arrow.right.circle", fullWidth: true, loading: loading) {
                submitAccount()
            }
            HStack {
                Button(tr("addServer.forgotPassword")) { error = tr("addServer.forgotPasswordHint") }
                Spacer()
                Button(tr("addServer.ssoLogin")) { error = tr("addServer.ssoHint") }
            }
            .font(.system(size: 12.5))
            .foregroundColor(t.accent)
        }
    }

    private var manualForm: some View {
        formScroll {
            field(tr("addServer.serverName"), text: $name, hint: tr("addServer.serverNameHint"), contentType: .organizationName)
            field(tr("addServer.serverUrl"), text: $url, hint: "https://server.example.com", keyboard: .URL, contentType: .URL, capitalization: .never)
            field(tr("addServer.deviceTokenOptional"), text: $token, hint: tr("addServer.deviceTokenHint"), secure: true, capitalization: .never)

            Button { withAnimation { advanced.toggle() } } label: {
                HStack {
                    Text(tr("addServer.advanced"))
                    Spacer()
                    Image(systemName: advanced ? "chevron.up" : "chevron.down")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(t.fg2)
            }
            .buttonStyle(.plain)

            if advanced {
                field(tr("addServer.deviceName"), text: $deviceName, hint: tr("addServer.deviceNameHint"), contentType: .name)
                toggleRow(tr("addServer.forceTls"), value: $forceTls)
                toggleRow(tr("addServer.ignoreCert"), value: $ignoreCert)
            }
            if let error { errorBanner(error) }
            NanoButton(tr("addServer.connect"), icon: "link", fullWidth: true, loading: loading) {
                submitManual()
            }
        }
    }

    private var pairingForm: some View {
        formScroll {
            notice("number.square", tr("addServer.pairingNotice"), color: t.info)
            field(tr("addServer.serverName"), text: $name, hint: tr("addServer.serverNameHint"), contentType: .organizationName)
            field(tr("addServer.serverUrl"), text: $url, hint: "https://server.example.com", keyboard: .URL, contentType: .URL, capitalization: .never)

            VStack(spacing: 12) {
                HStack(spacing: 7) {
                    ForEach(0..<6, id: \.self) { index in
                        if index == 3 { Text("·").foregroundColor(t.fg4).font(.title2) }
                        digitBox(index)
                    }
                }
                pairingStatus
                numberPad
            }
            .padding(.vertical, 8)
            if let error { errorBanner(error) }
        }
    }

    private func digitBox(_ index: Int) -> some View {
        let chars = Array(pairingCode)
        return Text(index < chars.count ? String(chars[index]) : "")
            .font(NanoFont.mono(23, weight: .bold))
            .foregroundColor(t.fg)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(t.card)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(index == chars.count && chars.count < 6 ? t.accent : t.sep, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var pairingStatus: some View {
        switch pairingState {
        case .verifying:
            HStack(spacing: 8) { ProgressView(); Text(tr("addServer.pairingVerifying")) }.foregroundColor(t.fg3)
        case .success:
            Text(tr("addServer.pairingPaired")).foregroundColor(t.ok)
        case .invalid:
            Text(tr("addServer.pairingInvalid")).foregroundColor(t.crit)
        case .input:
            Text(tr("addServer.pairingValid60s") + " · \(pairingRemaining)s")
                .foregroundColor(pairingRemaining < 10 ? t.warn : t.fg4)
        }
    }

    private var numberPad: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(["1","2","3","4","5","6","7","8","9","","0","⌫"], id: \.self) { value in
                if value.isEmpty { Color.clear.frame(height: 48) }
                else {
                    Button { numberTapped(value) } label: {
                        Text(value).font(.system(size: value == "⌫" ? 20 : 22, weight: .medium)).foregroundColor(t.fg)
                            .frame(maxWidth: .infinity).frame(height: 48).background(t.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }.buttonStyle(.plain).disabled(pairingState == .verifying)
                }
            }
        }
    }

    private func formScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content() }
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func field(_ label: String, text: Binding<String>, hint: String,
                       secure: Bool = false, keyboard: UIKeyboardType = .default,
                       contentType: UITextContentType? = nil,
                       capitalization: TextInputAutocapitalization = .sentences) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 12.5, weight: .medium)).foregroundColor(t.fg3)
            Group {
                if secure { SecureField(hint, text: text) }
                else { TextField(hint, text: text) }
            }
            .keyboardType(keyboard)
            .textContentType(contentType)
            .textInputAutocapitalization(capitalization)
            .autocorrectionDisabled(capitalization == .never)
            .font(.system(size: 15))
            .foregroundColor(t.fg)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(t.card)
            .overlay(RoundedRectangle(cornerRadius: t.fieldRadius).stroke(t.isIOS ? .clear : t.sep, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: t.fieldRadius, style: .continuous))
        }
    }

    private func toggleRow(_ label: String, value: Binding<Bool>) -> some View {
        HStack { Text(label).font(.system(size: 14)).foregroundColor(t.fg2); Spacer(); Toggle("", isOn: value).labelsHidden() }
            .padding(.horizontal, 14).frame(height: 48).background(t.card)
            .clipShape(RoundedRectangle(cornerRadius: t.fieldRadius, style: .continuous))
    }

    private func notice(_ icon: String, _ text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundColor(color)
            Text(text).font(.system(size: 12.5)).foregroundColor(t.fg2).lineSpacing(4)
        }
        .padding(14).background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(t.crit)
            Text(message).font(.system(size: 12.5)).foregroundColor(t.fg2)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(t.crit.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func resetMethod() {
        countdownTask?.cancel()
        qrRestartTask?.cancel()
        method = nil
        error = nil
        loading = false
        torchOn = false
        qrIdentity = nil
        pairingState = .input
        pairingCode = ""
    }

    private func validatedBasics(needsName: Bool = true) -> Bool {
        if needsName && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = tr("addServer.nameRequired"); return false
        }
        let raw = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { error = tr("addServer.urlRequired"); return false }
        guard let parsed = URL(string: raw), parsed.host != nil,
              parsed.scheme == "http" || parsed.scheme == "https" else {
            error = tr("addServer.urlInvalid"); return false
        }
        error = nil
        return true
    }

    private func submitManual() {
        guard validatedBasics() else { return }
        loading = true
        Task {
            let ok = await store.addServer(name: name.trimmed, url: url.trimmed,
                                           token: token.trimmed.nilIfEmpty,
                                           forceTls: forceTls, ignoreCert: ignoreCert)
            loading = false
            if ok { dismiss() } else { error = tr("addServer.connectionFailed") }
        }
    }

    private func submitAccount() {
        guard validatedBasics() else { return }
        guard !username.trimmed.isEmpty else { error = tr("addServer.usernameRequired"); return }
        guard !password.isEmpty else { error = tr("addServer.passwordRequired"); return }
        loading = true
        Task {
            let ok = await store.addServerWithCredentials(name: name.trimmed, url: url.trimmed,
                                                           username: username.trimmed, password: password)
            loading = false
            if ok { dismiss() } else { error = tr("addServer.loginFailed") }
        }
    }

    private func processQr(_ raw: String) {
        guard !loading else { return }
        loading = true
        error = nil
        let data = Data(base64Encoded: raw) ?? Data(raw.utf8)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["v"] as? NSNumber)?.intValue == 1,
              let qrUrl = obj["s"] as? String,
              let qrToken = obj["t"] as? String else {
            loading = false
            error = tr("addServer.qrInvalid")
            restartQrScanner()
            return
        }
        let qrName = (obj["n"] as? String)?.trimmed.nilIfEmpty ?? tr("addServer.defaultServerName")
        qrIdentity = "\(qrName) · \(qrUrl)"
        Task {
            let ok = await store.addServer(name: qrName, url: qrUrl, token: qrToken)
            loading = false
            if ok {
                dismiss()
            } else {
                error = tr("addServer.connectionFailed")
                restartQrScanner()
            }
        }
    }

    private func handleQrFailure(_ failure: QRScannerFailure) {
        loading = false
        torchOn = false
        switch failure {
        case .permissionDenied:
            error = tr("addServer.qrPermissionDenied")
        case .unavailable:
            error = tr("addServer.qrUnavailable")
        }
    }

    private func restartQrScanner() {
        qrRestartTask?.cancel()
        torchOn = false
        qrRestartTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, method == .qrCode else { return }
            qrIdentity = nil
            qrScanID = UUID()
        }
    }

    private func numberTapped(_ key: String) {
        if key == "⌫" {
            if !pairingCode.isEmpty { pairingCode.removeLast() }
            pairingState = .input
            return
        }
        guard pairingCode.count < 6 else { return }
        pairingCode.append(key)
        pairingState = .input
        if pairingCode.count == 6 { verifyPairing() }
    }

    private func verifyPairing() {
        guard pairingCode.count == 6 else { error = tr("addServer.pairingCodeInvalid"); return }
        guard validatedBasics() else { pairingCode = ""; return }
        pairingState = .verifying
        error = nil
        Task {
            let ok = await store.addServerWithPairingCode(name: name.trimmed, url: url.trimmed,
                                                           pairingCode: pairingCode)
            if ok {
                pairingState = .success
                try? await Task.sleep(nanoseconds: 450_000_000)
                dismiss()
            } else {
                pairingState = .invalid
                error = tr("addServer.pairingFailed")
                pairingCode = ""
            }
        }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        pairingRemaining = 60
        countdownTask = Task {
            while !Task.isCancelled && pairingRemaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                pairingRemaining -= 1
            }
        }
    }
}

private struct ScanFrame: Shape {
    func path(in rect: CGRect) -> Path {
        let l: CGFloat = 38
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + l)); p.addLine(to: CGPoint(x: rect.minX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        p.move(to: CGPoint(x: rect.maxX - l, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX + l, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        return p
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
