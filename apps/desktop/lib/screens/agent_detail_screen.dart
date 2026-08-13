import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/nano_tokens.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/server_service.dart';
import '../utils/format.dart';
import '../widgets/nano/nano_card.dart';
import '../widgets/nano/nano_charts.dart';
import '../widgets/nano/nano_primitives.dart';
import '../widgets/nano/nano_terminal.dart';
import '../widgets/agent_actions_sheet.dart';

/// Full agent detail: segmented Realtime / History / Terminal tabs.
class AgentDetailScreen extends StatefulWidget {
  final Agent agent;
  final int initialTab; // 0 realtime, 1 history, 2 terminal
  const AgentDetailScreen(
      {super.key, required this.agent, this.initialTab = 0});

  @override
  State<AgentDetailScreen> createState() => _AgentDetailScreenState();
}

class _AgentDetailScreenState extends State<AgentDetailScreen> {
  late int _tab = (widget.initialTab == 2 && widget.agent.permissionLevel == 0)
      ? 0
      : widget.initialTab; // 0 realtime, 1 history, 2 terminal

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final a = widget.agent;
    final locked = a.permissionLevel == 0;
    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(context, a),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _segmented(context, locked),
            ),
            Expanded(
              child: Consumer<AppProvider>(
                builder: (context, provider, _) {
                  final m = provider.metricsFor(a.id);
                  switch (_tab) {
                    case 1:
                      return _HistoryTab(agent: a, metrics: m);
                    case 2:
                      return NanoTerminalView(agent: a);
                    default:
                      return _RealtimeTab(agent: a, metrics: m);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, Agent a) {
    final t = context.nano;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    color: t.accent, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.more_horiz_rounded, color: t.accent),
                onPressed: () => showAgentActionsSheet(
                  context,
                  agent: a,
                  onOpenTerminal: () => setState(() => _tab = 2),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: Row(
              children: [
                NanoIconBox(_osIcon(a.os), size: 44, iconSize: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NanoMono(a.hostname,
                          size: 19,
                          weight: FontWeight.w700,
                          color: t.fg,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          NanoStatusLabel(
                              status: a.isOnline ? 'online' : 'offline'),
                          const SizedBox(width: 8),
                          Text('·', style: TextStyle(color: t.fg4)),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text('${a.os} · ${a.arch}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: t.fg3)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                NanoPermPill(level: a.permissionLevel),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                NanoMono(
                    'agentDetail.agentVersion'
                        .tr(namedArgs: {'version': a.version ?? '—'}),
                    size: 11,
                    color: t.fg4),
                const SizedBox(width: 8),
                Text('·', style: TextStyle(color: t.fg4, fontSize: 11)),
                const SizedBox(width: 8),
                NanoMono(
                    'agentDetail.heartbeat'
                        .tr(namedArgs: {'ago': Fmt.ago(a.lastHeartbeat)}),
                    size: 11,
                    color: t.fg4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmented(BuildContext context, bool locked) {
    final t = context.nano;
    final items = [
      'agentDetail.tabRealtime'.tr(),
      'agentDetail.tabHistory'.tr(),
      'agentDetail.tabTerminal'.tr(),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.card2,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (i == 2 && locked) return;
                  setState(() => _tab = i);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _tab == i ? t.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    boxShadow: _tab == i
                        ? [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4)
                          ]
                        : null,
                  ),
                  child: Text(
                    i == 2 && locked
                        ? 'agentDetail.tabTerminalLocked'.tr()
                        : items[i],
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: _tab == i ? FontWeight.w600 : FontWeight.w500,
                      color:
                          _tab == i ? t.fg : (i == 2 && locked ? t.fg5 : t.fg2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Realtime ───────────────────────────────────────────────────────────────
class _RealtimeTab extends StatelessWidget {
  final Agent agent;
  final AgentMetrics? metrics;
  const _RealtimeTab({required this.agent, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    if (!agent.isOnline || metrics == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 30, color: t.fg4),
            const SizedBox(height: 12),
            Text('agentDetail.nodeOffline'.tr(),
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: t.fg2)),
            const SizedBox(height: 6),
            Text(
                'agentDetail.lastHeartbeat'
                    .tr(namedArgs: {'ago': Fmt.ago(agent.lastHeartbeat)}),
                style: TextStyle(fontSize: 13, color: t.fg4)),
          ],
        ),
      );
    }
    final m = metrics!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
        _cpuCard(context, m),
        const SizedBox(height: 12),
        _memCard(context, m),
        if (m.disks.isNotEmpty) ...[
          NanoSectionLabel('agentDetail.storage'.tr()),
          NanoCard(
            child: Column(
              children: [
                for (var i = 0; i < m.disks.length; i++)
                  _diskTile(context, m.disks[i], i < m.disks.length - 1),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
        if (m.networks.isNotEmpty) ...[
          NanoSectionLabel('agentDetail.networkInterfaces'.tr()),
          NanoCard(
            child: Column(
              children: [
                for (var i = 0; i < m.networks.length; i++)
                  _netTile(context, m.networks[i], i < m.networks.length - 1),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
        if (m.gpus.isNotEmpty) ...[
          NanoSectionLabel('agentDetail.gpu'.tr(),
              trailing: NanoMono(
                  'agentDetail.gpuCount'
                      .tr(namedArgs: {'n': '${m.gpus.length}'}),
                  size: 11,
                  color: t.fg4)),
          for (final g in m.gpus) ...[
            _gpuCard(context, g),
            const SizedBox(height: 8),
          ],
        ],
        if (m.npus.isNotEmpty) ...[
          NanoSectionLabel('agentDetail.aiAccelerator'.tr()),
          NanoCard(
            child: Column(
              children: [
                for (var i = 0; i < m.npus.length; i++)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        14, 12, 14, i < m.npus.length - 1 ? 4 : 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                                child: NanoMono(m.npus[i].name,
                                    size: 13.5, weight: FontWeight.w600)),
                            NanoMono(
                                '${m.npus[i].temperature.toStringAsFixed(0)}°C',
                                size: 11,
                                color: t.fg4),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _bar(
                            context,
                            'agentDetail.utilization'.tr(),
                            m.npus[i].usagePercent,
                            '${m.npus[i].usagePercent.toStringAsFixed(0)}%'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
        if (m.userSessions.isNotEmpty) ...[
          NanoSectionLabel('agentDetail.loginSessions'.tr(),
              trailing:
                  NanoMono('${m.userSessions.length}', size: 11, color: t.fg4)),
          NanoCard(
            child: Column(
              children: [
                for (var i = 0; i < m.userSessions.length; i++)
                  NanoListRow(
                    divider: i < m.userSessions.length - 1,
                    trailing: NanoBadge(m.userSessions[i].sessionType),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        NanoMono(m.userSessions[i].username,
                            size: 13.5, weight: FontWeight.w600),
                        NanoMono(
                            '${m.userSessions[i].tty} · ${m.userSessions[i].remoteHost}',
                            size: 11,
                            color: t.fg4),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
        if (m.systemInfo != null) ...[
          NanoSectionLabel('agentDetail.systemInfo'.tr()),
          NanoCard(child: _systemInfo(context, m.systemInfo!)),
        ],
      ],
    );
  }

  Widget _cpuCard(BuildContext context, AgentMetrics m) {
    final t = context.nano;
    final cpu = m.cpuPercent;
    final tone = t.usageColor(cpu);
    return NanoCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.memory_rounded, size: 13, color: t.fg3),
                        const SizedBox(width: 5),
                        Text('agentDetail.cpu'.tr(),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: t.fg3)),
                        const SizedBox(width: 6),
                        NanoMono(
                            '${m.cpu.coreCount}c · ${m.cpu.temperature.toStringAsFixed(0)}°C',
                            size: 10.5,
                            color: t.fg4),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('${cpu.toStringAsFixed(0)}%',
                        style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w600,
                            height: 1.05,
                            letterSpacing: -0.5,
                            color: tone,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                    if (_cpuMeta(m.cpu).isNotEmpty)
                      NanoMono(_cpuMeta(m.cpu),
                          size: 11,
                          color: t.fg4,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              NanoDonut(
                  value: cpu,
                  size: 72,
                  thickness: 6,
                  label: '${cpu.toStringAsFixed(0)}%',
                  sub: '${m.cpu.coreCount}c'),
            ],
          ),
          if (m.cpu.loadAverage.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('agentDetail.perCore'.tr(),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: t.fg4)),
                NanoMono(
                    'agentDetail.load'.tr(namedArgs: {
                      'values': m.cpu.loadAverage
                          .take(3)
                          .map((v) => v.toStringAsFixed(2))
                          .join(' / ')
                    }),
                    size: 11,
                    color: t.fg4),
              ],
            ),
          ],
          if (m.cpu.perCoreUsage.isNotEmpty) ...[
            SizedBox(height: m.cpu.loadAverage.isNotEmpty ? 6 : 14),
            NanoCoreMatrix(
              cores: m.cpu.perCoreUsage,
              cols: m.cpu.perCoreUsage.length > 16
                  ? 16
                  : m.cpu.perCoreUsage.length.clamp(1, 16),
            ),
          ],
        ],
      ),
    );
  }

  /// "3.40 GHz · Intel Xeon …" — frequency (when known) joined with model.
  String _cpuMeta(CpuMetrics c) {
    final parts = <String>[];
    if (c.frequencyGhz > 0) {
      parts.add('agentDetail.ghz'
          .tr(namedArgs: {'value': c.frequencyGhz.toStringAsFixed(2)}));
    }
    if (c.model.isNotEmpty) parts.add(c.model);
    return parts.join(' · ');
  }

  Widget _memCard(BuildContext context, AgentMetrics m) {
    final t = context.nano;
    final mem = m.memoryPercent;
    final tone = t.usageColor(mem);
    return NanoCard(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.sd_storage_outlined, size: 13, color: t.fg3),
                        const SizedBox(width: 5),
                        Text('agentDetail.memory'.tr(),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: t.fg3)),
                        if (_memMeta(m.memory).isNotEmpty) ...[
                          const SizedBox(width: 6),
                          NanoMono(_memMeta(m.memory),
                              size: 10.5, color: t.fg4),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('${mem.toStringAsFixed(0)}%',
                        style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w600,
                            height: 1.05,
                            letterSpacing: -0.5,
                            color: tone,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                    NanoMono(
                        '${Fmt.gib(m.memory.used).toStringAsFixed(1)} / ${Fmt.gib(m.memory.total).toStringAsFixed(0)} GiB',
                        size: 11,
                        color: t.fg4),
                  ],
                ),
              ),
              NanoDonut(
                  value: mem,
                  size: 72,
                  thickness: 6,
                  label: '${mem.toStringAsFixed(0)}%',
                  sub: '${Fmt.gib(m.memory.total).toStringAsFixed(0)}G'),
            ],
          ),
          const SizedBox(height: 12),
          _kv(context, 'agentDetail.memUsed'.tr(),
              '${Fmt.gib(m.memory.used).toStringAsFixed(1)} GiB'),
          _kv(context, 'agentDetail.memAvailable'.tr(),
              '${Fmt.gib(m.memory.available).toStringAsFixed(1)} GiB'),
          if (m.memory.cached > 0 || m.memory.buffers > 0)
            _kv(context, 'agentDetail.cacheBuffers'.tr(),
                '${Fmt.gib(m.memory.cached).toStringAsFixed(1)} / ${Fmt.gib(m.memory.buffers).toStringAsFixed(1)} GiB'),
          if (m.memory.swapTotal > 0)
            _kv(context, 'Swap',
                '${Fmt.gib(m.memory.swapUsed).toStringAsFixed(1)} / ${Fmt.gib(m.memory.swapTotal).toStringAsFixed(0)} GiB',
                warn: m.memory.swapUsed / m.memory.swapTotal > 0.2),
        ],
      ),
    );
  }

  /// "DDR5 · 4800 MT/s" — module type joined with speed when known.
  String _memMeta(MemoryMetrics mem) {
    final parts = <String>[];
    if (mem.memoryType.isNotEmpty) parts.add(mem.memoryType);
    if (mem.memorySpeedMhz > 0) {
      parts.add('agentDetail.mtps'
          .tr(namedArgs: {'value': mem.memorySpeedMhz.toStringAsFixed(0)}));
    }
    return parts.join(' · ');
  }

  Widget _diskTile(BuildContext context, DiskMetrics d, bool divider) {
    final t = context.nano;
    final use = d.usagePercent;
    return Container(
      decoration: BoxDecoration(
        border: divider
            ? Border(bottom: BorderSide(color: t.sep2, width: 0.5))
            : null,
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NanoMono(d.mountPoint, size: 14, weight: FontWeight.w600),
                    NanoMono(_diskMeta(d),
                        size: 11,
                        color: t.fg4,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${use.toStringAsFixed(0)}%',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: t.usageColor(use),
                          fontFeatures: const [FontFeature.tabularFigures()])),
                  NanoMono(
                      '${Fmt.gib(d.used).toStringAsFixed(0)}/${Fmt.gib(d.total).toStringAsFixed(0)} GiB',
                      size: 11,
                      color: t.fg4),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          NanoMeter(value: use / 100),
          const SizedBox(height: 6),
          Row(
            children: [
              NanoMono('R ${Fmt.rate(d.readBytesPerSec)}',
                  size: 11, color: t.fg4),
              const SizedBox(width: 12),
              NanoMono('W ${Fmt.rate(d.writeBytesPerSec)}',
                  size: 11, color: t.fg4),
              if (d.temperature > 0) ...[
                const SizedBox(width: 12),
                NanoMono('${d.temperature.toStringAsFixed(0)}°C',
                    size: 11, color: d.temperature > 55 ? t.warn : t.fg4),
              ],
              const Spacer(),
              if (d.healthStatus.isNotEmpty)
                NanoBadge(d.healthStatus,
                    color: _diskHealthColor(t, d.healthStatus)),
            ],
          ),
        ],
      ),
    );
  }

  /// "/dev/nvme0n1p2 · ext4 · NVMe" — device, filesystem and disk type.
  String _diskMeta(DiskMetrics d) => [
        if (d.device.isNotEmpty) d.device,
        if (d.fsType.isNotEmpty) d.fsType,
        if (d.diskType.isNotEmpty) d.diskType,
      ].join(' · ');

  Color _diskHealthColor(NanoTokens t, String health) {
    final h = health.toLowerCase();
    if (h.contains('fail') || h.contains('crit') || h.contains('bad')) {
      return t.crit;
    }
    if (h.contains('warn') || h.contains('degrad')) return t.warn;
    return t.ok;
  }

  Widget _netTile(BuildContext context, NetworkMetrics n, bool divider) {
    final t = context.nano;
    return Container(
      decoration: BoxDecoration(
        border: divider
            ? Border(bottom: BorderSide(color: t.sep2, width: 0.5))
            : null,
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              NanoStatusDot(color: n.isUp ? t.ok : t.crit),
              const SizedBox(width: 7),
              NanoMono(n.interface_, size: 14, weight: FontWeight.w600),
              const SizedBox(width: 8),
              if (n.interfaceType.isNotEmpty) NanoBadge(n.interfaceType),
              const Spacer(),
              if (n.speedMbps > 0)
                NanoMono('${(n.speedMbps / 1000).toStringAsFixed(0)} Gb/s',
                    size: 11, color: t.fg4),
            ],
          ),
          if (n.ipAddresses.isNotEmpty) ...[
            const SizedBox(height: 4),
            NanoMono(n.ipAddresses.join(' · '),
                size: 11.5, color: t.fg3, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              NanoMono('↓ ${Fmt.rate(n.rxBytesPerSec)}',
                  size: 12, color: t.fg2),
              const SizedBox(width: 14),
              NanoMono('↑ ${Fmt.rate(n.txBytesPerSec)}',
                  size: 12, color: t.fg2),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gpuCard(BuildContext context, GpuMetrics g) {
    final t = context.nano;
    return NanoCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NanoMono(g.name,
                        size: 13.5,
                        weight: FontWeight.w600,
                        overflow: TextOverflow.ellipsis),
                    if (_gpuMeta(g).isNotEmpty)
                      NanoMono(_gpuMeta(g),
                          size: 10.5,
                          color: t.fg4,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              NanoMono('${g.temperature.toStringAsFixed(0)}°C',
                  size: 11, color: g.temperature > 75 ? t.warn : t.fg3),
            ],
          ),
          const SizedBox(height: 8),
          _bar(context, 'agentDetail.utilization'.tr(), g.usagePercent,
              '${g.usagePercent.toStringAsFixed(0)}%'),
          const SizedBox(height: 5),
          if (g.memoryTotal > 0)
            _bar(context, 'agentDetail.vram'.tr(), g.memoryPercent,
                '${Fmt.gib(g.memoryUsed).toStringAsFixed(1)}/${Fmt.gib(g.memoryTotal).toStringAsFixed(0)} GB'),
          if (g.powerWatts > 0) ...[
            const SizedBox(height: 5),
            if (g.powerLimitWatts > 0)
              _bar(
                  context,
                  'agentDetail.power'.tr(),
                  (g.powerWatts / g.powerLimitWatts * 100)
                      .clamp(0, 100)
                      .toDouble(),
                  'agentDetail.powerOf'.tr(namedArgs: {
                    'used': '${g.powerWatts}',
                    'limit': g.powerLimitWatts.toStringAsFixed(0)
                  }))
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('agentDetail.power'.tr(),
                      style: TextStyle(fontSize: 11.5, color: t.fg4)),
                  NanoMono('${g.powerWatts}W', size: 11.5, color: t.fg2),
                ],
              ),
          ],
        ],
      ),
    );
  }

  /// "566.40 · PCIe 4.0 x16" — driver version joined with PCIe generation.
  String _gpuMeta(GpuMetrics g) => [
        if (g.driverVersion.isNotEmpty) g.driverVersion,
        if (g.pcieGeneration.isNotEmpty) g.pcieGeneration,
      ].join(' · ');

  Widget _bar(BuildContext context, String label, double pct, String val) {
    final t = context.nano;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 11.5, color: t.fg4)),
            NanoMono(val, size: 11.5, color: t.fg2),
          ],
        ),
        const SizedBox(height: 3),
        NanoMeter(value: pct / 100),
      ],
    );
  }

  Widget _kv(BuildContext context, String k, String v, {bool warn = false}) {
    final t = context.nano;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: TextStyle(fontSize: 12.5, color: t.fg4)),
          NanoMono(v, size: 12.5, color: warn ? t.warn : t.fg2),
        ],
      ),
    );
  }

  Widget _systemInfo(BuildContext context, SystemInfo s) {
    final rows = <List<String>>[
      ['agentDetail.osLabel'.tr(), '${s.osName} ${s.osVersion}'.trim()],
      ['agentDetail.kernel'.tr(), s.kernelVersion],
      ['agentDetail.uptime'.tr(), Fmt.uptime(s.uptimeSeconds)],
      if (s.motherboardModel.isNotEmpty)
        ['agentDetail.motherboard'.tr(), s.motherboardModel],
      if (s.systemModel.isNotEmpty)
        ['agentDetail.systemModel'.tr(), s.systemModel],
      if (s.chassis.isNotEmpty) ['agentDetail.chassis'.tr(), s.chassis],
      if (s.biosVersion.isNotEmpty) ['agentDetail.bios'.tr(), s.biosVersion],
      if (s.primaryIp.isNotEmpty) ['agentDetail.primaryIp'.tr(), s.primaryIp],
    ].where((r) => r[1].trim().isNotEmpty).toList();
    final t = context.nano;
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            decoration: BoxDecoration(
              border: i < rows.length - 1
                  ? Border(bottom: BorderSide(color: t.sep2, width: 0.5))
                  : null,
            ),
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rows[i][0], style: TextStyle(fontSize: 14, color: t.fg3)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(rows[i][1],
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 13.5, color: t.fg2)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─── History (real data from /api/metrics/history) ──────────────────────────
class _RangeSpec {
  final Duration window;
  final String interval;
  final List<String> labels;
  const _RangeSpec(this.window, this.interval, this.labels);
}

const _kRanges = ['5m', '30m', '1h', '6h', '1d', '7d'];

_RangeSpec _rangeSpec(String r) {
  switch (r) {
    case '5m':
      return const _RangeSpec(
          Duration(minutes: 5), '1m', ['-5m', '-2m', 'now']);
    case '30m':
      return const _RangeSpec(
          Duration(minutes: 30), '1m', ['-30m', '-15m', 'now']);
    case '6h':
      return const _RangeSpec(Duration(hours: 6), '5m', ['-6h', '-3h', 'now']);
    case '1d':
      return const _RangeSpec(Duration(days: 1), '1h', ['-24h', '-12h', 'now']);
    case '7d':
      return const _RangeSpec(Duration(days: 7), '1h', ['-7d', '-3d', 'now']);
    default:
      return const _RangeSpec(
          Duration(hours: 1), 'auto', ['-60m', '-30m', 'now']);
  }
}

class _HistoryTab extends StatefulWidget {
  final Agent agent;
  final AgentMetrics? metrics;
  const _HistoryTab({required this.agent, required this.metrics});

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  String _range = '1h';
  Future<MetricsHistory?>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final svc = context.read<AppProvider>().serviceForAgent(widget.agent.id);
    final spec = _rangeSpec(_range);
    setState(() {
      _future = svc == null
          ? Future.value(null)
          : svc.fetchMetricsHistory(widget.agent.id,
              window: spec.window, interval: spec.interval);
    });
  }

  void _pick(String r) {
    if (r == _range) return;
    _range = r;
    _load();
  }

  Future<void> _refresh() async {
    _load();
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final spec = _rangeSpec(_range);
    return RefreshIndicator(
      onRefresh: _refresh,
      color: t.accent,
      backgroundColor: t.card,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          // Horizontally-scrollable range chips.
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: _kRanges.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final r = _kRanges[i];
                final sel = _range == r;
                return GestureDetector(
                  onTap: () => _pick(r),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: sel ? t.accent.withValues(alpha: 0.16) : t.card2,
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: sel ? t.accent.withValues(alpha: 0.5) : t.sep2,
                        width: 0.5,
                      ),
                    ),
                    child: NanoMono(r,
                        size: 12.5,
                        color: sel ? t.accent : t.fg3,
                        weight: sel ? FontWeight.w600 : FontWeight.w500),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<MetricsHistory?>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return _hint(t,
                    child: const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2)));
              }
              final h = snap.data;
              if (h == null) {
                return _hint(t,
                    icon: Icons.cloud_off_rounded,
                    title: 'history.loadFailed'.tr(),
                    sub: 'history.loadFailedSub'.tr(),
                    action: _retry(t));
              }
              if (h.isEmpty) {
                return _hint(t,
                    icon: Icons.show_chart_rounded,
                    title: 'history.noData'.tr(),
                    sub: 'history.noDataSub'.tr());
              }
              return _charts(context, h, spec.labels);
            },
          ),
        ],
      ),
    );
  }

  Widget _retry(NanoTokens t) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextButton.icon(
          onPressed: _load,
          icon: Icon(Icons.refresh_rounded, size: 16, color: t.accent),
          label: Text('common.retry'.tr(), style: TextStyle(color: t.accent)),
        ),
      );

  Widget _hint(NanoTokens t,
      {IconData? icon,
      String? title,
      String? sub,
      Widget? child,
      Widget? action}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (child != null) child,
            if (icon != null) Icon(icon, color: t.fg4, size: 30),
            if (title != null) ...[
              const SizedBox(height: 12),
              Text(title,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500, color: t.fg2)),
            ],
            if (sub != null) ...[
              const SizedBox(height: 6),
              Text(sub, style: TextStyle(fontSize: 12.5, color: t.fg4)),
            ],
            if (action != null) action,
          ],
        ),
      ),
    );
  }

  Widget _charts(BuildContext context, MetricsHistory h, List<String> labels) {
    final t = context.nano;
    double maxOf(List<double> s) =>
        s.isEmpty ? 0.0 : s.reduce((a, b) => a > b ? a : b);
    // Prefer DB-aggregated per-bucket peaks when present, else series max.
    final cpuPeak =
        h.hasMaxBands && h.cpuMax.isNotEmpty ? maxOf(h.cpuMax) : maxOf(h.cpu);
    final memPeak =
        h.hasMaxBands && h.memMax.isNotEmpty ? maxOf(h.memMax) : maxOf(h.mem);
    final m = widget.metrics;
    final times = h.times;
    String f(List<double> s) =>
        s.isEmpty ? '0' : s.last.toStringAsFixed(s.last >= 100 ? 0 : 1);

    return Column(
      children: [
        if (cpuPeak > 90 || memPeak > 90) ...[
          _anomalyBanner(t, cpuPeak, memPeak),
          const SizedBox(height: 12),
        ],
        _HistoryChartCard(
          title: 'history.cpu'.tr(),
          stat:
              '${(m?.cpuPercent ?? (h.cpu.isEmpty ? 0 : h.cpu.last)).toStringAsFixed(0)}%',
          peak: cpuPeak,
          unit: '%',
          xLabels: labels,
          times: times,
          yMax: 100,
          series: [
            NanoSeries(h.cpu, t.accent,
                fill: true, band: h.hasMaxBands ? h.cpuMax : null),
          ],
          thresholds: [NanoThreshold(90, t.crit, label: '90%')],
        ),
        _HistoryChartCard(
          title: 'history.memory'.tr(),
          stat:
              '${(m?.memoryPercent ?? (h.mem.isEmpty ? 0 : h.mem.last)).toStringAsFixed(0)}%',
          peak: memPeak,
          unit: '%',
          xLabels: labels,
          times: times,
          yMax: 100,
          series: [
            NanoSeries(h.mem, t.fg2,
                fill: true, band: h.hasMaxBands ? h.memMax : null),
          ],
          thresholds: [NanoThreshold(90, t.crit, label: '90%')],
        ),
        _HistoryChartCard(
          title: 'history.network'.tr(),
          stat: '↓${f(h.netRx)} ↑${f(h.netTx)}',
          unit: ' MB/s',
          xLabels: labels,
          times: times,
          series: [
            NanoSeries(h.netRx, t.accent, fill: true, label: 'history.rx'.tr()),
            NanoSeries(h.netTx, t.warn, dashed: true, label: 'history.tx'.tr()),
          ],
        ),
        _HistoryChartCard(
          title: 'history.diskIo'.tr(),
          stat: 'R ${f(h.diskRead)} · W ${f(h.diskWrite)}',
          unit: ' MB/s',
          xLabels: labels,
          times: times,
          series: [
            NanoSeries(h.diskRead, t.ok,
                fill: true, label: 'history.read'.tr()),
            NanoSeries(h.diskWrite, t.warn,
                dashed: true, label: 'history.write'.tr()),
          ],
        ),
        if (h.hasGpu)
          _HistoryChartCard(
            title: 'history.gpu'.tr(),
            stat:
                '${h.gpuUsage.isEmpty ? 0 : h.gpuUsage.last.toStringAsFixed(0)}%',
            unit: '%',
            xLabels: labels,
            times: times,
            yMax: 100,
            series: [
              NanoSeries(h.gpuUsage, t.tertiary,
                  fill: true, label: 'history.utilization'.tr()),
              if (h.gpuTemp.isNotEmpty)
                NanoSeries(h.gpuTemp, t.crit,
                    dashed: true, label: 'history.temperature'.tr()),
            ],
          ),
      ],
    );
  }

  Widget _anomalyBanner(NanoTokens t, double cpuPeak, double memPeak) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: t.warn.withValues(alpha: 0.1),
        border: Border.all(color: t.warn.withValues(alpha: 0.25), width: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 15, color: t.warn),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('history.anomaly'.tr(),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: t.fg)),
                if (cpuPeak > 90)
                  Text(
                      'history.anomalyCpu'
                          .tr(namedArgs: {'value': cpuPeak.toStringAsFixed(0)}),
                      style: TextStyle(fontSize: 11.5, color: t.fg3)),
                if (memPeak > 90)
                  Text(
                      'history.anomalyMem'
                          .tr(namedArgs: {'value': memPeak.toStringAsFixed(0)}),
                      style: TextStyle(fontSize: 11.5, color: t.fg3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryChartCard extends StatelessWidget {
  final String title;
  final String stat;
  final double? peak;
  final String unit;
  final double? yMax;
  final List<NanoSeries> series;
  final List<NanoThreshold> thresholds;
  final List<String> xLabels;
  final List<DateTime> times;
  const _HistoryChartCard({
    required this.title,
    required this.stat,
    required this.unit,
    required this.series,
    required this.xLabels,
    this.times = const [],
    this.peak,
    this.yMax,
    this.thresholds = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return NanoCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: t.fg3)),
                    const SizedBox(height: 1),
                    NanoMono(stat,
                        size: 16, weight: FontWeight.w600, color: t.fg),
                  ],
                ),
              ),
              if (peak != null)
                NanoBadge(
                    'history.peak'.tr(namedArgs: {
                      'value': peak!.toStringAsFixed(0),
                      'unit': unit
                    }),
                    color: peak! > 90 ? t.crit : t.fg3),
              if (series.length > 1) ...[
                for (final s in series)
                  if (s.label != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 2,
                            color: s.color,
                          ),
                          const SizedBox(width: 4),
                          Text(s.label!,
                              style: TextStyle(fontSize: 10.5, color: t.fg4)),
                        ],
                      ),
                    ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          NanoLineChart(
            series: series,
            unit: unit,
            yMax: yMax,
            thresholds: thresholds,
            xLabels: xLabels,
            times: times,
            height: 130,
          ),
        ],
      ),
    );
  }
}

IconData _osIcon(String os) {
  final s = os.toLowerCase();
  if (s.contains('mac') || s.contains('darwin') || s.contains('ios')) {
    return Icons.apple;
  }
  if (s.contains('win')) return Icons.window;
  return Icons.terminal;
}
