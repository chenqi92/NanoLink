import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/add_server_dialog.dart';

/// Dashboard screen showing aggregate health and server overview.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Row(
                children: [
                  Text(
                    'nav.dashboard'.tr(),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  // Add Server Button
                  IconButton.filledTonal(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => const AddServerDialog(),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    tooltip: 'server.addServer'.tr(),
                  ),
                ],
              ),
            ),
          ),
          // Server Chips
          Consumer<AppProvider>(
            builder: (context, provider, _) {
              if (provider.servers.isEmpty) {
                return SliverToBoxAdapter(child: _buildEmptyState(context, isDark));
              }
              return SliverToBoxAdapter(
                child: _buildServerChips(context, provider, isDark),
              );
            },
          ),
          // Stats Cards
          Consumer<AppProvider>(
            builder: (context, provider, _) {
              if (provider.servers.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
              return SliverPadding(
                padding: const EdgeInsets.all(24),
                sliver: SliverGrid.count(
                  crossAxisCount: MediaQuery.sizeOf(context).width > 800 ? 4 : 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.3,
                  children: [
                    _buildStatCard(
                      context,
                      icon: Icons.devices_other_rounded,
                      label: 'dashboard.totalAgents'.tr(),
                      value: '${provider.allAgents.length}',
                      color: AppTheme.primaryBlue,
                      isDark: isDark,
                    ),
                    _buildStatCard(
                      context,
                      icon: Icons.memory_rounded,
                      label: 'dashboard.avgCpu'.tr(),
                      value: '${provider.totalSummary.avgCpuUsage.toStringAsFixed(1)}%',
                      color: AppTheme.accentPurple,
                      isDark: isDark,
                    ),
                    _buildStatCard(
                      context,
                      icon: Icons.storage_rounded,
                      label: 'dashboard.avgMemory'.tr(),
                      value: '${provider.totalSummary.avgMemoryUsage.toStringAsFixed(1)}%',
                      color: AppTheme.successGreen,
                      isDark: isDark,
                    ),
                    _buildStatCard(
                      context,
                      icon: Icons.warning_amber_rounded,
                      label: 'dashboard.alerts'.tr(),
                      value: '${provider.totalSummary.totalAlerts}',
                      color: AppTheme.warningYellow,
                      isDark: isDark,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dns_outlined, size: 64, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
          const SizedBox(height: 16),
          Text(
            'home.noServersTitle'.tr(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'home.noServersDesc'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => showDialog(context: context, builder: (_) => const AddServerDialog()),
            icon: const Icon(Icons.add_rounded),
            label: Text('server.addServer'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildServerChips(BuildContext context, AppProvider provider, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard.withValues(alpha: 0.5) : AppTheme.lightCard.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppTheme.darkBorder.withValues(alpha: 0.3) : AppTheme.lightBorder.withValues(alpha: 0.5),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: provider.servers.map((server) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      avatar: Icon(
                        server.isConnected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                        size: 18,
                        color: server.isConnected ? AppTheme.successGreen : AppTheme.errorRed,
                      ),
                      label: Text(server.name),
                      deleteIcon: const Icon(Icons.close, size: 16),
                      onDeleted: () => provider.removeServer(server.id),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required bool isDark,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard.withValues(alpha: 0.5) : AppTheme.lightCard.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              Text(
                value,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
