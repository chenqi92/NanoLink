package com.nanolink.app.data.storage

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.nanoPreferences by preferencesDataStore(name = "nanolink_preferences")

object PreferenceKeys {
    val Servers = stringPreferencesKey("servers_metadata")
    val ActiveServer = stringPreferencesKey("active_server_id")
    val ThemeMode = intPreferencesKey("theme_mode")
    val ThemeStyle = stringPreferencesKey("theme_style")
    val Language = stringPreferencesKey("app_language")
    val Compact = booleanPreferencesKey("ui_compact")
    val NotifyOffline = booleanPreferencesKey("notify_offline")
    val NotifyHigh = booleanPreferencesKey("notify_high")
    val NotifyDisk = booleanPreferencesKey("notify_disk")
    val NotifyAudit = booleanPreferencesKey("notify_audit")
    val TerminalTheme = stringPreferencesKey("term_theme")
    val TerminalFontSize = intPreferencesKey("term_font_size")
    val TerminalCursor = stringPreferencesKey("term_cursor")
    val TerminalCursorBlink = booleanPreferencesKey("term_cursor_blink")
    val FaceId = booleanPreferencesKey("sec_face_id")
    val AutoLock = intPreferencesKey("sec_auto_lock")
}

class PreferencesStore(private val context: Context) {
    val data: Flow<Preferences> = context.nanoPreferences.data

    suspend fun <T> get(key: Preferences.Key<T>, default: T): T = data.first()[key] ?: default

    fun <T> flow(key: Preferences.Key<T>, default: T): Flow<T> = data.map { it[key] ?: default }

    suspend fun <T> set(key: Preferences.Key<T>, value: T) {
        context.nanoPreferences.edit { it[key] = value }
    }

    suspend fun remove(key: Preferences.Key<*>) {
        context.nanoPreferences.edit { it.remove(key) }
    }
}
