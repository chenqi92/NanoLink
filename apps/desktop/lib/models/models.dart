/// Server connection configuration model
class ServerConnection {
  final String id;
  final String name;
  final String url;
  final String? token;
  final bool isConnected;
  final DateTime? lastConnected;

  ServerConnection({
    required this.id,
    required this.name,
    required this.url,
    this.token,
    this.isConnected = false,
    this.lastConnected,
  });

  ServerConnection copyWith({
    String? id,
    String? name,
    String? url,
    String? token,
    bool? isConnected,
    DateTime? lastConnected,
  }) {
    return ServerConnection(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      token: token ?? this.token,
      isConnected: isConnected ?? this.isConnected,
      lastConnected: lastConnected ?? this.lastConnected,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'token': token,
        'lastConnected': lastConnected?.toIso8601String(),
      };

  factory ServerConnection.fromJson(Map<String, dynamic> json) {
    return ServerConnection(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      token: json['token'] as String?,
      lastConnected: json['lastConnected'] != null
          ? DateTime.parse(json['lastConnected'] as String)
          : null,
    );
  }
}

/// Agent information model
class Agent {
  final String id;
  final String serverId;
  final String hostname;
  final String os;
  final String arch;
  final String? version;
  final int permissionLevel;
  final DateTime connectedAt;
  final DateTime lastHeartbeat;

  Agent({
    required this.id,
    required this.serverId,
    required this.hostname,
    required this.os,
    required this.arch,
    this.version,
    required this.permissionLevel,
    required this.connectedAt,
    required this.lastHeartbeat,
  });

  factory Agent.fromJson(Map<String, dynamic> json, String serverId) {
    return Agent(
      id: json['id'] as String,
      serverId: serverId,
      hostname: json['hostname'] as String? ?? 'Unknown',
      os: json['os'] as String? ?? 'Unknown',
      arch: json['arch'] as String? ?? 'Unknown',
      version: json['version'] as String?,
      permissionLevel: json['permissionLevel'] as int? ?? 0,
      connectedAt: json['connectedAt'] != null
          ? DateTime.parse(json['connectedAt'] as String)
          : DateTime.now(),
      lastHeartbeat: json['lastHeartbeat'] != null
          ? DateTime.parse(json['lastHeartbeat'] as String)
          : DateTime.now(),
    );
  }
}

/// Agent metrics model
class AgentMetrics {
  final String agentId;
  final double cpuPercent;
  final double memoryPercent;
  final double diskPercent;
  final int networkIn;
  final int networkOut;
  final DateTime timestamp;

  AgentMetrics({
    required this.agentId,
    required this.cpuPercent,
    required this.memoryPercent,
    required this.diskPercent,
    required this.networkIn,
    required this.networkOut,
    required this.timestamp,
  });

  factory AgentMetrics.fromJson(Map<String, dynamic> json, String agentId) {
    final cpu = json['cpu'] as Map<String, dynamic>?;
    final memory = json['memory'] as Map<String, dynamic>?;
    final disk = json['disk'] as Map<String, dynamic>?;
    final network = json['network'] as Map<String, dynamic>?;

    return AgentMetrics(
      agentId: agentId,
      cpuPercent: (cpu?['percent'] as num?)?.toDouble() ?? 0.0,
      memoryPercent: (memory?['percent'] as num?)?.toDouble() ?? 0.0,
      diskPercent: (disk?['percent'] as num?)?.toDouble() ?? 0.0,
      networkIn: (network?['bytesRecv'] as num?)?.toInt() ?? 0,
      networkOut: (network?['bytesSent'] as num?)?.toInt() ?? 0,
      timestamp: DateTime.now(),
    );
  }
}
