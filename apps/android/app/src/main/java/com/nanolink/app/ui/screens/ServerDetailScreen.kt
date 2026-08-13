package com.nanolink.app.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Computer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.nanolink.app.data.model.ConnectionMode
import com.nanolink.app.state.AppViewModel
import com.nanolink.app.ui.design.NanoButton
import com.nanolink.app.ui.design.NanoButtonVariant
import com.nanolink.app.ui.design.NanoCard
import com.nanolink.app.ui.design.NanoEmptyState
import com.nanolink.app.ui.design.NanoListRow
import com.nanolink.app.ui.design.NanoMonoFamily
import com.nanolink.app.ui.design.NanoStatusDot
import com.nanolink.app.ui.design.nano
import com.nanolink.app.ui.tr
import com.nanolink.app.util.Fmt

@Composable
fun ServerDetailScreen(
    viewModel: AppViewModel,
    serverId: String,
    onBack: () -> Unit,
    onRemoved: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val t = nano
    val servers by viewModel.servers.collectAsStateWithLifecycle()
    val agents by viewModel.agents.collectAsStateWithLifecycle()
    val activeServerId by viewModel.activeServerId.collectAsStateWithLifecycle()
    val modes by viewModel.connectionModes.collectAsStateWithLifecycle()
    val server = servers.firstOrNull { it.id == serverId }
    var confirmRemove by remember { mutableStateOf(false) }

    Column(modifier = modifier.fillMaxSize()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(start = 4.dp, end = 16.dp, top = 4.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = tr("common.cancel"), tint = t.fg)
            }
            Text(
                server?.name ?: tr("serverDetail.notFound"),
                fontSize = 22.sp,
                fontWeight = FontWeight.SemiBold,
                color = t.fg,
                maxLines = 1,
            )
        }

        if (server == null) {
            Box(Modifier.fillMaxSize().padding(16.dp), contentAlignment = Alignment.Center) {
                NanoEmptyState(
                    icon = Icons.Outlined.Computer,
                    title = tr("serverDetail.notFound"),
                    detail = serverId,
                )
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                item {
                    NanoCard {
                        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                NanoStatusDot(
                                    color = if (server.isConnected) t.ok else t.fg4,
                                    pulse = server.isConnected,
                                )
                                Spacer(Modifier.padding(horizontal = 5.dp))
                                Text(
                                    if (server.isConnected) tr("status.connected") else tr("status.closed"),
                                    color = if (server.isConnected) t.ok else t.fg4,
                                    fontWeight = FontWeight.Medium,
                                )
                            }
                            Text(server.url, fontSize = 12.sp, fontFamily = NanoMonoFamily, color = t.fg3)
                        }
                    }
                }

                item {
                    NanoCard {
                        Column {
                            DetailRow(
                                tr("serverDetail.connectionMode"),
                                when (modes[server.id] ?: ConnectionMode.DISCONNECTED) {
                                    ConnectionMode.WEBSOCKET -> tr("serverDetail.modeWebsocket")
                                    ConnectionMode.HTTP_POLLING -> tr("serverDetail.modeHttp")
                                    ConnectionMode.DISCONNECTED -> tr("serverDetail.modeDisconnected")
                                },
                            )
                            DetailRow(
                                tr("serverDetail.authType"),
                                if (server.hasFullPermissions) tr("serverDetail.authFull") else tr("serverDetail.authReadonly"),
                            )
                            DetailRow(
                                tr("serverDetail.nodeCount"),
                                agents.count { it.serverId == server.id }.toString(),
                            )
                            if (!server.username.isNullOrBlank()) {
                                DetailRow(tr("serverDetail.username"), server.username)
                            }
                            DetailRow(
                                tr("serverDetail.lastConnected"),
                                server.lastConnectedMillis?.let(Fmt::dateTime) ?: "—",
                                divider = false,
                            )
                        }
                    }
                }

                if (activeServerId != server.id) {
                    item {
                        NanoButton(
                            label = tr("serverDetail.setActive"),
                            onClick = { viewModel.setActiveServer(server.id) },
                            fullWidth = true,
                        )
                    }
                }

                item {
                    NanoButton(
                        label = tr("serverDetail.removeServer"),
                        onClick = { confirmRemove = true },
                        variant = NanoButtonVariant.DANGER,
                        fullWidth = true,
                    )
                }
            }
        }
    }

    if (server != null && confirmRemove) {
        AlertDialog(
            onDismissRequest = { confirmRemove = false },
            title = { Text(tr("serverDetail.removeConfirmTitle")) },
            text = { Text(tr("serverDetail.removeConfirmBody", "name" to server.name)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmRemove = false
                    viewModel.removeServer(server.id)
                    onRemoved()
                }) {
                    Text(tr("serverDetail.remove"), color = t.crit)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmRemove = false }) { Text(tr("common.cancel")) }
            },
        )
    }
}

@Composable
private fun DetailRow(label: String, value: String, divider: Boolean = true) {
    val t = nano
    NanoListRow(divider = divider) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(label, fontSize = 14.sp, color = t.fg2, modifier = Modifier.weight(1f))
            Text(value, fontSize = 12.sp, color = t.fg3, fontFamily = NanoMonoFamily)
        }
    }
}
