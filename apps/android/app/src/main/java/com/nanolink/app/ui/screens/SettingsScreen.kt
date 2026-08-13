package com.nanolink.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.Computer
import androidx.compose.material.icons.outlined.DarkMode
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavHostController
import com.nanolink.app.data.model.ServerConnection
import com.nanolink.app.data.storage.PreferencesStore
import com.nanolink.app.state.AppViewModel
import com.nanolink.app.state.ThemeViewModel
import com.nanolink.app.ui.design.NanoCard
import com.nanolink.app.ui.design.NanoListRow
import com.nanolink.app.ui.design.NanoMonoFamily
import com.nanolink.app.ui.design.NanoStatusDot
import com.nanolink.app.ui.design.nano
import com.nanolink.app.ui.tr

@Composable
fun SettingsScreen(
    viewModel: AppViewModel,
    preferences: PreferencesStore,
    navController: NavHostController,
    modifier: Modifier = Modifier
) {
    val t = nano
    val servers by viewModel.servers.collectAsStateWithLifecycle()
    val themeViewModel = remember { ThemeViewModel(preferences) }
    val themeState by themeViewModel.state.collectAsStateWithLifecycle()

    var showThemePicker by remember { mutableStateOf(false) }
    var showLanguagePicker by remember { mutableStateOf(false) }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = if (t.isIOS) 32.dp else 8.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Header
        item {
            Text(
                tr("settings.title"),
                fontSize = if (t.isIOS) 32.sp else 28.sp,
                fontWeight = if (t.isIOS) FontWeight.Bold else FontWeight.SemiBold,
                letterSpacing = if (t.isIOS) (-0.6).sp else 0.sp,
                color = t.fg,
                modifier = Modifier.padding(bottom = 8.dp),
            )
        }

        // Servers
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    tr("settings.servers"),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = t.fg4,
                    modifier = Modifier.padding(horizontal = 4.dp),
                )
                NanoCard {
                    Column {
                        servers.forEachIndexed { index, server ->
                            ServerRow(server, divider = index < servers.size)
                        }
                        NanoListRow(divider = false) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { /* Navigate to add server */ }
                                    .padding(vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Icon(Icons.Outlined.Add, contentDescription = null, tint = t.accent, modifier = Modifier.size(18.dp))
                                Spacer(Modifier.width(12.dp))
                                Text(tr("settings.addServer"), fontSize = 15.sp, color = t.accent)
                            }
                        }
                    }
                }
            }
        }

        // Appearance
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    tr("settings.appearance"),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = t.fg4,
                    modifier = Modifier.padding(horizontal = 4.dp),
                )
                NanoCard {
                    Column {
                        NanoListRow(divider = true) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { showThemePicker = !showThemePicker }
                                    .padding(vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Icon(Icons.Outlined.DarkMode, contentDescription = null, tint = t.fg3, modifier = Modifier.size(18.dp))
                                Spacer(Modifier.width(12.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(tr("settings.theme"), fontSize = 15.sp, color = t.fg)
                                    Text(
                                        when (themeState.mode) {
                                            com.nanolink.app.state.AppThemeMode.LIGHT -> tr("settings.light")
                                            com.nanolink.app.state.AppThemeMode.DARK -> tr("settings.dark")
                                            else -> tr("settings.system")
                                        },
                                        fontSize = 12.sp,
                                        color = t.fg4,
                                    )
                                }
                                Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = t.fg4, modifier = Modifier.size(16.dp))
                            }
                        }
                        NanoListRow(divider = true) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable { showLanguagePicker = !showLanguagePicker }
                                    .padding(vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Icon(Icons.Outlined.Language, contentDescription = null, tint = t.fg3, modifier = Modifier.size(18.dp))
                                Spacer(Modifier.width(12.dp))
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(tr("settings.language"), fontSize = 15.sp, color = t.fg)
                                    Text(
                                        "English",
                                        fontSize = 12.sp,
                                        color = t.fg4,
                                    )
                                }
                                Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = t.fg4, modifier = Modifier.size(16.dp))
                            }
                        }
                        NanoListRow(divider = false) {
                            Row(
                                modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(modifier = Modifier.weight(1f)) {
                                    Text(tr("settings.compactMode"), fontSize = 15.sp, color = t.fg)
                                    Text(tr("settings.compactModeDetail"), fontSize = 12.sp, color = t.fg4)
                                }
                                Switch(
                                    checked = themeState.compact,
                                    onCheckedChange = { themeViewModel.setCompact(it) },
                                    colors = SwitchDefaults.colors(
                                        checkedThumbColor = t.bg,
                                        checkedTrackColor = t.accent,
                                        uncheckedThumbColor = t.fg4,
                                        uncheckedTrackColor = t.card2,
                                    ),
                                )
                            }
                        }
                    }
                }
            }
        }

        // About
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    tr("settings.about"),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = t.fg4,
                    modifier = Modifier.padding(horizontal = 4.dp),
                )
                NanoCard {
                    Column {
                        NanoListRow(divider = true) {
                            Row(
                                modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(tr("settings.version"), fontSize = 15.sp, color = t.fg, modifier = Modifier.weight(1f))
                                Text("v0.5.0", fontSize = 13.sp, fontFamily = NanoMonoFamily, color = t.fg3)
                            }
                        }
                        NanoListRow(divider = false) {
                            Row(
                                modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(tr("settings.source"), fontSize = 15.sp, color = t.fg, modifier = Modifier.weight(1f))
                                Text("github.com/chenqi92/NanoLink", fontSize = 11.sp, fontFamily = NanoMonoFamily, color = t.accent)
                            }
                        }
                    }
                }
            }
        }

        item { Spacer(Modifier.height(32.dp)) }
    }
}

@Composable
private fun ServerRow(server: ServerConnection, divider: Boolean) {
    val t = nano
    NanoListRow(divider = divider) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { /* Navigate to server detail */ }
                .padding(vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            NanoStatusDot(color = if (server.isConnected) t.ok else t.fg4, pulse = server.isConnected)
            Spacer(Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(server.name.ifEmpty { server.url.substringAfter("://").substringBefore("/").substringBefore(":") }, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = t.fg)
                Text(server.url.substringAfter("://").substringBefore("/"), fontSize = 11.sp, fontFamily = NanoMonoFamily, color = t.fg4)
            }
            Icon(Icons.Outlined.ChevronRight, contentDescription = null, tint = t.fg4, modifier = Modifier.size(16.dp))
        }
    }
}
