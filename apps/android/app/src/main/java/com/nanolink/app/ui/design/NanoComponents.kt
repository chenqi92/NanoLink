package com.nanolink.app.ui.design

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nanolink.app.ui.tr

/// Small status dot with an optional pulse glow. Ports `NanoStatusDot`.
@Composable
fun NanoStatusDot(
    color: Color,
    size: Dp = 7.dp,
    pulse: Boolean = false,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier.size(size * 2.6f), contentAlignment = Alignment.Center) {
        if (pulse) {
            val transition = rememberInfiniteTransition(label = "statusPulse")
            val progress = transition.animateFloat(
                initialValue = 0f,
                targetValue = 1f,
                animationSpec = infiniteRepeatable(tween(1_000), RepeatMode.Restart),
                label = "statusPulseProgress",
            ).value
            Box(
                modifier = Modifier
                    .size(size)
                    .scale(1f + progress * 1.4f)
                    .alpha((1f - progress) * 0.45f)
                    .background(color, CircleShape),
            )
        }
        Box(modifier = Modifier.size(size).background(color, CircleShape))
    }
}

/// Status pill = dot + localized label (online / offline / connecting).
@Composable
fun NanoStatusLabel(status: String, modifier: Modifier = Modifier) {
    val t = nano
    val color = when (status) {
        "online" -> t.ok
        "connecting" -> t.warn
        else -> t.crit
    }
    val label = when (status) {
        "online" -> tr("status.online")
        "connecting" -> tr("status.connecting")
        else -> tr("status.offline")
    }
    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
        NanoStatusDot(color = color, pulse = status == "online")
        Text(label, fontSize = 12.sp, color = t.fg3)
    }
}

/// Generic colored badge chip. Ports `NanoBadge`.
@Composable
fun NanoBadge(
    text: String,
    color: Color? = null,
    icon: ImageVector? = null,
    mono: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val t = nano
    val fg = color ?: t.fg3
    val bg = if (color == null) t.card2 else color.copy(alpha = 0.14f)
    Row(
        modifier = modifier
            .height(19.dp)
            .background(bg, RoundedCornerShape(5.dp))
            .padding(horizontal = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = fg, modifier = Modifier.size(11.dp))
        }
        Text(
            text = text,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
            color = fg,
            fontFamily = if (mono) NanoMonoFamily else null,
        )
    }
}

/// Permission-level pill (L0..L3) with localized name.
@Composable
fun NanoPermPill(level: Int, modifier: Modifier = Modifier) {
    val t = nano
    val clamped = level.coerceIn(0, 3)
    val color = t.permColor(clamped)
    val label = tr("perm.l$clamped")
    Box(
        modifier = modifier
            .height(18.dp)
            .background(color.copy(alpha = 0.16f), RoundedCornerShape(4.dp))
            .padding(horizontal = 6.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = "L$clamped · $label",
            fontSize = 10.5.sp,
            fontWeight = FontWeight.SemiBold,
            fontFamily = NanoMonoFamily,
            color = color,
        )
    }
}

/// Thin linear usage meter (0..1). Ports `NanoMeter`.
@Composable
fun NanoMeter(
    value: Double,
    color: Color? = null,
    height: Dp = 4.dp,
    modifier: Modifier = Modifier,
) {
    val t = nano
    val fill = color ?: t.meterColor(value * 100)
    val fraction = value.coerceIn(0.0, 1.0).toFloat()
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(height)
            .clip(CircleShape)
            .background(t.card3),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth(fraction)
                .fillMaxSize()
                .background(fill, CircleShape),
        )
    }
}

/// Section header label used between grouped cards. Ports `NanoSectionLabel`.
@Composable
fun NanoSectionLabel(
    label: String,
    grouped: Boolean = false,
    modifier: Modifier = Modifier,
    trailing: (@Composable () -> Unit)? = null,
) {
    val t = nano
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(
                start = 4.dp,
                end = 4.dp,
                top = if (grouped) 12.dp else 10.dp,
                bottom = if (grouped) 7.dp else 6.dp,
            ),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = if (grouped) label.uppercase() else label,
            fontSize = if (grouped) 11.5.sp else 13.sp,
            fontWeight = if (grouped) FontWeight.Normal else FontWeight.SemiBold,
            letterSpacing = if (grouped) 0.4.sp else 0.sp,
            color = if (grouped) t.fg3 else t.fg2,
        )
        Spacer(Modifier.weight(1f))
        trailing?.invoke()
    }
}

enum class NanoButtonVariant { PRIMARY, SECONDARY, DANGER, OUTLINED, TEXT }

/// Shared button primitive; heights, radii and typography follow the active
/// platform look. Ports `NanoButton`.
@Composable
fun NanoButton(
    label: String,
    onClick: () -> Unit,
    icon: ImageVector? = null,
    variant: NanoButtonVariant = NanoButtonVariant.PRIMARY,
    fullWidth: Boolean = false,
    loading: Boolean = false,
    enabled: Boolean = true,
    modifier: Modifier = Modifier,
) {
    val t = nano
    val isIOS = t.isIOS
    val height = when {
        variant == NanoButtonVariant.TEXT -> if (isIOS) 44.dp else 40.dp
        isIOS -> 50.dp
        else -> 40.dp
    }
    val fg = when (variant) {
        NanoButtonVariant.PRIMARY -> t.onAccent
        NanoButtonVariant.DANGER -> t.crit
        NanoButtonVariant.OUTLINED -> t.fg
        else -> t.accent
    }
    val bg = when (variant) {
        NanoButtonVariant.PRIMARY -> t.accent
        NanoButtonVariant.SECONDARY -> t.card2
        NanoButtonVariant.DANGER -> t.crit.copy(alpha = 0.14f)
        else -> Color.Transparent
    }
    val shape = RoundedCornerShape(t.buttonRadius)
    val interactive = enabled && !loading

    Box(
        modifier = modifier
            .then(if (fullWidth) Modifier.fillMaxWidth() else Modifier)
            .height(height)
            .clip(shape)
            .background(bg)
            .then(
                if (variant == NanoButtonVariant.OUTLINED) {
                    Modifier.border(1.dp, if (isIOS) t.sep else t.fg4, shape)
                } else {
                    Modifier
                },
            )
            .clickable(enabled = interactive, onClick = onClick)
            .alpha(if (enabled) 1f else 0.5f)
            .padding(horizontal = if (fullWidth) 0.dp else 18.dp),
        contentAlignment = Alignment.Center,
    ) {
        when {
            loading -> CircularProgressIndicator(
                color = fg,
                strokeWidth = 2.dp,
                modifier = Modifier.size(20.dp),
            )
            icon != null -> Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(icon, contentDescription = null, tint = fg, modifier = Modifier.size(if (isIOS) 20.dp else 18.dp))
                NanoButtonText(label, fg, isIOS)
            }
            else -> NanoButtonText(label, fg, isIOS)
        }
    }
}

@Composable
private fun NanoButtonText(label: String, color: Color, isIOS: Boolean) {
    Text(
        text = label,
        fontSize = if (isIOS) 17.sp else 14.sp,
        fontWeight = if (isIOS) FontWeight.SemiBold else FontWeight.Medium,
        color = color,
        textAlign = TextAlign.Center,
    )
}

/// Monospace text helper. Ports `NanoMono`.
@Composable
fun NanoMono(
    text: String,
    size: Int = 12,
    color: Color? = null,
    weight: FontWeight = FontWeight.Normal,
    modifier: Modifier = Modifier,
) {
    val t = nano
    Text(
        text = text,
        fontSize = size.sp,
        lineHeight = (size * 1.3f).sp,
        fontFamily = NanoMonoFamily,
        fontWeight = weight,
        color = color ?: t.fg2,
        modifier = modifier,
    )
}

/// Rounded square icon container used as a list-row leading element.
/// Ports `NanoIconBox`.
@Composable
fun NanoIconBox(
    icon: ImageVector,
    size: Dp = 36.dp,
    iconSize: Dp = 18.dp,
    background: Color? = null,
    tint: Color? = null,
    gradient: Brush? = null,
    modifier: Modifier = Modifier,
) {
    val t = nano
    Box(
        modifier = modifier
            .size(size)
            .clip(RoundedCornerShape(size * 0.25f))
            .then(
                if (gradient != null) {
                    Modifier.background(gradient)
                } else {
                    Modifier.background(background ?: t.card2)
                },
            ),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = tint ?: t.fg3, modifier = Modifier.size(iconSize))
    }
}

/// Grouped card surface (iOS inset-grouped / Material filled card). Ports `NanoCard`.
@Composable
fun NanoCard(
    modifier: Modifier = Modifier,
    padding: PaddingValues? = null,
    color: Color? = null,
    outlined: Boolean = false,
    onClick: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val t = nano
    val shape = RoundedCornerShape(t.cardRadius)
    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(color ?: t.card)
            .then(if (outlined) Modifier.border(1.dp, t.sep, shape) else Modifier)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .then(if (padding != null) Modifier.padding(padding) else Modifier),
    ) {
        content()
    }
}

/// A single row inside a `NanoCard`, with an optional hairline divider.
/// Ports `NanoListRow`.
@Composable
fun NanoListRow(
    modifier: Modifier = Modifier,
    divider: Boolean = true,
    onClick: (() -> Unit)? = null,
    padding: PaddingValues? = null,
    verticalAlignment: Alignment.Vertical = Alignment.CenterVertically,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val t = nano
    val resolvedPadding = padding ?: PaddingValues(horizontal = 16.dp, vertical = t.rowPadding)
    Box(
        modifier = modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(resolvedPadding),
            verticalAlignment = verticalAlignment,
        ) {
            if (leading != null) {
                leading()
                Spacer(Modifier.width(12.dp))
            }
            Box(Modifier.weight(1f)) { content() }
            if (trailing != null) {
                Spacer(Modifier.width(10.dp))
                trailing()
            }
        }
        if (divider) {
            Box(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .fillMaxWidth()
                    .height(0.5.dp)
                    .background(t.sep2),
            )
        }
    }
}

/// Empty-state placeholder used by list screens.
@Composable
fun NanoEmptyState(
    icon: ImageVector,
    title: String,
    detail: String? = null,
    modifier: Modifier = Modifier,
) {
    val t = nano
    Box(
        modifier = modifier.fillMaxWidth().padding(vertical = 48.dp),
        contentAlignment = Alignment.Center,
    ) {
        androidx.compose.foundation.layout.Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Icon(icon, contentDescription = null, tint = t.fg4, modifier = Modifier.size(38.dp))
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = t.fg2)
            if (detail != null) {
                Text(
                    detail,
                    fontSize = 13.sp,
                    color = t.fg3,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.defaultMinSize(minWidth = 0.dp).padding(horizontal = 32.dp),
                )
            }
        }
    }
}
