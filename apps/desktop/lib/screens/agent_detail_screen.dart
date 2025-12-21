import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/agent_card.dart';

/// Detailed view of a single agent with all metrics
class AgentDetailScreen extends StatelessWidget {
  final Agent agent;

  const AgentDetailScreen({super.key, required this.agent});

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
                color: _getOsColor(agent.os).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getOsIcon(agent.os),
                color: _getOsColor(agent.os),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agent.hostname,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  '${agent.os} • ${agent.arch}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Online indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.successGreen,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.successGreen.withValues(alpha: 0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Online',
                  style: TextStyle(
                    color: AppTheme.successGreen,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, provider, _) {
          final metrics = provider.allMetrics[agent.id];
          
          if (metrics == null) {
            return _buildLoadingState(context);
          }
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Overview section
                _buildSectionTitle(context, 'Overview'),
                const SizedBox(height: 12),
                _buildOverviewGrid(context, metrics),
                const SizedBox(height: 24),
                
                // CPU & Memory
                _buildSectionTitle(context, 'CPU & Memory'),
                const SizedBox(height: 12),
                _buildCpuMemorySection(context, metrics),
                const SizedBox(height: 24),
                
                // Disks
                if (metrics.disks.isNotEmpty) ...[
                  _buildSectionTitle(context, 'Storage (${metrics.disks.length} disks)'),
                  const SizedBox(height: 12),
                  _buildDisksSection(context, metrics.disks),
                  const SizedBox(height: 24),
                ],
                
                // Network
                if (metrics.networks.isNotEmpty) ...[
                  _buildSectionTitle(context, 'Network (${metrics.networks.length} interfaces)'),
                  const SizedBox(height: 12),
                  _buildNetworkSection(context, metrics.networks),
                  const SizedBox(height: 24),
                ],
                
                // GPUs
                if (metrics.gpus.isNotEmpty) ...[
                  _buildSectionTitle(context, 'GPU (${metrics.gpus.length})'),
                  const SizedBox(height: 12),
                  _buildGpuSection(context, metrics.gpus),
                  const SizedBox(height: 24),
                ],
                
                // NPUs
                if (metrics.npus.isNotEmpty) ...[
                  _buildSectionTitle(context, 'NPU / AI Accelerator (${metrics.npus.length})'),
                  const SizedBox(height: 12),
                  _buildNpuSection(context, metrics.npus),
                  const SizedBox(height: 24),
                ],
                
                // User Sessions
                if (metrics.userSessions.isNotEmpty) ...[
                  _buildSectionTitle(context, 'Active Users (${metrics.userSessions.length})'),
                  const SizedBox(height: 12),
                  _buildUserSessionsSection(context, metrics.userSessions),
                  const SizedBox(height: 24),
                ],
                
                // System Info
                if (metrics.systemInfo != null) ...[
                  _buildSectionTitle(context, 'System Information'),
                  const SizedBox(height: 12),
                  _buildSystemInfoSection(context, metrics.systemInfo!),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    final theme = Theme.of(context);
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppTheme.primaryBlue),
          const SizedBox(height: 16),
          Text(
            'Loading metrics...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final theme = Theme.of(context);
    
    return Text(
      title,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildOverviewGrid(BuildContext context, AgentMetrics metrics) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _buildOverviewCard(
          context,
          icon: Icons.memory,
          label: 'CPU',
          value: Formatter.percent(metrics.cpuPercent),
          color: AppTheme.primaryBlue,
          percent: metrics.cpuPercent,
        ),
        _buildOverviewCard(
          context,
          icon: Icons.storage_rounded,
          label: 'Memory',
          value: Formatter.bytes(metrics.memory.used),
          subtitle: 'of ${Formatter.bytes(metrics.memory.total)}',
          color: AppTheme.successGreen,
          percent: metrics.memoryPercent,
        ),
        _buildOverviewCard(
          context,
          icon: Icons.folder_open,
          label: 'Disk',
          value: Formatter.percent(metrics.diskPercent),
          color: AppTheme.warningYellow,
          percent: metrics.diskPercent,
        ),
        _buildOverviewCard(
          context,
          icon: Icons.wifi,
          label: 'Network',
          value: '↓${Formatter.bytesPerSec(metrics.networkIn)}',
          subtitle: '↑${Formatter.bytesPerSec(metrics.networkOut)}',
          color: AppTheme.infoCyan,
        ),
      ],
    );
  }

  Widget _buildOverviewCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    String? subtitle,
    required Color color,
    double? percent,
  }) {
    final theme = Theme.of(context);
    
    return Container(
      width: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerTheme.color ?? Colors.grey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          if (percent != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent / 100,
                backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation(AppTheme.getStatusColor(percent)),
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCpuMemorySection(BuildContext context, AgentMetrics metrics) {
    final theme = Theme.of(context);
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // CPU
            Row(
              children: [
                Icon(Icons.memory, size: 20, color: AppTheme.primaryBlue),
                const SizedBox(width: 8),
                Text('CPU Usage', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  Formatter.percent(metrics.cpuPercent),
                  style: TextStyle(
                    color: AppTheme.getStatusColor(metrics.cpuPercent),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: metrics.cpuPercent / 100,
                backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation(AppTheme.getStatusColor(metrics.cpuPercent)),
                minHeight: 10,
              ),
            ),
            if (metrics.cpu.model.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${metrics.cpu.model} (${metrics.cpu.coreCount} cores)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
            
            const Divider(height: 24),
            
            // Memory
            Row(
              children: [
                Icon(Icons.storage_rounded, size: 20, color: AppTheme.successGreen),
                const SizedBox(width: 8),
                Text('Memory Usage', style: theme.textTheme.titleSmall),
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
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: metrics.memoryPercent / 100,
                backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation(AppTheme.getStatusColor(metrics.memoryPercent)),
                minHeight: 10,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMemoryLabel(context, 'Available', metrics.memory.available),
                _buildMemoryLabel(context, 'Swap Used', metrics.memory.swapUsed),
                _buildMemoryLabel(context, 'Swap Total', metrics.memory.swapTotal),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryLabel(BuildContext context, String label, int value) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
        Text(
          Formatter.bytes(value),
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildDisksSection(BuildContext context, List<DiskMetrics> disks) {
    return Column(
      children: disks.map((disk) => _buildDiskCard(context, disk)).toList(),
    );
  }

  Widget _buildDiskCard(BuildContext context, DiskMetrics disk) {
    final theme = Theme.of(context);
    final percent = disk.usagePercent;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.warningYellow.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.folder_open, color: AppTheme.warningYellow, size: 24),
            ),
            const SizedBox(width: 16),
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
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percent / 100,
                      backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation(AppTheme.getStatusColor(percent)),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
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
                    'R: ${Formatter.bytesPerSec(disk.readBytesPerSec.toInt())} W: ${Formatter.bytesPerSec(disk.writeBytesPerSec.toInt())}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkSection(BuildContext context, List<NetworkMetrics> networks) {
    final theme = Theme.of(context);
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: networks.map((net) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (net.isUp ? AppTheme.successGreen : AppTheme.errorRed).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    net.isUp ? Icons.wifi : Icons.wifi_off,
                    color: net.isUp ? AppTheme.successGreen : AppTheme.errorRed,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
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
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
                        Icon(Icons.arrow_downward, size: 14, color: AppTheme.successGreen),
                        const SizedBox(width: 4),
                        Text(
                          Formatter.bytesPerSec(net.rxBytesPerSec),
                          style: TextStyle(color: AppTheme.successGreen, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_upward, size: 14, color: AppTheme.primaryBlue),
                        const SizedBox(width: 4),
                        Text(
                          Formatter.bytesPerSec(net.txBytesPerSec),
                          style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildGpuSection(BuildContext context, List<GpuMetrics> gpus) {
    return Column(
      children: gpus.map((gpu) => _buildGpuCard(context, gpu)).toList(),
    );
  }

  Widget _buildGpuCard(BuildContext context, GpuMetrics gpu) {
    final theme = Theme.of(context);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.gpuPurple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.videocam, color: AppTheme.gpuPurple, size: 24),
                ),
                const SizedBox(width: 12),
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
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                ),
                if (gpu.temperature > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (gpu.temperature > 80 ? AppTheme.errorRed : AppTheme.warningYellow).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.thermostat,
                          size: 16,
                          color: gpu.temperature > 80 ? AppTheme.errorRed : AppTheme.warningYellow,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${gpu.temperature.toInt()}°C',
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
            const SizedBox(height: 16),
            
            // Usage
            Row(
              children: [
                Text('GPU', style: theme.textTheme.bodySmall),
                const Spacer(),
                Text(
                  Formatter.percent(gpu.usagePercent),
                  style: TextStyle(
                    color: AppTheme.getStatusColor(gpu.usagePercent),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: gpu.usagePercent / 100,
                backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation(AppTheme.gpuPurple),
                minHeight: 8,
              ),
            ),
            
            const SizedBox(height: 12),
            
            // VRAM
            Row(
              children: [
                Text('VRAM', style: theme.textTheme.bodySmall),
                const Spacer(),
                Text(
                  '${Formatter.bytes(gpu.memoryUsed)} / ${Formatter.bytes(gpu.memoryTotal)}',
                  style: TextStyle(
                    color: AppTheme.getStatusColor(gpu.memoryPercent),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: gpu.memoryPercent / 100,
                backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation(AppTheme.getStatusColor(gpu.memoryPercent)),
                minHeight: 8,
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Additional stats
            Wrap(
              spacing: 16,
              runSpacing: 8,
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
      ),
    );
  }

  Widget _buildNpuSection(BuildContext context, List<NpuMetrics> npus) {
    return Column(
      children: npus.map((npu) => _buildNpuCard(context, npu)).toList(),
    );
  }

  Widget _buildNpuCard(BuildContext context, NpuMetrics npu) {
    final theme = Theme.of(context);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.npuIndigo.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.psychology, color: AppTheme.npuIndigo, size: 24),
                ),
                const SizedBox(width: 12),
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
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                    ],
                  ),
                ),
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
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: npu.usagePercent / 100,
                backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation(AppTheme.npuIndigo),
                minHeight: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserSessionsSection(BuildContext context, List<UserSession> sessions) {
    final theme = Theme.of(context);
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: sessions.map((session) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                  child: Text(
                    session.username.isNotEmpty ? session.username[0].toUpperCase() : '?',
                    style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.username,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${session.tty} • ${session.sessionType}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                if (session.remoteHost.isNotEmpty)
                  Text(
                    session.remoteHost,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildSystemInfoSection(BuildContext context, SystemInfo info) {
    final theme = Theme.of(context);
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildInfoRow(context, 'OS', '${info.osName} ${info.osVersion}'),
            _buildInfoRow(context, 'Kernel', info.kernelVersion),
            _buildInfoRow(context, 'Uptime', Formatter.uptime(info.uptimeSeconds)),
            if (info.systemModel.isNotEmpty)
              _buildInfoRow(context, 'System', '${info.systemVendor} ${info.systemModel}'),
            if (info.motherboardModel.isNotEmpty)
              _buildInfoRow(context, 'Motherboard', '${info.motherboardVendor} ${info.motherboardModel}'),
            if (info.biosVersion.isNotEmpty)
              _buildInfoRow(context, 'BIOS', info.biosVersion),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        const SizedBox(width: 4),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
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
