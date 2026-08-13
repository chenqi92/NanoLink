package com.nanolink.app.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

private val DarkColors = darkColorScheme(
    primary = NanoIndigo,
    onPrimary = Color(0xFF111A48),
    secondary = NanoBlue,
    background = NanoDarkBackground,
    onBackground = NanoDarkText,
    surface = NanoDarkSurface,
    onSurface = NanoDarkText,
    surfaceVariant = NanoDarkSurfaceAlt,
    error = NanoRed,
)

private val LightColors = lightColorScheme(
    primary = NanoIndigoLight,
    onPrimary = Color.White,
    secondary = Color(0xFF1769A8),
    background = NanoLightBackground,
    onBackground = NanoLightText,
    surface = NanoLightSurface,
    onSurface = NanoLightText,
    surfaceVariant = Color(0xFFE9EDF5),
    error = Color(0xFFBA1A1A),
)

@Composable
fun NanoLinkTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colors = if (darkTheme) DarkColors else LightColors
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.statusBarColor = Color.Transparent.toArgb()
            window.navigationBarColor = Color.Transparent.toArgb()
            WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = !darkTheme
                isAppearanceLightNavigationBars = !darkTheme
            }
        }
    }

    MaterialTheme(
        colorScheme = colors,
        typography = NanoTypography,
        content = content,
    )
}
