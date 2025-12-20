import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

/// Service for storing and managing server connections
class StorageService {
  static const String _serversKey = 'nanolink_servers';

  /// Get all saved server connections
  Future<List<ServerConnection>> getServers() async {
    final prefs = await SharedPreferences.getInstance();
    final serversJson = prefs.getString(_serversKey);
    if (serversJson == null) return [];

    try {
      final List<dynamic> data = jsonDecode(serversJson) as List<dynamic>;
      return data
          .map((json) => ServerConnection.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Save server connections
  Future<void> saveServers(List<ServerConnection> servers) async {
    final prefs = await SharedPreferences.getInstance();
    final serversJson = jsonEncode(servers.map((s) => s.toJson()).toList());
    await prefs.setString(_serversKey, serversJson);
  }

  /// Add a new server connection
  Future<void> addServer(ServerConnection server) async {
    final servers = await getServers();
    servers.add(server);
    await saveServers(servers);
  }

  /// Update a server connection
  Future<void> updateServer(ServerConnection server) async {
    final servers = await getServers();
    final index = servers.indexWhere((s) => s.id == server.id);
    if (index != -1) {
      servers[index] = server;
      await saveServers(servers);
    }
  }

  /// Delete a server connection
  Future<void> deleteServer(String serverId) async {
    final servers = await getServers();
    servers.removeWhere((s) => s.id == serverId);
    await saveServers(servers);
  }
}
