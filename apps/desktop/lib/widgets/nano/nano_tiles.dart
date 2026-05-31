import 'package:flutter/material.dart';
import '../../design/nano_tokens.dart';
import 'nano_charts.dart';
import 'nano_primitives.dart';

/// KPI summary tile used on the dashboard (label, big value, sub, optional spark).
class NanoKpiTile extends StatelessWidget {
  final String label;
  final Widget value;
  final String sub;
  final IconData icon;
  final String? tone; // 'warn' | 'crit' | null
  final List<double>? spark;
  final Color? background;
  const NanoKpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    this.tone,
    this.spark,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final toneColor = tone == 'crit'
        ? t.crit
        : tone == 'warn'
            ? t.warn
            : t.accent;
    final valueColor = tone == 'crit'
        ? t.crit
        : tone == 'warn'
            ? t.warn
            : t.fg;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: background ?? t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: t.fg3),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w500, color: t.fg3)),
            ],
          ),
          const SizedBox(height: 4),
          DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
              height: 1.1,
              color: valueColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            child: value,
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  sub,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: t.fg4,
                    fontFamilyFallback: kMonoFallback,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (spark != null)
                NanoSparkline(data: spark!, color: toneColor),
            ],
          ),
        ],
      ),
    );
  }
}

/// Row: leading icon + short label + meter + right-aligned value/sub.
class NanoMetricRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final double? pct; // 0..100
  final String? tone;
  const NanoMetricRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
    this.pct,
    this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final toneColor = tone == 'crit'
        ? t.crit
        : tone == 'warn'
            ? t.warn
            : t.fg;
    return Row(
      children: [
        SizedBox(width: 16, child: Icon(icon, size: 13, color: t.fg4)),
        const SizedBox(width: 10),
        SizedBox(
          width: 28,
          child: Text(label,
              style: TextStyle(
                fontSize: 11,
                color: t.fg3,
                fontFamilyFallback: kMonoFallback,
              )),
        ),
        const SizedBox(width: 10),
        if (pct != null)
          Expanded(child: NanoMeter(value: pct! / 100, color: tone == null ? null : toneColor))
        else
          const Spacer(),
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 60),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: toneColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
              if (sub != null)
                Text(sub!,
                    style: TextStyle(
                      fontSize: 10,
                      color: t.fg4,
                      fontFamilyFallback: kMonoFallback,
                    )),
            ],
          ),
        ),
      ],
    );
  }
}
