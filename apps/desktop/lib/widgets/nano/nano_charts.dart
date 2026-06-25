import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../design/nano_tokens.dart';

/// Tiny sparkline used inside KPI tiles.
class NanoSparkline extends StatelessWidget {
  final List<double> data;
  final Color color;
  final double width;
  final double height;
  final bool fill;
  const NanoSparkline({
    super.key,
    required this.data,
    required this.color,
    this.width = 56,
    this.height = 18,
    this.fill = false,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _SparkPainter(data, color, fill),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final bool fill;
  _SparkPainter(this.data, this.color, this.fill);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final lo = data.reduce(math.min);
    final hi = data.reduce(math.max);
    final range = (hi - lo) == 0 ? 1 : (hi - lo);
    final step = size.width / math.max(data.length - 1, 1);
    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final x = i * step;
      final y = size.height - ((data[i] - lo) / range) * (size.height - 2) - 1;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    if (fill) {
      final area = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.12));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.data != data || old.color != color;
}

/// One data series for [NanoLineChart].
class NanoSeries {
  final List<double> data;
  final Color color;
  final bool fill;
  final bool dashed;
  final String? label;

  /// Optional per-sample peak values (same length as [data]). When present a
  /// faint band is shaded between [data] and [band] to visualise the bucket
  /// max envelope (DB-aggregated cpuMax/memMax).
  final List<double>? band;
  const NanoSeries(this.data, this.color,
      {this.fill = false, this.dashed = false, this.label, this.band});
}

class NanoThreshold {
  final double value;
  final Color color;
  final String? label;
  const NanoThreshold(this.value, this.color, {this.label});
}

/// Touch-tuned line chart (history graphs). Mirrors `MLineChart`.
class NanoLineChart extends StatelessWidget {
  final List<NanoSeries> series;
  final double height;
  final double? yMax;
  final double yMin;
  final String unit;
  final List<NanoThreshold> thresholds;
  final bool grid;

  /// Pre-computed x-axis labels (start … now). When [times] is supplied the
  /// labels are derived from the real sample timestamps and this is ignored.
  final List<String> xLabels;

  /// Real sample timestamps. When non-empty, three evenly-spaced tick labels
  /// (first / middle / last) are derived from these and rendered instead of
  /// [xLabels]. The newest tick renders as "now".
  final List<DateTime> times;

  const NanoLineChart({
    super.key,
    required this.series,
    this.height = 140,
    this.yMax,
    this.yMin = 0,
    this.unit = '%',
    this.thresholds = const [],
    this.grid = true,
    this.xLabels = const ['-60m', '-30m', 'now'],
    this.times = const [],
  });

  /// Derive three tick labels (start / middle / now) from real timestamps.
  static List<String> labelsFromTimes(List<DateTime> times) {
    if (times.length < 2) return const ['', '', 'now'];
    final first = times.first;
    final last = times.last;
    final mid = times[times.length ~/ 2];
    String rel(DateTime t) {
      final s = last.difference(t).inSeconds;
      if (s <= 30) return 'now';
      if (s < 3600) return '-${(s / 60).round()}m';
      if (s < 86400) return '-${(s / 3600).round()}h';
      return '-${(s / 86400).round()}d';
    }

    return [rel(first), rel(mid), rel(last)];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final labels = times.length >= 2 ? labelsFromTimes(times) : xLabels;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _LinePainter(
          series: series,
          yMax: yMax,
          yMin: yMin,
          unit: unit,
          thresholds: thresholds,
          grid: grid,
          xLabels: labels,
          gridColor: t.sep2,
          axisText: t.fg4,
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<NanoSeries> series;
  final double? yMax;
  final double yMin;
  final String unit;
  final List<NanoThreshold> thresholds;
  final bool grid;
  final List<String> xLabels;
  final Color gridColor;
  final Color axisText;
  _LinePainter({
    required this.series,
    required this.yMax,
    required this.yMin,
    required this.unit,
    required this.thresholds,
    required this.grid,
    required this.xLabels,
    required this.gridColor,
    required this.axisText,
  });

  static const padL = 30.0, padR = 6.0, padT = 6.0, padB = 18.0;

  void _text(Canvas c, String s, Offset o, Color color,
      {TextAlign align = TextAlign.start}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontFamilyFallback: kMonoFallback,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = o.dx;
    if (align == TextAlign.end) dx -= tp.width;
    if (align == TextAlign.center) dx -= tp.width / 2;
    tp.paint(c, Offset(dx, o.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final all = series.expand((s) => s.data);
    final dataMax = all.isEmpty ? 1.0 : all.reduce(math.max);
    final ymax = yMax ?? math.max(dataMax * 1.1, 1);
    final ymin = yMin;
    final len = series.fold<int>(
        0, (p, s) => math.max(p, s.data.length));
    final innerW = size.width - padL - padR;
    final innerH = size.height - padT - padB;
    double xFor(int i) => padL + (i / math.max(len - 1, 1)) * innerW;
    double yFor(double v) =>
        padT + (1 - (v - ymin) / ((ymax - ymin) == 0 ? 1 : (ymax - ymin))) * innerH;

    // grid + y labels
    if (grid) {
      for (var i = 0; i <= 3; i++) {
        final tv = ymin + (ymax - ymin) * i / 3;
        final y = yFor(tv);
        final p = Paint()
          ..color = gridColor
          ..strokeWidth = 1;
        if (i == 0 || i == 3) {
          canvas.drawLine(Offset(padL, y), Offset(size.width - padR, y), p);
        } else {
          _dashedLine(canvas, Offset(padL, y), Offset(size.width - padR, y), p);
        }
        _text(canvas, '${tv.round()}$unit', Offset(padL - 4, y), axisText,
            align: TextAlign.end);
      }
    }

    // thresholds
    for (final th in thresholds) {
      final y = yFor(th.value);
      _dashedLine(canvas, Offset(padL, y), Offset(size.width - padR, y),
          Paint()..color = th.color.withValues(alpha: 0.7)..strokeWidth = 1);
      if (th.label != null) {
        _text(canvas, th.label!, Offset(size.width - padR - 2, y - 6), th.color,
            align: TextAlign.end);
      }
    }

    // max-envelope bands (drawn under the main lines)
    for (final s in series) {
      final band = s.band;
      if (band == null || band.isEmpty || s.data.isEmpty) continue;
      final n = math.min(band.length, s.data.length);
      if (n < 2) continue;
      final top = Path();
      for (var i = 0; i < n; i++) {
        final x = xFor(i);
        final y = yFor(math.max(band[i], s.data[i]));
        i == 0 ? top.moveTo(x, y) : top.lineTo(x, y);
      }
      final area = Path.from(top);
      for (var i = n - 1; i >= 0; i--) {
        area.lineTo(xFor(i), yFor(s.data[i]));
      }
      area.close();
      canvas.drawPath(
          area, Paint()..color = s.color.withValues(alpha: 0.10));
    }

    // series
    for (final s in series) {
      if (s.data.isEmpty) continue;
      final path = Path();
      for (var i = 0; i < s.data.length; i++) {
        final x = xFor(i);
        final y = yFor(s.data[i]);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      if (s.fill) {
        final area = Path.from(path)
          ..lineTo(xFor(s.data.length - 1), yFor(ymin))
          ..lineTo(xFor(0), yFor(ymin))
          ..close();
        canvas.drawPath(area, Paint()..color = s.color.withValues(alpha: 0.15));
      }
      final paint = Paint()
        ..color = s.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      if (s.dashed) {
        _drawDashedPath(canvas, path, paint);
      } else {
        canvas.drawPath(path, paint);
      }
    }

    // x labels
    final labels = xLabels.length >= 3 ? xLabels : const ['', '', 'now'];
    for (var i = 0; i < 3; i++) {
      final x = padL + (i / 2) * innerW;
      _text(canvas, labels[i], Offset(x, size.height - 8), axisText,
          align: i == 0 ? TextAlign.start : i == 2 ? TextAlign.end : TextAlign.center);
    }
  }

  void _dashedLine(Canvas c, Offset a, Offset b, Paint p) {
    const dash = 2.0, gap = 3.0;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final s = a + dir * d;
      final e = a + dir * math.min(d + dash, total);
      c.drawLine(s, e, p);
      d += dash + gap;
    }
  }

  void _drawDashedPath(Canvas c, Path path, Paint p) {
    const dash = 4.0, gap = 3.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final next = math.min(d + dash, metric.length);
        c.drawPath(metric.extractPath(d, next), p);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => true;
}

/// Circular gauge (CPU/MEM donuts).
class NanoDonut extends StatelessWidget {
  final double value;
  final double max;
  final double size;
  final double thickness;
  final String label;
  final String? sub;
  final Color? tone;
  const NanoDonut({
    super.key,
    required this.value,
    this.max = 100,
    this.size = 64,
    this.thickness = 5,
    required this.label,
    this.sub,
    this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    final pct = (value / max).clamp(0.0, 1.0);
    final color = tone ?? (pct > 0.9 ? t.crit : pct > 0.75 ? t.warn : t.fg);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _DonutPainter(pct, color, t.card3, thickness),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: size > 70 ? 16 : 13,
                  color: t.fg,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (sub != null)
                Text(
                  sub!,
                  style: TextStyle(
                    fontSize: 9,
                    color: t.fg4,
                    fontFamilyFallback: kMonoFallback,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final double pct;
  final Color color;
  final Color track;
  final double thickness;
  _DonutPainter(this.pct, this.color, this.track, this.thickness);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - thickness;
    final center = Offset(size.width / 2, size.height / 2);
    final trackP = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness;
    canvas.drawCircle(center, r, trackP);
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 2,
      2 * math.pi * pct,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.pct != pct || old.color != color;
}

/// Per-core utilization matrix (vertical bars in a grid).
class NanoCoreMatrix extends StatelessWidget {
  final List<double> cores;
  final int cols;
  const NanoCoreMatrix({super.key, required this.cores, this.cols = 8});

  @override
  Widget build(BuildContext context) {
    final t = context.nano;
    return GridView.count(
      crossAxisCount: cols,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 3,
      crossAxisSpacing: 3,
      childAspectRatio: 1.6,
      children: cores.map((v) {
        final tone = v > 90
            ? t.crit
            : v > 70
                ? t.warn
                : v > 30
                    ? t.fg2
                    : t.fg4;
        return ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Stack(
            children: [
              Container(color: t.card3),
              Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: (v / 100).clamp(0.0, 1.0),
                  widthFactor: 1,
                  child: Container(color: tone.withValues(alpha: 0.85)),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
