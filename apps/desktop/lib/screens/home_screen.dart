import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../widgets/agent_card.dart';
import '../widgets/add_server_dialog.dart';
import '../widgets/server_chip.dart';
import '../widgets/empty_state.dart';

/// Main home screen displaying all agents from connected servers
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.developer_board, color: Colors.blue.shade400),
            const SizedBox(width: 12),
            const Text('NanoLink'),
          ],
        ),
        actions: [
          Consumer<AppProvider>(
            builder: (context, provider, _) {
              final connectedCount = provider.servers.where((s) => s.isConnected).length;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      '${provider.allAgents.length} Agent${provider.allAgents.length != 1 ? 's' : ''}',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: connectedCount > 0 ? Colors.green : Colors.red,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Server',
            onPressed: () => _showAddServerDialog(context),
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
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
        final crossAxisCount = (constraints.maxWidth / 400).floor().clamp(1, 4);
        
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 1.3,
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
            );
          },
        );
      },
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Server'),
        content: Text('Are you sure you want to remove "${server.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
