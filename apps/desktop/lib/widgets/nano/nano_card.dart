import 'package:flutter/material.dart';
import '../../design/nano_tokens.dart';

/// Grouped card surface (iOS inset-grouped / Material filled card).
class NanoCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? color;
  final bool outlined;
  const NanoCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.color,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? t.card,
        borderRadius: BorderRadius.circular(t.cardRadius),
        border: outlined ? Border.all(color: t.sep, width: 1) : null,
      ),
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(t.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: content),
      );
    }
    if (margin != null) content = Padding(padding: margin!, child: content);
    return content;
  }
}

/// A single tappable row inside a [NanoCard], with optional hairline divider.
class NanoListRow extends StatelessWidget {
  final Widget? leading;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool divider;
  final EdgeInsetsGeometry padding;
  final CrossAxisAlignment crossAxis;
  const NanoListRow({
    super.key,
    this.leading,
    required this.child,
    this.trailing,
    this.onTap,
    this.divider = true,
    this.padding = const EdgeInsets.fromLTRB(16, 11, 16, 11),
    this.crossAxis = CrossAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    Widget row = Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: crossAxis,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(child: child),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
    if (divider) {
      row = DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.sep2, width: 0.5)),
        ),
        child: row,
      );
    }
    if (onTap != null) {
      return InkWell(onTap: onTap, child: row);
    }
    return row;
  }
}

/// Rounded square icon container used as a list-row leading element.
class NanoIconBox extends StatelessWidget {
  final IconData icon;
  final double size;
  final double iconSize;
  final Color? bg;
  final Color? fg;
  final Gradient? gradient;
  const NanoIconBox(
    this.icon, {
    super.key,
    this.size = 36,
    this.iconSize = 18,
    this.bg,
    this.fg,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: gradient == null ? (bg ?? t.card2) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Icon(icon, size: iconSize, color: fg ?? t.fg3),
    );
  }
}
