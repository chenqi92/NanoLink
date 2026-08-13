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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Computer
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.nanolink.app.state.AppViewModel
import com.nanolink.app.ui.design.NanoButton
import com.nanolink.app.ui.design.NanoButtonVariant
import com.nanolink.app.ui.design.NanoCard
import com.nanolink.app.ui.design.NanoEmptyState
import com.nanolink.app.ui.design.NanoMeter
import com.nanolink.app.ui.design.NanoMonoFamily
import com.nanolink.app.ui.design.NanoPermPill
import com.nanolink.app.ui.design.NanoSectionLabel
import com.nanolink.app.ui.design.NanoStatusDot
import com.nanolink.app.ui.design.nano
import com.nanolink.app.ui.tr
import com.nanolink.app.util.Fmt
import java.util.Locale

@Composable
fun AgentDetailScreen(
    viewModel: AppViewModel,
    agentId: String,
    onBack: () -> Unit,
    onOpenTerminal: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val t = nano
    val agents by viewModel.agents.collectAsStateWithLifecycle()
    val metricsByAgent by viewModel.metrics.collectAsStateWithLifecycle()
    val agent = agents.firstOrNull { it.id == agentId }
    val metrics = metricsByAgent[agentId]

    Column(modifier = modifier.fillMaxSize()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(start = 4.dp, end = 16.dp, top = 4.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = tr("common.cancel"), tint = t.fg)
            }
            Text(
                agent?.hostname ?: tr("agents.noMatch"),
                fontSize = 22.sp,
                fontWeight = FontWeight.SemiBold,
                color = t.fg,
                maxLines = 1,
            )
        }

        if (agent == null) {
            Box(Modifier.fillMaxSize().padding(16.dp), contentAlignment = Alignment.Center) {
                NanoEmptyState(Icons.Outlined.Computer, tr("agents.noMatch"), agentId)
            }
            return@Column
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            item {
                NanoCard {
                    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            NanoStatusDot(
                                color = if (agent.isOnline) t.ok else t.fg4,
                                pulse = agent.isOnline,
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(
                                if (agent.isOnline) tr("common.online") else tr("common.offline"),
                                color = if (agent.isOnline) t.ok else t.fg4,
                                fontWeight = FontWeight.Medium,
                            )
                            Spacer(Modifier.weight(1f))
                            NanoPermPill(agent.permissionLevel)
                        }
                        Text(
                            "${agent.os} · ${agent.arch} · ${tr("agentDetail.agentVersion", "version" to agent.version)}",
                            fontSize = 12.sp,
                            fontFamily = NanoMonoFamily,
                            color = t.fg3,
                        )
                        Text(
                            tr("agentDetail.lastHeartbeat", "ago" to Fmt.ago(agent.lastHeartbeatMillis)),
                            fontSize = 11.sp,
                            color = t.fg4,
                        )
                    }
                }
            }

            if (metrics == null) {
                item {
                    NanoEmptyState(
                        icon = Icons.Outlined.Computer,
                        title = if (agent.isOnline) tr("metrics.loadingMetrics") else tr("agentDetail.nodeOffline"),
                        detail = tr("metrics.waitingForMetrics"),
                    )
                }
            } else {
                item { NanoSectionLabel(tr("metrics.overview")) }
                item {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        UsageCard(tr("agentDetail.cpu"), metrics.cpuPercent, Modifier.weight(1f))
                        UsageCard(tr("agentDetail.memory"), metrics.memoryPercent, Modifier.weight(1f))
                        UsageCard(tr("agentDetail.storage"), metrics.diskPercent, Modifier.weight(1f))
                    }
                }

                item { NanoSectionLabel(tr("agentDetail.cpu")) }
                item {
                    NanoCard {
                        Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                            InfoRow(tr("agentDetail.utilization"), Fmt.percent(metrics.cpuPercent))
                            InfoRow(tr("metrics.cpu"), metrics.cpu.model.ifBlank { "—" })
                            InfoRow(tr("agentDetail.perCore"), metrics.cpu.coreCount.toString())
                            metrics.cpu.frequencyGhz?.let {
                                InfoRow(tr("agentDetail.ghz", "value" to String.format(Locale.US, "%.2f", it)), "")
                            }
                        }
                    }
                }

                item { NanoSectionLabel(tr("agentDetail.memory")) }
                item {
                    NanoCard {
                        Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                            InfoRow(tr("agentDetail.memUsed"), Fmt.bytes(metrics.memory.used.toDouble()))
                            InfoRow(tr("agentDetail.memAvailable"), Fmt.bytes(metrics.memory.available.toDouble()))
                            InfoRow(tr("metrics.swapUsed"), Fmt.bytes(metrics.memory.swapUsed.toDouble()))
                        }
                    }
                }

                if (metrics.disks.isNotEmpty()) {
                    item { NanoSectionLabel(tr("agentDetail.storage")) }
                    items(metrics.disks, key = { it.id }) { disk ->
                        NanoCard {
                            Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                                InfoRow(disk.mountPoint.ifBlank { disk.device }, Fmt.percent(disk.usagePercent))
                                NanoMeter(disk.usagePercent / 100.0)
                                Text(
                                    "${Fmt.bytes(disk.used.toDouble())} / ${Fmt.bytes(disk.total.toDouble())} · ${disk.fsType}",
                                    fontSize = 11.sp,
                                    fontFamily = NanoMonoFamily,
                                    color = t.fg4,
                                )
                            }
                        }
                    }
                }

                if (metrics.networks.isNotEmpty()) {
                    item { NanoSectionLabel(tr("agentDetail.networkInterfaces")) }
                    items(metrics.networks, key = { it.id }) { network ->
                        NanoCard {
                            Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                InfoRow(network.interfaceName, network.ipAddresses.firstOrNull() ?: "—")
                                Text(
                                    "↓ ${Fmt.rate(network.rxBytesPerSec)}   ↑ ${Fmt.rate(network.txBytesPerSec)}",
                                    fontSize = 12.sp,
                                    fontFamily = NanoMonoFamily,
                                    color = t.fg3,
                                )
                            }
                        }
                    }
                }

                metrics.systemInfo?.let { system ->
                    item { NanoSectionLabel(tr("agentDetail.systemInfo")) }
                    item {
                        NanoCard {
                            Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(7.dp)) {
                                InfoRow(tr("agentDetail.osLabel"), "${system.osName} ${system.osVersion}")
                                InfoRow(tr("agentDetail.kernel"), system.kernelVersion)
                                InfoRow(tr("agentDetail.uptime"), Fmt.uptime(system.uptimeSeconds))
                                system.primaryIp?.let { InfoRow(tr("agentDetail.primaryIp"), it) }
                            }
                        }
                    }
                }
            }

            item {
                NanoButton(
                    label = if (agent.permissionLevel >= 3) tr("actions.openTerminal") else tr("terminal.lockedTitle"),
                    onClick = onOpenTerminal,
                    icon = Icons.Outlined.Terminal,
                    variant = NanoButtonVariant.PRIMARY,
                    fullWidth = true,
                    enabled = agent.isOnline && agent.permissionLevel >= 3,
                )
            }
        }
    }
}

@Composable
private fun UsageCard(label: String, value: Double, modifier: Modifier = Modifier) {
    val t = nano
    NanoCard(modifier) {
        Column(Modifier.fillMaxWidth().padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(label, fontSize = 11.sp, color = t.fg4)
            Text(Fmt.percent(value), fontSize = 19.sp, fontWeight = FontWeight.SemiBold, color = t.meterColor(value))
            NanoMeter(value / 100.0)
        }
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    val t = nano
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, fontSize = 12.sp, color = t.fg3, modifier = Modifier.weight(1f))
        if (value.isNotEmpty()) {
            Text(value, fontSize = 12.sp, fontFamily = NanoMonoFamily, color = t.fg2, maxLines = 1)
        }
    }
}
