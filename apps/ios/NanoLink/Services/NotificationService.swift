import Foundation
import UserNotifications

/// Thin wrapper over UserNotifications for foreground alert pushes. Requests
/// authorization once, then posts local
/// notifications with a stable identifier so re-firing the same alert replaces
/// its banner instead of stacking duplicates.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    private var authorized = false
    private override init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.getNotificationSettings { [weak self] settings in
            self?.authorized = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
        }
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void = { _ in }) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, _ in
            self?.authorized = granted
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func refreshAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            self?.authorized = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
        }
    }

    /// Show a notification. `key` gives a stable id so re-firing the same alert
    /// replaces its banner instead of stacking duplicates.
    func show(key: String, title: String, body: String) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: key, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
