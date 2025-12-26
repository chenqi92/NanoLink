import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/agent_card.dart';
import '../widgets/add_server_dialog.dart';
import '../widgets/server_chip.dart';
import '../widgets/empty_state.dart';
import 'agent_detail_screen.dart';

/// Main home screen displaying all agents with Glassmorphism design
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context, isDark),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkGradient : AppTheme.lightGradient,
        ),
        child: Consumer<AppProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading) {
              return _buildLoadingState(context, isDark);
            }

            return Column(
              children: [
                // Safe area padding for app bar
                SizedBox(
                  height: MediaQuery.of(context).padding.top + kToolbarHeight,
                ),
                // Server chips
                if (provider.servers.isNotEmpty) _buildServerChips(context, provider),
                // Agent grid or empty state
                Expanded(
                  child: provider.servers.isEmpty
                      ? EmptyState(
                          icon: Icons.dns_outlined,
                          title: 'home.noServersTitle'.tr(),
                          subtitle: 'home.noServersDesc'.tr(),
                          actionLabel: 'server.addServer'.tr(),
                          onAction: () => _showAddServerDialog(context),
                        )
                      : provider.allAgents.isEmpty
                          ? EmptyState(
                              icon: Icons.computer_outlined,
                              title: 'home.noAgentsTitle'.tr(),
                              subtitle: 'home.noAgentsDesc'.tr(),
                            )
                          : _buildAgentGrid(context, provider),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, bool isDark) {
    final theme = Theme.of(context);

    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        AppTheme.darkBackground.withValues(alpha: 0.8),
                        AppTheme.darkBackground.withValues(alpha: 0.0),
                      ]
                    : [
                        AppTheme.lightBackground.withValues(alpha: 0.8),
                        AppTheme.lightBackground.withValues(alpha: 0.0),
                      ],
              ),
            ),
          ),
        ),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.developer_board,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: AppTheme.spacingMedium),
          Text(
            'NanoLink',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
      actions: [
        // Agent count and status
        Consumer<AppProvider>(
          builder: (context, provider, _) {
            final connectedCount =
                provider.servers.where((s) => s.isConnected).length;
            return _buildStatusChip(context, provider, connectedCount, isDark);
          },
        ),

        // Theme toggle
        Consumer<ThemeProvider>(
          builder: (context, themeProvider, _) {
            return _buildThemeToggle(context, themeProvider, isDark);
          },
        ),

        // Language toggle
        _buildLanguageToggle(context, isDark),

        // Add server button
        Padding(
          padding: const EdgeInsets.only(right: AppTheme.spacingMedium),
          child: _buildAddServerButton(context, isDark),
        ),
      ],
    );
  }

  Widget _buildStatusChip(
    BuildContext context,
    AppProvider provider,
    int connectedCount,
    bool isDark,
  ) {
    // Determine connection mode icon and tooltip
    final hasWs = provider.hasWebSocketConnection;
    final hasPolling = provider.hasPollingConnection;

    IconData modeIcon;
    String modeTooltip;
    Color modeColor;

    if (hasWs) {
      modeIcon = Icons.bolt_rounded;
      modeTooltip = 'connection.wsRealtime'.tr();
      modeColor = AppTheme.successGreen;
    } else if (hasPolling) {
      modeIcon = Icons.sync_rounded;
      modeTooltip = 'connection.httpPolling'.tr();
      modeColor = AppTheme.warningYellow;
    } else {
      modeIcon = Icons.cloud_off_rounded;
      modeTooltip = 'connection.disconnected'.tr();
      modeColor = AppTheme.errorRed;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMedium),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Tooltip(
            message: modeTooltip,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? AppTheme.darkCard.withValues(alpha: 0.6)
                    : AppTheme.lightCard.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? AppTheme.darkBorder.withValues(alpha: 0.3)
                      : AppTheme.lightBorder.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Connection mode indicator
                  Icon(
                    modeIcon,
                    size: 14,
                    color: modeColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${provider.allAgents.length}',
                    style: TextStyle(
                      color: AppTheme.primaryBlue,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    ' ${provider.allAgents.length != 1 ? 'home.agentsCount'.tr() : 'home.agentCount'.tr()}'.replaceFirst('{} ', ''),
                    style: TextStyle(
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingSmall),
                  StatusIndicator(
                    isOnline: connectedCount > 0,
                    size: 8,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThemeToggle(
    BuildContext context,
    ThemeProvider themeProvider,
    bool isDark,
  ) {
    IconData icon;
    String tooltip;
    switch (themeProvider.themeMode) {
      case AppThemeMode.light:
        icon = Icons.light_mode_rounded;
        tooltip = 'theme.light'.tr();
      case AppThemeMode.dark:
        icon = Icons.dark_mode_rounded;
        tooltip = 'theme.dark'.tr();
      case AppThemeMode.system:
        icon = Icons.brightness_auto_rounded;
        tooltip = 'theme.system'.tr();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: tooltip,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: themeProvider.cycleTheme,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkCard.withValues(alpha: 0.5)
                        : AppTheme.lightCard.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(
                      color: isDark
                          ? AppTheme.darkBorder.withValues(alpha: 0.3)
                          : AppTheme.lightBorder.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: isDark
                        ? AppTheme.darkTextSecondary
                        : AppTheme.lightTextSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageToggle(BuildContext context, bool isDark) {
    final isZh = context.locale.languageCode == 'zh';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: 'language.title'.tr(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (isZh) {
                    context.setLocale(const Locale('en'));
                  } else {
                    context.setLocale(const Locale('zh'));
                  }
                },
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.darkCard.withValues(alpha: 0.5)
                        : AppTheme.lightCard.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(
                      color: isDark
                          ? AppTheme.darkBorder.withValues(alpha: 0.3)
                          : AppTheme.lightBorder.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    isZh ? 'EN' : '中',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppTheme.darkTextSecondary
                          : AppTheme.lightTextSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddServerButton(BuildContext context, bool isDark) {
    return Tooltip(
      message: 'server.addServer'.tr(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showAddServerDialog(context),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primaryBlue.withValues(alpha: 0.2),
                      AppTheme.primaryBlue.withValues(alpha: 0.1),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  border: Border.all(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(
                  Icons.add_rounded,
                  size: 20,
                  color: AppTheme.primaryBlue,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context, bool isDark) {
    final theme = Theme.of(context);

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
            'home.connectingToServers'.tr(),
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

  Widget _buildServerChips(BuildContext context, AppProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingLarge),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.all(AppTheme.spacingSmall),
            decoration: BoxDecoration(
              color: isDark
                  ? AppTheme.darkCard.withValues(alpha: 0.4)
                  : AppTheme.lightCard.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(
                color: isDark
                    ? AppTheme.darkBorder.withValues(alpha: 0.2)
                    : AppTheme.lightBorder.withValues(alpha: 0.3),
              ),
            ),
            child: Wrap(
              spacing: AppTheme.spacingSmall,
              runSpacing: AppTheme.spacingSmall,
              children: provider.servers.map((server) {
                return ServerChip(
                  server: server,
                  onDelete: () =>
                      _confirmDeleteServer(context, provider, server),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAgentGrid(BuildContext context, AppProvider provider) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 380).floor().clamp(1, 4);

        return GridView.builder(
          padding: const EdgeInsets.all(AppTheme.spacingLarge),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 1.15,
            crossAxisSpacing: AppTheme.spacingLarge,
            mainAxisSpacing: AppTheme.spacingLarge,
          ),
          itemCount: provider.allAgents.length,
          itemBuilder: (context, index) {
            final agent = provider.allAgents[index];
            final metrics = provider.allMetrics[agent.id];
            final serverName = provider.getServerName(agent.serverId);

            return AgentCard(
              agent: agent,
              metrics: metrics,
              serverName: serverName,
              onTap: () => _openAgentDetail(context, agent, metrics),
            );
          },
        );
      },
    );
  }

  void _openAgentDetail(
      BuildContext context, Agent agent, AgentMetrics? metrics) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            AgentDetailScreen(agent: agent),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  void _showAddServerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const AddServerDialog(),
    );
  }

  void _confirmDeleteServer(
    BuildContext context,
    AppProvider provider,
    ServerConnection server,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
          side: BorderSide(
            color: isDark
                ? AppTheme.darkBorder.withValues(alpha: 0.3)
                : AppTheme.lightBorder,
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.errorRed.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Icon(
                Icons.delete_outline_rounded,
                color: AppTheme.errorRed,
                size: 20,
              ),
            ),
            const SizedBox(width: AppTheme.spacingMedium),
            Text('home.removeServer'.tr()),
          ],
        ),
        content: Text(
          'home.removeServerConfirm'.tr().replaceFirst('{}', server.name),
          style: theme.textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'common.cancel'.tr(),
              style: TextStyle(
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : AppTheme.lightTextSecondary,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              provider.removeServer(server.id);
              Navigator.pop(context);
            },
            child: Text('common.remove'.tr()),
          ),
        ],
      ),
    );
  }
}
