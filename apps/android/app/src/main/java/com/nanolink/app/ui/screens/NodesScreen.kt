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
import androidx.compose.material.icons.outlined.Computer
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Icon
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
import com.nanolink.app.data.model.Agent
import com.nanolink.app.state.AppViewModel
import com.nanolink.app.ui.design.NanoCard
import com.nanolink.app.ui.design.NanoEmptyState
import com.nanolink.app.ui.design.NanoListRow
import com.nanolink.app.ui.design.NanoMonoFamily
import com.nanolink.app.ui.design.NanoStatusDot
import com.nanolink.app.ui.design.nano
import com.nanolink.app.ui.tr
import kotlin.math.roundToInt

@Composable
fun NodesScreen(viewModel: AppViewModel, onNavigateToDetail: (Agent) -> Unit, modifier: Modifier = Modifier) {
    val t = nano
    val agents by viewModel.agents.collectAsStateWithLifecycle()
    val metrics by viewModel.metrics.collectAsStateWithLifecycle()

    var searchQuery by remember { mutableStateOf("") }
    var filterOnline by remember { mutableStateOf(false) }

    val filtered = agents.filter { agent ->
        (searchQuery.isEmpty() || agent.hostname.contains(searchQuery, ignoreCase = true)) &&
        (!filterOnline || agent.isOnline)
    }.sortedWith(compareByDescending<Agent> { it.isOnline }.thenBy { it.hostname })

    if (agents.isEmpty()) {
        Box(modifier = modifier.fillMaxSize().padding(16.dp), contentAlignment = Alignment.Center) {
            NanoEmptyState(
                icon = Icons.Outlined.Computer,
                title = tr("nodes.noNodesYet"),
                detail = tr("nodes.addFirstNode"),
            )
        }
        return
    }

    Column(modifier = modifier.fillMaxSize()) {
        // Header with title and action buttons
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 16.dp, end = 16.dp, top = if (t.isIOS) 32.dp else 4.dp, bottom = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                tr("nodes.title"),
                fontSize = if (t.isIOS) 32.sp else 28.sp,
                fontWeight = if (t.isIOS) FontWeight.Bold else FontWeight.SemiBold,
                letterSpacing = if (t.isIOS) (-0.6).sp else 0.sp,
                color = t.fg,
            )
            Spacer(Modifier.weight(1f))
            Box(
                modifier = Modifier
                    .size(34.dp)
                    .clip(CircleShape)
                    .background(if (filterOnline) t.accent.copy(alpha = 0.15f) else t.card)
                    .clickable { filterOnline = !filterOnline },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Outlined.FilterList,
                    contentDescription = null,
                    tint = if (filterOnline) t.accent else t.fg3,
                    modifier = Modifier.size(16.dp),
                )
            }
            Spacer(Modifier.width(8.dp))
            Box(
                modifier = Modifier
                    .size(34.dp)
                    .clip(CircleShape)
                    .background(t.card)
                    .clickable { /* Search */ },
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Outlined.Search, contentDescription = null, tint = t.fg3, modifier = Modifier.size(16.dp))
            }
        }

        // Stats summary
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            StatChip(
                label = tr("nodes.online"),
                value = agents.count { it.isOnline }.toString(),
                tone = "ok",
                modifier = Modifier.weight(1f),
            )
            StatChip(
                label = tr("nodes.offline"),
                value = agents.count { !it.isOnline }.toString(),
                tone = if (agents.any { !it.isOnline }) "warn" else null,
                modifier = Modifier.weight(1f),
            )
            StatChip(
                label = tr("nodes.total"),
                value = agents.size.toString(),
                tone = null,
                modifier = Modifier.weight(1f),
            )
        }

        // Agent list
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (filtered.isEmpty()) {
                item {
                    NanoCard(modifier = Modifier.padding(vertical = 12.dp)) {
                        Box(
                            modifier = Modifier.fillMaxWidth().padding(vertical = 22.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(tr("nodes.noResults"), fontSize = 13.sp, color = t.fg4)
                        }
                    }
                }
            } else {
                items(filtered) { agent ->
                    AgentCard(agent, metrics[agent.id], onClick = { onNavigateToDetail(agent) })
                }
            }
        }
    }
}

@Composable
private fun StatChip(label: String, value: String, tone: String?, modifier: Modifier = Modifier) {
    val t = nano
    val bg = when (tone) {
        "ok" -> t.ok.copy(alpha = 0.12f)
        "warn" -> t.warn.copy(alpha = 0.12f)
        "crit" -> t.crit.copy(alpha = 0.12f)
        else -> t.card2
    }
    val fg = when (tone) {
        "ok" -> t.ok
        "warn" -> t.warn
        "crit" -> t.crit
        else -> t.fg2
    }

    Column(
        modifier = modifier
            .clip(RoundedCornerShape(t.cardRadius))
            .background(bg)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(value, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = fg)
        Text(label, fontSize = 11.sp, color = t.fg4)
    }
}

@Composable
private fun AgentCard(
    agent: Agent,
    metrics: com.nanolink.app.data.model.AgentMetrics?,
    onClick: () -> Unit,
) {
    val t = nano
    val cpu = metrics?.cpuPercent ?: 0.0
    val memory = metrics?.memoryPercent ?: 0.0
    val disk = metrics?.disks?.maxOfOrNull { it.usagePercent } ?: 0.0

    NanoCard(modifier = Modifier.clickable(onClick = onClick)) {
        Column(modifier = Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            // Header row
            Row(verticalAlignment = Alignment.CenterVertically) {
                NanoStatusDot(color = if (agent.isOnline) t.ok else t.fg4, pulse = agent.isOnline)
                Spacer(Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(agent.hostname, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = t.fg)
                    Text(
                        "${agent.os} • ${agent.arch} • L${agent.permissionLevel}",
                        fontSize = 11.sp,
                        fontFamily = NanoMonoFamily,
                        color = t.fg4,
                    )
                }
                if (agent.isOnline) {
                    Icon(
                        Icons.Outlined.Computer,
                        contentDescription = null,
                        tint = t.accent.copy(alpha = 0.5f),
                        modifier = Modifier.size(20.dp),
                    )
                }
            }

            // Metrics row
            if (agent.isOnline && metrics != null) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    MetricPill("CPU", cpu, modifier = Modifier.weight(1f))
                    MetricPill("MEM", memory, modifier = Modifier.weight(1f))
                    MetricPill("DISK", disk, modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun MetricPill(label: String, value: Double, modifier: Modifier = Modifier) {
    val t = nano
    val tone = when {
        value > 85 -> t.crit
        value > 70 -> t.warn
        else -> t.fg3
    }

    Row(
        modifier = modifier
            .clip(RoundedCornerShape(8.dp))
            .background(t.bg.copy(alpha = 0.5f))
            .padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, fontSize = 10.sp, fontFamily = NanoMonoFamily, color = t.fg4)
        Text(
            "${value.roundToInt()}%",
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold,
            fontFamily = NanoMonoFamily,
            color = tone,
        )
    }
}
