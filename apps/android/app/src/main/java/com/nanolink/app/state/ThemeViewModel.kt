package com.nanolink.app.state

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.nanolink.app.data.storage.PreferenceKeys
import com.nanolink.app.data.storage.PreferencesStore
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class ThemeViewModel(private val preferences: PreferencesStore) : ViewModel() {
    val state: StateFlow<ThemeState> = combine(
        preferences.flow(PreferenceKeys.ThemeMode, AppThemeMode.DARK.ordinal),
        preferences.flow(PreferenceKeys.ThemeStyle, ThemeStyle.IOS.name.lowercase()),
        preferences.flow(PreferenceKeys.Compact, false),
    ) { mode, style, compact ->
        ThemeState(
            mode = AppThemeMode.entries.getOrElse(mode.coerceIn(0, AppThemeMode.entries.lastIndex)) { AppThemeMode.DARK },
            style = if (style == "md") ThemeStyle.MD else ThemeStyle.IOS,
            compact = compact,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), ThemeState())

    fun setMode(mode: AppThemeMode) = update { preferences.set(PreferenceKeys.ThemeMode, mode.ordinal) }
    fun setStyle(style: ThemeStyle) = update { preferences.set(PreferenceKeys.ThemeStyle, style.name.lowercase()) }
    fun setCompact(compact: Boolean) = update { preferences.set(PreferenceKeys.Compact, compact) }

    private fun update(block: suspend () -> Unit) {
        viewModelScope.launch { block() }
    }
}
