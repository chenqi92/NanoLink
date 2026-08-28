import Foundation

/// Persists server connections: non-secret metadata goes to `UserDefaults` (via
/// `PreferencesStore`), while
/// secrets (`token` / `userToken`) live in the Keychain keyed by server id.
final class StorageService {
    static let shared = StorageService()
    private init() {}

    private func tokenKey(_ id: String) -> String { "token_\(id)" }
    private func userTokenKey(_ id: String) -> String { "userToken_\(id)" }

    /// Load all saved servers, hydrating secrets from the Keychain.
    func getServers() -> [ServerConnection] {
        var servers = PreferencesStore.loadServers()
        for i in servers.indices {
            servers[i].token = KeychainStore.get(tokenKey(servers[i].id))
            servers[i].userToken = KeychainStore.get(userTokenKey(servers[i].id))
        }
        return servers
    }

    /// Persist the given servers: secrets → Keychain, metadata → UserDefaults.
    func saveServers(_ servers: [ServerConnection]) {
        for s in servers {
            KeychainStore.set(s.token, for: tokenKey(s.id))
            KeychainStore.set(s.userToken, for: userTokenKey(s.id))
        }
        PreferencesStore.saveServers(servers)
    }

    func addServer(_ server: ServerConnection) {
        var servers = getServers()
        servers.append(server)
        saveServers(servers)
    }

    func updateServer(_ server: ServerConnection) {
        var servers = getServers()
        if let idx = servers.firstIndex(where: { $0.id == server.id }) {
            servers[idx] = server
            saveServers(servers)
        }
    }

    func deleteServer(_ serverId: String) {
        var servers = getServers()
        servers.removeAll { $0.id == serverId }
        KeychainStore.remove(tokenKey(serverId))
        KeychainStore.remove(userTokenKey(serverId))
        saveServers(servers)
    }
}
