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
      return const _RangeSpec(Duration(hours: 1), 'auto', ['-60m', '-30m', 'now']);
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

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final spec = _rangeSpec(_range);
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
              for (final r in _kRanges)
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pick(r),
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
                  title: '无法加载历史数据',
                  sub: '请检查与服务器的连接',
                  action: _retry(t));
            }
            if (h.isEmpty) {
              return _hint(t,
                  icon: Icons.show_chart_rounded,
                  title: '无可用历史数据',
                  sub: '该时间范围内暂无采集记录');
            }
            return _charts(context, h, spec.labels);
          },
        ),
      ],
    );
  }

  Widget _retry(NanoTokens t) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextButton.icon(
          onPressed: _load,
          icon: Icon(Icons.refresh_rounded, size: 16, color: t.accent),
          label: Text('重试', style: TextStyle(color: t.accent)),
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
    final cpuPeak = h.cpu.isEmpty ? 0.0 : h.cpu.reduce((a, b) => a > b ? a : b);
    final memPeak = h.mem.isEmpty ? 0.0 : h.mem.reduce((a, b) => a > b ? a : b);
    final m = widget.metrics;
    String f(List<double> s) =>
        s.isEmpty ? '0' : s.last.toStringAsFixed(s.last >= 100 ? 0 : 1);

    return Column(
      children: [
        if (cpuPeak > 90 || memPeak > 90) ...[
          _anomalyBanner(t, cpuPeak, memPeak),
          const SizedBox(height: 12),
        ],
        _HistoryChartCard(
          title: 'CPU',
          stat: '${(m?.cpuPercent ?? (h.cpu.isEmpty ? 0 : h.cpu.last)).toStringAsFixed(0)}%',
          peak: cpuPeak,
          unit: '%',
          xLabels: labels,
          yMax: 100,
          series: [NanoSeries(h.cpu, t.accent, fill: true)],
          thresholds: [NanoThreshold(90, t.crit, label: '90%')],
        ),
        _HistoryChartCard(
          title: '内存',
          stat: '${(m?.memoryPercent ?? (h.mem.isEmpty ? 0 : h.mem.last)).toStringAsFixed(0)}%',
          peak: memPeak,
          unit: '%',
          xLabels: labels,
          yMax: 100,
          series: [NanoSeries(h.mem, t.fg2, fill: true)],
          thresholds: [NanoThreshold(90, t.crit, label: '90%')],
        ),
        _HistoryChartCard(
          title: '网络',
          stat: '↓${f(h.netRx)} ↑${f(h.netTx)}',
          unit: ' MB/s',
          xLabels: labels,
          series: [
            NanoSeries(h.netRx, t.accent, fill: true, label: 'RX'),
            NanoSeries(h.netTx, t.warn, dashed: true, label: 'TX'),
          ],
        ),
        _HistoryChartCard(
          title: '磁盘 IO',
          stat: 'R ${f(h.diskRead)} · W ${f(h.diskWrite)}',
          unit: ' MB/s',
          xLabels: labels,
          series: [
            NanoSeries(h.diskRead, t.ok, fill: true, label: 'Read'),
            NanoSeries(h.diskWrite, t.warn, dashed: true, label: 'Write'),
          ],
        ),
        if (h.hasGpu)
          _HistoryChartCard(
            title: 'GPU',
            stat: '${h.gpuUsage.isEmpty ? 0 : h.gpuUsage.last.toStringAsFixed(0)}%',
            unit: '%',
            xLabels: labels,
            yMax: 100,
            series: [
              NanoSeries(h.gpuUsage, t.tertiary, fill: true, label: 'Util'),
              if (h.gpuTemp.isNotEmpty)
                NanoSeries(h.gpuTemp, t.crit, dashed: true, label: 'Temp'),
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
                Text('近期异常',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500, color: t.fg)),
                if (cpuPeak > 90)
                  Text('· CPU 峰值 ${cpuPeak.toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 11.5, color: t.fg3)),
                if (memPeak > 90)
                  Text('· 内存峰值 ${memPeak.toStringAsFixed(0)}%',
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
  const _HistoryChartCard({
    required this.title,
    required this.stat,
    required this.unit,
    required this.series,
    required this.xLabels,
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
                    NanoMono(stat, size: 16, weight: FontWeight.w600, color: t.fg),
                  ],
                ),
              ),
              if (peak != null)
                NanoBadge('峰值 ${peak!.toStringAsFixed(0)}$unit',
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
