import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/nano_tokens.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
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
  const AgentDetailScreen({super.key, required this.agent, this.initialTab = 0});

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
                          size: 19, weight: FontWeight.w700, color: t.fg,
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
                NanoMono('agent ${a.version ?? '—'}', size: 11, color: t.fg4),
                const SizedBox(width: 8),
                Text('·', style: TextStyle(color: t.fg4, fontSize: 11)),
                const SizedBox(width: 8),
                NanoMono('心跳 ${Fmt.ago(a.lastHeartbeat)} 前',
                    size: 11, color: t.fg4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmented(BuildContext context, bool locked) {
    final t = context.nano;
    final items = ['实时', '历史', '终端'];
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
                    i == 2 && locked ? '终端 🔒' : items[i],
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: _tab == i ? FontWeight.w600 : FontWeight.w500,
                      color: _tab == i
                          ? t.fg
                          : (i == 2 && locked ? t.fg5 : t.fg2),
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
            Text('节点离线',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: t.fg2)),
            const SizedBox(height: 6),
            Text('最后心跳 ${Fmt.ago(agent.lastHeartbeat)} 前',
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
          NanoSectionLabel('存储'),
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
          NanoSectionLabel('网络接口'),
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
          NanoSectionLabel('GPU',
              trailing: NanoMono('${m.gpus.length} 个', size: 11, color: t.fg4)),
          for (final g in m.gpus) ...[
            _gpuCard(context, g),
            const SizedBox(height: 8),
          ],
        ],
        if (m.npus.isNotEmpty) ...[
          NanoSectionLabel('AI 加速器'),
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
                            NanoMono('${m.npus[i].temperature.toStringAsFixed(0)}°C',
                                size: 11, color: t.fg4),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _bar(context, '利用率', m.npus[i].usagePercent,
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
          NanoSectionLabel('登录会话',
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
          NanoSectionLabel('系统信息'),
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
                        Text('CPU',
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
                    if (m.cpu.model.isNotEmpty)
                      NanoMono(m.cpu.model, size: 11, color: t.fg4,
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
          if (m.cpu.perCoreUsage.isNotEmpty) ...[
            const SizedBox(height: 14),
            NanoCoreMatrix(
              cores: m.cpu.perCoreUsage,
              cols: m.cpu.perCoreUsage.length > 16 ? 16 : m.cpu.perCoreUsage.length.clamp(1, 16),
            ),
          ],
        ],
      ),
    );
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
                        Text('内存',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: t.fg3)),
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
          _kv(context, '已用', '${Fmt.gib(m.memory.used).toStringAsFixed(1)} GiB'),
          _kv(context, '可用', '${Fmt.gib(m.memory.available).toStringAsFixed(1)} GiB'),
          if (m.memory.swapTotal > 0)
            _kv(context, 'Swap',
                '${Fmt.gib(m.memory.swapUsed).toStringAsFixed(1)} / ${Fmt.gib(m.memory.swapTotal).toStringAsFixed(0)} GiB',
                warn: m.memory.swapUsed / m.memory.swapTotal > 0.2),
        ],
      ),
    );
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
                    NanoMono(d.mountPoint,
                        size: 14, weight: FontWeight.w600),
                    NanoMono('${d.device} · ${d.fsType}',
                        size: 11, color: t.fg4,
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
              NanoMono('R ${Fmt.rate(d.readBytesPerSec)}', size: 11, color: t.fg4),
              const SizedBox(width: 12),
              NanoMono('W ${Fmt.rate(d.writeBytesPerSec)}', size: 11, color: t.fg4),
            ],
          ),
        ],
      ),
    );
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
              NanoMono('↓ ${Fmt.rate(n.rxBytesPerSec)}', size: 12, color: t.fg2),
              const SizedBox(width: 14),
              NanoMono('↑ ${Fmt.rate(n.txBytesPerSec)}', size: 12, color: t.fg2),
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
                        size: 13.5, weight: FontWeight.w600,
                        overflow: TextOverflow.ellipsis),
                    if (g.driverVersion.isNotEmpty)
                      NanoMono(g.driverVersion, size: 10.5, color: t.fg4),
                  ],
                ),
              ),
              NanoMono('${g.temperature.toStringAsFixed(0)}°C',
                  size: 11,
                  color: g.temperature > 75 ? t.warn : t.fg3),
            ],
          ),
          const SizedBox(height: 8),
          _bar(context, '利用率', g.usagePercent,
              '${g.usagePercent.toStringAsFixed(0)}%'),
          const SizedBox(height: 5),
          if (g.memoryTotal > 0)
            _bar(context, '显存', g.memoryPercent,
                '${Fmt.gib(g.memoryUsed).toStringAsFixed(1)}/${Fmt.gib(g.memoryTotal).toStringAsFixed(0)} GB'),
          if (g.powerWatts > 0) ...[
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('功耗', style: TextStyle(fontSize: 11.5, color: t.fg4)),
                NanoMono('${g.powerWatts}W', size: 11.5, color: t.fg2),
              ],
            ),
          ],
        ],
      ),
    );
  }

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
      ['OS', '${s.osName} ${s.osVersion}'.trim()],
      ['内核', s.kernelVersion],
      ['运行时长', Fmt.uptime(s.uptimeSeconds)],
      if (s.motherboardModel.isNotEmpty) ['主板', s.motherboardModel],
      if (s.systemModel.isNotEmpty) ['整机', s.systemModel],
      if (s.biosVersion.isNotEmpty) ['BIOS', s.biosVersion],
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

// ─── History (placeholder until backend history wiring) ──────────────────────
class _HistoryTab extends StatefulWidget {
  final Agent agent;
  final AgentMetrics? metrics;
  const _HistoryTab({required this.agent, required this.metrics});

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  String _range = '1h';

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    const ranges = ['5m', '30m', '1h', '6h', '1d', '7d'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: t.card2,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              for (final r in ranges)
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _range = r),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _range == r ? t.card : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: NanoMono(r,
                          size: 12,
                          color: _range == r ? t.fg : t.fg3,
                          weight:
                              _range == r ? FontWeight.w600 : FontWeight.w500),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 40),
        Center(
          child: Column(
            children: [
              Icon(Icons.show_chart_rounded, color: t.fg4, size: 30),
              const SizedBox(height: 12),
              Text('历史曲线即将接入',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w500, color: t.fg2)),
              const SizedBox(height: 6),
              Text('将从服务器拉取该节点的历史指标',
                  style: TextStyle(fontSize: 12.5, color: t.fg4)),
            ],
          ),
        ),
      ],
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
