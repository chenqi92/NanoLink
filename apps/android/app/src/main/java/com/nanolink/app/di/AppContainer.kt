package com.nanolink.app.di

import android.content.Context
import com.nanolink.app.data.storage.PreferencesStore
import com.nanolink.app.data.storage.SecureStore
import com.nanolink.app.data.storage.StorageService
import com.nanolink.app.localization.L10n

class AppContainer(context: Context) {
    private val appContext = context.applicationContext
    val preferences = PreferencesStore(appContext)
    val secureStore = SecureStore(appContext)
    val storage = StorageService(preferences, secureStore)
    val l10n = L10n(appContext, preferences)
}
