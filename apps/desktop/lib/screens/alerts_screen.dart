import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../design/nano_tokens.dart';
import '../providers/app_provider.dart';
import '../widgets/nano/nano_card.dart';
import '../widgets/nano/nano_primitives.dart';

enum _Level { crit, warn, info }

class _Alert {
  final _Level level;
  final String title;
  final String detail;
  final String? agent;
  const _Alert(this.level, this.title, this.detail, {this.agent});
}

/// Activity & alerts tab. Alerts are derived client-side from live agent state
/// (offline nodes, high CPU/memory, low disk) — matching the design's behaviour.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        final alerts = _deriveAlerts(provider);
        final crit = alerts.where((a) => a.level == _Level.crit).length;
        final warn = alerts.where((a) => a.level == _Level.warn).length;
        final info = alerts.where((a) => a.level == _Level.info).length;

        return SafeArea(
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, t.isIOS ? 8 : 4, 16, 96),
            children: [
              _Header(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _MiniStat('alerts.critical'.tr(), crit, t.crit)),
                  const SizedBox(width: 8),
                  Expanded(child: _MiniStat('alerts.warning'.tr(), warn, t.warn)),
                  const SizedBox(width: 8),
                  Expanded(child: _MiniStat('alerts.info'.tr(), info, t.info)),
                ],
              ),
              const SizedBox(height: 4),
              NanoSectionLabel('alerts.current'.tr()),
              if (alerts.isEmpty)
                NanoCard(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Column(
                      children: [
                        Icon(Icons.check_circle_outline_rounded,
                            color: t.ok, size: 30),
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
                )
              else
                NanoCard(
                  child: Column(
                    children: [
                      for (var i = 0; i < alerts.length; i++)
                        _AlertRow(alert: alerts[i], divider: i < alerts.length - 1),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  List<_Alert> _deriveAlerts(AppProvider provider) {
    final out = <_Alert>[];
    final agents = provider.agentsForServer();
    for (final a in agents) {
      if (!a.isOnline) {
        out.add(_Alert(
            _Level.crit,
            'alerts.nodeOffline'.tr(namedArgs: {'host': a.hostname}),
            'alerts.nodeOfflineDetail'.tr(),
            agent: a.hostname));
        continue;
      }
      final m = provider.metricsFor(a.id);
      if (m == null) continue;
      final cpu = m.cpuPercent;
      final mem = m.memoryPercent;
      if (cpu > 90) {
        out.add(_Alert(
            _Level.crit,
            'alerts.cpuPressure'.tr(namedArgs: {'host': a.hostname}),
            'alerts.usageDetail'
                .tr(namedArgs: {'value': cpu.toStringAsFixed(0)}),
            agent: a.hostname));
      } else if (cpu > 80) {
        out.add(_Alert(
            _Level.warn,
            'alerts.cpuHigh'.tr(namedArgs: {'host': a.hostname}),
            'alerts.usageDetail'
                .tr(namedArgs: {'value': cpu.toStringAsFixed(0)}),
            agent: a.hostname));
      }
      if (mem > 90) {
        out.add(_Alert(
            _Level.crit,
            'alerts.memPressure'.tr(namedArgs: {'host': a.hostname}),
            'alerts.usageDetail'
                .tr(namedArgs: {'value': mem.toStringAsFixed(0)}),
            agent: a.hostname));
      } else if (mem > 80) {
        out.add(_Alert(
            _Level.warn,
            'alerts.memHigh'.tr(namedArgs: {'host': a.hostname}),
            'alerts.usageDetail'
                .tr(namedArgs: {'value': mem.toStringAsFixed(0)}),
            agent: a.hostname));
      }
      for (final d in m.disks) {
        if (d.usagePercent > 90) {
          out.add(_Alert(
              _Level.crit,
              'alerts.diskFull'.tr(namedArgs: {'host': a.hostname}),
              'alerts.diskDetail'.tr(namedArgs: {
                'mount': d.mountPoint,
                'value': d.usagePercent.toStringAsFixed(0)
              }),
              agent: a.hostname));
        } else if (d.usagePercent > 85) {
          out.add(_Alert(
              _Level.warn,
              'alerts.diskLow'.tr(namedArgs: {'host': a.hostname}),
              'alerts.diskDetail'.tr(namedArgs: {
                'mount': d.mountPoint,
                'value': d.usagePercent.toStringAsFixed(0)
              }),
              agent: a.hostname));
        }
      }
    }
    out.sort((x, y) => x.level.index.compareTo(y.level.index));
    return out;
  }
}

class _Header extends StatelessWidget {
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
            child: Text('alerts.title'.tr(),
                style: TextStyle(
                    fontSize: t.isIOS ? 32 : 28,
                    fontWeight: t.displayWeight,
                    letterSpacing: t.displayTracking,
                    color: t.fg)),
          ),
        ],
      ),
    );
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w500, color: t.fg3)),
            ],
          ),
          const SizedBox(height: 4),
          Text('$value',
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w600, color: t.fg)),
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  final _Alert alert;
  final bool divider;
  const _AlertRow({required this.alert, required this.divider});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final color = alert.level == _Level.crit
        ? t.crit
        : alert.level == _Level.warn
            ? t.warn
            : t.info;
    return NanoListRow(
      divider: divider,
      crossAxis: CrossAxisAlignment.start,
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.warning_amber_rounded, color: color, size: 16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(alert.title,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w500, color: t.fg)),
          const SizedBox(height: 2),
          Text(alert.detail,
              style: TextStyle(fontSize: 12, color: t.fg3, height: 1.4)),
          if (alert.agent != null) ...[
            const SizedBox(height: 6),
            NanoBadge(alert.agent!, mono: true),
          ],
        ],
      ),
    );
  }
}
