import Foundation

/// Typed accessors over `UserDefaults` for non-secret app configuration such as
/// the selected
/// theme, language, active server id, and the persisted server metadata list.
enum PreferencesStore {
    private static let d = UserDefaults.standard

    enum Key {
        static let servers = "servers_metadata"     // JSON array of ServerConnection metadata
        static let activeServer = "active_server_id"
        static let themeMode = "theme_mode"
        static let themeStyle = "theme_style"        // ios | md
        static let language = "app_language"
        static let notificationsEnabled = "notifications_enabled"
        static let clientVersion = "client_version"
    }

    // MARK: Servers

    static func loadServers() -> [ServerConnection] {
        guard let raw = d.string(forKey: Key.servers),
              let data = raw.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return arr.compactMap { ServerConnection.fromMetadata(JSON($0)) }
    }

    static func saveServers(_ servers: [ServerConnection]) {
        let arr = servers.map { $0.metadataDict() }
        guard let data = try? JSONSerialization.data(withJSONObject: arr),
              let str = String(data: data, encoding: .utf8) else { return }
        d.set(str, forKey: Key.servers)
    }

    // MARK: Scalars

    static var activeServerId: String? {
        get { d.string(forKey: Key.activeServer) }
        set { d.set(newValue, forKey: Key.activeServer) }
    }

    /// Stringified `AppThemeMode` raw value; defaults to `system` (2) so an
    /// install with no stored preference follows the OS appearance.
    static var themeMode: String {
        get { d.string(forKey: Key.themeMode) ?? String(AppThemeMode.system.rawValue) }
        set { d.set(newValue, forKey: Key.themeMode) }
    }

    static var themeStyle: String {
        get { d.string(forKey: Key.themeStyle) ?? "ios" }
        set { d.set(newValue, forKey: Key.themeStyle) }
    }

    static var notificationsEnabled: Bool {
        get { d.object(forKey: Key.notificationsEnabled) as? Bool ?? true }
        set { d.set(newValue, forKey: Key.notificationsEnabled) }
    }
}
