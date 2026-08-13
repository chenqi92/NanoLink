package com.nanolink.app.localization

import android.content.Context
import com.nanolink.app.data.storage.PreferenceKeys
import com.nanolink.app.data.storage.PreferencesStore
import java.util.Locale
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject

class L10n(
    private val context: Context,
    private val preferences: PreferencesStore,
) {
    private val tables = mutableMapOf<String, JsonObject>()

    init {
        load("en")
        load("zh")
    }

    val language: Flow<String> = preferences.flow(PreferenceKeys.Language, systemLanguage())
    @Volatile private var selectedLanguage = systemLanguage()

    private val _currentLanguageFlow = MutableStateFlow(selectedLanguage)
    val currentLanguageFlow: StateFlow<String> = _currentLanguageFlow.asStateFlow()

    suspend fun setLanguage(language: String) {
        selectedLanguage = if (language == "zh") "zh" else "en"
        preferences.set(PreferenceKeys.Language, selectedLanguage)
        _currentLanguageFlow.value = selectedLanguage
    }

    suspend fun currentLanguage(): String = language.first().also {
        selectedLanguage = it
        _currentLanguageFlow.value = it
    }

    fun text(key: String, named: Map<String, Any?> = emptyMap(), args: List<Any?> = emptyList()): String {
        var value = lookup(key, tables[selectedLanguage]) ?: lookup(key, tables["en"]) ?: key
        named.forEach { (name, replacement) -> value = value.replace("{$name}", replacement?.toString().orEmpty()) }
        args.forEach { replacement -> value = value.replaceFirst("{}", replacement?.toString().orEmpty()) }
        return value
    }

    private fun load(language: String) {
        runCatching {
            context.assets.open("i18n/$language.json").use { input ->
                tables[language] = Json.parseToJsonElement(input.bufferedReader().readText()).jsonObject
            }
        }
    }

    private fun lookup(key: String, root: JsonObject?): String? {
        var node: kotlinx.serialization.json.JsonElement = root ?: return null
        key.split('.').forEach { part ->
            node = (node as? JsonObject)?.get(part) ?: return null
        }
        return (node as? JsonPrimitive)?.contentOrNull
    }

    private fun systemLanguage(): String =
        if (Locale.getDefault().language == "zh") "zh" else "en"
}
