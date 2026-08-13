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
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.nanolink.app.data.model.AlertInstance
import com.nanolink.app.data.model.AuditEntry
import com.nanolink.app.state.AppViewModel
import com.nanolink.app.ui.design.NanoCard
import com.nanolink.app.ui.design.NanoEmptyState
import com.nanolink.app.ui.design.NanoListRow
import com.nanolink.app.ui.design.NanoMonoFamily
import com.nanolink.app.ui.design.NanoStatusDot
import com.nanolink.app.ui.design.nano
import com.nanolink.app.ui.tr
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun ActivityScreen(viewModel: AppViewModel, modifier: Modifier = Modifier) {
    val t = nano
    val alerts by viewModel.alerts.collectAsStateWithLifecycle()
    val activity by viewModel.activity.collectAsStateWithLifecycle()
    val activeServerId by viewModel.activeServerId.collectAsStateWithLifecycle()

    var selectedTab by remember { mutableIntStateOf(0) }

    val allAlerts = activeServerId?.let { alerts[it] }.orEmpty().sortedByDescending {
        runCatching { SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US).parse(it.since)?.time }.getOrNull() ?: 0L
    }
    val unackedAlerts = allAlerts.filter { !it.acked }
    val allActivity = activeServerId?.let { activity[it] }.orEmpty().sortedByDescending { it.atMillis }

    LaunchedEffect(activeServerId) {
        val serverId = activeServerId ?: return@LaunchedEffect
        viewModel.fetchServerAlerts(serverId)
        viewModel.fetchRecentActivity(serverId)
    }

    Column(modifier = modifier.fillMaxSize()) {
        // Header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 16.dp, end = 16.dp, top = if (t.isIOS) 32.dp else 4.dp, bottom = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                tr("activity.title"),
                fontSize = if (t.isIOS) 32.sp else 28.sp,
                fontWeight = if (t.isIOS) FontWeight.Bold else FontWeight.SemiBold,
                letterSpacing = if (t.isIOS) (-0.6).sp else 0.sp,
                color = t.fg,
            )
            Spacer(Modifier.weight(1f))
            if (unackedAlerts.isNotEmpty()) {
                Box(
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(t.crit.copy(alpha = 0.15f))
                        .padding(horizontal = 10.dp, vertical = 4.dp),
                ) {
                    Text(
                        unackedAlerts.size.toString(),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = t.crit,
                    )
                }
            }
        }

        // Tabs
        TabRow(
            selectedTabIndex = selectedTab,
            containerColor = t.bg,
            contentColor = t.accent,
            indicator = {},
            divider = {},
        ) {
            Tab(
                selected = selectedTab == 0,
                onClick = { selectedTab = 0 },
                text = {
                    Text(
                        tr("activity.alerts"),
                        fontSize = 15.sp,
                        fontWeight = if (selectedTab == 0) FontWeight.SemiBold else FontWeight.Normal,
                    )
                },
            )
            Tab(
                selected = selectedTab == 1,
                onClick = { selectedTab = 1 },
                text = {
                    Text(
                        tr("activity.audit"),
                        fontSize = 15.sp,
                        fontWeight = if (selectedTab == 1) FontWeight.SemiBold else FontWeight.Normal,
                    )
                },
            )
        }

        // Content
        when (selectedTab) {
            0 -> AlertsList(allAlerts, viewModel)
            1 -> AuditList(allActivity)
        }
    }
}

@Composable
private fun AlertsList(alerts: List<AlertInstance>, viewModel: AppViewModel) {
    val t = nano
    val scope = rememberCoroutineScope()

    if (alerts.isEmpty()) {
        Box(modifier = Modifier.fillMaxSize().padding(16.dp), contentAlignment = Alignment.Center) {
            NanoEmptyState(
                icon = Icons.Outlined.Notifications,
                title = tr("activity.noAlerts"),
                detail = tr("activity.noAlertsDetail"),
            )
        }
        return
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(alerts, key = { it.id }) { alert ->
            AlertCard(alert, onAcknowledge = {
                scope.launch { viewModel.acknowledgeAlert(alert.id) }
            })
        }
    }
}

@Composable
private fun AlertCard(alert: AlertInstance, onAcknowledge: () -> Unit) {
    val t = nano
    val icon = when (alert.level.uppercase()) {
        "CRITICAL" -> Icons.Outlined.ErrorOutline
        "WARNING" -> Icons.Outlined.Warning
        else -> Icons.Outlined.Info
    }
    val tone = when (alert.level.uppercase()) {
        "CRITICAL" -> t.crit
        "WARNING" -> t.warn
        else -> t.accent
    }

    NanoCard {
        Column(
            modifier = Modifier.fillMaxWidth().padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(icon, contentDescription = null, tint = tone, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(alert.title, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = t.fg)
                    Text(alert.agent, fontSize = 11.sp, fontFamily = NanoMonoFamily, color = t.fg4)
                }
                if (alert.acked) {
                    Icon(
                        Icons.Outlined.CheckCircle,
                        contentDescription = null,
                        tint = t.ok,
                        modifier = Modifier.size(16.dp),
                    )
                }
            }
            Text(alert.description, fontSize = 13.sp, color = t.fg3, lineHeight = 18.sp)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    alert.since,
                    fontSize = 10.sp,
                    fontFamily = NanoMonoFamily,
                    color = t.fg4,
                )
                if (!alert.acked) {
                    Spacer(Modifier.weight(1f))
                    Box(
                        modifier = Modifier
                            .clip(RoundedCornerShape(6.dp))
                            .background(t.accent.copy(alpha = 0.12f))
                            .clickable(onClick = onAcknowledge)
                            .padding(horizontal = 10.dp, vertical = 4.dp),
                    ) {
                        Text(
                            tr("activity.acknowledge"),
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Medium,
                            color = t.accent,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun AuditList(entries: List<AuditEntry>) {
    val t = nano

    if (entries.isEmpty()) {
        Box(modifier = Modifier.fillMaxSize().padding(16.dp), contentAlignment = Alignment.Center) {
            NanoEmptyState(
                icon = Icons.Outlined.Info,
                title = tr("activity.noAudit"),
                detail = tr("activity.noAuditDetail"),
            )
        }
        return
    }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(0.dp),
    ) {
        item { NanoCard { } }
        item {
            NanoCard {
                entries.forEachIndexed { index, entry ->
                    AuditRow(entry, divider = index < entries.size - 1)
                }
            }
        }
    }
}

@Composable
private fun AuditRow(entry: AuditEntry, divider: Boolean) {
    val t = nano
    val icon = when (entry.type.uppercase()) {
        "CREATE", "START" -> Icons.Outlined.Check
        "DELETE", "STOP" -> Icons.Outlined.Close
        else -> Icons.Outlined.Info
    }

    NanoListRow(divider = divider) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(icon, contentDescription = null, tint = t.fg3, modifier = Modifier.size(14.dp))
            Spacer(Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text("${entry.type} ${entry.target}", fontSize = 13.sp, color = t.fg2, maxLines = 1)
                Text(entry.agentHostname, fontSize = 11.sp, fontFamily = NanoMonoFamily, color = t.fg4)
                Text(
                    SimpleDateFormat("HH:mm:ss", Locale.US).format(Date(entry.atMillis)),
                    fontSize = 10.sp,
                    fontFamily = NanoMonoFamily,
                    color = t.fg4,
                )
            }
            if (!entry.ok) {
                Icon(Icons.Outlined.ErrorOutline, contentDescription = null, tint = t.crit, modifier = Modifier.size(14.dp))
            }
        }
    }
}
