package com.nanolink.app.ui.design

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp
import com.nanolink.app.state.ThemeStyle

/// Design tokens for a `style` + `isDark` pair, ported 1:1 from the Swift
/// `NanoTokens` (which mirrors `mobile-tokens.css`). Composables pull every color
/// and radius from here rather than hard-coding, so one place controls the iOS vs
/// Material palettes in light and dark.
data class NanoTokens(
    val style: ThemeStyle,
    val isDark: Boolean,
    // Surfaces / backgrounds
    val bg: Color,
    val bg2: Color,
    val card: Color,
    val card2: Color,
    val card3: Color,
    val sep: Color,
    val sep2: Color,
    // Foreground text tiers
    val fg: Color,
    val fg2: Color,
    val fg3: Color,
    val fg4: Color,
    val fg5: Color,
    // Accents
    val accent: Color,
    val onAccent: Color,
    val secondary: Color,
    val tertiary: Color,
    // Chrome
    val tabBg: Color,
    val glassBorder: Color,
    // Status
    val ok: Color,
    val warn: Color,
    val crit: Color,
    val info: Color,
    /// Compact mode shrinks row/tile density app-wide.
    val compact: Boolean = false,
) {
    val isIOS: Boolean get() = style == ThemeStyle.IOS

    val cardRadius: Dp get() = if (isIOS) 14.dp else 16.dp
    val fieldRadius: Dp get() = if (isIOS) 12.dp else 8.dp
    val buttonRadius: Dp get() = if (isIOS) 14.dp else 100.dp

    val displayWeight: FontWeight get() = if (isIOS) FontWeight.Bold else FontWeight.Medium
    val displayTracking: TextUnit get() = if (isIOS) (-0.8).sp else (-0.3).sp

    /// Row vertical padding, tightened in compact mode.
    val rowPadding: Dp get() = if (compact) 8.dp else 11.dp
    val sectionGap: Dp get() = if (compact) 10.dp else 16.dp

    /// Color for a 0-100 usage value: fg < 75 < warn < 90 < crit.
    fun usageColor(percent: Double): Color = when {
        percent > 90 -> crit
        percent > 75 -> warn
        else -> fg
    }

    /// Tone color for meters and sparklines.
    fun meterColor(percent: Double): Color = when {
        percent > 90 -> crit
        percent > 75 -> warn
        else -> fg2
    }

    /// Permission-level pill color (L0..L3).
    fun permColor(level: Int): Color = when (level) {
        1 -> StatusInfo
        2 -> warn
        3 -> crit
        else -> Color(0xFFA3A3A3)
    }

    companion object {
        private val StatusOk = Color(0xFF30D158)
        private val StatusWarn = Color(0xFFFFB020)
        private val StatusCrit = Color(0xFFFF453A)
        private val StatusInfo = Color(0xFF0A84FF)

        val IosDark = NanoTokens(
            style = ThemeStyle.IOS,
            isDark = true,
            bg = Color(0xFF000000),
            bg2 = Color(0xFF0A0A0A),
            card = Color(0xFF1C1C1E),
            card2 = Color(0xFF2C2C2E),
            card3 = Color(0xFF3A3A3C),
            sep = Color(0x80545458),
            sep2 = Color(0x52545458),
            fg = Color(0xFFFFFFFF),
            fg2 = Color(0xD9EBEBF5),
            fg3 = Color(0x99EBEBF5),
            fg4 = Color(0x66EBEBF5),
            fg5 = Color(0x40EBEBF5),
            accent = Color(0xFF0A84FF),
            onAccent = Color(0xFFFFFFFF),
            secondary = Color(0xFF0A84FF),
            tertiary = Color(0xFF5E5CE6),
            tabBg = Color(0xC71C1C1E),
            glassBorder = Color(0x12FFFFFF),
            ok = StatusOk,
            warn = StatusWarn,
            crit = StatusCrit,
            info = StatusInfo,
        )

        val IosLight = NanoTokens(
            style = ThemeStyle.IOS,
            isDark = false,
            bg = Color(0xFFF2F2F7),
            bg2 = Color(0xFFE5E5EA),
            card = Color(0xFFFFFFFF),
            card2 = Color(0xFFF2F2F7),
            card3 = Color(0xFFE5E5EA),
            sep = Color(0x4A3C3C43),
            sep2 = Color(0x2E3C3C43),
            fg = Color(0xFF000000),
            fg2 = Color(0xDB3C3C43),
            fg3 = Color(0x993C3C43),
            fg4 = Color(0x663C3C43),
            fg5 = Color(0x403C3C43),
            accent = Color(0xFF007AFF),
            onAccent = Color(0xFFFFFFFF),
            secondary = Color(0xFF007AFF),
            tertiary = Color(0xFF5856D6),
            tabBg = Color(0xC7F8F8F8),
            glassBorder = Color(0x12000000),
            ok = StatusOk,
            warn = StatusWarn,
            crit = StatusCrit,
            info = StatusInfo,
        )

        val MdDark = NanoTokens(
            style = ThemeStyle.MD,
            isDark = true,
            bg = Color(0xFF131318),
            bg2 = Color(0xFF1B1B21),
            card = Color(0xFF1F1F25),
            card2 = Color(0xFF28282E),
            card3 = Color(0xFF36363D),
            sep = Color(0xFF2A2A30),
            sep2 = Color(0xFF36363D),
            fg = Color(0xFFE6E1E9),
            fg2 = Color(0xFFCAC4D0),
            fg3 = Color(0xFF938F99),
            fg4 = Color(0xFF79747E),
            fg5 = Color(0xFF49454F),
            accent = Color(0xFFB4C5FF),
            onAccent = Color(0xFF1B2C5D),
            secondary = Color(0xFFC6C2DC),
            tertiary = Color(0xFFEEB8E8),
            tabBg = Color(0xF21F1F25),
            glassBorder = Color(0x14FFFFFF),
            ok = StatusOk,
            warn = StatusWarn,
            crit = StatusCrit,
            info = StatusInfo,
        )

        val MdLight = NanoTokens(
            style = ThemeStyle.MD,
            isDark = false,
            bg = Color(0xFFFFFBFF),
            bg2 = Color(0xFFF4EFF4),
            card = Color(0xFFECE6EB),
            card2 = Color(0xFFE6E0E9),
            card3 = Color(0xFFE6E0E9),
            sep = Color(0xFFE6E0E9),
            sep2 = Color(0xFFECE6EB),
            fg = Color(0xFF1C1B1F),
            fg2 = Color(0xFF49454F),
            fg3 = Color(0xFF79747E),
            fg4 = Color(0xFF938F99),
            fg5 = Color(0xFFCAC4D0),
            accent = Color(0xFF4F5A86),
            onAccent = Color(0xFFFFFFFF),
            secondary = Color(0xFF5A5D72),
            tertiary = Color(0xFF7E5260),
            tabBg = Color(0xEBFFFBFF),
            glassBorder = Color(0x14000000),
            ok = StatusOk,
            warn = StatusWarn,
            crit = StatusCrit,
            info = StatusInfo,
        )

        fun resolve(style: ThemeStyle, isDark: Boolean, compact: Boolean = false): NanoTokens {
            val base = when (style) {
                ThemeStyle.IOS -> if (isDark) IosDark else IosLight
                ThemeStyle.MD -> if (isDark) MdDark else MdLight
            }
            return if (base.compact == compact) base else base.copy(compact = compact)
        }
    }
}

val LocalNano: ProvidableCompositionLocal<NanoTokens> = staticCompositionLocalOf { NanoTokens.IosDark }

/// Shorthand for the ambient tokens, the Compose analogue of `@Environment(\.nano)`.
val nano: NanoTokens
    @Composable get() = LocalNano.current

/// Monospace family used by terminal output, IDs and numeric readouts.
val NanoMonoFamily: FontFamily = FontFamily.Monospace
