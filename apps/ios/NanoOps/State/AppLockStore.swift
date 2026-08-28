import Foundation
import Combine
import LocalAuthentication

@MainActor
final class AppLockStore: ObservableObject {
    static let shared = AppLockStore()

    @Published private(set) var isLocked = false
    @Published private(set) var errorMessage: String?

    private var backgroundedAt: Date?
    private var authenticationInFlight = false
    private let defaults = UserDefaults.standard

    private init() {
        isLocked = defaults.bool(forKey: AppPreferenceKey.faceId)
    }

    private var faceIDEnabled: Bool { defaults.bool(forKey: AppPreferenceKey.faceId) }
    private var autoLockMinutes: Int {
        defaults.object(forKey: AppPreferenceKey.autoLock) == nil
            ? 2
            : defaults.integer(forKey: AppPreferenceKey.autoLock)
    }

    func sceneDidEnterBackground() {
        backgroundedAt = Date()
    }

    func sceneDidBecomeActive() {
        guard faceIDEnabled else {
            isLocked = false
            errorMessage = nil
            backgroundedAt = nil
            return
        }

        if autoLockMinutes > 0, let backgroundedAt {
            let delay = TimeInterval(autoLockMinutes * 60)
            if Date().timeIntervalSince(backgroundedAt) >= delay { lock() }
        }
        backgroundedAt = nil
        if isLocked { authenticate() }
    }

    func lock() {
        guard faceIDEnabled else { return }
        isLocked = true
        errorMessage = nil
    }

    func authorizeProtection() async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            errorMessage = error?.localizedDescription ?? tr("security.unavailable")
            return false
        }
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                             localizedReason: tr("security.enableReason"))
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func disableProtection() {
        isLocked = false
        errorMessage = nil
        backgroundedAt = nil
    }

    func authenticate() {
        guard isLocked, !authenticationInFlight else { return }
        authenticationInFlight = true
        errorMessage = nil

        let context = LAContext()
        context.localizedCancelTitle = tr("security.cancel")
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authenticationInFlight = false
            errorMessage = error?.localizedDescription ?? tr("security.unavailable")
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: tr("security.unlockReason")) { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                self.authenticationInFlight = false
                if success {
                    self.isLocked = false
                    self.errorMessage = nil
                } else {
                    self.errorMessage = error?.localizedDescription ?? tr("security.failed")
                }
            }
        }
    }
}
