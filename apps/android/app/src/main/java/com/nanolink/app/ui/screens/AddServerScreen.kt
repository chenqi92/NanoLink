package com.nanolink.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Security
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nanolink.app.BuildConfig
import com.nanolink.app.state.AppViewModel
import com.nanolink.app.ui.design.NanoCard
import com.nanolink.app.ui.design.nano
import com.nanolink.app.ui.tr
import kotlinx.coroutines.launch
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

private enum class AddServerMode { ACCOUNT, TOKEN, PAIRING }

internal fun normalizedServerUrl(raw: String, forceTls: Boolean): String? {
    val parsed = raw.trim().trimEnd('/').toHttpUrlOrNull() ?: return null
    if (parsed.scheme != "http" && parsed.scheme != "https") return null
    if (parsed.username.isNotEmpty() || parsed.password.isNotEmpty()) return null
    if (parsed.querySize > 0 || parsed.fragment != null) return null
    val normalized = if (forceTls && parsed.scheme == "http") {
        parsed.newBuilder().scheme("https").build()
    } else {
        parsed
    }
    return normalized.toString().trimEnd('/')
}

@Composable
fun AddServerScreen(
    viewModel: AppViewModel,
    onBack: () -> Unit,
    onAdded: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val t = nano
    val scope = rememberCoroutineScope()
    var mode by remember { mutableStateOf(AddServerMode.ACCOUNT) }
    var name by remember { mutableStateOf("NanoOps") }
    var url by remember { mutableStateOf(BuildConfig.DEFAULT_SERVER_URL) }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var token by remember { mutableStateOf("") }
    var pairingCode by remember { mutableStateOf("") }
    var showAdvanced by remember { mutableStateOf(false) }
    var forceTls by remember { mutableStateOf(false) }
    var ignoreCert by remember { mutableStateOf(false) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    fun submit() {
        if (loading) return
        val serverName = name.trim()
        val serverUrl = normalizedServerUrl(url, forceTls)
        error = when {
            serverName.isEmpty() -> viewModel.localization.text("addServer.nameRequired")
            url.isBlank() -> viewModel.localization.text("addServer.urlRequired")
            serverUrl == null -> viewModel.localization.text("addServer.urlInvalid")
            mode == AddServerMode.ACCOUNT && username.isBlank() -> viewModel.localization.text("addServer.usernameRequired")
            mode == AddServerMode.ACCOUNT && password.isBlank() -> viewModel.localization.text("addServer.passwordRequired")
            mode == AddServerMode.TOKEN && token.isBlank() -> viewModel.localization.text("addServer.deviceTokenRequired")
            mode == AddServerMode.PAIRING && !pairingCode.matches(Regex("\\d{6}")) -> {
                viewModel.localization.text("addServer.pairingCodeInvalid")
            }
            else -> null
        }
        if (error != null || serverUrl == null) return

        loading = true
        scope.launch {
            val added = when (mode) {
                AddServerMode.ACCOUNT -> viewModel.addServerWithCredentials(
                    name = serverName,
                    url = serverUrl,
                    username = username.trim(),
                    password = password,
                    forceTls = forceTls,
                    ignoreCert = ignoreCert,
                )
                AddServerMode.TOKEN -> viewModel.addServer(
                    name = serverName,
                    url = serverUrl,
                    token = token.trim(),
                    forceTls = forceTls,
                    ignoreCert = ignoreCert,
                )
                AddServerMode.PAIRING -> viewModel.addServerWithPairingCode(
                    name = serverName,
                    url = serverUrl,
                    pairingCode = pairingCode,
                    forceTls = forceTls,
                    ignoreCert = ignoreCert,
                )
            }
            loading = false
            if (added) onAdded()
            else {
                error = when (mode) {
                    AddServerMode.ACCOUNT -> viewModel.localization.text("addServer.loginFailed")
                    AddServerMode.PAIRING -> viewModel.localization.text("addServer.pairingFailed")
                    AddServerMode.TOKEN -> viewModel.localization.text("addServer.connectionFailed")
                }
            }
        }
    }

    Column(modifier = modifier.fillMaxSize()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(start = 4.dp, end = 16.dp, top = 4.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = tr("common.cancel"), tint = t.fg)
            }
            Text(
                tr("addServer.title"),
                fontSize = 22.sp,
                fontWeight = FontWeight.SemiBold,
                color = t.fg,
            )
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item {
                Text(tr("server.chooseMethodDesc"), fontSize = 13.sp, color = t.fg3)
                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 10.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    ModeChip(
                        label = tr("addServer.methodAccount"),
                        selected = mode == AddServerMode.ACCOUNT,
                        onClick = { mode = AddServerMode.ACCOUNT; error = null },
                        modifier = Modifier.weight(1f),
                    )
                    ModeChip(
                        label = tr("addServer.methodManual"),
                        selected = mode == AddServerMode.TOKEN,
                        onClick = { mode = AddServerMode.TOKEN; error = null },
                        modifier = Modifier.weight(1f),
                    )
                    ModeChip(
                        label = tr("addServer.methodPairing"),
                        selected = mode == AddServerMode.PAIRING,
                        onClick = { mode = AddServerMode.PAIRING; error = null },
                        modifier = Modifier.weight(1f),
                    )
                }
            }

            item {
                NanoCard {
                    Column(
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        OutlinedTextField(
                            value = name,
                            onValueChange = { name = it; error = null },
                            label = { Text(tr("addServer.serverName")) },
                            placeholder = { Text(tr("addServer.serverNameHint")) },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth(),
                        )
                        OutlinedTextField(
                            value = url,
                            onValueChange = { url = it; error = null },
                            label = { Text(tr("addServer.serverUrl")) },
                            placeholder = { Text(BuildConfig.DEFAULT_SERVER_URL) },
                            singleLine = true,
                            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                            modifier = Modifier.fillMaxWidth(),
                        )
                        when (mode) {
                            AddServerMode.ACCOUNT -> {
                                OutlinedTextField(
                                    value = username,
                                    onValueChange = { username = it; error = null },
                                    label = { Text(tr("addServer.username")) },
                                    singleLine = true,
                                    modifier = Modifier.fillMaxWidth(),
                                )
                                OutlinedTextField(
                                    value = password,
                                    onValueChange = { password = it; error = null },
                                    label = { Text(tr("addServer.password")) },
                                    singleLine = true,
                                    visualTransformation = PasswordVisualTransformation(),
                                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                                    modifier = Modifier.fillMaxWidth(),
                                )
                            }
                            AddServerMode.TOKEN -> OutlinedTextField(
                                value = token,
                                onValueChange = { token = it; error = null },
                                label = { Text(tr("addServer.deviceTokenOptional")) },
                                placeholder = { Text(tr("addServer.deviceTokenHint")) },
                                singleLine = true,
                                visualTransformation = PasswordVisualTransformation(),
                                modifier = Modifier.fillMaxWidth(),
                            )
                            AddServerMode.PAIRING -> OutlinedTextField(
                                value = pairingCode,
                                onValueChange = { value ->
                                    pairingCode = value.filter(Char::isDigit).take(6)
                                    error = null
                                },
                                label = { Text(tr("addServer.pairingCode")) },
                                placeholder = { Text(tr("addServer.pairingCodeHint")) },
                                singleLine = true,
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                    }
                }
            }

            item {
                NanoCard {
                    Column(Modifier.fillMaxWidth()) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable { showAdvanced = !showAdvanced }
                                .padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(Icons.Outlined.Security, contentDescription = null, tint = t.fg3)
                            Spacer(Modifier.width(10.dp))
                            Text(tr("addServer.advanced"), color = t.fg, modifier = Modifier.weight(1f))
                            Icon(Icons.Outlined.ExpandMore, contentDescription = null, tint = t.fg4)
                        }
                        if (showAdvanced) {
                            ToggleRow(tr("addServer.forceTls"), forceTls) { forceTls = it }
                            ToggleRow(tr("addServer.ignoreCert"), ignoreCert) { ignoreCert = it }
                            if (ignoreCert) {
                                Text(
                                    tr("addServer.ignoreCertWarning"),
                                    fontSize = 12.sp,
                                    color = t.warn,
                                    modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 14.dp),
                                )
                            }
                        }
                    }
                }
            }

            if (error != null) {
                item {
                    Text(
                        error.orEmpty(),
                        color = t.crit,
                        fontSize = 13.sp,
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp),
                    )
                }
            }

            item {
                Button(
                    onClick = ::submit,
                    enabled = !loading,
                    shape = RoundedCornerShape(t.buttonRadius),
                    modifier = Modifier.fillMaxWidth().height(50.dp),
                ) {
                    if (loading) {
                        CircularProgressIndicator(modifier = Modifier.height(20.dp).width(20.dp), strokeWidth = 2.dp)
                        Spacer(Modifier.width(10.dp))
                    }
                    Text(if (mode == AddServerMode.ACCOUNT) tr("addServer.login") else tr("addServer.connect"))
                }
            }
        }
    }
}

@Composable
private fun ModeChip(label: String, selected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(label, maxLines = 1, fontSize = 11.sp) },
        modifier = modifier,
    )
}

@Composable
private fun ToggleRow(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    val t = nano
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = t.fg2, fontSize = 14.sp, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}
