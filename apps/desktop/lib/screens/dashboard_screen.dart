import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/nano_tokens.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../utils/format.dart';
import '../widgets/nano/nano_card.dart';
import '../widgets/nano/nano_primitives.dart';
import '../widgets/nano/nano_tiles.dart';
import '../widgets/server_switch_sheet.dart';
import 'add_server_page.dart';
import 'agent_detail_screen.dart';
import 'agents_screen.dart';
import 'assistant_screen.dart';

/// Aggregate overview for the active server: KPI tiles (with rolling
/// sparklines on avg CPU/mem), offline banner, top CPU agents and the real
/// recent-activity audit feed. Mirrors the iOS/Material dashboards.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _sparkLen = 20;

  // Rolling buffers of the live average cpu/mem, fed once per metrics update.
  final List<double> _cpuSpark = <double>[];
  final List<double> _memSpark = <double>[];
  String? _sparkServerId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppProvider>().fetchRecentActivity();
    });
  }

  Future<void> _refresh() async {
    final provider = context.read<AppProvider>();
    await provider.fetchRecentActivity();
  }

  /// Append the latest avg sample, resetting the buffer when the active server
  /// changes so one server's history never bleeds into another.
  void _pushSpark(String? serverId, double avgCpu, double avgMem) {
    if (serverId != _sparkServerId) {
      _sparkServerId = serverId;
      _cpuSpark.clear();
      _memSpark.clear();
    }
    void push(List<double> buf, double v) {
      if (buf.isNotEmpty && (buf.last - v).abs() < 0.05) return;
      buf.add(v);
      if (buf.length > _sparkLen) buf.removeAt(0);
    }

    push(_cpuSpark, avgCpu);
    push(_memSpark, avgMem);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final agents = provider.agentsForServer();
        final online = agents.where((a) => a.isOnline).toList();
        final offline = agents.where((a) => !a.isOnline).toList();

        double avg(double Function(AgentMetrics m) sel) {
          final vals = <double>[];
          for (final a in online) {
            final m = provider.metricsFor(a.id);
            if (m != null) vals.add(sel(m));
          }
          if (vals.isEmpty) return 0;
          return vals.reduce((x, y) => x + y) / vals.length;
        }

        final avgCpu = avg((m) => m.cpuPercent);
        final avgMem = avg((m) => m.memoryPercent);

        // GiB used across online nodes (sum of MemoryMetrics.used bytes).
        var memUsedBytes = 0;
        for (final a in online) {
          final m = provider.metricsFor(a.id);
          if (m != null) memUsedBytes += m.memory.used;
        }
        final memUsedGib = Fmt.gib(memUsedBytes);

        _pushSpark(provider.activeServerId, avgCpu, avgMem);

        final diskAlerts = agents.where((a) {
          final m = provider.metricsFor(a.id);
          return m != null && m.disks.any((d) => d.usagePercent > 85);
        }).length;

        final topCpu = [...online]
          ..sort((a, b) => (provider.metricsFor(b.id)?.cpuPercent ?? 0)
              .compareTo(provider.metricsFor(a.id)?.cpuPercent ?? 0));

        final activity = provider.recentActivity();

        final list = RefreshIndicator(
          onRefresh: _refresh,
          edgeOffset: t.isIOS ? 40 : 0,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                16, t.isIOS ? 8 : 4, 16, t.isIOS ? 96 : 90),
            children: [
              _Header(provider: provider),
              const SizedBox(height: 12),
              _ServerChips(provider: provider),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.55,
                children: [
                  NanoKpiTile(
                    label: 'dashboard.onlineNodes'.tr(),
                    icon: Icons.dns_rounded,
                    value: Text.rich(TextSpan(children: [
                      TextSpan(text: '${online.length}'),
                      TextSpan(
                        text: '/${agents.length}',
                        style: TextStyle(color: t.fg4, fontSize: 18),
                      ),
                    ])),
                    sub: 'dashboard.nodesOffline'
                        .tr(namedArgs: {'n': '${offline.length}'}),
                  ),
                  NanoKpiTile(
                    label: 'dashboard.avgCpu'.tr(),
                    icon: Icons.memory_rounded,
                    value: Text('${avgCpu.toStringAsFixed(1)}%'),
                    sub: 'dashboard.avgCpuLast60s'.tr(),
                    tone: avgCpu > 80 ? 'warn' : null,
                    spark: _cpuSpark.length >= 2 ? List.of(_cpuSpark) : null,
                  ),
                  NanoKpiTile(
                    label: 'dashboard.avgMemory'.tr(),
                    icon: Icons.sd_storage_outlined,
                    value: Text('${avgMem.toStringAsFixed(1)}%'),
                    sub: 'dashboard.avgMemUsed'.tr(
                        namedArgs: {'gib': memUsedGib.toStringAsFixed(0)}),
                    tone: avgMem > 80 ? 'warn' : null,
                    spark: _memSpark.length >= 2 ? List.of(_memSpark) : null,
                  ),
                  NanoKpiTile(
                    label: 'dashboard.diskAlerts'.tr(),
                    icon: Icons.warning_amber_rounded,
                    value: Text('$diskAlerts'),
                    sub: 'dashboard.diskAlertsSub'.tr(),
                    tone: diskAlerts > 0 ? 'warn' : null,
                  ),
                ],
              ),
              if (offline.isNotEmpty) ...[
                const SizedBox(height: 12),
                _OfflineBanner(
                  offline: offline,
                  onView: () => _openAgents(context),
                ),
              ],
              const SizedBox(height: 4),
              NanoSectionLabel('dashboard.topCpu'.tr()),
              if (topCpu.isEmpty)
                _EmptyHint(
                  icon: Icons.dns_outlined,
                  text: provider.servers.isEmpty
                      ? 'dashboard.noServersYet'.tr()
                      : 'dashboard.noOnlineNodes'.tr(),
                )
              else
                NanoCard(
                  child: Column(
                    children: [
                      for (var i = 0; i < topCpu.take(4).length; i++)
                        _TopCpuRow(
                          agent: topCpu[i],
                          metrics: provider.metricsFor(topCpu[i].id),
                          divider: i < topCpu.take(4).length - 1,
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              NanoSectionLabel('dashboard.recentActivity'.tr()),
              if (activity.isEmpty)
                NanoCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    child: Center(
                      child: Text('dashboard.noActivity'.tr(),
                          style: TextStyle(color: t.fg4, fontSize: 13)),
                    ),
                  ),
                )
              else
                NanoCard(
                  child: Column(
                    children: [
                      for (var i = 0;
                          i < activity.take(5).length;
                          i++)
                        _AuditRow(
                          entry: activity[i],
                          divider: i < activity.take(5).length - 1,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );

        return SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Positioned.fill(child: list),
              Positioned(
                right: 16,
                bottom: t.isIOS ? 96 : 86,
                child: _AddNodeFab(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AddServerPage()),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openAgents(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AgentsScreen(initialFilter: 'offline'),
      ),
    );
  }
}

/// Floating "新节点" action that opens the add-server flow.
class _AddNodeFab extends StatelessWidget {
  final VoidCallback onTap;
  const _AddNodeFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [t.accent, t.tertiary]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: t.accent.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 6),
              Text('dashboard.newNode'.tr(),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One real audit entry: type + relative time, decoded params, acting user.
class _AuditRow extends StatelessWidget {
  final AuditEntry entry;
  final bool divider;
  const _AuditRow({required this.entry, required this.divider});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final ok = entry.ok;
    final tone = ok ? t.ok : t.crit;
    final summary = _paramsSummary(entry);
    return Container(
      decoration: BoxDecoration(
        border: divider
            ? Border(bottom: BorderSide(color: t.sep, width: 0.5))
            : null,
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(_auditIcon(entry.type), color: tone, size: 15),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: NanoMono(
                        entry.type.isEmpty ? 'event' : entry.type,
                        size: 13,
                        weight: FontWeight.w500,
                        color: t.fg,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(Fmt.ago(entry.at),
                        style: TextStyle(fontSize: 11, color: t.fg4)),
                  ],
                ),
                if (summary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: NanoMono(summary,
                        size: 11.5,
                        color: t.fg3,
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ),
          if (entry.user.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(entry.user,
                style: TextStyle(fontSize: 11, color: t.fg4)),
          ],
        ],
      ),
    );
  }

  /// Prefer the decoded params map; fall back to host/target/error context.
  String _paramsSummary(AuditEntry e) {
    final map = e.paramsMap;
    if (map.isNotEmpty) {
      return map.entries
          .map((kv) => '${kv.key}=${kv.value}')
          .join(' · ');
    }
    if (e.target.isNotEmpty) return e.target;
    if (e.agentHostname.isNotEmpty) return e.agentHostname;
    if (!e.ok && e.error.isNotEmpty) return e.error;
    return '';
  }
}

IconData _auditIcon(String type) {
  final s = type.toLowerCase();
  if (s.contains('shell') || s.contains('exec')) return Icons.terminal_rounded;
  if (s.contains('restart') || s.contains('reload')) {
    return Icons.refresh_rounded;
  }
  if (s.contains('reboot') || s.contains('power') || s.contains('shutdown')) {
    return Icons.power_settings_new_rounded;
  }
  if (s.contains('stop') || s.contains('kill')) return Icons.stop_rounded;
  if (s.contains('start')) return Icons.play_arrow_rounded;
  return Icons.history_rounded;
}

class _Header extends StatelessWidget {
  final AppProvider provider;
  const _Header({required this.provider});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Padding(
      padding: EdgeInsets.only(top: t.isIOS ? 40 : 8),
      child: Row(
        children: [
          if (!t.isIOS)
            Builder(
              builder: (ctx) => IconButton(
                icon: Icon(Icons.menu_rounded, color: t.fg),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
          Expanded(
            child: Text(
              'dashboard.title'.tr(),
              style: TextStyle(
                fontSize: t.isIOS ? 32 : 28,
                fontWeight: t.displayWeight,
                letterSpacing: t.displayTracking,
                color: t.fg,
              ),
            ),
          ),
          _circleBtn(
            context,
            icon: Icons.auto_awesome,
            gradient: LinearGradient(colors: [t.accent, t.tertiary]),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AssistantScreen()),
            ),
          ),
          const SizedBox(width: 8),
          _circleBtn(
            context,
            icon: Icons.search_rounded,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AgentsScreen()),
            ),
          ),
          const SizedBox(width: 8),
          _circleBtn(
            context,
            icon: Icons.dns_rounded,
            onTap: () => showServerSwitchSheet(context),
          ),
        ],
      ),
    );
  }

  Widget _circleBtn(BuildContext context,
      {required IconData icon, Gradient? gradient, required VoidCallback onTap}) {
    final t = context.nano;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: gradient == null ? t.card : null,
          gradient: gradient,
        ),
        child: Icon(icon,
            size: 18, color: gradient != null ? Colors.white : t.accent),
      ),
    );
  }
}

class _ServerChips extends StatelessWidget {
  final AppProvider provider;
  const _ServerChips({required this.provider});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final servers = provider.servers;
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final s in servers)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => provider.setActiveServer(s.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: s.id == provider.activeServerId
                        ? (t.isIOS ? t.card : t.card2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(t.isIOS ? 100 : 8),
                    border: Border.all(color: t.sep2),
                  ),
                  child: Row(
                    children: [
                      NanoStatusDot(
                        color: s.isConnected ? t.ok : t.crit,
                        pulse: s.isConnected,
                      ),
                      const SizedBox(width: 6),
                      Text(s.name,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: t.fg)),
                      const SizedBox(width: 6),
                      Text(
                        '${provider.agentsForServer(s.id).length}',
                        style: TextStyle(
                            fontSize: 10.5,
                            color: t.fg4,
                            fontFamilyFallback: kMonoFallback),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddServerPage()),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(t.isIOS ? 100 : 8),
                border: Border.all(color: t.sep, width: 1.5),
              ),
              child: Row(
                children: [
                  Icon(Icons.add_rounded, size: 14, color: t.fg3),
                  const SizedBox(width: 4),
                  Text('dashboard.add'.tr(),
                      style: TextStyle(fontSize: 13, color: t.fg3)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  final List<Agent> offline;
  final VoidCallback onView;
  const _OfflineBanner({required this.offline, required this.onView});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: t.crit.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.crit.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded, color: t.crit, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'dashboard.offlineBanner'
                        .tr(namedArgs: {'n': '${offline.length}'}),
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: t.fg)),
                Text(
                  offline.map((a) => a.hostname).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: t.fg3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onView,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text('dashboard.view'.tr(),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.crit)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopCpuRow extends StatelessWidget {
  final Agent agent;
  final AgentMetrics? metrics;
  final bool divider;
  const _TopCpuRow(
      {required this.agent, required this.metrics, required this.divider});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final cpu = metrics?.cpuPercent ?? 0;
    final tone = cpu > 90 ? t.crit : cpu > 75 ? t.warn : t.fg;
    return NanoListRow(
      divider: divider,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AgentDetailScreen(agent: agent)),
      ),
      leading: Icon(_osIcon(agent.os), size: 18, color: t.fg3),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${cpu.toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: tone,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 3),
              SizedBox(width: 50, child: NanoMeter(value: cpu / 100)),
            ],
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: t.fg4, size: 18),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NanoMono(agent.hostname, size: 14, weight: FontWeight.w500, color: t.fg),
          Text('${agent.os} · ${agent.arch}',
              style: TextStyle(fontSize: 11.5, color: t.fg4)),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return NanoCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            Icon(icon, color: t.fg4, size: 26),
            const SizedBox(height: 8),
            Text(text, style: TextStyle(color: t.fg4, fontSize: 13)),
          ],
        ),
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
