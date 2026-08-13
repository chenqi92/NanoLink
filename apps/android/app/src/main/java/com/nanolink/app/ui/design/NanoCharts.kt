package com.nanolink.app.ui.design

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/// Tiny sparkline used inside KPI tiles. Ports `NanoSparkline`.
@Composable
fun NanoSparkline(
    data: List<Double>,
    color: Color,
    width: Dp = 56.dp,
    height: Dp = 18.dp,
    fill: Boolean = false,
    modifier: Modifier = Modifier,
) {
    if (data.isEmpty()) {
        Spacer(modifier.size(width, height))
        return
    }
    Canvas(modifier = modifier.size(width, height)) {
        val low = data.min()
        val high = data.max()
        val range = if (high - low == 0.0) 1.0 else high - low
        val step = size.width / max(data.size - 1, 1)
        val path = Path()
        data.forEachIndexed { index, value ->
            val x = index * step
            val y = size.height - ((value - low) / range).toFloat() * (size.height - 2f) - 1f
            if (index == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        if (fill) {
            val area = Path().apply {
                addPath(path)
                lineTo(size.width, size.height)
                lineTo(0f, size.height)
                close()
            }
            drawPath(area, color.copy(alpha = 0.12f))
        }
        drawPath(
            path = path,
            color = color,
            style = Stroke(width = 1.5f * density, cap = StrokeCap.Round, join = StrokeJoin.Round),
        )
    }
}

/// One data series for `NanoLineChart`.
data class NanoSeries(
    val data: List<Double>,
    val color: Color,
    val fill: Boolean = false,
    val dashed: Boolean = false,
    val label: String? = null,
    /// Optional per-sample peak values; shaded as a faint envelope band.
    val band: List<Double>? = null,
)

data class NanoThreshold(
    val value: Double,
    val color: Color,
    val label: String? = null,
)

/// Touch-tuned line chart used by the history graphs. Ports `NanoLineChart`.
@Composable
fun NanoLineChart(
    series: List<NanoSeries>,
    modifier: Modifier = Modifier,
    height: Dp = 140.dp,
    yMax: Double? = null,
    yMin: Double = 0.0,
    unit: String = "%",
    thresholds: List<NanoThreshold> = emptyList(),
    grid: Boolean = true,
    xLabels: List<String> = listOf("-60m", "-30m", "now"),
    timesMillis: List<Long> = emptyList(),
) {
    val t = nano
    val measurer = rememberTextMeasurer()
    val labels = if (timesMillis.size >= 2) labelsFromTimes(timesMillis) else xLabels
    val gridColor = t.sep2
    val axisColor = t.fg4

    Canvas(modifier = modifier.fillMaxWidth().height(height)) {
        val padL = 30f * density
        val padR = 6f * density
        val padT = 6f * density
        val padB = 18f * density
        val dataMax = series.flatMap { it.data }.maxOrNull() ?: 1.0
        val top = yMax ?: max(dataMax * 1.1, 1.0)
        val length = series.maxOfOrNull { it.data.size } ?: 0
        val innerW = size.width - padL - padR
        val innerH = size.height - padT - padB

        fun xFor(index: Int): Float = padL + index.toFloat() / max(length - 1, 1) * innerW
        fun yFor(value: Double): Float {
            val denominator = if (top - yMin == 0.0) 1.0 else top - yMin
            return padT + (1f - ((value - yMin) / denominator).toFloat()) * innerH
        }

        val dash = PathEffect.dashPathEffect(floatArrayOf(2f * density, 3f * density))

        if (grid) {
            for (i in 0..3) {
                val tick = yMin + (top - yMin) * i / 3
                val y = yFor(tick)
                drawLine(
                    color = gridColor,
                    start = Offset(padL, y),
                    end = Offset(size.width - padR, y),
                    strokeWidth = density,
                    pathEffect = if (i == 0 || i == 3) null else dash,
                )
                drawAxisText(
                    measurer = measurer,
                    text = "${tick.roundToInt()}$unit",
                    anchor = Offset(padL - 4f * density, y),
                    color = axisColor,
                    align = TextAlign.End,
                    density = density,
                )
            }
        }

        thresholds.forEach { threshold ->
            val y = yFor(threshold.value)
            drawLine(
                color = threshold.color.copy(alpha = 0.7f),
                start = Offset(padL, y),
                end = Offset(size.width - padR, y),
                strokeWidth = density,
                pathEffect = dash,
            )
            threshold.label?.let { label ->
                drawAxisText(
                    measurer = measurer,
                    text = label,
                    anchor = Offset(size.width - padR - 2f * density, y - 6f * density),
                    color = threshold.color,
                    align = TextAlign.End,
                    density = density,
                )
            }
        }

        // max-envelope bands
        series.forEach { entry ->
            val band = entry.band ?: return@forEach
            if (band.isEmpty() || entry.data.isEmpty()) return@forEach
            val count = min(band.size, entry.data.size)
            if (count < 2) return@forEach
            val area = Path()
            for (i in 0 until count) {
                val x = xFor(i)
                val y = yFor(max(band[i], entry.data[i]))
                if (i == 0) area.moveTo(x, y) else area.lineTo(x, y)
            }
            for (i in count - 1 downTo 0) {
                area.lineTo(xFor(i), yFor(entry.data[i]))
            }
            area.close()
            drawPath(area, entry.color.copy(alpha = 0.10f))
        }

        series.forEach { entry ->
            if (entry.data.isEmpty()) return@forEach
            val path = Path()
            entry.data.forEachIndexed { index, value ->
                val x = xFor(index)
                val y = yFor(value)
                if (index == 0) path.moveTo(x, y) else path.lineTo(x, y)
            }
            if (entry.fill) {
                val area = Path().apply {
                    addPath(path)
                    lineTo(xFor(entry.data.size - 1), yFor(yMin))
                    lineTo(xFor(0), yFor(yMin))
                    close()
                }
                drawPath(area, entry.color.copy(alpha = 0.15f))
            }
            drawPath(
                path = path,
                color = entry.color,
                style = Stroke(
                    width = 1.5f * density,
                    cap = StrokeCap.Round,
                    join = StrokeJoin.Round,
                    pathEffect = if (entry.dashed) {
                        PathEffect.dashPathEffect(floatArrayOf(4f * density, 3f * density))
                    } else {
                        null
                    },
                ),
            )
        }

        val ticks = if (labels.size >= 3) labels else listOf("", "", "now")
        for (i in 0..2) {
            val x = padL + i / 2f * innerW
            val align = when (i) {
                0 -> TextAlign.Start
                2 -> TextAlign.End
                else -> TextAlign.Center
            }
            drawAxisText(
                measurer = measurer,
                text = ticks[i],
                anchor = Offset(x, size.height - 8f * density),
                color = axisColor,
                align = align,
                density = density,
            )
        }
    }
}

private enum class TextAlign { Start, Center, End }

private fun DrawScope.drawAxisText(
    measurer: TextMeasurer,
    text: String,
    anchor: Offset,
    color: Color,
    align: TextAlign,
    density: Float,
) {
    if (text.isEmpty()) return
    val layout = measurer.measure(
        text = text,
        style = TextStyle(fontSize = 9.sp, fontFamily = NanoMonoFamily, color = color),
    )
    val width = layout.size.width.toFloat()
    val heightPx = layout.size.height.toFloat()
    val x = when (align) {
        TextAlign.Start -> anchor.x
        TextAlign.Center -> anchor.x - width / 2
        TextAlign.End -> anchor.x - width
    }
    drawText(layout, topLeft = Offset(x, anchor.y - heightPx / 2))
}

/// Derive three tick labels (start / middle / now) from real timestamps.
fun labelsFromTimes(timesMillis: List<Long>): List<String> {
    if (timesMillis.size < 2) return listOf("", "", "now")
    val last = timesMillis.last()
    fun relative(value: Long): String {
        val seconds = (last - value) / 1_000
        return when {
            seconds <= 30 -> "now"
            seconds < 3_600 -> "-${(seconds / 60.0).roundToInt()}m"
            seconds < 86_400 -> "-${(seconds / 3_600.0).roundToInt()}h"
            else -> "-${(seconds / 86_400.0).roundToInt()}d"
        }
    }
    return listOf(
        relative(timesMillis.first()),
        relative(timesMillis[timesMillis.size / 2]),
        relative(last),
    )
}

/// Circular gauge (CPU/MEM donuts). Ports `NanoDonut`.
@Composable
fun NanoDonut(
    value: Double,
    label: String,
    maxValue: Double = 100.0,
    size: Dp = 64.dp,
    thickness: Dp = 5.dp,
    sub: String? = null,
    tone: Color? = null,
    modifier: Modifier = Modifier,
) {
    val t = nano
    val fraction = (value / maxValue).coerceIn(0.0, 1.0)
    val color = tone ?: when {
        fraction > 0.9 -> t.crit
        fraction > 0.75 -> t.warn
        else -> t.fg
    }
    val trackColor = t.card3
    Box(modifier = modifier.size(size), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(size)) {
            val strokePx = thickness.toPx()
            val inset = strokePx * 1.5f
            val arcSize = Size(this.size.width - inset * 2, this.size.height - inset * 2)
            drawArc(
                color = trackColor,
                startAngle = 0f,
                sweepAngle = 360f,
                useCenter = false,
                topLeft = Offset(inset, inset),
                size = arcSize,
                style = Stroke(width = strokePx),
            )
            drawArc(
                color = color,
                startAngle = -90f,
                sweepAngle = (360 * fraction).toFloat(),
                useCenter = false,
                topLeft = Offset(inset, inset),
                size = arcSize,
                style = Stroke(width = strokePx, cap = StrokeCap.Round),
            )
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = label,
                fontSize = if (size > 70.dp) 16.sp else 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = t.fg,
            )
            if (sub != null) {
                Text(sub, fontSize = 9.sp, fontFamily = NanoMonoFamily, color = t.fg4)
            }
        }
    }
}

/// Per-core utilization matrix (vertical bars in a grid). Ports `NanoCoreMatrix`.
@Composable
fun NanoCoreMatrix(
    cores: List<Double>,
    columns: Int = 8,
    modifier: Modifier = Modifier,
) {
    val t = nano
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        cores.chunked(columns).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(3.dp), modifier = Modifier.fillMaxWidth()) {
                row.forEach { value ->
                    val tone = when {
                        value > 90 -> t.crit
                        value > 70 -> t.warn
                        value > 30 -> t.fg2
                        else -> t.fg4
                    }
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .aspectRatio(1.6f)
                            .clip(RoundedCornerShape(2.dp))
                            .background(t.card3),
                        contentAlignment = Alignment.BottomCenter,
                    ) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .fillMaxHeight((value / 100).coerceIn(0.0, 1.0).toFloat())
                                .background(tone.copy(alpha = 0.85f)),
                        )
                    }
                }
                // Keep the last partial row aligned with the full rows above it.
                repeat(columns - row.size) {
                    Spacer(Modifier.weight(1f))
                }
            }
        }
    }
}

/// KPI summary tile used on the dashboard. Ports `NanoKpiTile`.
@Composable
fun NanoKpiTile(
    label: String,
    value: String,
    sub: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    modifier: Modifier = Modifier,
    tone: String? = null,
    spark: List<Double>? = null,
    background: Color? = null,
) {
    val t = nano
    val toneColor = when (tone) {
        "crit" -> t.crit
        "warn" -> t.warn
        else -> t.accent
    }
    val valueColor = when (tone) {
        "crit" -> t.crit
        "warn" -> t.warn
        else -> t.fg
    }
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(t.cardRadius))
            .background(background ?: t.card)
            .padding(horizontal = 14.dp, vertical = 12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            androidx.compose.material3.Icon(
                icon,
                contentDescription = null,
                tint = t.fg3,
                modifier = Modifier.size(14.dp),
            )
            Text(label, fontSize = 12.sp, fontWeight = FontWeight.Medium, color = t.fg3)
        }
        Spacer(Modifier.height(4.dp))
        Text(
            text = value,
            fontSize = 26.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = (-0.3).sp,
            color = valueColor,
        )
        Spacer(Modifier.height(2.dp))
        Row(verticalAlignment = Alignment.Bottom) {
            Text(
                text = sub,
                fontSize = 10.5.sp,
                fontFamily = NanoMonoFamily,
                color = t.fg4,
                maxLines = 1,
                modifier = Modifier.weight(1f, fill = false),
            )
            Spacer(Modifier.weight(1f))
            if (spark != null) {
                NanoSparkline(data = spark, color = toneColor)
            }
        }
    }
}

/// Row: leading icon + short label + meter + right-aligned value/sub.
/// Ports `NanoMetricRow`.
@Composable
fun NanoMetricRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    sub: String? = null,
    percent: Double? = null,
    tone: String? = null,
) {
    val t = nano
    val toneColor = when (tone) {
        "crit" -> t.crit
        "warn" -> t.warn
        else -> t.fg
    }
    Row(modifier = modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        androidx.compose.material3.Icon(
            icon,
            contentDescription = null,
            tint = t.fg4,
            modifier = Modifier.size(13.dp),
        )
        Spacer(Modifier.width(10.dp))
        Text(
            text = label,
            fontSize = 11.sp,
            fontFamily = NanoMonoFamily,
            color = t.fg3,
            modifier = Modifier.width(30.dp),
        )
        Spacer(Modifier.width(10.dp))
        Box(Modifier.weight(1f)) {
            if (percent != null) {
                NanoMeter(value = percent / 100, color = if (tone == null) null else toneColor)
            }
        }
        Spacer(Modifier.width(10.dp))
        Column(horizontalAlignment = Alignment.End, modifier = Modifier.width(64.dp)) {
            Text(value, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = toneColor)
            if (sub != null) {
                Text(sub, fontSize = 10.sp, fontFamily = NanoMonoFamily, color = t.fg4)
            }
        }
    }
}
