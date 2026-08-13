package com.nanolink.app.util

import java.util.concurrent.TimeUnit
import kotlin.math.roundToInt

/// Byte-size and rate formatting, ported from `format.dart` / `Format.swift`
/// (binary units: KiB/MiB/GiB/TiB).
object Fmt {
    private const val KIB = 1024.0
    private const val MIB = KIB * 1024
    private const val GIB = MIB * 1024
    private const val TIB = GIB * 1024

    private fun fixed(value: Double, digits: Int): String = String.format("%.${digits}f", value)

    fun gib(bytes: Double): Double = bytes / GIB

    fun bytes(value: Double): String = when {
        value >= TIB -> "${fixed(value / TIB, if (value / TIB >= 10) 0 else 1)} TiB"
        value >= GIB -> "${fixed(value / GIB, if (value / GIB >= 10) 0 else 1)} GiB"
        value >= MIB -> "${fixed(value / MIB, 0)} MiB"
        value >= KIB -> "${fixed(value / KIB, 0)} KiB"
        else -> "${fixed(value, 0)} B"
    }

    fun rate(bytesPerSec: Double): String = when {
        bytesPerSec >= GIB -> "${fixed(bytesPerSec / GIB, 1)} GB/s"
        bytesPerSec >= MIB -> "${fixed(bytesPerSec / MIB, 1)} MB/s"
        bytesPerSec >= KIB -> "${fixed(bytesPerSec / KIB, 0)} KB/s"
        else -> "${fixed(bytesPerSec, 0)} B/s"
    }

    fun mbps(bytesPerSec: Double): Double = bytesPerSec / MIB

    fun uptime(seconds: Long): String {
        if (seconds <= 0) return "—"
        val days = seconds / 86_400
        val hours = (seconds % 86_400) / 3_600
        val minutes = (seconds % 3_600) / 60
        return when {
            days > 0 -> "${days}d ${hours}h"
            hours > 0 -> "${hours}h ${minutes}m"
            else -> "${minutes}m"
        }
    }

    /// Relative time from an epoch-millis timestamp, e.g. "5s", "3m", "2h", "4d".
    fun ago(millis: Long?): String {
        if (millis == null || millis <= 0) return "—"
        val seconds = TimeUnit.MILLISECONDS.toSeconds((System.currentTimeMillis() - millis).coerceAtLeast(0))
        return when {
            seconds < 60 -> "${seconds}s"
            seconds < 3_600 -> "${seconds / 60}m"
            seconds < 86_400 -> "${seconds / 3_600}h"
            else -> "${seconds / 86_400}d"
        }
    }

    fun percent(value: Double): String = "${value.roundToInt()}%"

    fun clockTime(millis: Long): String {
        val date = java.util.Date(millis)
        return java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault()).format(date)
    }

    fun dateTime(millis: Long): String {
        val date = java.util.Date(millis)
        return java.text.SimpleDateFormat("MM-dd HH:mm:ss", java.util.Locale.getDefault()).format(date)
    }
}
