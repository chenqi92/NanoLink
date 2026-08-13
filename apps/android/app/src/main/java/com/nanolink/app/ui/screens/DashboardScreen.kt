package com.nanolink.app.ui.screens

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Computer
import androidx.compose.material.icons.outlined.Dashboard
import androidx.compose.material.icons.outlined.Memory
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.nanolink.app.data.model.Agent
import com.nanolink.app.data.model.AuditEntry
import com.nanolink.app.state.AppViewModel
import com.nanolink.app.ui.design.NanoCard
import com.nanolink.app.ui.design.NanoEmptyState
import com.nanolink.app.ui.design.NanoKpiTile
import com.nanolink.app.ui.design.NanoListRow
import com.nanolink.app.ui.design.NanoMonoFamily
import com.nanolink.app.ui.design.NanoSectionLabel
import com.nanolink.app.ui.design.NanoSparkline
import com.nanolink.app.ui.design.NanoStatusDot
import com.nanolink.app.ui.design.nano
import com.nanolink.app.ui.tr
import kotlin.math.roundToInt

@Composable
fun DashboardScreen(viewModel: AppViewModel, modifier: Modifier = Modifier) {
    val t = nano
    val servers by viewModel.servers.collectAsStateWithLifecycle()
    val agents by viewModel.agents.collectAsStateWithLifecycle()
    val metrics by viewModel.metrics.collectAsStateWithLifecycle()
    val activity by viewModel.activity.collectAsStateWithLifecycle()
    val activeServerId by viewModel.activeServerId.collectAsStateWithLifecycle()

    val online = agents.filter { it.isOnline }
    val offline = agents.filter { !it.isOnline }

    fun average(select: (com.nanolink.app.data.model.AgentMetrics) -> Double): Double {
        val values = online.mapNotNull { metrics[it.id] }.map(select)
        return if (values.isEmpty()) 0.0 else values.average()
    }

    val avgCpu = average { it.cpuPercent }
    val avgMemory = average { it.memoryPercent }
    val memoryUsedGiB = online.mapNotNull { metrics[it.id]?.memory?.used }.sum() / (1024.0 * 1024.0 * 1024.0)
    val diskAlerts = agents.count { agent ->
        metrics[agent.id]?.disks?.any { it.usagePercent > 85 } == true
    }
    val topCpu = online.sortedByDescending { metrics[it.id]?.cpuPercent ?: 0.0 }.take(4)
    val recentActivity = activity.values.flatten().sortedByDescending { it.atMillis }.take(5)

    var cpuSpark by remember { mutableStateOf<List<Double>>(emptyList()) }
    var memSpark by remember { mutableStateOf<List<Double>>(emptyList()) }

    LaunchedEffect(metrics, activeServerId) {
        val samples = 20
        cpuSpark = List(samples) { avgCpu }
        memSpark = List(samples) { avgMemory }
    }

    if (servers.isEmpty()) {
        Box(modifier = modifier.fillMaxSize().padding(16.dp), contentAlignment = Alignment.Center) {
            NanoEmptyState(
                icon = Icons.Outlined.Dashboard,
                title = tr("dashboard.noServersYet"),
                detail = tr("dashboard.addFirstServer"),
            )
        }
        return
    }

    Box(modifier = modifier.fillMaxSize()) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 110.dp),
            verticalArrangement = Arrangement.spacedBy(0.dp),
        ) {
            item {
                DashboardHeader(servers.size, activeServerId)
                Spacer(Modifier.height(12.dp))
            }

            if (servers.size > 1) {
                item {
                    ServerChips(servers.map { it.name }, activeServerId ?: "")
                    Spacer(Modifier.height(12.dp))
                }
            }

            item {
                KpiGrid(
                    avgCpu = avgCpu,
                    avgMemory = avgMemory,
                    memoryUsedGiB = memoryUsedGiB,
                    onlineCount = online.size,
                    totalCount = agents.size,
                    diskAlerts = diskAlerts,
                    cpuSpark = cpuSpark,
                    memSpark = memSpark,
                )
                Spacer(Modifier.height(12.dp))
            }

            if (offline.isNotEmpty()) {
                item {
                    OfflineBanner(offline.size)
                    Spacer(Modifier.height(12.dp))
                }
            }

            item {
                NanoSectionLabel(tr("dashboard.topCpu"))
            }

            if (topCpu.isEmpty()) {
                item {
                    NanoCard(modifier = Modifier.padding(vertical = 12.dp)) {
                        Box(
                            modifier = Modifier.fillMaxWidth().padding(vertical = 22.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                tr("dashboard.noOnlineNodes"),
                                fontSize = 13.sp,
                                color = t.fg4,
                            )
                        }
                    }
                }
            } else {
                item {
                    NanoCard {
                        topCpu.forEachIndexed { index, agent ->
                            TopCpuRow(agent, metrics[agent.id], divider = index < topCpu.size - 1)
                        }
                    }
                }
            }

            item {
                Spacer(Modifier.height(12.dp))
                NanoSectionLabel(tr("dashboard.recentActivity"))
            }

            if (recentActivity.isEmpty()) {
                item {
                    NanoCard(modifier = Modifier.padding(vertical = 12.dp)) {
                        Box(
                            modifier = Modifier.fillMaxWidth().padding(vertical = 22.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(tr("dashboard.noActivity"), fontSize = 13.sp, color = t.fg4)
                        }
                    }
                }
            } else {
                item {
                    NanoCard {
                        recentActivity.forEachIndexed { index, entry ->
                            AuditRow(entry, divider = index < recentActivity.size - 1)
                        }
                    }
                }
            }
        }

        // Floating action button with gradient and shadow.
        FloatingActionButton(
            onClick = { /* Navigate to add server */ },
            containerColor = t.accent,
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(end = 16.dp, bottom = 16.dp),
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 18.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(Icons.Outlined.Add, contentDescription = null, tint = t.onAccent)
                Text(
                    tr("dashboard.newNode"),
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = t.onAccent,
                )
            }
        }
    }
}

@Composable
private fun DashboardHeader(serverCount: Int, activeServerId: String?) {
    val t = nano
    Row(
        modifier = Modifier.fillMaxWidth().padding(top = if (t.isIOS) 32.dp else 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            text = tr("dashboard.title"),
            fontSize = if (t.isIOS) 32.sp else 28.sp,
            fontWeight = if (t.isIOS) FontWeight.Bold else FontWeight.SemiBold,
            letterSpacing = if (t.isIOS) (-0.6).sp else 0.sp,
            color = t.fg,
        )
        Spacer(Modifier.weight(1f))
        CircleButton(icon = Icons.Outlined.Settings, gradient = true) { /* Assistant */ }
        CircleButton(icon = Icons.AutoMirrored.Outlined.List) { /* Agents */ }
        CircleButton(icon = Icons.Outlined.Computer) { /* Server switch */ }
    }
}

@Composable
private fun CircleButton(icon: ImageVector, gradient: Boolean = false, onClick: () -> Unit) {
    val t = nano
    Box(
        modifier = Modifier
            .size(34.dp)
            .clip(CircleShape)
            .background(
                if (gradient) {
                    Brush.linearGradient(listOf(t.accent, t.tertiary))
                } else {
                    Brush.linearGradient(listOf(t.card, t.card))
                },
            )
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = if (gradient) t.onAccent else t.accent,
            modifier = Modifier.size(16.dp),
        )
    }
}

@Composable
private fun ServerChips(names: List<String>, activeId: String) {
    val t = nano
    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items(names) { name ->
            val active = name.hashCode().toString() == activeId
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(16.dp))
                    .background(if (active) t.accent.copy(alpha = 0.15f) else t.card2)
                    .clickable { /* Switch server */ }
                    .padding(horizontal = 14.dp, vertical = 8.dp),
            ) {
                Text(
                    name,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    color = if (active) t.accent else t.fg2,
                )
            }
        }
    }
}

@Composable
private fun KpiGrid(
    avgCpu: Double,
    avgMemory: Double,
    memoryUsedGiB: Double,
    onlineCount: Int,
    totalCount: Int,
    diskAlerts: Int,
    cpuSpark: List<Double>,
    memSpark: List<Double>,
) {
    val t = nano
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NanoKpiTile(
                label = tr("dashboard.kpi.cpu"),
                value = "${avgCpu.roundToInt()}%",
                sub = tr("dashboard.kpi.avgAll"),
                icon = Icons.Outlined.Memory,
                tone = if (avgCpu > 85) "crit" else if (avgCpu > 70) "warn" else null,
                spark = cpuSpark,
                modifier = Modifier.weight(1f),
            )
            NanoKpiTile(
                label = tr("dashboard.kpi.memory"),
                value = "${avgMemory.roundToInt()}%",
                sub = String.format("%.1f GiB " + tr("dashboard.kpi.used"), memoryUsedGiB),
                icon = Icons.Outlined.Dashboard,
                tone = if (avgMemory > 85) "crit" else if (avgMemory > 75) "warn" else null,
                spark = memSpark,
                modifier = Modifier.weight(1f),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NanoKpiTile(
                label = tr("dashboard.kpi.nodes"),
                value = "$onlineCount/$totalCount",
                sub = tr("dashboard.kpi.online"),
                icon = Icons.Outlined.Computer,
                modifier = Modifier.weight(1f),
            )
            NanoKpiTile(
                label = tr("dashboard.kpi.diskAlerts"),
                value = diskAlerts.toString(),
                sub = tr("dashboard.kpi.over85"),
                icon = Icons.Outlined.Storage,
                tone = if (diskAlerts > 0) "warn" else null,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun OfflineBanner(count: Int) {
    val t = nano
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(t.cardRadius))
            .background(t.warn.copy(alpha = 0.12f))
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(Icons.Outlined.Warning, contentDescription = null, tint = t.warn, modifier = Modifier.size(18.dp))
        Text(
            tr("dashboard.offlineNodes", "count" to count),
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            color = t.warn,
        )
    }
}

@Composable
private fun TopCpuRow(
    agent: Agent,
    metrics: com.nanolink.app.data.model.AgentMetrics?,
    divider: Boolean,
) {
    val t = nano
    val cpu = metrics?.cpuPercent ?: 0.0
    NanoListRow(divider = divider) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            NanoStatusDot(color = if (agent.isOnline) t.ok else t.fg4, pulse = agent.isOnline)
            Spacer(Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(agent.hostname, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = t.fg)
                Text("${agent.os} ${agent.arch}", fontSize = 11.sp, fontFamily = NanoMonoFamily, color = t.fg4)
            }
            Spacer(Modifier.width(12.dp))
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    "${cpu.roundToInt()}%",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (cpu > 85) t.crit else if (cpu > 70) t.warn else t.fg,
                )
                Text("CPU", fontSize = 10.sp, fontFamily = NanoMonoFamily, color = t.fg4)
            }
        }
    }
}

@Composable
private fun AuditRow(entry: AuditEntry, divider: Boolean) {
    val t = nano
    NanoListRow(divider = divider) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                when (entry.type.uppercase()) {
                    "CREATE", "START" -> Icons.Outlined.Check
                    "DELETE", "STOP" -> Icons.Outlined.Close
                    else -> Icons.Outlined.Settings
                },
                contentDescription = null,
                tint = t.fg3,
                modifier = Modifier.size(14.dp),
            )
            Spacer(Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text("${entry.type} ${entry.target}", fontSize = 13.sp, color = t.fg2, maxLines = 1)
                Text(
                    java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.US)
                        .format(java.util.Date(entry.atMillis)),
                    fontSize = 10.sp,
                    fontFamily = NanoMonoFamily,
                    color = t.fg4,
                )
            }
        }
    }
}
