import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/nano_tokens.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../widgets/nano/nano_card.dart';
import '../widgets/nano/nano_primitives.dart';
import '../widgets/nano/nano_tiles.dart';
import '../widgets/server_switch_sheet.dart';
import 'add_server_page.dart';
import 'agent_detail_screen.dart';
import 'assistant_screen.dart';

/// Aggregate overview for the active server: KPI tiles, offline banner,
/// top CPU agents and recent activity. Mirrors the iOS/Material dashboards.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

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
        final diskAlerts = agents.where((a) {
          final m = provider.metricsFor(a.id);
          return m != null && m.disks.any((d) => d.usagePercent > 85);
        }).length;

        final topCpu = [...online]
          ..sort((a, b) => (provider.metricsFor(b.id)?.cpuPercent ?? 0)
              .compareTo(provider.metricsFor(a.id)?.cpuPercent ?? 0));

        return SafeArea(
          bottom: false,
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
                  ),
                  NanoKpiTile(
                    label: 'dashboard.avgMemory'.tr(),
                    icon: Icons.sd_storage_outlined,
                    value: Text('${avgMem.toStringAsFixed(1)}%'),
                    sub: 'dashboard.avgMemNodes'
                        .tr(namedArgs: {'n': '${online.length}'}),
                    tone: avgMem > 80 ? 'warn' : null,
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
                _OfflineBanner(offline: offline),
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
              () {
                final items = <Widget>[];
                for (final a in offline) {
                  if (items.length >= 6) break;
                  items.add(_ActivityRow(
                    icon: Icons.cloud_off_rounded,
                    text: 'alerts.nodeOffline'.tr(namedArgs: {'host': a.hostname}),
                    color: t.crit,
                  ));
                }
                for (final a in online) {
                  if (items.length >= 6) break;
                  final m = provider.metricsFor(a.id);
                  if (m == null) continue;
                  if (m.cpuPercent > 90) {
                    items.add(_ActivityRow(
                        icon: Icons.memory_rounded,
                        text: 'alerts.cpuPressure'.tr(namedArgs: {'host': a.hostname}),
                        color: t.warn));
                  } else if (m.memoryPercent > 90) {
                    items.add(_ActivityRow(
                        icon: Icons.sd_storage_outlined,
                        text: 'alerts.memPressure'.tr(namedArgs: {'host': a.hostname}),
                        color: t.warn));
                  } else if (m.disks.any((d) => d.usagePercent > 90)) {
                    items.add(_ActivityRow(
                        icon: Icons.warning_amber_rounded,
                        text: 'alerts.diskFull'.tr(namedArgs: {'host': a.hostname}),
                        color: t.warn));
                  }
                }
                if (items.isEmpty) {
                  return NanoCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 22),
                      child: Center(
                        child: Text('dashboard.noActivity'.tr(),
                            style: TextStyle(color: t.fg4, fontSize: 13)),
                      ),
                    ),
                  );
                }
                return NanoCard(child: Column(children: items));
              }(),
            ],
          ),
        );
      },
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _ActivityRow({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text, style: TextStyle(fontSize: 13.5, color: t.fg))),
        ],
      ),
    );
  }
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
            icon: Icons.dns_rounded,
            onTap: () => showServerSwitchSheet(context),
          ),
          const SizedBox(width: 8),
          _circleBtn(
            context,
            icon: Icons.add_rounded,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddServerPage()),
            ),
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
                        ? t.card
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(100),
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
                borderRadius: BorderRadius.circular(100),
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
  const _OfflineBanner({required this.offline});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.crit.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.crit.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: t.crit, size: 18),
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
          Icon(Icons.chevron_right_rounded, color: t.fg4, size: 18),
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
