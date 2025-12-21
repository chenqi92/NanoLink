import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

/// Utility class for formatting values
class Formatter {
  static String bytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String bytesPerSec(int bytesValue) => '${bytes(bytesValue)}/s';

  static String percent(double value) => '${value.toStringAsFixed(1)}%';

  static String uptime(int seconds) {
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (days > 0) return '${days}d ${hours}h';
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }
}

/// Enhanced card widget displaying agent information and real-time metrics
class AgentCard extends StatelessWidget {
  final Agent agent;
  final AgentMetrics? metrics;
  final String serverName;
  final VoidCallback? onTap;

  const AgentCard({
    super.key,
    required this.agent,
    this.metrics,
    required this.serverName,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: isDark
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.cardTheme.color ?? const Color(0xFF1E293B),
                      const Color(0xFF1E293B).withValues(alpha: 0.8),
                    ],
                  )
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                _buildHeader(context),
                const SizedBox(height: 12),
                
                // Server badge
                _buildServerBadge(context),
                const SizedBox(height: 16),
                
                // Metrics
                Expanded(
                  child: metrics != null
                      ? _buildMetrics(context)
                      : _buildLoadingState(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    
    return Row(
      children: [
        // OS Icon with background
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _getOsColor(agent.os).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _getOsIcon(agent.os),
            color: _getOsColor(agent.os),
            size: 24,
          ),
        ),
        const SizedBox(width: 12),
        
        // Hostname and OS info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                agent.hostname,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${agent.os} • ${agent.arch}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        
        // Online indicator
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.successGreen,
            boxShadow: [
              BoxShadow(
                color: AppTheme.successGreen.withValues(alpha: 0.4),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildServerBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.dns_outlined,
            size: 12,
            color: AppTheme.primaryBlue,
          ),
          const SizedBox(width: 6),
          Text(
            serverName,
            style: TextStyle(
              color: AppTheme.primaryBlue,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetrics(BuildContext context) {
    final m = metrics!;
    
    return Column(
      children: [
        // CPU & Memory
        _buildMetricRow(
          context,
          icon: Icons.memory,
          label: 'CPU',
          value: m.cpuPercent,
          color: AppTheme.primaryBlue,
        ),
        const SizedBox(height: 8),
        _buildMetricRow(
          context,
          icon: Icons.storage_rounded,
          label: 'RAM',
          value: m.memoryPercent,
          color: AppTheme.successGreen,
          subtitle: '${Formatter.bytes(m.memory.used)} / ${Formatter.bytes(m.memory.total)}',
        ),
        const SizedBox(height: 8),
        _buildMetricRow(
          context,
          icon: Icons.folder_open,
          label: 'Disk',
          value: m.diskPercent,
          color: AppTheme.warningYellow,
        ),
        
        const Spacer(),
        
        // Network speed
        if (m.networks.isNotEmpty) ...[
          const Divider(height: 16),
          _buildNetworkRow(context, m),
        ],
        
        // GPU indicator
        if (m.gpus.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildGpuIndicator(context, m.gpus.first),
        ],
      ],
    );
  }

  Widget _buildMetricRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required double value,
    required Color color,
    String? subtitle,
  }) {
    final theme = Theme.of(context);
    final statusColor = AppTheme.getStatusColor(value);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            if (subtitle != null) ...[
              const Spacer(),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                  fontSize: 10,
                ),
              ),
            ],
            const Spacer(),
            Text(
              Formatter.percent(value),
              style: theme.textTheme.bodySmall?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value / 100,
            backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation(statusColor),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkRow(BuildContext context, AgentMetrics m) {
    final theme = Theme.of(context);
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildNetworkStat(
          context,
          icon: Icons.arrow_downward,
          label: 'Download',
          value: m.networkIn,
          color: AppTheme.successGreen,
        ),
        Container(
          width: 1,
          height: 24,
          color: theme.dividerTheme.color,
        ),
        _buildNetworkStat(
          context,
          icon: Icons.arrow_upward,
          label: 'Upload',
          value: m.networkOut,
          color: AppTheme.primaryBlue,
        ),
      ],
    );
  }

  Widget _buildNetworkStat(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int value,
    required Color color,
  }) {
    final theme = Theme.of(context);
    
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              Formatter.bytesPerSec(value),
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildGpuIndicator(BuildContext context, GpuMetrics gpu) {
    final theme = Theme.of(context);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.gpuPurple.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.videocam,
            size: 14,
            color: AppTheme.gpuPurple,
          ),
          const SizedBox(width: 6),
          Text(
            gpu.name.length > 15 ? '${gpu.name.substring(0, 15)}...' : gpu.name,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppTheme.gpuPurple,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            Formatter.percent(gpu.usagePercent),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppTheme.getStatusColor(gpu.usagePercent),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (gpu.temperature > 0) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.thermostat,
              size: 12,
              color: gpu.temperature > 80 ? AppTheme.errorRed : AppTheme.warningYellow,
            ),
            Text(
              '${gpu.temperature.toInt()}°',
              style: theme.textTheme.bodySmall?.copyWith(
                color: gpu.temperature > 80 ? AppTheme.errorRed : AppTheme.warningYellow,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final theme = Theme.of(context);
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Waiting for metrics...',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getOsIcon(String os) {
    final osLower = os.toLowerCase();
    if (osLower.contains('linux')) return Icons.terminal;
    if (osLower.contains('windows')) return Icons.window;
    if (osLower.contains('darwin') || osLower.contains('macos')) return Icons.laptop_mac;
    return Icons.computer;
  }

  Color _getOsColor(String os) {
    final osLower = os.toLowerCase();
    if (osLower.contains('linux')) return Colors.orange;
    if (osLower.contains('windows')) return AppTheme.primaryBlue;
    if (osLower.contains('darwin') || osLower.contains('macos')) return Colors.grey;
    return AppTheme.npuIndigo;
  }
}
