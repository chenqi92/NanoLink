import 'package:flutter/material.dart';
import '../models/models.dart';

/// Card widget displaying agent information and real-time metrics
class AgentCard extends StatelessWidget {
  final Agent agent;
  final AgentMetrics? metrics;
  final String serverName;

  const AgentCard({
    super.key,
    required this.agent,
    this.metrics,
    required this.serverName,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _getOsColor(agent.os).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _getOsIcon(agent.os),
                    color: _getOsColor(agent.os),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        agent.hostname,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${agent.os} ${agent.arch}',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Server badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                serverName,
                style: TextStyle(
                  color: Colors.blue.shade300,
                  fontSize: 11,
                ),
              ),
            ),
            
            const Spacer(),
            
            // Metrics
            if (metrics != null) ...[
              _buildMetricBar('CPU', metrics!.cpuPercent, Colors.blue),
              const SizedBox(height: 8),
              _buildMetricBar('Memory', metrics!.memoryPercent, Colors.green),
              const SizedBox(height: 8),
              _buildMetricBar('Disk', metrics!.diskPercent, Colors.orange),
            ] else
              Center(
                child: Text(
                  'Waiting for metrics...',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricBar(String label, double percent, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            label,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent / 100,
              backgroundColor: Colors.grey.shade800,
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 45,
          child: Text(
            '${percent.toStringAsFixed(1)}%',
            style: TextStyle(
              color: _getPercentColor(percent),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Color _getPercentColor(double percent) {
    if (percent > 80) return Colors.red;
    if (percent > 50) return Colors.yellow;
    return Colors.green;
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
    if (osLower.contains('windows')) return Colors.blue;
    if (osLower.contains('darwin') || osLower.contains('macos')) return Colors.grey;
    return Colors.purple;
  }
}
