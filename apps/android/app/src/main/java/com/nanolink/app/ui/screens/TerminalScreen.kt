package com.nanolink.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Send
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.nanolink.app.state.AppViewModel
import com.nanolink.app.ui.design.NanoEmptyState
import com.nanolink.app.ui.design.NanoMonoFamily
import com.nanolink.app.ui.design.nano
import com.nanolink.app.ui.tr

data class ShellLine(val kind: ShellLineKind, val text: String)
enum class ShellLineKind { SYS, INPUT, OUTPUT, ERROR }

@Composable
fun TerminalScreen(viewModel: AppViewModel, modifier: Modifier = Modifier) {
    val t = nano
    val agents by viewModel.agents.collectAsStateWithLifecycle()
    val activeServerId by viewModel.activeServerId.collectAsStateWithLifecycle()

    val onlineAgents = agents.filter { it.isOnline }

    if (activeServerId == null || onlineAgents.isEmpty()) {
        Box(modifier = modifier.fillMaxSize().padding(16.dp), contentAlignment = Alignment.Center) {
            NanoEmptyState(
                icon = Icons.Outlined.Terminal,
                title = tr("terminal.noAgents"),
                detail = tr("terminal.noAgentsDetail"),
            )
        }
        return
    }

    val selectedAgent = remember(onlineAgents) { onlineAgents.firstOrNull() }
    var lines by remember { mutableStateOf<List<ShellLine>>(emptyList()) }
    var input by remember { mutableStateOf("") }
    var status by remember { mutableStateOf("connecting") }

    val listState = rememberLazyListState()

    LaunchedEffect(selectedAgent) {
        if (selectedAgent != null) {
            lines = listOf(
                ShellLine(ShellLineKind.SYS, "→ Connecting to ${selectedAgent.hostname}..."),
                ShellLine(ShellLineKind.SYS, "✓ Console authenticated (level ${selectedAgent.permissionLevel})"),
            )
            status = "connected"
        }
    }

    LaunchedEffect(lines.size) {
        if (lines.isNotEmpty()) {
            listState.animateScrollToItem(lines.size - 1)
        }
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
                tr("terminal.title"),
                fontSize = if (t.isIOS) 32.sp else 28.sp,
                fontWeight = if (t.isIOS) FontWeight.Bold else FontWeight.SemiBold,
                letterSpacing = if (t.isIOS) (-0.6).sp else 0.sp,
                color = t.fg,
            )
        }

        // Agent selector (simplified)
        if (selectedAgent != null) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp)
                    .clip(RoundedCornerShape(t.cardRadius))
                    .background(t.card)
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(selectedAgent.hostname, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = t.fg)
                    Text(
                        "${selectedAgent.os} ${selectedAgent.arch}",
                        fontSize = 11.sp,
                        fontFamily = NanoMonoFamily,
                        color = t.fg4,
                    )
                }
                Text(
                    status,
                    fontSize = 11.sp,
                    fontFamily = NanoMonoFamily,
                    color = if (status == "connected") t.ok else t.fg4,
                )
            }
        }

        // Console output
        LazyColumn(
            state = listState,
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .clip(RoundedCornerShape(t.cardRadius))
                .background(t.bg.copy(alpha = 0.5f))
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            items(lines) { line ->
                val color = when (line.kind) {
                    ShellLineKind.SYS -> t.fg4
                    ShellLineKind.INPUT -> t.accent
                    ShellLineKind.OUTPUT -> t.fg2
                    ShellLineKind.ERROR -> t.crit
                }
                Text(
                    line.text,
                    fontSize = 13.sp,
                    fontFamily = NanoMonoFamily,
                    color = color,
                    lineHeight = 18.sp,
                )
            }
        }

        // Input bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp)
                .clip(RoundedCornerShape(t.cardRadius))
                .background(t.card)
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            BasicTextField(
                value = input,
                onValueChange = { input = it },
                modifier = Modifier.weight(1f),
                textStyle = androidx.compose.ui.text.TextStyle(
                    fontSize = 14.sp,
                    fontFamily = NanoMonoFamily,
                    color = t.fg,
                ),
                cursorBrush = SolidColor(t.accent),
                enabled = status == "connected",
                decorationBox = { innerTextField ->
                    Box {
                        if (input.isEmpty()) {
                            Text(
                                "Enter command...",
                                fontSize = 14.sp,
                                fontFamily = NanoMonoFamily,
                                color = t.fg4,
                            )
                        }
                        innerTextField()
                    }
                },
            )
            IconButton(
                onClick = {
                    if (input.isNotEmpty()) {
                        lines = lines + ShellLine(ShellLineKind.INPUT, "$ $input")
                        lines = lines + ShellLine(ShellLineKind.OUTPUT, "Command sent: $input")
                        input = ""
                    }
                },
                enabled = input.isNotEmpty() && status == "connected",
            ) {
                Icon(
                    Icons.Outlined.Send,
                    contentDescription = null,
                    tint = if (input.isNotEmpty()) t.accent else t.fg4,
                )
            }
        }
    }
}
