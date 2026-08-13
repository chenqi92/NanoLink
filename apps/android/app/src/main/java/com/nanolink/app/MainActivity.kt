package com.nanolink.app

import android.Manifest
import android.os.Bundle
import android.os.Build
import androidx.activity.result.contract.ActivityResultContracts
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
    private val notificationPermission = registerForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { /* NotificationService checks the resulting permission before posting. */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED
        ) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        setContent {
            val themeState by appViewModel.themeState.collectAsStateWithLifecycle()
            val language by appViewModel.currentLanguage.collectAsStateWithLifecycle()
            CompositionLocalProvider(
                LocalL10n provides appViewModel.localization,
                LocalLanguage provides language,
            ) {
                NanoThemeProvider(state = themeState) {
                    NanoShell(viewModel = appViewModel, modifier = Modifier.fillMaxSize())
                }
            }
        }
    }
}
