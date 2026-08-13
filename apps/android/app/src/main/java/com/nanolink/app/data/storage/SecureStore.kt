package com.nanolink.app.data.storage

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

class SecureStore(context: Context) {
    private val preferences = EncryptedSharedPreferences.create(
        context,
        "nanolink_secrets",
        MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    fun get(key: String): String? = preferences.getString(key, null)

    fun set(key: String, value: String?) {
        preferences.edit().apply {
            if (value.isNullOrEmpty()) remove(key) else putString(key, value)
        }.apply()
    }

    fun remove(key: String) {
        preferences.edit().remove(key).apply()
    }
}
