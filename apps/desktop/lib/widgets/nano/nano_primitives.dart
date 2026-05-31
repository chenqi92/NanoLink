import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../design/nano_tokens.dart';

/// Small status dot (online/offline/warn) with optional pulse glow.
class NanoStatusDot extends StatefulWidget {
  final Color color;
  final double size;
  final bool pulse;
  const NanoStatusDot({
    super.key,
    required this.color,
    this.size = 7,
    this.pulse = false,
  });

  @override
  State<NanoStatusDot> createState() => _NanoStatusDotState();
}

class _NanoStatusDotState extends State<NanoStatusDot>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    if (widget.pulse) {
      _c = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 2),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
    );
    if (_c == null) return dot;
    return AnimatedBuilder(
      animation: _c!,
      builder: (_, child) {
        final v = (0.5 - (_c!.value - 0.5).abs()) * 2; // triangle 0..1..0
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.45 * (1 - v)),
                blurRadius: 0,
                spreadRadius: widget.size * 0.7 * v,
              ),
            ],
          ),
          child: child,
        );
      },
      child: dot,
    );
  }
}

/// Status pill = dot + localized label (online / offline / connecting).
class NanoStatusLabel extends StatelessWidget {
  final String status; // online | offline | connecting
  const NanoStatusLabel({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    late Color c;
    late String label;
    switch (status) {
      case 'online':
        c = t.ok;
        label = 'status.online'.tr();
      case 'connecting':
        c = t.warn;
        label = 'status.connecting'.tr();
      default:
        c = t.crit;
        label = 'status.offline'.tr();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        NanoStatusDot(color: c, pulse: status == 'online'),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12, color: t.fg3)),
      ],
    );
  }
}

/// Generic colored badge chip.
class NanoBadge extends StatelessWidget {
  final String text;
  final Color? color; // foreground; background derived
  final IconData? icon;
  final bool mono;
  const NanoBadge(this.text, {super.key, this.color, this.icon, this.mono = false});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final fg = color ?? t.fg3;
    final bg = color == null ? t.card2 : color!.withValues(alpha: 0.14);
    return Container(
      height: 19,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(5)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 11, color: fg), const SizedBox(width: 4)],
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: fg,
              fontFamilyFallback: mono ? kMonoFallback : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Permission-level pill (L0..L3) with name.
class NanoPermPill extends StatelessWidget {
  final int level;
  const NanoPermPill({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final c = t.permColor(level);
    final lv = level.clamp(0, 3);
    final labels = [
      'perm.l0'.tr(),
      'perm.l1'.tr(),
      'perm.l2'.tr(),
      'perm.l3'.tr(),
    ];
    return Container(
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Text(
          'L$lv · ${labels[lv]}',
          style: TextStyle(
            fontSize: 10.5,
            height: 1,
            fontWeight: FontWeight.w600,
            color: c,
            fontFamilyFallback: kMonoFallback,
          ),
        ),
      ),
    );
  }
}

/// Thin linear usage meter.
class NanoMeter extends StatelessWidget {
  final double value; // 0..1
  final Color? color;
  final double height;
  const NanoMeter({super.key, required this.value, this.color, this.height = 4});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final c = color ?? t.meterColor(value * 100);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Stack(
        children: [
          Container(height: height, color: t.card3),
          FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              height: height,
              decoration: BoxDecoration(
                color: c,
                borderRadius: BorderRadius.circular(height / 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section header label used between grouped cards.
class NanoSectionLabel extends StatelessWidget {
  final String label;
  final Widget? trailing;
  final bool grouped; // iOS uppercase grouped style
  const NanoSectionLabel(this.label, {super.key, this.trailing, this.grouped = false});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Padding(
      padding: EdgeInsets.fromLTRB(4, grouped ? 12 : 10, 4, grouped ? 7 : 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              grouped ? label.toUpperCase() : label,
              style: TextStyle(
                fontSize: grouped ? 11.5 : 13,
                fontWeight: grouped ? FontWeight.w400 : FontWeight.w600,
                letterSpacing: grouped ? 0.4 : 0,
                color: grouped ? t.fg3 : t.fg2,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Monospace text helper.
class NanoMono extends StatelessWidget {
  final String text;
  final double size;
  final Color? color;
  final FontWeight weight;
  final TextOverflow? overflow;
  const NanoMono(
    this.text, {
    super.key,
    this.size = 12,
    this.color,
    this.weight = FontWeight.w400,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Text(
      text,
      overflow: overflow,
      style: TextStyle(
        fontSize: size,
        height: 1.3,
        color: color ?? t.fg2,
        fontWeight: weight,
        fontFamilyFallback: kMonoFallback,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
