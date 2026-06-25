import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/nano_tokens.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../widgets/nano/nano_card.dart';
import '../widgets/nano/nano_primitives.dart';

/// Activity & alerts tab. Alerts and the recent-audit feed are wired to the
/// live server APIs (`/alerts`, `/audit`) through [AppProvider]. Pull to refresh
/// re-fetches both. Swipe or tap an alert to acknowledge it.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    // Fetch after first frame so context.read is safe and the provider can
    // notify listeners (which rebuilds the Consumer below).
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final provider = context.read<AppProvider>();
    await Future.wait([
      provider.fetchServerAlerts(),
      provider.fetchRecentActivity(limit: 50),
    ]);
  }

  Future<void> _ackOne(String id) async {
    final provider = context.read<AppProvider>();
    final err = await provider.acknowledgeAlert(id);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('alerts.ackFailed'.tr(namedArgs: {'error': err}))),
      );
    }
  }

  Future<void> _ackAll() async {
    if (_clearing) return;
    final provider = context.read<AppProvider>();
    setState(() => _clearing = true);
    final count = await provider.acknowledgeAllAlerts();
    if (!mounted) return;
    setState(() => _clearing = false);
    final messenger = ScaffoldMessenger.of(context);
    if (count == null) {
      messenger.showSnackBar(
        SnackBar(content: Text('alerts.clearAllFailed'.tr())),
      );
    } else if (count > 0) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('alerts.clearedCount'.tr(namedArgs: {'n': '$count'})),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final firing =
            provider.serverAlerts().where((a) => !a.acked).toList()
              ..sort((x, y) => _levelRank(x.level).compareTo(_levelRank(y.level)));
        final audit = provider.recentActivity();
        final crit = firing.where((a) => a.level == 'crit').length;
        final warn = firing.where((a) => a.level == 'warn').length;
        final info = firing.where((a) => a.level == 'info').length;

        return SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: _refresh,
            color: t.accent,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, t.isIOS ? 8 : 4, 16, 96),
              children: [
                _Header(
                  clearing: _clearing,
                  canClear: firing.isNotEmpty,
                  onClearAll: _ackAll,
                ),
                const SizedBox(height: 12),
                // Stat summary: single outlined card with vertical dividers.
                NanoCard(
                  outlined: true,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                          child: _MiniStat('alerts.critical'.tr(), crit, t.crit)),
                      _StatDivider(),
                      Expanded(
                          child: _MiniStat('alerts.warning'.tr(), warn, t.warn)),
                      _StatDivider(),
                      Expanded(child: _MiniStat('alerts.info'.tr(), info, t.info)),
                    ],
                  ),
                ),
                NanoSectionLabel('alerts.current'.tr()),
                if (firing.isEmpty)
                  _EmptyAlerts()
                else
                  for (var i = 0; i < firing.length; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: i < firing.length - 1 ? 8 : 0),
                      child: _AlertCard(
                        alert: firing[i],
                        onAck: () => _ackOne(firing[i].id),
                      ),
                    ),
                NanoSectionLabel('alerts.auditRecent'.tr()),
                if (audit.isEmpty)
                  NanoCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 22),
                      child: Center(
                        child: Text('alerts.auditEmpty'.tr(),
                            style: TextStyle(color: t.fg4, fontSize: 12.5)),
                      ),
                    ),
                  )
                else
                  NanoCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < audit.length && i < 6; i++)
                          _AuditRow(
                            entry: audit[i],
                            divider: i < audit.length - 1 && i < 5,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static int _levelRank(String level) {
    switch (level) {
      case 'crit':
        return 0;
      case 'warn':
        return 1;
      default:
        return 2;
    }
  }
}

class _Header extends StatelessWidget {
  final bool clearing;
  final bool canClear;
  final VoidCallback onClearAll;
  const _Header({
    required this.clearing,
    required this.canClear,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Padding(
      padding: EdgeInsets.only(top: t.isIOS ? 40 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!t.isIOS)
            Builder(
              builder: (ctx) => IconButton(
                icon: Icon(Icons.menu_rounded, color: t.fg),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
          Expanded(
            child: Text('alerts.title'.tr(),
                style: TextStyle(
                    fontSize: t.isIOS ? 32 : 28,
                    fontWeight: t.displayWeight,
                    letterSpacing: t.displayTracking,
                    color: t.fg)),
          ),
          if (clearing)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: t.accent),
            )
          else
            TextButton(
              onPressed: canClear ? onClearAll : null,
              style: TextButton.styleFrom(
                foregroundColor: t.accent,
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text('alerts.clearAll'.tr(),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: canClear ? t.accent : t.fg4,
                  )),
            ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Container(width: 1, height: 38, color: t.sep);
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _MiniStat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$value',
            style: TextStyle(
              fontSize: 26,
              fontWeight: t.isIOS ? FontWeight.w600 : FontWeight.w500,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: t.fg3)),
          ],
        ),
      ],
    );
  }
}

class _EmptyAlerts extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return NanoCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(
          children: [
            Icon(Icons.check_circle_outline_rounded, color: t.ok, size: 30),
            const SizedBox(height: 10),
            Text('alerts.allClear'.tr(),
                style: TextStyle(
                    color: t.fg2,
                    fontSize: 15,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text('alerts.allClearSub'.tr(),
                style: TextStyle(color: t.fg4, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

/// A single alert with a 4px severity-colored left border, a circular 36 badge,
/// the humanized `since` time, an agent chip, and swipe/tap to acknowledge.
class _AlertCard extends StatelessWidget {
  final AlertInstance alert;
  final VoidCallback onAck;
  const _AlertCard({required this.alert, required this.onAck});

  Color _color(NanoTokens t) {
    switch (alert.level) {
      case 'crit':
        return t.crit;
      case 'warn':
        return t.warn;
      default:
        return t.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final color = _color(t);

    final card = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(t.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onAck,
        child: Container(
          decoration: BoxDecoration(
            color: t.card,
            borderRadius: BorderRadius.circular(t.cardRadius),
            border: Border(left: BorderSide(color: color, width: 4)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.warning_amber_rounded, color: color, size: 16),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(alert.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: t.fg)),
                        ),
                        if (alert.since.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(alert.since,
                              style: TextStyle(fontSize: 11, color: t.fg4)),
                        ],
                      ],
                    ),
                    if (alert.description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(alert.description,
                          style: TextStyle(
                              fontSize: 12.5, color: t.fg3, height: 1.4)),
                    ],
                    if (alert.agent.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      NanoBadge(alert.agent, mono: true),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Dismissible(
      key: ValueKey('alert-${alert.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onAck(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: t.ok.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(t.cardRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, color: t.ok, size: 18),
            const SizedBox(width: 6),
            Text('alerts.acknowledge'.tr(),
                style: TextStyle(
                    color: t.ok, fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      child: card,
    );
  }
}

/// Recent-audit row: ok/crit dot + mono type + relative time + user → agent.
class _AuditRow extends StatelessWidget {
  final AuditEntry entry;
  final bool divider;
  const _AuditRow({required this.entry, required this.divider});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final agent =
        entry.agentHostname.isNotEmpty ? entry.agentHostname : '—';
    return NanoListRow(
      divider: divider,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      leading: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: entry.ok ? t.ok : t.crit,
          shape: BoxShape.circle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(entry.type,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: t.fg,
                      fontFamilyFallback: kMonoFallback,
                    )),
              ),
              const SizedBox(width: 6),
              Text(_relativeTime(context, entry.at),
                  style: TextStyle(fontSize: 11, color: t.fg4)),
            ],
          ),
          const SizedBox(height: 1),
          Row(
            children: [
              Flexible(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 12, color: t.fg3),
                    children: [
                      TextSpan(text: entry.user.isNotEmpty ? entry.user : '—'),
                      const TextSpan(text: '  →  '),
                      TextSpan(
                        text: agent,
                        style: TextStyle(fontFamilyFallback: kMonoFallback),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _relativeTime(BuildContext context, DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inSeconds < 60) {
      return 'time.secondsAgo'
          .tr(namedArgs: {'n': '${diff.inSeconds.clamp(1, 59)}'});
    }
    if (diff.inMinutes < 60) {
      return 'time.minutesAgo'.tr(namedArgs: {'n': '${diff.inMinutes}'});
    }
    if (diff.inHours < 24) {
      return 'time.hoursAgo'.tr(namedArgs: {'n': '${diff.inHours}'});
    }
    return 'time.daysAgo'.tr(namedArgs: {'n': '${diff.inDays}'});
  }
}
