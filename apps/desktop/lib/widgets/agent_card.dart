import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

/// Utility class for formatting values
class Formatter {
  static String bytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
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

/// Enhanced card widget displaying agent information with Glassmorphism effect
class AgentCard extends StatefulWidget {
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
  State<AgentCard> createState() => _AgentCardState();
}

class _AgentCardState extends State<AgentCard>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHoverChanged(bool isHovered) {
    setState(() => _isHovered = isHovered);
    if (isHovered) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: MouseRegion(
            onEnter: (_) => _onHoverChanged(true),
            onExit: (_) => _onHoverChanged(false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                  boxShadow: _isHovered
                      ? [
                          BoxShadow(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.2),
                            blurRadius: 20,
                            spreadRadius: 0,
                          ),
                        ]
                      : AppTheme.cardShadow,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isDark
                              ? [
                                  AppTheme.darkCard.withValues(alpha: 0.8),
                                  AppTheme.darkCard.withValues(alpha: 0.6),
                                ]
                              : [
                                  AppTheme.lightCard.withValues(alpha: 0.9),
                                  AppTheme.lightCard.withValues(alpha: 0.7),
                                ],
                        ),
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusLarge),
                        border: Border.all(
                          color: _isHovered
                              ? AppTheme.primaryBlue.withValues(alpha: 0.4)
                              : (isDark
                                  ? AppTheme.darkBorder
                                      .withValues(alpha: 0.3)
                                  : AppTheme.lightBorder
                                      .withValues(alpha: 0.5)),
                          width: 1,
                        ),
                      ),
                      child: Padding(
                        padding:
                            const EdgeInsets.all(AppTheme.spacingLarge),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(context),
                            const SizedBox(height: AppTheme.spacingMedium),
                            _buildServerBadge(context),
                            const SizedBox(height: AppTheme.spacingLarge),
                            Expanded(
                              child: widget.metrics != null
                                  ? _buildMetrics(context)
                                  : _buildLoadingState(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      children: [
        // OS Icon with gradient background
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _getOsColor(widget.agent.os).withValues(alpha: 0.2),
                _getOsColor(widget.agent.os).withValues(alpha: 0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(
              color: _getOsColor(widget.agent.os).withValues(alpha: 0.3),
            ),
          ),
          child: Icon(
            _getOsIcon(widget.agent.os),
            color: _getOsColor(widget.agent.os),
            size: 24,
          ),
        ),
        const SizedBox(width: AppTheme.spacingMedium),

        // Hostname and OS info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.agent.hostname,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${widget.agent.os} \u2022 ${widget.agent.arch}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),

        // Online indicator with glow
        const StatusIndicator(isOnline: true, size: 12),
      ],
    );
  }

  Widget _buildServerBadge(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMedium,
        vertical: AppTheme.spacingSmall,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryBlue.withValues(alpha: 0.15),
            AppTheme.primaryBlue.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(
          color: AppTheme.primaryBlue.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.dns_outlined,
            size: 12,
            color: AppTheme.primaryBlue,
          ),
          const SizedBox(width: AppTheme.spacingSmall),
          Text(
            widget.serverName,
            style: TextStyle(
              color: AppTheme.primaryBlue,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetrics(BuildContext context) {
    final m = widget.metrics!;

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
        const SizedBox(height: AppTheme.spacingSmall),
        _buildMetricRow(
          context,
          icon: Icons.storage_rounded,
          label: 'RAM',
          value: m.memoryPercent,
          color: AppTheme.successGreen,
          subtitle:
              '${Formatter.bytes(m.memory.used)} / ${Formatter.bytes(m.memory.total)}',
        ),
        const SizedBox(height: AppTheme.spacingSmall),
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
          _buildNetworkRow(context, m),
        ],

        // GPU indicator
        if (m.gpus.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spacingSmall),
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
    final isDark = theme.brightness == Brightness.dark;
    final statusColor = AppTheme.getStatusColor(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(icon, size: 12, color: color),
            ),
            const SizedBox(width: AppTheme.spacingSmall),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            if (subtitle != null) ...[
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: (isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary)
                      .withValues(alpha: 0.6),
                  fontSize: 10,
                ),
              ),
              const SizedBox(width: AppTheme.spacingSmall),
            ],
            Text(
              Formatter.percent(value),
              style: theme.textTheme.bodySmall?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        GradientProgressBar(
          value: value / 100,
          height: 5,
          color: statusColor,
        ),
      ],
    );
  }

  Widget _buildNetworkRow(BuildContext context, AgentMetrics m) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppTheme.spacingSmall,
        horizontal: AppTheme.spacingMedium,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.darkBorder.withValues(alpha: 0.2)
            : AppTheme.lightBorder.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNetworkStat(
            context,
            icon: Icons.arrow_downward_rounded,
            value: m.networkIn,
            color: AppTheme.successGreen,
          ),
          Container(
            width: 1,
            height: 20,
            color: isDark
                ? AppTheme.darkBorder.withValues(alpha: 0.5)
                : AppTheme.lightBorder,
          ),
          _buildNetworkStat(
            context,
            icon: Icons.arrow_upward_rounded,
            value: m.networkOut,
            color: AppTheme.primaryBlue,
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkStat(
    BuildContext context, {
    required IconData icon,
    required int value,
    required Color color,
  }) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          Formatter.bytesPerSec(value),
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildGpuIndicator(BuildContext context, GpuMetrics gpu) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMedium,
        vertical: AppTheme.spacingSmall,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.gpuPurple.withValues(alpha: 0.15),
            AppTheme.gpuPurple.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(
          color: AppTheme.gpuPurple.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppTheme.gpuPurple.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              Icons.videocam_rounded,
              size: 12,
              color: AppTheme.gpuPurple,
            ),
          ),
          const SizedBox(width: AppTheme.spacingSmall),
          Expanded(
            child: Text(
              gpu.name.length > 15
                  ? '${gpu.name.substring(0, 15)}...'
                  : gpu.name,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.gpuPurple,
                fontWeight: FontWeight.w500,
                fontSize: 11,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            Formatter.percent(gpu.usagePercent),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppTheme.getStatusColor(gpu.usagePercent),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (gpu.temperature > 0) ...[
            const SizedBox(width: AppTheme.spacingSmall),
            Icon(
              Icons.thermostat_rounded,
              size: 12,
              color:
                  gpu.temperature > 80 ? AppTheme.errorRed : AppTheme.warningYellow,
            ),
            Text(
              '${gpu.temperature.toInt()}\u00B0',
              style: theme.textTheme.bodySmall?.copyWith(
                color: gpu.temperature > 80
                    ? AppTheme.errorRed
                    : AppTheme.warningYellow,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppTheme.primaryBlue,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingMedium),
          Text(
            'Waiting for metrics...',
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
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
    if (osLower.contains('darwin') || osLower.contains('macos')) {
      return Icons.laptop_mac;
    }
    return Icons.computer;
  }

  Color _getOsColor(String os) {
    final osLower = os.toLowerCase();
    if (osLower.contains('linux')) return Colors.orange;
    if (osLower.contains('windows')) return AppTheme.primaryBlue;
    if (osLower.contains('darwin') || osLower.contains('macos')) {
      return Colors.grey;
    }
    return AppTheme.npuIndigo;
  }
}
