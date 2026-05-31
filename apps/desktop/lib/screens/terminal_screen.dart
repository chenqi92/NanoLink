import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/nano_tokens.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../widgets/nano/nano_card.dart';
import '../widgets/nano/nano_primitives.dart';
import 'agent_detail_screen.dart';

/// Terminal navigation tab: pick an online node to open its remote shell.
/// L0 read-only nodes are not eligible; the actual session needs L3.
class TerminalScreen extends StatelessWidget {
  const TerminalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final agents = provider.agentsForServer()
          ..removeWhere((a) => !a.isOnline || a.permissionLevel == 0);
        agents.sort((a, b) => a.hostname.compareTo(b.hostname));

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
                child: agents.isEmpty
                    ? _empty(t)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        children: [
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
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
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

IconData _osIcon(String os) {
  final s = os.toLowerCase();
  if (s.contains('mac') || s.contains('darwin') || s.contains('ios')) {
    return Icons.apple;
  }
  if (s.contains('win')) return Icons.window;
  return Icons.terminal;
}
