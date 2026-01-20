import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/agent_card.dart';
import 'agent_detail_screen.dart';

/// Agents list screen with swipe actions and grid/list toggle.
class AgentsScreen extends StatefulWidget {
  const AgentsScreen({super.key});

  @override
  State<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends State<AgentsScreen> {
  bool _isGridView = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Row(
              children: [
                Text(
                  'nav.agents'.tr(),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // View Toggle
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, icon: Icon(Icons.grid_view_rounded)),
                    ButtonSegment(value: false, icon: Icon(Icons.view_list_rounded)),
                  ],
                  selected: {_isGridView},
                  onSelectionChanged: (value) => setState(() => _isGridView = value.first),
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          // Agent List/Grid
          Expanded(
            child: Consumer<AppProvider>(
              builder: (context, provider, _) {
                if (provider.allAgents.isEmpty) {
                  return _buildEmptyState(isDark);
                }
                return _isGridView
                    ? _buildGridView(context, provider, isDark)
                    : _buildListView(context, provider, isDark);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.computer_outlined, size: 64, color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
          const SizedBox(height: 16),
          Text(
            'home.noAgentsTitle'.tr(),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'home.noAgentsDesc'.tr(),
            style: TextStyle(color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildGridView(BuildContext context, AppProvider provider, bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 380).floor().clamp(1, 4);
        return GridView.builder(
          padding: const EdgeInsets.all(24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.95, // Taller cards to fit GPU info
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
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
              onTap: () => _openAgentDetail(context, agent),
            );
          },
        );
      },
    );
  }

  Widget _buildListView(BuildContext context, AppProvider provider, bool isDark) {
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: provider.allAgents.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final agent = provider.allAgents[index];
        final metrics = provider.allMetrics[agent.id];
        final serverName = provider.getServerName(agent.serverId);
        return Dismissible(
          key: Key(agent.id),
          direction: DismissDirection.horizontal,
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              // Swipe right -> Terminal (TODO)
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Terminal for ${agent.hostname} coming soon')),
              );
            }
            return false; // Don't dismiss
          },
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 24),
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.terminal_rounded, color: AppTheme.primaryBlue),
          ),
          child: _buildListTile(context, agent, metrics, serverName, isDark),
        );
      },
    );
  }

  Widget _buildListTile(BuildContext context, Agent agent, AgentMetrics? metrics, String serverName, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openAgentDetail(context, agent),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // OS Icon
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(_getOsIcon(agent.os), color: AppTheme.primaryBlue),
                ),
                const SizedBox(width: 16),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        agent.hostname,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                      Text(
                        '${agent.os} • $serverName',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? AppTheme.darkTextSecondary : AppTheme.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Status
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: agent.isOnline ? AppTheme.successGreen : AppTheme.errorRed,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (agent.isOnline ? AppTheme.successGreen : AppTheme.errorRed).withValues(alpha: 0.4),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getOsIcon(String os) {
    final osLower = os.toLowerCase();
    if (osLower.contains('linux')) return Icons.terminal;
    if (osLower.contains('windows')) return Icons.window;
    if (osLower.contains('darwin') || osLower.contains('mac')) return Icons.laptop_mac;
    return Icons.computer;
  }

  void _openAgentDetail(BuildContext context, agent) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AgentDetailScreen(agent: agent)),
    );
  }
}
