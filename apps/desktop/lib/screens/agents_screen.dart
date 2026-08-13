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
import '../widgets/agent_actions_sheet.dart';
import '../widgets/server_switch_sheet.dart';
import 'agent_detail_screen.dart';

/// Node list with search + filters. Each card shows live CPU/MEM/disk meters.
class AgentsScreen extends StatefulWidget {
  /// Optional initial filter ('all' | 'online' | 'offline' | 'warn') used to
  /// deep-link into a specific node view (e.g. the dashboard offline banner).
  final String? initialFilter;

  /// Optional initial search query applied to hostname/os.
  final String? initialQuery;

  const AgentsScreen({super.key, this.initialFilter, this.initialQuery});

  @override
  State<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends State<AgentsScreen> {
  late String _query = widget.initialQuery ?? '';
  late String _filter = widget.initialFilter ?? 'all';
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  bool _warn(AppProvider p, Agent a) {
    final m = p.metricsFor(a.id);
    if (m == null) return false;
    return m.cpuPercent > 80 ||
        m.memoryPercent > 80 ||
        m.disks.any((d) => d.usagePercent > 85);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final all = provider.agentsForServer();
        final filtered = all.where((a) {
          if (_filter == 'online' && !a.isOnline) return false;
          if (_filter == 'offline' && a.isOnline) return false;
          if (_filter == 'warn' && !_warn(provider, a)) return false;
          if (_query.isNotEmpty) {
            final q = _query.toLowerCase();
            if (!a.hostname.toLowerCase().contains(q) &&
                !a.os.toLowerCase().contains(q)) {
              return false;
            }
          }
          return true;
        }).toList();

        final filters = <List<dynamic>>[
          ['all', 'agents.filterAll'.tr(), all.length],
          [
            'online',
            'agents.filterOnline'.tr(),
            all.where((a) => a.isOnline).length
          ],
          [
            'warn',
            'agents.filterWarn'.tr(),
            all.where((a) => _warn(provider, a)).length
          ],
          [
            'offline',
            'agents.filterOffline'.tr(),
            all.where((a) => !a.isOnline).length
          ],
        ];

        return Stack(
          children: [
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, t.isIOS ? 40 : 8, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (!t.isIOS)
                              Builder(
                                builder: (ctx) => Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: IconButton(
                                    icon: Icon(Icons.menu_rounded, color: t.fg),
                                    onPressed: () =>
                                        Scaffold.of(ctx).openDrawer(),
                                  ),
                                ),
                              ),
                            Text('agents.title'.tr(),
                                style: TextStyle(
                                    fontSize: t.isIOS ? 32 : 28,
                                    fontWeight: t.displayWeight,
                                    letterSpacing: t.displayTracking,
                                    color: t.fg)),
                            const Spacer(),
                            IconButton(
                              tooltip: 'agents.searchHint'.tr(),
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.search_rounded, color: t.fg2),
                              onPressed: () => _searchFocus.requestFocus(),
                            ),
                            IconButton(
                              tooltip: 'agents.filter'.tr(),
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                _filter == 'all'
                                    ? Icons.filter_list_rounded
                                    : Icons.filter_list_alt,
                                color: _filter == 'all' ? t.fg2 : t.accent,
                              ),
                              onPressed: () =>
                                  _showFilterSheet(provider, filters),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // search
                        Container(
                          decoration: BoxDecoration(
                            color: t.card2,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            children: [
                              Icon(Icons.search_rounded,
                                  size: 18, color: t.fg4),
                              const SizedBox(width: 6),
                              Expanded(
                                child: TextField(
                                  focusNode: _searchFocus,
                                  style: TextStyle(color: t.fg, fontSize: 15),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: InputBorder.none,
                                    hintText: 'agents.searchHint'.tr(),
                                    hintStyle: TextStyle(color: t.fg4),
                                  ),
                                  onChanged: (v) => setState(() => _query = v),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 30,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final f in filters)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: _FilterChip(
                                    label: f[1] as String,
                                    count: f[2] as int,
                                    selected: _filter == f[0],
                                    onTap: () => setState(
                                        () => _filter = f[0] as String),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              all.isEmpty
                                  ? 'agents.noNodes'.tr()
                                  : 'agents.noMatch'.tr(),
                              style: TextStyle(color: t.fg4, fontSize: 13.5),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (ctx, i) => _AgentCard(
                              agent: filtered[i],
                              metrics: provider.metricsFor(filtered[i].id),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 16,
              bottom: 16 + MediaQuery.of(context).padding.bottom,
              child: FloatingActionButton.extended(
                heroTag: 'agents-switch-server',
                backgroundColor: t.accent,
                foregroundColor: t.isIOS ? Colors.white : t.onAccent,
                onPressed: () => showServerSwitchSheet(context),
                icon: const Icon(Icons.dns_rounded, size: 18),
                label: Text('agents.switchServer'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showFilterSheet(AppProvider provider, List<List<dynamic>> filters) {
    final t = context.nano;
    showModalBottomSheet(
      context: context,
      backgroundColor: t.card,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(t.isIOS ? 16 : 28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('agents.filter'.tr(),
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: t.fg)),
              ),
              for (final f in filters)
                ListTile(
                  onTap: () {
                    setState(() => _filter = f[0] as String);
                    Navigator.pop(ctx);
                  },
                  title: Text(f[1] as String,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: t.fg)),
                  trailing: _filter == f[0]
                      ? Icon(Icons.check_rounded, color: t.accent, size: 20)
                      : Text('${f[2]}',
                          style: TextStyle(
                              fontSize: 13,
                              color: t.fg4,
                              fontFamilyFallback: kMonoFallback)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label,
      required this.count,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    // Material look: `.md-chip` — radius 8, fg-4 outline, surface-3 selected
    // fill, leading check icon. iOS keeps the inverted pill.
    if (!t.isIOS) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? t.card2 : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? t.card2 : t.fg4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check_rounded, size: 16, color: t.fg),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: selected ? t.fg : t.fg2)),
              const SizedBox(width: 5),
              Text('$count',
                  style: TextStyle(
                      fontSize: 11,
                      color: t.fg4,
                      fontFamilyFallback: kMonoFallback)),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? t.fg : t.card,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: selected ? t.bg : t.fg2)),
            const SizedBox(width: 5),
            Text('$count',
                style: TextStyle(
                    fontSize: 11,
                    color: selected ? t.bg.withValues(alpha: 0.7) : t.fg4,
                    fontFamilyFallback: kMonoFallback)),
          ],
        ),
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  final Agent agent;
  final AgentMetrics? metrics;
  const _AgentCard({required this.agent, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return NanoCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AgentDetailScreen(agent: agent)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NanoIconBox(_osIcon(agent.os)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NanoMono(agent.hostname,
                        size: 14,
                        weight: FontWeight.w600,
                        color: t.fg,
                        overflow: TextOverflow.ellipsis),
                    Text('${agent.os} · ${agent.arch}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: t.fg4)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  NanoStatusLabel(
                      status: agent.isOnline ? 'online' : 'offline'),
                  const SizedBox(height: 5),
                  NanoPermPill(level: agent.permissionLevel),
                ],
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.more_horiz_rounded, color: t.fg4, size: 20),
                onPressed: () => showAgentActionsSheet(context, agent: agent),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 46, right: 6, top: 4),
            child: _summary(context),
          ),
        ],
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final t = context.nano;
    final m = metrics;
    if (!agent.isOnline || m == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: 14, color: t.fg4),
            const SizedBox(width: 6),
            Text('agents.offlineNoData'.tr(),
                style: TextStyle(fontSize: 12, color: t.fg4)),
          ],
        ),
      );
    }
    final cpu = m.cpuPercent;
    final mem = m.memoryPercent;
    DiskMetrics? worst;
    for (final d in m.disks) {
      if (worst == null || d.usagePercent > worst.usagePercent) worst = d;
    }
    String tone(double v) => v > 90
        ? 'crit'
        : v > 75
            ? 'warn'
            : '';
    final temp = m.cpu.temperature;
    final cpuSub = temp > 0
        ? '${m.cpu.coreCount}c · ${temp.toStringAsFixed(0)}°C'
        : '${m.cpu.coreCount}c';
    return Column(
      children: [
        const SizedBox(height: 4),
        NanoMetricRow(
          icon: Icons.memory_rounded,
          label: 'history.cpu'.tr(),
          pct: cpu,
          value: '${cpu.toStringAsFixed(0)}%',
          sub: cpuSub,
          tone: tone(cpu).isEmpty ? null : tone(cpu),
        ),
        const SizedBox(height: 6),
        NanoMetricRow(
          icon: Icons.sd_storage_outlined,
          label: 'history.memory'.tr(),
          pct: mem,
          value: '${mem.toStringAsFixed(0)}%',
          sub:
              '${Fmt.gib(m.memory.used).toStringAsFixed(0)}/${Fmt.gib(m.memory.total).toStringAsFixed(0)}G',
          tone: tone(mem).isEmpty ? null : tone(mem),
        ),
        if (worst != null) ...[
          const SizedBox(height: 6),
          NanoMetricRow(
            icon: Icons.storage_rounded,
            label: 'metrics.disk'.tr(),
            pct: worst.usagePercent,
            value: '${worst.usagePercent.toStringAsFixed(0)}%',
            sub: worst.mountPoint,
            tone: tone(worst.usagePercent).isEmpty
                ? null
                : tone(worst.usagePercent),
          ),
        ],
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
