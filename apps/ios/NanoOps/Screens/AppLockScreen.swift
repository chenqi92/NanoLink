import SwiftUI

struct AppLockScreen: View {
    @EnvironmentObject private var appLock: AppLockStore
    @Environment(\.nano) private var t

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "faceid")
                .font(.system(size: 52, weight: .light))
                .foregroundColor(t.accent)
            Text(tr("security.lockedTitle"))
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(t.fg)
            Text(tr("security.lockedBody"))
                .font(.system(size: 13.5))
                .foregroundColor(t.fg3)
                .multilineTextAlignment(.center)
            if let error = appLock.errorMessage {
                Text(error)
                    .font(.system(size: 12.5))
                    .foregroundColor(t.crit)
                    .multilineTextAlignment(.center)
            }
            NanoButton(tr("security.unlock"), icon: "faceid", fullWidth: true) {
                appLock.authenticate()
            }
            .frame(maxWidth: 280)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.bg.ignoresSafeArea())
        .onAppear { appLock.authenticate() }
    }
}
