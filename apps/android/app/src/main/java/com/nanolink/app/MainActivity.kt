package com.nanolink.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.nanolink.app.state.AppViewModel
import com.nanolink.app.ui.LocalL10n
import com.nanolink.app.ui.LocalLanguage
import com.nanolink.app.ui.NanoShell
import com.nanolink.app.ui.design.NanoThemeProvider

class MainActivity : ComponentActivity() {
    private val appViewModel: AppViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val themeState by appViewModel.themeState.collectAsStateWithLifecycle()
            val language by appViewModel.currentLanguage.collectAsStateWithLifecycle()
            CompositionLocalProvider(
                LocalL10n provides appViewModel.localization,
                LocalLanguage provides language,
            ) {
                NanoThemeProvider(state = themeState) {
                    NanoShell(viewModel = appViewModel, preferences = appViewModel.getPreferences(), modifier = Modifier.fillMaxSize())
                }
            }
        }
    }
}
