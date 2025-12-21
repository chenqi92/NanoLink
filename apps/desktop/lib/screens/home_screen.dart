import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/agent_card.dart';
import '../widgets/add_server_dialog.dart';
import '../widgets/server_chip.dart';
import '../widgets/empty_state.dart';
import 'agent_detail_screen.dart';

/// Main home screen displaying all agents from connected servers
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.developer_board,
                color: AppTheme.primaryBlue,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'NanoLink',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          // Agent count and status
          Consumer<AppProvider>(
            builder: (context, provider, _) {
              final connectedCount = provider.servers.where((s) => s.isConnected).length;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: theme.dividerTheme.color ?? Colors.grey,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '${provider.allAgents.length}',
                            style: TextStyle(
                              color: AppTheme.primaryBlue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            ' Agent${provider.allAgents.length != 1 ? 's' : ''}',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: connectedCount > 0 
                                  ? AppTheme.successGreen 
                                  : AppTheme.errorRed,
                              boxShadow: [
                                BoxShadow(
                                  color: (connectedCount > 0 
                                      ? AppTheme.successGreen 
                                      : AppTheme.errorRed).withValues(alpha: 0.4),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          
          // Theme toggle
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, _) {
              IconData icon;
              switch (themeProvider.themeMode) {
                case AppThemeMode.light:
                  icon = Icons.light_mode;
                case AppThemeMode.dark:
                  icon = Icons.dark_mode;
                case AppThemeMode.system:
                  icon = Icons.brightness_auto;
              }
              return IconButton(
                icon: Icon(icon),
                tooltip: 'Toggle theme',
                onPressed: themeProvider.cycleTheme,
              );
            },
          ),
          
          // Add server button
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add, color: AppTheme.primaryBlue),
              ),
              tooltip: 'Add Server',
              onPressed: () => _showAddServerDialog(context),
            ),
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppTheme.primaryBlue),
                  const SizedBox(height: 16),
                  Text(
                    'Connecting to servers...',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Server chips
              if (provider.servers.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: provider.servers.map((server) {
                      return ServerChip(
                        server: server,
                        onDelete: () => _confirmDeleteServer(context, provider, server),
                      );
                    }).toList(),
                  ),
                ),

              // Agent grid or empty state
              Expanded(
                child: provider.servers.isEmpty
                    ? EmptyState(
                        icon: Icons.dns_outlined,
                        title: 'No Servers Connected',
                        subtitle: 'Add a NanoLink server to start monitoring your agents',
                        actionLabel: 'Add Server',
                        onAction: () => _showAddServerDialog(context),
                      )
                    : provider.allAgents.isEmpty
                        ? const EmptyState(
                            icon: Icons.computer_outlined,
                            title: 'No Agents Connected',
                            subtitle: 'Agents will appear here when they connect to your servers',
                          )
                        : _buildAgentGrid(context, provider),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAgentGrid(BuildContext context, AppProvider provider) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 380).floor().clamp(1, 4);
        
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 1.15,
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
              onTap: () => _openAgentDetail(context, agent, metrics),
            );
          },
        );
      },
    );
  }

  void _openAgentDetail(BuildContext context, Agent agent, AgentMetrics? metrics) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AgentDetailScreen(agent: agent),
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
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Server'),
        content: Text('Are you sure you want to remove "${server.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorRed,
            ),
            onPressed: () {
              provider.removeServer(server.id);
              Navigator.pop(context);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}
