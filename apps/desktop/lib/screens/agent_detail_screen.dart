import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/agent_card.dart';

/// Detailed view of a single agent with all metrics (Glassmorphism design)
class AgentDetailScreen extends StatelessWidget {
  final Agent agent;

  const AgentDetailScreen({super.key, required this.agent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark
                  ? AppTheme.darkCard.withValues(alpha: 0.8)
                  : AppTheme.lightCard.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(
                color: isDark
                    ? AppTheme.darkBorder.withValues(alpha: 0.3)
                    : AppTheme.lightBorder.withValues(alpha: 0.5),
              ),
            ),
            child: Icon(
              Icons.arrow_back_rounded,
              color: isDark ? AppTheme.darkText : AppTheme.lightText,
              size: 20,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            _buildOsIcon(context),
            const SizedBox(width: AppTheme.spacingMedium),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agent.hostname,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${agent.os} \u2022 ${agent.arch}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppTheme.spacingLarge),
            child: _buildStatusBadge(context),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkGradient : AppTheme.lightGradient,
        ),
        child: Consumer<AppProvider>(
          builder: (context, provider, _) {
            final metrics = provider.allMetrics[agent.id];

            if (metrics == null) {
              return _buildLoadingState(context);
            }

            return SingleChildScrollView(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + kToolbarHeight + 20,
                left: 20,
                right: 20,
                bottom: 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildOverviewSection(context, metrics),
                  const SizedBox(height: AppTheme.spacingXLarge),
                  _buildCpuMemorySection(context, metrics),
                  const SizedBox(height: AppTheme.spacingXLarge),
                  if (metrics.disks.isNotEmpty) ...[
                    _buildDisksSection(context, metrics.disks),
                    const SizedBox(height: AppTheme.spacingXLarge),
                  ],
                  if (metrics.networks.isNotEmpty) ...[
                    _buildNetworkSection(context, metrics.networks),
                    const SizedBox(height: AppTheme.spacingXLarge),
                  ],
                  if (metrics.gpus.isNotEmpty) ...[
                    _buildGpuSection(context, metrics.gpus),
                    const SizedBox(height: AppTheme.spacingXLarge),
                  ],
                  if (metrics.npus.isNotEmpty) ...[
                    _buildNpuSection(context, metrics.npus),
                    const SizedBox(height: AppTheme.spacingXLarge),
                  ],
                  if (metrics.userSessions.isNotEmpty) ...[
                    _buildUserSessionsSection(context, metrics.userSessions),
                    const SizedBox(height: AppTheme.spacingXLarge),
                  ],
                  if (metrics.systemInfo != null) ...[
                    _buildSystemInfoSection(context, metrics.systemInfo!),
                  ],
                  const SizedBox(height: AppTheme.spacingXLarge),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildOsIcon(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _getOsColor(agent.os).withValues(alpha: 0.2),
            _getOsColor(agent.os).withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: _getOsColor(agent.os).withValues(alpha: 0.3),
        ),
      ),
      child: Icon(
        _getOsIcon(agent.os),
        color: _getOsColor(agent.os),
        size: 20,
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMedium,
        vertical: AppTheme.spacingSmall,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.successGreen.withValues(alpha: 0.2),
            AppTheme.successGreen.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(
          color: AppTheme.successGreen.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const StatusIndicator(isOnline: true, size: 8),
          const SizedBox(width: AppTheme.spacingSmall),
          Text(
            'common.online'.tr(),
            style: TextStyle(
              color: AppTheme.successGreen,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
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
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppTheme.primaryBlue,
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingLarge),
          Text(
            'metrics.loadingMetrics'.tr(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title, {IconData? icon}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      children: [
        if (icon != null) ...[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: Icon(icon, size: 16, color: AppTheme.primaryBlue),
          ),
          const SizedBox(width: AppTheme.spacingMedium),
        ],
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildGlassCard(BuildContext context, {required Widget child}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(AppTheme.spacingLarge),
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
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            border: Border.all(
              color: isDark
                  ? AppTheme.darkBorder.withValues(alpha: 0.3)
                  : AppTheme.lightBorder.withValues(alpha: 0.5),
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildOverviewSection(BuildContext context, AgentMetrics metrics) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, 'metrics.overview'.tr(), icon: Icons.dashboard_rounded),
        const SizedBox(height: AppTheme.spacingMedium),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth - AppTheme.spacingMedium * 3) / 4;
            final adjustedWidth = cardWidth < 160
                ? (constraints.maxWidth - AppTheme.spacingMedium) / 2
                : cardWidth;

            return Wrap(
              spacing: AppTheme.spacingMedium,
              runSpacing: AppTheme.spacingMedium,
              children: [
                _buildOverviewCard(
                  context,
                  width: adjustedWidth,
                  icon: Icons.memory,
                  label: 'metrics.cpu'.tr(),
                  value: Formatter.percent(metrics.cpuPercent),
                  color: AppTheme.primaryBlue,
                  percent: metrics.cpuPercent,
                ),
                _buildOverviewCard(
                  context,
                  width: adjustedWidth,
                  icon: Icons.storage_rounded,
                  label: 'metrics.memory'.tr(),
                  value: Formatter.bytes(metrics.memory.used),
                  subtitle: 'of ${Formatter.bytes(metrics.memory.total)}',
                  color: AppTheme.successGreen,
                  percent: metrics.memoryPercent,
                ),
                _buildOverviewCard(
                  context,
                  width: adjustedWidth,
                  icon: Icons.folder_open,
                  label: 'metrics.disk'.tr(),
                  value: Formatter.percent(metrics.diskPercent),
                  color: AppTheme.warningYellow,
                  percent: metrics.diskPercent,
                ),
                _buildOverviewCard(
                  context,
                  width: adjustedWidth,
                  icon: Icons.wifi,
                  label: 'metrics.network'.tr(),
                  value: '\u2193${Formatter.bytesPerSec(metrics.networkIn)}',
                  subtitle: '\u2191${Formatter.bytesPerSec(metrics.networkOut)}',
                  color: AppTheme.infoCyan,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildOverviewCard(
    BuildContext context, {
    required double width,
    required IconData icon,
    required String label,
    required String value,
    String? subtitle,
    required Color color,
    double? percent,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: width,
          padding: const EdgeInsets.all(AppTheme.spacingLarge),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      AppTheme.darkCard.withValues(alpha: 0.7),
                      AppTheme.darkCard.withValues(alpha: 0.5),
                    ]
                  : [
                      AppTheme.lightCard.withValues(alpha: 0.9),
                      AppTheme.lightCard.withValues(alpha: 0.7),
                    ],
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            border: Border.all(
              color: isDark
                  ? AppTheme.darkBorder.withValues(alpha: 0.3)
                  : AppTheme.lightBorder.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          color.withValues(alpha: 0.2),
                          color.withValues(alpha: 0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                    child: Icon(icon, size: 18, color: color),
                  ),
                  const SizedBox(width: AppTheme.spacingMedium),
                  Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingMedium),
              Text(
                value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: percent != null ? AppTheme.getStatusColor(percent) : null,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppTheme.darkTextSecondary.withValues(alpha: 0.7)
                        : AppTheme.lightTextSecondary.withValues(alpha: 0.7),
                  ),
                ),
              if (percent != null) ...[
                const SizedBox(height: AppTheme.spacingMedium),
                GradientProgressBar(
                  value: percent / 100,
                  height: 6,
                  color: AppTheme.getStatusColor(percent),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCpuMemorySection(BuildContext context, AgentMetrics metrics) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, 'metrics.cpuMemory'.tr(), icon: Icons.memory),
        const SizedBox(height: AppTheme.spacingMedium),
        _buildGlassCard(
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // CPU
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                    child: Icon(Icons.memory, size: 18, color: AppTheme.primaryBlue),
                  ),
                  const SizedBox(width: AppTheme.spacingMedium),
                  Text('metrics.cpuUsage'.tr(), style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Text(
                    Formatter.percent(metrics.cpuPercent),
                    style: TextStyle(
                      color: AppTheme.getStatusColor(metrics.cpuPercent),
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingMedium),
              GradientProgressBar(
                value: metrics.cpuPercent / 100,
                height: 10,
                color: AppTheme.getStatusColor(metrics.cpuPercent),
              ),
              if (metrics.cpu.model.isNotEmpty) ...[
                const SizedBox(height: AppTheme.spacingSmall),
                Text(
                  '${metrics.cpu.model} (${metrics.cpu.coreCount} cores)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
              ],

              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingLarge),
                child: Divider(
                  color: isDark
                      ? AppTheme.darkBorder.withValues(alpha: 0.3)
                      : AppTheme.lightBorder,
                ),
              ),

              // Memory
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.successGreen.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                    child: Icon(Icons.storage_rounded, size: 18, color: AppTheme.successGreen),
                  ),
                  const SizedBox(width: AppTheme.spacingMedium),
                  Text('metrics.memoryUsage'.tr(), style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Text(
                    '${Formatter.bytes(metrics.memory.used)} / ${Formatter.bytes(metrics.memory.total)}',
                    style: TextStyle(
                      color: AppTheme.getStatusColor(metrics.memoryPercent),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingMedium),
              GradientProgressBar(
                value: metrics.memoryPercent / 100,
                height: 10,
                color: AppTheme.getStatusColor(metrics.memoryPercent),
              ),
              const SizedBox(height: AppTheme.spacingMedium),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildMemoryLabel(context, 'metrics.available'.tr(), metrics.memory.available),
                  _buildMemoryLabel(context, 'metrics.swapUsed'.tr(), metrics.memory.swapUsed),
                  _buildMemoryLabel(context, 'metrics.swapTotal'.tr(), metrics.memory.swapTotal),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMemoryLabel(BuildContext context, String label, int value) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isDark
                ? AppTheme.darkTextSecondary.withValues(alpha: 0.6)
                : AppTheme.lightTextSecondary.withValues(alpha: 0.6),
          ),
        ),
        Text(
          Formatter.bytes(value),
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildDisksSection(BuildContext context, List<DiskMetrics> disks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          context,
          disks.length == 1
              ? 'metrics.storage'.tr().replaceFirst('{}', disks.length.toString())
              : 'metrics.storages'.tr().replaceFirst('{}', disks.length.toString()),
          icon: Icons.folder_open,
        ),
        const SizedBox(height: AppTheme.spacingMedium),
        ...disks.map((disk) => Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
          child: _buildDiskCard(context, disk),
        )),
      ],
    );
  }

  Widget _buildDiskCard(BuildContext context, DiskMetrics disk) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final percent = disk.usagePercent;

    return _buildGlassCard(
      context,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.warningYellow.withValues(alpha: 0.2),
                  AppTheme.warningYellow.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: Icon(Icons.folder_open, color: AppTheme.warningYellow, size: 24),
          ),
          const SizedBox(width: AppTheme.spacingLarge),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  disk.mountPoint,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${Formatter.bytes(disk.used)} / ${Formatter.bytes(disk.total)} (${disk.fsType})',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: AppTheme.spacingSmall),
                GradientProgressBar(
                  value: percent / 100,
                  height: 6,
                  color: AppTheme.getStatusColor(percent),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacingLarge),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                Formatter.percent(percent),
                style: TextStyle(
                  color: AppTheme.getStatusColor(percent),
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              if (disk.readBytesPerSec > 0 || disk.writeBytesPerSec > 0)
                Text(
                  'R: ${Formatter.bytesPerSec(disk.readBytesPerSec.toInt())}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppTheme.darkTextSecondary.withValues(alpha: 0.6)
                        : AppTheme.lightTextSecondary.withValues(alpha: 0.6),
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkSection(BuildContext context, List<NetworkMetrics> networks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          context,
          networks.length == 1
              ? 'metrics.networkInterface'.tr().replaceFirst('{}', networks.length.toString())
              : 'metrics.networkInterfaces'.tr().replaceFirst('{}', networks.length.toString()),
          icon: Icons.wifi,
        ),
        const SizedBox(height: AppTheme.spacingMedium),
        _buildGlassCard(
          context,
          child: Column(
            children: networks.asMap().entries.map((entry) {
              final index = entry.key;
              final net = entry.value;
              return Column(
                children: [
                  if (index > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppTheme.spacingMedium,
                      ),
                      child: Divider(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppTheme.darkBorder.withValues(alpha: 0.3)
                            : AppTheme.lightBorder,
                      ),
                    ),
                  _buildNetworkRow(context, net),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkRow(BuildContext context, NetworkMetrics net) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                (net.isUp ? AppTheme.successGreen : AppTheme.errorRed).withValues(alpha: 0.2),
                (net.isUp ? AppTheme.successGreen : AppTheme.errorRed).withValues(alpha: 0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
          child: Icon(
            net.isUp ? Icons.wifi : Icons.wifi_off,
            color: net.isUp ? AppTheme.successGreen : AppTheme.errorRed,
            size: 20,
          ),
        ),
        const SizedBox(width: AppTheme.spacingMedium),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                net.interface_,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (net.ipAddresses.isNotEmpty)
                Text(
                  net.ipAddresses.join(', '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_downward_rounded, size: 14, color: AppTheme.successGreen),
                const SizedBox(width: 4),
                Text(
                  Formatter.bytesPerSec(net.rxBytesPerSec),
                  style: TextStyle(
                    color: AppTheme.successGreen,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_upward_rounded, size: 14, color: AppTheme.primaryBlue),
                const SizedBox(width: 4),
                Text(
                  Formatter.bytesPerSec(net.txBytesPerSec),
                  style: TextStyle(
                    color: AppTheme.primaryBlue,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGpuSection(BuildContext context, List<GpuMetrics> gpus) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, 'metrics.gpuCount'.tr().replaceFirst('{}', gpus.length.toString()), icon: Icons.videocam_rounded),
        const SizedBox(height: AppTheme.spacingMedium),
        ...gpus.map((gpu) => Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
          child: _buildGpuCard(context, gpu),
        )),
      ],
    );
  }

  Widget _buildGpuCard(BuildContext context, GpuMetrics gpu) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return _buildGlassCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.gpuPurple.withValues(alpha: 0.2),
                      AppTheme.gpuPurple.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                ),
                child: Icon(Icons.videocam_rounded, color: AppTheme.gpuPurple, size: 24),
              ),
              const SizedBox(width: AppTheme.spacingMedium),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gpu.name,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (gpu.vendor.isNotEmpty)
                      Text(
                        gpu.vendor,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppTheme.darkTextSecondary
                              : AppTheme.lightTextSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (gpu.temperature > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingMedium,
                    vertical: AppTheme.spacingSmall,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        (gpu.temperature > 80 ? AppTheme.errorRed : AppTheme.warningYellow)
                            .withValues(alpha: 0.2),
                        (gpu.temperature > 80 ? AppTheme.errorRed : AppTheme.warningYellow)
                            .withValues(alpha: 0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.thermostat_rounded,
                        size: 16,
                        color: gpu.temperature > 80 ? AppTheme.errorRed : AppTheme.warningYellow,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${gpu.temperature.toInt()}\u00B0C',
                        style: TextStyle(
                          color: gpu.temperature > 80 ? AppTheme.errorRed : AppTheme.warningYellow,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingLarge),

          // Usage
          _buildProgressRow(
            context,
            label: 'metrics.gpuUsage'.tr(),
            value: gpu.usagePercent,
            color: AppTheme.gpuPurple,
          ),
          const SizedBox(height: AppTheme.spacingMedium),

          // VRAM
          _buildProgressRow(
            context,
            label: 'metrics.vram'.tr(),
            value: gpu.memoryPercent,
            suffix: '${Formatter.bytes(gpu.memoryUsed)} / ${Formatter.bytes(gpu.memoryTotal)}',
          ),
          const SizedBox(height: AppTheme.spacingMedium),

          // Additional stats
          Wrap(
            spacing: AppTheme.spacingLarge,
            runSpacing: AppTheme.spacingSmall,
            children: [
              if (gpu.powerWatts > 0)
                _buildStat(context, Icons.bolt, '${gpu.powerWatts}W'),
              if (gpu.fanSpeedPercent > 0)
                _buildStat(context, Icons.air, '${gpu.fanSpeedPercent}%'),
              if (gpu.driverVersion.isNotEmpty)
                _buildStat(context, Icons.info_outline, gpu.driverVersion),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressRow(
    BuildContext context, {
    required String label,
    required double value,
    Color? color,
    String? suffix,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final statusColor = color ?? AppTheme.getStatusColor(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
              ),
            ),
            const Spacer(),
            if (suffix != null) ...[
              Text(
                suffix,
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ] else
              Text(
                Formatter.percent(value),
                style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        GradientProgressBar(
          value: value / 100,
          height: 8,
          color: statusColor,
        ),
      ],
    );
  }

  Widget _buildNpuSection(BuildContext context, List<NpuMetrics> npus) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          context,
          'metrics.npuCount'.tr().replaceFirst('{}', npus.length.toString()),
          icon: Icons.psychology,
        ),
        const SizedBox(height: AppTheme.spacingMedium),
        ...npus.map((npu) => Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
          child: _buildNpuCard(context, npu),
        )),
      ],
    );
  }

  Widget _buildNpuCard(BuildContext context, NpuMetrics npu) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return _buildGlassCard(
      context,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.npuIndigo.withValues(alpha: 0.2),
                  AppTheme.npuIndigo.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: Icon(Icons.psychology, color: AppTheme.npuIndigo, size: 24),
          ),
          const SizedBox(width: AppTheme.spacingMedium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  npu.name,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (npu.vendor.isNotEmpty)
                  Text(
                    npu.vendor,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                    ),
                  ),
                const SizedBox(height: AppTheme.spacingSmall),
                GradientProgressBar(
                  value: npu.usagePercent / 100,
                  height: 8,
                  color: AppTheme.npuIndigo,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacingLarge),
          Text(
            Formatter.percent(npu.usagePercent),
            style: TextStyle(
              color: AppTheme.getStatusColor(npu.usagePercent),
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserSessionsSection(BuildContext context, List<UserSession> sessions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          context,
          'metrics.activeUsers'.tr().replaceFirst('{}', sessions.length.toString()),
          icon: Icons.people_rounded,
        ),
        const SizedBox(height: AppTheme.spacingMedium),
        _buildGlassCard(
          context,
          child: Column(
            children: sessions.asMap().entries.map((entry) {
              final index = entry.key;
              final session = entry.value;
              return Column(
                children: [
                  if (index > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppTheme.spacingMedium,
                      ),
                      child: Divider(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppTheme.darkBorder.withValues(alpha: 0.3)
                            : AppTheme.lightBorder,
                      ),
                    ),
                  _buildUserSessionRow(context, session),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildUserSessionRow(BuildContext context, UserSession session) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.primaryBlue.withValues(alpha: 0.2),
                AppTheme.primaryBlue.withValues(alpha: 0.1),
              ],
            ),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              session.username.isNotEmpty ? session.username[0].toUpperCase() : '?',
              style: TextStyle(
                color: AppTheme.primaryBlue,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppTheme.spacingMedium),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session.username,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                '${session.tty} \u2022 ${session.sessionType}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? AppTheme.darkTextSecondary
                      : AppTheme.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),
        if (session.remoteHost.isNotEmpty)
          Text(
            session.remoteHost,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : AppTheme.lightTextSecondary,
            ),
          ),
      ],
    );
  }

  Widget _buildSystemInfoSection(BuildContext context, SystemInfo info) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, 'system.systemInfo'.tr(), icon: Icons.info_outline),
        const SizedBox(height: AppTheme.spacingMedium),
        _buildGlassCard(
          context,
          child: Column(
            children: [
              _buildInfoRow(context, 'system.os'.tr(), '${info.osName} ${info.osVersion}'),
              _buildInfoRow(context, 'system.kernel'.tr(), info.kernelVersion),
              _buildInfoRow(context, 'system.uptime'.tr(), Formatter.uptime(info.uptimeSeconds)),
              if (info.systemModel.isNotEmpty)
                _buildInfoRow(context, 'system.systemModel'.tr(), '${info.systemVendor} ${info.systemModel}'),
              if (info.motherboardModel.isNotEmpty)
                _buildInfoRow(context, 'system.motherboard'.tr(), '${info.motherboardVendor} ${info.motherboardModel}'),
              if (info.biosVersion.isNotEmpty)
                _buildInfoRow(context, 'system.bios'.tr(), info.biosVersion),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(BuildContext context, IconData icon, String value) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMedium,
        vertical: AppTheme.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? AppTheme.darkBorder.withValues(alpha: 0.2)
            : AppTheme.lightBorder.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isDark
                ? AppTheme.darkTextSecondary
                : AppTheme.lightTextSecondary,
          ),
          const SizedBox(width: 4),
          Text(
            value,
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
