package com.nanolink.app.ui.design

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import com.nanolink.app.state.AppThemeMode
import com.nanolink.app.state.ThemeState
import com.nanolink.app.ui.theme.NanoTypography

/// Resolves `NanoTokens` from the persisted theme state plus the system color
/// scheme, then injects them for the whole subtree. Also maps the tokens onto a
/// Material color scheme so stock M3 widgets (dialogs, switches, sliders) match.
@Composable
fun NanoThemeProvider(
    state: ThemeState,
    content: @Composable () -> Unit,
) {
    val systemDark = isSystemInDarkTheme()
    val isDark = when (state.mode) {
        AppThemeMode.LIGHT -> false
        AppThemeMode.DARK -> true
        AppThemeMode.SYSTEM -> systemDark
    }
    val tokens = NanoTokens.resolve(state.style, isDark, state.compact)

    val colors = if (isDark) {
        darkColorScheme(
            primary = tokens.accent,
            onPrimary = tokens.onAccent,
            secondary = tokens.secondary,
            tertiary = tokens.tertiary,
            background = tokens.bg,
            onBackground = tokens.fg,
            surface = tokens.card,
            onSurface = tokens.fg,
            surfaceVariant = tokens.card2,
            onSurfaceVariant = tokens.fg2,
            outline = tokens.sep,
            outlineVariant = tokens.sep2,
            error = tokens.crit,
        )
    } else {
        lightColorScheme(
            primary = tokens.accent,
            onPrimary = tokens.onAccent,
            secondary = tokens.secondary,
            tertiary = tokens.tertiary,
            background = tokens.bg,
            onBackground = tokens.fg,
            surface = tokens.card,
            onSurface = tokens.fg,
            surfaceVariant = tokens.card2,
            onSurfaceVariant = tokens.fg2,
            outline = tokens.sep,
            outlineVariant = tokens.sep2,
            error = tokens.crit,
        )
    }

    CompositionLocalProvider(LocalNano provides tokens) {
        MaterialTheme(
            colorScheme = colors,
            typography = NanoTypography,
            content = content,
        )
    }
}
