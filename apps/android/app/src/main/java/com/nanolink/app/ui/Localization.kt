package com.nanolink.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.staticCompositionLocalOf
import com.nanolink.app.localization.L10n

val LocalL10n: ProvidableCompositionLocal<L10n> = staticCompositionLocalOf {
    error("L10n was not provided")
}

/// The active language code, provided alongside `LocalL10n`. Reading it inside
/// `tr(...)` is what makes every localized string recompose on a language switch —
/// `L10n.text` itself is a plain lookup with no snapshot state behind it.
val LocalLanguage: ProvidableCompositionLocal<String> = compositionLocalOf { "en" }

/// Localize a dot-path key, mirroring the Swift global `tr(...)`.
@Composable
fun tr(key: String): String {
    LocalLanguage.current
    return LocalL10n.current.text(key)
}

@Composable
fun tr(key: String, vararg named: Pair<String, Any?>): String {
    LocalLanguage.current
    return LocalL10n.current.text(key, named.toMap())
}

@Composable
fun trArgs(key: String, vararg args: Any?): String {
    LocalLanguage.current
    return LocalL10n.current.text(key, emptyMap(), args.toList())
}
