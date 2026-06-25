import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/nano_tokens.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../widgets/nano/nano_card.dart';
import '../widgets/nano/nano_primitives.dart';

/// Read-only permissions & roles overview for the active server.
///
/// Groups the active server's agents by their server-assigned
/// `permissionLevel` (L0 read-only → L3 system admin) using the real
/// [AppProvider.agentsForServer] feed. Each group is labelled with its tier and
/// lists the nodes that hold it, with an online/offline status dot.
class PermissionsScreen extends StatelessWidget {
  const PermissionsScreen({super.key});

  static const _levels = [3, 2, 1, 0]; // most → least privileged

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final provider = context.watch<AppProvider>();
    final agents = provider.agentsForServer();

    final byLevel = <int, List<Agent>>{for (final l in _levels) l: []};
    for (final a in agents) {
      final l = a.permissionLevel.clamp(0, 3);
      byLevel[l]!.add(a);
    }
    for (final list in byLevel.values) {
      list.sort((x, y) => x.hostname.compareTo(y.hostname));
    }

    return Scaffold(
      backgroundColor: t.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _PermHeader(),
            Expanded(
              child: agents.isEmpty
                  ? _Empty()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                          child: Text('permissions.intro'.tr(),
                              style: TextStyle(
                                  fontSize: 13, color: t.fg3, height: 1.45)),
                        ),
                        for (final level in _levels)
                          _LevelGroup(
                              level: level, agents: byLevel[level] ?? const []),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Padding(
      padding: EdgeInsets.fromLTRB(4, t.isIOS ? 12 : 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
                t.isIOS
                    ? Icons.arrow_back_ios_new_rounded
                    : Icons.arrow_back_rounded,
                color: t.isIOS ? t.accent : t.fg,
                size: t.isIOS ? 20 : 24),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text('permissions.title'.tr(),
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: t.isIOS ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: t.displayTracking,
                    color: t.fg)),
          ),
        ],
      ),
    );
  }
}

class _LevelGroup extends StatelessWidget {
  final int level;
  final List<Agent> agents;
  const _LevelGroup({required this.level, required this.agents});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NanoSectionLabel(
          'permissions.levelGroup'.tr(namedArgs: {'n': '${agents.length}'}),
          trailing: NanoPermPill(level: level),
        ),
        NanoCard(
          child: agents.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Text('permissions.noneAtLevel'.tr(),
                      style: TextStyle(fontSize: 13, color: t.fg4)),
                )
              : Column(
                  children: [
                    for (var i = 0; i < agents.length; i++)
                      _AgentPermRow(
                        agent: agents[i],
                        divider: i < agents.length - 1,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _AgentPermRow extends StatelessWidget {
  final Agent agent;
  final bool divider;
  const _AgentPermRow({required this.agent, required this.divider});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final online = agent.isOnline;
    return NanoListRow(
      divider: divider,
      leading: NanoStatusDot(
          color: online ? t.ok : t.crit, pulse: online, size: 8),
      trailing: Text(online ? 'status.online'.tr() : 'status.offline'.tr(),
          style: TextStyle(fontSize: 12, color: online ? t.fg3 : t.fg4)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(agent.hostname,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: t.fg,
                  fontFamilyFallback: kMonoFallback)),
          const SizedBox(height: 2),
          Text('${agent.os} · ${agent.arch}',
              style: TextStyle(fontSize: 12, color: t.fg3)),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
      children: [
        Icon(Icons.shield_outlined, color: t.fg4, size: 34),
        const SizedBox(height: 12),
        Center(
          child: Text('permissions.empty'.tr(),
              style: TextStyle(
                  color: t.fg2, fontSize: 15, fontWeight: FontWeight.w500)),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text('permissions.emptySub'.tr(),
              style: TextStyle(color: t.fg4, fontSize: 12.5)),
        ),
      ],
    );
  }
}
