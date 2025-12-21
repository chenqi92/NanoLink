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

/// CPU metrics
class CpuMetrics {
  final double usagePercent;
  final int coreCount;
  final List<double> perCoreUsage;
  final String model;
  final double temperature;

  CpuMetrics({
    required this.usagePercent,
    this.coreCount = 0,
    this.perCoreUsage = const [],
    this.model = '',
    this.temperature = 0,
  });

  factory CpuMetrics.fromJson(Map<String, dynamic>? json) {
    if (json == null) return CpuMetrics(usagePercent: 0);
    return CpuMetrics(
      usagePercent: (json['percent'] as num?)?.toDouble() ?? 
                   (json['usagePercent'] as num?)?.toDouble() ?? 0,
      coreCount: json['coreCount'] as int? ?? 0,
      perCoreUsage: (json['perCoreUsage'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ?? [],
      model: json['model'] as String? ?? '',
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Memory metrics
class MemoryMetrics {
  final int total;
  final int used;
  final int available;
  final int swapTotal;
  final int swapUsed;

  MemoryMetrics({
    required this.total,
    required this.used,
    this.available = 0,
    this.swapTotal = 0,
    this.swapUsed = 0,
  });

  double get usagePercent => total > 0 ? (used / total) * 100 : 0;

  factory MemoryMetrics.fromJson(Map<String, dynamic>? json) {
    if (json == null) return MemoryMetrics(total: 0, used: 0);
    return MemoryMetrics(
      total: json['total'] as int? ?? 0,
      used: json['used'] as int? ?? 0,
      available: json['available'] as int? ?? 0,
      swapTotal: json['swapTotal'] as int? ?? 0,
      swapUsed: json['swapUsed'] as int? ?? 0,
    );
  }
}

/// Disk metrics
class DiskMetrics {
  final String mountPoint;
  final String device;
  final String fsType;
  final int total;
  final int used;
  final int available;
  final double readBytesPerSec;
  final double writeBytesPerSec;

  DiskMetrics({
    required this.mountPoint,
    this.device = '',
    this.fsType = '',
    required this.total,
    required this.used,
    this.available = 0,
    this.readBytesPerSec = 0,
    this.writeBytesPerSec = 0,
  });

  double get usagePercent => total > 0 ? (used / total) * 100 : 0;

  factory DiskMetrics.fromJson(Map<String, dynamic> json) {
    return DiskMetrics(
      mountPoint: json['mountPoint'] as String? ?? json['mount'] as String? ?? '/',
      device: json['device'] as String? ?? '',
      fsType: json['fsType'] as String? ?? '',
      total: json['total'] as int? ?? 0,
      used: json['used'] as int? ?? 0,
      available: json['available'] as int? ?? 0,
      readBytesPerSec: (json['readBytesPerSec'] as num?)?.toDouble() ?? 0,
      writeBytesPerSec: (json['writeBytesPerSec'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Network interface metrics
class NetworkMetrics {
  final String interface_;
  final int rxBytesPerSec;
  final int txBytesPerSec;
  final bool isUp;
  final String macAddress;
  final List<String> ipAddresses;
  final int speedMbps;
  final String interfaceType;

  NetworkMetrics({
    required this.interface_,
    required this.rxBytesPerSec,
    required this.txBytesPerSec,
    this.isUp = true,
    this.macAddress = '',
    this.ipAddresses = const [],
    this.speedMbps = 0,
    this.interfaceType = '',
  });

  factory NetworkMetrics.fromJson(Map<String, dynamic> json) {
    return NetworkMetrics(
      interface_: json['interface'] as String? ?? json['name'] as String? ?? 'eth0',
      rxBytesPerSec: json['rxBytesPerSec'] as int? ?? 
                     (json['bytesRecv'] as num?)?.toInt() ?? 0,
      txBytesPerSec: json['txBytesPerSec'] as int? ?? 
                     (json['bytesSent'] as num?)?.toInt() ?? 0,
      isUp: json['isUp'] as bool? ?? true,
      macAddress: json['macAddress'] as String? ?? '',
      ipAddresses: (json['ipAddresses'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ?? [],
      speedMbps: json['speedMbps'] as int? ?? 0,
      interfaceType: json['interfaceType'] as String? ?? '',
    );
  }
}

/// GPU metrics
class GpuMetrics {
  final int index;
  final String name;
  final String vendor;
  final double usagePercent;
  final int memoryTotal;
  final int memoryUsed;
  final double temperature;
  final int powerWatts;
  final int fanSpeedPercent;
  final String driverVersion;

  GpuMetrics({
    required this.index,
    required this.name,
    this.vendor = '',
    required this.usagePercent,
    this.memoryTotal = 0,
    this.memoryUsed = 0,
    this.temperature = 0,
    this.powerWatts = 0,
    this.fanSpeedPercent = 0,
    this.driverVersion = '',
  });

  double get memoryPercent => memoryTotal > 0 ? (memoryUsed / memoryTotal) * 100 : 0;

  factory GpuMetrics.fromJson(Map<String, dynamic> json) {
    return GpuMetrics(
      index: json['index'] as int? ?? 0,
      name: json['name'] as String? ?? 'GPU',
      vendor: json['vendor'] as String? ?? '',
      usagePercent: (json['usagePercent'] as num?)?.toDouble() ?? 0,
      memoryTotal: json['memoryTotal'] as int? ?? 0,
      memoryUsed: json['memoryUsed'] as int? ?? 0,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0,
      powerWatts: json['powerWatts'] as int? ?? 0,
      fanSpeedPercent: json['fanSpeedPercent'] as int? ?? 0,
      driverVersion: json['driverVersion'] as String? ?? '',
    );
  }
}

/// NPU metrics
class NpuMetrics {
  final int index;
  final String name;
  final String vendor;
  final double usagePercent;
  final int memoryTotal;
  final int memoryUsed;
  final double temperature;
  final int powerWatts;

  NpuMetrics({
    required this.index,
    required this.name,
    this.vendor = '',
    required this.usagePercent,
    this.memoryTotal = 0,
    this.memoryUsed = 0,
    this.temperature = 0,
    this.powerWatts = 0,
  });

  factory NpuMetrics.fromJson(Map<String, dynamic> json) {
    return NpuMetrics(
      index: json['index'] as int? ?? 0,
      name: json['name'] as String? ?? 'NPU',
      vendor: json['vendor'] as String? ?? '',
      usagePercent: (json['usagePercent'] as num?)?.toDouble() ?? 0,
      memoryTotal: json['memoryTotal'] as int? ?? 0,
      memoryUsed: json['memoryUsed'] as int? ?? 0,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0,
      powerWatts: json['powerWatts'] as int? ?? 0,
    );
  }
}

/// User session info
class UserSession {
  final String username;
  final String tty;
  final int loginTime;
  final String remoteHost;
  final int idleSeconds;
  final String sessionType;

  UserSession({
    required this.username,
    required this.tty,
    required this.loginTime,
    this.remoteHost = '',
    this.idleSeconds = 0,
    this.sessionType = '',
  });

  factory UserSession.fromJson(Map<String, dynamic> json) {
    return UserSession(
      username: json['username'] as String? ?? '',
      tty: json['tty'] as String? ?? '',
      loginTime: json['loginTime'] as int? ?? 0,
      remoteHost: json['remoteHost'] as String? ?? '',
      idleSeconds: json['idleSeconds'] as int? ?? 0,
      sessionType: json['sessionType'] as String? ?? '',
    );
  }
}

/// System info
class SystemInfo {
  final String osName;
  final String osVersion;
  final String kernelVersion;
  final String hostname;
  final int bootTime;
  final int uptimeSeconds;
  final String motherboardModel;
  final String motherboardVendor;
  final String biosVersion;
  final String systemModel;
  final String systemVendor;

  SystemInfo({
    this.osName = '',
    this.osVersion = '',
    this.kernelVersion = '',
    this.hostname = '',
    this.bootTime = 0,
    this.uptimeSeconds = 0,
    this.motherboardModel = '',
    this.motherboardVendor = '',
    this.biosVersion = '',
    this.systemModel = '',
    this.systemVendor = '',
  });

  factory SystemInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return SystemInfo();
    return SystemInfo(
      osName: json['osName'] as String? ?? '',
      osVersion: json['osVersion'] as String? ?? '',
      kernelVersion: json['kernelVersion'] as String? ?? '',
      hostname: json['hostname'] as String? ?? '',
      bootTime: json['bootTime'] as int? ?? 0,
      uptimeSeconds: json['uptimeSeconds'] as int? ?? 0,
      motherboardModel: json['motherboardModel'] as String? ?? '',
      motherboardVendor: json['motherboardVendor'] as String? ?? '',
      biosVersion: json['biosVersion'] as String? ?? '',
      systemModel: json['systemModel'] as String? ?? '',
      systemVendor: json['systemVendor'] as String? ?? '',
    );
  }
}

/// Complete agent metrics model
class AgentMetrics {
  final String agentId;
  final CpuMetrics cpu;
  final MemoryMetrics memory;
  final List<DiskMetrics> disks;
  final List<NetworkMetrics> networks;
  final List<GpuMetrics> gpus;
  final List<NpuMetrics> npus;
  final List<UserSession> userSessions;
  final SystemInfo? systemInfo;
  final DateTime timestamp;

  AgentMetrics({
    required this.agentId,
    required this.cpu,
    required this.memory,
    this.disks = const [],
    this.networks = const [],
    this.gpus = const [],
    this.npus = const [],
    this.userSessions = const [],
    this.systemInfo,
    required this.timestamp,
  });

  /// Legacy getters for backward compatibility
  double get cpuPercent => cpu.usagePercent;
  double get memoryPercent => memory.usagePercent;
  double get diskPercent => disks.isNotEmpty ? disks.first.usagePercent : 0;
  int get networkIn => networks.fold(0, (sum, n) => sum + n.rxBytesPerSec);
  int get networkOut => networks.fold(0, (sum, n) => sum + n.txBytesPerSec);

  factory AgentMetrics.fromJson(Map<String, dynamic> json, String agentId) {
    // Parse CPU
    final cpuJson = json['cpu'] as Map<String, dynamic>?;
    final cpu = CpuMetrics.fromJson(cpuJson);

    // Parse Memory
    final memoryJson = json['memory'] as Map<String, dynamic>?;
    final memory = MemoryMetrics.fromJson(memoryJson);

    // Parse Disks (can be single 'disk' or array 'disks')
    List<DiskMetrics> disks = [];
    if (json['disks'] != null) {
      disks = (json['disks'] as List<dynamic>)
          .map((d) => DiskMetrics.fromJson(d as Map<String, dynamic>))
          .toList();
    } else if (json['disk'] != null) {
      disks = [DiskMetrics.fromJson(json['disk'] as Map<String, dynamic>)];
    }

    // Parse Networks (can be single 'network' or array 'networks')
    List<NetworkMetrics> networks = [];
    if (json['networks'] != null) {
      networks = (json['networks'] as List<dynamic>)
          .map((n) => NetworkMetrics.fromJson(n as Map<String, dynamic>))
          .toList();
    } else if (json['network'] != null) {
      networks = [NetworkMetrics.fromJson(json['network'] as Map<String, dynamic>)];
    }

    // Parse GPUs
    List<GpuMetrics> gpus = [];
    if (json['gpus'] != null) {
      gpus = (json['gpus'] as List<dynamic>)
          .map((g) => GpuMetrics.fromJson(g as Map<String, dynamic>))
          .toList();
    } else if (json['gpu'] != null) {
      gpus = [GpuMetrics.fromJson(json['gpu'] as Map<String, dynamic>)];
    }

    // Parse NPUs
    List<NpuMetrics> npus = [];
    if (json['npus'] != null) {
      npus = (json['npus'] as List<dynamic>)
          .map((n) => NpuMetrics.fromJson(n as Map<String, dynamic>))
          .toList();
    }

    // Parse User Sessions
    List<UserSession> userSessions = [];
    if (json['userSessions'] != null) {
      userSessions = (json['userSessions'] as List<dynamic>)
          .map((s) => UserSession.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    // Parse System Info
    final systemInfo = json['systemInfo'] != null
        ? SystemInfo.fromJson(json['systemInfo'] as Map<String, dynamic>)
        : null;

    return AgentMetrics(
      agentId: agentId,
      cpu: cpu,
      memory: memory,
      disks: disks,
      networks: networks,
      gpus: gpus,
      npus: npus,
      userSessions: userSessions,
      systemInfo: systemInfo,
      timestamp: DateTime.now(),
    );
  }
}
