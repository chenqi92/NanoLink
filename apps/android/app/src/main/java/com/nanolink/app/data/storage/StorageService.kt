package com.nanolink.app.data.storage

import com.nanolink.app.data.model.NanoJson
import com.nanolink.app.data.model.ServerConnection
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.encodeToString

@Serializable
private data class ServerMetadata(
    val id: String,
    val name: String,
    val url: String,
    val username: String? = null,
    val lastConnectedMillis: Long? = null,
    val forceTls: Boolean = false,
    val ignoreCert: Boolean = false,
)

class StorageService(
    private val preferences: PreferencesStore,
    private val secureStore: SecureStore,
) {
    private fun tokenKey(id: String) = "token_$id"
    private fun userTokenKey(id: String) = "userToken_$id"

    suspend fun getServers(): List<ServerConnection> {
        val raw = preferences.get(PreferenceKeys.Servers, "[]")
        val metadata = runCatching {
            NanoJson.decodeFromString(ListSerializer(ServerMetadata.serializer()), raw)
        }.getOrDefault(emptyList())
        return metadata.map { server ->
            ServerConnection(
                id = server.id,
                name = server.name,
                url = server.url,
                token = secureStore.get(tokenKey(server.id)),
                userToken = secureStore.get(userTokenKey(server.id)),
                username = server.username,
                lastConnectedMillis = server.lastConnectedMillis,
                forceTls = server.forceTls,
                ignoreCert = server.ignoreCert,
            )
        }
    }

    suspend fun saveServers(servers: List<ServerConnection>) {
        servers.forEach { server ->
            secureStore.set(tokenKey(server.id), server.token)
            secureStore.set(userTokenKey(server.id), server.userToken)
        }
        val metadata = servers.map { server ->
            ServerMetadata(
                id = server.id,
                name = server.name,
                url = server.url,
                username = server.username,
                lastConnectedMillis = server.lastConnectedMillis,
                forceTls = server.forceTls,
                ignoreCert = server.ignoreCert,
            )
        }
        preferences.set(PreferenceKeys.Servers, NanoJson.encodeToString(metadata))
    }

    suspend fun deleteServer(serverId: String) {
        saveServers(getServers().filterNot { it.id == serverId })
        secureStore.remove(tokenKey(serverId))
        secureStore.remove(userTokenKey(serverId))
    }
}
