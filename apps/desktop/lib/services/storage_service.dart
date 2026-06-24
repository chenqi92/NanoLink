import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// Service for storing and managing server connections.
///
/// Non-secret metadata (id, name, url, username, lastConnected) is persisted in
/// [SharedPreferences]. Secret fields (token, userToken) are stored in
/// [FlutterSecureStorage], keyed by server id.
class StorageService {
  static const String _serversKey = 'nanolink_servers';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  String _tokenKey(String id) => 'token_$id';
  String _userTokenKey(String id) => 'userToken_$id';

  /// Get all saved server connections.
  ///
  /// Reads metadata from [SharedPreferences] and hydrates secrets from
  /// [FlutterSecureStorage]. Performs a one-time migration of any legacy
  /// plaintext secrets still present in the prefs JSON.
  Future<List<ServerConnection>> getServers() async {
    final prefs = await SharedPreferences.getInstance();
    final serversJson = prefs.getString(_serversKey);
    if (serversJson == null) return [];

    List<dynamic> data;
    try {
      data = jsonDecode(serversJson) as List<dynamic>;
    } catch (e) {
      return [];
    }

    var needsRewrite = false;
    final servers = <ServerConnection>[];

    for (final entry in data) {
      if (entry is! Map<String, dynamic>) continue;

      final server = ServerConnection.fromJson(entry);

      // Legacy migration: secrets still embedded in the prefs JSON.
      final legacyToken = entry['token'] as String?;
      final legacyUserToken = entry['userToken'] as String?;
      if (legacyToken != null || legacyUserToken != null) {
        await _writeSecret(_tokenKey(server.id), legacyToken);
        await _writeSecret(_userTokenKey(server.id), legacyUserToken);
        needsRewrite = true;
      }

      // Hydrate secrets from secure storage (falling back to legacy values).
      final token =
          await _secureStorage.read(key: _tokenKey(server.id)) ?? legacyToken;
      final userToken =
          await _secureStorage.read(key: _userTokenKey(server.id)) ??
              legacyUserToken;

      servers.add(server.copyWith(token: token, userToken: userToken));
    }

    // Rewrite the prefs JSON without secrets after migration.
    if (needsRewrite) {
      await _persistMetadata(prefs, servers);
    }

    return servers;
  }

  /// Save server connections.
  ///
  /// Secrets are written to [FlutterSecureStorage]; metadata is persisted as a
  /// sanitized JSON (without token/userToken) in [SharedPreferences].
  Future<void> saveServers(List<ServerConnection> servers) async {
    final prefs = await SharedPreferences.getInstance();

    for (final server in servers) {
      await _writeSecret(_tokenKey(server.id), server.token);
      await _writeSecret(_userTokenKey(server.id), server.userToken);
    }

    await _persistMetadata(prefs, servers);
  }

  /// Add a new server connection.
  Future<void> addServer(ServerConnection server) async {
    final servers = await getServers();
    servers.add(server);
    await saveServers(servers);
  }

  /// Update a server connection.
  Future<void> updateServer(ServerConnection server) async {
    final servers = await getServers();
    final index = servers.indexWhere((s) => s.id == server.id);
    if (index != -1) {
      servers[index] = server;
      await saveServers(servers);
    }
  }

  /// Delete a server connection.
  Future<void> deleteServer(String serverId) async {
    final servers = await getServers();
    servers.removeWhere((s) => s.id == serverId);
    await _secureStorage.delete(key: _tokenKey(serverId));
    await _secureStorage.delete(key: _userTokenKey(serverId));
    await saveServers(servers);
  }

  /// Read a boolean preference (defaults to [fallback] when unset).
  Future<bool> getBool(String key, {bool fallback = true}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? fallback;
  }

  /// Persist a boolean preference.
  Future<void> setBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  /// Write [value] to secure storage, deleting the key when [value] is null.
  Future<void> _writeSecret(String key, String? value) async {
    if (value == null) {
      await _secureStorage.delete(key: key);
    } else {
      await _secureStorage.write(key: key, value: value);
    }
  }

  /// Persist server metadata (without secrets) to [SharedPreferences].
  Future<void> _persistMetadata(
    SharedPreferences prefs,
    List<ServerConnection> servers,
  ) async {
    final serversJson =
        jsonEncode(servers.map((s) => s.toJsonMetadata()).toList());
    await prefs.setString(_serversKey, serversJson);
  }
}
