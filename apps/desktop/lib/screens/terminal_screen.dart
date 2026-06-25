import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/nano_tokens.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../utils/format.dart';
import '../widgets/nano/nano_card.dart';
import '../widgets/nano/nano_primitives.dart';
import 'agent_detail_screen.dart';

/// Audit `commandType` values that represent a remote-shell command. The server
/// records `Type.String()` of the proto CommandType, so SHELL_EXECUTE is the
/// canonical value; the lowercase variants are tolerated for older records.
const _shellAuditTypes = {
  'SHELL_EXECUTE',
  'shell',
  'shell.exec',
};

/// Terminal navigation tab: pick an online node to open its remote shell.
/// L0 read-only nodes are not eligible; the actual session needs L3.
class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    await context.read<AppProvider>().fetchRecentActivity(limit: 50);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final agents = provider.agentsForServer()
          ..removeWhere((a) => !a.isOnline || a.permissionLevel == 0);
        agents.sort((a, b) => a.hostname.compareTo(b.hostname));

        // Recent shell sessions: shell-exec audit entries, newest first.
        final sessions = provider
            .recentActivity()
            .where((e) => _shellAuditTypes.contains(e.type))
            .toList()
          ..sort((a, b) => b.at.compareTo(a.at));
        final recent = sessions.take(5).toList();

        return SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, t.isIOS ? 40 : 8, 16, 0),
                child: Row(
                  children: [
                    if (!t.isIOS)
                      Builder(
                        builder: (ctx) => Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: IconButton(
                            icon: Icon(Icons.menu_rounded, color: t.fg),
                            onPressed: () => Scaffold.of(ctx).openDrawer(),
                          ),
                        ),
                      ),
                    Text('terminal.navTitle'.tr(),
                        style: TextStyle(
                            fontSize: t.isIOS ? 32 : 28,
                            fontWeight: t.displayWeight,
                            letterSpacing: t.displayTracking,
                            color: t.fg)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                child: Text('terminal.navDesc'.tr(),
                    style: TextStyle(fontSize: 13.5, color: t.fg3, height: 1.5)),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  color: t.accent,
                  child: (agents.isEmpty && recent.isEmpty)
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.5,
                              child: _empty(t),
                            ),
                          ],
                        )
                      : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                          children: [
                            if (agents.isEmpty)
                              _emptyInline(t)
                            else
                              NanoCard(
                                padding: EdgeInsets.zero,
                                child: Column(
                                  children: [
                                    for (var i = 0; i < agents.length; i++)
                                      _AgentRow(
                                        agent: agents[i],
                                        divider: i < agents.length - 1,
                                      ),
                                  ],
                                ),
                              ),
                            if (recent.isNotEmpty) ...[
                              NanoSectionLabel(
                                'terminal.recentSessions'.tr(),
                                grouped: t.isIOS,
                              ),
                              NanoCard(
                                padding: EdgeInsets.zero,
                                child: Column(
                                  children: [
                                    for (var i = 0; i < recent.length; i++)
                                      _SessionRow(
                                        entry: recent[i],
                                        divider: i < recent.length - 1,
                                        agent: _matchAgent(provider, recent[i]),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Find an online, L1+ agent matching the audit entry so a tapped session can
  /// reopen the terminal; null if the node is gone/offline/read-only.
  Agent? _matchAgent(AppProvider provider, AuditEntry e) {
    for (final a in provider.agentsForServer()) {
      final matchesId = e.agentId.isNotEmpty && a.id == e.agentId;
      final matchesHost =
          e.agentHostname.isNotEmpty && a.hostname == e.agentHostname;
      if ((matchesId || matchesHost) && a.isOnline && a.permissionLevel > 0) {
        return a;
      }
    }
    return null;
  }

  Widget _empty(NanoTokens t) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.terminal_rounded, size: 30, color: t.fg4),
          const SizedBox(height: 12),
          Text('terminal.noAvailableNodes'.tr(),
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w500, color: t.fg2)),
          const SizedBox(height: 6),
          Text('terminal.noAvailableNodesSub'.tr(),
              style: TextStyle(fontSize: 12.5, color: t.fg4)),
        ],
      ),
    );
  }

  // Compact empty-node notice shown above a non-empty recent-sessions list.
  Widget _emptyInline(NanoTokens t) {
    return NanoCard(
      child: Row(
        children: [
          Icon(Icons.terminal_rounded, size: 20, color: t.fg4),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('terminal.noAvailableNodes'.tr(),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: t.fg2)),
                const SizedBox(height: 2),
                Text('terminal.noAvailableNodesSub'.tr(),
                    style: TextStyle(fontSize: 12, color: t.fg4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentRow extends StatelessWidget {
  final Agent agent;
  final bool divider;
  const _AgentRow({required this.agent, required this.divider});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return NanoListRow(
      divider: divider,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AgentDetailScreen(agent: agent, initialTab: 2),
        ),
      ),
      leading: NanoIconBox(_osIcon(agent.os)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          NanoPermPill(level: agent.permissionLevel),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, color: t.fg4, size: 20),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NanoMono(agent.hostname,
              size: 14, weight: FontWeight.w600, color: t.fg,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 1),
          Text('${agent.os} · ${agent.arch}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: t.fg4)),
        ],
      ),
    );
  }
}

/// One row in the 最近会话 list: a past shell command from the audit log.
/// Mirrors android-app2.jsx MDTerminalTab L429-441 (term icon + agent + params
/// + relative time). Tapping reopens the terminal when the node is reachable.
class _SessionRow extends StatelessWidget {
  final AuditEntry entry;
  final bool divider;
  final Agent? agent;
  const _SessionRow({
    required this.entry,
    required this.divider,
    required this.agent,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    // Command text: prefer the audit target, else a "command" param, else type.
    final params = entry.paramsMap;
    final command = entry.target.isNotEmpty
        ? entry.target
        : (params['command'] ?? params['cmd'] ?? entry.type).toString();
    final host =
        entry.agentHostname.isNotEmpty ? entry.agentHostname : entry.agentId;

    final reachable = agent != null;
    return NanoListRow(
      divider: divider,
      onTap: reachable
          ? () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      AgentDetailScreen(agent: agent!, initialTab: 2),
                ),
              )
          : null,
      leading: NanoIconBox(
        Icons.terminal_rounded,
        size: 32,
        iconSize: 15,
        fg: entry.ok ? t.accent : t.crit,
      ),
      trailing: Text(
        Fmt.ago(entry.at),
        style: TextStyle(fontSize: 11, color: t.fg4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: NanoMono(host,
                    size: 13.5, weight: FontWeight.w500, color: t.fg,
                    overflow: TextOverflow.ellipsis),
              ),
              if (!entry.ok) ...[
                const SizedBox(width: 6),
                NanoBadge('terminal.sessionFailed'.tr(), color: t.crit),
              ],
            ],
          ),
          const SizedBox(height: 1),
          NanoMono(command,
              size: 11.5, color: t.fg3, overflow: TextOverflow.ellipsis),
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
